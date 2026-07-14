import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/db/assessment_dao.dart';
import '../../core/db/follow_up_dao.dart';
import '../../core/db/immunisation_dao.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/db/sync_meta_dao.dart';
import '../../core/debug/console_log.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/patient.dart';
import '../../core/models/programme.dart';
import '../../core/models/risk.dart';
import '../../core/models/worklist_entry.dart';
import '../../core/mission/programme_reason.dart' as programme_reason;
import '../../core/risk/risk_scoring_service.dart';

/// View-model layer above the worklist DAOs. UI consumes [load] /
/// [watchChanges] only — never touches DAOs or the risk engine directly.
class WorklistRepository {
  WorklistRepository({
    required PatientDao patients,
    required PatientProgrammesDao programmes,
    required FollowUpDao followUps,
    required ImmunisationDao immunisations,
    required SyncMetaDao syncMeta,
    required RiskScoringService risk,
    required LocalAssessmentDao localAssessments,
    required AssessmentDao assessments,
  })  : _patients = patients,
        _programmes = programmes,
        _followUps = followUps,
        _immunisations = immunisations,
        _syncMeta = syncMeta,
        _risk = risk,
        _localAssessments = localAssessments,
        _assessments = assessments;

  final PatientDao _patients;
  final PatientProgrammesDao _programmes;
  final FollowUpDao _followUps;
  final ImmunisationDao _immunisations;
  final SyncMetaDao _syncMeta;
  final RiskScoringService _risk;
  final LocalAssessmentDao _localAssessments;
  final AssessmentDao _assessments;

  /// Programme.wireTag-family kinds counted as completed ANC / PNC visits
  /// for the visit-count-aware dashboard label (spec v13) — shared with
  /// HouseholdListScreen via `programme_reason.dart` so both surfaces count
  /// visits identically.
  static const _ancKinds = programme_reason.ancVisitKinds;
  static const _pncKinds = programme_reason.pncVisitKinds;

  final _changes = ValueNotifier<int>(0);

  /// Fired after every successful recompute or sync — UI listens to refresh.
  Listenable get changes => _changes;

  Future<List<WorklistEntry>> load({
    Set<Programme> filter = const <Programme>{},
    int limit = 500,
    String? selectedVillageId,
  }) async {
    final rows = await _patients.queryWorklist(
      programmeFilter: filter,
      limit: limit,
    );
    if (rows.isEmpty) return const <WorklistEntry>[];
    final ids = rows
        .map((r) => r['id'] as String?)
        .whereType<String>()
        .toList(growable: false);
    final progMap = await _programmes.programmesForMany(ids);
    final ancCounts = await _assessments.visitCountsByPatients(ids, _ancKinds);
    final pncCounts = await _assessments.visitCountsByPatients(ids, _pncKinds);
    final out = <WorklistEntry>[];
    for (final r in rows) {
      final p = Patient.fromDb(r);
      out.add(_toEntry(
        p,
        progMap[p.id] ?? const <Programme>{},
        ancVisitCount: ancCounts[p.id] ?? 0,
        pncVisitCount: pncCounts[p.id] ?? 0,
      ));
    }
    _applySpecSort(out, selectedVillageId: selectedVillageId);
    return out;
  }

  WorklistEntry _toEntry(
    Patient p,
    Set<Programme> programmes, {
    int ancVisitCount = 0,
    int pncVisitCount = 0,
  }) {
    final age = p.age ?? _ageFromDob(p.dob);
    return WorklistEntry(
      patientId: p.id,
      displayName: p.name ?? '(Unnamed patient)',
      age: age,
      gender: p.gender,
      phoneNumber: p.phone,
      nid: p.nationalId,
      householdNo: p.householdId,
      householdName: null, // Could be populated from household cache
      villageId: p.villageId,
      villageName: p.villageName,
      programmes: programmes,
      band: p.riskBand ?? Band.band4,
      modifier: p.riskModifier ?? Modifier.none,
      reasons: p.riskReasons,
      nextDueAt: p.nextDueAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(p.nextDueAt!),
      lastVisitAt: p.lastVisitAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(p.lastVisitAt!),
      ancVisitCount: ancVisitCount,
      pncVisitCount: pncVisitCount,
    );
  }

  /// Apply sort order — date urgency first, then clinical severity (spec §2.8):
  ///   1. Date tier: Overdue → Today → This week → Upcoming
  ///   2. Band: 1 → 2 → 3 → 4
  ///   3. Modifier: a → b → none
  ///   4. Pregnant > non-pregnant (spec §2.8 step 3)
  ///   5. Modifier b: longer overdue ranks higher (spec §2.8 step 4)
  ///   6. Village match (when SK has selected a village)
  ///   7. Display name (stable tiebreaker)
  static void _applySpecSort(
    List<WorklistEntry> entries, {
    String? selectedVillageId,
  }) {
    final now = DateTime.now();

    int tierRank(WorklistEntry e) {
      final due = e.nextDueAt;
      if (due == null) return DashboardTier.upcoming.rank;
      return DashboardTier.fromDaysToDue(due.difference(now).inDays).rank;
    }

    String tierLabel(WorklistEntry e) {
      final due = e.nextDueAt;
      if (due == null) return 'upcoming';
      return DashboardTier.fromDaysToDue(due.difference(now).inDays).name;
    }

    int bandRank(Band b) => switch (b) {
          Band.band1 => 1,
          Band.band2 => 2,
          Band.band3 => 3,
          Band.band4 => 4,
        };
    int modRank(Modifier m) => switch (m) {
          Modifier.a => 0,
          Modifier.b => 1,
          Modifier.none => 2,
        };
    int overdueDays(WorklistEntry e) {
      final due = e.nextDueAt;
      if (due == null) return 0;
      return now.difference(due).inDays.clamp(0, 999);
    }

    entries.sort((a, b) {
      final byTier = tierRank(a).compareTo(tierRank(b));
      if (byTier != 0) return byTier;
      final byBand = bandRank(a.band).compareTo(bandRank(b.band));
      if (byBand != 0) return byBand;
      final byMod = modRank(a.modifier).compareTo(modRank(b.modifier));
      if (byMod != 0) return byMod;
      final byPreg = (a.isPregnant ? 0 : 1).compareTo(b.isPregnant ? 0 : 1);
      if (byPreg != 0) return byPreg;
      if (a.modifier == Modifier.b) {
        final byOverdue = overdueDays(b).compareTo(overdueDays(a));
        if (byOverdue != 0) return byOverdue;
      }
      if (selectedVillageId != null && selectedVillageId.isNotEmpty) {
        final byVillage = (a.villageId == selectedVillageId ? 0 : 1)
            .compareTo(b.villageId == selectedVillageId ? 0 : 1);
        if (byVillage != 0) return byVillage;
      }
      return a.displayName.compareTo(b.displayName);
    });

    assert(() {
      ConsoleLog.step('[Worklist sort] ${entries.length} patients:');
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        final progs = e.programmes.map((p) => p.name).join(',');
        final modTag = e.modifier == Modifier.none ? '' : e.modifier.wireTag;
        final overdue = overdueDays(e);
        final tier = tierLabel(e);
        ConsoleLog.step(
          '  ${i + 1}. [${e.band.wireTag}$modTag] ${e.displayName}'
          ' | prog: $progs | tier: $tier'
          '${overdue > 0 ? " | overdue: ${overdue}d" : ""}',
        );
      }
      return true;
    }());
  }

  /// Iterate cached patients, derive [PatientFacts] from joined follow-ups +
  /// immunisations, run the risk engine, persist results. Cheap enough to run
  /// after every cold/warm sync (1k patients ≈ <1s on a mid-range Android).
  Future<int> recomputeAllAfterSync() async {
    final patients = await _patients.allForVillages(const <String>[]);
    if (patients.isEmpty) return 0;
    final ids = patients.map((p) => p.id).toList(growable: false);
    final progMap = await _programmes.programmesForMany(ids);
    final followMap = await _followUps.forMany(ids);
    final immMap = await _immunisations.forMany(ids);
    final vitalsMap = await _localAssessments.latestClinicalVitalsForMany(ids);
    final now = DateTime.now();
    for (final p in patients) {
      final facts = _factsFor(
        p,
        progMap[p.id] ?? const <Programme>{},
        followMap[p.id] ?? const <FollowUpRow>[],
        immMap[p.id] ?? const <ImmunisationRow>[],
        vitalsMap[p.id],
        now,
      );
      final assessment = _risk.score(facts);
      final nextDue = _earliestDueMillis(
        followMap[p.id] ?? const <FollowUpRow>[],
        immMap[p.id] ?? const <ImmunisationRow>[],
        now,
      );
      final lastVisit = _lastCompletedMillis(
        followMap[p.id] ?? const <FollowUpRow>[],
      );
      await _patients.updateRisk(
        patientId: p.id,
        sortRank: assessment.sortRank,
        bandWireTag: assessment.band.wireTag,
        modifierWireTag: assessment.modifier.wireTag,
        reasonsJson: jsonEncode(assessment.reasons),
        nextDueAt: nextDue,
        lastVisitAt: lastVisit,
        missedVisitCount: facts.missedVisitsLast90d,
        redFlag: facts.redFlag,
      );
    }
    await _syncMeta.stampWarm('worklist', DateTime.now());
    _changes.value++;
    return patients.length;
  }

  PatientFacts _factsFor(
    Patient p,
    Set<Programme> programmes,
    List<FollowUpRow> follows,
    List<ImmunisationRow> imms,
    ClinicalVitals? vitals,
    DateTime now,
  ) {
    final cutoff = now.subtract(const Duration(days: 90)).millisecondsSinceEpoch;
    int missed = 0;
    bool lost = false;
    for (final f in follows) {
      if (f.isLost) lost = true;
      final due = f.dueAt;
      if (due == null) continue;
      if (due < now.millisecondsSinceEpoch && due >= cutoff &&
          f.completedAt == null) {
        missed++;
      }
    }
    // Treat overdue immunisations the same way (EPI signal → IMCI band).
    for (final im in imms) {
      final due = im.dueAt;
      if (due == null) continue;
      if (due < now.millisecondsSinceEpoch && due >= cutoff &&
          im.givenAt == null) {
        missed++;
      }
    }

    final daysSinceLast = _daysSinceLastVisit(follows, now);

    return PatientFacts(
      patientId: p.id,
      ageYears: p.age ?? _ageFromDob(p.dob),
      programmes: programmes,
      missedVisitsLast90d: missed,
      daysSinceLastVisit: daysSinceLast,
      lostToFollowUp: lost,
      redFlag: p.redFlag ?? false,
      serverRiskLevel: p.riskHintLevel,
      serverRiskColor: p.riskHintColor,
      vitals: vitals,
    );
  }

  /// Find the next due date, prioritizing:
  /// 1. The earliest FUTURE due date if any exists
  /// 2. Otherwise, the most recent (least overdue) PAST due date
  /// This ensures overdue items are correctly classified into overdue/dueToday tiers.
  static int? _earliestDueMillis(
    List<FollowUpRow> follows,
    List<ImmunisationRow> imms,
    DateTime now,
  ) {
    final nowMs = now.millisecondsSinceEpoch;
    int? earliestFuture;
    int? mostRecentPast;
    
    for (final f in follows) {
      final due = f.dueAt;
      if (due == null) continue;
      if (due >= nowMs) {
        // Future or today
        if (earliestFuture == null || due < earliestFuture) {
          earliestFuture = due;
        }
      } else {
        // Past (overdue)
        if (mostRecentPast == null || due > mostRecentPast) {
          mostRecentPast = due;
        }
      }
    }
    for (final im in imms) {
      final due = im.dueAt;
      if (due == null) continue;
      if (due >= nowMs) {
        if (earliestFuture == null || due < earliestFuture) {
          earliestFuture = due;
        }
      } else {
        if (mostRecentPast == null || due > mostRecentPast) {
          mostRecentPast = due;
        }
      }
    }
    
    // Prefer future dates, fall back to most recent past date
    return earliestFuture ?? mostRecentPast;
  }

  static int? _lastCompletedMillis(List<FollowUpRow> follows) {
    int? best;
    for (final f in follows) {
      final at = f.completedAt;
      if (at == null) continue;
      if (best == null || at > best) best = at;
    }
    return best;
  }

  static int? _daysSinceLastVisit(List<FollowUpRow> follows, DateTime now) {
    final last = _lastCompletedMillis(follows);
    if (last == null) return null;
    return now.difference(DateTime.fromMillisecondsSinceEpoch(last)).inDays;
  }

  static int? _ageFromDob(String? dob) {
    if (dob == null || dob.isEmpty) return null;
    final parsed = DateTime.tryParse(dob);
    if (parsed == null) return null;
    final now = DateTime.now();
    var years = now.year - parsed.year;
    if (now.month < parsed.month ||
        (now.month == parsed.month && now.day < parsed.day)) {
      years -= 1;
    }
    return years < 0 ? 0 : years;
  }
}
