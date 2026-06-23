import '../models/sla.dart';

/// On-device priority scorer for the SK Referral dashboard.
///
/// Pure-Dart, named-constant weights — mirrors [RiskScoringService].
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §4.2 + §12.5.
///
/// Output: 0..100+ score (no upper clamp by design — stacked weights for an
/// emergency referral can exceed 100) + a four-band [SlaPriority] level +
/// structured `drivers: List<String>` machine-readable tags for the
/// rationale payload.
class PriorityScorer {
  const PriorityScorer();

  /// Stable identifier for the rationale payload's `modelVersion` field.
  static const String modelVersion = 'on-device-priority-rule-v1';

  // ── Weights ─────────────────────────────────────────────────────────────
  static const int _wSlaBreached = 50;
  static const int _wChildUnder5 = 20;
  static const int _wPregnancy = 20;
  static const int _wEmergencyDiagnosis = 40;
  static const int _wNoArrival = 30;
  static const int _wDelayOver48h = 25;
  static const int _wMissedFollowUp = 15;

  // ── Band thresholds ─────────────────────────────────────────────────────
  static const int _bandCriticalMin = 91;
  static const int _bandHighMin = 61;
  static const int _bandMediumMin = 31;

  /// Time threshold for the "delay > 48h" driver.
  static const Duration _delayWindow = Duration(hours: 48);

  /// Run the scorer over a [ReferralFacts] + breach signal.
  ///
  /// [slaBreached] is supplied by the caller (typically `SlaAssessment
  /// .isBreached`) so the scorer doesn't re-evaluate the SLA window itself.
  PriorityAssessment score({
    required ReferralFacts facts,
    required bool slaBreached,
  }) {
    final drivers = <String>[];
    int s = 0;

    if (slaBreached) {
      s += _wSlaBreached;
      drivers.add('sla-breached');
    }
    if (facts.ageYears != null && facts.ageYears! < 5) {
      s += _wChildUnder5;
      drivers.add('under-5:${facts.ageYears}');
    }
    if (facts.isPregnancy) {
      s += _wPregnancy;
      drivers.add('pregnancy');
    }
    if (facts.isEmergencyDiagnosis) {
      s += _wEmergencyDiagnosis;
      drivers.add('emergency-dx');
    }
    if (!facts.arrivalConfirmed && facts.elapsedSinceCreated.inSeconds > 0) {
      s += _wNoArrival;
      drivers.add('no-arrival');
    }
    if (facts.elapsedSinceCreated > _delayWindow) {
      s += _wDelayOver48h;
      drivers.add('delay-48h');
    }
    if (facts.missedFollowUps > 0) {
      s += _wMissedFollowUp;
      drivers.add('missed-follow-up:${facts.missedFollowUps}');
    }

    if (s < 0) s = 0;

    final level = _bandFor(s);
    final rationale = ReferralRationale(
      drivers: List.unmodifiable(drivers),
      modelVersion: modelVersion,
      computedAt: facts.now,
      humanReviewRequired: level == SlaPriority.critical,
    );

    return PriorityAssessment(
      referralId: facts.referralId,
      score: s,
      level: level,
      drivers: List.unmodifiable(drivers),
      rationale: rationale,
    );
  }

  static SlaPriority _bandFor(int score) {
    if (score >= _bandCriticalMin) return SlaPriority.critical;
    if (score >= _bandHighMin) return SlaPriority.high;
    if (score >= _bandMediumMin) return SlaPriority.medium;
    return SlaPriority.low;
  }
}
