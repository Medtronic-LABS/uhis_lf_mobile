/// Mission Queue Item — unified action item for the AI Mission Dashboard.
///
/// Combines patient, referral, and follow-up data into a single prioritized
/// action card. The queue is ranked by composite priority (clinical risk +
/// SLA status + programme priority + time overdue + AI risk prediction).
///
/// Spec: AI Mission Dashboard (Screen 2) — Mission Queue section.
library;

import 'programme.dart';
import 'referral.dart';
import 'sla.dart';

/// Type of mission item determining available actions.
enum MissionItemType {
  /// Patient visit (worklist entry).
  patientVisit,

  /// Active referral requiring follow-up.
  referral,

  /// Post-treatment follow-up.
  followUp,

  /// Household opportunity (bundled services).
  householdOpportunity,
}

/// Priority level badge for queue cards.
enum MissionPriority {
  critical,
  high,
  medium,
  low;

  String get emoji {
    switch (this) {
      case MissionPriority.critical:
        return '🔴';
      case MissionPriority.high:
        return '🟠';
      case MissionPriority.medium:
        return '🟡';
      case MissionPriority.low:
        return '🟢';
    }
  }

  String get label {
    switch (this) {
      case MissionPriority.critical:
        return 'CRITICAL';
      case MissionPriority.high:
        return 'HIGH';
      case MissionPriority.medium:
        return 'MEDIUM';
      case MissionPriority.low:
        return 'LOW';
    }
  }

  /// Convert from SlaPriority for referrals.
  static MissionPriority fromSlaPriority(SlaPriority sla) {
    switch (sla) {
      case SlaPriority.critical:
        return MissionPriority.critical;
      case SlaPriority.high:
        return MissionPriority.high;
      case SlaPriority.medium:
        return MissionPriority.medium;
      case SlaPriority.low:
        return MissionPriority.low;
    }
  }
}

/// Actions available for a mission queue item.
enum MissionAction {
  callFamily,
  locate,
  openCase,
  callFacility,
  openReferral,
  scheduleVisit,
  visitHousehold,
  updateStatus,
  escalate,
}

/// A single item in the AI Mission Queue.
class MissionQueueItem {
  const MissionQueueItem({
    required this.id,
    required this.type,
    required this.priority,
    required this.priorityScore,
    required this.patientName,
    this.patientId,
    this.referralId,
    this.householdId,
    this.householdNumber,
    this.age,
    this.village,
    this.programmes = const <Programme>{},
    required this.reason,
    this.daysOverdue,
    required this.aiInsight,
    this.aiDrivers = const [],
    this.availableActions = const [],
    this.phoneNumber,
    this.latitude,
    this.longitude,
    this.slaTier,
    this.diagnosisLabel,
    this.dueAt,
  });

  /// Unique identifier (patient ID, referral ID, or composite key).
  final String id;

  /// Type of mission item.
  final MissionItemType type;

  /// Priority level for badge display.
  final MissionPriority priority;

  /// Raw priority score for sorting (higher = more urgent).
  final int priorityScore;

  /// Patient display name.
  final String patientName;

  /// Patient ID for navigation.
  final String? patientId;

  /// Referral ID if this is a referral item.
  final String? referralId;

  /// Household ID (server UUID). Populated for patient/referral/follow-up
  /// items whose patient belongs to a known household, not only for explicit
  /// household opportunities — repository uses it to resolve
  /// [householdNumber] for display.
  final String? householdId;

  /// Display-only household number (e.g. `12`, `07`). Resolved by the
  /// repository from `HouseholdDao` keyed off [householdId]. UI consumes via
  /// [householdDisplay] and never re-formats it.
  final String? householdNumber;

  /// Patient age.
  final int? age;

  /// Village name.
  final String? village;

  /// Programme badges.
  final Set<Programme> programmes;

  /// Primary reason for appearing in queue (e.g., "Missed ANC", "Referral Delay").
  final String reason;

  /// Days overdue if applicable.
  final int? daysOverdue;

  /// Human-readable AI insight explaining prioritization.
  final String aiInsight;

  /// Machine-readable priority drivers (for detailed rationale).
  final List<String> aiDrivers;

  /// Actions available for this item.
  final List<MissionAction> availableActions;

  /// Phone number for call actions.
  final String? phoneNumber;

  /// Location coordinates for locate action.
  final double? latitude;
  final double? longitude;

  /// SLA tier for referrals.
  final SlaTier? slaTier;

  /// Diagnosis/condition label.
  final String? diagnosisLabel;

  /// Canonical "when is this due / when did it start waiting" timestamp.
  /// patientVisit → patient.nextDueAt; followUp → followUp.dueAt;
  /// referral → referral.createdAt (the longer it has waited, the earlier the
  /// timestamp). Used by the dashboard's earliest-first fallback sort when the
  /// queue has no critical / high priority items. Nullable — `nextDueAt` is
  /// often unknown for low-risk routine patients.
  final DateTime? dueAt;

  /// Nulls-last ascending comparator on [dueAt]. Falls back to patient name
  /// as a tiebreaker so the sort is stable even when all dueAt values are null.
  static int compareByDueAtAsc(MissionQueueItem a, MissionQueueItem b) {
    final ad = a.dueAt;
    final bd = b.dueAt;
    if (ad != null && bd != null) {
      final cmp = ad.compareTo(bd);
      if (cmp != 0) return cmp;
    } else if (ad != null) {
      return -1; // a has date, b doesn't → a first
    } else if (bd != null) {
      return 1; // b has date, a doesn't → b first
    }
    // Both null or equal dates: fall back to priority score (higher first),
    // then patient name for stable sort
    final scoreCmp = b.priorityScore.compareTo(a.priorityScore);
    if (scoreCmp != 0) return scoreCmp;
    return (a.patientName ?? '').compareTo(b.patientName ?? '');
  }

  /// Whether this is a critical item requiring immediate attention.
  bool get isCritical => priority == MissionPriority.critical;

  /// Whether location data is available.
  bool get hasLocation => latitude != null && longitude != null;

  /// Whether phone number is available.
  bool get hasPhone => phoneNumber != null && phoneNumber!.isNotEmpty;

  /// Age display string.
  String get ageDisplay => age != null ? 'Age $age' : '';

  /// Household display string (`House #12`) or empty when unknown. Centralised
  /// so screens never inline the prefix.
  String get householdDisplay =>
      (householdNumber != null && householdNumber!.isNotEmpty)
          ? 'House #${householdNumber!}'
          : '';

  /// Returns the most representative programme for routing the visit flow.
  /// Falls back to [Programme.unknown] when no programme is tagged so callers
  /// always get a non-null value (matches `VisitLandingScreen` convention).
  Programme get primaryProgramme {
    if (programmes.contains(Programme.imci)) return Programme.imci;
    if (programmes.contains(Programme.anc)) return Programme.anc;
    if (programmes.contains(Programme.pnc)) return Programme.pnc;
    if (programmes.contains(Programme.ncd)) return Programme.ncd;
    if (programmes.contains(Programme.tb)) return Programme.tb;
    return programmes.isNotEmpty ? programmes.first : Programme.unknown;
  }

  /// Programme emoji for display.
  String get programmeEmoji {
    if (programmes.contains(Programme.imci)) return '🌡️';
    if (programmes.contains(Programme.anc)) return '🤰';
    if (programmes.contains(Programme.ncd)) return '💊';
    if (programmes.contains(Programme.tb)) return '🫁';
    return '👤';
  }
}

/// Household with bundled service opportunities.
class HouseholdOpportunity {
  const HouseholdOpportunity({
    required this.householdId,
    required this.householdNumber,
    this.householdName,
    required this.memberServices,
    this.latitude,
    this.longitude,
  });

  /// Household ID for navigation.
  final String householdId;

  /// Household number for display.
  final int householdNumber;

  /// Household name if available.
  final String? householdName;

  /// Map of member role to pending service (e.g., "Mother" → "ANC Follow-up Due").
  final Map<String, String> memberServices;

  /// Location for routing.
  final double? latitude;
  final double? longitude;

  /// Total potential services in this household.
  int get potentialServicesCount => memberServices.length;

  /// Whether multiple services can be done in one visit.
  bool get hasMultipleOpportunities => memberServices.length > 1;
}

/// A stop in the optimized route.
class RouteStop {
  const RouteStop({
    required this.rank,
    required this.patientName,
    this.patientId,
    this.householdId,
    this.latitude,
    this.longitude,
  });

  /// Order in the route (1-indexed).
  final int rank;

  /// Patient or household name.
  final String patientName;

  /// Patient ID if individual.
  final String? patientId;

  /// Household ID if household visit.
  final String? householdId;

  /// Location coordinates.
  final double? latitude;
  final double? longitude;

  /// Whether location is available.
  bool get hasLocation => latitude != null && longitude != null;
}

/// Optimized route for the day's visits.
class OptimizedRoute {
  const OptimizedRoute({
    required this.stops,
    required this.totalDistanceKm,
    required this.estimatedDurationMinutes,
  });

  /// Ordered list of stops.
  final List<RouteStop> stops;

  /// Total distance in kilometers.
  final double totalDistanceKm;

  /// Total estimated travel time in minutes.
  final int estimatedDurationMinutes;

  /// Number of stops.
  int get stopCount => stops.length;

  /// Whether route has been calculated.
  bool get hasRoute => stops.isNotEmpty;

  /// Format duration as human-readable string.
  String get durationFormatted {
    if (estimatedDurationMinutes < 60) {
      return '${estimatedDurationMinutes}m';
    }
    final hours = estimatedDurationMinutes ~/ 60;
    final mins = estimatedDurationMinutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  /// Empty route.
  static const OptimizedRoute empty = OptimizedRoute(
    stops: [],
    totalDistanceKm: 0,
    estimatedDurationMinutes: 0,
  );
}

/// Follow-up due after discharge.
class FollowUpDue {
  const FollowUpDue({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.dischargedAt,
    required this.dueAt,
    this.reason,
    this.phoneNumber,
  });

  /// Follow-up ID.
  final String id;

  /// Patient ID for navigation.
  final String patientId;

  /// Patient display name.
  final String patientName;

  /// When patient was discharged.
  final DateTime? dischargedAt;

  /// When follow-up is due.
  final DateTime dueAt;

  /// Reason for follow-up.
  final String? reason;

  /// Phone number for contact.
  final String? phoneNumber;

  /// Whether follow-up is overdue.
  bool isOverdue(DateTime now) => dueAt.isBefore(now);

  /// Days until due (negative if overdue).
  int daysUntilDue(DateTime now) {
    final diff = dueAt.difference(now);
    return diff.inDays;
  }
}

/// Referral summary counts for the dashboard widget.
class ReferralSummary {
  const ReferralSummary({
    required this.active,
    required this.breached,
    required this.awaitingReview,
    required this.completed,
    this.topBreachedReferral,
  });

  /// Active (not completed) referrals.
  final int active;

  /// Referrals that have breached SLA.
  final int breached;

  /// Referrals awaiting facility review.
  final int awaitingReview;

  /// Completed referrals.
  final int completed;

  /// The most critical breached referral for quick action.
  final MissionQueueItem? topBreachedReferral;

  /// Total referrals.
  int get total => active + completed;

  /// Whether any breaches exist.
  bool get hasBreaches => breached > 0;

  /// Empty summary.
  static const ReferralSummary empty = ReferralSummary(
    active: 0,
    breached: 0,
    awaitingReview: 0,
    completed: 0,
  );
}
