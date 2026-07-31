import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/scribe/models/ai_extracted_field.dart';

void main() {
  group('FormPrefillResult.withRecoveredVitals', () {
    test('recovers Hindi height and weight from transcript', () {
      final result = FormPrefillResult(
        fields: const [],
        transcriptText:
            'मेरा हाइट 170 सेंटीमीटर है और मेरा वेट 80 केजी है '
            'ব্লাড প্রেজার 120/80 হ্যায়',
      ).withRecoveredVitals();

      expect(result.getValue('height'), 170);
      expect(result.getValue('weight'), 80);
      expect(result.hasField('bpLogDetails'), isFalse);
    });

    test('does not treat BP slash reading as height', () {
      final result = FormPrefillResult(
        fields: const [],
        transcriptText: 'ব্লাড প্রেজার 120/80 হ্যায়',
      ).withRecoveredVitals();
      expect(result.hasField('height'), isFalse);
    });

    test('recovers hba1c from code-mixed utterance', () {
      final result = FormPrefillResult(
        fields: const [],
        transcriptText: 'मेरा एच बी এ ওয়ান সি रीडিং 4.1 হ্যাঁ',
      ).withRecoveredVitals();
      expect(result.getValue('hba1c'), 4.1);
    });
  });
}
