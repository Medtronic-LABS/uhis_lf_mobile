/// NCD Assessment models matching spice-service BpLogDTO + GlucoseLogDTO.
///
/// Used for diabetes and hypertension patients.
library;

/// Details for a single BP reading.
class BpLogDetails {
  const BpLogDetails({
    required this.systolic,
    required this.diastolic,
    this.pulse,
  });

  final int systolic;
  final int diastolic;
  final int? pulse;

  BpLogDetails copyWith({int? systolic, int? diastolic, int? pulse}) =>
      BpLogDetails(
        systolic: systolic ?? this.systolic,
        diastolic: diastolic ?? this.diastolic,
        pulse: pulse ?? this.pulse,
      );

  Map<String, dynamic> toJson() => {
        'systolic': systolic,
        'diastolic': diastolic,
        if (pulse != null) 'pulse': pulse,
      };

  factory BpLogDetails.fromJson(Map<String, dynamic> json) => BpLogDetails(
        systolic: json['systolic'] as int,
        diastolic: json['diastolic'] as int,
        pulse: json['pulse'] as int?,
      );
}

/// Blood pressure log matching spice-service BpLogDTO.
class BpLog {
  const BpLog({
    this.bpLogDetails = const [],
    this.avgSystolic,
    this.avgDiastolic,
    this.avgPulse,
    this.temperature,
    this.cvdRiskLevel,
    this.cvdRiskScore,
    this.cvdRiskScoreDisplay,
    this.isRegularSmoker,
    this.isBeforeHtnDiagnosis,
    this.weight,
    this.height,
    this.bmi,
    this.bmiCategory,
    this.symptoms = const [],
    this.bpTakenOn,
  });

  final List<BpLogDetails> bpLogDetails;
  final double? avgSystolic;
  final double? avgDiastolic;
  final int? avgPulse;
  final double? temperature;
  final String? cvdRiskLevel;
  final double? cvdRiskScore;
  final String? cvdRiskScoreDisplay;
  final bool? isRegularSmoker;
  final bool? isBeforeHtnDiagnosis;
  final double? weight;
  final double? height;
  final double? bmi;
  final String? bmiCategory;
  final List<String> symptoms;
  final DateTime? bpTakenOn;

  /// Computed average systolic from readings.
  double get computedAvgSystolic {
    if (bpLogDetails.isEmpty) return 0;
    return bpLogDetails.map((e) => e.systolic).reduce((a, b) => a + b) /
        bpLogDetails.length;
  }

  /// Computed average diastolic from readings.
  double get computedAvgDiastolic {
    if (bpLogDetails.isEmpty) return 0;
    return bpLogDetails.map((e) => e.diastolic).reduce((a, b) => a + b) /
        bpLogDetails.length;
  }

  /// Computed average pulse from readings.
  int? get computedAvgPulse {
    final withPulse = bpLogDetails.where((e) => e.pulse != null).toList();
    if (withPulse.isEmpty) return null;
    return (withPulse.map((e) => e.pulse!).reduce((a, b) => a + b) /
            withPulse.length)
        .round();
  }

  BpLog copyWith({
    List<BpLogDetails>? bpLogDetails,
    double? avgSystolic,
    double? avgDiastolic,
    int? avgPulse,
    double? temperature,
    String? cvdRiskLevel,
    double? cvdRiskScore,
    String? cvdRiskScoreDisplay,
    bool? isRegularSmoker,
    bool? isBeforeHtnDiagnosis,
    double? weight,
    double? height,
    double? bmi,
    String? bmiCategory,
    List<String>? symptoms,
    DateTime? bpTakenOn,
  }) =>
      BpLog(
        bpLogDetails: bpLogDetails ?? this.bpLogDetails,
        avgSystolic: avgSystolic ?? this.avgSystolic,
        avgDiastolic: avgDiastolic ?? this.avgDiastolic,
        avgPulse: avgPulse ?? this.avgPulse,
        temperature: temperature ?? this.temperature,
        cvdRiskLevel: cvdRiskLevel ?? this.cvdRiskLevel,
        cvdRiskScore: cvdRiskScore ?? this.cvdRiskScore,
        cvdRiskScoreDisplay: cvdRiskScoreDisplay ?? this.cvdRiskScoreDisplay,
        isRegularSmoker: isRegularSmoker ?? this.isRegularSmoker,
        isBeforeHtnDiagnosis: isBeforeHtnDiagnosis ?? this.isBeforeHtnDiagnosis,
        weight: weight ?? this.weight,
        height: height ?? this.height,
        bmi: bmi ?? this.bmi,
        bmiCategory: bmiCategory ?? this.bmiCategory,
        symptoms: symptoms ?? this.symptoms,
        bpTakenOn: bpTakenOn ?? this.bpTakenOn,
      );

  /// Whether this log contains at least one real BP reading.
  bool get hasReadings => bpLogDetails.isNotEmpty;

  Map<String, dynamic> toJson() {
    final hasBp = hasReadings;
    return {
      'bpLogDetails': bpLogDetails.map((e) => e.toJson()).toList(),
      if (hasBp) 'avgSystolic': (avgSystolic ?? computedAvgSystolic).toInt(),
      if (hasBp) 'avgDiastolic': (avgDiastolic ?? computedAvgDiastolic).toInt(),
      if (hasBp && (avgPulse != null || computedAvgPulse != null))
        'avgPulse': avgPulse ?? computedAvgPulse,
      if (temperature != null) 'temperature': temperature,
      if (cvdRiskLevel != null) 'cvdRiskLevel': cvdRiskLevel,
      if (cvdRiskScore != null) 'cvdRiskScore': cvdRiskScore,
      if (cvdRiskScoreDisplay != null)
        'cvdRiskScoreDisplay': cvdRiskScoreDisplay,
      // weight/height/bmi only meaningful alongside a real BP reading
      if (hasBp && isRegularSmoker != null) 'isRegularSmoker': isRegularSmoker,
      if (hasBp && isBeforeHtnDiagnosis != null)
        'isBeforeHtnDiagnosis': isBeforeHtnDiagnosis,
      if (hasBp && weight != null) 'weight': weight,
      if (hasBp && height != null) 'height': height,
      if (hasBp && bmi != null) 'bmi': bmi,
      if (hasBp && bmiCategory != null) 'bmiCategory': bmiCategory,
      if (symptoms.isNotEmpty) 'symptoms': symptoms,
      if (bpTakenOn != null) 'bpTakenOn': bpTakenOn!.toIso8601String(),
    };
  }
}

/// Glucose log matching spice-service GlucoseLogDTO.
class GlucoseLog {
  const GlucoseLog({
    this.glucoseValue,
    this.glucoseUnit = 'mg/dL',
    this.glucoseType,
    this.glucoseDateTime,
    this.lastMealTime,
    this.hba1c,
    this.hba1cUnit = '%',
    this.hba1cDateTime,
    this.isBeforeDiabetesDiagnosis,
    this.symptoms = const [],
    this.bgTakenOn,
  });

  final double? glucoseValue;
  final String glucoseUnit;
  final String? glucoseType; // 'fasting', 'random', 'postprandial'
  final DateTime? glucoseDateTime;
  final DateTime? lastMealTime;
  final double? hba1c;
  final String hba1cUnit;
  final DateTime? hba1cDateTime;
  final bool? isBeforeDiabetesDiagnosis;
  final List<String> symptoms;
  final DateTime? bgTakenOn;

  /// Get glucose status based on fasting/random thresholds.
  String? get glucoseStatus {
    if (glucoseValue == null) return null;
    final val = glucoseValue!;
    if (glucoseType == 'fasting') {
      if (val < 100) return 'Normal';
      if (val < 126) return 'Prediabetes';
      return 'Diabetes';
    } else if (glucoseType == 'random' || glucoseType == 'postprandial') {
      if (val < 140) return 'Normal';
      if (val < 200) return 'Prediabetes';
      return 'Diabetes';
    }
    return null;
  }

  GlucoseLog copyWith({
    double? glucoseValue,
    String? glucoseUnit,
    String? glucoseType,
    DateTime? glucoseDateTime,
    DateTime? lastMealTime,
    double? hba1c,
    String? hba1cUnit,
    DateTime? hba1cDateTime,
    bool? isBeforeDiabetesDiagnosis,
    List<String>? symptoms,
    DateTime? bgTakenOn,
  }) =>
      GlucoseLog(
        glucoseValue: glucoseValue ?? this.glucoseValue,
        glucoseUnit: glucoseUnit ?? this.glucoseUnit,
        glucoseType: glucoseType ?? this.glucoseType,
        glucoseDateTime: glucoseDateTime ?? this.glucoseDateTime,
        lastMealTime: lastMealTime ?? this.lastMealTime,
        hba1c: hba1c ?? this.hba1c,
        hba1cUnit: hba1cUnit ?? this.hba1cUnit,
        hba1cDateTime: hba1cDateTime ?? this.hba1cDateTime,
        isBeforeDiabetesDiagnosis:
            isBeforeDiabetesDiagnosis ?? this.isBeforeDiabetesDiagnosis,
        symptoms: symptoms ?? this.symptoms,
        bgTakenOn: bgTakenOn ?? this.bgTakenOn,
      );

  Map<String, dynamic> toJson() => {
        if (glucoseValue != null) 'glucoseValue': glucoseValue,
        'glucoseUnit': glucoseUnit,
        if (glucoseType != null) 'glucoseType': glucoseType,
        if (glucoseDateTime != null)
          'glucoseDateTime': glucoseDateTime!.toIso8601String(),
        if (lastMealTime != null)
          'lastMealTime': lastMealTime!.toIso8601String(),
        if (hba1c != null) 'hba1c': hba1c,
        'hba1cUnit': hba1cUnit,
        if (hba1cDateTime != null)
          'hba1cDateTime': hba1cDateTime!.toIso8601String(),
        if (isBeforeDiabetesDiagnosis != null)
          'isBeforeDiabetesDiagnosis': isBeforeDiabetesDiagnosis,
        if (symptoms.isNotEmpty) 'symptoms': symptoms,
        if (bgTakenOn != null) 'bgTakenOn': bgTakenOn!.toIso8601String(),
      };
}

/// Hypertension screening questions — spec §5.2.2.
///
/// Four routine Yes/No toggles plus an escalation flag for one-sided weakness
/// (stroke sign). Stroke sign maps to spec §2.8.2 Band 1 — immediate emergency
/// referral regardless of BP reading.
class HtnScreening {
  const HtnScreening({
    this.morningHeadaches,
    this.chestTightnessOrSob,
    this.highSaltIntake,
    this.familyHistoryHtn,
    this.oneSidedWeakness,
  });

  /// "Morning headaches" — classic HTN symptom. Informs AI CDSS.
  final bool? morningHeadaches;

  /// "Chest tightness or shortness of breath" — cardiac involvement indicator.
  /// Combined with high BP this is a §2.8.2 Band 1 trigger ("SOB with high BP").
  final bool? chestTightnessOrSob;

  /// "High salt intake" — modifiable lifestyle risk; triggers counselling.
  final bool? highSaltIntake;

  /// "Family history of high BP" — genetic risk; informs AI CDSS narrative.
  final bool? familyHistoryHtn;

  /// One-sided weakness / signs of stroke — spec §2.8.2 Band 1 short-circuit.
  /// Surfaces as an immediate-emergency-referral driver in the risk engine.
  final bool? oneSidedWeakness;

  bool get hasAnswered =>
      morningHeadaches != null ||
      chestTightnessOrSob != null ||
      highSaltIntake != null ||
      familyHistoryHtn != null ||
      oneSidedWeakness != null;

  HtnScreening copyWith({
    bool? morningHeadaches,
    bool? chestTightnessOrSob,
    bool? highSaltIntake,
    bool? familyHistoryHtn,
    bool? oneSidedWeakness,
  }) =>
      HtnScreening(
        morningHeadaches: morningHeadaches ?? this.morningHeadaches,
        chestTightnessOrSob: chestTightnessOrSob ?? this.chestTightnessOrSob,
        highSaltIntake: highSaltIntake ?? this.highSaltIntake,
        familyHistoryHtn: familyHistoryHtn ?? this.familyHistoryHtn,
        oneSidedWeakness: oneSidedWeakness ?? this.oneSidedWeakness,
      );

  Map<String, dynamic> toJson() => {
        if (morningHeadaches != null) 'morningHeadaches': morningHeadaches,
        if (chestTightnessOrSob != null)
          'chestTightnessOrSob': chestTightnessOrSob,
        if (highSaltIntake != null) 'highSaltIntake': highSaltIntake,
        if (familyHistoryHtn != null) 'familyHistoryHtn': familyHistoryHtn,
        if (oneSidedWeakness != null) 'oneSidedWeakness': oneSidedWeakness,
      };

  factory HtnScreening.fromJson(Map<String, dynamic> json) => HtnScreening(
        morningHeadaches: json['morningHeadaches'] as bool?,
        chestTightnessOrSob: json['chestTightnessOrSob'] as bool?,
        highSaltIntake: json['highSaltIntake'] as bool?,
        familyHistoryHtn: json['familyHistoryHtn'] as bool?,
        oneSidedWeakness: json['oneSidedWeakness'] as bool?,
      );
}

/// Complete NCD assessment containing BP and glucose logs.
class NcdAssessment {
  const NcdAssessment({
    this.bpLog,
    this.glucoseLog,
    this.htnScreening,
    this.cvdRiskLevel,
    this.cvdRiskScore,
    this.riskLevel,
    this.riskMessage,
  });

  final BpLog? bpLog;
  final GlucoseLog? glucoseLog;
  final HtnScreening? htnScreening;
  final String? cvdRiskLevel;
  final double? cvdRiskScore;
  final String? riskLevel;
  final String? riskMessage;

  NcdAssessment copyWith({
    BpLog? bpLog,
    GlucoseLog? glucoseLog,
    HtnScreening? htnScreening,
    String? cvdRiskLevel,
    double? cvdRiskScore,
    String? riskLevel,
    String? riskMessage,
  }) =>
      NcdAssessment(
        bpLog: bpLog ?? this.bpLog,
        glucoseLog: glucoseLog ?? this.glucoseLog,
        htnScreening: htnScreening ?? this.htnScreening,
        cvdRiskLevel: cvdRiskLevel ?? this.cvdRiskLevel,
        cvdRiskScore: cvdRiskScore ?? this.cvdRiskScore,
        riskLevel: riskLevel ?? this.riskLevel,
        riskMessage: riskMessage ?? this.riskMessage,
      );

  Map<String, dynamic> toJson() => {
        if (bpLog != null && bpLog!.hasReadings) 'bpLog': bpLog!.toJson(),
        if (glucoseLog != null) 'glucoseLog': glucoseLog!.toJson(),
        if (htnScreening != null) 'htnScreening': htnScreening!.toJson(),
        if (cvdRiskLevel != null) 'cvdRiskLevel': cvdRiskLevel,
        if (cvdRiskScore != null) 'cvdRiskScore': cvdRiskScore,
        if (riskLevel != null) 'riskLevel': riskLevel,
        if (riskMessage != null) 'riskMessage': riskMessage,
      };
}
