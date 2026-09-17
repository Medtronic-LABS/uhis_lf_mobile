import 'app_locale.dart';

/// Bengali digit localisation.
///
/// QA reported member age rendering as `4m/F` in a Bangla app. Nothing in the
/// codebase converted digits, so every number — ages, vitals, counts, dates —
/// rendered in Latin numerals regardless of language.
///
/// Deliberately code-point mapping rather than `NumberFormat`: the strings that
/// need converting are already-composed display text like `151/101`,
/// `9 সপ্তাহ 1 দিন` or `10 August 2026`, not bare numbers. A formatter would
/// require parsing each of those apart first.
abstract final class BnNumerals {
  BnNumerals._();

  /// U+09E6..U+09EF, indexed by the Latin digit they replace.
  static const List<String> _bengaliDigits = [
    '০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯',
  ];

  static const int _latinZero = 0x30; // '0'
  static const int _latinNine = 0x39; // '9'

  /// Replaces Latin digits with Bengali ones, unconditionally.
  ///
  /// Everything that is not a digit — letters, `/`, `.`, `-`, spaces, Bengali
  /// text already present — passes through untouched, so `151/101` becomes
  /// `১৫১/১০১` and separators survive.
  static String toBengaliDigits(String input) {
    if (input.isEmpty) return input;
    final buffer = StringBuffer();
    for (final unit in input.codeUnits) {
      if (unit >= _latinZero && unit <= _latinNine) {
        buffer.write(_bengaliDigits[unit - _latinZero]);
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  /// [toBengaliDigits] when the app is in Bangla, otherwise unchanged.
  ///
  /// The locale check lives here rather than inside [toBengaliDigits] so the
  /// conversion itself stays pure and directly testable.
  static String localize(String input) =>
      AppLocale.isBangla ? toBengaliDigits(input) : input;

  /// [localize] for a number.
  static String localizeNumber(num value) => localize('$value');
}

extension BnNumeralsString on String {
  /// Convenience for render sites: `'$systolic/$diastolic'.localizedDigits`.
  String get localizedDigits => BnNumerals.localize(this);
}
