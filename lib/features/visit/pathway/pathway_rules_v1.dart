import '../../../core/models/programme.dart';
import '../triage/patient_context_builder.dart';

/// WHO-derived clinical thresholds for pathway activation.
///
/// These constants are subject to clinical sign-off and may be
/// localized by national protocol. Each constant includes a doc
/// comment citing the WHO source.
abstract final class PathwayThresholds {
  PathwayThresholds._();

  // ═══════════════════════════════════════════════════════════════════════════
  // NUTRITION — WHO Child Growth Standards
  // ═══════════════════════════════════════════════════════════════════════════

  /// MUAC threshold for severe acute malnutrition (red zone).
  /// Source: WHO IMCI 2014, WHO Child Growth Standards
  static const double muacRedCm = 11.5;

  /// MUAC threshold for moderate acute malnutrition (yellow zone).
  /// Source: WHO IMCI 2014
  static const double muacYellowCm = 12.5;

  // ═══════════════════════════════════════════════════════════════════════════
  // BLOOD PRESSURE — WHO HEARTS / WHO ANC 2016
  // ═══════════════════════════════════════════════════════════════════════════

  /// Systolic BP threshold for hypertension.
  /// Source: WHO HEARTS Technical Package
  static const int bpSystolicThreshold = 140;

  /// Diastolic BP threshold for hypertension.
  /// Source: WHO HEARTS Technical Package
  static const int bpDiastolicThreshold = 90;

  /// Systolic BP threshold for severe hypertension (emergency referral).
  /// Source: WHO ANC 2016
  static const int bpSystolicSevere = 160;

  /// Diastolic BP threshold for severe hypertension (emergency referral).
  /// Source: WHO ANC 2016
  static const int bpDiastolicSevere = 110;

  // ═══════════════════════════════════════════════════════════════════════════
  // BLOOD GLUCOSE — WHO PEN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fasting blood glucose threshold for diabetes (mg/dL).
  /// Source: WHO PEN Protocol
  static const double glucoseFastingThreshold = 126;

  /// Random blood glucose threshold for diabetes (mg/dL).
  /// Source: WHO PEN Protocol
  static const double glucoseRandomThreshold = 200;

  // ═══════════════════════════════════════════════════════════════════════════
  // TB SCREENING — WHO 4-Symptom Screen
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cough duration threshold for presumptive TB screening (days).
  /// Source: WHO 4-Symptom Screen for TB
  static const int coughDurationTbDays = 14;

  // ═══════════════════════════════════════════════════════════════════════════
  // AGE GATES — WHO IMCI / IMNCI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Maximum age for neonate classification (months, exclusive).
  /// Source: WHO IMNCI
  static const int neonateMaxAgeMonths = 2;

  /// Maximum age for ICCM/IMCI classification (months, exclusive).
  /// Source: Bangladesh UHIS Phase 1 spec — 0–24 months (not WHO IMCI 5-year cap)
  static const int imciMaxAgeMonths = 24;

  /// Minimum age for adult NCD screening (months).
  /// Source: Bangladesh UHIS Phase 1 spec — NCD & Eye Care eligibility ≥ 30 years
  static const int adultMinAgeMonths = 360; // 30 years

  /// Minimum age for pediatric HTN screening if known HTN (months).
  /// Source: WHO PEN / AAP Guidelines
  static const int pediatricHtnMinAgeMonths = 60; // 5 years

  /// Minimum age for FP and maternal health programmes (months).
  /// Source: Bangladesh UHIS Phase 1 spec — FP & Maternal Health: female ≥ 14 years
  static const int reproductiveMinAgeMonths = 168; // 14 years

  // ═══════════════════════════════════════════════════════════════════════════
  // PNC WINDOW
  // ═══════════════════════════════════════════════════════════════════════════

  /// Postpartum window duration (days).
  /// Source: WHO PNC Guidelines
  static const int pncWindowDays = 42; // 6 weeks
}

/// Demographic gate for pathway activation.
///
/// Specifies age, sex, and pregnancy requirements for a pathway to be eligible.
class DemographicGate {
  const DemographicGate({
    this.minAgeMonths,
    this.maxAgeMonths,
    this.sex,
    this.requiresPregnancy = false,
    this.requiresPostpartum = false,
  });

  /// Minimum age in months (inclusive). Null = no minimum.
  final int? minAgeMonths;

  /// Maximum age in months (exclusive). Null = no maximum.
  final int? maxAgeMonths;

  /// Required sex. Null = any sex.
  final Sex? sex;

  /// Whether pregnancy is required.
  final bool requiresPregnancy;

  /// Whether postpartum status is required.
  final bool requiresPostpartum;

  /// Empty gate — all demographics pass.
  static const any = DemographicGate();

  /// Evaluate whether a patient context passes this gate.
  bool evaluate(PatientContext ctx) {
    // Age checks
    if (minAgeMonths != null && ctx.ageMonths < minAgeMonths!) {
      return false;
    }
    if (maxAgeMonths != null && ctx.ageMonths >= maxAgeMonths!) {
      return false;
    }

    // Sex check
    if (sex != null && ctx.sex != sex && ctx.sex != Sex.unknown) {
      return false;
    }

    // Pregnancy check
    if (requiresPregnancy && !ctx.isPregnant) {
      return false;
    }

    // Postpartum check
    if (requiresPostpartum && !ctx.isPostpartum) {
      return false;
    }

    return true;
  }
}

/// A pathway activation rule.
///
/// Rules are WHO-derived and hardcoded for v1. The schema is designed
/// for future admin-service configuration (Phase 7).
class PathwayRule {
  const PathwayRule({
    required this.programme,
    required this.priority,
    this.anyOf = const {},
    this.combinations = const [],
    this.gate = DemographicGate.any,
    this.historyTriggers = const {},
    required this.rationaleKey,
    this.suppressedBy,
  });

  /// Target programme for this pathway.
  final Programme programme;

  /// Priority order (lower = higher priority).
  /// Acute programmes < 100, scheduled programmes >= 100.
  final int priority;

  /// Single symptom codes that activate this pathway (OR logic).
  final Set<String> anyOf;

  /// Combinations of symptom codes that activate this pathway (all-of within set, OR across sets).
  final List<Set<String>> combinations;

  /// Demographic gate (age, sex, pregnancy).
  final DemographicGate gate;

  /// History triggers — condition codes or flags that activate this pathway.
  /// Example: 'HYPERTENSION', 'TB_SCREEN_DUE'
  final Set<String> historyTriggers;

  /// Localization key for the rationale string.
  final String rationaleKey;

  /// Programme that suppresses this one when both activate.
  /// Example: Neonate suppresses ICCM.
  final Programme? suppressedBy;
}

/// Registry of all pathway activation rules (WHO-derived v1).
///
/// Rules are ordered by priority. The rule table is the single source
/// of truth for pathway activation logic.
abstract final class PathwayRulesV1 {
  PathwayRulesV1._();

  /// All rules, sorted by priority (ascending = higher priority first).
  static const List<PathwayRule> all = [
    // ═════════════════════════════════════════════════════════════════════════
    // NEONATE (Priority 1) — replaces ICCM when age < 2 months
    // Source: WHO IMNCI
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.imci, // Uses IMCI programme type but neonate forms
      priority: 1,
      anyOf: {
        'fever',
        'cough',
        'difficulty_breathing',
        'diarrhea',
        'vomiting',
        'not_eating',
        'convulsions',
        'lethargy',
        'umbilicus_red',
        'jaundice',
        'skin_rash',
      },
      gate: DemographicGate(
        maxAgeMonths: PathwayThresholds.neonateMaxAgeMonths,
      ),
      rationaleKey: 'pathwayNeonateRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // ICCM (Priority 10) — Children 2-59 months
    // Source: WHO IMCI 2014
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.imci,
      priority: 10,
      anyOf: {
        'fever',
        'cough',
        'diarrhea',
        'difficulty_breathing',
        'breathlessness', // synonym for difficulty_breathing
        'convulsions',
        'lethargy',
        'weakness', // synonym for lethargy
        'not_eating',
        'vomiting',
        'abdominal_pain',
        'painful_urination',
        'chest_indrawing',
        'stridor',
        'muac_red',
        'visible_wasting',
        'weight_loss',
        'edema_both_feet',
        'ear_problem',
        'skin_rash',
        'eye_discharge',
      },
      gate: DemographicGate(
        minAgeMonths: PathwayThresholds.neonateMaxAgeMonths,
        maxAgeMonths: PathwayThresholds.imciMaxAgeMonths,
      ),
      rationaleKey: 'pathwayIccmRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // ANC (Priority 20) — Confirmed pregnant women
    // Source: WHO ANC 2016
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.anc,
      priority: 20,
      anyOf: {
        'pregnant',
        'vaginal_bleeding',
        'water_break',
        'leaking_fluid_vagina',
        'reduced_fetal_movement',
        'labor_signs',
        'painful_uterine_contractions',
        'heavy_bleeding',
        'foul_smelling_vaginal_discharge',
        'swelling_face_hands',
        'abdominal_pain',
        'blurred_vision',
        'headache_severe',
        'edema',
        // Extended ANC symptom set — WHO ANC 2016 + clinical guidance
        'convulsions',
        'fever',
        'dizziness',
        'high_bp_known',
        'chest_pain',
        'one_sided_weakness',
        'palpitations',
        'shortness_breath',
        'polydipsia',
        'numbness',
        'foot_wound',
        'weakness',
        'weight_loss',
      },
      // Female-only, pregnant, minimum 10 years — prevents ANC firing on
      // male patients or infants with corrupted isPregnant flags.
      gate: DemographicGate(
        sex: Sex.female,
        requiresPregnancy: true,
        minAgeMonths: PathwayThresholds.reproductiveMinAgeMonths,
      ),
      historyTriggers: {'PREGNANCY', 'ANC'},
      rationaleKey: 'pathwayAncRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // ANC Symptom-Detected (Priority 21) — Pregnancy implied by symptoms
    //
    // Activates ANC when the patient selects symptoms that are only possible
    // during pregnancy/labour, even if the SK has not yet recorded pregnancy.
    // This handles the common field case where the SK picks symptoms first
    // and records demographics after.
    // Source: WHO ANC 2016 danger signs
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.anc,
      priority: 21,
      anyOf: {
        'reduced_fetal_movement',
        'leaking_fluid_vagina',
        'painful_uterine_contractions',
        'water_break',
        'one_sided_weakness', // stroke-sign — activate ANC even if pregnancy unrecorded
      },
      gate: DemographicGate(
        sex: Sex.female,
        // requiresPregnancy intentionally false: symptoms themselves imply
        // pregnancy when the profile hasn't been updated yet.
        minAgeMonths: PathwayThresholds.reproductiveMinAgeMonths,
      ),
      rationaleKey: 'pathwayAncRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // PNC (Priority 25) — Confirmed postpartum women (< 6 weeks)
    // Source: WHO PNC Guidelines
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.pnc,
      priority: 25,
      anyOf: {
        'fever',
        'vaginal_bleeding',
        'headache_severe',
        'headache',    // triage catalog alias
        'dizziness',   // triage catalog symptom
        'blurred_vision',
        'swelling_face_hands',
        'abdominal_pain',
        'perineal_wound_discharge', // postpartum wound complication
        'breast_pain',              // mastitis / engorgement
        'breast_swelling',          // mastitis / engorgement
        'foul_smelling_vaginal_discharge', // postpartum infection
      },
      // Female-only, postpartum, minimum 10 years — same guard as ANC.
      gate: DemographicGate(
        sex: Sex.female,
        requiresPostpartum: true,
        minAgeMonths: PathwayThresholds.reproductiveMinAgeMonths,
      ),
      historyTriggers: {'PNC', 'POSTNATAL'},
      rationaleKey: 'pathwayPncRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // PNC Symptom-Detected (Priority 26) — Postpartum implied by symptoms
    //
    // Activates PNC when the patient selects symptoms only possible after
    // delivery, even if isPostpartum is not yet recorded in the profile.
    // Source: WHO PNC Guidelines
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.pnc,
      priority: 26,
      anyOf: {
        'perineal_wound_discharge', // only after vaginal delivery
      },
      gate: DemographicGate(
        sex: Sex.female,
        // requiresPostpartum intentionally false: symptom itself implies
        // recent delivery when postpartum status isn't yet recorded.
        minAgeMonths: PathwayThresholds.reproductiveMinAgeMonths,
      ),
      rationaleKey: 'pathwayPncRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // TB SCREEN (Priority 30)
    // Source: WHO 4-Symptom Screen
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.tb,
      priority: 30,
      anyOf: {
        'cough_over_2_weeks',
        'cough',       // triage catalog alias (SK-facing label 'Cough')
        'hemoptysis',
        'tb_contact',
      },
      combinations: [
        {'night_sweats', 'weight_loss'},
        {'night_sweats', 'fever'},
        {'weakness', 'weight_loss'}, // triage catalog: 'Feeling weak' + 'Losing weight'
        {'weakness', 'fever'},
      ],
      gate: DemographicGate.any,
      historyTriggers: {'TB_SCREEN_DUE', 'TUBERCULOSIS', 'PRESUMPTIVE_TB'},
      rationaleKey: 'pathwayTbScreenRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // NCD-HTN (Priority 40)
    // Source: WHO HEARTS Technical Package
    // Gate: age ≥ 5 years (60 months) — starts where ICCM ends so that
    // adolescents and adults with BP/neuro symptoms are not left without a form.
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.ncd,
      priority: 40,
      anyOf: {
        'high_bp_known',
        'headache_severe',
        'headache',
        'dizziness',
        'chest_pain',
        'blurred_vision',
        'weakness',
        'fatigue',
        'breathlessness',
        'numbness',
      },
      gate: DemographicGate(
        minAgeMonths: PathwayThresholds.imciMaxAgeMonths, // 60 months / 5 yrs
      ),
      historyTriggers: {'HYPERTENSION', 'HTN', 'I10'},
      rationaleKey: 'pathwayNcdHtnRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // NCD-DM (Priority 41)
    // Source: WHO PEN Protocol
    // Gate: age ≥ 5 years (60 months) — same lower bound as NCD-HTN.
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.ncd,
      priority: 41,
      combinations: [
        // Classic diabetes symptom combo
        {'polyuria', 'polydipsia'},
      ],
      anyOf: {
        'numbness',
        'foot_wound',
        'weight_loss',
      },
      gate: DemographicGate(
        minAgeMonths: PathwayThresholds.imciMaxAgeMonths, // 60 months / 5 yrs
      ),
      historyTriggers: {'DIABETES', 'DM', 'E11'},
      rationaleKey: 'pathwayNcdDmRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // NUTRITION (Priority 50)
    // Source: WHO Child Growth Standards
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.imci,
      priority: 50,
      anyOf: {
        'muac_red',
        'visible_wasting',
        'edema_both_feet',
      },
      combinations: [
        // Not eating + wasting combo
        {'not_eating', 'visible_wasting'},
      ],
      gate: DemographicGate(
        maxAgeMonths: PathwayThresholds.imciMaxAgeMonths,
      ),
      rationaleKey: 'pathwayNutritionRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // FAMILY PLANNING (Priority 60)
    // Source: WHO Family Planning Guidelines 2022
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.familyPlanning,
      priority: 60,
      anyOf: {
        'no_family_planning',
        'wants_contraception',
      },
      gate: DemographicGate(
        sex: Sex.female,
        minAgeMonths: 180,
        maxAgeMonths: 588,
      ),
      historyTriggers: {
        'FP_COUNSELLING_DUE',
        'PPFP_WINDOW',
        'UNMET_FP_NEED',
      },
      rationaleKey: 'pathwayFamilyPlanningRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // CATARACT (Priority 70)
    // Source: WHO VISION 2020
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.cataract,
      priority: 70,
      anyOf: {
        'blurred_vision',
        'eye_pain',
        'gradual_vision_loss',
      },
      gate: DemographicGate.any,
      historyTriggers: {
        'CATARACT',
        'EYE_DISEASE',
        'VISUAL_IMPAIRMENT',
      },
      rationaleKey: 'pathwayCataractRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // EYE CARE (Priority 75)
    // Source: WHO Primary Eye Care Guidelines
    // Suppressed by Cataract when both would activate (cataract more specific).
    // ═════════════════════════════════════════════════════════════════════════
    PathwayRule(
      programme: Programme.eyeCare,
      priority: 75,
      anyOf: {
        'blurred_vision',
        'reduced_vision',
        'eye_pain',
      },
      gate: DemographicGate.any,
      historyTriggers: {
        'EYE_CARE',
        'GLAUCOMA',
        'REFRACTIVE_ERROR',
        'POST_OP_EYE',
      },
      suppressedBy: Programme.cataract,
      rationaleKey: 'pathwayEyeCareRationale',
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // SCHEDULED: EPI (Priority 100)
    // Source: National Immunization Schedule
    // ═════════════════════════════════════════════════════════════════════════
    // EPI is triggered via openFlags (EPI_DUE) and overdueImmunizations,
    // not via symptoms. The PathwayEngine handles this specially.
  ];

  /// Get rules for a specific programme.
  static List<PathwayRule> forProgramme(Programme programme) {
    return all.where((r) => r.programme == programme).toList();
  }

  /// Get the highest priority rule that matches the given symptoms and context.
  static PathwayRule? firstMatch(
    Set<String> symptoms,
    PatientContext ctx,
  ) {
    for (final rule in all) {
      if (_evaluateRule(rule, symptoms, ctx)) {
        return rule;
      }
    }
    return null;
  }

  static bool _evaluateRule(
    PathwayRule rule,
    Set<String> symptoms,
    PatientContext ctx,
  ) {
    // Check demographic gate
    if (!rule.gate.evaluate(ctx)) return false;

    // Check anyOf symptoms (OR logic)
    if (rule.anyOf.isNotEmpty) {
      if (symptoms.any((s) => rule.anyOf.contains(s))) {
        return true;
      }
    }

    // Check combinations (all-of within set, OR across sets)
    for (final combo in rule.combinations) {
      if (combo.every((s) => symptoms.contains(s))) {
        return true;
      }
    }

    // Check history triggers
    if (rule.historyTriggers.isNotEmpty) {
      // Check known conditions
      if (ctx.knownConditions.any((c) => rule.historyTriggers.contains(c))) {
        return true;
      }
      // Check open flags
      if (ctx.openFlags.any((f) => rule.historyTriggers.contains(f))) {
        return true;
      }
      // Check active programmes
      for (final prog in ctx.activeProgrammes) {
        if (rule.historyTriggers.contains(prog.wireTag)) {
          return true;
        }
      }
    }

    return false;
  }
}
