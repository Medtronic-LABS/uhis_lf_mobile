import 'package:intl/intl.dart';

/// Date-of-birth parsing, formatting and age maths shared by the household-head
/// form ([CreateHouseholdScreen]) and the member form
/// ([AddHouseholdMemberScreen]), which previously each had their own copy and
/// disagreed on the picker range and on how age was derived.
///
/// Two representations exist and must not be mixed up:
///  * [display] — `DD-MM-YYYY`, what the SK reads in the field.
///  * [wire] — `yyyy-MM-dd`, what [HouseholdMember.dateOfBirth] carries into the
///    local DB and the sync payload, where it is parsed with `DateTime.parse`.
abstract final class EnrollmentDob {
  static final DateFormat _display = DateFormat('dd-MM-yyyy');
  static final DateFormat _wire = DateFormat('yyyy-MM-dd');

  /// Spice registration.json caps `dateOfBirth` at `maxAge: 130`.
  static const int maxAgeYears = 130;

  static DateTime earliestBirthDate() {
    final now = DateTime.now();
    return DateTime(now.year - maxAgeYears, now.month, now.day);
  }

  static String display(DateTime date) => _display.format(date);

  static String wire(DateTime date) => _wire.format(date);

  /// Approximate date of birth for a manually typed age in whole years:
  /// 1 January of (current year − [years]). Matches the Android AgeOrDob
  /// fallback when the SK enters age instead of a full date.
  static DateTime fromAgeYears(int years, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final clamped = years < 0
        ? 0
        : (years > maxAgeYears ? maxAgeYears : years);
    return DateTime(now.year - clamped, 1, 1);
  }

  /// Parses either representation, plus the slash-separated and full-timestamp
  /// forms that NID OCR, the patient lookup and previously saved drafts return.
  /// Returns null when [raw] holds no usable date.
  static DateTime? parse(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;

    final iso = DateTime.tryParse(s);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final dmy = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(s);
    if (dmy == null) return null;
    final day = int.parse(dmy.group(1)!);
    final month = int.parse(dmy.group(2)!);
    final year = int.parse(dmy.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }
}

/// Age split into years/months/days, presented the way Android's
/// `getAgeOrDobDisplay` does it: whole years from the first birthday onwards,
/// months for infants, days for newborns.
class EnrollmentAge {
  const EnrollmentAge({
    required this.years,
    required this.months,
    required this.days,
  });

  factory EnrollmentAge.from(DateTime dateOfBirth, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();

    var years = now.year - dateOfBirth.year;
    var months = now.month - dateOfBirth.month;
    var days = now.day - dateOfBirth.day;

    if (days < 0) {
      months--;
      days += DateTime(now.year, now.month, 0).day;
    }
    if (months < 0) {
      years--;
      months += 12;
    }

    return EnrollmentAge(years: years, months: months, days: days);
  }

  final int years;
  final int months;
  final int days;

  /// Number shown in the age field, in the unit named by [unit].
  int get value {
    if (years >= 1) return years;
    if (months > 0) return months;
    return days < 1 ? 1 : days;
  }

  String get unit {
    if (years >= 1) return years == 1 ? 'year' : 'years';
    if (months > 0) return months == 1 ? 'month' : 'months';
    return value == 1 ? 'day' : 'days';
  }

  String get summary {
    if (years >= 1) {
      return months > 0
          ? '$years yr ${months}m old'
          : '$years year${years == 1 ? '' : 's'} old';
    }
    if (months > 0) return '$months month${months == 1 ? '' : 's'} old';
    return days < 1 ? '< 1 day old' : '$days days old';
  }

  /// Compact list/header chip: `12d` / `4m` under 24 months, else whole years.
  /// Prefer this over raw `age` years so infants are never shown as `0/F`.
  static String? compactChipLabel(String? dateOfBirth, {int? fallbackYears}) {
    final dob = EnrollmentDob.parse(dateOfBirth);
    if (dob != null) {
      final age = EnrollmentAge.from(dob);
      final totalMonths = age.years * 12 + age.months;
      if (totalMonths < 24) {
        if (totalMonths < 1) {
          if (age.days < 1) return '<1d';
          return '${age.days}d';
        }
        return '${totalMonths}m';
      }
      return '${age.years}';
    }
    if (fallbackYears == null) return null;
    if (fallbackYears < 1) return '<1y';
    return '$fallbackYears';
  }
}
