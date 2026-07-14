import '../models/programme.dart';
import '../models/risk.dart';

/// On-device risk scoring for the AI Worklist — spec §2.8.
///
/// Implements the **band + modifier** model (spec V1, June 2026):
/// the *worst single clinical finding* determines the patient's band.
/// Letter modifiers (a, b) rank within a band; no composite score is computed.
/// Band & modifier never surface to the SK — they only drive sort order.
///
/// Sort sequence emitted (via [RiskAssessment.sortRank]):
///   1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4.
class RiskScoringService {
  const RiskScoringService();

  static const String modelVersion = 'on-device-rule-v3-band-modifier';

  RiskAssessment score(PatientFacts f) {
    final drivers = <String>[];

    Band? worst;
    var triggerA = false;
    var triggerB = false;

    void considerBand(Band candidate, String driver) {
      drivers.add(driver);
      if (worst == null || _bandRank(candidate) < _bandRank(worst!)) {
        worst = candidate;
      }
    }

    void markA(String driver) {
      drivers.add(driver);
      triggerA = true;
    }

    void markB(String driver) {
      drivers.add(driver);
      triggerB = true;
    }

    final v = f.vitals;
    final age = f.ageYears;
    final isAnc = f.programmes.contains(Programme.anc);
    final isNcd = f.programmes.contains(Programme.ncd);

    // ── ANC clinical rules (§2.8.1) ─────────────────────────────────────────
    if (isAnc && v != null) {
      // Band 1 — Severe
      if (v.hasDangerSign) {
        considerBand(Band.band1, 'anc-danger-sign');
      }
      final hb = v.hemoglobin;
      if (hb != null && hb < 7.0) {
        considerBand(Band.band1, 'anc-anaemia-severe:${hb.toStringAsFixed(1)}');
      }
      final sys = v.systolicBp;
      final dia = v.diastolicBp;
      if ((sys != null && sys >= 160) || (dia != null && dia >= 110)) {
        considerBand(Band.band1, 'anc-bp-severe:${sys ?? 0}/${dia ?? 0}');
      }

      // Band 2 — Moderate
      if (v.hasEclampsia) {
        considerBand(Band.band2, 'anc-eclampsia');
      }
      if (((sys != null && sys >= 140) || (dia != null && dia >= 90)) &&
          !((sys != null && sys >= 160) || (dia != null && dia >= 110))) {
        considerBand(Band.band2, 'anc-bp-elevated:${sys ?? 0}/${dia ?? 0}');
      }
      if (v.hasAbnormalUrine) {
        considerBand(Band.band2, 'anc-urine-abnormal');
      }
      final glu = v.fastingGlucoseMmolL;
      if (glu != null && glu >= 5.1) {
        considerBand(Band.band2, 'anc-gdm-risk:${glu.toStringAsFixed(1)}');
      }
      if (hb != null && hb >= 7.0 && hb < 10.0) {
        considerBand(Band.band2, 'anc-anaemia-moderate:${hb.toStringAsFixed(1)}');
      }

      // Band 3 — Mild
      if (hb != null && hb >= 10.0 && hb < 11.0) {
        considerBand(Band.band3, 'anc-anaemia-mild:${hb.toStringAsFixed(1)}');
      }
      final ga = v.gestationalAgeWeeks;
      if (ga != null && ga >= 36) {
        considerBand(Band.band3, 'anc-late-term:$ga');
        markA('anc-late-term-modifier');
      }

      // Modifiers
      if (v.parity != null && v.parity == 0) {
        markA('anc-primigravida');
      }
      if (v.hasDiabetes) {
        markA('anc-comorbidity-dm');
      }
    }

    // ── NCD clinical rules (§2.8.2) ─────────────────────────────────────────
    if (isNcd) {
      final sys = v?.systolicBp;
      final dia = v?.diastolicBp;
      final glu = v?.fastingGlucoseMmolL;
      final hasHtn = (sys != null && sys >= 140) || (dia != null && dia >= 90);
      final hasDm = v?.hasDiabetes ?? false;

      // Band 1 — Severe
      if (v != null && v.hasStrokeSign) {
        considerBand(Band.band1, 'ncd-stroke-sign');
      }
      if (v != null && v.hasSobWithHighBp) {
        considerBand(Band.band1, 'ncd-sob-high-bp');
      }
      if ((sys != null && sys >= 180) || (dia != null && dia >= 110)) {
        considerBand(Band.band1, 'ncd-htn-crisis:${sys ?? 0}/${dia ?? 0}');
      }
      if (glu != null && glu >= 18.0) {
        considerBand(Band.band1, 'ncd-dm-crisis:${glu.toStringAsFixed(1)}');
      }

      // Band 2 — Moderate
      if (sys != null && dia != null) {
        if (((sys >= 160 && sys <= 179) || (dia >= 100 && dia <= 109)) &&
            !((sys >= 180) || (dia >= 110))) {
          considerBand(Band.band2, 'ncd-htn-stage2:$sys/$dia');
        }
      }
      if (glu != null && glu >= 10.0 && glu < 18.0) {
        considerBand(Band.band2, 'ncd-dm-poor-control:${glu.toStringAsFixed(1)}');
      }

      // Band 3 — Mild
      if (sys != null && dia != null) {
        if (((sys >= 140 && sys <= 159) || (dia >= 90 && dia <= 99)) &&
            !(sys >= 160 || dia >= 100)) {
          considerBand(Band.band3, 'ncd-htn-stage1:$sys/$dia');
        }
      }
      if (glu != null && glu >= 7.0 && glu < 10.0) {
        considerBand(Band.band3, 'ncd-dm-elevated:${glu.toStringAsFixed(1)}');
      }

      // Band 4 — Routine
      if (sys != null && dia != null) {
        if (((sys >= 130 && sys <= 139) || (dia >= 85 && dia <= 89)) &&
            !(sys >= 140 || dia >= 90)) {
          considerBand(Band.band4, 'ncd-prehtn:$sys/$dia');
        }
      }
      if (glu != null && glu >= 6.1 && glu < 7.0) {
        considerBand(Band.band4, 'ncd-prediabetes:${glu.toStringAsFixed(1)}');
      }

      // Modifiers
      if (hasHtn && hasDm) {
        markA('ncd-comorbid-htn-dm');
      }
      if (age != null && age >= 60) {
        markA('ncd-elderly:$age');
      }
    }

    // ── Overdue follow-up — modifier b ──────────────────────────────────────
    final daysSince = f.daysSinceLastVisit;
    if (isAnc && daysSince != null && daysSince > 28) {
      markB('anc-missed-visit:${daysSince}d');
    } else if (isNcd && daysSince != null && daysSince > 42) {
      markB('ncd-missed-followup:${daysSince}d');
    }

    // ── Non-ANC/NCD programme defaults — keep them visible in the worklist
    //    so SKs don't lose under-5s, TB cases, etc.
    if (worst == null) {
      for (final p in f.programmes) {
        switch (p) {
          case Programme.tb:
            considerBand(Band.band2, 'tb');
            break;
          case Programme.imci:
            considerBand(Band.band3, 'imci');
            break;
          case Programme.pnc:
          case Programme.epi:
          case Programme.nutrition:
          case Programme.familyPlanning:
          case Programme.cataract:
          case Programme.eyeCare:
          case Programme.anc:
          case Programme.pw:
          case Programme.ncd:
          case Programme.unknown:
            break;
        }
      }
      if (age != null && age < 5 && !isAnc) {
        considerBand(Band.band3, 'under-5:$age');
      }
    }

    // ── Adherence signals — apply when no ANC/NCD vitals drove a band ──────
    final hasVitals = v != null;
    if (!hasVitals && !isAnc && !isNcd && f.missedVisitsLast90d > 0) {
      considerBand(Band.band3, 'missed-visits:${f.missedVisitsLast90d}');
      markB('missed-visits-modifier');
    }
    if (f.lostToFollowUp) {
      considerBand(Band.band2, 'lost-to-follow-up');
    }

    // ── Server-side hints — conservative overrides ────────────────────────
    final color = f.serverRiskColor?.toUpperCase();
    if (color == 'RED') {
      considerBand(Band.band1, 'server-risk-red');
    } else if (color == 'YELLOW' || color == 'AMBER') {
      considerBand(Band.band2, 'server-risk-yellow');
    }
    final hint = f.serverRiskLevel?.toUpperCase();
    if (hint == 'HIGH') {
      considerBand(Band.band1, 'server-risk-high');
    }
    if (f.redFlag) {
      considerBand(Band.band1, 'clinician-red-flag');
    }

    // ── Resolve final band + modifier ──────────────────────────────────────
    final band = worst ?? Band.band4;
    final modifier = triggerA
        ? Modifier.a
        : triggerB
            ? Modifier.b
            : Modifier.none;

    if (drivers.isEmpty) drivers.add('no-programme');

    final now = DateTime.now();
    final rationale = RiskRationale(
      drivers: List.unmodifiable(drivers),
      modelVersion: modelVersion,
      computedAt: now,
      humanReviewRequired: band == Band.band1,
      guidelineIds: const <String>[],
      sourceObservationIds: const <String>[],
    );

    return RiskAssessment(
      band: band,
      modifier: modifier,
      programmes: f.programmes,
      reasons: rationale.formattedReasons,
      rationale: rationale,
    );
  }

  static int _bandRank(Band b) => switch (b) {
        Band.band1 => 1,
        Band.band2 => 2,
        Band.band3 => 3,
        Band.band4 => 4,
      };
}
