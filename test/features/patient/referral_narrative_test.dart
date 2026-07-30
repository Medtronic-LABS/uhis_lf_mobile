import 'package:flutter_test/flutter_test.dart';
import 'package:leapwell/features/patient/referral_narrative.dart';

void main() {
  group('parseReferralReasonTokens', () {
    test('parses JSON array string without leaking brackets', () {
      expect(
        parseReferralReasonTokens('["bloodpressure", "symptoms"]'),
        ['bloodpressure', 'symptoms'],
      );
    });

    test('parses comma-separated list', () {
      expect(
        parseReferralReasonTokens('bloodPressure, bloodGlucose'),
        ['bloodPressure', 'bloodGlucose'],
      );
    });

    test('accepts List directly', () {
      expect(
        parseReferralReasonTokens(['bloodpressure', 'symptoms']),
        ['bloodpressure', 'symptoms'],
      );
    });
  });

  group('buildReferralNarrative', () {
    test('does not render raw JSON for bloodpressure + symptoms', () {
      final text = buildReferralNarrative(
        '["bloodpressure", "symptoms"]',
        {'bp': '150/95', 'bg': '12.0', 'bgType': 'RBS'},
      );
      expect(text, isNot(contains('[')));
      expect(text, isNot(contains(']')));
      expect(text, isNot(contains('"')));
      expect(text, contains('BP 150/95'));
      expect(text, contains('Blood sugar'));
      expect(text.toLowerCase(), isNot(contains('bloodpressure')));
      expect(text, contains('Clinical symptoms'));
    });

    test('maps bloodpressure token to BP narrative when vitals present', () {
      final text = buildReferralNarrative(
        '["bloodpressure"]',
        {'bp': '189/99', 'bg': '7.2', 'bgType': 'RBS'},
      );
      expect(text, contains('BP 189/99'));
      expect(text, isNot(contains('Bloodpressure')));
      expect(text, isNot(contains('[')));
    });

    test('comma-separated reasons still work', () {
      final text = buildReferralNarrative(
        'bloodPressure, bloodGlucose',
        {'bp': '150/95', 'bg': '12.0', 'bgType': 'RBS'},
      );
      expect(text, contains('BP 150/95'));
      expect(text, contains('Blood sugar'));
    });
  });

  group('shortReasonLabel', () {
    test('humanizes bloodpressure', () {
      expect(shortReasonLabel('bloodpressure'), 'High BP');
    });
  });
}
