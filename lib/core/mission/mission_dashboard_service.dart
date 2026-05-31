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
import '../models/mission_brief.dart';
import '../models/mission_queue_item.dart';
import '../models/programme.dart';
import '../models/risk.dart';
import '../models/sla.dart';
import '../models/worklist_entry.dart';
import '../models/referral.dart';

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

    // Count high-risk diabetic patients (NCD + high/urgent risk)
    final diabeticHighRisk = data.worklistEntries.where((e) =>
        e.programmes.contains(Programme.ncd) &&
        (e.band == RiskBand.urgent || e.band == RiskBand.high)).length;

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

    return MissionBrief(
      visitsRecommended: totalVisits,
      childDangerCases: childDangerCases,
      slaBreachedReferrals: slaBreached,
      ancFollowUps: ancFollowUps,
      highRiskDiabeticPatients: diabeticHighRisk,
      expectedWorkloadHours: workloadHours,
      priorityLevel: priorityLevel,
      riskFactors: riskFactors,
      computedAt: now,
    );
  }

  /// Compute prioritized mission queue from input data.
  List<MissionQueueItem> computeQueue(MissionInputData data, {int? limit}) {
    final items = <MissionQueueItem>[];
    final now = DateTime.now();

    // Add worklist entries
    for (final entry in data.worklistEntries) {
      items.add(_worklistToQueueItem(entry, now));
    }

    // Add referrals
    for (final referral in data.referrals) {
      final assessment = data.referralAssessments[referral.id];
      items.add(_referralToQueueItem(referral, assessment, now));
    }

    // Add follow-ups
    for (final followUp in data.followUps) {
      items.add(_followUpToQueueItem(followUp, now));
    }

    // Sort by priority score descending
    items.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

    // Apply limit if specified
    if (limit != null && items.length > limit) {
      return items.sublist(0, limit);
    }

    return items;
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
          topBreach = _referralToQueueItem(referral, assessment, DateTime.now());
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

  MissionQueueItem _worklistToQueueItem(WorklistEntry entry, DateTime now) {
    int score = 0;
    final drivers = <String>[];

    // Risk band contribution
    switch (entry.band) {
      case RiskBand.urgent:
        score += _wCriticalRisk;
        drivers.add('urgent-risk');
        break;
      case RiskBand.high:
        score += _wHighRisk;
        drivers.add('high-risk');
        break;
      case RiskBand.moderate:
        score += _wMediumRisk;
        drivers.add('moderate-risk');
        break;
      case RiskBand.low:
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
      age: entry.age,
      village: entry.householdName ?? entry.villageId,
      programmes: entry.programmes,
      reason: reason,
      daysOverdue: entry.nextDueAt != null
          ? now.difference(entry.nextDueAt!).inDays.clamp(0, 999)
          : null,
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
      village: referral.villageId,
      programmes: const {}, // Referrals don't have programme context here
      reason: referral.diagnosisLabel ?? 'Referral',
      daysOverdue: daysOverdue > 0 ? daysOverdue : null,
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

  MissionQueueItem _followUpToQueueItem(FollowUpDue followUp, DateTime now) {
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

    return MissionQueueItem(
      id: followUp.id,
      type: MissionItemType.followUp,
      priority: priority,
      priorityScore: score,
      patientName: followUp.patientName,
      patientId: followUp.patientId,
      reason: followUp.reason ?? 'Follow-up due',
      daysOverdue: daysUntil < 0 ? -daysUntil : null,
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
}
