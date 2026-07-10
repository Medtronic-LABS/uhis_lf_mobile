/// On-device aggregation service for the AI Mission Dashboard.
///
/// Pure Dart — no Flutter binding. Computes:
/// - [MissionBrief] from worklist + referrals + follow-ups
/// - [MissionQueueItem] list ranked by composite priority
/// - [MissionProgress] from visit completion tracking
/// - [HouseholdOpportunity] from household member analysis
///
/// Reuses existing [RiskScoringService], [PriorityScorer], [SlaEvaluator].
/// Weights are named constants for easy tuning (DRY principle).
///
/// Spec: AI Mission Dashboard (Screen 2).
library;

import '../api/cql_api_service.dart';
import '../models/dashboard_tier.dart';
import '../models/mission_brief.dart';
import '../models/mission_queue_item.dart';
import '../models/programme.dart';
import '../models/risk.dart';
import '../models/sla.dart';
import '../models/worklist_entry.dart';
import '../models/referral.dart';
import 'mission_pregnancy_facts.dart';

/// Input data for computing mission brief and queue.
class MissionInputData {
  const MissionInputData({
    this.worklistEntries = const [],
    this.referrals = const [],
    this.referralAssessments = const {},
    this.followUps = const [],
    this.completedVisitsToday = 0,
    this.householdMembers = const {},
    this.cqlResults = const {},
    this.householdNumbersById = const {},
    this.patientHouseholdsById = const {},
    this.pregnancyByPatientId = const {},
    this.patientsOnTreatment = const {},
    this.patientsLtfu = const {},
    this.unsuccessfulAttemptsByPatientId = const {},
    this.patientsEverReferred = const {},
    this.agesByPatientId = const {},
    this.disabilityByPatientId = const {},
    this.lastUpdatedByPatientId = const {},
    this.hiddenPatientIds = const {},
    this.completedTodayPatientIds = const {},
    this.tbAtRiskPatientIds = const {},
    this.ncdOverduePatientIds = const {},
    this.redFlagPatientIds = const {},
    this.pregnantPatientIds = const {},
    this.householdHeadPatientIds = const {},
    this.neonatePatientIds = const {},
    this.youngInfantPatientIds = const {},
    this.referralArrivalPendingPatientIds = const {},
    this.villageNamesById = const {},
  });

  /// All patients on the worklist.
  final List<WorklistEntry> worklistEntries;

  /// All active referrals.
  final List<Referral> referrals;

  /// Priority assessments keyed by referral ID.
  final Map<String, PriorityAssessment> referralAssessments;

  /// Follow-ups due.
  final List<FollowUpDue> followUps;

  /// Number of visits completed today.
  final int completedVisitsToday;

  /// Household members grouped by household ID for opportunity detection.
  /// Key: household ID, Value: list of (memberId, name, programmes, dueServices)
  final Map<String, List<HouseholdMemberData>> householdMembers;

  /// CQL risk results keyed by patient ID.
  /// When populated, these take precedence over local risk scoring.
  final Map<String, CqlRiskResult> cqlResults;

  /// Household display number (`'12'`, `'07'`) keyed by household UUID.
  /// Used so queue items render `House #12` without a per-row DAO lookup.
  final Map<String, String> householdNumbersById;

  /// Household UUID keyed by patient ID. Lets referral / follow-up items —
  /// which only know the patient — resolve into [householdNumbersById].
  final Map<String, String> patientHouseholdsById;

  /// Pregnancy / postpartum snapshot keyed by patient ID. Drives CRITICAL
  /// drivers (`pnc-window`, `anc-near-term`, `delivery-complication`,
  /// `pnc-illness`, `hi-risk-anc-gap`). Empty when no `pregnancyInfos[]`
  /// row exists for the patient — callers should treat absence as
  /// [PregnancyFacts.empty].
  final Map<String, PregnancyFacts> pregnancyByPatientId;

  /// Patient IDs with at least one `treatmentDetails[]` row in the bundle.
  /// Drives the `ncd-drift` OVERDUE-min driver and the on-treatment
  /// composite-score bonus.
  final Set<String> patientsOnTreatment;

  /// Patient IDs with `followUps[].type == LOST_TO_FOLLOW_UP`. Drives the
  /// `ltfu-streak` OVERDUE-min driver. A patient may also reach LTFU via
  /// the `unsuccessfulAttempts > 2` rule (see [unsuccessfulAttemptsByPatientId]).
  final Set<String> patientsLtfu;

  /// Highest observed `followUps[].unsuccessfulAttempts` per patient.
  /// Drives `ltfu-streak` promotion and the composite-score
  /// `min(attempts, 5) × 5` term.
  final Map<String, int> unsuccessfulAttemptsByPatientId;

  /// Patient IDs that have ever had a `followUps[].referredSiteId` set.
  /// Drives the ever-referred composite-score bonus (care-continuity).
  final Set<String> patientsEverReferred;

  /// Patient age in years, keyed by patient ID. Pre-computed at sync time
  /// so the service doesn't reparse `dateOfBirth`. Null when DOB is missing.
  final Map<String, int> agesByPatientId;

  /// Disability flag keyed by patient ID — `true` when
  /// `member.disability != null && member.disability != 'absent'`. Drives
  /// the `child-disability` OVERDUE-min driver (when paired with age < 5)
  /// and the composite-score vulnerability bonus.
  final Map<String, bool> disabilityByPatientId;

  /// Epoch-millis of the last record update per patient. Drives the
  /// stale-record composite-score bonus (`(now − lastUpdated).days > 30`).
  final Map<String, int> lastUpdatedByPatientId;

  /// Patients hidden from the queue unconditionally — `member.isActive == false`
  /// OR `member.deceasedReason != null`.
  final Set<String> hiddenPatientIds;

  /// Patients with a follow-up marked completed today — hidden from today's
  /// queue but not from the underlying patient list.
  final Set<String> completedTodayPatientIds;

  /// Patients on TB treatment whose contact attempts indicate default risk
  /// (`followUps[].encounterType == TB` AND (`unsuccessfulAttempts > 0` OR
  /// overdue)). Drives the `tb-default-risk` OVERDUE-min driver.
  final Set<String> tbAtRiskPatientIds;

  /// Patients on NCD treatment whose next BP/BG assessment date is in the
  /// past. Drives the `ncd-drift` OVERDUE-min driver.
  final Set<String> ncdOverduePatientIds;

  /// Patients flagged red by the on-device risk engine
  /// (`Patient.redFlag == true`). Drives the `red-flag` CRITICAL driver.
  /// Separate from `Band.band1` because the spec lets either fire.
  final Set<String> redFlagPatientIds;

  /// Patients with `member.isPregnant == true`. Drives the pregnancy
  /// composite-score bonus when no pregnancyInfos[] row exists yet.
  final Set<String> pregnantPatientIds;

  /// Patients flagged as household head. Drives the cascade-impact
  /// composite-score bonus.
  final Set<String> householdHeadPatientIds;

  /// Patients aged under 28 days (DOB-derived at sync time). Drives the
  /// `neonate` CRITICAL driver. Age in years is too coarse — Phase 2 syncs
  /// resolve DOB once and bucket the patient here.
  final Set<String> neonatePatientIds;

  /// Patients aged 28–60 days. Drives the `young-infant` CRITICAL driver.
  /// Mutually exclusive with [neonatePatientIds].
  final Set<String> youngInfantPatientIds;

  /// Patients with a community-side REFERRED follow-up that has not yet
  /// recorded facility arrival/close-out for ≥3 days. Drives the
  /// `referral-arrival-pending` OVERDUE-min driver — surfaces patients the
  /// SK sent to facility but who may have never made it (PPH / sepsis /
  /// TB-default risk window).
  final Set<String> referralArrivalPendingPatientIds;

  /// Village / sub-village id → display name, pre-resolved from
  /// [UserHierarchyService]. Used so queue items show a human-readable
  /// location instead of the raw numeric ID.
  final Map<String, String> villageNamesById;

  /// True if CQL results are available for scoring.
  bool get hasCqlResults => cqlResults.isNotEmpty;
}

/// Simplified member data for household opportunity detection.
class HouseholdMemberData {
  const HouseholdMemberData({
    required this.memberId,
    required this.name,
    this.role,
    this.programmes = const {},
    this.dueServices = const [],
    this.phoneNumber,
  });

  final String memberId;
  final String name;
  final String? role;
  final Set<Programme> programmes;
  final List<String> dueServices;
  final String? phoneNumber;
}

/// On-device mission dashboard aggregation service.
class MissionDashboardService {
  const MissionDashboardService();

  // ── Weights for queue ranking ─────────────────────────────────────────────
  static const int _wSlaBreached = 100;
  static const int _wCriticalRisk = 80;
  static const int _wChildUnder5 = 30;
  static const int _wPregnancy = 25;
  static const int _wOverduePerDay = 5;
  static const int _wOverdueCap = 50;
  static const int _wHighRisk = 40;
  static const int _wMediumRisk = 20;
  static const int _wReferral = 15;
  static const int _wFollowUp = 10;

  // ── Workload estimation ───────────────────────────────────────────────────
  /// Average minutes per visit for workload estimation.
  static const int _avgVisitMinutes = 25;

  // ── Priority thresholds ───────────────────────────────────────────────────
  static const int _criticalThreshold = 80;
  static const int _highThreshold = 50;
  static const int _mediumThreshold = 25;

  /// Compute the AI daily brief from input data.
  MissionBrief computeBrief(MissionInputData data) {
    final now = DateTime.now();

    // Count child danger cases (IMCI + urgent risk band)
    final childDangerCases = data.worklistEntries.where((e) =>
        e.programmes.contains(Programme.imci) && e.isUrgent).length;

    // Count SLA breached referrals
    final slaBreached = data.referralAssessments.values
        .where((a) => a.level == SlaPriority.critical)
        .length;

    // Count ANC follow-ups (ANC programme patients due for visit)
    final ancFollowUps = data.worklistEntries.where((e) {
      if (!e.programmes.contains(Programme.anc)) return false;
      final due = e.nextDueAt;
      return due != null && due.isBefore(now.add(const Duration(days: 1)));
    }).length;

    // Count high-risk diabetic patients (NCD + band1/band2)
    final diabeticHighRisk = data.worklistEntries.where((e) =>
        e.programmes.contains(Programme.ncd) &&
        (e.band == Band.band1 || e.band == Band.band2)).length;

    // Total visits = worklist + due follow-ups
    final totalVisits = data.worklistEntries.length + data.followUps.length;

    // Expected workload in hours
    final workloadHours = (totalVisits * _avgVisitMinutes) / 60.0;

    // Determine priority level
    final priorityLevel = _computeDayPriority(
      childDangerCases: childDangerCases,
      slaBreached: slaBreached,
      ancFollowUps: ancFollowUps,
      diabeticHighRisk: diabeticHighRisk,
    );

    // Build risk factors list
    final riskFactors = _buildRiskFactors(data);

    // Estimate distance: ~0.5 km average between households in rural areas
    final estimatedDistanceKm = totalVisits * 0.5;

    return MissionBrief(
      visitsRecommended: totalVisits,
      childDangerCases: childDangerCases,
      slaBreachedReferrals: slaBreached,
      ancFollowUps: ancFollowUps,
      highRiskDiabeticPatients: diabeticHighRisk,
      expectedWorkloadHours: workloadHours,
      estimatedDistanceKm: estimatedDistanceKm,
      priorityLevel: priorityLevel,
      riskFactors: riskFactors,
      computedAt: now,
    );
  }

  /// Compute prioritized mission queue from input data.
  @Deprecated('Use computeTieredQueue for the 5-tier model')
  List<MissionQueueItem> computeQueue(MissionInputData data, {int? limit}) {
    final items = <MissionQueueItem>[];
    final now = DateTime.now();

    // Add worklist entries
    for (final entry in data.worklistEntries) {
      items.add(_worklistToQueueItem(entry, now, data));
    }

    // Add referrals
    for (final referral in data.referrals) {
      final assessment = data.referralAssessments[referral.id];
      items.add(_referralToQueueItem(referral, assessment, now, data));
    }

    // Add follow-ups
    for (final followUp in data.followUps) {
      items.add(_followUpToQueueItem(followUp, now, data));
    }

    // Sort by priority score descending
    items.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

    // Dedupe by patientId — the same patient may appear via a worklist entry,
    // a referral, and a follow-up. Keep the highest-scoring representation
    // (already at the front of `items` after the sort above). Items without
    // a patientId (e.g. household opportunities) pass through unchanged so
    // they're not collapsed with each other.
    final seen = <String>{};
    final deduped = <MissionQueueItem>[];
    for (final item in items) {
      final pid = item.patientId;
      if (pid != null && pid.isNotEmpty) {
        if (!seen.add(pid)) continue;
      }
      deduped.add(item);
    }

    // Apply limit if specified
    if (limit != null && deduped.length > limit) {
      return deduped.sublist(0, limit);
    }

    return deduped;
  }

  /// Compute mission progress from input data.
  MissionProgress computeProgress(MissionInputData data) {
    final totalVisits = data.worklistEntries.length + data.followUps.length;
    final completed = data.completedVisitsToday;
    final remaining = totalVisits - completed;
    final remainingMinutes = remaining * _avgVisitMinutes;

    // Predict completion time
    String? predictedTime;
    if (remaining > 0 && completed > 0) {
      final now = DateTime.now();
      final completionTime = now.add(Duration(minutes: remainingMinutes));
      predictedTime = _formatTime(completionTime);
    }

    return MissionProgress(
      completedVisits: completed,
      totalVisits: totalVisits,
      estimatedRemainingMinutes: remainingMinutes,
      predictedCompletionTime: predictedTime,
    );
  }

  /// Detect household opportunities (multiple services in one visit).
  List<HouseholdOpportunity> computeHouseholdOpportunities(
    MissionInputData data,
  ) {
    final opportunities = <HouseholdOpportunity>[];

    for (final entry in data.householdMembers.entries) {
      final householdId = entry.key;
      final members = entry.value;

      // Count members with due services
      final membersWithServices =
          members.where((m) => m.dueServices.isNotEmpty).toList();

      if (membersWithServices.length >= 2) {
        // Multiple services available in one household visit
        final memberServices = <String, String>{};
        for (final member in membersWithServices) {
          final role = member.role ?? 'Member';
          final service = member.dueServices.isNotEmpty
              ? member.dueServices.first
              : 'Check-up';
          memberServices[role] = service;
        }

        opportunities.add(HouseholdOpportunity(
          householdId: householdId,
          householdNumber: int.tryParse(householdId.split('-').last) ?? 0,
          memberServices: memberServices,
        ));
      }
    }

    return opportunities;
  }

  /// Get critical alerts (items requiring immediate attention).
  List<MissionQueueItem> getCriticalAlerts(List<MissionQueueItem> queue) {
    return queue.where((item) => item.isCritical).toList();
  }

  /// Compute referral summary counts.
  ReferralSummary computeReferralSummary(MissionInputData data) {
    final active = data.referrals
        .where((r) =>
            r.state != ReferralStatus.closedRecovered &&
            r.state != ReferralStatus.closedDeceased)
        .length;

    final breached = data.referralAssessments.values
        .where((a) => a.level == SlaPriority.critical)
        .length;

    final awaitingReview = data.referrals
        .where((r) =>
            r.state == ReferralStatus.arrived ||
            r.state == ReferralStatus.acknowledged)
        .length;

    final completed = data.referrals
        .where((r) =>
            r.state == ReferralStatus.closedRecovered ||
            r.state == ReferralStatus.closedDeceased)
        .length;

    // Find top breached referral
    MissionQueueItem? topBreach;
    if (breached > 0) {
      for (final referral in data.referrals) {
        final assessment = data.referralAssessments[referral.id];
        if (assessment?.level == SlaPriority.critical) {
          topBreach = _referralToQueueItem(
            referral,
            assessment,
            DateTime.now(),
            data,
          );
          break;
        }
      }
    }

    return ReferralSummary(
      active: active,
      breached: breached,
      awaitingReview: awaitingReview,
      completed: completed,
      topBreachedReferral: topBreach,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  DayPriorityLevel _computeDayPriority({
    required int childDangerCases,
    required int slaBreached,
    required int ancFollowUps,
    required int diabeticHighRisk,
  }) {
    if (childDangerCases > 0 || slaBreached > 0) {
      return DayPriorityLevel.critical;
    }
    if (ancFollowUps >= 3 || diabeticHighRisk >= 2) {
      return DayPriorityLevel.high;
    }
    if (ancFollowUps > 0 || diabeticHighRisk > 0) {
      return DayPriorityLevel.medium;
    }
    return DayPriorityLevel.low;
  }

  List<String> _buildRiskFactors(MissionInputData data) {
    final factors = <String>[];

    // Find specific cases to mention
    for (final assessment in data.referralAssessments.values) {
      if (assessment.level == SlaPriority.critical) {
        final daysOverdue = assessment.drivers.contains('sla-breached')
            ? _extractDaysFromDrivers(assessment.drivers)
            : null;
        if (daysOverdue != null && daysOverdue > 0) {
          factors.add('Referral overdue by $daysOverdue days');
        }
      }
    }

    // Check for waiting referrals
    final waitingCount = data.referrals
        .where((r) => r.state == ReferralStatus.arrived)
        .length;
    if (waitingCount > 0) {
      factors.add('$waitingCount patient(s) waiting for facility review');
    }

    // Check for missed follow-ups
    final missedFollowUps = data.worklistEntries
        .where((e) => e.reasons.any((r) => r.contains('missed')))
        .length;
    if (missedFollowUps > 0) {
      factors.add('$missedFollowUps patient(s) missed follow-up');
    }

    return factors;
  }

  int? _extractDaysFromDrivers(List<String> drivers) {
    for (final driver in drivers) {
      if (driver.startsWith('overdue:')) {
        return int.tryParse(driver.split(':').last);
      }
    }
    return null;
  }

  MissionQueueItem _worklistToQueueItem(
    WorklistEntry entry,
    DateTime now,
    MissionInputData data,
  ) {
    int score = 0;
    final drivers = <String>[];

    // Spec §2.8 band contribution. Band 1 = Severe → critical-risk driver.
    // Surface specific danger-sign / stroke / eclampsia drivers when the
    // reasons list carries them so the card border rule (§2.6) can paint
    // red ONLY for clinical danger signs / CCE alerts — not for band1 cards
    // that landed on labs alone.
    final reasonText = entry.reasons.join(' ').toLowerCase();
    if (reasonText.contains('danger-sign')) drivers.add('danger-sign');
    if (reasonText.contains('stroke-sign')) drivers.add('stroke-sign');
    if (reasonText.contains('eclampsia')) drivers.add('eclampsia');

    switch (entry.band) {
      case Band.band1:
        score += _wCriticalRisk;
        drivers.add('band1-severe');
        break;
      case Band.band2:
        score += _wHighRisk;
        drivers.add('band2-moderate');
        break;
      case Band.band3:
        score += _wMediumRisk;
        drivers.add('band3-mild');
        break;
      case Band.band4:
        break;
    }

    // Age contribution
    if (entry.age != null && entry.age! < 5) {
      score += _wChildUnder5;
      drivers.add('child-under-5');
    }

    // Programme contribution
    if (entry.programmes.contains(Programme.anc)) {
      score += _wPregnancy;
      drivers.add('pregnancy');
    }

    // Overdue contribution
    if (entry.nextDueAt != null) {
      final overdueDays = now.difference(entry.nextDueAt!).inDays;
      if (overdueDays > 0) {
        final overdueScore = (overdueDays * _wOverduePerDay).clamp(0, _wOverdueCap);
        score += overdueScore;
        drivers.add('overdue:$overdueDays');
      }
    }

    final priority = _scoreToPriority(score);
    final aiInsight = _buildAiInsight(drivers);
    final reason = entry.reasons.isNotEmpty ? entry.reasons.first : 'Scheduled visit';

    return MissionQueueItem(
      id: entry.patientId,
      type: MissionItemType.patientVisit,
      priority: priority,
      priorityScore: score,
      patientName: entry.displayName,
      patientId: entry.patientId,
      householdId: entry.householdNo,
      householdNumber: data.householdNumbersById[entry.householdNo],
      age: entry.age,
      phoneNumber: entry.phoneNumber,
      village: entry.householdName ?? entry.villageName ?? entry.villageId,
      programmes: entry.programmes,
      reason: reason,
      daysOverdue: entry.nextDueAt != null
          ? now.difference(entry.nextDueAt!).inDays.clamp(0, 999)
          : null,
      dueAt: entry.nextDueAt,
      aiInsight: aiInsight,
      aiDrivers: drivers,
      availableActions: [
        MissionAction.openCase,
        MissionAction.scheduleVisit,
        MissionAction.callFamily,
      ],
    );
  }

  MissionQueueItem _referralToQueueItem(
    Referral referral,
    PriorityAssessment? assessment,
    DateTime now,
    MissionInputData data,
  ) {
    int score = assessment?.score ?? 0;
    final drivers = List<String>.from(assessment?.drivers ?? []);

    // Add referral base weight
    score += _wReferral;
    if (!drivers.contains('referral')) {
      drivers.add('referral');
    }

    // SLA breach adds critical weight
    if (assessment?.level == SlaPriority.critical) {
      if (!drivers.contains('sla-breached')) {
        score += _wSlaBreached;
        drivers.add('sla-breached');
      }
    }

    final priority = assessment != null
        ? MissionPriority.fromSlaPriority(assessment.level)
        : _scoreToPriority(score);

    final aiInsight = _buildAiInsight(drivers);
    // createdAt is epoch ms, convert to DateTime for calculation
    final createdDateTime = DateTime.fromMillisecondsSinceEpoch(referral.createdAt);
    final daysOverdue = now.difference(createdDateTime).inDays;

    final hhId = data.patientHouseholdsById[referral.patientId];
    return MissionQueueItem(
      id: referral.id,
      type: MissionItemType.referral,
      priority: priority,
      priorityScore: score,
      patientName: referral.patientId.length > 8
          ? 'Patient ${referral.patientId.substring(0, 8)}'
          : 'Patient ${referral.patientId}', // Handle short IDs
      patientId: referral.patientId,
      referralId: referral.id,
      householdId: hhId,
      householdNumber: hhId != null ? data.householdNumbersById[hhId] : null,
      village: referral.villageId != null
          ? (data.villageNamesById[referral.villageId!] ?? referral.villageId)
          : null,
      programmes: const {}, // Referrals don't have programme context here
      reason: referral.diagnosisLabel ?? 'Referral',
      daysOverdue: daysOverdue > 0 ? daysOverdue : null,
      dueAt: createdDateTime,
      aiInsight: aiInsight,
      aiDrivers: drivers,
      slaTier: referral.slaTier,
      diagnosisLabel: referral.diagnosisLabel,
      availableActions: [
        MissionAction.openReferral,
        MissionAction.callFamily,
        MissionAction.callFacility,
        MissionAction.locate,
      ],
    );
  }

  MissionQueueItem _followUpToQueueItem(
    FollowUpDue followUp,
    DateTime now,
    MissionInputData data,
  ) {
    int score = _wFollowUp;
    final drivers = <String>['follow-up'];

    // Overdue contribution
    final daysUntil = followUp.daysUntilDue(now);
    if (daysUntil < 0) {
      final overdueScore = (-daysUntil * _wOverduePerDay).clamp(0, _wOverdueCap);
      score += overdueScore;
      drivers.add('overdue:${-daysUntil}');
    }

    final priority = _scoreToPriority(score);
    final aiInsight = _buildAiInsight(drivers);

    final hhId = data.patientHouseholdsById[followUp.patientId];
    return MissionQueueItem(
      id: followUp.id,
      type: MissionItemType.followUp,
      priority: priority,
      priorityScore: score,
      patientName: followUp.patientName,
      patientId: followUp.patientId,
      householdId: hhId,
      householdNumber: hhId != null ? data.householdNumbersById[hhId] : null,
      reason: followUp.reason ?? 'Follow-up due',
      daysOverdue: daysUntil < 0 ? -daysUntil : null,
      dueAt: followUp.dueAt,
      aiInsight: aiInsight,
      aiDrivers: drivers,
      phoneNumber: followUp.phoneNumber,
      availableActions: [
        MissionAction.openCase,
        MissionAction.scheduleVisit,
        MissionAction.callFamily,
      ],
    );
  }

  MissionPriority _scoreToPriority(int score) {
    if (score >= _criticalThreshold) return MissionPriority.critical;
    if (score >= _highThreshold) return MissionPriority.high;
    if (score >= _mediumThreshold) return MissionPriority.medium;
    return MissionPriority.low;
  }

  String _buildAiInsight(List<String> drivers) {
    if (drivers.isEmpty) return 'Scheduled for regular check-up.';

    final insights = <String>[];
    for (final driver in drivers) {
      final insight = _driverToInsight(driver);
      if (insight != null && !insights.contains(insight)) {
        insights.add(insight);
      }
    }

    if (insights.isEmpty) return 'Requires attention.';
    return insights.take(3).join(' ');
  }

  String? _driverToInsight(String driver) {
    final parts = driver.split(':');
    final key = parts[0];

    switch (key) {
      case 'sla-breached':
        return 'SLA breached — immediate action required.';
      case 'child-under-5':
        return 'Child under 5 — higher priority.';
      case 'pregnancy':
        return 'High-risk pregnancy.';
      case 'urgent-risk':
        return 'Urgent clinical risk identified.';
      case 'high-risk':
        return 'High clinical risk.';
      case 'overdue':
        final days = parts.length > 1 ? parts[1] : '';
        return days.isNotEmpty ? 'Overdue by $days days.' : 'Visit overdue.';
      case 'no-arrival':
        return 'Patient never arrived at facility.';
      case 'emergency-dx':
        return 'Emergency diagnosis.';
      case 'missed-follow-up':
        return 'Missed scheduled follow-up.';
      case 'referral':
        return 'Active referral requires tracking.';
      case 'follow-up':
        return 'Post-discharge follow-up due.';
      default:
        return null;
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMinute $period';
  }

  // ─── 5-tier classifier ─────────────────────────────────────────────────────
  // Spec: leapfrog-setup/designs/dashboard-prioritization-impl.md
  //
  // Composite-score weights drive intra-tier ordering only — strong drivers
  // promote a candidate to its tier *before* the score is consulted.
  static const int _csOverduePerDay = 3;
  static const int _csOverdueCap = 30;
  static const int _csAttemptsPerTry = 5;
  static const int _csAttemptsCap = 5;
  static const int _csUnderOneYear = 25;
  static const int _csUnderFive = 12;
  static const int _csElderly = 6;
  static const int _csPregnant = 10;
  static const int _csPregnancySnapshot = 4;
  static const int _csOnTreatment = 8;
  static const int _csEverReferred = 5;
  static const int _csHouseholdHead = 3;
  static const int _csDisability = 6;
  static const int _csStaleRecord = 5;
  static const int _csStaleThresholdDays = 30;
  static const int _csUpcomingPenaltyCap = 14;
  static const int _ltfuAttemptThreshold = 2;
  static const int _elderlyAgeThreshold = 60;
  static const int _childUnder5AgeThreshold = 5;

  /// Composite intra-tier score. Higher is more urgent. Spec formula:
  ///   + min(daysOverdue, 30)             × 3
  ///   + min(unsuccessfulAttempts, 5)     × 5
  ///   + (age < 1 ? 25 : 0)
  ///   + (age < 5 ? 12 : 0)
  ///   + (age ≥ 60 ? 6 : 0)
  ///   + (isPregnant ? 10 : 0)
  ///   + (pregnancySnapshot present ? 4 : 0)
  ///   + (onTreatment ? 8 : 0)
  ///   + (everReferred ? 5 : 0)
  ///   + (householdHead ? 3 : 0)
  ///   + (disability ? 6 : 0)
  ///   + (lastUpdated stale > 30d ? 5 : 0)
  ///   − (daysUntilDue > 0 ? min(daysUntilDue, 14) : 0)
  int _compositeScore({
    required String patientId,
    required int? age,
    required DateTime? dueAt,
    required MissionInputData input,
    required DateTime now,
  }) {
    int score = 0;

    if (dueAt != null) {
      final today = _atStartOfDay(now);
      final due = _atStartOfDay(dueAt);
      final daysOverdue = today.difference(due).inDays;
      if (daysOverdue > 0) {
        final clamped =
            daysOverdue > _csOverdueCap ? _csOverdueCap : daysOverdue;
        score += clamped * _csOverduePerDay;
      } else if (daysOverdue < 0) {
        final daysUntilDue = -daysOverdue;
        final clamped = daysUntilDue > _csUpcomingPenaltyCap
            ? _csUpcomingPenaltyCap
            : daysUntilDue;
        score -= clamped;
      }
    }

    final attempts = input.unsuccessfulAttemptsByPatientId[patientId] ?? 0;
    if (attempts > 0) {
      final clamped =
          attempts > _csAttemptsCap ? _csAttemptsCap : attempts;
      score += clamped * _csAttemptsPerTry;
    }

    if (age != null) {
      if (age < 1) score += _csUnderOneYear;
      if (age < _childUnder5AgeThreshold) score += _csUnderFive;
      if (age >= _elderlyAgeThreshold) score += _csElderly;
    }

    if (input.pregnantPatientIds.contains(patientId)) score += _csPregnant;
    if (input.pregnancyByPatientId.containsKey(patientId)) {
      score += _csPregnancySnapshot;
    }
    if (input.patientsOnTreatment.contains(patientId)) score += _csOnTreatment;
    if (input.patientsEverReferred.contains(patientId)) {
      score += _csEverReferred;
    }
    if (input.householdHeadPatientIds.contains(patientId)) {
      score += _csHouseholdHead;
    }
    if (input.disabilityByPatientId[patientId] == true) {
      score += _csDisability;
    }

    final lastUpdated = input.lastUpdatedByPatientId[patientId];
    if (lastUpdated != null) {
      final ageDays =
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastUpdated)).inDays;
      if (ageDays > _csStaleThresholdDays) score += _csStaleRecord;
    }

    return score;
  }

  /// Returns an inferred next-due date for a patient whose follow-up records
  /// have no `dueAt` — derived from `lastVisitAt` + the programme's standard
  /// recall interval. Returns null if there is no last-visit date or no
  /// programme with a known interval.
  DateTime? _inferDueAt(WorklistEntry entry) {
    final last = entry.lastVisitAt;
    if (last == null) return null;
    int? intervalDays;
    if (entry.programmes.contains(Programme.anc) ||
        entry.programmes.contains(Programme.pnc)) {
      intervalDays = 14;
    } else if (entry.programmes.contains(Programme.tb)) {
      intervalDays = 7;
    } else if (entry.programmes.contains(Programme.imci)) {
      intervalDays = 7;
    } else if (entry.programmes.contains(Programme.ncd)) {
      intervalDays = 30;
    } else if (entry.programmes.contains(Programme.epi)) {
      intervalDays = 30;
    } else if (entry.programmes.contains(Programme.familyPlanning)) {
      intervalDays = 90;
    }
    if (intervalDays == null) return null;
    return last.add(Duration(days: intervalDays));
  }

  /// Classify a candidate into a [DashboardTier] and return its driver tags.
  /// Returns `null` when hide rules apply (inactive / deceased / completed
  /// today) so the caller drops the candidate without counting it against
  /// the top-N cap.
  ({DashboardTier tier, List<String> drivers})? _classify({
    required String patientId,
    required int? age,
    required Band? band,
    required DateTime? dueAt,
    required MissionInputData input,
    required DateTime now,
  }) {
    if (input.hiddenPatientIds.contains(patientId)) return null;
    if (input.completedTodayPatientIds.contains(patientId)) return null;

    final drivers = <String>[];
    final preg = input.pregnancyByPatientId[patientId];

    // ── CRITICAL: strong drivers (user-locked) ──
    if (input.redFlagPatientIds.contains(patientId) ||
        band == Band.band1) {
      drivers.add('red-flag');
    }
    if (preg != null &&
        preg.highRiskPregnantWoman &&
        preg.hasGapsInAnc) {
      drivers.add('hi-risk-anc-gap');
    }

    // ── CRITICAL: medical-lens refinements ──
    if (input.neonatePatientIds.contains(patientId)) {
      drivers.add('neonate');
    } else if (input.youngInfantPatientIds.contains(patientId)) {
      drivers.add('young-infant');
    }
    if (preg?.isPostpartumWindow == true) drivers.add('pnc-window');
    if (preg?.isNearTermAnc == true) drivers.add('anc-near-term');
    if (preg?.hadDeliveryComplications == true) {
      drivers.add('delivery-complication');
    }
    if (preg?.hasPncIllness == true) drivers.add('pnc-illness');

    if (drivers.isNotEmpty) {
      return (tier: DashboardTier.critical, drivers: drivers);
    }

    // ── OVERDUE-minimum drivers ──
    final attempts = input.unsuccessfulAttemptsByPatientId[patientId] ?? 0;
    if (input.patientsLtfu.contains(patientId) ||
        attempts > _ltfuAttemptThreshold) {
      drivers.add('ltfu-streak');
    }
    if (input.tbAtRiskPatientIds.contains(patientId)) {
      drivers.add('tb-default-risk');
    }
    if (input.ncdOverduePatientIds.contains(patientId)) {
      drivers.add('ncd-drift');
    }
    if (input.referralArrivalPendingPatientIds.contains(patientId)) {
      drivers.add('referral-arrival-pending');
    }
    if (age != null &&
        age < _childUnder5AgeThreshold &&
        (input.disabilityByPatientId[patientId] ?? false)) {
      drivers.add('child-disability');
    }

    // Date-based tier (null-safe: missing dueAt → upcoming).
    final daysToDue = dueAt == null
        ? null
        : _atStartOfDay(dueAt).difference(_atStartOfDay(now)).inDays;
    final dateTier = DashboardTier.fromDaysToDue(daysToDue);

    if (drivers.isNotEmpty) {
      final promoted = dateTier.rank > DashboardTier.overdue.rank
          ? DashboardTier.overdue
          : dateTier;
      return (tier: promoted, drivers: drivers);
    }

    return (tier: dateTier, drivers: drivers);
  }

  /// Compute the tier-tagged, within-tier-sorted Mission Dashboard queue.
  /// Coexists with the legacy single-score [computeQueue]; Phase 3 swaps
  /// the dashboard screen onto this method.
  ///
  /// Referrals are deliberately excluded — per the Leapfrog HTML prototype,
  /// the referral surface is the right-side `Referral alerts` tile, not the
  /// main patient list.
  List<MissionQueueItem> computeTieredQueue(MissionInputData input) {
    final now = DateTime.now();
    final candidates = <MissionQueueItem>[];

    for (final entry in input.worklistEntries) {
      // Only enrolled patients belong on the Mission Dashboard — patients with
      // no programme have no clinical context or follow-up schedule.
      if (entry.programmes.isEmpty) continue;
      final age = entry.age ?? input.agesByPatientId[entry.patientId];
      // Use explicit follow-up dueAt when available; fall back to programme-
      // interval inference so patients without a follow-up record still surface
      // in the correct tier instead of always landing in "upcoming".
      final effectiveDueAt = entry.nextDueAt ?? _inferDueAt(entry);
      final classified = _classify(
        patientId: entry.patientId,
        age: age,
        band: entry.band,
        dueAt: effectiveDueAt,
        input: input,
        now: now,
      );
      if (classified == null) continue;
      final base = _worklistToQueueItem(entry, now, input);
      // When nextDueAt was null but we inferred a due date, patch it into
      // the queue item so the card shows the correct "due" / "overdue" label.
      final inferredDueAt =
          entry.nextDueAt == null ? effectiveDueAt : null;
      final inferredDaysOverdue = inferredDueAt != null
          ? now.difference(inferredDueAt).inDays.clamp(0, 999)
          : null;
      candidates.add(base.copyWith(
        // sortRankFor encodes the full 1a→1b→1→2a→…→4 sequence so
        // compareInTier() (priorityScore DESC) produces the correct
        // band+modifier order within each date tier.
        priorityScore: sortRankFor(entry.band, entry.modifier),
        tier: classified.tier,
        drivers: classified.drivers,
        dueAt: inferredDueAt,
        daysOverdue: inferredDaysOverdue,
      ));
    }

    for (final followUp in input.followUps) {
      final age = input.agesByPatientId[followUp.patientId];
      final classified = _classify(
        patientId: followUp.patientId,
        age: age,
        band: null,
        dueAt: followUp.dueAt,
        input: input,
        now: now,
      );
      if (classified == null) continue;
      final score = _compositeScore(
        patientId: followUp.patientId,
        age: age,
        dueAt: followUp.dueAt,
        input: input,
        now: now,
      );
      final base = _followUpToQueueItem(followUp, now, input);
      candidates.add(base.copyWith(
        priorityScore: score,
        tier: classified.tier,
        drivers: classified.drivers,
      ));
    }

    // Dedupe by patientId — same patient can appear via worklist + follow-up.
    // Keep the most-urgent tier; within same tier keep the higher composite.
    final byPid = <String, MissionQueueItem>{};
    final nonPatient = <MissionQueueItem>[];
    for (final c in candidates) {
      final pid = c.patientId;
      if (pid == null || pid.isEmpty) {
        nonPatient.add(c);
        continue;
      }
      final prev = byPid[pid];
      if (prev == null) {
        byPid[pid] = c;
      } else if (c.tier.rank < prev.tier.rank ||
          (c.tier == prev.tier && c.priorityScore > prev.priorityScore)) {
        byPid[pid] = c;
      }
    }

    final result = <MissionQueueItem>[...byPid.values, ...nonPatient];
    result.sort((a, b) {
      final tierCmp = a.tier.rank.compareTo(b.tier.rank);
      if (tierCmp != 0) return tierCmp;
      return MissionQueueItem.compareInTier(a, b);
    });
    return result;
  }

  /// Truncates a [DateTime] to local-midnight so `daysToDue` math ignores
  /// the wall-clock offset.
  DateTime _atStartOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
}
