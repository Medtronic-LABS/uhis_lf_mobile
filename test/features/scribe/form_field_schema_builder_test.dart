/// Unit tests for [FormFieldSchemaBuilder] — regression coverage for the
/// programme-tag ∩ real-fieldRef intersection fix (a field tagged for a
/// programme in field_library.json was previously extractable even when it
/// was never a rendered fieldRef on that programme's Step 2 screen — see
/// docs/step2_scribe_autofill_gap_analysis.md).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/features/scribe/form_field_schema_builder.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';

FormConfig _buildConfig({
  required Map<String, FieldDef> fields,
  required Map<String, List<FormSection>> forms,
}) =>
    FormConfig(fields: fields, forms: forms);

FieldDef _field(
  String id, {
  required List<String> programmeIds,
  List<FieldOption> options = const [],
  String? widgetHint,
  String? unitMeasurement,
}) =>
    FieldDef.fromJson(id, {
      'label': id,
      'widgetHint': widgetHint ?? 'EditText',
      'programmes': [for (final p in programmeIds) {'id': p}],
      'optionsList': [
        for (final o in options) {'id': o.id, 'name': o.name}
      ],
      'unitMeasurement': unitMeasurement,
    });

void main() {
  group('_forProgramme (via forProgrammeNames) — fieldRef intersection', () {
    test('includes a field that is both programme-tagged and a real fieldRef', () {
      final config = _buildConfig(
        fields: {
          'weight': _field('weight', programmeIds: ['ncd'], unitMeasurement: 'kg'),
        },
        forms: {
          'ncd': [
            const FormSection(
              sectionId: 'ncdBiometrics',
              title: 'Biometrics',
              formType: 'ncd',
              fieldRefs: [FieldRef(id: 'weight', isMandatory: false, inputType: 2)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['ncd'], config: config);

      expect(schema.map((f) => f.fieldId), contains('weight'));
    });

    test('excludes a field that is programme-tagged but not a real fieldRef', () {
      final config = _buildConfig(
        fields: {
          'weight': _field('weight', programmeIds: ['ncd'], unitMeasurement: 'kg'),
          'hba1c': _field('hba1c', programmeIds: ['ncd'], unitMeasurement: '%'),
        },
        forms: {
          'ncd': [
            const FormSection(
              sectionId: 'ncdBiometrics',
              title: 'Biometrics',
              formType: 'ncd',
              fieldRefs: [FieldRef(id: 'weight', isMandatory: false, inputType: 2)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['ncd'], config: config);
      final ids = schema.map((f) => f.fieldId).toSet();

      expect(ids, contains('weight'));
      expect(ids, isNot(contains('hba1c')));
    });

    test('known dual-sibling extra (glucose) survives despite no fieldRef', () {
      final config = _buildConfig(
        fields: {
          'glucoseType': _field(
            'glucoseType',
            programmeIds: ['ncd'],
            widgetHint: 'BloodGlucoseEntry',
            options: const [FieldOption(id: 'fbs', name: 'Fasting')],
          ),
          'glucose': _field('glucose', programmeIds: ['ncd'], unitMeasurement: 'mmol/L'),
        },
        forms: {
          'ncd': [
            const FormSection(
              sectionId: 'glucoseLog',
              title: 'Glucose',
              formType: 'ncd',
              fieldRefs: [FieldRef(id: 'glucoseType', isMandatory: false, inputType: 0)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['ncd'], config: config);
      final ids = schema.map((f) => f.fieldId).toSet();

      expect(ids, containsAll(['glucoseType', 'glucose']));
    });

    test('composite/label-only widget hints are never extractable', () {
      final config = _buildConfig(
        fields: {
          'bloodPressure': _field(
            'bloodPressure',
            programmeIds: ['ncd'],
            widgetHint: 'TextLabel',
          ),
        },
        forms: {
          'ncd': [
            const FormSection(
              sectionId: 'bpLog',
              title: 'BP',
              formType: 'ncd',
              fieldRefs: [FieldRef(id: 'bloodPressure', isMandatory: false, inputType: 0)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['ncd'], config: config);

      expect(schema.map((f) => f.fieldId), isNot(contains('bloodPressure')));
    });

    test('unsupported formTypes (pncMother, imci, tb) return no fields even with real layout data', () {
      final config = _buildConfig(
        fields: {
          'weight': _field('weight', programmeIds: ['pncMother'], unitMeasurement: 'kg'),
        },
        forms: {
          'pncMother': [
            const FormSection(
              sectionId: 'maternalHealthAssessment',
              title: 'Maternal',
              formType: 'pncMother',
              fieldRefs: [FieldRef(id: 'weight', isMandatory: false, inputType: 2)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['pncMother'], config: config);

      expect(schema, isEmpty);
    });

    test('dedupes fields shared across combined ANC+NCD programme names', () {
      final config = _buildConfig(
        fields: {
          'systolic': _field('systolic', programmeIds: ['anc', 'ncd'], unitMeasurement: 'mmHg'),
        },
        forms: {
          'anc': [
            const FormSection(
              sectionId: 'ancSpecificVitals',
              title: 'Vitals',
              formType: 'anc',
              fieldRefs: [FieldRef(id: 'systolic', isMandatory: false, inputType: 3)],
            ),
          ],
          'ncd': [
            const FormSection(
              sectionId: 'bpLog',
              title: 'BP',
              formType: 'ncd',
              fieldRefs: [FieldRef(id: 'systolic', isMandatory: false, inputType: 3)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['anc', 'ncd'], config: config);

      expect(schema.where((f) => f.fieldId == 'systolic'), hasLength(1));
      expect(schema.single.type, FieldType.integer);
    });

    test('known dual-sibling extra (glucose) survives for anc too', () {
      // Regression guard for the ANC blood-glucose gap: glucoseType is the
      // rendered fieldRef, glucose never has its own fieldRef, same pattern
      // as the ncd case above — anc needs the same extras exception.
      final config = _buildConfig(
        fields: {
          'glucoseType': _field(
            'glucoseType',
            programmeIds: ['anc'],
            widgetHint: 'BloodGlucoseEntry',
            options: const [FieldOption(id: 'fbs', name: 'Fasting')],
          ),
          'glucose': _field('glucose', programmeIds: ['anc'], unitMeasurement: 'mmol/L'),
        },
        forms: {
          'anc': [
            const FormSection(
              sectionId: 'labInvestigations',
              title: 'Lab',
              formType: 'anc',
              fieldRefs: [FieldRef(id: 'glucoseType', isMandatory: false, inputType: 0)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['anc'], config: config);
      final ids = schema.map((f) => f.fieldId).toSet();

      expect(ids, containsAll(['glucoseType', 'glucose']));
    });
  });

  group('FormFieldSchema.toJson() — allowedValueIds / multi', () {
    test('enum field carries allowedValueIds parallel to allowedValues', () {
      final config = _buildConfig(
        fields: {
          'glucoseType': _field(
            'glucoseType',
            programmeIds: ['ncd'],
            widgetHint: 'BloodGlucoseEntry',
            options: const [
              FieldOption(id: 'fbs', name: 'FBS (Before Meal)'),
              FieldOption(id: 'rbs', name: 'RBS (After Meal)'),
            ],
          ),
        },
        forms: {
          'ncd': [
            const FormSection(
              sectionId: 'glucoseLog',
              title: 'Glucose',
              formType: 'ncd',
              fieldRefs: [FieldRef(id: 'glucoseType', isMandatory: false, inputType: 0)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['ncd'], config: config);
      final field = schema.singleWhere((f) => f.fieldId == 'glucoseType');

      expect(field.allowedValues, ['FBS (Before Meal)', 'RBS (After Meal)']);
      expect(field.allowedValueIds, ['fbs', 'rbs']);

      final json = field.toJson();
      expect(json['allowedValues'], ['FBS (Before Meal)', 'RBS (After Meal)']);
      expect(json['allowedValueIds'], ['fbs', 'rbs']);
    });

    test('multi is true for a DialogCheckbox field, false for a single-select enum', () {
      final config = _buildConfig(
        fields: {
          'ncdSymptoms': _field(
            'ncdSymptoms',
            programmeIds: ['ncd'],
            widgetHint: 'DialogCheckbox',
            options: const [FieldOption(id: 'headache', name: 'Headache')],
          ),
          'glucoseType': _field(
            'glucoseType',
            programmeIds: ['ncd'],
            widgetHint: 'BloodGlucoseEntry',
            options: const [FieldOption(id: 'fbs', name: 'Fasting')],
          ),
        },
        forms: {
          'ncd': [
            const FormSection(
              sectionId: 'symptomsLog',
              title: 'Symptoms',
              formType: 'ncd',
              fieldRefs: [
                FieldRef(id: 'ncdSymptoms', isMandatory: false, inputType: 0),
                FieldRef(id: 'glucoseType', isMandatory: false, inputType: 0),
              ],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['ncd'], config: config);
      final multiField = schema.singleWhere((f) => f.fieldId == 'ncdSymptoms');
      final singleField = schema.singleWhere((f) => f.fieldId == 'glucoseType');

      expect(multiField.multi, isTrue);
      expect(multiField.toJson()['multi'], isTrue);
      expect(singleField.multi, isFalse);
      expect(singleField.toJson()['multi'], isFalse);
    });

    test('non-enum field always includes multi:false, no allowedValues/allowedValueIds keys', () {
      final config = _buildConfig(
        fields: {
          'temperature': _field('temperature', programmeIds: ['anc'], unitMeasurement: '°F'),
        },
        forms: {
          'anc': [
            const FormSection(
              sectionId: 'vitals',
              title: 'Vitals',
              formType: 'anc',
              fieldRefs: [FieldRef(id: 'temperature', isMandatory: false, inputType: 2)],
            ),
          ],
        },
      );

      final schema = FormFieldSchemaBuilder.forProgrammeNames(['anc'], config: config);
      final json = schema.single.toJson();

      expect(json['multi'], isFalse);
      expect(json.containsKey('allowedValues'), isFalse);
      expect(json.containsKey('allowedValueIds'), isFalse);
    });
  });
}
