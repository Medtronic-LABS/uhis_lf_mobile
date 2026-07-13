import '../../../core/models/programme.dart';

/// Symptom clusters for grouping in the triage picker UI.
///
/// Danger signs are always pinned first and visually distinct.
enum SymptomCluster {
  dangerSigns,
  feverRespiratory,
  giNutrition,
  maternal,
  ncdMetabolic,
  tbIndicators,
  mentalHealth,
  childHealth,
}

/// A unified symptom definition for the triage checklist.
///
/// Extends the original [SymptomDef] shape with cluster grouping
/// and SNOMED-CT codes for interoperability.
class UnifiedSymptomDef {
  const UnifiedSymptomDef({
    required this.code,
    required this.labelKey,
    required this.cluster,
    this.icon,
    this.emoji,
    this.programmes = const {},
    this.isDangerSign = false,
    this.snomedCode,
    this.requiresFemale = false,
    this.maxAgeMonths,
  });

  /// Canonical code, e.g. 'cough', 'fever'. Used as fieldId for deduplication.
  final String code;

  /// Key into [TriageStrings] for localized label. Matches app_strings.dart pattern.
  final String labelKey;

  /// UI grouping cluster.
  final SymptomCluster cluster;

  /// Material icon name for tile display (fallback when [emoji] is null).
  final String? icon;

  /// Emoji character displayed prominently in the symptom tile.
  ///
  /// When present, replaces the Material icon in the tile. Chosen to be
  /// immediately recognisable to community health workers without literacy.
  final String? emoji;

  /// Programmes that this symptom is relevant to.
  final Set<Programme> programmes;

  /// Whether this symptom is a danger sign requiring immediate attention.
  final bool isDangerSign;

  /// SNOMED-CT code for interoperability (e.g., cough = 49727002).
  final String? snomedCode;

  /// If true, hide this symptom for male patients.
  ///
  /// Symptoms that are anatomically or clinically exclusive to female patients
  /// (pregnancy-related findings, obstetric danger signs) should set this to
  /// true.  Unknown sex shows the symptom.
  final bool requiresFemale;

  /// Maximum patient age in months for this symptom to be relevant.
  ///
  /// Null means no upper limit.  Used to hide neonatal findings (e.g.,
  /// umbilicus redness) from adult patients.
  final int? maxAgeMonths;
}

/// Unified catalog of all symptoms across programmes.
///
/// Merges per-programme symptom lists into a single source of truth.
/// Deduplication: a symptom code (e.g., 'fever') appears once with
/// merged [programmes] sets from IMCI + TB + general.
class UnifiedSymptomCatalog {
  UnifiedSymptomCatalog._();

  // ═══════════════════════════════════════════════════════════════════════════
  // DANGER SIGNS (pinned first in UI, visually distinct)
  // ═══════════════════════════════════════════════════════════════════════════
  static const _dangerSigns = <UnifiedSymptomDef>[
    UnifiedSymptomDef(
      code: 'convulsions',
      labelKey: 'symptomConvulsions',
      cluster: SymptomCluster.dangerSigns,
      icon: 'warning',
      emoji: '⚡',
      programmes: {Programme.imci, Programme.anc, Programme.pnc},
      isDangerSign: true,
      snomedCode: '91175000',
    ),
    UnifiedSymptomDef(
      code: 'unconscious',
      labelKey: 'symptomUnconscious',
      cluster: SymptomCluster.dangerSigns,
      icon: 'warning',
      emoji: '😵',
      programmes: {Programme.imci, Programme.anc, Programme.ncd},
      isDangerSign: true,
      snomedCode: '419045004',
    ),
    UnifiedSymptomDef(
      code: 'lethargy',
      labelKey: 'symptomLethargy',
      cluster: SymptomCluster.dangerSigns,
      icon: 'bedtime',
      emoji: '😴',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '214264003',
    ),
    UnifiedSymptomDef(
      code: 'not_eating',
      labelKey: 'symptomNotEating',
      cluster: SymptomCluster.dangerSigns,
      icon: 'no_food',
      emoji: '🍼',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '79890006',
    ),
    UnifiedSymptomDef(
      code: 'chest_indrawing',
      labelKey: 'symptomChestIndrawing',
      cluster: SymptomCluster.dangerSigns,
      icon: 'warning',
      emoji: '😮‍💨',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '248595007',
    ),
    UnifiedSymptomDef(
      code: 'stridor',
      labelKey: 'symptomStridor',
      cluster: SymptomCluster.dangerSigns,
      icon: 'warning',
      emoji: '🌬️',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '70407001',
    ),
    UnifiedSymptomDef(
      code: 'vaginal_bleeding',
      labelKey: 'symptomVaginalBleeding',
      cluster: SymptomCluster.dangerSigns,
      icon: 'water_drop',
      emoji: '🩸',
      programmes: {Programme.anc, Programme.pnc},
      isDangerSign: true,
      snomedCode: '266599000',
      requiresFemale: true,
    ),
    UnifiedSymptomDef(
      code: 'water_break',
      labelKey: 'symptomWaterBreak',
      cluster: SymptomCluster.dangerSigns,
      icon: 'water',
      emoji: '💧',
      programmes: {Programme.anc},
      isDangerSign: true,
      snomedCode: '289259007',
      requiresFemale: true,
    ),
    UnifiedSymptomDef(
      code: 'reduced_fetal_movement',
      labelKey: 'symptomReducedFetalMovement',
      cluster: SymptomCluster.dangerSigns,
      icon: 'child_care',
      emoji: '👶',
      programmes: {Programme.anc},
      isDangerSign: true,
      snomedCode: '276367008',
      requiresFemale: true,
    ),
    UnifiedSymptomDef(
      code: 'chest_pain',
      labelKey: 'symptomChestPain',
      cluster: SymptomCluster.dangerSigns,
      icon: 'favorite',
      emoji: '💔',
      programmes: {Programme.anc, Programme.ncd, Programme.tb},
      isDangerSign: true,
      snomedCode: '29857009',
    ),
    UnifiedSymptomDef(
      code: 'one_sided_weakness',
      labelKey: 'symptomOneSidedWeakness',
      cluster: SymptomCluster.dangerSigns,
      icon: 'warning',
      emoji: '🫀',
      programmes: {Programme.anc, Programme.ncd},
      isDangerSign: true,
      snomedCode: '230690007',
    ),
    UnifiedSymptomDef(
      code: 'hemoptysis',
      labelKey: 'symptomHemoptysis',
      cluster: SymptomCluster.dangerSigns,
      icon: 'water_drop',
      emoji: '🩸',
      programmes: {Programme.tb},
      isDangerSign: true,
      snomedCode: '66857006',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // FEVER & RESPIRATORY
  // ═══════════════════════════════════════════════════════════════════════════
  static const _feverRespiratory = <UnifiedSymptomDef>[
    UnifiedSymptomDef(
      code: 'fever',
      labelKey: 'symptomFever',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'thermostat',
      emoji: '🌡️',
      programmes: {Programme.imci, Programme.anc, Programme.tb},
      snomedCode: '386661006',
    ),
    UnifiedSymptomDef(
      code: 'cough',
      labelKey: 'symptomCough',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      emoji: '🤧',
      programmes: {Programme.imci, Programme.tb},
      snomedCode: '49727002',
    ),
    UnifiedSymptomDef(
      code: 'cough_over_2_weeks',
      labelKey: 'symptomCoughOver2Weeks',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      emoji: '🤧',
      programmes: {Programme.tb},
      snomedCode: '49727002',
    ),
    UnifiedSymptomDef(
      code: 'difficulty_breathing',
      labelKey: 'symptomDifficultyBreathing',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      emoji: '😮‍💨',
      programmes: {Programme.imci, Programme.ncd},
      isDangerSign: true,
      snomedCode: '267036007',
    ),
    UnifiedSymptomDef(
      code: 'fast_breathing',
      labelKey: 'symptomFastBreathing',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      emoji: '💨',
      programmes: {Programme.imci},
      snomedCode: '271823003',
    ),
    UnifiedSymptomDef(
      code: 'shortness_breath',
      labelKey: 'symptomShortnessBreath',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      emoji: '😮‍💨',
      programmes: {Programme.anc, Programme.ncd, Programme.tb},
      snomedCode: '267036007',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // GI & NUTRITION
  // ═══════════════════════════════════════════════════════════════════════════
  static const _giNutrition = <UnifiedSymptomDef>[
    UnifiedSymptomDef(
      code: 'diarrhea',
      labelKey: 'symptomDiarrhea',
      cluster: SymptomCluster.giNutrition,
      icon: 'water_drop',
      emoji: '🚽',
      programmes: {Programme.imci},
      snomedCode: '62315008',
    ),
    UnifiedSymptomDef(
      code: 'bloody_diarrhea',
      labelKey: 'symptomBloodyDiarrhea',
      cluster: SymptomCluster.giNutrition,
      icon: 'water_drop',
      emoji: '🩸',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '95545007',
    ),
    UnifiedSymptomDef(
      code: 'vomiting',
      labelKey: 'symptomVomiting',
      cluster: SymptomCluster.giNutrition,
      icon: 'sick',
      emoji: '🤢',
      programmes: {Programme.imci, Programme.anc},
      snomedCode: '422400008',
    ),
    UnifiedSymptomDef(
      code: 'loss_appetite',
      labelKey: 'symptomLossAppetite',
      cluster: SymptomCluster.giNutrition,
      icon: 'no_food',
      emoji: '🍽️',
      programmes: {Programme.imci, Programme.tb},
      snomedCode: '79890006',
    ),
    UnifiedSymptomDef(
      code: 'muac_red',
      labelKey: 'symptomMuacRed',
      cluster: SymptomCluster.giNutrition,
      icon: 'straighten',
      emoji: '📏',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '248325000',
    ),
    UnifiedSymptomDef(
      code: 'visible_wasting',
      labelKey: 'symptomVisibleWasting',
      cluster: SymptomCluster.giNutrition,
      icon: 'trending_down',
      emoji: '📉',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '271807003',
    ),
    UnifiedSymptomDef(
      code: 'edema_both_feet',
      labelKey: 'symptomEdemaBothFeet',
      cluster: SymptomCluster.giNutrition,
      icon: 'bubble_chart',
      emoji: '🦶',
      programmes: {Programme.imci, Programme.anc, Programme.ncd},
      isDangerSign: true,
      snomedCode: '267038008',
    ),
    UnifiedSymptomDef(
      code: 'weight_loss',
      labelKey: 'symptomWeightLoss',
      cluster: SymptomCluster.giNutrition,
      icon: 'trending_down',
      emoji: '⚖️',
      programmes: {Programme.anc, Programme.tb, Programme.ncd},
      snomedCode: '89362005',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // MATERNAL
  // ═══════════════════════════════════════════════════════════════════════════
  static const _maternal = <UnifiedSymptomDef>[
    UnifiedSymptomDef(
      code: 'pregnant',
      labelKey: 'symptomPregnant',
      cluster: SymptomCluster.maternal,
      icon: 'pregnant_woman',
      emoji: '🤰',
      programmes: {Programme.anc},
      snomedCode: '77386006',
      requiresFemale: true,
    ),
    UnifiedSymptomDef(
      code: 'headache_severe',
      labelKey: 'symptomHeadacheSevere',
      cluster: SymptomCluster.maternal,
      icon: 'psychology',
      emoji: '🤕',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '25064002',
    ),
    UnifiedSymptomDef(
      code: 'blurred_vision',
      labelKey: 'symptomBlurredVision',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'visibility_off',
      emoji: '👁️',
      programmes: {Programme.anc, Programme.ncd, Programme.cataract, Programme.eyeCare},
      snomedCode: '246636008',
    ),
    UnifiedSymptomDef(
      code: 'abdominal_pain',
      labelKey: 'symptomAbdominalPain',
      cluster: SymptomCluster.maternal,
      icon: 'healing',
      emoji: '🩺',
      programmes: {Programme.anc, Programme.imci},
      snomedCode: '21522001',
    ),
    UnifiedSymptomDef(
      code: 'swelling_face_hands',
      labelKey: 'symptomSwellingFaceHands',
      cluster: SymptomCluster.maternal,
      icon: 'bubble_chart',
      emoji: '🫧',
      programmes: {Programme.anc},
      isDangerSign: true,
      snomedCode: '267038008',
      requiresFemale: true,
    ),
    UnifiedSymptomDef(
      code: 'high_bp_known',
      labelKey: 'symptomHighBpKnown',
      cluster: SymptomCluster.maternal,
      icon: 'favorite',
      emoji: '💊',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '38341003',
    ),
    UnifiedSymptomDef(
      code: 'palpitations',
      labelKey: 'symptomPalpitations',
      cluster: SymptomCluster.maternal,
      icon: 'monitor_heart',
      emoji: '💓',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '80313002',
    ),
    UnifiedSymptomDef(
      code: 'labor_signs',
      labelKey: 'symptomLaborSigns',
      cluster: SymptomCluster.maternal,
      icon: 'child_care',
      emoji: '👶',
      programmes: {Programme.anc},
      snomedCode: '289530006',
      requiresFemale: true,
    ),

    // ── Eye symptoms ─────────────────────────────────────────────────────────
    UnifiedSymptomDef(
      code: 'eye_pain',
      labelKey: 'symptomEyePain',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'remove_red_eye',
      emoji: '👁️',
      programmes: {Programme.cataract, Programme.eyeCare},
      snomedCode: '41652007',
    ),
    UnifiedSymptomDef(
      code: 'gradual_vision_loss',
      labelKey: 'symptomGradualVisionLoss',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'visibility',
      emoji: '🔭',
      programmes: {Programme.cataract},
      snomedCode: '246638009',
    ),
    UnifiedSymptomDef(
      code: 'reduced_vision',
      labelKey: 'symptomReducedVision',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'visibility_off',
      emoji: '🕶️',
      programmes: {Programme.eyeCare},
      snomedCode: '397540003',
    ),

    // ── Family planning ───────────────────────────────────────────────────────
    UnifiedSymptomDef(
      code: 'no_family_planning',
      labelKey: 'symptomNoFamilyPlanning',
      cluster: SymptomCluster.maternal,
      icon: 'family_restroom',
      emoji: '👨‍👩‍👧',
      programmes: {Programme.familyPlanning},
      requiresFemale: true,
    ),
    UnifiedSymptomDef(
      code: 'wants_contraception',
      labelKey: 'symptomWantsContraception',
      cluster: SymptomCluster.maternal,
      icon: 'favorite_border',
      emoji: '💊',
      programmes: {Programme.familyPlanning},
      requiresFemale: true,
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // NCD / METABOLIC
  // ═══════════════════════════════════════════════════════════════════════════
  static const _ncdMetabolic = <UnifiedSymptomDef>[
    UnifiedSymptomDef(
      code: 'dizziness',
      labelKey: 'symptomDizziness',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'blur_on',
      emoji: '💫',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '404640003',
    ),
    UnifiedSymptomDef(
      code: 'numbness',
      labelKey: 'symptomNumbness',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'touch_app',
      emoji: '🖐️',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '44077006',
    ),
    UnifiedSymptomDef(
      code: 'polyuria',
      labelKey: 'symptomPolyuria',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'wc',
      emoji: '🚽',
      programmes: {Programme.ncd},
      snomedCode: '28442001',
    ),
    UnifiedSymptomDef(
      code: 'polydipsia',
      labelKey: 'symptomPolydipsia',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'local_drink',
      emoji: '💧',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '17173007',
    ),
    UnifiedSymptomDef(
      code: 'foot_pain',
      labelKey: 'symptomFootPain',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'directions_walk',
      emoji: '🦶',
      programmes: {Programme.ncd},
      snomedCode: '47933007',
    ),
    UnifiedSymptomDef(
      code: 'foot_wound',
      labelKey: 'symptomFootWound',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'healing',
      emoji: '🩹',
      programmes: {Programme.anc, Programme.ncd},
      isDangerSign: true,
      snomedCode: '13954005',
    ),
    UnifiedSymptomDef(
      code: 'weakness',
      labelKey: 'symptomWeakness',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'battery_alert',
      emoji: '🪫',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '13791008',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // TB INDICATORS
  // ═══════════════════════════════════════════════════════════════════════════
  static const _tbIndicators = <UnifiedSymptomDef>[
    UnifiedSymptomDef(
      code: 'night_sweats',
      labelKey: 'symptomNightSweats',
      cluster: SymptomCluster.tbIndicators,
      icon: 'nightlight',
      emoji: '🌙',
      programmes: {Programme.tb},
      snomedCode: '42984000',
    ),
    UnifiedSymptomDef(
      code: 'fatigue',
      labelKey: 'symptomFatigue',
      cluster: SymptomCluster.tbIndicators,
      icon: 'battery_alert',
      emoji: '🔋',
      programmes: {Programme.tb, Programme.ncd},
      snomedCode: '84229001',
    ),
    UnifiedSymptomDef(
      code: 'tb_contact',
      labelKey: 'symptomTbContact',
      cluster: SymptomCluster.tbIndicators,
      icon: 'people',
      emoji: '👥',
      programmes: {Programme.tb},
      snomedCode: '442131005',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // MENTAL HEALTH
  // ═══════════════════════════════════════════════════════════════════════════
  static const _mentalHealth = <UnifiedSymptomDef>[
    UnifiedSymptomDef(
      code: 'feeling_sad',
      labelKey: 'symptomFeelingSad',
      cluster: SymptomCluster.mentalHealth,
      icon: 'sentiment_dissatisfied',
      emoji: '😢',
      programmes: {Programme.ncd, Programme.anc},
      snomedCode: '394924000',
    ),
    UnifiedSymptomDef(
      code: 'anxiety',
      labelKey: 'symptomAnxiety',
      cluster: SymptomCluster.mentalHealth,
      icon: 'psychology',
      emoji: '😰',
      programmes: {Programme.ncd, Programme.anc},
      snomedCode: '48694002',
    ),
    UnifiedSymptomDef(
      code: 'sleep_difficulty',
      labelKey: 'symptomSleepDifficulty',
      cluster: SymptomCluster.mentalHealth,
      icon: 'bedtime_off',
      emoji: '🌙',
      programmes: {Programme.ncd},
      snomedCode: '193462001',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // CHILD HEALTH
  // ═══════════════════════════════════════════════════════════════════════════
  static const _childHealth = <UnifiedSymptomDef>[
    UnifiedSymptomDef(
      code: 'ear_problem',
      labelKey: 'symptomEarProblem',
      cluster: SymptomCluster.childHealth,
      icon: 'hearing',
      emoji: '👂',
      programmes: {Programme.imci},
      snomedCode: '300226004',
    ),
    UnifiedSymptomDef(
      code: 'skin_rash',
      labelKey: 'symptomSkinRash',
      cluster: SymptomCluster.childHealth,
      icon: 'healing',
      emoji: '🔴',
      programmes: {Programme.imci},
      snomedCode: '271807003',
    ),
    UnifiedSymptomDef(
      code: 'eye_discharge',
      labelKey: 'symptomEyeDischarge',
      cluster: SymptomCluster.childHealth,
      icon: 'visibility',
      emoji: '👁️',
      programmes: {Programme.imci},
      snomedCode: '246679005',
    ),
    UnifiedSymptomDef(
      code: 'umbilicus_red',
      labelKey: 'symptomUmbilicusRed',
      cluster: SymptomCluster.childHealth,
      icon: 'warning',
      emoji: '⚠️',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '239095007',
      maxAgeMonths: 3,
    ),
    UnifiedSymptomDef(
      code: 'jaundice',
      labelKey: 'symptomJaundice',
      cluster: SymptomCluster.childHealth,
      icon: 'warning',
      emoji: '💛',
      programmes: {Programme.imci},
      snomedCode: '18165001',
    ),
  ];

  /// All symptoms in the unified catalog, ordered by cluster.
  ///
  /// Danger signs cluster appears first.
  static const List<UnifiedSymptomDef> all = [
    ..._dangerSigns,
    ..._feverRespiratory,
    ..._giNutrition,
    ..._maternal,
    ..._ncdMetabolic,
    ..._tbIndicators,
    ..._mentalHealth,
    ..._childHealth,
  ];

  /// Get symptoms for a specific cluster.
  static List<UnifiedSymptomDef> byCluster(SymptomCluster cluster) {
    return all.where((s) => s.cluster == cluster).toList();
  }

  /// Get all danger sign symptoms.
  static List<UnifiedSymptomDef> get dangerSigns {
    return all.where((s) => s.isDangerSign).toList();
  }

  /// Get symptoms relevant to a specific programme.
  static List<UnifiedSymptomDef> forProgramme(Programme programme) {
    return all.where((s) => s.programmes.contains(programme)).toList();
  }

  /// Lookup a symptom by code.
  static UnifiedSymptomDef? byCode(String code) {
    final index = all.indexWhere((s) => s.code == code);
    return index >= 0 ? all[index] : null;
  }

  /// Get all unique symptom codes.
  static Set<String> get allCodes {
    return all.map((s) => s.code).toSet();
  }
}
