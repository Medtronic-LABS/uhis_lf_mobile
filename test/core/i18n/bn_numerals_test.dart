import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/i18n/bn_numerals.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.bangla);

  group('toBengaliDigits', () {
    test('maps every Latin digit', () {
      expect(BnNumerals.toBengaliDigits('0123456789'), '০১২৩৪৫৬৭৮৯');
    });

    test('preserves separators inside a blood-pressure reading', () {
      // The screenshot case: 151/101 must keep its slash.
      expect(BnNumerals.toBengaliDigits('151/101'), '১৫১/১০১');
    });

    test('converts digits embedded in Bangla text', () {
      // "9 সপ্তাহ 1 দিন" rendered Bangla words with Latin digits.
      expect(
        BnNumerals.toBengaliDigits('9 সপ্তাহ 1 দিন'),
        '৯ সপ্তাহ ১ দিন',
      );
    });

    test('leaves letters and punctuation alone', () {
      expect(BnNumerals.toBengaliDigits('4m/F'), '৪m/F');
      expect(BnNumerals.toBengaliDigits('10 August 2026'), '১০ August ২০২৬');
      expect(BnNumerals.toBengaliDigits('BP mmHg'), 'BP mmHg');
    });

    test('handles decimals and negatives without mangling the symbols', () {
      expect(BnNumerals.toBengaliDigits('12.5'), '১২.৫');
      expect(BnNumerals.toBengaliDigits('-3'), '-৩');
    });

    test('empty string is returned as-is', () {
      expect(BnNumerals.toBengaliDigits(''), '');
    });

    test('already-Bengali digits are left untouched', () {
      // Guards against double conversion if a value passes through twice.
      expect(BnNumerals.toBengaliDigits('১৫১'), '১৫১');
    });
  });

  group('localize — locale aware', () {
    test('converts when the app is in Bangla', () {
      AppLocale.current = AppLanguage.bangla;
      expect(BnNumerals.localize('151/101'), '১৫১/১০১');
    });

    test('is a no-op in English', () {
      AppLocale.current = AppLanguage.english;
      expect(BnNumerals.localize('151/101'), '151/101');
    });

    test('reads the locale at call time, not at import time', () {
      // Strings resolve at build, so a mid-session language switch must be
      // reflected by the very next call.
      AppLocale.current = AppLanguage.english;
      final english = BnNumerals.localize('2026');
      AppLocale.current = AppLanguage.bangla;
      final bangla = BnNumerals.localize('2026');

      expect(english, '2026');
      expect(bangla, '২০২৬');
    });

    test('localizeNumber accepts ints and doubles', () {
      AppLocale.current = AppLanguage.bangla;
      expect(BnNumerals.localizeNumber(93), '৯৩');
      expect(BnNumerals.localizeNumber(12.5), '১২.৫');
    });

    test('string extension matches the static call', () {
      AppLocale.current = AppLanguage.bangla;
      expect('151/101'.localizedDigits, BnNumerals.localize('151/101'));
    });
  });
}
