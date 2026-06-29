/// ANC Assessment models matching spice-service AncDTO.
///
/// Antenatal care assessment for pregnant women.
library;

/// Vaccination and supplements section matching VaccinationAndSupplementsDTO.
class VaccinationAndSupplements {
  const VaccinationAndSupplements({
    this.ttTdCompleted,
    this.folicAcidTotalConsumed,
    this.folicAcidProvided,
    this.ifaTotalConsumed,
    this.ifaProvided,
    this.calciumTotalConsumed,
    this.calciumProvided,
  });

  /// TT/Td vaccination status.
  final String? ttTdCompleted;

  /// Total folic acid tablets consumed.
  final int? folicAcidTotalConsumed;

  /// Folic acid tablets provided this visit.
  final int? folicAcidProvided;

  /// Total IFA (Iron-Folic Acid) tablets consumed.
  final int? ifaTotalConsumed;

  /// IFA tablets provided this visit.
  final int? ifaProvided;

  /// Total calcium tablets consumed.
  final int? calciumTotalConsumed;

  /// Calcium tablets provided this visit.
  final int? calciumProvided;

  VaccinationAndSupplements copyWith({
    String? ttTdCompleted,
    int? folicAcidTotalConsumed,
    int? folicAcidProvided,
    int? ifaTotalConsumed,
    int? ifaProvided,
    int? calciumTotalConsumed,
    int? calciumProvided,
  }) =>
      VaccinationAndSupplements(
        ttTdCompleted: ttTdCompleted ?? this.ttTdCompleted,
        folicAcidTotalConsumed:
            folicAcidTotalConsumed ?? this.folicAcidTotalConsumed,
        folicAcidProvided: folicAcidProvided ?? this.folicAcidProvided,
        ifaTotalConsumed: ifaTotalConsumed ?? this.ifaTotalConsumed,
        ifaProvided: ifaProvided ?? this.ifaProvided,
        calciumTotalConsumed: calciumTotalConsumed ?? this.calciumTotalConsumed,
        calciumProvided: calciumProvided ?? this.calciumProvided,
      );

  Map<String, dynamic> toJson() => {
        if (ttTdCompleted != null) 'ttTdCompleted': ttTdCompleted,
        if (folicAcidTotalConsumed != null)
          'folicAcidTotalConsumed': folicAcidTotalConsumed,
        if (folicAcidProvided != null) 'folicAcidProvided': folicAcidProvided,
        if (ifaTotalConsumed != null) 'ifaTotalConsumed': ifaTotalConsumed,
        if (ifaProvided != null) 'ifaProvided': ifaProvided,
        if (calciumTotalConsumed != null)
          'calciumTotalConsumed': calciumTotalConsumed,
        if (calciumProvided != null) 'calciumProvided': calciumProvided,
      };

  factory VaccinationAndSupplements.fromJson(Map<String, dynamic> json) =>
      VaccinationAndSupplements(
        ttTdCompleted: json['ttTdCompleted'] as String?,
        folicAcidTotalConsumed: json['folicAcidTotalConsumed'] as int?,
        folicAcidProvided: json['folicAcidProvided'] as int?,
        ifaTotalConsumed: json['ifaTotalConsumed'] as int?,
        ifaProvided: json['ifaProvided'] as int?,
        calciumTotalConsumed: json['calciumTotalConsumed'] as int?,
        calciumProvided: json['calciumProvided'] as int?,
      );
}

/// Danger signs by trimester matching DangerSignsRiskIdentificationDTO.
class DangerSignsRiskIdentification {
  const DangerSignsRiskIdentification({
    this.dangerSignsExperienced12 = const [],
    this.dangerSignsExperienced13To27 = const [],
    this.dangerSignsExperienced28To40 = const [],
  });

  /// Danger signs in first trimester (weeks 1-12).
  final List<String> dangerSignsExperienced12;

  /// Danger signs in second trimester (weeks 13-27).
  final List<String> dangerSignsExperienced13To27;

  /// Danger signs in third trimester (weeks 28-40).
  final List<String> dangerSignsExperienced28To40;

  /// Whether any danger signs are present.
  bool get hasDangerSigns =>
      dangerSignsExperienced12.isNotEmpty ||
      dangerSignsExperienced13To27.isNotEmpty ||
      dangerSignsExperienced28To40.isNotEmpty;

  /// All danger signs across trimesters.
  List<String> get allDangerSigns => [
        ...dangerSignsExperienced12,
        ...dangerSignsExperienced13To27,
        ...dangerSignsExperienced28To40,
      ];

  DangerSignsRiskIdentification copyWith({
    List<String>? dangerSignsExperienced12,
    List<String>? dangerSignsExperienced13To27,
    List<String>? dangerSignsExperienced28To40,
  }) =>
      DangerSignsRiskIdentification(
        dangerSignsExperienced12:
            dangerSignsExperienced12 ?? this.dangerSignsExperienced12,
        dangerSignsExperienced13To27:
            dangerSignsExperienced13To27 ?? this.dangerSignsExperienced13To27,
        dangerSignsExperienced28To40:
            dangerSignsExperienced28To40 ?? this.dangerSignsExperienced28To40,
      );

  Map<String, dynamic> toJson() => {
        if (dangerSignsExperienced12.isNotEmpty)
          'dangerSignsExperienced12': dangerSignsExperienced12,
        if (dangerSignsExperienced13To27.isNotEmpty)
          'dangerSignsExperienced13To27': dangerSignsExperienced13To27,
        if (dangerSignsExperienced28To40.isNotEmpty)
          'dangerSignsExperienced28To40': dangerSignsExperienced28To40,
      };

  factory DangerSignsRiskIdentification.fromJson(Map<String, dynamic> json) =>
      DangerSignsRiskIdentification(
        dangerSignsExperienced12:
            (json['dangerSignsExperienced12'] as List<dynamic>?)
                    ?.cast<String>() ??
                [],
        dangerSignsExperienced13To27:
            (json['dangerSignsExperienced13To27'] as List<dynamic>?)
                    ?.cast<String>() ??
                [],
        dangerSignsExperienced28To40:
            (json['dangerSignsExperienced28To40'] as List<dynamic>?)
                    ?.cast<String>() ??
                [],
      );
}

/// Medical history and physical examination.
class MedicalHistoryPhysicalExamination {
  const MedicalHistoryPhysicalExamination({
    this.bloodPressureSystolic,
    this.bloodPressureDiastolic,
    this.weight,
    this.height,
    this.bmi,
    this.bmiCategory,
    this.fundalHeight,
    this.fetalHeartRate,
    this.fetalMovement,
    this.presentation,
    this.oedema,
    this.pallor,
    this.urineProtein,
  });

  final int? bloodPressureSystolic;
  final int? bloodPressureDiastolic;
  final double? weight;
  final double? height;
  final double? bmi;
  final String? bmiCategory;
  final double? fundalHeight;
  final int? fetalHeartRate;
  final String? fetalMovement;
  final String? presentation;
  final String? oedema;
  final String? pallor;

  /// Urine protein result (Absent / Trace / Present).
  final String? urineProtein;

  MedicalHistoryPhysicalExamination copyWith({
    int? bloodPressureSystolic,
    int? bloodPressureDiastolic,
    double? weight,
    double? height,
    double? bmi,
    String? bmiCategory,
    double? fundalHeight,
    int? fetalHeartRate,
    String? fetalMovement,
    String? presentation,
    String? oedema,
    String? pallor,
    String? urineProtein,
  }) =>
      MedicalHistoryPhysicalExamination(
        bloodPressureSystolic:
            bloodPressureSystolic ?? this.bloodPressureSystolic,
        bloodPressureDiastolic:
            bloodPressureDiastolic ?? this.bloodPressureDiastolic,
        weight: weight ?? this.weight,
        height: height ?? this.height,
        bmi: bmi ?? this.bmi,
        bmiCategory: bmiCategory ?? this.bmiCategory,
        fundalHeight: fundalHeight ?? this.fundalHeight,
        fetalHeartRate: fetalHeartRate ?? this.fetalHeartRate,
        fetalMovement: fetalMovement ?? this.fetalMovement,
        presentation: presentation ?? this.presentation,
        oedema: oedema ?? this.oedema,
        pallor: pallor ?? this.pallor,
        urineProtein: urineProtein ?? this.urineProtein,
      );

  Map<String, dynamic> toJson() => {
        if (bloodPressureSystolic != null)
          'bloodPressureSystolic': bloodPressureSystolic,
        if (bloodPressureDiastolic != null)
          'bloodPressureDiastolic': bloodPressureDiastolic,
        if (weight != null) 'weight': weight,
        if (height != null) 'height': height,
        if (bmi != null) 'bmi': bmi,
        if (bmiCategory != null) 'bmiCategory': bmiCategory,
        if (fundalHeight != null) 'fundalHeight': fundalHeight,
        if (fetalHeartRate != null) 'fetalHeartRate': fetalHeartRate,
        if (fetalMovement != null) 'fetalMovement': fetalMovement,
        if (presentation != null) 'presentation': presentation,
        if (oedema != null) 'oedema': oedema,
        if (pallor != null) 'pallor': pallor,
        if (urineProtein != null) 'urineProtein': urineProtein,
      };

  factory MedicalHistoryPhysicalExamination.fromJson(
          Map<String, dynamic> json) =>
      MedicalHistoryPhysicalExamination(
        bloodPressureSystolic: json['bloodPressureSystolic'] as int?,
        bloodPressureDiastolic: json['bloodPressureDiastolic'] as int?,
        weight: (json['weight'] as num?)?.toDouble(),
        height: (json['height'] as num?)?.toDouble(),
        bmi: (json['bmi'] as num?)?.toDouble(),
        bmiCategory: json['bmiCategory'] as String?,
        fundalHeight: (json['fundalHeight'] as num?)?.toDouble(),
        fetalHeartRate: json['fetalHeartRate'] as int?,
        fetalMovement: json['fetalMovement'] as String?,
        presentation: json['presentation'] as String?,
        oedema: json['oedema'] as String?,
        pallor: json['pallor'] as String?,
        urineProtein: json['urineProtein'] as String?,
      );
}

/// Point of care investigations matching PointOfCareInvestigationsDTO.
class PointOfCareInvestigations {
  const PointOfCareInvestigations({
    this.urinaryAlbumin,
    this.urinaryBilirubin,
    this.urinarySugar,
    this.bloodSugar,
    this.bloodSugarFasting,
    this.bloodSugarRandom,
    this.hemoglobin,
    this.bloodSugarFastingUnit = 'mg/dL',
    this.bloodSugarRandomUnit = 'mg/dL',
    this.hemoglobinUnit = 'g/dL',
  });

  final String? urinaryAlbumin;
  final String? urinaryBilirubin;
  final String? urinarySugar;
  final String? bloodSugar;
  final double? bloodSugarFasting;
  final double? bloodSugarRandom;
  final double? hemoglobin;
  final String bloodSugarFastingUnit;
  final String bloodSugarRandomUnit;
  final String hemoglobinUnit;

  /// Whether hemoglobin indicates anemia (<11 g/dL in pregnancy).
  bool get hasAnemia => hemoglobin != null && hemoglobin! < 11.0;

  /// Anemia severity classification.
  String? get anemiaStatus {
    if (hemoglobin == null) return null;
    final hb = hemoglobin!;
    if (hb >= 11) return 'Normal';
    if (hb >= 10) return 'Mild anemia';
    if (hb >= 7) return 'Moderate anemia';
    return 'Severe anemia';
  }

  PointOfCareInvestigations copyWith({
    String? urinaryAlbumin,
    String? urinaryBilirubin,
    String? urinarySugar,
    String? bloodSugar,
    double? bloodSugarFasting,
    double? bloodSugarRandom,
    double? hemoglobin,
    String? bloodSugarFastingUnit,
    String? bloodSugarRandomUnit,
    String? hemoglobinUnit,
  }) =>
      PointOfCareInvestigations(
        urinaryAlbumin: urinaryAlbumin ?? this.urinaryAlbumin,
        urinaryBilirubin: urinaryBilirubin ?? this.urinaryBilirubin,
        urinarySugar: urinarySugar ?? this.urinarySugar,
        bloodSugar: bloodSugar ?? this.bloodSugar,
        bloodSugarFasting: bloodSugarFasting ?? this.bloodSugarFasting,
        bloodSugarRandom: bloodSugarRandom ?? this.bloodSugarRandom,
        hemoglobin: hemoglobin ?? this.hemoglobin,
        bloodSugarFastingUnit:
            bloodSugarFastingUnit ?? this.bloodSugarFastingUnit,
        bloodSugarRandomUnit: bloodSugarRandomUnit ?? this.bloodSugarRandomUnit,
        hemoglobinUnit: hemoglobinUnit ?? this.hemoglobinUnit,
      );

  Map<String, dynamic> toJson() => {
        if (urinaryAlbumin != null) 'urinaryAlbumin': urinaryAlbumin,
        if (urinaryBilirubin != null) 'urinaryBilirubin': urinaryBilirubin,
        if (urinarySugar != null) 'urinarySugar': urinarySugar,
        if (bloodSugar != null) 'bloodSugar': bloodSugar,
        if (bloodSugarFasting != null) 'bloodSugarFasting': bloodSugarFasting,
        if (bloodSugarRandom != null) 'bloodSugarRandom': bloodSugarRandom,
        if (hemoglobin != null) 'hemoglobin': hemoglobin,
        'bloodSugarFastingUnit': bloodSugarFastingUnit,
        'bloodSugarRandomUnit': bloodSugarRandomUnit,
        'hemoglobinUnit': hemoglobinUnit,
      };
}

/// ANC services and birth preparedness matching AncServicesBirthPreparednessDTO.
class AncServicesBirthPreparedness {
  const AncServicesBirthPreparedness({
    this.facilityIdentifiedForDelivery,
    this.ancVisitsOtherProviders,
    this.ancFromMedicalDoctor,
    this.ultrasound,
  });

  /// Delivery facility identified.
  final String? facilityIdentifiedForDelivery;

  /// ANC visits from other providers.
  final String? ancVisitsOtherProviders;

  /// ANC from medical doctor.
  final String? ancFromMedicalDoctor;

  /// Ultrasound status.
  final String? ultrasound;

  AncServicesBirthPreparedness copyWith({
    String? facilityIdentifiedForDelivery,
    String? ancVisitsOtherProviders,
    String? ancFromMedicalDoctor,
    String? ultrasound,
  }) =>
      AncServicesBirthPreparedness(
        facilityIdentifiedForDelivery:
            facilityIdentifiedForDelivery ?? this.facilityIdentifiedForDelivery,
        ancVisitsOtherProviders:
            ancVisitsOtherProviders ?? this.ancVisitsOtherProviders,
        ancFromMedicalDoctor: ancFromMedicalDoctor ?? this.ancFromMedicalDoctor,
        ultrasound: ultrasound ?? this.ultrasound,
      );

  Map<String, dynamic> toJson() => {
        if (facilityIdentifiedForDelivery != null)
          'facilityIdentifiedForDelivery': facilityIdentifiedForDelivery,
        if (ancVisitsOtherProviders != null)
          'ancVisitsOtherProviders': ancVisitsOtherProviders,
        if (ancFromMedicalDoctor != null)
          'ancFromMedicalDoctor': ancFromMedicalDoctor,
        if (ultrasound != null) 'ultrasound': ultrasound,
      };
}

/// Complete ANC assessment matching spice-service AncDTO.
class AncAssessment {
  const AncAssessment({
    this.vaccinationAndSupplements,
    this.dangerSignsRiskIdentification,
    this.medicalHistoryPhysicalExamination,
    this.pointOfCareInvestigations,
    this.ancServicesBirthPreparedness,
    this.bmiCategory,
    this.visitNo,
    this.gestationalWeeks,
  });

  final VaccinationAndSupplements? vaccinationAndSupplements;
  final DangerSignsRiskIdentification? dangerSignsRiskIdentification;
  final MedicalHistoryPhysicalExamination? medicalHistoryPhysicalExamination;
  final PointOfCareInvestigations? pointOfCareInvestigations;
  final AncServicesBirthPreparedness? ancServicesBirthPreparedness;
  final String? bmiCategory;
  final int? visitNo;
  final int? gestationalWeeks;

  /// Current trimester based on gestational weeks.
  int get trimester {
    final weeks = gestationalWeeks ?? 0;
    if (weeks <= 12) return 1;
    if (weeks <= 27) return 2;
    return 3;
  }

  /// Whether referral is recommended based on danger signs or severe anemia.
  bool get referralRecommended =>
      (dangerSignsRiskIdentification?.hasDangerSigns ?? false) ||
      (pointOfCareInvestigations?.hemoglobin != null &&
          pointOfCareInvestigations!.hemoglobin! < 7);

  AncAssessment copyWith({
    VaccinationAndSupplements? vaccinationAndSupplements,
    DangerSignsRiskIdentification? dangerSignsRiskIdentification,
    MedicalHistoryPhysicalExamination? medicalHistoryPhysicalExamination,
    PointOfCareInvestigations? pointOfCareInvestigations,
    AncServicesBirthPreparedness? ancServicesBirthPreparedness,
    String? bmiCategory,
    int? visitNo,
    int? gestationalWeeks,
  }) =>
      AncAssessment(
        vaccinationAndSupplements:
            vaccinationAndSupplements ?? this.vaccinationAndSupplements,
        dangerSignsRiskIdentification:
            dangerSignsRiskIdentification ?? this.dangerSignsRiskIdentification,
        medicalHistoryPhysicalExamination: medicalHistoryPhysicalExamination ??
            this.medicalHistoryPhysicalExamination,
        pointOfCareInvestigations:
            pointOfCareInvestigations ?? this.pointOfCareInvestigations,
        ancServicesBirthPreparedness:
            ancServicesBirthPreparedness ?? this.ancServicesBirthPreparedness,
        bmiCategory: bmiCategory ?? this.bmiCategory,
        visitNo: visitNo ?? this.visitNo,
        gestationalWeeks: gestationalWeeks ?? this.gestationalWeeks,
      );

  Map<String, dynamic> toJson() => {
        if (vaccinationAndSupplements != null)
          'vaccinationAndSupplements': vaccinationAndSupplements!.toJson(),
        if (dangerSignsRiskIdentification != null)
          'dangerSignsRiskIdentification':
              dangerSignsRiskIdentification!.toJson(),
        if (medicalHistoryPhysicalExamination != null)
          'medicalHistoryPhysicalExamination':
              medicalHistoryPhysicalExamination!.toJson(),
        if (pointOfCareInvestigations != null)
          'pointOfCareInvestigations': pointOfCareInvestigations!.toJson(),
        if (ancServicesBirthPreparedness != null)
          'ancServicesBirthPreparedness': ancServicesBirthPreparedness!.toJson(),
        if (bmiCategory != null) 'bmiCategory': bmiCategory,
        if (visitNo != null) 'visitNo': visitNo,
      };
}

/// Danger signs options for ANC by trimester.
class AncDangerSignsOptions {
  /// First trimester danger signs (weeks 1-12).
  static const List<String> firstTrimester = [
    'Vaginal bleeding',
    'Severe abdominal pain',
    'Persistent vomiting',
    'Fever',
    'Headache',
    'Convulsions',
  ];

  /// Second trimester danger signs (weeks 13-27).
  static const List<String> secondTrimester = [
    'Vaginal bleeding',
    'Severe abdominal pain',
    'Leaking fluid',
    'Fever',
    'Severe headache',
    'Blurred vision',
    'Convulsions',
    'Swelling of face/hands',
  ];

  /// Third trimester danger signs (weeks 28-40).
  static const List<String> thirdTrimester = [
    'Vaginal bleeding',
    'Severe abdominal pain',
    'Leaking fluid',
    'Reduced fetal movement',
    'Fever',
    'Severe headache',
    'Blurred vision',
    'Convulsions',
    'Swelling of face/hands',
    'Difficulty breathing',
  ];
}
