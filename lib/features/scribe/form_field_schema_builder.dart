/// Form field schema builder for AI Scribe form_prefill mode.
///
/// Generates [FormFieldSchema] definitions from assessment forms to send
/// to the AI scribe service. The service uses this schema to extract
/// structured field values from the consultation transcript.
library;

import '../../core/models/programme.dart';

/// Field type for the AI scribe extraction contract.
enum FieldType {
  boolean,
  integer,
  decimal,
  string,
  enumType, // enum in API
  date,
}

/// Schema definition for a single form field.
///
/// Sent to the AI scribe service as part of the form_fill request.
class FormFieldSchema {
  const FormFieldSchema({
    required this.fieldId,
    required this.type,
    required this.label,
    this.unit,
    this.allowedValues,
    this.description,
    this.clinicalContext,
  });

  /// Unique field identifier (matches form field key).
  final String fieldId;

  /// Data type for extraction.
  final FieldType type;

  /// Human-readable label for context.
  final String label;

  /// Unit of measurement (e.g., 'mmHg', 'mg/dL', 'cm').
  final String? unit;

  /// Allowed values for enum types.
  final List<String>? allowedValues;

  /// Additional description for the AI.
  final String? description;

  /// Clinical context to help AI extraction.
  final String? clinicalContext;

  Map<String, dynamic> toJson() => {
        'fieldId': fieldId,
        'type': type == FieldType.enumType ? 'enum' : type.name,
        'label': label,
        if (unit != null) 'unit': unit,
        if (allowedValues != null) 'allowedValues': allowedValues,
        if (description != null) 'description': description,
        if (clinicalContext != null) 'clinicalContext': clinicalContext,
      };
}

/// Builder for creating form schemas for each programme.
///
/// Provides the extraction contract for the AI scribe service to map
/// transcript content to form fields.
abstract final class FormFieldSchemaBuilder {
  FormFieldSchemaBuilder._();

  /// Server `assessmentType` for a Step 2 realtime ASR session, or null when
  /// auto-fill is not yet supported for this visit's programme mix.
  ///
  /// v1 scope is NCD and ANC only. PNC intentionally returns null: the PNC
  /// screen renders mother + child + outcome forms together and a
  /// mother-only extraction would silently drop every newborn utterance —
  /// worse than no fill. ANC outranks NCD in combined visits (maternal
  /// danger signs are the higher-stakes capture).
  static String? assessmentTypeFor(List<String> activeFormTypes) {
    final programmes =
        activeFormTypes.map(Programme.fromString).toSet();
    if (programmes.contains(Programme.pnc)) return null;
    if (programmes.contains(Programme.anc)) return 'anc';
    if (programmes.contains(Programme.ncd)) return 'ncd';
    return null;
  }

  /// Build the combined schema for a list of programme name strings.
  ///
  /// Deduplicates fields that appear in multiple programmes (e.g. `systolic`
  /// shared by ANC and PNC-mother).
  static List<FormFieldSchema> forProgrammeNames(List<String> names) {
    final seen = <String>{};
    final result = <FormFieldSchema>[];
    for (final name in names) {
      final p = Programme.fromString(name);
      for (final field in _forProgramme(p)) {
        if (seen.add(field.fieldId)) result.add(field);
      }
    }
    return result;
  }

  /// Build schema for a single [Programme].
  static List<FormFieldSchema> _forProgramme(Programme programme) {
    switch (programme) {
      case Programme.ncd:
        return _ncd;
      case Programme.anc:
        return _anc;
      case Programme.pnc:
        return _pncMother;
      case Programme.imci:
        return _imci;
      case Programme.tb:
        return _tb;
      default:
        return const [];
    }
  }

  // ── NCD ─────────────────────────────────────────────────────────────────

  static const _ncd = [
    FormFieldSchema(
      fieldId: 'systolic',
      type: FieldType.integer,
      label: 'Systolic Blood Pressure',
      unit: 'mmHg',
      clinicalContext: 'Upper number in blood pressure reading',
    ),
    FormFieldSchema(
      fieldId: 'diastolic',
      type: FieldType.integer,
      label: 'Diastolic Blood Pressure',
      unit: 'mmHg',
      clinicalContext: 'Lower number in blood pressure reading',
    ),
    FormFieldSchema(
      fieldId: 'pulse',
      type: FieldType.integer,
      label: 'Pulse / Heart Rate',
      unit: 'per minute',
    ),
    FormFieldSchema(
      fieldId: 'height',
      type: FieldType.decimal,
      label: 'Height',
      unit: 'cm',
    ),
    FormFieldSchema(
      fieldId: 'weight',
      type: FieldType.decimal,
      label: 'Weight',
      unit: 'kg',
    ),
    FormFieldSchema(
      fieldId: 'glucose',
      type: FieldType.decimal,
      label: 'Blood Glucose',
      unit: 'mmol/L',
      clinicalContext: 'Blood sugar reading',
    ),
    FormFieldSchema(
      fieldId: 'glucoseType',
      type: FieldType.enumType,
      label: 'Glucose Test Type',
      allowedValues: ['rbs', 'fbs', 'ppbs'],
      description: 'rbs=random, fbs=fasting, ppbs=post-prandial',
    ),
    FormFieldSchema(
      fieldId: 'hba1c',
      type: FieldType.decimal,
      label: 'HbA1c',
      unit: '%',
      clinicalContext: '3-month average blood sugar',
    ),
    FormFieldSchema(
      fieldId: 'isRegularSmoker',
      type: FieldType.boolean,
      label: 'Regular Smoker / Tobacco User',
    ),
    FormFieldSchema(
      fieldId: 'hasSymptoms',
      type: FieldType.enumType,
      label: 'Has Symptoms Since Last Visit',
      allowedValues: ['Yes', 'No'],
    ),
    FormFieldSchema(
      fieldId: 'ncdSymptoms',
      type: FieldType.enumType,
      label: 'NCD Symptoms',
      allowedValues: [
        'Headache',
        'Chest Pain',
        'Weakness',
        'Numbness',
        'Excessive Thirst',
        'Breathlessness',
        'Fatigue',
        'Blurred Vision',
        'Swelling of Feet',
      ],
      description: 'Multiple values allowed',
    ),
    FormFieldSchema(
      fieldId: 'compliance',
      type: FieldType.enumType,
      label: 'Medication Compliance',
      allowedValues: ['Yes', 'No', 'Partial'],
    ),
    FormFieldSchema(
      fieldId: 'newWorseningSymptoms',
      type: FieldType.string,
      label: 'New or Worsening Symptoms (free text)',
    ),
  ];

  // ── ANC ─────────────────────────────────────────────────────────────────

  static const _anc = [
    FormFieldSchema(
      fieldId: 'systolic',
      type: FieldType.integer,
      label: 'Systolic Blood Pressure',
      unit: 'mmHg',
    ),
    FormFieldSchema(
      fieldId: 'diastolic',
      type: FieldType.integer,
      label: 'Diastolic Blood Pressure',
      unit: 'mmHg',
    ),
    FormFieldSchema(
      fieldId: 'pulse',
      type: FieldType.integer,
      label: 'Pulse',
      unit: 'per minute',
    ),
    FormFieldSchema(
      fieldId: 'temperature',
      type: FieldType.decimal,
      label: 'Temperature',
      unit: '°F',
    ),
    FormFieldSchema(
      fieldId: 'weight',
      type: FieldType.decimal,
      label: 'Weight',
      unit: 'kg',
    ),
    FormFieldSchema(
      fieldId: 'height',
      type: FieldType.decimal,
      label: 'Height',
      unit: 'cm',
    ),
    FormFieldSchema(
      fieldId: 'hemoglobin',
      type: FieldType.decimal,
      label: 'Haemoglobin (Hb)',
      unit: 'g/dL',
      clinicalContext: 'Blood haemoglobin level',
    ),
    FormFieldSchema(
      fieldId: 'fundalHeight',
      type: FieldType.decimal,
      label: 'Fundal Height',
      unit: 'cm',
    ),
    FormFieldSchema(
      fieldId: 'bloodSugarFasting',
      type: FieldType.decimal,
      label: 'Fasting Blood Sugar',
      unit: 'mmol/L',
    ),
    FormFieldSchema(
      fieldId: 'bloodSugarRandom',
      type: FieldType.decimal,
      label: 'Random Blood Sugar',
      unit: 'mmol/L',
    ),
    FormFieldSchema(
      fieldId: 'fetalMovement',
      type: FieldType.enumType,
      label: 'Fetal Movement',
      allowedValues: ['normal', 'lessThanUsual', 'notFelt'],
    ),
    FormFieldSchema(
      fieldId: 'ancDangerSigns',
      type: FieldType.enumType,
      label: 'ANC Danger Signs',
      allowedValues: [
        'Vaginal bleeding',
        'Leaking fluid from vagina',
        'Regular / painful contractions',
        'Headache / blurred vision / facial swelling',
        'Severe epigastric pain',
        'Fever / burning while urinating',
        'Reduced fetal movements',
        'None of these',
      ],
      description: 'Multiple values allowed',
    ),
    FormFieldSchema(
      fieldId: 'urinarySugar',
      type: FieldType.enumType,
      label: 'Urinary Sugar',
      allowedValues: ['Absent', 'Present'],
    ),
    FormFieldSchema(
      fieldId: 'urinaryAlbumin',
      type: FieldType.enumType,
      label: 'Urinary Albumin / Protein',
      allowedValues: ['Absent', 'Present'],
    ),
  ];

  // ── PNC Mother ───────────────────────────────────────────────────────────

  static const _pncMother = [
    FormFieldSchema(
      fieldId: 'systolic',
      type: FieldType.integer,
      label: 'Systolic Blood Pressure',
      unit: 'mmHg',
    ),
    FormFieldSchema(
      fieldId: 'diastolic',
      type: FieldType.integer,
      label: 'Diastolic Blood Pressure',
      unit: 'mmHg',
    ),
    FormFieldSchema(
      fieldId: 'pulse',
      type: FieldType.integer,
      label: 'Pulse',
      unit: 'per minute',
    ),
    FormFieldSchema(
      fieldId: 'temperature',
      type: FieldType.decimal,
      label: 'Temperature',
      unit: '°F',
    ),
    FormFieldSchema(
      fieldId: 'weight',
      type: FieldType.decimal,
      label: 'Weight',
      unit: 'kg',
    ),
    FormFieldSchema(
      fieldId: 'hemoglobin',
      type: FieldType.decimal,
      label: 'Haemoglobin (Hb)',
      unit: 'g/dL',
    ),
    FormFieldSchema(
      fieldId: 'fastingBloodSugar',
      type: FieldType.decimal,
      label: 'Fasting Blood Sugar',
      unit: 'mmol/L',
    ),
    FormFieldSchema(
      fieldId: 'randomBloodSugar',
      type: FieldType.decimal,
      label: 'Random Blood Sugar',
      unit: 'mmol/L',
    ),
    FormFieldSchema(
      fieldId: 'postpartumDangerSigns',
      type: FieldType.enumType,
      label: 'Postpartum Danger Signs',
      allowedValues: [
        'Excessive bleeding',
        'Fever',
        'Severe headache',
        'Breast pain/redness',
        'Wound infection',
      ],
      description: 'Multiple values allowed',
    ),
    FormFieldSchema(
      fieldId: 'edema',
      type: FieldType.enumType,
      label: 'Oedema / Swelling',
      allowedValues: ['Present', 'Absent'],
    ),
  ];

  // ── IMCI / Child ─────────────────────────────────────────────────────────

  static const _imci = [
    FormFieldSchema(
      fieldId: 'temperature',
      type: FieldType.decimal,
      label: 'Temperature',
      unit: '°F',
    ),
    FormFieldSchema(
      fieldId: 'weight',
      type: FieldType.decimal,
      label: 'Weight',
      unit: 'kg',
    ),
    FormFieldSchema(
      fieldId: 'respiratoryRate',
      type: FieldType.integer,
      label: 'Respiratory Rate',
      unit: 'breaths per minute',
    ),
    FormFieldSchema(
      fieldId: 'childBreastFeeding',
      type: FieldType.enumType,
      label: 'Is Child Breastfeeding',
      allowedValues: ['Yes', 'No'],
    ),
    FormFieldSchema(
      fieldId: 'anyIllness',
      type: FieldType.enumType,
      label: 'Any Illness / Complication',
      allowedValues: ['Yes', 'No'],
    ),
  ];

  // ── TB ───────────────────────────────────────────────────────────────────

  static const _tb = [
    FormFieldSchema(
      fieldId: 'weight',
      type: FieldType.decimal,
      label: 'Weight',
      unit: 'kg',
    ),
    FormFieldSchema(
      fieldId: 'temperature',
      type: FieldType.decimal,
      label: 'Temperature',
      unit: '°F',
    ),
  ];
}
