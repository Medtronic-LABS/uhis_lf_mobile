/// Mission Queue Item — unified action item for the AI Mission Dashboard.
///
/// Combines patient, referral, and follow-up data into a single prioritized
/// action card. The queue is ranked by composite priority (clinical risk +
/// SLA status + programme priority + time overdue + AI risk prediction).
///
/// Spec: AI Mission Dashboard (Screen 2) — Mission Queue section.
library;

import '../mission/programme_reason.dart' show primaryProgrammeOf;
import 'dashboard_tier.dart';
import 'programme.dart';
import 'referral.dart';
import 'risk.dart';
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
    this.gender,
    this.nid,
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
    this.tier = DashboardTier.upcoming,
    this.drivers = const <String>[],
    this.modifier = Modifier.none,
    this.isPregnant = false,
    this.band = Band.band4,
    this.clinicalReasons = const <String>[],
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

  /// Patient gender as stored in the sync payload ("Male", "Female", "Other",
  /// or a single letter). Card formats it to a single uppercase letter via
  /// [genderInitial].
  final String? gender;

  /// National ID / NID — used for inline dashboard search only, never shown
  /// on the card itself.
  final String? nid;

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

  /// 5-tier dashboard priority — drives Mission Dashboard grouping + CTA.
  /// Defaults to [DashboardTier.upcoming] so existing call sites compile
  /// unchanged during Phase 0; `MissionDashboardService.computeTieredQueue`
  /// assigns the real tier in Phase 1.
  final DashboardTier tier;

  /// Machine-readable driver tags explaining *why* this item landed in
  /// [tier] (e.g. `'neonate'`, `'sla-breached'`, `'hi-risk-anc-gap'`,
  /// `'ltfu-streak'`). Stable identifiers — UI maps them through
  /// `MissionDashboardStrings.driverLabel` for display.
  final List<String> drivers;

  /// Intra-band modifier from PRD §2.8 — drives sort within a band.
  /// `a` = additional risk (comorbidity / primigravida / near-term / age ≥ 60).
  /// `b` = overdue (longer past scheduled visit → higher within band, below `a`).
  /// Never shown to the SK; only used in [compareInBand].
  final Modifier modifier;

  /// Whether this patient is currently pregnant (ANC enrolled + snapshot).
  /// Pregnant patients always rank above non-pregnant patients within the
  /// same band (PRD §2.8 requirement). Not shown in the card directly.
  final bool isPregnant;

  /// Clinical risk band from PRD §2.8 — primary sort key on the Mission
  /// Dashboard. Stamped by [MissionDashboardService.computeTieredQueue] from
  /// [WorklistEntry.band]. Defaults to [Band.band4] so existing call sites
  /// compile unchanged before the tiered queue is wired up.
  final Band band;

  /// Human-readable clinical scoring reasons that explain *why* this patient
  /// received their [band] and [modifier] — e.g. "NCD: stage 1 hypertension
  /// (BP 142/88)", "NCD: elderly patient (age 65)". Sourced from
  /// [RiskRationale.formattedReasons] via [WorklistEntry.reasons]. Debug-only;
  /// never surfaced in the SK UI.
  final List<String> clinicalReasons;

  /// Returns a copy with the supplied fields overridden. Null arguments leave
  /// the original value in place — to clear a nullable field, pass the
  /// existing value through the call site or build a fresh ctor. Used by
  /// `MissionDashboardService.computeTieredQueue` to swap [tier], [drivers],
  /// and [priorityScore] onto an already-built candidate.
  /// Single uppercase initial for display ("M", "F", "O").
  /// Returns null when gender is absent.
  String? get genderInitial {
    final g = gender?.trim();
    if (g == null || g.isEmpty) return null;
    return g[0].toUpperCase();
  }

  MissionQueueItem copyWith({
    MissionItemType? type,
    MissionPriority? priority,
    int? priorityScore,
    String? patientName,
    String? patientId,
    String? referralId,
    String? householdId,
    String? householdNumber,
    int? age,
    String? gender,
    String? nid,
    String? village,
    Set<Programme>? programmes,
    String? reason,
    int? daysOverdue,
    String? aiInsight,
    List<String>? aiDrivers,
    List<MissionAction>? availableActions,
    String? phoneNumber,
    double? latitude,
    double? longitude,
    SlaTier? slaTier,
    String? diagnosisLabel,
    DateTime? dueAt,
    DashboardTier? tier,
    List<String>? drivers,
    Modifier? modifier,
    bool? isPregnant,
    Band? band,
    List<String>? clinicalReasons,
  }) {
    return MissionQueueItem(
      id: id,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      priorityScore: priorityScore ?? this.priorityScore,
      patientName: patientName ?? this.patientName,
      patientId: patientId ?? this.patientId,
      referralId: referralId ?? this.referralId,
      householdId: householdId ?? this.householdId,
      householdNumber: householdNumber ?? this.householdNumber,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      nid: nid ?? this.nid,
      village: village ?? this.village,
      programmes: programmes ?? this.programmes,
      reason: reason ?? this.reason,
      daysOverdue: daysOverdue ?? this.daysOverdue,
      aiInsight: aiInsight ?? this.aiInsight,
      aiDrivers: aiDrivers ?? this.aiDrivers,
      availableActions: availableActions ?? this.availableActions,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      slaTier: slaTier ?? this.slaTier,
      diagnosisLabel: diagnosisLabel ?? this.diagnosisLabel,
      dueAt: dueAt ?? this.dueAt,
      tier: tier ?? this.tier,
      drivers: drivers ?? this.drivers,
      modifier: modifier ?? this.modifier,
      isPregnant: isPregnant ?? this.isPregnant,
      band: band ?? this.band,
      clinicalReasons: clinicalReasons ?? this.clinicalReasons,
    );
  }

  /// Tier-rank ascending comparator (most-urgent tier first).
  /// Pure tier comparison — does not break ties; callers should chain
  /// [compareInTier] for deterministic intra-tier order.
  static int compareByTierRank(MissionQueueItem a, MissionQueueItem b) =>
      a.tier.rank.compareTo(b.tier.rank);

  /// Intra-band comparator implementing PRD §2.8 sort order within a band:
  ///   1. modifier a → modifier b → no modifier
  ///   2. pregnant > non-pregnant (spec §2.8 step 3)
  ///   3. modifier b: longer overdue ranks higher (spec §2.8 step 4)
  ///   4. ANC programme > NCD (CD-1 tiebreaker)
  ///   5. patient name ASC (stable tiebreaker)
  static int compareInBand(MissionQueueItem a, MissionQueueItem b) {
    // 1. Modifier: a(0) < b(1) < none(2) — best modifier wins
    final modCmp = a.modifier.sortRank.compareTo(b.modifier.sortRank);
    if (modCmp != 0) return modCmp;
    // 2. Pregnant before non-pregnant (spec §2.8 step 3)
    final pregCmp = (b.isPregnant ? 0 : 1).compareTo(a.isPregnant ? 0 : 1);
    if (pregCmp != 0) return pregCmp;
    // 3. Longer overdue ranks higher (spec §2.8 step 4 — applied to all patients
    //    with positive overdue days; risk scorer does not always assign modifier b).
    final overdueCmp = (b.daysOverdue ?? 0).compareTo(a.daysOverdue ?? 0);
    if (overdueCmp != 0) return overdueCmp;
    // 4. ANC programme ranks above NCD (CD-1 tiebreaker)
    final ancCmp = _ancRank(b).compareTo(_ancRank(a));
    if (ancCmp != 0) return ancCmp;
    // 5. Stable alphabetical tiebreaker
    return a.patientName.compareTo(b.patientName);
  }

  static int _ancRank(MissionQueueItem item) =>
      item.programmes.contains(Programme.anc) ? 1 : 0;

  /// Intra-tier comparator: [priorityScore] DESC (encodes band+modifier), then
  /// the full [compareInBand] tiebreaker chain — pregnant, overdue (mod b),
  /// ANC > NCD, name — so PRD §2.8 ordering is preserved end-to-end.
  static int compareInTier(MissionQueueItem a, MissionQueueItem b) {
    final scoreCmp = b.priorityScore.compareTo(a.priorityScore);
    if (scoreCmp != 0) return scoreCmp;
    return compareInBand(a, b);
  }

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
    return a.patientName.compareTo(b.patientName);
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
  Programme get primaryProgramme => primaryProgrammeOf(programmes);

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
