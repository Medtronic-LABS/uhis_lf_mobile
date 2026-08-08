/// Unit tests for [DateFormatStrings.monthAbbrev] — the single source of
/// month-abbreviation copy, extracted to de-duplicate three call sites that
/// each carried their own inline 'Jan'..'Dec' array (household detail /
/// enrollment localization pass, Task 2).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

void main() {
  // AppLocale.current is a global static flag shared across the whole test
  // process (see app_locale.dart). Any case that sets it to bangla must
  // restore english afterwards or it leaks into unrelated test files run in
  // the same suite.
  tearDown(() {
    AppLocale.current = AppLanguage.english;
  });

  group('DateFormatStrings.monthAbbrev — English fallback', () {
    const expected = <int, String>{
      1: 'Jan',
      2: 'Feb',
      3: 'Mar',
      4: 'Apr',
      5: 'May',
      6: 'Jun',
      7: 'Jul',
      8: 'Aug',
      9: 'Sep',
      10: 'Oct',
      11: 'Nov',
      12: 'Dec',
    };

    expected.forEach((month, abbrev) {
      test('month $month returns "$abbrev"', () {
        expect(DateFormatStrings.monthAbbrev(month), abbrev);
      });
    });
  });

  group('DateFormatStrings.monthAbbrev — Bangla-locale fallback behaviour',
      () {
    test(
        'still returns the English abbreviation under the Bangla locale, '
        'since strings.json is not loaded in this harness and carries no '
        'DateFormat.month* entries for getTranslatedString to prefer',
        () {
      AppLocale.current = AppLanguage.bangla;

      expect(DateFormatStrings.monthAbbrev(1), 'Jan');
      expect(DateFormatStrings.monthAbbrev(12), 'Dec');
    });
  });
}
