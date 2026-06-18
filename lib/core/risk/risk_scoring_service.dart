import '../models/programme.dart';
import '../models/risk.dart';

/// On-device risk scoring for the AI Worklist.
///
/// Pure Dart — no Flutter binding, no I/O, no time provider beyond
/// [DateTime.now()] (overridable via [_clock] for tests). The repository
/// builds [PatientFacts] from cached SQLite rows and calls [score]; the
/// returned [RiskAssessment] is persisted on the patient row so the worklist
/// SQL is `ORDER BY risk_score DESC`.
///
/// Weights are *not* magic numbers — every contribution is a named constant
/// here so tuning is a single-file edit (Engineering Design Standards: DRY).
class RiskScoringService {
  const RiskScoringService();

  /// Model version for the on-device rule engine (architecture.md §3.4 contract).
  static const String modelVersion = 'on-device-rule-v1';

  // ── Weights ───────────────────────────────────────────────────────────────
  static const int _weightAgeUnder5 = 20;
  static const int _weightAgeOver60 = 10;
  static const int _weightPregnancy = 20;

  static const int _weightProgrammeNcd = 15;
  static const int _weightProgrammeTb = 25;
  static const int _weightProgrammeImci = 15;
  // ANC contribution is folded into [_weightPregnancy] — kept here as a doc
  // anchor so future tuners know ANC weight lives on the pregnancy axis.

  static const int _weightPerMissedVisit = 12;
  static const int _weightMissedVisitCap = 36;
  static const int _weightLostToFollowUp = 30;

  static const int _weightServerRiskColorRed = 15;
  static const int _weightServerRiskColorYellow = 5;

  /// Bands.
  static const int _bandUrgentMin = 80;
  static const int _bandHighMin = 60;
  static const int _bandModerateMin = 35;

  /// Score floor applied when a server hard-red flag is present.
  static const int _redFlagFloor = 80;

  /// Clock seam for tests.
  final DateTime Function() _clock = DateTime.now;

  RiskAssessment score(PatientFacts f) {
    final drivers = <String>[];
    int s = 0;

    // ── Age band ──────────────────────────────────────────────────────────
    final age = f.ageYears;
    if (age != null) {
      if (age < 5) {
        s += _weightAgeUnder5;
        drivers.add('under-5:$age');
      } else if (age >= 60) {
        s += _weightAgeOver60;
        drivers.add('senior:$age');
      }
    }

    if (f.programmes.contains(Programme.anc)) {
      s += _weightPregnancy;
      drivers.add('pregnancy');
    }

    // ── Programme base ────────────────────────────────────────────────────
    for (final p in f.programmes) {
      switch (p) {
        case Programme.ncd:
          s += _weightProgrammeNcd;
          drivers.add('ncd');
          break;
        case Programme.tb:
          s += _weightProgrammeTb;
          drivers.add('tb');
          break;
        case Programme.imci:
          s += _weightProgrammeImci;
          drivers.add('imci');
          break;
        case Programme.anc:
        case Programme.pnc:
          // Already covered by the pregnancy weight above.
          break;
        case Programme.epi:
        case Programme.nutrition:
        case Programme.familyPlanning:
        case Programme.cataract:
        case Programme.eyeCare:
        case Programme.unknown:
          // No additional weight for these programmes.
          break;
      }
    }

    // ── Missed visits ─────────────────────────────────────────────────────
    if (f.missedVisitsLast90d > 0) {
      final bump = (f.missedVisitsLast90d * _weightPerMissedVisit)
          .clamp(0, _weightMissedVisitCap);
      s += bump;
      drivers.add('missed-visits:${f.missedVisitsLast90d}');
    }

    if (f.lostToFollowUp) {
      s += _weightLostToFollowUp;
      drivers.add('lost-to-follow-up');
    }

    // ── Server hints (signals only, never the final answer) ───────────────
    final color = f.serverRiskColor?.toUpperCase();
    if (color == 'RED') {
      s += _weightServerRiskColorRed;
      drivers.add('server-risk-red');
    } else if (color == 'YELLOW' || color == 'AMBER') {
      s += _weightServerRiskColorYellow;
      drivers.add('server-risk-yellow');
    }

    final hint = f.serverRiskLevel?.toUpperCase();
    if (hint == 'HIGH' || f.redFlag) {
      if (s < _redFlagFloor) {
        s = _redFlagFloor;
        drivers.add(f.redFlag ? 'clinician-red-flag' : 'server-risk-high');
      }
    }

    if (s > 100) s = 100;
    if (s < 0) s = 0;

    final band = _bandFor(s);

    if (drivers.isEmpty) {
      drivers.add('no-programme');
    }

    final now = _clock();

    // Build structured rationale (architecture.md §3.4 contract).
    final rationale = RiskRationale(
      drivers: List.unmodifiable(drivers),
      modelVersion: modelVersion,
      computedAt: now,
      confidence: null, // Rule-based; populated when ML lands.
      humanReviewRequired: band == RiskBand.urgent,
      guidelineIds: const <String>[], // Future: WHO PEN, IMCI codes.
      sourceObservationIds: const <String>[], // Future: FHIR Observation IDs.
    );

    // Derive human-readable reasons from structured drivers.
    final reasons = rationale.formattedReasons;

    return RiskAssessment(
      score: s,
      band: band,
      programmes: f.programmes,
      reasons: reasons,
      rationale: rationale,
    );
  }

  static RiskBand _bandFor(int score) {
    if (score >= _bandUrgentMin) return RiskBand.urgent;
    if (score >= _bandHighMin) return RiskBand.high;
    if (score >= _bandModerateMin) return RiskBand.moderate;
    return RiskBand.low;
  }
}
