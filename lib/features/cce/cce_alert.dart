/// Care Coordination Engine (CCE) — view model + derivation.
///
/// The CCE feature is a **presentation layer** over the existing on-device
/// referral SLA engine (`ReferralRepository` + `SlaEvaluator` +
/// `PriorityScorer`). It re-frames the same `referrals` rows as an
/// action-first "who is slipping between SK and facility" alert list.
///
/// The mapping from the 14-state [ReferralStatus] lifecycle + SLA bookkeeping
/// onto the 4-step care journey lives here and nowhere else. All user-facing
/// copy the derivation interpolates comes from [CceStrings]
/// (`core/constants/app_strings.dart`) — this file holds no string literals.
///
/// Wireframe: `apon_sushashthya_v13.html` → CCE NOTIFICATION DRAWER.
library;

import 'dart:convert';

import '../../core/constants/app_strings.dart';
import '../../core/db/follow_up_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/referral.dart';
import '../../core/models/sla.dart';

/// Severity band that drives card colour, sort order and whether the alert
/// counts toward the "N actions needed" badge.
enum CceSeverity {
  /// SLA window already breached and the referral is still open. Red.
  breached,

  /// Not yet breached but the window closes soon, or a critical case is
  /// waiting. Amber — SK action recommended.
  warning,

  /// Active and on schedule. Neutral — no action needed right now.
  onTrack,

  /// Closed (recovered / discharged / deceased / duplicate). Green — resolved.
  completed;

  /// Whether this severity should surface in the "actions needed" count and
  /// sort ahead of resolved / on-track work.
  bool get needsAction =>
      this == CceSeverity.breached || this == CceSeverity.warning;
}

/// Per-node state in the 4-step care journey strip.
enum CceStepState { done, missed, pending }

/// One node in the referral care journey (SK Visit → Referred → Facility →
/// Treatment).
class CceJourneyStep {
  const CceJourneyStep({
    required this.label,
    required this.sublabel,
    required this.state,
  });

  final String label;
  final String sublabel;
  final CceStepState state;
}

/// Lightweight assessment signal used to advance Facility / Treatment on
/// NCD CCE cards. [id] is the FHIR Encounter id (`assessments.id` /
/// history `encounterId`); [kind] is `serviceProvided`.
class CceAssessmentSignal {
  const CceAssessmentSignal({
    required this.id,
    this.kind,
    this.occurredAt,
  });

  final String id;
  final String? kind;

  /// Epoch ms of the visit (`assessments.occurred_at` / history `visitDate`).
  final int? occurredAt;
}

/// A single CCE alert — one open (or recently-closed) referral, enriched with
/// patient identity and reduced to the fields the drawer renders.
class CceAlert {
  const CceAlert({
    required this.referralId,
    required this.patientId,
    required this.patientName,
    required this.severity,
    required this.slaBadge,
    required this.referredMeta,
    required this.statusLine,
    required this.intelTags,
    required this.journey,
    required this.priorityScore,
    this.patientAge,
    this.patientGender,
    this.patientPhone,
    this.villageName,
    this.facilityName,
    this.latitude,
    this.longitude,
    this.landmark,
    this.followUpDate,
    this.followUpId,
    this.backendId,
    this.attempts = 0,
    this.remainingAttempts,
    this.programmeLabel,
    this.isWrongNumber = false,
  });

  final String referralId;
  final String patientId;
  final String patientName;
  final int? patientAge;
  final String? patientGender;
  final String? patientPhone;
  final String? villageName;

  /// Referral target facility name (e.g. "UHC Manikganj"), parsed from the
  /// referral payload when present.
  final String? facilityName;

  /// Patient household location — drives a precise "Locate" when present.
  final double? latitude;
  final double? longitude;
  final String? landmark;
  final CceSeverity severity;

  /// Whether a precise map pin is available (vs. a name-based search).
  bool get hasGeo => latitude != null && longitude != null;

  /// Right-aligned pill text, e.g. "SLA BREACHED +4d" / "SLA: 1d left" /
  /// "Completed".
  final String slaBadge;

  /// Sub-header, e.g. "Referred: 13 May · Severe pneumonia".
  final String referredMeta;

  /// Emphasised status sentence, e.g. "Not arrived · 7 days overdue · SLA was
  /// 3 days".
  final String statusLine;

  /// Short chips surfacing the "why", e.g. ["Not checked in", "Transport
  /// barrier?"].
  final List<String> intelTags;

  /// Four-step care journey for the timeline strip.
  final List<CceJourneyStep> journey;

  /// Priority score carried through for stable secondary sort.
  final int priorityScore;

  /// Local follow-up row id when this alert is backed by a fetch CallRegister.
  final String? followUpId;

  /// Server CallRegister id — required for call logging + sync.
  final int? backendId;

  final int attempts;
  final int? remainingAttempts;
  final String? programmeLabel;
  final bool isWrongNumber;

  bool get hasPhone {
    final p = patientPhone?.trim() ?? '';
    if (p.isEmpty || p == '0') return false;
    return !isWrongNumber;
  }

  /// Call is allowed only for open fetched follow-ups with a valid number.
  bool get canCall =>
      followUpId != null && backendId != null && hasPhone && !isWrongNumber;

  // NOTE: this parses [slaBadge], which is now localized. The `SLA:` / `left` /
  // `+` tokens must survive translation or this falls back to '!' / '+?'.
  // TODO(cce): derive the ring label from structured fields, not display text.
  /// Short label rendered inside the donut ring: "+4d" (breached), "4h"
  /// (warning with countdown), "!" (warning with no countdown), empty for
  /// on-track/completed (those use an icon instead of text).
  String get ringLabel {
    switch (severity) {
      case CceSeverity.breached:
        final m = RegExp(r'\+\S+').firstMatch(slaBadge);
        return m?.group(0) ?? '+?';
      case CceSeverity.warning:
        final m = RegExp(r'SLA:\s*(\S+)\s+left').firstMatch(slaBadge);
        return m?.group(1) ?? '!';
      case CceSeverity.onTrack:
      case CceSeverity.completed:
        return '';
    }
  }

  /// Formatted follow-up date string (e.g. "27 May") if a follow-up is
  /// scheduled after discharge. Null when not applicable or not yet populated.
  final String? followUpDate;

  /// Derive a [CceAlert] from a fetched REFERRED [FollowUpRow].
  ///
  /// For NCD follow-ups, [assessments] advances Facility / Treatment from
  /// post–NCD-visit history (`medicalreviewvisit` / `ncdmedicalreview`),
  /// anchored on the community NCD visit date (`encounterDate`, or the
  /// assessment whose id equals follow-up `encounterId`). Non-NCD programmes
  /// keep the call-attempt Facility heuristic.
  factory CceAlert.fromFollowUp(
    FollowUpRow fu, {
    Patient? patient,
    double? latitude,
    double? longitude,
    String? landmark,
    required DateTime now,
    int retryAttempts = 3,
    List<CceAssessmentSignal> assessments = const [],
  }) {
    final raw = _decodeMap(fu.rawJson);
    final programme = _programmeLabel(raw);
    final reason = _firstString(raw, const [
          'reason',
          'referredReasons',
          'referralReason',
        ]) ??
        programme ??
        CceStrings.referralReasonFallback;
    final facility = _firstString(raw, const [
      'referredSiteName',
      'facilityName',
      'referredTo',
      'referredSite',
    ]);
    final attempts = fu.attempts ?? 0;
    final remaining = (retryAttempts - attempts).clamp(1, retryAttempts);
    final encounterId = _firstString(raw, const ['encounterId']);
    final createdMs = _ncdVisitMs(
          encounterId: encounterId,
          encounterDateRaw: raw['encounterDate'],
          assessments: assessments,
        ) ??
        fu.updatedAt ??
        now.millisecondsSinceEpoch;
    final ageDays =
        now.difference(DateTime.fromMillisecondsSinceEpoch(createdMs)).inDays;

    final CceSeverity severity;
    if (fu.isCompleted || fu.isLost) {
      severity = CceSeverity.completed;
    } else if (remaining <= 1 || ageDays >= 7) {
      severity = CceSeverity.breached;
    } else if (remaining <= 2 || ageDays >= 3) {
      severity = CceSeverity.warning;
    } else {
      severity = CceSeverity.onTrack;
    }

    final date = _dateShort(createdMs);
    final phone = patient?.phone;
    final validPhone = phone != null &&
        phone.trim().isNotEmpty &&
        phone.trim() != '0' &&
        !fu.isLost;

    // Prefer identity resolved via members.fhir_id (patient.id); fall back to
    // follow-up patientId / memberId from the wire payload.
    final resolvedPatientId = patient?.id ??
        _firstString(raw, const ['memberId', 'householdMemberId']) ??
        fu.patientId;

    final progress = _followUpProgress(
      programme: programme,
      attempts: attempts,
      ncdVisitMs: createdMs,
      encounterId: encounterId,
      assessments: assessments,
    );

    return CceAlert(
      referralId: fu.id,
      followUpId: fu.id,
      backendId: fu.backendId,
      patientId: resolvedPatientId,
      patientName: patient?.name?.trim().isNotEmpty == true
          ? patient!.name!.trim()
          : CceStrings.unknownPatient,
      patientAge: patient?.age,
      patientGender: patient?.gender,
      patientPhone: validPhone ? phone : patient?.phone,
      villageName: patient?.villageName ??
          _firstString(raw, const ['villageName', 'village']),
      facilityName: facility,
      latitude: latitude,
      longitude: longitude,
      landmark: landmark,
      severity: severity,
      slaBadge: severity == CceSeverity.breached
          ? CceStrings.breachBadge('${ageDays}d')
          : (severity == CceSeverity.warning
              ? CceStrings.attentionBadge
              : (severity == CceSeverity.completed
                  ? CceStrings.completedBadge
                  : CceStrings.onTrackBadge)),
      referredMeta: CceStrings.referredMeta(date, facility, reason),
      statusLine: fu.isLost
          ? CceStrings.wrongNumberClosed
          : CceStrings.callAttemptsStatus(attempts, retryAttempts, remaining),
      intelTags: [
        if (programme != null) programme,
        if (progress.atFacility && !progress.treated) CceStrings.tagAtFacility,
        if (remaining <= 1) CceStrings.lastAttempt,
      ],
      journey: [
        CceJourneyStep(
          label: CceStrings.stepSkVisit,
          sublabel: date,
          state: CceStepState.done,
        ),
        CceJourneyStep(
          label: CceStrings.stepReferred,
          sublabel: programme ?? date,
          state: CceStepState.done,
        ),
        CceJourneyStep(
          label: CceStrings.stepFacility,
          sublabel: progress.atFacility
              ? (progress.treated
                  ? CceStrings.stepArrived
                  : (programme == 'NCD'
                      ? CceStrings.stepArrived
                      : CceStrings.followingUp))
              : CceStrings.stepPending,
          state:
              progress.atFacility ? CceStepState.done : CceStepState.pending,
        ),
        CceJourneyStep(
          label: progress.treated
              ? CceStrings.stepTreated
              : CceStrings.stepTreatment,
          sublabel: progress.treated
              ? CceStrings.stepInProgress
              : CceStrings.stepPending,
          state: progress.treated ? CceStepState.done : CceStepState.pending,
        ),
      ],
      priorityScore: (retryAttempts - remaining) * 10 + ageDays,
      followUpDate: null,
      attempts: attempts,
      remainingAttempts: remaining,
      programmeLabel: programme,
      isWrongNumber: fu.isLost,
    );
  }

  /// NCD visit anchor: prefer the assessment whose id equals follow-up
  /// `encounterId`, else `encounterDate` from the CallRegister wire.
  static int? _ncdVisitMs({
    required String? encounterId,
    required Object? encounterDateRaw,
    required List<CceAssessmentSignal> assessments,
  }) {
    if (encounterId != null) {
      for (final a in assessments) {
        if (a.id == encounterId && a.occurredAt != null) {
          return a.occurredAt;
        }
      }
    }
    return _parseDateMs(encounterDateRaw);
  }

  /// Facility / Treatment progress for a REFERRED follow-up card.
  ///
  /// NCD: `medicalreviewvisit` after NCD visit → Facility;
  /// `ncdmedicalreview` / `medicalReview` after NCD visit → Treatment
  /// (Treatment implies Facility). Non-NCD: Facility when call attempts > 0.
  static ({bool atFacility, bool treated}) _followUpProgress({
    required String? programme,
    required int attempts,
    required int ncdVisitMs,
    required String? encounterId,
    required List<CceAssessmentSignal> assessments,
  }) {
    if (programme != 'NCD') {
      return (atFacility: attempts > 0, treated: false);
    }

    var atFacility = false;
    var treated = false;
    for (final a in assessments) {
      final at = a.occurredAt;
      if (at == null) continue;
      // Exclude the community NCD encounter that created the referral.
      if (encounterId != null && a.id == encounterId) continue;
      // Must be on/after the NCD visit (same-day facility visits count).
      if (at < ncdVisitMs) continue;
      final kind = _compactKind(a.kind);
      if (_isFacilityKind(kind)) atFacility = true;
      if (_isTreatmentKind(kind)) treated = true;
    }
    if (treated) atFacility = true;
    return (atFacility: atFacility, treated: treated);
  }

  static String _compactKind(String? kind) =>
      (kind ?? '').toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');

  /// Facility check-in shell (`medicalreviewvisit`).
  static bool _isFacilityKind(String compact) =>
      compact == 'MEDICALREVIEWVISIT';

  /// Clinical NCD medical review (`ncdmedicalreview` / `medicalReview`).
  static bool _isTreatmentKind(String compact) =>
      compact == 'NCDMEDICALREVIEW' ||
      compact == 'MEDICALREVIEW' ||
      compact.contains('NCDMEDICALREVIEW');

  /// Derive a [CceAlert] from a referral row + (optional) cached patient.
  ///
  /// [now] is injected so the same referral yields deterministic output in
  /// tests. All timing text is computed here — the widgets are pure render.
  factory CceAlert.fromReferral(
    Referral r, {
    Patient? patient,
    double? latitude,
    double? longitude,
    String? landmark,
    required DateTime now,
  }) {
    final severity = _severity(r, now);
    final arrived = _arrived(r.state);
    final treated = _treated(r.state);
    final facility = _facilityName(r);

    return CceAlert(
      referralId: r.id,
      patientId: r.patientId,
      patientName: patient?.name?.trim().isNotEmpty == true
          ? patient!.name!.trim()
          : CceStrings.unknownPatient,
      patientAge: patient?.age,
      patientGender: patient?.gender,
      patientPhone: patient?.phone,
      villageName: patient?.villageName,
      facilityName: facility,
      latitude: latitude,
      longitude: longitude,
      landmark: landmark,
      severity: severity,
      slaBadge: _slaBadge(r, severity, now),
      referredMeta: _referredMeta(r, facility),
      statusLine: _statusLine(r, severity, arrived, treated, now),
      intelTags: _intelTags(r, severity, arrived, treated),
      journey: _journey(r, arrived, treated),
      priorityScore: r.priorityScore ?? 0,
      followUpDate: null,
    );
  }

  /// Best-effort facility name from the referral payload. The `Referral`
  /// model carries no dedicated facility field, so we read the original
  /// server/seed JSON, tolerant of the several keys the wire has used.
  static String? _facilityName(Referral r) {
    final raw = r.rawJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      for (final k in const [
        'facilityName',
        'referredTo',
        'referredSiteName',
        'referredSite',
      ]) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    } catch (_) {}
    return null;
  }

  // ── Derivation constants (pilot-grade; clinical lead to tune) ─────────────

  /// How close to the SLA deadline an open referral must be before it flips
  /// from on-track to amber "warning". 24h.
  static const int _warnWindowMs = 24 * 60 * 60 * 1000;

  // ── State helpers ─────────────────────────────────────────────────────────

  static bool _arrived(ReferralStatus s) =>
      s == ReferralStatus.arrived ||
      s == ReferralStatus.treatmentStarted ||
      s == ReferralStatus.closedRecovered ||
      s == ReferralStatus.closedDeceased;

  static bool _treated(ReferralStatus s) =>
      s == ReferralStatus.treatmentStarted ||
      s == ReferralStatus.closedRecovered ||
      s == ReferralStatus.closedDeceased;

  static CceSeverity _severity(Referral r, DateTime now) {
    if (r.state.isClosed) return CceSeverity.completed;
    if (r.breachedSince != null) return CceSeverity.breached;

    // Pick the deadline that matters for the current stage: treatment window
    // once arrived, arrival window before that.
    final due = _arrived(r.state) ? r.dueTreatmentAt : r.dueArrivalAt;
    if (due != null) {
      final remaining = due - now.millisecondsSinceEpoch;
      if (remaining <= _warnWindowMs) return CceSeverity.warning;
    }

    // A critical-band case that is still waiting always warns, even if the
    // clock has room — losing it is the expensive failure.
    if (SlaPriority.fromWireTag(r.priorityLevel) == SlaPriority.critical) {
      return CceSeverity.warning;
    }
    return CceSeverity.onTrack;
  }

  static String _slaBadge(Referral r, CceSeverity severity, DateTime now) {
    switch (severity) {
      case CceSeverity.breached:
        final over = r.dueArrivalAt != null
            ? now.millisecondsSinceEpoch - r.dueArrivalAt!
            : (r.breachedSince != null
                ? now.millisecondsSinceEpoch - r.breachedSince!
                : 0);
        return CceStrings.breachBadge(_humanizeShort(over));
      case CceSeverity.warning:
        final due = _arrived(r.state) ? r.dueTreatmentAt : r.dueArrivalAt;
        if (due != null) {
          final left = due - now.millisecondsSinceEpoch;
          if (left > 0) return CceStrings.leftBadge(_humanizeShort(left));
        }
        return CceStrings.attentionBadge;
      case CceSeverity.onTrack:
        return CceStrings.onTrackBadge;
      case CceSeverity.completed:
        return CceStrings.completedBadge;
    }
  }

  static String _referredMeta(Referral r, String? facility) {
    final date = _dateShort(r.createdAt);
    final reason = (r.diagnosisLabel != null && r.diagnosisLabel!.isNotEmpty)
        ? r.diagnosisLabel!
        : CceStrings.referralReasonFallback;
    return CceStrings.referredMeta(date, facility, reason);
  }

  static String _statusLine(
    Referral r,
    CceSeverity severity,
    bool arrived,
    bool treated,
    DateTime now,
  ) {
    switch (severity) {
      case CceSeverity.breached:
        if (!arrived) {
          final over = r.dueArrivalAt != null
              ? now.millisecondsSinceEpoch - r.dueArrivalAt!
              : now.millisecondsSinceEpoch - (r.breachedSince ?? r.createdAt);
          return CceStrings.notArrivedOverdue(
            _humanizeLong(over),
            _slaWindowText(r),
          );
        }
        // Arrived but treatment window breached.
        return CceStrings.treatmentOverdue(_slaWindowText(r));
      case CceSeverity.warning:
        if (arrived && !treated) {
          final waiting = now.millisecondsSinceEpoch -
              (r.updatedAt);
          return CceStrings.awaitingReview(_humanizeLong(waiting));
        }
        final due = arrived ? r.dueTreatmentAt : r.dueArrivalAt;
        if (due != null) {
          final left = due - now.millisecondsSinceEpoch;
          if (left > 0) return CceStrings.dueSoon(_humanizeLong(left));
        }
        return CceStrings.actionRecommended;
      case CceSeverity.onTrack:
        if (arrived && !treated) return CceStrings.atFacilityOnTrack;
        return CceStrings.onTrackLine;
      case CceSeverity.completed:
        final closed = r.closedAt ?? r.updatedAt;
        if (r.state == ReferralStatus.closedDeceased) {
          return CceStrings.closedDeceased(_dateShort(closed));
        }
        return CceStrings.dischargedLine(_dateShort(closed));
    }
  }

  static List<String> _intelTags(
    Referral r,
    CceSeverity severity,
    bool arrived,
    bool treated,
  ) {
    final tags = <String>[];
    if (severity == CceSeverity.completed) {
      tags.add(CceStrings.tagCareComplete);
    } else if (arrived && !treated) {
      tags.add(CceStrings.tagAtFacility);
    } else if (severity == CceSeverity.breached && !arrived) {
      tags.add(CceStrings.tagNotCheckedIn);
    }

    // Transport friction is the single most common "not arrived" cause in
    // pilot data — surface it as a prompt the SK can confirm.
    if (r.state == ReferralStatus.transportDeclined ||
        (severity == CceSeverity.breached &&
            r.state == ReferralStatus.inTransit)) {
      tags.add(CceStrings.tagTransportBarrier);
    }
    if (r.escalationLevel > 0) {
      tags.add(CceStrings.tagEscalated(r.escalationLevel));
    }
    return tags;
  }

  static List<CceJourneyStep> _journey(
    Referral r,
    bool arrived,
    bool treated,
  ) {
    final createdDate = _dateShort(r.createdAt);
    final notArrivedBreach = r.breachedSince != null && !arrived;

    return <CceJourneyStep>[
      CceJourneyStep(
        label: CceStrings.stepSkVisit,
        sublabel: createdDate,
        state: CceStepState.done,
      ),
      CceJourneyStep(
        label: CceStrings.stepReferred,
        sublabel: createdDate,
        state: CceStepState.done,
      ),
      CceJourneyStep(
        label: CceStrings.stepFacility,
        sublabel: arrived
            ? CceStrings.stepArrived
            : (notArrivedBreach
                ? CceStrings.stepNotArrived
                : CceStrings.stepPending),
        state: arrived
            ? CceStepState.done
            : (notArrivedBreach ? CceStepState.missed : CceStepState.pending),
      ),
      CceJourneyStep(
        label:
            treated ? CceStrings.stepTreated : CceStrings.stepTreatment,
        sublabel: r.state == ReferralStatus.closedRecovered
            ? CceStrings.stepDischarged
            : (treated ? CceStrings.stepInProgress : CceStrings.stepPending),
        state: treated ? CceStepState.done : CceStepState.pending,
      ),
    ];
  }

  // ── Formatting helpers ────────────────────────────────────────────────────

  /// SLA window between creation and the arrival deadline, humanised — the
  /// "SLA was 3 days" figure. Falls back to the tier's nominal window.
  static String _slaWindowText(Referral r) {
    if (r.dueArrivalAt != null) {
      return _humanizeLong(r.dueArrivalAt! - r.createdAt);
    }
    switch (r.slaTier) {
      case SlaTier.emergency:
        return CceStrings.slaEmergencyWindow;
      case SlaTier.urgent:
        return CceStrings.slaUrgentWindow;
      case SlaTier.routine:
        return CceStrings.slaRoutineWindow;
    }
  }

  /// Compact duration for badges: "4d", "6h", "45m". Always non-negative.
  static String _humanizeShort(int ms) {
    final v = ms.abs();
    final days = v ~/ (24 * 60 * 60 * 1000);
    if (days >= 1) return '${days}d';
    final hours = v ~/ (60 * 60 * 1000);
    if (hours >= 1) return '${hours}h';
    final mins = v ~/ (60 * 1000);
    return '${mins}m';
  }

  /// Sentence-friendly duration: "7 days", "6 hours", "45 minutes".
  static String _humanizeLong(int ms) {
    final v = ms.abs();
    final days = v ~/ (24 * 60 * 60 * 1000);
    if (days >= 1) return '$days day${days == 1 ? '' : 's'}';
    final hours = v ~/ (60 * 60 * 1000);
    if (hours >= 1) return '$hours hour${hours == 1 ? '' : 's'}';
    final mins = v ~/ (60 * 1000);
    return '$mins minute${mins == 1 ? '' : 's'}';
  }

  static String _dateShort(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  static Map<String, dynamic> _decodeMap(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return const {};
  }

  static String? _firstString(Map<String, dynamic> raw, List<String> keys) {
    for (final k in keys) {
      final v = raw[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static int? _parseDateMs(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final asInt = int.tryParse(s);
    if (asInt != null) {
      return asInt < 100000000000 ? asInt * 1000 : asInt;
    }
    return DateTime.tryParse(s)?.millisecondsSinceEpoch;
  }

  /// Normalise wire encounterName / encounterType into a short CCE label.
  static String? _programmeLabel(Map<String, dynamic> raw) {
    final name = (_firstString(raw, const ['encounterName', 'encounterType']) ??
            '')
        .toLowerCase()
        .replaceAll(RegExp(r'[\s-]'), '_');
    if (name.isEmpty) return null;
    if (name == 'anc' || name.contains('anc')) return 'ANC';
    if (name.contains('pnc')) return 'PNC';
    if (name == 'epi' || name.contains('immunis') || name.contains('immuniz')) {
      return 'EPI';
    }
    if (name == 'ncd' || name.contains('ncd')) return 'NCD';
    return null;
  }
}
