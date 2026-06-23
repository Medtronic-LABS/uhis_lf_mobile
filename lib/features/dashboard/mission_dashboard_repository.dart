import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api/cql_api_service.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/follow_up_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/pregnancy_snapshot_dao.dart';
import '../../core/db/referral_dao.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/db/treatment_presence_dao.dart';
import '../../core/mission/mission_dashboard_service.dart';
import '../../core/mission/mission_pregnancy_facts.dart';
import '../../core/models/mission_brief.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/models/referral.dart';
import '../../core/models/sla.dart';
import '../../core/sla/priority_scorer.dart';
import '../../core/sla/sla_evaluator.dart';
import '../../core/models/programme.dart';
import '../worklist/worklist_repository.dart';
import '../referral/referral_repository.dart' as referral_repo;

/// Repository for the AI Mission Dashboard.
///
/// Wraps [MissionDashboardService] and DAOs to provide reactive data loading.
/// UI consumes this via Provider — never touches DAOs or services directly.
///
/// When [cqlService] is provided and [useCqlService] is true, fetches risk
/// scores from the server-side CQL engine. Falls back to on-device
/// [PriorityScorer] when offline or when CQL service fails.
class MissionDashboardRepository {
  MissionDashboardRepository({
    required WorklistRepository worklist,
    required referral_repo.ReferralRepository referrals,
    required PatientDao patients,
    required ReferralDao referralDao,
    required FollowUpDao followUps,
    required HouseholdDao households,
    required SlaEvaluator slaEvaluator,
    required PriorityScorer priorityScorer,
    PregnancySnapshotDao? pregnancySnapshot,
    TreatmentPresenceDao? treatmentPresence,
    CqlApiService? cqlService,
    AssessmentDao? assessments,
    UserHierarchyService? hierarchy,
    DateTime Function()? clock,
  })  : _worklist = worklist,
        _referrals = referrals,
        _patients = patients,
        _referralDao = referralDao,
        _followUps = followUps,
        _households = households,
        _slaEvaluator = slaEvaluator,
        _priorityScorer = priorityScorer,
        _pregnancySnapshot = pregnancySnapshot,
        _treatmentPresence = treatmentPresence,
        _cqlService = cqlService,
        _assessments = assessments,
        _hierarchy = hierarchy,
        _clock = clock ?? DateTime.now,
        _service = const MissionDashboardService();

  final WorklistRepository _worklist;
  final referral_repo.ReferralRepository _referrals;
  final PatientDao _patients;
  final ReferralDao _referralDao;
  final FollowUpDao _followUps;
  final HouseholdDao _households;
  final SlaEvaluator _slaEvaluator;
  final PriorityScorer _priorityScorer;
  final PregnancySnapshotDao? _pregnancySnapshot;
  final TreatmentPresenceDao? _treatmentPresence;
  final CqlApiService? _cqlService;
  final AssessmentDao? _assessments;
  final UserHierarchyService? _hierarchy;
  final DateTime Function() _clock;
  final MissionDashboardService _service;

  final _changes = ValueNotifier<int>(0);

  /// Fired after data changes. UI listens to refresh.
  Listenable get changes => _changes;

  /// Cached input data for reuse.
  MissionInputData? _cachedInput;

  /// In-flight loading operation to prevent duplicate concurrent loads.
  /// When multiple callers request data simultaneously, they share the same
  /// future rather than each starting their own load.
  Completer<MissionInputData>? _loadingCompleter;

  /// Cached CQL risk results for the current session.
  Map<String, CqlRiskResult>? _cachedCqlResults;

  /// Whether to use CQL service for risk scoring when available.
  /// Default: true when cqlService is provided.
  bool _useCqlService = true;

  /// Enable or disable CQL service usage.
  set useCqlService(bool value) {
    if (_useCqlService != value) {
      _useCqlService = value;
      clearCache(); // Force re-computation with new setting
    }
  }

  bool get useCqlService => _useCqlService && _cqlService != null;

  /// True if CQL service is available and enabled.
  bool get hasCqlService => _cqlService != null;

  /// True if last load used CQL service (vs local fallback).
  bool _lastLoadUsedCql = false;
  bool get lastLoadUsedCql => _lastLoadUsedCql;

  /// Load the AI daily brief.
  Future<MissionBrief> loadBrief() async {
    final input = await _loadInputData();
    return _service.computeBrief(input);
  }

  /// Load the prioritized mission queue using the 5-tier model.
  /// Returns items tagged with [DashboardTier], sorted by tier then
  /// composite score. Phase 3 dashboard consumes this; Phase 4
  /// wires the `+ N more` deep-link onto `/patients?tier=...`.
  Future<List<MissionQueueItem>> loadQueue({int? limit}) async {
    final input = await _loadInputData();
    final tiered = _service.computeTieredQueue(input);
    if (limit != null && tiered.length > limit) {
      return tiered.sublist(0, limit);
    }
    return tiered;
  }

  /// Load mission progress.
  Future<MissionProgress> loadProgress() async {
    final input = await _loadInputData();
    return _service.computeProgress(input);
  }

  /// Load critical alerts only.
  /// Reuses the same input data as loadQueue to avoid duplicate loading.
  Future<List<MissionQueueItem>> loadCriticalAlerts() async {
    final input = await _loadInputData();
    final queue = _service.computeTieredQueue(input);
    return _service.getCriticalAlerts(queue);
  }

  /// Load referral summary.
  Future<ReferralSummary> loadReferralSummary() async {
    final input = await _loadInputData();
    final summary = _service.computeReferralSummary(input);
    debugPrint('[MissionDashboardRepository] ReferralSummary: active=${summary.active}, breached=${summary.breached}, awaiting=${summary.awaitingReview}, completed=${summary.completed}');
    return summary;
  }

  /// Load due follow-ups.
  Future<List<FollowUpDue>> loadDueFollowUps() async {
    final input = await _loadInputData();
    return input.followUps;
  }

  /// Load household opportunities.
  Future<List<HouseholdOpportunity>> loadHouseholdOpportunities() async {
    final input = await _loadInputData();
    return _service.computeHouseholdOpportunities(input);
  }

  /// Force refresh all data.
  /// Invalidates the cache silently, pre-loads new data, then fires exactly
  /// one change notification — avoiding the two extra reloads that would
  /// occur if clearCache() (which notifies) was called here first.
  Future<void> refresh() async {
    _invalidateCache();
    await _loadInputData();
    _changes.value++;
  }

  /// Clear cached data and notify listeners so dependent widgets reload.
  /// Call this after external mutations (e.g. visit completion) to drive
  /// an immediate queue refresh.
  void clearCache() {
    _invalidateCache();
    _changes.value++;
  }

  /// Wipes cached state without firing a change notification.
  void _invalidateCache() {
    _cachedInput = null;
    _cachedCqlResults = null;
    _loadingCompleter = null;
  }

  /// Fetch CQL risk results for a batch of patient IDs.
  ///
  /// Returns empty map on failure (offline, service unavailable, etc.).
  Future<Map<String, CqlRiskResult>> _fetchCqlResults(
    List<String> patientIds,
  ) async {
    if (_cqlService == null || patientIds.isEmpty) {
      return const {};
    }

    try {
      final results = await _cqlService.evaluatePatients(patientIds);
      debugPrint(
        '[MissionDashboardRepository] CQL batch returned ${results.length} results',
      );
      return results;
    } catch (e) {
      debugPrint('[MissionDashboardRepository] CQL batch failed: $e');
      return const {};
    }
  }

  /// Convert CQL result to PriorityAssessment for compatibility.
  PriorityAssessment _cqlToPriorityAssessment(
    CqlRiskResult cql, {
    required String referralId,
  }) {
    // Map CQL level to SlaPriority
    SlaPriority level;
    switch (cql.level) {
      case CqlRiskLevel.urgent:
        level = SlaPriority.critical;
        break;
      case CqlRiskLevel.high:
        level = SlaPriority.high;
        break;
      case CqlRiskLevel.moderate:
        level = SlaPriority.medium;
        break;
      case CqlRiskLevel.low:
        level = SlaPriority.low;
        break;
    }

    // Build rationale from CQL result
    final rationale = ReferralRationale(
      drivers: cql.drivers,
      modelVersion: cql.modelVersion ?? 'cql-service',
      computedAt: cql.computedAt ?? DateTime.now(),
      confidence: cql.confidence,
      humanReviewRequired: cql.isCritical,
    );

    return PriorityAssessment(
      referralId: referralId,
      score: cql.score,
      level: level,
      drivers: cql.drivers,
      rationale: rationale,
    );
  }

  /// Load and cache all input data.
  /// Uses a Completer lock to ensure concurrent callers share the same load
  /// operation rather than each triggering their own DB/API queries.
  Future<MissionInputData> _loadInputData() async {
    // Return cached data immediately if available
    if (_cachedInput != null) return _cachedInput!;

    // If a load is already in progress, wait for it instead of starting another
    if (_loadingCompleter != null) {
      return _loadingCompleter!.future;
    }

    // Start a new load operation
    final completer = Completer<MissionInputData>();
    _loadingCompleter = completer;

    try {
      final result = await _loadInputDataImpl();
      _cachedInput = result;
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      // Only clear if this is still the active completer
      if (_loadingCompleter == completer) {
        _loadingCompleter = null;
      }
    }
  }

  /// Internal implementation of data loading, called once per cache miss.
  Future<MissionInputData> _loadInputDataImpl() async {
    final now = _clock();
    _lastLoadUsedCql = false;

    // Load worklist entries
    final worklistEntries = await _worklist.load();

    // Load referrals using queryDashboard (excludes closed by default)
    final referrals = await _referralDao.queryDashboard(limit: 200);
    debugPrint('[MissionDashboardRepository] Loaded ${referrals.length} referrals');
    for (final ref in referrals) {
      debugPrint('[MissionDashboardRepository] Referral ${ref.id}: state=${ref.state}, tier=${ref.slaTier}, patient=${ref.patientId}');
    }
    final referralAssessments = <String, PriorityAssessment>{};

    // Collect patient IDs for CQL batch request
    final patientIds = <String>{
      ...worklistEntries.map((e) => e.patientId),
      ...referrals.map((r) => r.patientId),
    }.toList();

    // Try CQL service first if enabled
    Map<String, CqlRiskResult> cqlResults = {};
    if (useCqlService && patientIds.isNotEmpty) {
      cqlResults = _cachedCqlResults ?? await _fetchCqlResults(patientIds);
      if (cqlResults.isNotEmpty) {
        _cachedCqlResults = cqlResults;
        _lastLoadUsedCql = true;
        debugPrint(
          '[MissionDashboardRepository] Using CQL service for ${cqlResults.length} patients',
        );
      }
    }

    for (final ref in referrals) {
      // Check if we have a CQL result for this referral's patient
      final cqlResult = cqlResults[ref.patientId];
      if (cqlResult != null) {
        // Use CQL-derived assessment
        referralAssessments[ref.id] = _cqlToPriorityAssessment(
          cqlResult,
          referralId: ref.id,
        );
        continue;
      }

      // Fall back to local scoring
      // Convert epoch ms to DateTime
      final createdDateTime = DateTime.fromMillisecondsSinceEpoch(ref.createdAt);
      final facts = ReferralFacts(
        referralId: ref.id,
        slaTier: ref.slaTier,
        currentState: ref.state,
        createdAt: createdDateTime,
        now: now,
        ageYears: null, // Would need patient lookup
        isPregnancy: false, // Would need patient lookup
        isEmergencyDiagnosis: ref.slaTier == SlaTier.emergency,
      );

      // Evaluate SLA
      final slaResult = _slaEvaluator.evaluate(facts);
      
      // Compute priority
      final priorityResult = _priorityScorer.score(
        facts: facts,
        slaBreached: slaResult.isBreached,
      );

      referralAssessments[ref.id] = priorityResult;
    }

    // Load follow-ups for all patients in worklist
    final worklistPatientIds = worklistEntries.map((e) => e.patientId).toList();
    final followUpMap = await _followUps.forMany(worklistPatientIds);

    // Build patientId → displayName lookup off the worklist join so follow-up
    // cards render the real member name instead of the literal "Patient"
    // placeholder that used to leak through here.
    final patientNamesById = <String, String>{
      for (final e in worklistEntries) e.patientId: e.displayName,
    };

    // Convert to FollowUpDue list. No date-window filter — the tier
    // classifier (DashboardTier.fromDaysToDue + composite score) decides
    // visibility. Old 7-day window was dropping every overdue community
    // follow-up (most bundle rows are 30-90 days stale), making 24 of 24
    // SK-owned follow-ups invisible. Dedupe by patientId in
    // `computeTieredQueue` collapses duplicate worklist + follow-up rows.
    final followUps = <FollowUpDue>[];
    for (final entry in followUpMap.entries) {
      for (final row in entry.value) {
        final dueMs = row.dueAt;
        if (dueMs == null) continue;
        if (row.completedAt != null) continue; // already done — skip
        followUps.add(FollowUpDue(
          id: row.id,
          patientId: row.patientId,
          patientName: patientNamesById[row.patientId] ?? row.patientId,
          dischargedAt: null,
          dueAt: DateTime.fromMillisecondsSinceEpoch(dueMs),
          reason: row.kind,
          phoneNumber: null,
        ));
      }
    }

    // TODO: Load household members for opportunity detection
    // For now, return empty map — can be wired later
    final householdMembers = <String, List<HouseholdMemberData>>{};

    // Resolve patient → household → household number so queue items can render
    // `House #NN`. Worklist entries already carry the household UUID in
    // `householdNo`; referrals + follow-ups only carry patientId, so look those
    // up via PatientDao. Failures fall back to no number (display will hide).
    final patientHouseholdsById = <String, String>{};
    for (final entry in worklistEntries) {
      final hh = entry.householdNo;
      if (hh != null && hh.isNotEmpty) {
        patientHouseholdsById[entry.patientId] = hh;
      }
    }
    final extraPatientIds = <String>{
      ...referrals.map((r) => r.patientId),
      ...followUps.map((f) => f.patientId),
    }..removeAll(patientHouseholdsById.keys);
    for (final pid in extraPatientIds) {
      try {
        final p = await _patients.byId(pid);
        final hh = p?.householdId;
        if (hh != null && hh.isNotEmpty) {
          patientHouseholdsById[pid] = hh;
        }
      } on Object catch (e) {
        debugPrint(
          '[MissionDashboardRepository] patient lookup failed for $pid: $e',
        );
      }
    }
    final householdNumbersById = <String, String>{};
    final uniqueHouseholdIds = patientHouseholdsById.values.toSet();
    for (final hhId in uniqueHouseholdIds) {
      try {
        final hh = await _households.getById(hhId);
        final no = hh?.householdNo;
        if (no != null && no.isNotEmpty) {
          householdNumbersById[hhId] = no;
        }
      } on Object catch (e) {
        debugPrint(
          '[MissionDashboardRepository] household lookup failed for $hhId: $e',
        );
      }
    }

    // ── Tier-classifier side maps (Phase 2 wiring) ─────────────────────────
    // Pull side-channel patient signals so MissionDashboardService.
    // computeTieredQueue can classify without re-reading the DB per row.

    final pregSnap = _pregnancySnapshot;
    final pregnancyByPatientId = pregSnap == null
        ? const <String, PregnancyFacts>{}
        : await pregSnap.getAll();
    final tpDao = _treatmentPresence;
    final patientsOnTreatment =
        tpDao == null ? const <String>{} : await tpDao.getAll();

    final patientIdSet = <String>{
      ...worklistEntries.map((e) => e.patientId),
      ...followUps.map((f) => f.patientId),
    };

    // Patient-table-derived signals (redFlag, isActive, dob, updatedAt).
    final agesByPatientId = <String, int>{
      for (final e in worklistEntries)
        if (e.age != null) e.patientId: e.age!,
    };
    final disabilityByPatientId = <String, bool>{};
    final lastUpdatedByPatientId = <String, int>{};
    final hiddenPatientIds = <String>{};
    final redFlagPatientIds = <String>{};
    final ncdOverduePatientIds = <String>{};
    final neonatePatientIds = <String>{};
    final youngInfantPatientIds = <String>{};

    final today = DateTime(now.year, now.month, now.day);
    for (final pid in patientIdSet) {
      try {
        final p = await _patients.byId(pid);
        if (p == null) continue;
        if (p.isActive == false) hiddenPatientIds.add(pid);
        if (p.redFlag == true) redFlagPatientIds.add(pid);
        if (p.updatedAt != null) lastUpdatedByPatientId[pid] = p.updatedAt!;
        final hintLevel = p.riskHintLevel?.toUpperCase();
        final hintColor = p.riskHintColor?.toUpperCase();
        if (hintLevel == 'HIGH' || hintColor == 'RED') {
          ncdOverduePatientIds.add(pid);
        }
        if (p.age != null && !agesByPatientId.containsKey(pid)) {
          agesByPatientId[pid] = p.age!;
        }
        final dobIso = p.dob;
        if (dobIso != null && dobIso.isNotEmpty) {
          final dob = DateTime.tryParse(dobIso);
          if (dob != null) {
            final ageDays = today.difference(DateTime(dob.year, dob.month, dob.day)).inDays;
            if (ageDays >= 0 && ageDays < 28) {
              neonatePatientIds.add(pid);
            } else if (ageDays >= 28 && ageDays < 60) {
              youngInfantPatientIds.add(pid);
            }
          }
        }
      } on Object catch (e) {
        debugPrint(
          '[MissionDashboardRepository] patient enrich failed for $pid: $e',
        );
      }
    }

    // pregnant proxy: snapshot-backed patients + any ANC/PNC-enrolled patient
    // from the worklist. Snapshot-only gave +0 composite bonus to ANC patients
    // without a PregnancySnapshot row (e.g. first-sync or sparse server data),
    // causing them to sort identically to low-risk patients in the same tier.
    final pregnantPatientIds = <String>{
      ...pregnancyByPatientId.keys,
      ...worklistEntries
          .where((e) =>
              e.programmes.contains(Programme.anc) ||
              e.programmes.contains(Programme.pnc))
          .map((e) => e.patientId),
    };
    final householdHeadPatientIds = <String>{};

    // Follow-up-row-derived signals: LTFU set, attempts max, ever-referred,
    // completed-today, TB-default-risk.
    final followUpRowMap = await _followUps.forMany(patientIdSet.toList());
    final patientsLtfu = <String>{};
    final unsuccessfulAttemptsByPatientId = <String, int>{};
    final patientsEverReferred = <String>{};
    final completedTodayPatientIds = <String>{};
    final tbAtRiskPatientIds = <String>{};
    final referralArrivalPendingPatientIds = <String>{};
    const referralArrivalPendingDays = 3;
    for (final entry in followUpRowMap.entries) {
      final pid = entry.key;
      bool anyTb = false;
      bool anyTbRisk = false;
      bool anyTbOverdue = false;
      for (final r in entry.value) {
        final type = r.type?.toUpperCase();
        if (r.isLost || type == 'LOST_TO_FOLLOW_UP') {
          patientsLtfu.add(pid);
        }
        final attempts = r.unsuccessfulAttempts;
        if (attempts != null) {
          final prev = unsuccessfulAttemptsByPatientId[pid] ?? 0;
          if (attempts > prev) {
            unsuccessfulAttemptsByPatientId[pid] = attempts;
          }
        }
        if (r.referredSiteId != null && r.referredSiteId!.isNotEmpty) {
          patientsEverReferred.add(pid);
          // Referral arrival pending: bundle's REFERRED follow-up has a
          // facility recorded but no close-out for ≥3 days. Surfaces lost
          // referrals — the PPH / sepsis / TB-default loss window.
          final isReferred = type == 'REFERRED';
          final notDone = !(r.isLost) && r.completedAt == null;
          final dueMs = r.dueAt;
          if (isReferred && notDone && dueMs != null) {
            final dueAt = DateTime.fromMillisecondsSinceEpoch(dueMs);
            final daysSince = today.difference(
              DateTime(dueAt.year, dueAt.month, dueAt.day),
            ).inDays;
            if (daysSince >= referralArrivalPendingDays) {
              referralArrivalPendingPatientIds.add(pid);
            }
          }
        }
        final completedAt = r.completedAt;
        if (completedAt != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(completedAt);
          if (DateTime(dt.year, dt.month, dt.day) == today) {
            completedTodayPatientIds.add(pid);
          }
        }
        final isTb = (type ?? '').contains('TB') ||
            r.kind.toLowerCase().contains('tb');
        if (isTb) {
          anyTb = true;
          if ((attempts ?? 0) > 0) anyTbRisk = true;
          final dueAt = r.dueAt;
          if (dueAt != null &&
              DateTime.fromMillisecondsSinceEpoch(dueAt).isBefore(today)) {
            anyTbOverdue = true;
          }
        }
        // NCD follow-up that is past due → NCD drift signal
        if (r.kind == FollowUpKind.ncd || r.kind == FollowUpKind.assessment) {
          final dueMs = r.dueAt;
          if (dueMs != null && r.completedAt == null && !r.isLost &&
              DateTime.fromMillisecondsSinceEpoch(dueMs).isBefore(today)) {
            ncdOverduePatientIds.add(pid);
          }
        }
      }
      if (anyTb && (anyTbRisk || anyTbOverdue)) {
        tbAtRiskPatientIds.add(pid);
      }
    }

    // Assessment customStatus → NCD drift signal (e.g. UNCONTROLLED_BP)
    if (_assessments != null) {
      const ncdAlertStatuses = {
        'UNCONTROLLED_BP',
        'UNCONTROLLED_BLOOD_SUGAR',
        'UNCONTROLLED_CHOLESTEROL',
        'IRREGULAR_MEDICATION',
      };
      final assessmentMap =
          await _assessments.forMany(patientIdSet.toList());
      for (final entry in assessmentMap.entries) {
        for (final row in entry.value) {
          try {
            final decoded = jsonDecode(row.rawJson);
            if (decoded is! Map) continue;
            final statusRaw = decoded['customStatus'];
            if (statusRaw is! List) continue;
            for (final s in statusRaw) {
              if (s is String &&
                  ncdAlertStatuses.contains(s.toUpperCase())) {
                ncdOverduePatientIds.add(entry.key);
                break;
              }
            }
          } on Object catch (_) {}
        }
      }
    }

    // Build village id → name lookup from hierarchy cache (no network call).
    final villageNamesById = <String, String>{};
    if (_hierarchy != null) {
      for (final v in _hierarchy.subVillages ?? const []) {
        villageNamesById[v.id] = v.name;
      }
      for (final v in _hierarchy.villages ?? const []) {
        villageNamesById.putIfAbsent(v.id, () => v.name);
      }
    }

    _cachedInput = MissionInputData(
      worklistEntries: worklistEntries,
      referrals: referrals,
      referralAssessments: referralAssessments,
      followUps: followUps,
      completedVisitsToday: 0, // TODO: Track completed visits
      householdMembers: householdMembers,
      cqlResults: cqlResults, // Pass CQL results for worklist scoring
      householdNumbersById: householdNumbersById,
      patientHouseholdsById: patientHouseholdsById,
      pregnancyByPatientId: pregnancyByPatientId,
      patientsOnTreatment: patientsOnTreatment,
      patientsLtfu: patientsLtfu,
      unsuccessfulAttemptsByPatientId: unsuccessfulAttemptsByPatientId,
      patientsEverReferred: patientsEverReferred,
      agesByPatientId: agesByPatientId,
      disabilityByPatientId: disabilityByPatientId,
      lastUpdatedByPatientId: lastUpdatedByPatientId,
      hiddenPatientIds: hiddenPatientIds,
      completedTodayPatientIds: completedTodayPatientIds,
      tbAtRiskPatientIds: tbAtRiskPatientIds,
      ncdOverduePatientIds: ncdOverduePatientIds,
      redFlagPatientIds: redFlagPatientIds,
      pregnantPatientIds: pregnantPatientIds,
      householdHeadPatientIds: householdHeadPatientIds,
      neonatePatientIds: neonatePatientIds,
      youngInfantPatientIds: youngInfantPatientIds,
      referralArrivalPendingPatientIds: referralArrivalPendingPatientIds,
      villageNamesById: villageNamesById,
    );

    return _cachedInput!;
  }
}
