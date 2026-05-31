/// AI Mission Brief — daily summary for the SK dashboard.
///
/// Aggregated from worklist + referrals + follow-ups to answer:
/// "What needs action today?" without showing raw statistics.
library;

/// Priority level for the overall day.
enum DayPriorityLevel {
  critical,
  high,
  medium,
  low;

  String get label {
    switch (this) {
      case DayPriorityLevel.critical:
        return 'Critical';
      case DayPriorityLevel.high:
        return 'High';
      case DayPriorityLevel.medium:
        return 'Medium';
      case DayPriorityLevel.low:
        return 'Low';
    }
  }
}

/// AI-generated daily brief summarizing work and priorities.
class MissionBrief {
  const MissionBrief({
    required this.visitsRecommended,
    required this.childDangerCases,
    required this.slaBreachedReferrals,
    required this.ancFollowUps,
    required this.highRiskDiabeticPatients,
    required this.expectedWorkloadHours,
    required this.priorityLevel,
    this.riskFactors = const [],
    this.computedAt,
  });

  final int visitsRecommended;
  final int childDangerCases;
  final int slaBreachedReferrals;
  final int ancFollowUps;
  final int highRiskDiabeticPatients;
  final double expectedWorkloadHours;
  final DayPriorityLevel priorityLevel;
  final List<String> riskFactors;
  final DateTime? computedAt;

  bool get hasCriticalItems =>
      childDangerCases > 0 ||
      slaBreachedReferrals > 0 ||
      priorityLevel == DayPriorityLevel.critical;

  int get totalActionItems =>
      childDangerCases +
      slaBreachedReferrals +
      ancFollowUps +
      highRiskDiabeticPatients;

  static const MissionBrief empty = MissionBrief(
    visitsRecommended: 0,
    childDangerCases: 0,
    slaBreachedReferrals: 0,
    ancFollowUps: 0,
    highRiskDiabeticPatients: 0,
    expectedWorkloadHours: 0,
    priorityLevel: DayPriorityLevel.low,
  );
}

/// Progress tracking for daily mission completion.
class MissionProgress {
  const MissionProgress({
    required this.completedVisits,
    required this.totalVisits,
    required this.estimatedRemainingMinutes,
    this.predictedCompletionTime,
  });

  final int completedVisits;
  final int totalVisits;
  final int estimatedRemainingMinutes;
  final String? predictedCompletionTime;

  int get percentComplete =>
      totalVisits > 0 ? ((completedVisits / totalVisits) * 100).round() : 0;

  int get remainingVisits => totalVisits - completedVisits;

  bool get isComplete => completedVisits >= totalVisits && totalVisits > 0;

  String get remainingTimeFormatted {
    if (estimatedRemainingMinutes < 60) {
      return '${estimatedRemainingMinutes}m';
    }
    final hours = estimatedRemainingMinutes ~/ 60;
    final mins = estimatedRemainingMinutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  static const MissionProgress empty = MissionProgress(
    completedVisits: 0,
    totalVisits: 0,
    estimatedRemainingMinutes: 0,
  );
}
