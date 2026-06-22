import '../models/programme.dart';
import '../models/risk.dart';

/// On-device risk scoring for the AI Worklist — spec §2.8.
///
/// Implements ANC (§2.8.1) and NCD (§2.8.2) clinical factor tables.
/// Non-ANC/NCD programmes retain the previous programme-weight fallback.
/// All weights are named constants — tune here, nowhere else (DRY).
class RiskScoringService {
  const RiskScoringService();

  static const String modelVersion = 'on-device-rule-v2';

  // ── ANC weights (§2.8.1) ─────────────────────────────────────────────────
  static const int _ancDangerSign          = 30; // any danger sign
  static const int _ancEclampsia           = 25; // eclampsia / pre-eclampsia
  static const int _ancHighBp              = 20; // BP ≥ 140/90
  static const int _ancSevereAnaemia       = 20; // Hb < 7 g/dL
  static const int _ancMissedVisit         = 15; // > 28 days overdue
  static const int _ancModeratAnaemia      = 10; // Hb 7–10.9 g/dL
  static const int _ancPrimigravida        = 5;  // parity = 0

  // ── NCD weights (§2.8.2) ─────────────────────────────────────────────────
  static const int _ncdStage2Htn           = 25; // BP ≥ 160/100
  static const int _ncdStage1Htn           = 20; // BP ≥ 140/90 (below stage 2)
  static const int _ncdPoorlyControlledDm  = 20; // fasting glucose ≥ 180 mg/dL (≈10 mmol/L)
  static const int _ncdComorbidHtnDm       = 20; // HTN + DM together
  static const int _ncdMissedFollowUp      = 15; // > 42 days since last visit
  static const int _ncdElevatedBp          = 10; // systolic 130–139 or diastolic 80–89
  static const int _ncdElderly             = 5;  // age ≥ 60

  // ── Programme fallback weights (non-ANC/NCD) ─────────────────────────────
  static const int _weightProgrammeTb      = 25;
  static const int _weightProgrammeImci    = 15;
  static const int _weightAgeUnder5        = 20;

  // ── Server-hint modifiers ─────────────────────────────────────────────────
  static const int _weightServerRed        = 15;
  static const int _weightServerYellow     = 5;
  static const int _redFlagFloor           = 80;

  // ── Missed-visit fallback (no vitals available) ───────────────────────────
  static const int _weightPerMissedVisit   = 12;
  static const int _weightMissedVisitCap   = 36;
  static const int _weightLostToFollowUp   = 30;

  // ── Bands ─────────────────────────────────────────────────────────────────
  static const int _bandUrgentMin = 80;
  static const int _bandHighMin   = 60;
  static const int _bandModerateMin = 35;

  RiskAssessment score(PatientFacts f) {
    final drivers = <String>[];
    int s = 0;

    // ── ANC clinical rules (§2.8.1) ─────────────────────────────────────────
    if (f.programmes.contains(Programme.anc)) {
      final v = f.vitals;
      if (v != null) {
        // Danger sign (30 pts — immediate referral)
        if (v.hasDangerSign) {
          s += _ancDangerSign;
          drivers.add('anc-danger-sign');
        }
        // Eclampsia / pre-eclampsia (25 pts)
        if (v.hasEclampsia) {
          s += _ancEclampsia;
          drivers.add('anc-eclampsia');
        }
        // High BP ≥ 140/90 (20 pts)
        final sys = v.systolicBp;
        final dia = v.diastolicBp;
        if ((sys != null && sys >= 140) || (dia != null && dia >= 90)) {
          s += _ancHighBp;
          drivers.add('anc-high-bp:${sys ?? 0}/${dia ?? 0}');
        }
        // Severe anaemia Hb < 7 g/dL (20 pts)
        final hb = v.hemoglobin;
        if (hb != null) {
          if (hb < 7.0) {
            s += _ancSevereAnaemia;
            drivers.add('anc-anaemia-severe:${hb.toStringAsFixed(1)}');
          } else if (hb < 11.0) {
            // Moderate anaemia 7–10.9 g/dL (10 pts)
            s += _ancModeratAnaemia;
            drivers.add('anc-anaemia-moderate:${hb.toStringAsFixed(1)}');
          }
        }
        // Primigravida: parity = 0 (5 pts)
        if (v.parity != null && v.parity == 0) {
          s += _ancPrimigravida;
          drivers.add('anc-primigravida');
        }
      }

      // Missed ANC visit > 28 days (15 pts) — via daysSinceLastVisit
      final days = f.daysSinceLastVisit;
      if (days != null && days > 28) {
        s += _ancMissedVisit;
        drivers.add('anc-missed-visit:${days}d');
      }
    }

    // ── NCD clinical rules (§2.8.2) ─────────────────────────────────────────
    if (f.programmes.contains(Programme.ncd)) {
      final v = f.vitals;
      final sys = v?.systolicBp;
      final dia = v?.diastolicBp;
      final hasHtn = (sys != null && sys >= 140) || (dia != null && dia >= 90);
      final hasDm  = v?.hasDiabetes ?? false;

      if (v != null && sys != null && dia != null) {
        if (sys >= 160 || dia >= 100) {
          // Stage 2 HTN (25 pts)
          s += _ncdStage2Htn;
          drivers.add('ncd-htn-stage2:$sys/$dia');
        } else if (sys >= 140 || dia >= 90) {
          // Stage 1 HTN (20 pts)
          s += _ncdStage1Htn;
          drivers.add('ncd-htn-stage1:$sys/$dia');
        } else if (sys >= 130 || dia >= 80) {
          // Elevated / pre-hypertension (10 pts)
          s += _ncdElevatedBp;
          drivers.add('ncd-elevated-bp:$sys/$dia');
        }
      }

      // Poorly controlled DM: fasting ≥ 180 mg/dL ≈ 10 mmol/L (20 pts)
      final glu = v?.fastingGlucoseMgDl;
      if (glu != null && glu >= 180) {
        s += _ncdPoorlyControlledDm;
        drivers.add('ncd-dm-poor-control:${glu.toStringAsFixed(0)}');
      }

      // Comorbidity: HTN + DM (20 pts, additive)
      if (hasHtn && hasDm) {
        s += _ncdComorbidHtnDm;
        drivers.add('ncd-comorbid-htn-dm');
      }

      // Missed NCD follow-up > 42 days (15 pts)
      final days = f.daysSinceLastVisit;
      if (days != null && days > 42) {
        s += _ncdMissedFollowUp;
        drivers.add('ncd-missed-followup:${days}d');
      }

      // Elderly ≥ 60 years (5 pts)
      final age = f.ageYears;
      if (age != null && age >= 60) {
        s += _ncdElderly;
        drivers.add('ncd-elderly:$age');
      }
    }

    // ── Programme fallback (non-ANC / non-NCD programmes) ───────────────────
    for (final p in f.programmes) {
      switch (p) {
        case Programme.tb:
          s += _weightProgrammeTb;
          drivers.add('tb');
          break;
        case Programme.imci:
          s += _weightProgrammeImci;
          drivers.add('imci');
          break;
        case Programme.anc:
        case Programme.ncd:
        case Programme.pnc:
        case Programme.epi:
        case Programme.nutrition:
        case Programme.familyPlanning:
        case Programme.cataract:
        case Programme.eyeCare:
        case Programme.unknown:
          break;
      }
    }

    // ── Age < 5 (not in ANC/NCD tables — keep for IMCI/EPI) ─────────────────
    final age = f.ageYears;
    if (age != null && age < 5 && !f.programmes.contains(Programme.anc)) {
      s += _weightAgeUnder5;
      drivers.add('under-5:$age');
    }

    // ── Missed-visit fallback (no vitals, not ANC or NCD) ───────────────────
    final hasVitals = f.vitals != null;
    final isAncOrNcd = f.programmes.contains(Programme.anc) ||
        f.programmes.contains(Programme.ncd);
    if (!hasVitals && !isAncOrNcd && f.missedVisitsLast90d > 0) {
      final bump = (f.missedVisitsLast90d * _weightPerMissedVisit)
          .clamp(0, _weightMissedVisitCap);
      s += bump;
      drivers.add('missed-visits:${f.missedVisitsLast90d}');
    }

    if (f.lostToFollowUp) {
      s += _weightLostToFollowUp;
      drivers.add('lost-to-follow-up');
    }

    // ── Server hints ─────────────────────────────────────────────────────────
    final color = f.serverRiskColor?.toUpperCase();
    if (color == 'RED') {
      s += _weightServerRed;
      drivers.add('server-risk-red');
    } else if (color == 'YELLOW' || color == 'AMBER') {
      s += _weightServerYellow;
      drivers.add('server-risk-yellow');
    }

    final hint = f.serverRiskLevel?.toUpperCase();
    if (hint == 'HIGH' || f.redFlag) {
      if (s < _redFlagFloor) {
        s = _redFlagFloor;
        drivers.add(f.redFlag ? 'clinician-red-flag' : 'server-risk-high');
      }
    }

    s = s.clamp(0, 100);
    final band = _bandFor(s);
    if (drivers.isEmpty) drivers.add('no-programme');

    final now = DateTime.now();
    final rationale = RiskRationale(
      drivers: List.unmodifiable(drivers),
      modelVersion: modelVersion,
      computedAt: now,
      humanReviewRequired: band == RiskBand.urgent,
      guidelineIds: const <String>[],
      sourceObservationIds: const <String>[],
    );

    return RiskAssessment(
      score: s,
      band: band,
      programmes: f.programmes,
      reasons: rationale.formattedReasons,
      rationale: rationale,
    );
  }

  static RiskBand _bandFor(int score) {
    if (score >= _bandUrgentMin) return RiskBand.urgent;
    if (score >= _bandHighMin)   return RiskBand.high;
    if (score >= _bandModerateMin) return RiskBand.moderate;
    return RiskBand.low;
  }
}
