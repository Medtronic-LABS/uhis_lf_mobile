/// Cross-programme BG sync: NCD/ANC `glucoseType`+`glucose` ↔ PNC maternal keys.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

import '../../../helpers/fake_form_deps.dart';

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
}
