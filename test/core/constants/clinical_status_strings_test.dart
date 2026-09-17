import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

/// The detail sheets used to render backend codes verbatim — an SK saw
/// `HIGH_RISK_PW` and `UNCONTROLLED_BP` as clinical status.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTranslations();
  });

  tearDown(() => AppLocale.current = AppLanguage.bangla);

  group('known codes', () {
    test('map to Bangla', () {
      AppLocale.current = AppLanguage.bangla;
      for (final code in [
        'HIGH_RISK_PW',
        'NORMAL_PREGNANCY',
        'UNCONTROLLED_BP',
        'UNCONTROLLED_BG',
        'Referred',
        'rbs',
      ]) {
        final label = ClinicalStatusStrings.label(code);
        expect(label, isNot(code), reason: '$code was not localized');
        expect(label, isNot(contains('_')),
            reason: 'raw enum shape leaked for $code: $label');
      }
    });

    test('are case- and separator-insensitive', () {
      // Backends have sent 'OnTreatment', 'ON_TREATMENT' and 'on treatment'.
      final a = ClinicalStatusStrings.label('ONTREATMENT');
      final b = ClinicalStatusStrings.label('On_Treatment');
      final c = ClinicalStatusStrings.label('on treatment');
      expect(a, b);
      expect(b, c);
    });

    test('map to English when the app is in English', () {
      AppLocale.current = AppLanguage.english;
      expect(ClinicalStatusStrings.label('HIGH_RISK_PW'), 'High-risk pregnancy');
      expect(ClinicalStatusStrings.label('Referred'), 'Referred');
    });
  });

  group('unknown codes', () {
    test('are humanized, never shown as a raw enum', () {
      // A new backend value should read as awkward English, not as a database
      // identifier — this is the fallback that stops the original bug
      // reappearing the next time the backend adds a status.
      expect(ClinicalStatusStrings.label('SOME_NEW_CODE'), 'Some new code');
      expect(ClinicalStatusStrings.label('SOME_NEW_CODE'), isNot(contains('_')));
    });

    test('empty and whitespace input do not crash', () {
      expect(ClinicalStatusStrings.label(''), '');
      expect(ClinicalStatusStrings.label('   '), isNotNull);
    });
  });

  test('labelAll joins a list and localizes each element', () {
    AppLocale.current = AppLanguage.english;
    final out = ClinicalStatusStrings.labelAll(
        ['UNCONTROLLED_BP', 'UNCONTROLLED_BG']);
    expect(out, 'Uncontrolled blood pressure, Uncontrolled blood sugar');
  });
}
