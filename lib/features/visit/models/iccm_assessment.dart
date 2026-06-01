/// ICCM/IMCI Assessment models for children under 5.
///
/// Integrated Community Case Management / Integrated Management of Childhood Illness.
/// Based on WHO IMCI guidelines and Android app's AssessmentICCMFragment.
library;

/// General danger signs for all sick children.
class GeneralDangerSigns {
  const GeneralDangerSigns({
    this.unableToBreastfeed = false,
    this.vomitsEverything = false,
    this.hasConvulsions = false,
    this.lethargicOrUnconscious = false,
    this.chestIndrawing = false,
    this.stridor = false,
  });

  /// Unable to drink or breastfeed.
  final bool unableToBreastfeed;

  /// Vomits everything.
  final bool vomitsEverything;

  /// Has convulsions or convulsed in past few days.
  final bool hasConvulsions;

  /// Lethargic or unconscious.
  final bool lethargicOrUnconscious;

  /// Chest indrawing.
  final bool chestIndrawing;

  /// Stridor when calm.
  final bool stridor;

  /// Whether any danger sign is present.
  bool get hasDangerSigns =>
      unableToBreastfeed ||
      vomitsEverything ||
      hasConvulsions ||
      lethargicOrUnconscious ||
      chestIndrawing ||
      stridor;

  /// Count of positive danger signs.
  int get dangerSignCount {
    int count = 0;
    if (unableToBreastfeed) count++;
    if (vomitsEverything) count++;
    if (hasConvulsions) count++;
    if (lethargicOrUnconscious) count++;
    if (chestIndrawing) count++;
    if (stridor) count++;
    return count;
  }

  GeneralDangerSigns copyWith({
    bool? unableToBreastfeed,
    bool? vomitsEverything,
    bool? hasConvulsions,
    bool? lethargicOrUnconscious,
    bool? chestIndrawing,
    bool? stridor,
  }) =>
      GeneralDangerSigns(
        unableToBreastfeed: unableToBreastfeed ?? this.unableToBreastfeed,
        vomitsEverything: vomitsEverything ?? this.vomitsEverything,
        hasConvulsions: hasConvulsions ?? this.hasConvulsions,
        lethargicOrUnconscious:
            lethargicOrUnconscious ?? this.lethargicOrUnconscious,
        chestIndrawing: chestIndrawing ?? this.chestIndrawing,
        stridor: stridor ?? this.stridor,
      );

  Map<String, dynamic> toJson() => {
        'unableToBreastfeed': unableToBreastfeed,
        'vomitsEverything': vomitsEverything,
        'hasConvulsions': hasConvulsions,
        'lethargicOrUnconscious': lethargicOrUnconscious,
        'chestIndrawing': chestIndrawing,
        'stridor': stridor,
      };

  factory GeneralDangerSigns.fromJson(Map<String, dynamic> json) =>
      GeneralDangerSigns(
        unableToBreastfeed: json['unableToBreastfeed'] as bool? ?? false,
        vomitsEverything: json['vomitsEverything'] as bool? ?? false,
        hasConvulsions: json['hasConvulsions'] as bool? ?? false,
        lethargicOrUnconscious:
            json['lethargicOrUnconscious'] as bool? ?? false,
        chestIndrawing: json['chestIndrawing'] as bool? ?? false,
        stridor: json['stridor'] as bool? ?? false,
      );
}

/// Nutrition assessment using MUAC.
class NutritionAssessment {
  const NutritionAssessment({
    this.muacCm,
    this.hasOedemaOfBothFeet = false,
    this.weightKg,
    this.heightCm,
  });

  /// Mid-upper arm circumference in cm.
  final double? muacCm;

  /// Bilateral pitting oedema.
  final bool hasOedemaOfBothFeet;

  /// Weight in kg.
  final double? weightKg;

  /// Height in cm.
  final double? heightCm;

  /// MUAC color code based on measurement.
  String? get muacColorCode {
    if (muacCm == null) return null;
    if (muacCm! < 11.5) return 'red';
    if (muacCm! < 12.5) return 'yellow';
    return 'green';
  }

  /// Nutrition status classification.
  String? get nutritionStatus {
    if (hasOedemaOfBothFeet) return 'Severe Acute Malnutrition (SAM)';
    if (muacCm == null) return null;
    if (muacCm! < 11.5) return 'Severe Acute Malnutrition (SAM)';
    if (muacCm! < 12.5) return 'Moderate Acute Malnutrition (MAM)';
    return 'Normal';
  }

  /// Whether referral is needed for malnutrition.
  bool get referralNeeded =>
      hasOedemaOfBothFeet || (muacCm != null && muacCm! < 11.5);

  NutritionAssessment copyWith({
    double? muacCm,
    bool? hasOedemaOfBothFeet,
    double? weightKg,
    double? heightCm,
  }) =>
      NutritionAssessment(
        muacCm: muacCm ?? this.muacCm,
        hasOedemaOfBothFeet: hasOedemaOfBothFeet ?? this.hasOedemaOfBothFeet,
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm ?? this.heightCm,
      );

  Map<String, dynamic> toJson() => {
        if (muacCm != null) 'muacCm': muacCm,
        'hasOedemaOfBothFeet': hasOedemaOfBothFeet,
        if (weightKg != null) 'weightKg': weightKg,
        if (heightCm != null) 'heightCm': heightCm,
        if (muacColorCode != null) 'muacCode': muacColorCode,
        if (nutritionStatus != null) 'muacStatus': nutritionStatus,
      };
}

/// Diarrhoea assessment.
class DiarrhoeaAssessment {
  const DiarrhoeaAssessment({
    this.hasDiarrhoea = false,
    this.durationDays,
    this.isBloodyDiarrhoea = false,
    this.hasSevereDehydration = false,
    this.hasModerateDehydration = false,
    this.orsDispensed = false,
    this.zincDispensed = false,
  });

  /// Whether child has diarrhoea.
  final bool hasDiarrhoea;

  /// Duration in days.
  final int? durationDays;

  /// Whether blood in stool.
  final bool isBloodyDiarrhoea;

  /// Signs of severe dehydration.
  final bool hasSevereDehydration;

  /// Signs of moderate (some) dehydration.
  final bool hasModerateDehydration;

  /// ORS provided.
  final bool orsDispensed;

  /// Zinc provided.
  final bool zincDispensed;

  /// Diarrhoea classification.
  String? get classification {
    if (!hasDiarrhoea) return null;
    if (hasSevereDehydration) return 'Severe dehydration';
    if (hasModerateDehydration) return 'Some dehydration';
    if (isBloodyDiarrhoea) return 'Dysentery';
    if ((durationDays ?? 0) >= 14) return 'Persistent diarrhoea';
    return 'Diarrhoea - no dehydration';
  }

  /// Whether referral is needed.
  bool get referralNeeded =>
      hasSevereDehydration || isBloodyDiarrhoea || (durationDays ?? 0) >= 14;

  DiarrhoeaAssessment copyWith({
    bool? hasDiarrhoea,
    int? durationDays,
    bool? isBloodyDiarrhoea,
    bool? hasSevereDehydration,
    bool? hasModerateDehydration,
    bool? orsDispensed,
    bool? zincDispensed,
  }) =>
      DiarrhoeaAssessment(
        hasDiarrhoea: hasDiarrhoea ?? this.hasDiarrhoea,
        durationDays: durationDays ?? this.durationDays,
        isBloodyDiarrhoea: isBloodyDiarrhoea ?? this.isBloodyDiarrhoea,
        hasSevereDehydration: hasSevereDehydration ?? this.hasSevereDehydration,
        hasModerateDehydration:
            hasModerateDehydration ?? this.hasModerateDehydration,
        orsDispensed: orsDispensed ?? this.orsDispensed,
        zincDispensed: zincDispensed ?? this.zincDispensed,
      );

  Map<String, dynamic> toJson() => {
        'hasDiarrhoea': hasDiarrhoea,
        if (durationDays != null) 'noOfDaysDiarrhoea': durationDays,
        'isBloodyDiarrhoea': isBloodyDiarrhoea,
        'severeDehydration': hasSevereDehydration,
        'moderateDehydration': hasModerateDehydration,
        'orsDispensedStatus': orsDispensed,
        'zincDispensedStatus': zincDispensed,
        if (classification != null) 'diarrheaCondition': classification,
      };
}

/// Fever assessment.
class FeverAssessment {
  const FeverAssessment({
    this.hasFever = false,
    this.temperature,
    this.durationDays,
    this.rdtResult,
    this.actDispensed = false,
  });

  /// Whether child has fever.
  final bool hasFever;

  /// Temperature in Celsius.
  final double? temperature;

  /// Duration in days.
  final int? durationDays;

  /// RDT result: 'positive', 'negative', or null if not done.
  final String? rdtResult;

  /// ACT (antimalarial) dispensed.
  final bool actDispensed;

  /// Whether RDT is positive.
  bool get isRdtPositive => rdtResult?.toLowerCase() == 'positive';

  /// Fever classification.
  String? get classification {
    if (!hasFever) return null;
    if (isRdtPositive) return 'Malaria';
    if ((temperature ?? 0) >= 38.5) return 'High fever';
    return 'Fever';
  }

  /// Whether referral is needed.
  bool get referralNeeded =>
      (temperature ?? 0) >= 39 || (durationDays ?? 0) >= 7;

  FeverAssessment copyWith({
    bool? hasFever,
    double? temperature,
    int? durationDays,
    String? rdtResult,
    bool? actDispensed,
  }) =>
      FeverAssessment(
        hasFever: hasFever ?? this.hasFever,
        temperature: temperature ?? this.temperature,
        durationDays: durationDays ?? this.durationDays,
        rdtResult: rdtResult ?? this.rdtResult,
        actDispensed: actDispensed ?? this.actDispensed,
      );

  Map<String, dynamic> toJson() => {
        'hasFever': hasFever,
        if (temperature != null) 'temperature': temperature,
        if (durationDays != null) 'durationDays': durationDays,
        if (rdtResult != null) 'rdtTest': rdtResult,
        'actStatus': actDispensed,
        if (classification != null) 'feverCondition': classification,
      };
}

/// Cough/ARI assessment.
class CoughAssessment {
  const CoughAssessment({
    this.hasCough = false,
    this.durationDays,
    this.breathsPerMinute,
    this.hasFastBreathing = false,
    this.hasChestIndrawing = false,
    this.amoxicillinDispensed = false,
  });

  /// Whether child has cough or difficulty breathing.
  final bool hasCough;

  /// Duration in days.
  final int? durationDays;

  /// Respiratory rate per minute.
  final int? breathsPerMinute;

  /// Fast breathing for age.
  final bool hasFastBreathing;

  /// Chest indrawing.
  final bool hasChestIndrawing;

  /// Amoxicillin dispensed.
  final bool amoxicillinDispensed;

  /// ARI classification.
  String? get classification {
    if (!hasCough) return null;
    if (hasChestIndrawing) return 'Severe pneumonia';
    if (hasFastBreathing) return 'Pneumonia';
    return 'Cough or cold';
  }

  /// Whether referral is needed.
  bool get referralNeeded => hasChestIndrawing;

  CoughAssessment copyWith({
    bool? hasCough,
    int? durationDays,
    int? breathsPerMinute,
    bool? hasFastBreathing,
    bool? hasChestIndrawing,
    bool? amoxicillinDispensed,
  }) =>
      CoughAssessment(
        hasCough: hasCough ?? this.hasCough,
        durationDays: durationDays ?? this.durationDays,
        breathsPerMinute: breathsPerMinute ?? this.breathsPerMinute,
        hasFastBreathing: hasFastBreathing ?? this.hasFastBreathing,
        hasChestIndrawing: hasChestIndrawing ?? this.hasChestIndrawing,
        amoxicillinDispensed: amoxicillinDispensed ?? this.amoxicillinDispensed,
      );

  Map<String, dynamic> toJson() => {
        'hasCough': hasCough,
        if (durationDays != null) 'durationDays': durationDays,
        if (breathsPerMinute != null) 'breathPerMinute': breathsPerMinute,
        'hasFastBreathing': hasFastBreathing,
        'chestInDrawing': hasChestIndrawing,
        'amoxicillinStatus': amoxicillinDispensed,
        if (classification != null) 'coughCondition': classification,
      };
}

/// Complete ICCM assessment for children under 5.
class IccmAssessment {
  const IccmAssessment({
    this.generalDangerSigns,
    this.nutritionAssessment,
    this.diarrhoeaAssessment,
    this.feverAssessment,
    this.coughAssessment,
    this.ageInMonths,
  });

  final GeneralDangerSigns? generalDangerSigns;
  final NutritionAssessment? nutritionAssessment;
  final DiarrhoeaAssessment? diarrhoeaAssessment;
  final FeverAssessment? feverAssessment;
  final CoughAssessment? coughAssessment;
  final int? ageInMonths;

  /// Whether urgent referral is needed based on danger signs or severe conditions.
  bool get urgentReferralNeeded =>
      (generalDangerSigns?.hasDangerSigns ?? false) ||
      (nutritionAssessment?.referralNeeded ?? false) ||
      (diarrhoeaAssessment?.hasSevereDehydration ?? false) ||
      (coughAssessment?.hasChestIndrawing ?? false);

  /// Whether any referral is recommended.
  bool get referralRecommended =>
      urgentReferralNeeded ||
      (diarrhoeaAssessment?.referralNeeded ?? false) ||
      (feverAssessment?.referralNeeded ?? false);

  /// Summary of conditions found.
  List<String> get conditionsSummary {
    final conditions = <String>[];
    if (generalDangerSigns?.hasDangerSigns ?? false) {
      conditions.add('Danger signs present');
    }
    if (nutritionAssessment?.nutritionStatus != null &&
        nutritionAssessment!.nutritionStatus != 'Normal') {
      conditions.add(nutritionAssessment!.nutritionStatus!);
    }
    if (diarrhoeaAssessment?.classification != null) {
      conditions.add(diarrhoeaAssessment!.classification!);
    }
    if (feverAssessment?.classification != null) {
      conditions.add(feverAssessment!.classification!);
    }
    if (coughAssessment?.classification != null) {
      conditions.add(coughAssessment!.classification!);
    }
    return conditions;
  }

  IccmAssessment copyWith({
    GeneralDangerSigns? generalDangerSigns,
    NutritionAssessment? nutritionAssessment,
    DiarrhoeaAssessment? diarrhoeaAssessment,
    FeverAssessment? feverAssessment,
    CoughAssessment? coughAssessment,
    int? ageInMonths,
  }) =>
      IccmAssessment(
        generalDangerSigns: generalDangerSigns ?? this.generalDangerSigns,
        nutritionAssessment: nutritionAssessment ?? this.nutritionAssessment,
        diarrhoeaAssessment: diarrhoeaAssessment ?? this.diarrhoeaAssessment,
        feverAssessment: feverAssessment ?? this.feverAssessment,
        coughAssessment: coughAssessment ?? this.coughAssessment,
        ageInMonths: ageInMonths ?? this.ageInMonths,
      );

  Map<String, dynamic> toJson() => {
        if (generalDangerSigns != null)
          'generalDangerSigns': generalDangerSigns!.toJson(),
        if (nutritionAssessment != null)
          'nutritionAssessment': nutritionAssessment!.toJson(),
        if (diarrhoeaAssessment != null)
          'diarrhoeaAssessment': diarrhoeaAssessment!.toJson(),
        if (feverAssessment != null)
          'feverAssessment': feverAssessment!.toJson(),
        if (coughAssessment != null)
          'coughAssessment': coughAssessment!.toJson(),
        if (ageInMonths != null) 'ageInMonths': ageInMonths,
      };

  factory IccmAssessment.fromJson(Map<String, dynamic> json) => IccmAssessment(
        generalDangerSigns: json['generalDangerSigns'] != null
            ? GeneralDangerSigns.fromJson(
                json['generalDangerSigns'] as Map<String, dynamic>)
            : null,
        ageInMonths: json['ageInMonths'] as int?,
      );
}

/// Fast breathing thresholds by age (WHO IMCI guidelines).
class FastBreathingThresholds {
  /// Get respiratory rate threshold for fast breathing.
  ///
  /// - 2 months to 12 months: ≥50 breaths/min
  /// - 12 months to 5 years: ≥40 breaths/min
  static int getThreshold(int ageInMonths) {
    if (ageInMonths < 12) return 50;
    return 40;
  }

  /// Check if breathing rate is fast for the given age.
  static bool isFastBreathing(int breathsPerMinute, int ageInMonths) {
    return breathsPerMinute >= getThreshold(ageInMonths);
  }
}
