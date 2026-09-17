import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/features/patient/referral_narrative.dart';

void main() {
  // AppLocale.current is a global static flag (the app's context-free
  // localization seam) shared across the whole test process; it defaults to
  // bangla, so pin english here and restore it in tearDown so this file
  // doesn't leak locale state into other test files run in the same suite.
  setUp(() {
    AppLocale.current = AppLanguage.english;
  });

  tearDown(() {
    AppLocale.current = AppLanguage.english;
  });

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

    test('splits English and / middle-dot lists used on CCE cards', () {
      expect(
        parseReferralReasonTokens('Symptoms, High BP and High BG'),
        ['Symptoms', 'High BP', 'High BG'],
      );
      expect(
        parseReferralReasonTokens('Symptoms · High BP · High BG'),
        ['Symptoms', 'High BP', 'High BG'],
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

    test('BP >= 160/110 renders the dangerously-elevated sentence exactly',
        () {
      final text = buildReferralNarrative(
        '["bloodpressure"]',
        {'bp': '189/99'},
      );
      expect(
        text,
        'BP 189/99 is dangerously elevated — urgent referral needed.',
      );
    });

    test(
        'bloodpressure + symptoms with vitals renders the exact composed '
        'narrative (locks English wording end to end)', () {
      final text = buildReferralNarrative(
        '["bloodpressure", "symptoms"]',
        {'bp': '150/95', 'bg': '12.0', 'bgType': 'RBS'},
      );
      expect(
        text,
        'BP 150/95 is above the normal — review and follow-up required. '
        'Blood sugar 12.0 mmol/L (RBS) is elevated — review and follow-up '
        'required. Clinical symptoms present — review and follow-up '
        'required.',
      );
    });

    test('Hb < 7 renders the severe-anemia sentence with the exact value',
        () {
      final text = buildReferralNarrative('anemia', {'hemoglobin': '6.5'});
      expect(
        text,
        'Severe anemia (Hb 6.5 g/dL) — urgent review needed.',
      );
    });

    test('Hb between 7 and 10 renders the non-severe anemia sentence', () {
      final text = buildReferralNarrative('anemia', {'hemoglobin': '9.0'});
      expect(
        text,
        'Anemia (Hb 9.0 g/dL) — review iron supplementation.',
      );
    });

    test('pulse > 90 selects the above-normal sentence (not a spliced '
        'fragment)', () {
      final text = buildReferralNarrative('pulse', {'pulse': '110'});
      expect(
        text,
        'Pulse 110 bpm is above normal — needs urgent attention.',
      );
    });

    test('pulse < 60 selects the below-normal sentence (not a spliced '
        'fragment)', () {
      final text = buildReferralNarrative('pulse', {'pulse': '50'});
      expect(
        text,
        'Pulse 50 bpm is below normal — needs urgent attention.',
      );
    });
  });

  group('shortReasonLabel', () {
    test('humanizes bloodpressure', () {
      expect(shortReasonLabel('bloodpressure'), 'High BP');
    });

    test('humanizes anemia', () {
      expect(shortReasonLabel('anemia'), 'Low Hb / Anemia');
    });

    test('humanizes overdueVisit via the overdue match branch', () {
      expect(shortReasonLabel('overdueVisit'), 'Visit overdue');
    });

    test('maps Spice NCD wire chips', () {
      expect(shortReasonLabel('Symptoms'), 'Symptoms');
      expect(shortReasonLabel('High BP'), 'High BP');
      expect(shortReasonLabel('High BG'), 'High BG');
    });
  });
}
