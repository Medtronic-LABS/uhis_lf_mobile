/// Cross-programme BP sync: NCD `bpLogDetails` ↔ ANC/PNC flat keys.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

import '../../../helpers/fake_form_deps.dart';

void main() {
  late UnifiedFormNotifier notifier;

  setUp(() {
    notifier = buildTestNotifier(
      draftDao: FakeAssessmentDraftDao(),
      activeFormTypes: const ['anc', 'ncd'],
    );
  });

  group('BP cross-programme mirror', () {
    test('bpLogDetails mirrors systolic/diastolic/pulse to flat keys', () {
      notifier.updateField('bpLogDetails', [
        {'systolic': 140, 'diastolic': 90, 'pulse': 72},
      ]);
      expect(notifier.data.getValue('systolic'), 140);
      expect(notifier.data.getValue('diastolic'), 90);
      expect(notifier.data.getValue('pulse'), 72);
    });

    test('flat systolic/diastolic seed and update bpLogDetails', () {
      notifier.updateField('systolic', 130);
      notifier.updateField('diastolic', 85);
      notifier.updateField('pulse', 70);

      final log = notifier.data.getValue('bpLogDetails') as List;
      expect(log, isNotEmpty);
      final last = log.last as Map;
      expect(last['systolic'], 130);
      expect(last['diastolic'], 85);
      expect(last['pulse'], 70);
    });

    test('updating flat keys patches the latest bpLogDetails reading', () {
      notifier.updateField('bpLogDetails', [
        {'systolic': 120, 'diastolic': 80},
        {'systolic': 150, 'diastolic': 95},
      ]);
      notifier.updateField('systolic', 148);
      notifier.updateField('diastolic', 92);

      final log = notifier.data.getValue('bpLogDetails') as List;
      expect(log.length, 2);
      expect(log.first['systolic'], 120);
      expect(log.last['systolic'], 148);
      expect(log.last['diastolic'], 92);
    });
  });
}
