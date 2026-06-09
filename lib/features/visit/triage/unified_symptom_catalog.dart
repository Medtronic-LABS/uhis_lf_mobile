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
    this.programmes = const {},
    this.isDangerSign = false,
    this.snomedCode,
  });

  /// Canonical code, e.g. 'cough', 'fever'. Used as fieldId for deduplication.
  final String code;

  /// Key into [TriageStrings] for localized label. Matches app_strings.dart pattern.
  final String labelKey;

  /// UI grouping cluster.
  final SymptomCluster cluster;

  /// Material icon name for tile display.
  final String? icon;

  /// Programmes that this symptom is relevant to.
  final Set<Programme> programmes;

  /// Whether this symptom is a danger sign requiring immediate attention.
  final bool isDangerSign;

  /// SNOMED-CT code for interoperability (e.g., cough = 49727002).
  final String? snomedCode;
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
      programmes: {Programme.imci, Programme.anc, Programme.pnc},
      isDangerSign: true,
      snomedCode: '91175000',
    ),
    UnifiedSymptomDef(
      code: 'unconscious',
      labelKey: 'symptomUnconscious',
      cluster: SymptomCluster.dangerSigns,
      icon: 'warning',
      programmes: {Programme.imci, Programme.anc, Programme.ncd},
      isDangerSign: true,
      snomedCode: '419045004',
    ),
    UnifiedSymptomDef(
      code: 'lethargy',
      labelKey: 'symptomLethargy',
      cluster: SymptomCluster.dangerSigns,
      icon: 'bedtime',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '214264003',
    ),
    UnifiedSymptomDef(
      code: 'not_eating',
      labelKey: 'symptomNotEating',
      cluster: SymptomCluster.dangerSigns,
      icon: 'no_food',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '79890006',
    ),
    UnifiedSymptomDef(
      code: 'chest_indrawing',
      labelKey: 'symptomChestIndrawing',
      cluster: SymptomCluster.dangerSigns,
      icon: 'warning',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '248595007',
    ),
    UnifiedSymptomDef(
      code: 'stridor',
      labelKey: 'symptomStridor',
      cluster: SymptomCluster.dangerSigns,
      icon: 'warning',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '70407001',
    ),
    UnifiedSymptomDef(
      code: 'vaginal_bleeding',
      labelKey: 'symptomVaginalBleeding',
      cluster: SymptomCluster.dangerSigns,
      icon: 'water_drop',
      programmes: {Programme.anc, Programme.pnc},
      isDangerSign: true,
      snomedCode: '266599000',
    ),
    UnifiedSymptomDef(
      code: 'water_break',
      labelKey: 'symptomWaterBreak',
      cluster: SymptomCluster.dangerSigns,
      icon: 'water',
      programmes: {Programme.anc},
      isDangerSign: true,
      snomedCode: '289259007',
    ),
    UnifiedSymptomDef(
      code: 'reduced_fetal_movement',
      labelKey: 'symptomReducedFetalMovement',
      cluster: SymptomCluster.dangerSigns,
      icon: 'child_care',
      programmes: {Programme.anc},
      isDangerSign: true,
      snomedCode: '276367008',
    ),
    UnifiedSymptomDef(
      code: 'chest_pain',
      labelKey: 'symptomChestPain',
      cluster: SymptomCluster.dangerSigns,
      icon: 'favorite',
      programmes: {Programme.ncd, Programme.tb},
      isDangerSign: true,
      snomedCode: '29857009',
    ),
    UnifiedSymptomDef(
      code: 'hemoptysis',
      labelKey: 'symptomHemoptysis',
      cluster: SymptomCluster.dangerSigns,
      icon: 'water_drop',
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
      programmes: {Programme.imci, Programme.anc, Programme.tb},
      snomedCode: '386661006',
    ),
    UnifiedSymptomDef(
      code: 'cough',
      labelKey: 'symptomCough',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      programmes: {Programme.imci, Programme.tb},
      snomedCode: '49727002',
    ),
    UnifiedSymptomDef(
      code: 'cough_over_2_weeks',
      labelKey: 'symptomCoughOver2Weeks',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      programmes: {Programme.tb},
      snomedCode: '49727002',
    ),
    UnifiedSymptomDef(
      code: 'difficulty_breathing',
      labelKey: 'symptomDifficultyBreathing',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      programmes: {Programme.imci, Programme.ncd},
      isDangerSign: true,
      snomedCode: '267036007',
    ),
    UnifiedSymptomDef(
      code: 'fast_breathing',
      labelKey: 'symptomFastBreathing',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      programmes: {Programme.imci},
      snomedCode: '271823003',
    ),
    UnifiedSymptomDef(
      code: 'shortness_breath',
      labelKey: 'symptomShortnessBreath',
      cluster: SymptomCluster.feverRespiratory,
      icon: 'air',
      programmes: {Programme.ncd, Programme.tb},
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
      programmes: {Programme.imci},
      snomedCode: '62315008',
    ),
    UnifiedSymptomDef(
      code: 'bloody_diarrhea',
      labelKey: 'symptomBloodyDiarrhea',
      cluster: SymptomCluster.giNutrition,
      icon: 'water_drop',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '95545007',
    ),
    UnifiedSymptomDef(
      code: 'vomiting',
      labelKey: 'symptomVomiting',
      cluster: SymptomCluster.giNutrition,
      icon: 'sick',
      programmes: {Programme.imci, Programme.anc},
      snomedCode: '422400008',
    ),
    UnifiedSymptomDef(
      code: 'loss_appetite',
      labelKey: 'symptomLossAppetite',
      cluster: SymptomCluster.giNutrition,
      icon: 'no_food',
      programmes: {Programme.imci, Programme.tb},
      snomedCode: '79890006',
    ),
    UnifiedSymptomDef(
      code: 'muac_red',
      labelKey: 'symptomMuacRed',
      cluster: SymptomCluster.giNutrition,
      icon: 'straighten',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '248325000',
    ),
    UnifiedSymptomDef(
      code: 'visible_wasting',
      labelKey: 'symptomVisibleWasting',
      cluster: SymptomCluster.giNutrition,
      icon: 'trending_down',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '271807003',
    ),
    UnifiedSymptomDef(
      code: 'edema_both_feet',
      labelKey: 'symptomEdemaBothFeet',
      cluster: SymptomCluster.giNutrition,
      icon: 'bubble_chart',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '267038008',
    ),
    UnifiedSymptomDef(
      code: 'weight_loss',
      labelKey: 'symptomWeightLoss',
      cluster: SymptomCluster.giNutrition,
      icon: 'trending_down',
      programmes: {Programme.tb, Programme.ncd},
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
      programmes: {Programme.anc},
      snomedCode: '77386006',
    ),
    UnifiedSymptomDef(
      code: 'headache_severe',
      labelKey: 'symptomHeadacheSevere',
      cluster: SymptomCluster.maternal,
      icon: 'psychology',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '25064002',
    ),
    UnifiedSymptomDef(
      code: 'blurred_vision',
      labelKey: 'symptomBlurredVision',
      cluster: SymptomCluster.maternal,
      icon: 'visibility_off',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '246636008',
    ),
    UnifiedSymptomDef(
      code: 'abdominal_pain',
      labelKey: 'symptomAbdominalPain',
      cluster: SymptomCluster.maternal,
      icon: 'healing',
      programmes: {Programme.anc},
      snomedCode: '21522001',
    ),
    UnifiedSymptomDef(
      code: 'swelling_face_hands',
      labelKey: 'symptomSwellingFaceHands',
      cluster: SymptomCluster.maternal,
      icon: 'bubble_chart',
      programmes: {Programme.anc},
      isDangerSign: true,
      snomedCode: '267038008',
    ),
    UnifiedSymptomDef(
      code: 'high_bp_known',
      labelKey: 'symptomHighBpKnown',
      cluster: SymptomCluster.maternal,
      icon: 'favorite',
      programmes: {Programme.anc, Programme.ncd},
      snomedCode: '38341003',
    ),
    UnifiedSymptomDef(
      code: 'labor_signs',
      labelKey: 'symptomLaborSigns',
      cluster: SymptomCluster.maternal,
      icon: 'child_care',
      programmes: {Programme.anc},
      snomedCode: '289530006',
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
      programmes: {Programme.ncd},
      snomedCode: '404640003',
    ),
    UnifiedSymptomDef(
      code: 'numbness',
      labelKey: 'symptomNumbness',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'touch_app',
      programmes: {Programme.ncd},
      snomedCode: '44077006',
    ),
    UnifiedSymptomDef(
      code: 'polyuria',
      labelKey: 'symptomPolyuria',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'wc',
      programmes: {Programme.ncd},
      snomedCode: '28442001',
    ),
    UnifiedSymptomDef(
      code: 'polydipsia',
      labelKey: 'symptomPolydipsia',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'local_drink',
      programmes: {Programme.ncd},
      snomedCode: '17173007',
    ),
    UnifiedSymptomDef(
      code: 'foot_pain',
      labelKey: 'symptomFootPain',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'directions_walk',
      programmes: {Programme.ncd},
      snomedCode: '47933007',
    ),
    UnifiedSymptomDef(
      code: 'foot_wound',
      labelKey: 'symptomFootWound',
      cluster: SymptomCluster.ncdMetabolic,
      icon: 'healing',
      programmes: {Programme.ncd},
      isDangerSign: true,
      snomedCode: '13954005',
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
      programmes: {Programme.tb},
      snomedCode: '42984000',
    ),
    UnifiedSymptomDef(
      code: 'fatigue',
      labelKey: 'symptomFatigue',
      cluster: SymptomCluster.tbIndicators,
      icon: 'battery_alert',
      programmes: {Programme.tb, Programme.ncd},
      snomedCode: '84229001',
    ),
    UnifiedSymptomDef(
      code: 'tb_contact',
      labelKey: 'symptomTbContact',
      cluster: SymptomCluster.tbIndicators,
      icon: 'people',
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
      programmes: {Programme.ncd, Programme.anc},
      snomedCode: '394924000',
    ),
    UnifiedSymptomDef(
      code: 'anxiety',
      labelKey: 'symptomAnxiety',
      cluster: SymptomCluster.mentalHealth,
      icon: 'psychology',
      programmes: {Programme.ncd, Programme.anc},
      snomedCode: '48694002',
    ),
    UnifiedSymptomDef(
      code: 'sleep_difficulty',
      labelKey: 'symptomSleepDifficulty',
      cluster: SymptomCluster.mentalHealth,
      icon: 'bedtime_off',
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
      programmes: {Programme.imci},
      snomedCode: '300226004',
    ),
    UnifiedSymptomDef(
      code: 'skin_rash',
      labelKey: 'symptomSkinRash',
      cluster: SymptomCluster.childHealth,
      icon: 'healing',
      programmes: {Programme.imci},
      snomedCode: '271807003',
    ),
    UnifiedSymptomDef(
      code: 'eye_discharge',
      labelKey: 'symptomEyeDischarge',
      cluster: SymptomCluster.childHealth,
      icon: 'visibility',
      programmes: {Programme.imci},
      snomedCode: '246679005',
    ),
    UnifiedSymptomDef(
      code: 'umbilicus_red',
      labelKey: 'symptomUmbilicusRed',
      cluster: SymptomCluster.childHealth,
      icon: 'warning',
      programmes: {Programme.imci},
      isDangerSign: true,
      snomedCode: '239095007',
    ),
    UnifiedSymptomDef(
      code: 'jaundice',
      labelKey: 'symptomJaundice',
      cluster: SymptomCluster.childHealth,
      icon: 'warning',
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
