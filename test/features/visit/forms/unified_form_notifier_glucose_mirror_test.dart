/// Cross-programme BG sync: NCD/ANC `glucoseType`+`glucose` ↔ PNC maternal keys.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/scribe/models/ai_extracted_field.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

import '../../../helpers/fake_form_deps.dart';

Map<String, FieldDef> _bgFieldDefs() => {
      'glucoseType': FieldDef.fromJson('glucoseType', {
        'label': 'Glucose Test Type',
        'widgetHint': 'BloodGlucoseEntry',
        'optionsList': [
          {'id': 'fbs', 'name': 'Fasting'},
          {'id': 'rbs', 'name': 'Random'},
        ],
      }),
      'glucose': FieldDef.fromJson('glucose', {
        'label': 'Glucose',
        'widgetHint': 'EditText',
      }),
      'bloodSugar': FieldDef.fromJson('bloodSugar', {
        'label': 'Blood Sugar Type',
        'widgetHint': 'SingleSelectionView',
        'optionsList': [
          {'id': 'fasting', 'name': 'Fasting'},
          {'id': 'random', 'name': 'Random'},
        ],
      }),
      'fastingBloodSugar': FieldDef.fromJson('fastingBloodSugar', {
        'label': 'Fasting Blood Sugar',
        'widgetHint': 'EditText',
      }),
    };

AIExtractedField _ai(String fieldId, dynamic value) => AIExtractedField(
      fieldId: fieldId,
      value: value,
      confidence: 1.0,
    );

void main() {
  group('BG cross-programme mirror — PNC + NCD', () {
    late UnifiedFormNotifier notifier;

    setUp(() {
      notifier = buildTestNotifier(
        draftDao: FakeAssessmentDraftDao(),
        activeFormTypes: const ['pncMother', 'ncd'],
      );
    });

    test('NCD fbs + glucose mirrors to PNC bloodSugar / fastingBloodSugar', () {
      notifier.updateField('glucoseType', 'fbs');
      notifier.updateField('glucose', 5.6);

      expect(notifier.data.getValue('bloodSugar'), 'fasting');
      expect(notifier.data.getValue('fastingBloodSugar'), 5.6);
      expect(notifier.data.getValue('bloodSugarFasting'), 5.6);
      expect(notifier.data.getValue('glucoseType'), 'fbs');
      expect(notifier.data.getValue('glucose'), 5.6);
    });

    test('NCD rbs + glucose mirrors to PNC randomBloodSugar', () {
      notifier.updateField('glucoseType', 'rbs');
      notifier.updateField('glucose', 8.2);

      expect(notifier.data.getValue('bloodSugar'), 'random');
      expect(notifier.data.getValue('randomBloodSugar'), 8.2);
      expect(notifier.data.getValue('bloodSugarRandom'), 8.2);
    });

    test('PNC fastingBloodSugar mirrors to NCD glucoseType + glucose', () {
      notifier.updateField('bloodSugar', 'fasting');
      notifier.updateField('fastingBloodSugar', 6.1);

      expect(notifier.data.getValue('glucoseType'), 'fbs');
      expect(notifier.data.getValue('glucose'), 6.1);
      expect(notifier.data.getValue('bloodSugar'), 'fasting');
      expect(notifier.data.getValue('bloodSugarFasting'), 6.1);
    });

    test('PNC randomBloodSugar mirrors to NCD rbs + glucose', () {
      notifier.updateField('randomBloodSugar', 9.4);

      expect(notifier.data.getValue('bloodSugar'), 'random');
      expect(notifier.data.getValue('glucoseType'), 'rbs');
      expect(notifier.data.getValue('glucose'), 9.4);
    });

    test('selecting PNC bloodSugar type pulls existing maternal value into glucose',
        () {
      notifier.updateField('fastingBloodSugar', 4.8);
      notifier.updateField('bloodSugar', 'fasting');

      expect(notifier.data.getValue('glucoseType'), 'fbs');
      expect(notifier.data.getValue('glucose'), 4.8);
    });
  });

  group('BG cross-programme mirror — ANC + NCD', () {
    late UnifiedFormNotifier notifier;

    setUp(() {
      notifier = buildTestNotifier(
        draftDao: FakeAssessmentDraftDao(),
        activeFormTypes: const ['anc', 'ncd'],
      );
    });

    test('shared BloodGlucoseEntry keys stay aligned and fan out to maternal aliases',
        () {
      // ANC and NCD both write glucoseType/glucose; mirror also fills the
      // maternal / legacy ANC typed fields used by payloads and PNC widgets.
      notifier.updateField('glucoseType', 'fbs');
      notifier.updateField('glucose', 7.0);

      expect(notifier.data.getValue('glucoseType'), 'fbs');
      expect(notifier.data.getValue('glucose'), 7.0);
      expect(notifier.data.getValue('bloodSugar'), 'fasting');
      expect(notifier.data.getValue('fastingBloodSugar'), 7.0);
      expect(notifier.data.getValue('bloodSugarFasting'), 7.0);
    });

    test('legacy ANC bloodSugarFasting mirrors into NCD glucose fields', () {
      notifier.updateField('bloodSugarFasting', 5.2);

      expect(notifier.data.getValue('glucoseType'), 'fbs');
      expect(notifier.data.getValue('glucose'), 5.2);
      expect(notifier.data.getValue('bloodSugar'), 'fasting');
      expect(notifier.data.getValue('fastingBloodSugar'), 5.2);
    });
  });

  group('BG cross-programme mirror — applyAiPrefill PNC + NCD', () {
    late UnifiedFormNotifier notifier;

    setUp(() {
      notifier = buildTestNotifier(
        draftDao: FakeAssessmentDraftDao(),
        activeFormTypes: const ['pncMother', 'ncd'],
      );
    });

    tearDown(() => notifier.dispose());

    test('NCD glucoseType + glucose fill PNC maternal keys', () {
      notifier.applyAiPrefill(
        [_ai('glucoseType', 'fbs'), _ai('glucose', 5.6)],
        fieldDefs: _bgFieldDefs(),
      );

      expect(notifier.data.getValue('bloodSugar'), 'fasting');
      expect(notifier.data.getValue('fastingBloodSugar'), 5.6);
      expect(notifier.data.getValue('glucoseType'), 'fbs');
      expect(notifier.data.getValue('glucose'), 5.6);
    });

    test('PNC fastingBloodSugar fill seeds NCD glucoseType + glucose', () {
      notifier.applyAiPrefill(
        [_ai('fastingBloodSugar', 6.1)],
        fieldDefs: _bgFieldDefs(),
      );

      expect(notifier.data.getValue('glucoseType'), 'fbs');
      expect(notifier.data.getValue('glucose'), 6.1);
      expect(notifier.data.getValue('bloodSugar'), 'fasting');
    });
  });
}
