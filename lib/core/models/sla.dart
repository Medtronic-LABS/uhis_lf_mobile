/// Models for the on-device SLA + priority engines.
///
/// - [ReferralFacts] is the engine input — a thin, denormalised view assembled
///   by [ReferralRepository] from cached SQLite rows.
/// - [SlaAssessment] is [SlaEvaluator] output (state machine + window math).
/// - [PriorityAssessment] is [PriorityScorer] output (weighted score + band).
/// - [SlaPriority] is the four-band priority taxonomy that drives dashboard
///   colour + notification channel.
///
/// `ReferralRationale` is a type alias of `RiskRationale` (same JSON shape;
/// same `formattedReasons` localiser pattern). Spec:
/// `leapfrog-setup/designs/referral-sla-engine.md` §5.
library;

import 'referral.dart';
import 'risk.dart';

/// Reuse the structured rationale payload used by the risk engine.
/// Wire-compatible — `referrals.rationale_json` JSON shape is identical.
typedef ReferralRationale = RiskRationale;

/// Priority band derived from [PriorityScorer.score].
enum SlaPriority {
  critical,
  high,
  medium,
  low;

  String get wireTag {
    switch (this) {
      case SlaPriority.critical:
        return 'critical';
      case SlaPriority.high:
        return 'high';
      case SlaPriority.medium:
        return 'medium';
      case SlaPriority.low:
        return 'low';
    }
  }

  static SlaPriority fromWireTag(String? tag) {
    switch ((tag ?? '').toLowerCase()) {
      case 'critical':
        return SlaPriority.critical;
      case 'high':
        return SlaPriority.high;
      case 'medium':
        return SlaPriority.medium;
      default:
        return SlaPriority.low;
    }
  }
}

/// Where the escalation has reached today. Bumped by [EscalationChain].
enum EscalationLevel {
  sk,
  supervisor,
  facility,
  district;

  int get index0 => index;

  static EscalationLevel fromIndex(int? i) {
    if (i == null) return EscalationLevel.sk;
    if (i < 0 || i >= EscalationLevel.values.length) return EscalationLevel.sk;
    return EscalationLevel.values[i];
  }
}

/// Engine input. Pure data — no Flutter or sqflite imports allowed here so
/// the SLA + priority code stays unit-testable without a runtime.
class ReferralFacts {
  const ReferralFacts({
    required this.referralId,
    required this.slaTier,
    required this.currentState,
    required this.createdAt,
    required this.now,
    this.ageYears,
    this.isPregnancy = false,
    this.isEmergencyDiagnosis = false,
    this.arrivalConfirmedAt,
    this.treatmentStartedAt,
    this.missedFollowUps = 0,
    this.escalationLevel = EscalationLevel.sk,
  });

  final String referralId;
  final SlaTier slaTier;
  final ReferralStatus currentState;
  final DateTime createdAt;
  final DateTime now;
  final int? ageYears;
  final bool isPregnancy;
  final bool isEmergencyDiagnosis;
  final DateTime? arrivalConfirmedAt;
  final DateTime? treatmentStartedAt;
  final int missedFollowUps;
  final EscalationLevel escalationLevel;

  Duration get elapsedSinceCreated => now.difference(createdAt);
  bool get arrivalConfirmed => arrivalConfirmedAt != null;
  bool get treatmentStarted => treatmentStartedAt != null;
}

/// SLA evaluator output.
class SlaAssessment {
  const SlaAssessment({
    required this.referralId,
    required this.slaTier,
    required this.state,
    required this.escalationLevel,
    required this.computedAt,
    this.dueArrivalAt,
    this.dueTreatmentAt,
    this.breachedSince,
    this.warningArrival = false,
    this.warningTreatment = false,
  });

  final String referralId;
  final SlaTier slaTier;
  final ReferralStatus state;
  final EscalationLevel escalationLevel;
  final DateTime computedAt;
  final DateTime? dueArrivalAt;
  final DateTime? dueTreatmentAt;

  /// When the SLA was first considered breached. Null when never breached.
  final DateTime? breachedSince;

  /// Transient flag: within 25 % of arrival-window expiry, not yet breached.
  final bool warningArrival;
  final bool warningTreatment;

  bool get isBreached => breachedSince != null;
  bool get isClosed => state.isClosed;
}

/// Priority scorer output.
class PriorityAssessment {
  const PriorityAssessment({
    required this.referralId,
    required this.score,
    required this.level,
    required this.drivers,
    required this.rationale,
  });

  final String referralId;

  /// 0..100+, no upper clamp by design — emergency referrals with multiple
  /// stacked weights can land above 100 (e.g. 50 sla-breached + 40 emergency
  /// + 30 no-arrival + 25 delay >48h = 145 → CRITICAL).
  final int score;
  final SlaPriority level;

  /// Structured machine-readable drivers, e.g. `['sla-breached', 'under-5:2']`.
  /// Source of truth for the rationale; UI derives display text from these.
  final List<String> drivers;

  /// Full rationale payload (architecture.md §3.4 contract). Persisted as
  /// JSON in `referrals.rationale_json`.
  final ReferralRationale rationale;
}
