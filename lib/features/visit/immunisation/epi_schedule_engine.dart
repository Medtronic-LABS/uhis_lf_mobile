import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/db/immunisation_dao.dart';
import '../../../core/debug/console_log.dart';

/// Mirrors assets/forms/field_library.json's "childReferralFacilityType"
/// optionsList (id + English label only — the immunisation screen has no
/// Bangla localisation path yet). Single source of truth — the Refer flow's
/// dropdown and the history-pull facility-id lookup both use this list.
class FacilityOption {
  const FacilityOption(this.id, this.label);
  final String id;
  final String label;
}

const List<FacilityOption> referralFacilityOptions = [
  FacilityOption('medicalCollegeHospital', 'Medical College Hospital'),
  FacilityOption('governmentHospital', 'Government Hospital'),
  FacilityOption('upazilaHealthComplex', 'Upazila Health Complex'),
  FacilityOption('privateHospital', 'Private Hospital/Clinic'),
  FacilityOption('hwc', 'Health & Family Welfare Center'),
  FacilityOption('communityClinic', 'Community Clinic'),
];

/// One vaccine's outcome recovered from assessment history (local cache or
/// a fresh network fetch) — lower priority than a same-session
/// [ImmunisationRow], used to fill gaps when the backend schedule response
/// or a fresh install hasn't caught up with an outcome recorded elsewhere.
class HistoryOutcome {
  const HistoryOutcome({
    required this.vaccineName,
    this.givenAtMs,
    this.status,
    this.reason,
    this.facility,
  });

  final String vaccineName;
  final int? givenAtMs;

  /// 'Vaccinated' | 'Missed'.
  final String? status;
  final String? reason;
  final String? facility;
}

/// Vaccine status within a milestone group.
enum VaccineStatus {
  completed,
  dueNow,
  missed,
  upcoming,
  notYetDue,
}

/// Single vaccine entry in the timeline.
class VaccineEntry {
  const VaccineEntry({
    required this.code,
    required this.wireName,
    required this.display,
    required this.category,
    required this.description,
    required this.route,
    required this.cardGroup,
    required this.scheduledDate,
    this.givenDate,
    required this.status,
    this.missedReason,
    this.referralFacility,
  });

  /// Stable internal id and local DB key. Row ids embed it
  /// (`'<patientId>_<code>'`) and recorded history is matched on it, so a
  /// change here orphans every dose already recorded — it must never change.
  final String code;

  /// Frozen string sent to the backend as `vaccineName`. Seeded with the value
  /// that used to be sent (the old [display]) so payloads stay byte-identical
  /// and already-synced records keep their meaning. Never derived from
  /// [display], which is localised.
  final String wireName;

  /// UI-only label. Localised via `Epi.vaccine.<code>`; never persisted and
  /// never transmitted.
  final String display;
  final String category;
  final String description;
  final String route;
  final int cardGroup;
  final DateTime scheduledDate;
  final DateTime? givenDate;
  final VaccineStatus status;
  final String? missedReason;

  /// Facility label captured when [status] is [VaccineStatus.missed] via
  /// the Refer flow — present alongside [missedReason] whenever a dose was
  /// referred rather than just recorded missed.
  final String? referralFacility;

  bool get isOverdue =>
      (status == VaccineStatus.dueNow) &&
      DateTime.now().isAfter(scheduledDate);
}

/// A milestone group (e.g. "6 Weeks") with its vaccines.
class VaccineMilestone {
  const VaccineMilestone({
    required this.label,
    this.milestoneKey = '',
    required this.scheduledDate,
    required this.vaccines,
    required this.offsetType,
    required this.offsetValue,
    this.actionEnabled = true,
  });

  final String label;

  /// Stable key for this milestone, used for the `Epi.milestone.<key>`
  /// translation lookup. Separate from [label], which is localisable copy.
  final String milestoneKey;
  final DateTime scheduledDate;
  final List<VaccineEntry> vaccines;

  /// Offset type from the EPI schedule — 'day' | 'week' | 'month'.
  /// Matches the Android VaccinationDetail.type field (uppercased on send).
  final String offsetType;

  /// Offset value (e.g. 6 for "6 Weeks", 9 for "9 Months", 0 for "At Birth").
  final int offsetValue;

  /// Whether this milestone's "Update Status" action is currently
  /// clickable. Computed by [EpiScheduleEngine.applySequencing] — the
  /// button itself always renders when [hasDueNow] or [hasMissed] is true;
  /// this only controls whether it's enabled or shown-but-disabled.
  final bool actionEnabled;

  VaccineMilestone copyWith({bool? actionEnabled}) => VaccineMilestone(
        label: label,
        milestoneKey: milestoneKey,
        scheduledDate: scheduledDate,
        vaccines: vaccines,
        offsetType: offsetType,
        offsetValue: offsetValue,
        actionEnabled: actionEnabled ?? this.actionEnabled,
      );

  bool get allCompleted =>
      vaccines.every((v) => v.status == VaccineStatus.completed);

  bool get hasDueNow =>
      vaccines.any((v) => v.status == VaccineStatus.dueNow);

  bool get hasUpcoming =>
      vaccines.any((v) => v.status == VaccineStatus.upcoming);

  bool get hasMissed =>
      vaccines.any((v) => v.status == VaccineStatus.missed);

  int get overdueCount =>
      vaccines.where((v) => v.isOverdue).length;

  int get dueNowCount =>
      vaccines.where((v) => v.status == VaccineStatus.dueNow).length;

  /// Vaccines grouped by [VaccineEntry.cardGroup] for the update sheet.
  List<List<VaccineEntry>> get vaccineCards {
    final groups = <int, List<VaccineEntry>>{};
    for (final v in vaccines) {
      (groups[v.cardGroup] ??= []).add(v);
    }
    return groups.values.toList();
  }
}

/// Pure-Dart engine — merges EPI schedule asset with synced DB rows.
class EpiScheduleEngine {
  const EpiScheduleEngine._();

  static Future<List<VaccineMilestone>> build({
    required DateTime dob,
    required List<ImmunisationRow> rows,
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now();

    final scheduleJson = await rootBundle
        .loadString('assets/forms/epi_schedule.json');
    final schedule =
        (jsonDecode(scheduleJson) as List).cast<Map<String, dynamic>>();

    // Resolve every recorded row onto a schedule `code` before matching. Rows
    // reach us in three vocabularies: the local code (offline writes), the
    // frozen wireName (what we send), and the server's own spelling
    // (e.g. 'Polio-(OPV 2)' for OPV2) — historically these silently failed to
    // match, so previously-given doses reappeared as due.
    final codeByAlias = buildAliasIndex(schedule);

    final givenByCode = <String, DateTime>{};
    final statusByCode = <String, String>{};
    final missedReasonByCode = <String, String>{};
    final referralFacilityByCode = <String, String>{};
    for (final r in rows) {
      if (r.vaccineCode == null) continue;
      final code = resolveCode(r.vaccineCode!, codeByAlias);
      if (code == null) continue;
      if (r.givenAt != null) {
        givenByCode[code] = DateTime.fromMillisecondsSinceEpoch(r.givenAt!);
      }
      if (r.status != null && r.status!.isNotEmpty) {
        statusByCode[code] = r.status!;
      }
      if (r.missedReason != null && r.missedReason!.isNotEmpty) {
        missedReasonByCode[code] = r.missedReason!;
      }
      if (r.referralFacility != null && r.referralFacility!.isNotEmpty) {
        referralFacilityByCode[code] = r.referralFacility!;
      }
    }

    final milestones = <VaccineMilestone>[];

    // Each vaccine's status is computed strictly from its own scheduled
    // date / recorded outcome, independent of every other milestone --
    // there is no cross-milestone "prior must be complete first" gate.
    // Two milestones that are both overdue and unrecorded (e.g. "At Birth"
    // and "6 Weeks") therefore both resolve to dueNow and are both
    // independently actionable, instead of only the earliest one.
    for (final group in schedule) {
      final scheduledDate = _scheduledDate(dob, group);
      // Per-milestone dose-closure window, in weeks. Previously a hardcoded
      // literal 28 days duplicated here and in the timeline screen.
      final upcomingWindowDays =
          ((group['doseClosureWeeks'] as num?)?.toInt() ?? 4) * 7;

      final vaccines = (group['vaccines'] as List)
          .cast<Map<String, dynamic>>()
          .map((v) {
        final code = v['code'] as String;
        final givenDate = givenByCode[code];
        final recordedStatus = statusByCode[code];

        final VaccineStatus status;
        if (givenDate != null) {
          status = VaccineStatus.completed;
        } else if (recordedStatus == 'Missed') {
          status = VaccineStatus.missed;
        } else {
          status = statusFor(
            scheduledDate: scheduledDate,
            now: now,
            upcomingWindowDays: upcomingWindowDays,
          );
        }

        return VaccineEntry(
          code: code,
          wireName: v['wireName'] as String? ?? v['display'] as String,
          display: v['display'] as String,
          category: v['category'] as String,
          description: v['description'] as String? ?? '',
          route: v['route'] as String? ?? '',
          cardGroup: (v['cardGroup'] as num?)?.toInt() ?? 1,
          scheduledDate: scheduledDate,
          givenDate: givenDate,
          status: status,
          missedReason: missedReasonByCode[code],
          referralFacility: referralFacilityByCode[code],
        );
      }).toList();

      milestones.add(VaccineMilestone(
        label: group['milestone'] as String,
        milestoneKey: group['milestoneKey'] as String? ?? '',
        scheduledDate: scheduledDate,
        vaccines: vaccines,
        offsetType: group['offsetType'] as String,
        offsetValue: (group['offsetValue'] as num).toInt(),
      ));
    }

    return milestones;
  }

  /// Builds `alias → code` from a decoded schedule. Every vaccine contributes
  /// its `code`, its `wireName`, and each entry of `wireAliases`. Keys are
  /// lower-cased and whitespace-collapsed so trivial server formatting
  /// differences still match.
  ///
  /// Deliberately additive: an alias maps to exactly one code, and an unknown
  /// spelling resolves to null rather than to a wrong vaccine.
  static Map<String, String> buildAliasIndex(
      List<Map<String, dynamic>> schedule) {
    final index = <String, String>{};
    for (final group in schedule) {
      for (final v in (group['vaccines'] as List).cast<Map<String, dynamic>>()) {
        final code = v['code'] as String;
        void add(String? alias) {
          if (alias == null || alias.trim().isEmpty) return;
          index[_normalizeAlias(alias)] = code;
        }

        add(code);
        add(v['wireName'] as String?);
        for (final a in (v['wireAliases'] as List?) ?? const []) {
          add(a as String?);
        }
      }
    }
    return index;
  }

  /// Maps a recorded vaccine identifier — local code, frozen wire name, or a
  /// server spelling — onto a schedule `code`. Returns null when nothing
  /// matches, and logs it so unseen server vocabulary surfaces from real
  /// traffic instead of being guessed at up front.
  static String? resolveCode(String raw, Map<String, String> codeByAlias) {
    final hit = codeByAlias[_normalizeAlias(raw)];
    if (hit == null) {
      ConsoleLog.warn(
          '[EpiSchedule] unmatched vaccine identifier "$raw" — no schedule '
          'entry claims it; add it to that vaccine\'s wireAliases');
    }
    return hit;
  }

  static String _normalizeAlias(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Single home for the due/upcoming/not-yet-due decision. Previously
  /// duplicated between this engine and the timeline screen's backend path.
  static VaccineStatus statusFor({
    required DateTime scheduledDate,
    required DateTime now,
    required int upcomingWindowDays,
  }) {
    final daysDiff = scheduledDate.difference(now).inDays;
    if (daysDiff <= 0) return VaccineStatus.dueNow;
    if (daysDiff <= upcomingWindowDays) return VaccineStatus.upcoming;
    return VaccineStatus.notYetDue;
  }

  /// Gates each milestone's "Update Status" action to sequential order,
  /// independent of how the milestone list was built (offline [build] or
  /// the backend-dto path in immunisation_timeline_screen.dart) — call this
  /// once, right before rendering, on whichever list was produced.
  ///
  /// Walks milestones in chronological order tracking a single [unlocked]
  /// flag: a referred (missed) milestone is always actionable and never
  /// blocks what follows (reaching "referred" already resolves that step);
  /// the *first* unresolved due-now milestone is enabled and immediately
  /// blocks every due-now milestone after it, until it resolves. Completed/
  /// upcoming/not-yet-due milestones show no button either way and don't
  /// affect the flag. This self-heals even with out-of-order historical
  /// data rather than assuming strict linear progress.
  static List<VaccineMilestone> applySequencing(
      List<VaccineMilestone> milestones) {
    var unlocked = true;
    final out = <VaccineMilestone>[];
    for (final m in milestones) {
      if (m.hasMissed) {
        out.add(m.copyWith(actionEnabled: true));
      } else if (m.hasDueNow) {
        out.add(m.copyWith(actionEnabled: unlocked));
        unlocked = false;
      } else {
        out.add(m);
      }
    }
    return out;
  }

  /// Recovers [HistoryOutcome]s from a list of assessment-history raw JSON
  /// blobs (newest-first) — first occurrence per vaccine name wins, i.e. the
  /// latest known outcome. Best-effort: entries this can't parse are
  /// skipped, never thrown — this is a read-side enrichment, not a hard
  /// requirement.
  static List<HistoryOutcome> outcomesFromRawJsonList(
      List<Map<String, dynamic>> rawJsons) {
    final seen = <String>{};
    final out = <HistoryOutcome>[];
    for (final raw in rawJsons) {
      final vaccinations = _extractVaccinations(raw);
      if (vaccinations == null) continue;
      final facility = _extractReferralFacilityLabel(raw);
      for (final v in vaccinations) {
        if (v is! Map) continue;
        final name = v['vaccineName'] as String?;
        if (name == null || name.isEmpty || !seen.add(name)) continue;
        final status = v['status'] as String?;
        final vaccinatedDate = v['vaccinatedDate'] as String?;
        final givenDate =
            vaccinatedDate != null ? DateTime.tryParse(vaccinatedDate) : null;
        out.add(HistoryOutcome(
          vaccineName: name,
          givenAtMs: givenDate?.millisecondsSinceEpoch,
          status: status,
          reason: v['reason'] as String?,
          facility: status == 'Missed' ? facility : null,
        ));
      }
    }
    return out;
  }

  /// Defensively checks the plausible shapes a `CHILD_IMMUNIZATION`
  /// assessment-history row's raw JSON might echo the write-side
  /// `{'vaccinations': [...]}` payload back in — unverified against a real
  /// backend response as of writing (see plan doc); returns null (skip,
  /// don't crash) if none match.
  static List<dynamic>? _extractVaccinations(Map<String, dynamic> raw) {
    // Confirmed against a real member-assessment-history response: the
    // backend echoes a CHILD_IMMUNIZATION visit's doses back as a
    // top-level `immunization` list — NOT nested under `observations` or
    // `assessmentDetails.childImmunization` (those wrapper keys only exist
    // on the write-side offline-sync/create payload, not on a read).
    final immunization = raw['immunization'];
    if (immunization is List) return immunization;

    // Kept as harmless fallbacks in case a different read surface ever
    // echoes the write shape verbatim — unconfirmed, but zero-cost.
    final observations = raw['observations'];
    if (observations is Map && observations['vaccinations'] is List) {
      return observations['vaccinations'] as List;
    }
    final assessmentDetails = raw['assessmentDetails'];
    if (assessmentDetails is Map) {
      final childImmunization = assessmentDetails['childImmunization'];
      if (childImmunization is Map &&
          childImmunization['vaccinations'] is List) {
        return childImmunization['vaccinations'] as List;
      }
    }
    final childImmunization = raw['childImmunization'];
    if (childImmunization is Map &&
        childImmunization['vaccinations'] is List) {
      return childImmunization['vaccinations'] as List;
    }
    return null;
  }

  /// Recovers the referral facility label recorded at the assessment level.
  /// Written via `otherDetails: {'referralFacilityType': id}` /
  /// `referredReasons: [label]` (see the Update Status sheet's save flow),
  /// but confirmed against a real history response to come back as
  /// top-level `referralFacilityType` (an id) and `referralReason` (a
  /// single already-resolved label string) — not nested under a `summary`
  /// key and not a `referredReasons` list, which only exist on the write
  /// side.
  static String? _extractReferralFacilityLabel(Map<String, dynamic> raw) {
    final facilityId = raw['referralFacilityType'] as String?;
    if (facilityId != null) {
      for (final o in referralFacilityOptions) {
        if (o.id == facilityId) return o.label;
      }
    }
    final referralReason = raw['referralReason'] as String?;
    if (referralReason != null && referralReason.isNotEmpty) {
      return referralReason;
    }

    // Harmless fallbacks for the write-side shape, in case it's ever
    // echoed back verbatim on some other read surface.
    final summary = raw['summary'];
    final summaryFacilityId =
        summary is Map ? summary['referralFacilityType'] as String? : null;
    if (summaryFacilityId != null) {
      for (final o in referralFacilityOptions) {
        if (o.id == summaryFacilityId) return o.label;
      }
    }
    final reasons = raw['referredReasons'];
    if (reasons is List && reasons.isNotEmpty) {
      return reasons.first?.toString();
    }
    return null;
  }

  static Future<List<String>> overdueCodesFor({
    required DateTime dob,
    required List<ImmunisationRow> rows,
    DateTime? today,
  }) async {
    final milestones = await build(dob: dob, rows: rows, today: today);
    return milestones
        .expand((m) => m.vaccines)
        .where((v) => v.isOverdue || v.status == VaccineStatus.dueNow)
        .map((v) => v.code)
        .toList();
  }

  static DateTime _scheduledDate(DateTime dob, Map<String, dynamic> group) {
    final type = group['offsetType'] as String;
    final value = (group['offsetValue'] as num).toInt();
    switch (type) {
      case 'day':
        return dob.add(Duration(days: value));
      case 'week':
        return dob.add(Duration(days: value * 7));
      case 'month':
        return DateTime(dob.year, dob.month + value, dob.day);
    }
    return dob;
  }
}
