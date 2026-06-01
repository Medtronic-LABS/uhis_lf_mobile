import '../../core/models/programme.dart';

/// Symptom selection during triage.
class SymptomSelection {
  const SymptomSelection({
    required this.code,
    required this.label,
    this.selected = false,
  });

  final String code;
  final String label;
  final bool selected;

  SymptomSelection copyWith({bool? selected}) => SymptomSelection(
        code: code,
        label: label,
        selected: selected ?? this.selected,
      );
  
  Map<String, dynamic> toJson() => {
        'code': code,
        'label': label,
        'selected': selected,
      };
}

/// Duration of symptoms.
enum SymptomDuration {
  oneDay,
  twoToThreeDays,
  fourPlusDays,
}

extension SymptomDurationExt on SymptomDuration {
  String get label {
    switch (this) {
      case SymptomDuration.oneDay:
        return '1 day';
      case SymptomDuration.twoToThreeDays:
        return '2-3 days';
      case SymptomDuration.fourPlusDays:
        return '4+ days';
    }
  }

  int get maxDays {
    switch (this) {
      case SymptomDuration.oneDay:
        return 1;
      case SymptomDuration.twoToThreeDays:
        return 3;
      case SymptomDuration.fourPlusDays:
        return 7; // Assume 7 for 4+ days
    }
  }
}

/// Vital reading captured during vitals step.
class VitalInput {
  const VitalInput({
    required this.code,
    required this.label,
    this.value,
    this.systolic,
    this.diastolic,
    this.boolValue,
    this.unit,
  });

  final String code;
  final String label;
  final double? value;
  final double? systolic; // For BP
  final double? diastolic; // For BP
  final bool? boolValue; // For yes/no toggles
  final String? unit;

  bool get hasValue =>
      value != null ||
      (systolic != null && diastolic != null) ||
      boolValue != null;

  VitalInput copyWith({
    double? value,
    double? systolic,
    double? diastolic,
    bool? boolValue,
  }) =>
      VitalInput(
        code: code,
        label: label,
        value: value ?? this.value,
        systolic: systolic ?? this.systolic,
        diastolic: diastolic ?? this.diastolic,
        boolValue: boolValue ?? this.boolValue,
        unit: unit,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'label': label,
        if (value != null) 'value': value,
        if (systolic != null) 'systolic': systolic,
        if (diastolic != null) 'diastolic': diastolic,
        if (boolValue != null) 'boolValue': boolValue,
        if (unit != null) 'unit': unit,
      };
}

/// Current step in the visit flow.
enum VisitStep {
  landing,
  triage,
  vitals,
  assessment,
  complete,
}

/// Immutable state for the current visit session.
class VisitSession {
  const VisitSession({
    required this.id,
    required this.patientId,
    required this.programme,
    this.patientName,
    this.patientAge,
    this.patientGender,
    this.householdId,
    this.serverVisitId,
    this.step = VisitStep.landing,
    this.symptoms = const [],
    this.duration,
    this.vitals = const [],
    this.assessmentData = const {},
    this.startedAt,
  });

  final String id;
  final String patientId;
  final Programme programme;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? householdId;
  final String? serverVisitId;
  final VisitStep step;
  final List<SymptomSelection> symptoms;
  final SymptomDuration? duration;
  final List<VitalInput> vitals;
  final Map<String, dynamic> assessmentData;
  final DateTime? startedAt;

  /// Create a new session for starting a visit.
  factory VisitSession.create({
    required String id,
    required String patientId,
    required Programme programme,
    String? patientName,
    int? patientAge,
    String? patientGender,
    String? householdId,
  }) =>
      VisitSession(
        id: id,
        patientId: patientId,
        programme: programme,
        patientName: patientName,
        patientAge: patientAge,
        patientGender: patientGender,
        householdId: householdId,
        startedAt: DateTime.now(),
      );

  VisitSession copyWith({
    String? id,
    String? patientId,
    Programme? programme,
    String? patientName,
    int? patientAge,
    String? patientGender,
    String? householdId,
    String? serverVisitId,
    VisitStep? step,
    List<SymptomSelection>? symptoms,
    SymptomDuration? duration,
    List<VitalInput>? vitals,
    Map<String, dynamic>? assessmentData,
    DateTime? startedAt,
  }) =>
      VisitSession(
        id: id ?? this.id,
        patientId: patientId ?? this.patientId,
        programme: programme ?? this.programme,
        patientName: patientName ?? this.patientName,
        patientAge: patientAge ?? this.patientAge,
        patientGender: patientGender ?? this.patientGender,
        householdId: householdId ?? this.householdId,
        serverVisitId: serverVisitId ?? this.serverVisitId,
        step: step ?? this.step,
        symptoms: symptoms ?? this.symptoms,
        duration: duration ?? this.duration,
        vitals: vitals ?? this.vitals,
        assessmentData: assessmentData ?? this.assessmentData,
        startedAt: startedAt ?? this.startedAt,
      );

  /// Get selected symptoms for triage payload.
  List<Map<String, dynamic>> get selectedSymptomsJson =>
      symptoms.where((s) => s.selected).map((s) => s.toJson()).toList();

  /// Get triage payload for persistence.
  Map<String, dynamic> get triagePayload => {
        'symptoms': selectedSymptomsJson,
        if (duration != null) 'durationDays': duration!.maxDays,
        if (duration != null) 'durationLabel': duration!.label,
      };

  /// Get vitals payload for persistence.
  Map<String, dynamic> get vitalsPayload => {
        'vitals': vitals.where((v) => v.hasValue).map((v) => v.toJson()).toList(),
      };
}
