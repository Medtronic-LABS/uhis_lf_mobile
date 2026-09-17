import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/i18n/app_date_format.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

/// Dates could not be Bangla at all before this: `initializeDateFormatting` was
/// never called and no `DateFormat` was given a locale, so all ~16 display call
/// sites rendered English month names and Latin digits regardless of language.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppDateFormat.ensureInitialised();
  });

  tearDown(() => AppLocale.current = AppLanguage.bangla);

  final date = DateTime(2026, 8, 10);

  test('renders English when the app is in English', () {
    AppLocale.current = AppLanguage.english;
    expect(AppDateFormat.dayMonthYearFmt.format(date), '10 Aug 2026');
  });

  test('renders Bangla month names and digits when in Bangla', () {
    AppLocale.current = AppLanguage.bangla;
    final out = AppDateFormat.dayMonthYearFmt.format(date);

    expect(out, isNot(contains('Aug')), reason: 'month should be localized');
    expect(RegExp(r'[0-9]').hasMatch(out), isFalse,
        reason: 'no Latin digits should survive: $out');
  });

  test('a language switch is reflected immediately', () {
    // The regression this guards: three call sites cached the DateFormat in a
    // `static final`, which froze whichever language was active at first use.
    AppLocale.current = AppLanguage.english;
    final english = AppDateFormat.dayMonthYearFmt.format(date);
    AppLocale.current = AppLanguage.bangla;
    final bangla = AppDateFormat.dayMonthYearFmt.format(date);

    expect(bangla, isNot(english));
  });

  test('every display format is locale-aware', () {
    AppLocale.current = AppLanguage.bangla;
    for (final formatted in [
      AppDateFormat.dayMonthYearFmt.format(date),
      AppDateFormat.dayMonthYearPaddedFmt.format(date),
      AppDateFormat.dayMonthNameYearFmt.format(date),
      AppDateFormat.monthYearFmt.format(date),
      AppDateFormat.dayMonthFmt.format(date),
    ]) {
      expect(RegExp(r'[0-9]').hasMatch(formatted), isFalse,
          reason: 'Latin digits leaked through: $formatted');
    }
  });

  test('the wire format stays Latin in Bangla', () {
    // iso() reaches the backend and the local DB; a Bengali-digit date there
    // would be unparseable.
    AppLocale.current = AppLanguage.bangla;
    expect(AppDateFormat.iso(date), '2026-08-10');
  });
}
