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
import '../../core/risk/clinical_vitals_from_history.dart';
import '../../core/risk/risk_scoring_service.dart';
import '../../core/time/calendar_day.dart';

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

  /// Apply sort order — PRD §2.8 priority algorithm:
  ///   1. Band: 1 → 2 → 3 → 4
  ///   2. Modifier: a → b → none
  ///   3. Pregnant > non-pregnant
  ///   4. Longer overdue ranks higher (esp. modifier b; applied whenever
  ///      overdue days > 0 so scheduled overdue is visible even if modifier
  ///      assignment missed a row)
  ///   5. Village match (when SK has selected a village)
  ///   6. Display name (stable tiebreaker)
  ///
  /// Date tier is *not* a primary key — overdue duration is a within-band
  /// tiebreaker only. Date urgency surfaces as modifier `b` + overdue days.
  static void _applySpecSort(
    List<WorklistEntry> entries, {
    String? selectedVillageId,
  }) {
    final now = DateTime.now();

    String tierLabel(WorklistEntry e) {
      final due = e.nextDueAt;
      if (due == null) return 'upcoming';
      return DashboardTier.fromDueAt(due, now: now).name;
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
      return CalendarDay.daysBetween(due, now).clamp(0, 999);
    }

    entries.sort((a, b) {
      final byBand = bandRank(a.band).compareTo(bandRank(b.band));
      if (byBand != 0) return byBand;
      final byMod = modRank(a.modifier).compareTo(modRank(b.modifier));
      if (byMod != 0) return byMod;
      final byPreg = (a.isPregnant ? 0 : 1).compareTo(b.isPregnant ? 0 : 1);
      if (byPreg != 0) return byPreg;
      final byOverdue = overdueDays(b).compareTo(overdueDays(a));
      if (byOverdue != 0) return byOverdue;
      if (selectedVillageId != null && selectedVillageId.isNotEmpty) {
        final byVillage = (a.villageId == selectedVillageId ? 0 : 1)
            .compareTo(b.villageId == selectedVillageId ? 0 : 1);
        if (byVillage != 0) return byVillage;
      }
      return a.displayName.compareTo(b.displayName);
    });

    assert(() {
      final codes = entries.map((e) => e.priorityCode);
      ConsoleLog.step('[Worklist sort] ${entries.length} patients:');
      ConsoleLog.step('  spec:     $kPrioritySortSpecLegend');
      ConsoleLog.step('  chain:    ${prioritySortChain(codes)}');
      ConsoleLog.step('  compact:  ${prioritySortChainCompact(codes)}');
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        final progs = e.programmes.map((p) => p.name).join(',');
        final overdue = overdueDays(e);
        final tier = tierLabel(e);
        ConsoleLog.step(
          '  ${i + 1}. [${e.priorityCode}] ${e.displayName}'
          ' | prog: $progs | tier: $tier'
          '${e.isPregnant ? " | pregnant" : ""}'
          '${overdue > 0 ? " | overdue: ${overdue}d" : ""}'
          '${e.reasons.isNotEmpty ? " | why: ${e.reasons.first}" : ""}',
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
    final localVitals = await _localAssessments.latestClinicalVitalsForMany(ids);
    final historyVitals = await _vitalsFromAssessmentHistory(ids);
    final now = DateTime.now();

    assert(() {
      ConsoleLog.banner(
        '[Risk recompute] scoring ${patients.length} patients '
        '(localVitals=${localVitals.length}, historyVitals=${historyVitals.length})',
      );
      return true;
    }());

    // Collect debug rows for a ranked summary after scoring.
    final debugRows = <_ScoreDebugRow>[];

    for (final p in patients) {
      final follows = followMap[p.id] ?? const <FollowUpRow>[];
      final imms = immMap[p.id] ?? const <ImmunisationRow>[];
      final nextDueMs = _earliestDueMillis(follows, imms, now) ?? p.nextDueAt;
      final nextDue = nextDueMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextDueMs);
      final hasLocal = localVitals.containsKey(p.id);
      final hasHistory = historyVitals.containsKey(p.id);
      final vitals = ClinicalVitalsFromHistory.merge(
        localVitals[p.id],
        historyVitals[p.id],
      );
      final facts = _factsFor(
        p,
        progMap[p.id] ?? const <Programme>{},
        follows,
        imms,
        vitals,
        now,
        nextDueAt: nextDue,
      );
      final assessment = _risk.score(facts);
      final lastVisit = _lastCompletedMillis(follows) ?? p.lastVisitAt;
      await _patients.updateRisk(
        patientId: p.id,
        sortRank: assessment.sortRank,
        bandWireTag: assessment.band.wireTag,
        modifierWireTag: assessment.modifier.wireTag,
        reasonsJson: jsonEncode(assessment.reasons),
        nextDueAt: nextDueMs,
        lastVisitAt: lastVisit,
        missedVisitCount: facts.missedVisitsLast90d,
        redFlag: facts.redFlag,
      );

      assert(() {
        final progs = facts.programmes.map((x) => x.name).join(',');
        final overdueDays = nextDue != null
            ? CalendarDay.daysBetween(nextDue, now).clamp(0, 999)
            : 0;
        final vitalsSrc = hasLocal && hasHistory
            ? 'local+history'
            : hasLocal
                ? 'local'
                : hasHistory
                    ? 'history'
                    : 'none';
        final drivers =
            assessment.rationale?.drivers.join(', ') ?? '(no drivers)';
        ConsoleLog.step(
          '[Risk score] ${p.name ?? p.id} → ${assessment.priorityCode}'
          ' | prog: $progs | vitals: $vitalsSrc'
          '${_vitalsBrief(vitals)}'
          '${overdueDays > 0 ? " | overdue: ${overdueDays}d" : ""}'
          ' | drivers: $drivers',
        );
        debugRows.add(_ScoreDebugRow(
          name: p.name ?? p.id,
          code: assessment.priorityCode,
          sortRank: assessment.sortRank,
          pregnant: facts.isPregnant,
          overdueDays: overdueDays,
        ));
        return true;
      }());
    }

    assert(() {
      debugRows.sort((a, b) {
        final byRank = b.sortRank.compareTo(a.sortRank);
        if (byRank != 0) return byRank;
        final byPreg = (a.pregnant ? 0 : 1).compareTo(b.pregnant ? 0 : 1);
        if (byPreg != 0) return byPreg;
        return b.overdueDays.compareTo(a.overdueDays);
      });
      ConsoleLog.banner(
        '[Risk recompute] priority order (band+mod, then preg, then overdue):',
      );
      final codes = debugRows.map((r) => r.code);
      ConsoleLog.banner('  spec:     $kPrioritySortSpecLegend');
      ConsoleLog.banner('  chain:    ${prioritySortChain(codes)}');
      ConsoleLog.banner('  compact:  ${prioritySortChainCompact(codes)}');
      for (var i = 0; i < debugRows.length; i++) {
        final r = debugRows[i];
        ConsoleLog.banner(
          '  ${i + 1}. [${r.code}] ${r.name}'
          '${r.pregnant ? " | pregnant" : ""}'
          '${r.overdueDays > 0 ? " | overdue: ${r.overdueDays}d" : ""}',
        );
      }
      return true;
    }());

    await _syncMeta.stampWarm('worklist', DateTime.now());
    _changes.value++;
    return patients.length;
  }

  static String _vitalsBrief(ClinicalVitals? v) {
    if (v == null) return '';
    final parts = <String>[];
    if (v.hemoglobin != null) {
      parts.add('Hb ${v.hemoglobin!.toStringAsFixed(1)}');
    }
    if (v.systolicBp != null || v.diastolicBp != null) {
      parts.add('BP ${v.systolicBp ?? '-'}/${v.diastolicBp ?? '-'}');
    }
    if (v.fastingGlucoseMmolL != null) {
      parts.add('glu ${v.fastingGlucoseMmolL!.toStringAsFixed(1)}');
    }
    if (v.gestationalAgeWeeks != null) parts.add('GA ${v.gestationalAgeWeeks}');
    if (v.parity != null) parts.add('parity ${v.parity}');
    if (v.hasDangerSign) parts.add('danger');
    if (v.hasStrokeSign) parts.add('stroke');
    if (v.hasEclampsia) parts.add('eclampsia');
    if (v.hasAbnormalUrine) parts.add('urine+');
    if (v.hasDiabetes) parts.add('DM');
    if (parts.isEmpty) return '';
    return ' [${parts.join(', ')}]';
  }

  /// Parse synced assessment-history rows into ClinicalVitals.
  /// Walks newest → oldest per patient and merges so Hb from the latest ANC
  /// visit can combine with gravida from an earlier PWPROFILE row.
  Future<Map<String, ClinicalVitals>> _vitalsFromAssessmentHistory(
    List<String> patientIds,
  ) async {
    final byPatient = await _assessments.forMany(patientIds);
    if (byPatient.isEmpty) return const <String, ClinicalVitals>{};
    final out = <String, ClinicalVitals>{};
    for (final entry in byPatient.entries) {
      ClinicalVitals? merged;
      for (final row in entry.value) {
        final parsed = ClinicalVitalsFromHistory.fromRawJson(
          row.rawJson,
          assessmentType: row.kind,
        );
        if (parsed == null) continue;
        // Rows are ordered occurred_at DESC — accumulate field gaps from older.
        merged = ClinicalVitalsFromHistory.merge(merged, parsed);
      }
      if (merged != null) out[entry.key] = merged;
    }
    return out;
  }

  PatientFacts _factsFor(
    Patient p,
    Set<Programme> programmes,
    List<FollowUpRow> follows,
    List<ImmunisationRow> imms,
    ClinicalVitals? vitals,
    DateTime now, {
    DateTime? nextDueAt,
  }) {
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
      nextDueAt: nextDueAt,
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

class _ScoreDebugRow {
  const _ScoreDebugRow({
    required this.name,
    required this.code,
    required this.sortRank,
    required this.pregnant,
    required this.overdueDays,
  });

  final String name;
  final String code;
  final int sortRank;
  final bool pregnant;
  final int overdueDays;
}
