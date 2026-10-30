import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/teleconsult/consent_template_filler.dart';

void main() {
  group('fillConsentTemplate', () {
    test('substitutes all known tokens', () {
      const html = '{{participant_name}}|{{participant_id}}|{{chw_name}}|'
          '{{consent_version}}|{{language}}|{{consent_method}}|{{date_time}}';

      final result = fillConsentTemplate(
        html,
        participantName: 'Jane Doe',
        participantId: 'PAT-1',
        dateTime: DateTime(2026, 3, 5, 9, 7),
        lng: 'en',
        chwName: 'Dr. Rahman',
        consentVersion: '3',
      );

      expect(
        result,
        'Jane Doe|PAT-1|Dr. Rahman|3|English|App|2026-03-05 09:07',
      );
    });

    test('uses Bangla language/method labels when lng is bn', () {
      final result = fillConsentTemplate(
        '{{language}}/{{consent_method}}',
        participantName: 'X',
        participantId: 'Y',
        dateTime: DateTime(2026, 1, 1),
        lng: 'bn',
      );

      expect(result, 'বাংলা/অ্যাপ');
    });

    test('missing optional tokens substitute as empty strings, not "null"', () {
      final result = fillConsentTemplate(
        '[{{chw_name}}][{{consent_version}}]',
        participantName: 'X',
        participantId: 'Y',
        dateTime: DateTime(2026, 1, 1),
        lng: 'en',
      );

      expect(result, '[][]');
    });

    test('pads single-digit month/day/hour/minute with a leading zero', () {
      final result = fillConsentTemplate(
        '{{date_time}}',
        participantName: 'X',
        participantId: 'Y',
        dateTime: DateTime(2026, 1, 2, 3, 4),
        lng: 'en',
      );

      expect(result, '2026-01-02 03:04');
    });

    test('leaves unrecognized placeholders untouched', () {
      final result = fillConsentTemplate(
        '{{unknown_token}}',
        participantName: 'X',
        participantId: 'Y',
        dateTime: DateTime(2026, 1, 1),
        lng: 'en',
      );

      expect(result, '{{unknown_token}}');
    });
  });
}
