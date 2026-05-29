import '../models/referral.dart';
import '../models/sla.dart';

/// On-device SLA evaluator for the SK Referral dashboard.
///
/// Pure Dart — no Flutter binding, no I/O. Tests construct [ReferralFacts]
/// instances directly; production callers (`ReferralRepository`) build them
/// from cached SQLite rows.
///
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §4.1 + §12.4.
///
/// Thresholds are **named constants** per Engineering Design Standards — no
/// literal hour/day appears in any UI or repository code. Tuning is a
/// single-file edit.
class SlaEvaluator {
  const SlaEvaluator();

  /// Stable identifier for the rationale payload's `modelVersion` field.
  /// Bump when the state-machine or threshold table changes.
  static const String modelVersion = 'on-device-sla-rule-v1';

  // ── Tier windows (hours) ────────────────────────────────────────────────
  static const int _emergencyArrivalHours = 3;
  static const int _emergencyTreatmentHours = 1;
  static const int _urgentArrivalHours = 24;
  static const int _urgentTreatmentHours = 12;
  static const int _routineArrivalDaysMin = 3;
  static const int _routineArrivalDaysMax = 7;
  static const int _routineTreatmentDays = 7;

  /// Fraction of the SLA window remaining at which we flag a warning.
  /// 0.25 ⇒ warn during the final quarter of the window.
  static const double _warningThreshold = 0.25;

  /// Auto-promote `acknowledged` → `inTransit` once more than half of the
  /// arrival window has elapsed. Surfaces motion to the SK even when the
  /// facility hasn't pushed an explicit acknowledgement.
  static const double _inTransitAssumeFraction = 0.5;

  SlaAssessment evaluate(ReferralFacts f) {
    final created = f.createdAt;
    final now = f.now;
    final arrivalWindow = _arrivalWindowFor(f.slaTier);
    final treatmentWindow = _treatmentWindowFor(f.slaTier);

    final dueArrival = created.add(arrivalWindow);
    final dueTreatment = f.arrivalConfirmedAt == null
        ? null
        : f.arrivalConfirmedAt!.add(treatmentWindow);

    final elapsed = now.difference(created);

    // ── State machine ─────────────────────────────────────────────────────
    final from = f.currentState;
    ReferralStatus next = from;
    DateTime? breachedSince;

    // Closed / exception states are terminal — don't run transitions.
    if (from.isClosed || from.isException) {
      return SlaAssessment(
        referralId: f.referralId,
        slaTier: f.slaTier,
        state: from,
        escalationLevel: f.escalationLevel,
        computedAt: now,
        dueArrivalAt: dueArrival,
        dueTreatmentAt: dueTreatment,
      );
    }

    switch (from) {
      case ReferralStatus.created:
        // Pure aging — the explicit acknowledged transition is fired by the
        // facility via a status-event call.
        next = ReferralStatus.created;
        break;
      case ReferralStatus.acknowledged:
        if (elapsed.inSeconds >
            (arrivalWindow.inSeconds * _inTransitAssumeFraction)) {
          next = ReferralStatus.inTransit;
        }
        break;
      case ReferralStatus.inTransit:
        if (f.arrivalConfirmed) {
          next = ReferralStatus.arrived;
        } else if (now.isAfter(dueArrival)) {
          next = ReferralStatus.breachedArrival;
          breachedSince = dueArrival;
        }
        break;
      case ReferralStatus.arrived:
        if (f.treatmentStarted) {
          next = ReferralStatus.treatmentStarted;
        } else if (dueTreatment != null && now.isAfter(dueTreatment)) {
          // Treatment-window breach reuses the breachedArrival enum slot
          // (the spec maps "breachedArrival|breachedTreatment" to one
          // composite exception state). The dueAt distinguishes which.
          next = ReferralStatus.breachedArrival;
          breachedSince = dueTreatment;
        }
        break;
      case ReferralStatus.treatmentStarted:
        // Closure transitions are caller-driven (clinician input). No
        // automatic transition out of treatmentStarted.
        break;
      default:
        break;
    }

    // Compute warning flags (only when not breached, not closed).
    final warningArrival = breachedSince == null &&
        next == ReferralStatus.inTransit &&
        _withinWarningBand(now, dueArrival, arrivalWindow);
    final warningTreatment = breachedSince == null &&
        next == ReferralStatus.arrived &&
        dueTreatment != null &&
        _withinWarningBand(now, dueTreatment, treatmentWindow);

    // Escalation: time since breach drives the chain.
    final escalation = breachedSince == null
        ? f.escalationLevel
        : EscalationChain.levelFor(
            f.slaTier, now.difference(breachedSince));

    return SlaAssessment(
      referralId: f.referralId,
      slaTier: f.slaTier,
      state: next,
      escalationLevel: escalation,
      computedAt: now,
      dueArrivalAt: dueArrival,
      dueTreatmentAt: dueTreatment,
      breachedSince: breachedSince ??
          (next == ReferralStatus.breachedArrival ? dueArrival : null),
      warningArrival: warningArrival,
      warningTreatment: warningTreatment,
    );
  }

  // ── Window math ─────────────────────────────────────────────────────────

  Duration _arrivalWindowFor(SlaTier tier) {
    switch (tier) {
      case SlaTier.emergency:
        return const Duration(hours: _emergencyArrivalHours);
      case SlaTier.urgent:
        return const Duration(hours: _urgentArrivalHours);
      case SlaTier.routine:
        // Use the upper bound of the 3-7 day range — the SLA "breaches" at
        // the late end; the warning band catches the early end.
        return const Duration(days: _routineArrivalDaysMax);
    }
  }

  Duration _treatmentWindowFor(SlaTier tier) {
    switch (tier) {
      case SlaTier.emergency:
        return const Duration(hours: _emergencyTreatmentHours);
      case SlaTier.urgent:
        return const Duration(hours: _urgentTreatmentHours);
      case SlaTier.routine:
        return const Duration(days: _routineTreatmentDays);
    }
  }

  bool _withinWarningBand(DateTime now, DateTime dueAt, Duration window) {
    final remaining = dueAt.difference(now);
    if (remaining.isNegative) return false;
    final pct = remaining.inSeconds / window.inSeconds;
    return pct <= _warningThreshold;
  }

  /// Expose the routine-min for callers that want to suppress warning chatter
  /// on routine referrals during their grace period. Not used internally.
  static int get routineArrivalGraceDays => _routineArrivalDaysMin;
}

/// Escalation chain — maps (tier, time since breach) → escalation level.
///
/// Repeat intervals + escalation cadence live here so notification + SLA
/// engine read from one source of truth.
class EscalationChain {
  EscalationChain._();

  // Repeat intervals per channel — public so [RepeatScheduler] reads the
  // same constants and we don't double-encode the cadence.
  static const Duration repeatIntervalCritical = Duration(minutes: 30);
  static const Duration repeatIntervalWarning = Duration(hours: 2);
  static const Duration repeatIntervalCompletion = Duration.zero; // one-shot

  /// Floor between repeats within the same (channel, referralId). Prevents
  /// notification storms when multiple recompute passes fire in quick
  /// succession.
  static const Duration minIntervalBetweenRepeats = Duration(minutes: 30);

  // ── Level thresholds, expressed as multiples of the tier's arrival window
  // for emergency / urgent, and as wall-clock days for routine ────────────
  static EscalationLevel levelFor(SlaTier tier, Duration sinceBreach) {
    switch (tier) {
      case SlaTier.emergency:
        // 0..30 min → SK; 30 min..2h → Supervisor; 2h..6h → Facility; 6h+ → District
        if (sinceBreach < const Duration(minutes: 30)) return EscalationLevel.sk;
        if (sinceBreach < const Duration(hours: 2)) {
          return EscalationLevel.supervisor;
        }
        if (sinceBreach < const Duration(hours: 6)) {
          return EscalationLevel.facility;
        }
        return EscalationLevel.district;
      case SlaTier.urgent:
        if (sinceBreach < const Duration(hours: 6)) return EscalationLevel.sk;
        if (sinceBreach < const Duration(hours: 24)) {
          return EscalationLevel.supervisor;
        }
        if (sinceBreach < const Duration(days: 3)) {
          return EscalationLevel.facility;
        }
        return EscalationLevel.district;
      case SlaTier.routine:
        if (sinceBreach < const Duration(days: 2)) return EscalationLevel.sk;
        if (sinceBreach < const Duration(days: 7)) {
          return EscalationLevel.supervisor;
        }
        if (sinceBreach < const Duration(days: 14)) {
          return EscalationLevel.facility;
        }
        return EscalationLevel.district;
    }
  }
}
