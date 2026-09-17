import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app_locale.dart';

/// Locale-aware date formatting.
///
/// Before this, `DateFormat('d MMM yyyy')` was constructed with no locale at
/// ~12 call sites and `initializeDateFormatting` was never called, so every
/// date rendered in English — `10 August 2026` — no matter the app language.
///
/// Patterns mirror the ones already in use so call sites change only which
/// helper they call, not how the date looks in English.
abstract final class AppDateFormat {
  AppDateFormat._();

  static bool _initialised = false;

  /// Loads Bengali symbol data. Must run before any Bangla formatting, and is
  /// safe to call more than once.
  static Future<void> ensureInitialised() async {
    if (_initialised) return;
    await initializeDateFormatting('bn');
    _initialised = true;
  }

  /// Intl locale tag for the current app language.
  static String get _locale => AppLocale.isBangla ? 'bn' : 'en';

  // Exposed as DateFormat getters rather than cached statics: call sites use
  // them both as `X.format(d)` and by assigning to a local, and a getter
  // re-reads the locale so a mid-session language switch is picked up. A
  // `static final` would freeze whichever language was active at first use.

  /// `7 Jun 2026` / `৭ জুন ২০২৬`
  static DateFormat get dayMonthYearFmt => DateFormat('d MMM yyyy', _locale);

  /// `07 Jun 2026` — zero-padded day.
  static DateFormat get dayMonthYearPaddedFmt =>
      DateFormat('dd MMM yyyy', _locale);

  /// `07 June 2026` — full month name.
  static DateFormat get dayMonthNameYearFmt =>
      DateFormat('dd MMMM yyyy', _locale);

  /// `June 2026`
  static DateFormat get monthYearFmt => DateFormat('MMMM yyyy', _locale);

  /// `7 Jun` — no year, for same-year contexts.
  static DateFormat get dayMonthFmt => DateFormat('d MMM', _locale);

  /// `5:22 PM`
  static DateFormat get timeFmt => DateFormat('h:mm a', _locale);

  /// `10 August 2026 · 5:22 PM` — the assessment detail sheet header.
  static DateFormat get dayMonthNameYearTimeFmt =>
      DateFormat('d MMMM yyyy · h:mm a', _locale);

  // Convenience wrappers for the common one-shot case.
  static String dayMonthYear(DateTime date) => dayMonthYearFmt.format(date);
  static String monthYear(DateTime date) => monthYearFmt.format(date);
  static String time(DateTime date) => timeFmt.format(date);

  /// Machine format for wire values and form fields.
  ///
  /// Deliberately locale-free: this reaches the backend and the local database,
  /// where a Bengali-digit date would be unparseable.
  static String iso(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
}
