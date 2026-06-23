import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/db/follow_up_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/db/referral_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/programme.dart';
import '../../core/models/referral.dart';
import '../../core/models/sla.dart';
import '../../core/notifications/channel_registry.dart';
import '../../core/notifications/repeat_scheduler.dart';
import '../../core/sla/priority_scorer.dart';
import '../../core/sla/sla_evaluator.dart';

/// View-model + lifecycle owner for referrals. UI consumes [load] / [counts]
/// / [watchChanges] only — never touches DAOs or the engines directly.
///
/// Single seam between cached SQLite, the on-device SLA engine, the priority
/// scorer, and the notification scheduler.
///
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §4 + §12.
class ReferralRepository {
  ReferralRepository({
    required ReferralDao referrals,
    required PatientDao patients,
    required PatientProgrammesDao programmes,
    required FollowUpDao followUps,
    required SlaEvaluator slaEvaluator,
    required PriorityScorer priorityScorer,
    RepeatScheduler? notificationScheduler,
    DateTime Function()? clock,
  })  : _referrals = referrals,
        _patients = patients,
        _programmes = programmes,
        _followUps = followUps,
        _sla = slaEvaluator,
        _priority = priorityScorer,
        _notifications = notificationScheduler,
        _clock = clock ?? DateTime.now;

  final ReferralDao _referrals;
  final PatientDao _patients;
  final PatientProgrammesDao _programmes;
  final FollowUpDao _followUps;
  final SlaEvaluator _sla;
  final PriorityScorer _priority;
  final RepeatScheduler? _notifications;
  final DateTime Function() _clock;

  final _changes = ValueNotifier<int>(0);

  /// Fired after every successful recompute or persistence. UI listens to
  /// refresh.
  Listenable get changes => _changes;

  /// Create a new referral on-device. Computes SLA + priority + rationale
  /// then persists. Always emits a status event so the timeline is complete.
  Future<Referral> create({
    required String patientId,
    required SlaTier slaTier,
    String? id,
    String? householdId,
    String? villageId,
    String? diagnosisCode,
    String? diagnosisLabel,
    String actor = 'sk',
  }) async {
    final now = _clock();
    final referralId = id ?? _newId(patientId, now);
    var draft = Referral.draft(
      id: referralId,
      patientId: patientId,
      slaTier: slaTier,
      householdId: householdId,
      villageId: villageId,
      diagnosisCode: diagnosisCode,
      diagnosisLabel: diagnosisLabel,
      now: now,
    );
    await _referrals.upsertMany([draft]);
    await _referrals.appendStatusEvent(ReferralStatusEventRow(
      id: '$referralId:create:${now.millisecondsSinceEpoch}',
      referralId: referralId,
      toState: ReferralStatus.created,
      occurredAt: now.millisecondsSinceEpoch,
      actor: actor,
    ));
    final after = await _recomputeOne(referralId);
    return after ?? draft;
  }

  /// Transition a referral to a new state. Appends a status event + reruns
  /// the SLA / priority pass so the persisted row reflects the change.
  Future<void> transition({
    required String referralId,
    required ReferralStatus to,
    String actor = 'sk',
    String? reason,
  }) async {
    final current = await _referrals.byId(referralId);
    if (current == null) return;
    final now = _clock();
    final updated = current.copyWith(
      state: to,
      updatedAt: now.millisecondsSinceEpoch,
      closedAt: to.isClosed ? now.millisecondsSinceEpoch : null,
    );
    await _referrals.upsertMany([updated]);
    await _referrals.appendStatusEvent(ReferralStatusEventRow(
      id: '$referralId:${to.wireTag}:${now.millisecondsSinceEpoch}',
      referralId: referralId,
      fromState: current.state,
      toState: to,
      occurredAt: now.millisecondsSinceEpoch,
      actor: actor,
      reason: reason,
    ));
    await _recomputeOne(referralId);
  }

  /// Worklist-equivalent entry point. UI passes the priority-band filter; the
  /// repository returns rows sorted by indexed SQL.
  Future<List<Referral>> load({SlaPriority? levelFilter, int limit = 200}) {
    return _referrals.queryDashboard(
      levelFilter: levelFilter,
      limit: limit,
    );
  }

  /// Lightweight aggregates for the dashboard chip on the home screen.
  Future<({int critical, int active})> counts() async {
    final crit = await _referrals.countByLevel(SlaPriority.critical);
    final active = await _referrals.countActive();
    return (critical: crit, active: active);
  }

  /// Timeline data — all status events for a referral in chronological order.
  Future<List<ReferralStatusEventRow>> timeline(String referralId) {
    return _referrals.eventsForReferral(referralId);
  }

  /// Hooked from `OfflineSyncService` after every sync — recompute every
  /// open referral. Mirrors `WorklistRepository.recomputeAllAfterSync`.
  /// Returns the count of referrals re-scored.
  Future<int> recomputeAllAfterSync() async {
    final open = await _referrals.allOpen();
    if (open.isEmpty) return 0;
    final patientIds = open.map((r) => r.patientId).toSet().toList();
    final allPatients = await _patients.allForVillages(const <String>[]);
    final patientById = <String, Patient>{
      for (final p in allPatients) p.id: p,
    };
    final progMap = await _programmes.programmesForMany(patientIds);
    final followMap = await _followUps.forMany(patientIds);
    final now = _clock();
    int reprocessed = 0;
    for (final r in open) {
      final patient = patientById[r.patientId];
      final programmes = progMap[r.patientId] ?? const <Programme>{};
      final followUps = followMap[r.patientId] ?? const <FollowUpRow>[];
      await _applyAssessmentsTo(r,
          patient: patient,
          programmes: programmes,
          followUps: followUps,
          now: now);
      reprocessed++;
    }
    _changes.value++;
    return reprocessed;
  }

  /// Re-emit notifications for any newly-breached or newly-warning referrals.
  /// Idempotent within the [EscalationChain.minIntervalBetweenRepeats] floor.
  Future<int> dispatchPendingNotifications() async {
    final scheduler = _notifications;
    if (scheduler == null) return 0;
    final open = await _referrals.allOpen();
    int n = 0;
    for (final r in open) {
      final channel = _channelForReferral(r);
      if (channel == null) continue;
      final title = _titleFor(channel);
      final body = _bodyFor(r);
      final fired = await scheduler.maybeFire(
        referralId: r.id,
        channelId: channel,
        title: title,
        body: body,
        payload: <String, Object?>{
          'referralId': r.id,
          'patientId': r.patientId,
          'level': r.priorityLevel,
          'drivers': r.priorityDrivers,
          'title': title,
          'body': body,
        },
      );
      if (fired) n++;
    }
    return n;
  }

  Future<Referral?> _recomputeOne(String referralId) async {
    final current = await _referrals.byId(referralId);
    if (current == null) return null;
    final patient = await _patients.byId(current.patientId);
    final programmes = (await _programmes.programmesForMany([current.patientId]))
            [current.patientId] ??
        const <Programme>{};
    final followUps =
        (await _followUps.forMany([current.patientId]))[current.patientId] ??
            const <FollowUpRow>[];
    return _applyAssessmentsTo(
      current,
      patient: patient,
      programmes: programmes,
      followUps: followUps,
      now: _clock(),
    );
  }

  Future<Referral> _applyAssessmentsTo(
    Referral r, {
    required Patient? patient,
    required Set<Programme> programmes,
    required List<FollowUpRow> followUps,
    required DateTime now,
  }) async {
    final facts = _factsFor(
      r,
      patient: patient,
      programmes: programmes,
      followUps: followUps,
      now: now,
    );
    final sla = _sla.evaluate(facts);
    final priority = _priority.score(
      facts: facts,
      slaBreached: sla.isBreached || sla.state == ReferralStatus.breachedArrival,
    );
    final rationaleJson = jsonEncode(priority.rationale.toJson());
    final driversJson = jsonEncode(priority.drivers);
    await _referrals.updateAssessment(
      referralId: r.id,
      score: priority.score,
      level: priority.level.wireTag,
      driversJson: driversJson,
      rationaleJson: rationaleJson,
      state: sla.state.wireTag,
      breachedSince: sla.breachedSince?.millisecondsSinceEpoch,
      dueArrivalAt: sla.dueArrivalAt?.millisecondsSinceEpoch,
      dueTreatmentAt: sla.dueTreatmentAt?.millisecondsSinceEpoch,
      escalationLevel: sla.escalationLevel.index0,
      updatedAt: now.millisecondsSinceEpoch,
      closedAt: sla.state.isClosed ? now.millisecondsSinceEpoch : null,
    );
    return r.copyWith(
      state: sla.state,
      priorityScore: priority.score,
      priorityLevel: priority.level.wireTag,
      priorityDrivers: priority.drivers,
      rationaleJson: rationaleJson,
      dueArrivalAt: sla.dueArrivalAt?.millisecondsSinceEpoch,
      dueTreatmentAt: sla.dueTreatmentAt?.millisecondsSinceEpoch,
      breachedSince: sla.breachedSince?.millisecondsSinceEpoch,
      escalationLevel: sla.escalationLevel.index0,
      updatedAt: now.millisecondsSinceEpoch,
    );
  }

  ReferralFacts _factsFor(
    Referral r, {
    required Patient? patient,
    required Set<Programme> programmes,
    required List<FollowUpRow> followUps,
    required DateTime now,
  }) {
    final ageYears = patient?.age ?? _ageFromDob(patient?.dob);
    final isPregnancy = programmes.contains(Programme.anc);
    final isEmergency = r.slaTier == SlaTier.emergency;

    // Arrival + treatment timestamps come from the status events log;
    // synthesise here from the current state column. Persisted history is
    // available via `eventsForReferral` for the timeline UI; the engine
    // only needs the "has-it-happened-yet" booleans.
    DateTime? arrivalAt;
    DateTime? treatmentAt;
    switch (r.state) {
      case ReferralStatus.arrived:
      case ReferralStatus.treatmentStarted:
      case ReferralStatus.closedRecovered:
      case ReferralStatus.closedDeceased:
        arrivalAt = DateTime.fromMillisecondsSinceEpoch(r.updatedAt);
        break;
      default:
        break;
    }
    if (r.state == ReferralStatus.treatmentStarted ||
        r.state == ReferralStatus.closedRecovered ||
        r.state == ReferralStatus.closedDeceased) {
      treatmentAt = DateTime.fromMillisecondsSinceEpoch(r.updatedAt);
    }

    int missed = 0;
    final cutoff =
        now.subtract(const Duration(days: 90)).millisecondsSinceEpoch;
    final nowMs = now.millisecondsSinceEpoch;
    for (final f in followUps) {
      final due = f.dueAt;
      if (due == null) continue;
      if (due < nowMs && due >= cutoff && f.completedAt == null) missed++;
    }

    return ReferralFacts(
      referralId: r.id,
      slaTier: r.slaTier,
      currentState: r.state,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
      now: now,
      ageYears: ageYears,
      isPregnancy: isPregnancy,
      isEmergencyDiagnosis: isEmergency,
      arrivalConfirmedAt: arrivalAt,
      treatmentStartedAt: treatmentAt,
      missedFollowUps: missed,
      escalationLevel: EscalationLevel.fromIndex(r.escalationLevel),
    );
  }

  String _newId(String patientId, DateTime now) {
    final ms = now.millisecondsSinceEpoch;
    final h = '$patientId:$ms'.hashCode & 0x7fffffff;
    return 'ref-$ms-$h';
  }

  String? _channelForReferral(Referral r) {
    final level = SlaPriority.fromWireTag(r.priorityLevel);
    if (r.state == ReferralStatus.closedRecovered ||
        r.state == ReferralStatus.closedDeceased) {
      return NotificationChannels.completion;
    }
    if (r.breachedSince != null || level == SlaPriority.critical) {
      return NotificationChannels.critical;
    }
    if (level == SlaPriority.high) {
      return NotificationChannels.warning;
    }
    return null;
  }

  String _titleFor(String channel) {
    switch (channel) {
      case NotificationChannels.critical:
        return '🔴 SLA breach';
      case NotificationChannels.warning:
        return '🟠 Referral warning';
      case NotificationChannels.completion:
        return '🟢 Referral completed';
      default:
        return 'Referral update';
    }
  }

  String _bodyFor(Referral r) {
    final drivers = r.priorityDrivers.take(3).join(' · ');
    return drivers.isEmpty
        ? 'Open referral needs your attention.'
        : drivers;
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

  /// Seeds comprehensive demo referral data matching the SLA monitoring spec.
  /// Creates varied scenarios: SLA breached, facility delay, completed, etc.
  /// Always clears and reseeds demo data to ensure fresh scenarios.
  Future<int> seedDemoDataIfEmpty() async {
    // Clear existing demo data to reseed with latest scenarios
    final cleared = await _referrals.clearDemoData();
    if (cleared > 0) {
      debugPrint('[referrals] cleared $cleared old demo referrals');
    }
    
    final now = _clock();
    final patients = await _patients.allForVillages(const <String>[]);
    debugPrint('[referrals] found ${patients.length} patients for demo data');
    
    final patientIds = patients.isEmpty
        ? ['demo-rashida', 'demo-nasrin', 'demo-karim', 'demo-fatima', 'demo-rahim', 'demo-salma']
        : patients.take(6).map((p) => p.id).toList();
    
    int seeded = 0;
    
    // ══════════════════════════════════════════════════════════════════════
    // SCENARIO 1: CRITICAL SLA BREACH — Child with severe pneumonia
    // 7 days overdue, not arrived at facility, emergency tier
    // ══════════════════════════════════════════════════════════════════════
    if (patientIds.isNotEmpty) {
      final referralId = 'ref-demo-critical-1';
      final createdAt = now.subtract(const Duration(days: 10));
      final dueArrival = createdAt.add(const Duration(days: 3)); // 3-day SLA
      final breachedAt = dueArrival; // Breached 7 days ago
      
      final r1 = Referral(
        id: referralId,
        patientId: patientIds[0],
        slaTier: SlaTier.emergency,
        state: ReferralStatus.created, // Still not arrived
        diagnosisCode: 'J18.9',
        diagnosisLabel: 'Severe pneumonia',
        priorityScore: 95,
        priorityLevel: 'critical',
        priorityDrivers: const [
          '🔴 SLA BREACHED +7d',
          '👶 Child under 5',
          '🚌 Transport barrier detected',
          '⚠️ Emergency referral',
        ],
        dueArrivalAt: dueArrival.millisecondsSinceEpoch,
        breachedSince: breachedAt.millisecondsSinceEpoch,
        escalationLevel: 2, // Escalated to supervisor
        createdAt: createdAt.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );
      await _referrals.upsertMany([r1]);
      
      // Timeline events
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:sk-visit:${createdAt.millisecondsSinceEpoch}',
        referralId: referralId,
        toState: ReferralStatus.created,
        occurredAt: createdAt.millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'SK home visit - child presenting with high fever, respiratory distress',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:referred:${createdAt.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.created,
        toState: ReferralStatus.created,
        occurredAt: createdAt.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'Referred to UHC Manikganj - Emergency pediatric care',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:breached:${breachedAt.millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.created,
        toState: ReferralStatus.breachedArrival,
        occurredAt: breachedAt.millisecondsSinceEpoch,
        actor: 'system',
        reason: 'SLA breached - Patient not arrived within 3-day window',
      ));
      seeded++;
    }
    
    // ══════════════════════════════════════════════════════════════════════
    // SCENARIO 2: FACILITY QUEUE DELAY — High-risk ANC waiting for OB review
    // Arrived but waiting 2 days for specialist, 1 day left on SLA
    // ══════════════════════════════════════════════════════════════════════
    if (patientIds.length > 1) {
      final referralId = 'ref-demo-delay-1';
      final createdAt = now.subtract(const Duration(days: 5));
      final arrivedAt = createdAt.add(const Duration(hours: 6));
      final dueTreatment = createdAt.add(const Duration(days: 6)); // 1 day left
      
      final r2 = Referral(
        id: referralId,
        patientId: patientIds[1],
        slaTier: SlaTier.urgent,
        state: ReferralStatus.arrived, // At facility, waiting
        diagnosisCode: 'O26.8',
        diagnosisLabel: 'High-risk ANC - Pre-eclampsia screening',
        priorityScore: 78,
        priorityLevel: 'high',
        priorityDrivers: const [
          '🟠 SLA: 1d left',
          '🤰 High-risk pregnancy',
          '⏳ OB queue delay: 48h',
          '🏥 At facility - awaiting review',
        ],
        dueArrivalAt: createdAt.add(const Duration(days: 1)).millisecondsSinceEpoch,
        dueTreatmentAt: dueTreatment.millisecondsSinceEpoch,
        escalationLevel: 1,
        createdAt: createdAt.millisecondsSinceEpoch,
        updatedAt: arrivedAt.millisecondsSinceEpoch,
      );
      await _referrals.upsertMany([r2]);
      
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:sk-visit:${createdAt.millisecondsSinceEpoch}',
        referralId: referralId,
        toState: ReferralStatus.created,
        occurredAt: createdAt.millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'ANC visit - elevated BP detected, protein in urine',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:referred:${createdAt.add(const Duration(hours: 2)).millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.created,
        toState: ReferralStatus.created,
        occurredAt: createdAt.add(const Duration(hours: 2)).millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'Referred to District Hospital - OB specialist evaluation',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:arrived:${arrivedAt.millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.created,
        toState: ReferralStatus.arrived,
        occurredAt: arrivedAt.millisecondsSinceEpoch,
        actor: 'facility',
        reason: 'Patient checked in at District Hospital',
      ));
      seeded++;
    }
    
    // ══════════════════════════════════════════════════════════════════════
    // SCENARIO 3: COMPLETED REFERRAL — Diabetic foot care completed
    // Discharged, prescription shared, follow-up scheduled
    // ══════════════════════════════════════════════════════════════════════
    if (patientIds.length > 2) {
      final referralId = 'ref-demo-completed-1';
      final createdAt = now.subtract(const Duration(days: 15));
      final arrivedAt = createdAt.add(const Duration(hours: 4));
      final treatedAt = createdAt.add(const Duration(days: 1));
      final dischargedAt = createdAt.add(const Duration(days: 2));
      
      final r3 = Referral(
        id: referralId,
        patientId: patientIds[2],
        slaTier: SlaTier.routine,
        state: ReferralStatus.closedRecovered,
        diagnosisCode: 'E11.621',
        diagnosisLabel: 'Diabetic foot ulcer - wound care',
        priorityScore: 15,
        priorityLevel: 'low',
        priorityDrivers: const [
          '🟢 Completed ✓',
          '📋 Follow-up in 7d',
          '💊 Prescription shared',
        ],
        dueArrivalAt: createdAt.add(const Duration(days: 7)).millisecondsSinceEpoch,
        dueTreatmentAt: createdAt.add(const Duration(days: 14)).millisecondsSinceEpoch,
        createdAt: createdAt.millisecondsSinceEpoch,
        updatedAt: dischargedAt.millisecondsSinceEpoch,
        closedAt: dischargedAt.millisecondsSinceEpoch,
      );
      await _referrals.upsertMany([r3]);
      
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:sk-visit:${createdAt.millisecondsSinceEpoch}',
        referralId: referralId,
        toState: ReferralStatus.created,
        occurredAt: createdAt.millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'Home visit - non-healing foot wound, requires debridement',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:arrived:${arrivedAt.millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.created,
        toState: ReferralStatus.arrived,
        occurredAt: arrivedAt.millisecondsSinceEpoch,
        actor: 'facility',
        reason: 'Checked in at UHC wound care clinic',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:treated:${treatedAt.millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.arrived,
        toState: ReferralStatus.treatmentStarted,
        occurredAt: treatedAt.millisecondsSinceEpoch,
        actor: 'facility',
        reason: 'Wound debrided, antibiotics prescribed, dressing applied',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:discharged:${dischargedAt.millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.treatmentStarted,
        toState: ReferralStatus.closedRecovered,
        occurredAt: dischargedAt.millisecondsSinceEpoch,
        actor: 'facility',
        reason: 'Discharged with wound care instructions, follow-up in 10 days',
      ));
      seeded++;
    }
    
    // ══════════════════════════════════════════════════════════════════════
    // SCENARIO 4: SLA WARNING — Urgent maternal case approaching deadline
    // In transit, 4 hours left on emergency SLA
    // ══════════════════════════════════════════════════════════════════════
    if (patientIds.length > 3) {
      final referralId = 'ref-demo-warning-1';
      final createdAt = now.subtract(const Duration(hours: 20));
      final dueArrival = createdAt.add(const Duration(hours: 24)); // 4h left
      
      final r4 = Referral(
        id: referralId,
        patientId: patientIds[3],
        slaTier: SlaTier.emergency,
        state: ReferralStatus.inTransit,
        diagnosisCode: 'O62.1',
        diagnosisLabel: 'Prolonged labor - emergency C-section evaluation',
        priorityScore: 88,
        priorityLevel: 'critical',
        priorityDrivers: const [
          '🟡 SLA: 4h remaining',
          '🚑 In transit to facility',
          '🤰 Active labor complications',
          '⚠️ Emergency maternal',
        ],
        dueArrivalAt: dueArrival.millisecondsSinceEpoch,
        escalationLevel: 1,
        createdAt: createdAt.millisecondsSinceEpoch,
        updatedAt: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
      );
      await _referrals.upsertMany([r4]);
      
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:sk-visit:${createdAt.millisecondsSinceEpoch}',
        referralId: referralId,
        toState: ReferralStatus.created,
        occurredAt: createdAt.millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'Emergency call - prolonged labor >18h, no progress',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:transit:${now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.created,
        toState: ReferralStatus.inTransit,
        occurredAt: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'Ambulance dispatched - ETA 2 hours to District Hospital',
      ));
      seeded++;
    }
    
    // ══════════════════════════════════════════════════════════════════════
    // SCENARIO 5: FOLLOW-UP OVERDUE — Post-treatment follow-up missed
    // Treatment completed but patient missed scheduled follow-up
    // ══════════════════════════════════════════════════════════════════════
    if (patientIds.length > 4) {
      final referralId = 'ref-demo-followup-1';
      final createdAt = now.subtract(const Duration(days: 21));
      final treatedAt = createdAt.add(const Duration(days: 3));
      final followUpDue = createdAt.add(const Duration(days: 14)); // 7 days overdue
      
      final r5 = Referral(
        id: referralId,
        patientId: patientIds[4],
        slaTier: SlaTier.routine,
        state: ReferralStatus.treatmentStarted, // Needs follow-up
        diagnosisCode: 'I10',
        diagnosisLabel: 'Hypertension - medication adjustment',
        priorityScore: 55,
        priorityLevel: 'medium',
        priorityDrivers: const [
          '📅 Follow-up 7d overdue',
          '💊 Medication compliance check needed',
          '📞 No response to reminders',
        ],
        dueArrivalAt: createdAt.add(const Duration(days: 2)).millisecondsSinceEpoch,
        dueTreatmentAt: followUpDue.millisecondsSinceEpoch,
        createdAt: createdAt.millisecondsSinceEpoch,
        updatedAt: treatedAt.millisecondsSinceEpoch,
      );
      await _referrals.upsertMany([r5]);
      
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:sk-visit:${createdAt.millisecondsSinceEpoch}',
        referralId: referralId,
        toState: ReferralStatus.created,
        occurredAt: createdAt.millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'Routine NCD screening - BP 180/110, requires evaluation',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:treated:${treatedAt.millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.arrived,
        toState: ReferralStatus.treatmentStarted,
        occurredAt: treatedAt.millisecondsSinceEpoch,
        actor: 'facility',
        reason: 'Started on Amlodipine 5mg, follow-up in 2 weeks',
      ));
      seeded++;
    }
    
    // ══════════════════════════════════════════════════════════════════════
    // SCENARIO 6: NEW REFERRAL — Just created, within SLA
    // Fresh referral, patient preparing to travel
    // ══════════════════════════════════════════════════════════════════════
    if (patientIds.length > 5) {
      final referralId = 'ref-demo-new-1';
      final createdAt = now.subtract(const Duration(hours: 3));
      
      final r6 = Referral(
        id: referralId,
        patientId: patientIds[5],
        slaTier: SlaTier.urgent,
        state: ReferralStatus.acknowledged,
        diagnosisCode: 'K35.8',
        diagnosisLabel: 'Acute appendicitis - surgical evaluation',
        priorityScore: 72,
        priorityLevel: 'high',
        priorityDrivers: const [
          '🟢 SLA: 45h remaining',
          '✅ Patient notified',
          '🚌 Transport being arranged',
        ],
        dueArrivalAt: createdAt.add(const Duration(days: 2)).millisecondsSinceEpoch,
        createdAt: createdAt.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );
      await _referrals.upsertMany([r6]);
      
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:sk-visit:${createdAt.millisecondsSinceEpoch}',
        referralId: referralId,
        toState: ReferralStatus.created,
        occurredAt: createdAt.millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'Home visit - acute abdominal pain, rebound tenderness',
      ));
      await _referrals.appendStatusEvent(ReferralStatusEventRow(
        id: '$referralId:ack:${now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch}',
        referralId: referralId,
        fromState: ReferralStatus.created,
        toState: ReferralStatus.acknowledged,
        occurredAt: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        actor: 'sk',
        reason: 'Family contacted, preparing for travel to UHC',
      ));
      seeded++;
    }
    
    _changes.value++;
    return seeded;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Extended Methods for Full Referral Flow
  // ══════════════════════════════════════════════════════════════════════════

  /// Escalate a referral to the next level supervisor.
  /// Returns true if successful.
  Future<bool> escalate({
    required String referralId,
    String? reason,
    String actor = 'sk',
  }) async {
    final current = await _referrals.byId(referralId);
    if (current == null) return false;

    final newLevel = current.escalationLevel + 1;
    final now = _clock();

    // Update local state
    final updated = current.copyWith(
      escalationLevel: newLevel,
      updatedAt: now.millisecondsSinceEpoch,
    );
    await _referrals.upsertMany([updated]);

    // Log the escalation event
    await _referrals.appendStatusEvent(ReferralStatusEventRow(
      id: '$referralId:escalate:${now.millisecondsSinceEpoch}',
      referralId: referralId,
      fromState: current.state,
      toState: current.state, // State doesn't change, only level
      occurredAt: now.millisecondsSinceEpoch,
      actor: actor,
      reason: reason ?? 'Escalated to level $newLevel',
    ));

    _changes.value++;
    return true;
  }

  /// Bulk escalate multiple referrals.
  Future<int> bulkEscalate({
    required List<String> referralIds,
    String? reason,
    String actor = 'sk',
  }) async {
    int count = 0;
    for (final id in referralIds) {
      final success = await escalate(
        referralId: id,
        reason: reason,
        actor: actor,
      );
      if (success) count++;
    }
    return count;
  }

  /// Bulk close multiple referrals.
  Future<int> bulkClose({
    required List<String> referralIds,
    ReferralStatus toState = ReferralStatus.closedRecovered,
    String? reason,
    String actor = 'sk',
  }) async {
    int count = 0;
    for (final id in referralIds) {
      await transition(
        referralId: id,
        to: toState,
        reason: reason ?? 'Bulk closed by $actor',
        actor: actor,
      );
      count++;
    }
    return count;
  }

  /// Get referral by ID.
  Future<Referral?> byId(String referralId) {
    return _referrals.byId(referralId);
  }

  /// Get all referrals for a patient.
  Future<List<Referral>> forPatient(String patientId) {
    return _referrals.forPatient(patientId);
  }

  /// Search referrals by text (patient name, diagnosis, etc.).
  /// This is a client-side filter on loaded referrals.
  Future<List<Referral>> search({
    required String query,
    SlaPriority? levelFilter,
    int limit = 200,
  }) async {
    final all = await load(levelFilter: levelFilter, limit: limit);
    if (query.isEmpty) return all;

    final lowerQuery = query.toLowerCase();
    return all.where((r) {
      final diagnosis = r.diagnosisLabel?.toLowerCase() ?? '';
      final patientId = r.patientId.toLowerCase();
      return diagnosis.contains(lowerQuery) || patientId.contains(lowerQuery);
    }).toList();
  }

  /// Watch for any changes to referrals. Returns a listenable that triggers
  /// whenever referral data changes.
  Listenable watchChanges() => _changes;

  /// Get count of referrals by status.
  Future<Map<String, int>> countsByStatus() async {
    final all = await _referrals.allOpen();
    final counts = <String, int>{};
    
    for (final r in all) {
      final key = r.state.wireTag;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    
    return counts;
  }

  /// Check if there are any critical referrals needing attention.
  Future<bool> hasCriticalReferrals() async {
    final count = await _referrals.countByLevel(SlaPriority.critical);
    return count > 0;
  }

  /// Get the most urgent referral (highest priority, earliest breach).
  Future<Referral?> getMostUrgent() async {
    final list = await load(limit: 1);
    return list.isEmpty ? null : list.first;
  }

  /// Force refresh of all SLA calculations.
  Future<void> refreshAllSla() async {
    await recomputeAllAfterSync();
    _changes.value++;
  }
}
