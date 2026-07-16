/// Calendar-date helpers — day math must ignore wall-clock time.
///
/// `DateTime.difference(...).inDays` truncates toward zero, so e.g.
/// 15 Jul 00:00 minus 14 Jul 21:00 yields **0** instead of **1**. Always
/// truncate both sides to local midnight before comparing days.
abstract final class CalendarDay {
  static DateTime startOf(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  /// Signed calendar days from [from]'s date to [to]'s date (`to − from`).
  static int daysBetween(DateTime from, DateTime to) =>
      startOf(to).difference(startOf(from)).inDays;

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Local midnight at the start of today.
  static DateTime todayStart([DateTime? now]) => startOf(now ?? DateTime.now());

  /// Local midnight at the start of tomorrow (exclusive upper bound for "today").
  static DateTime tomorrowStart([DateTime? now]) =>
      todayStart(now).add(const Duration(days: 1));

  /// Age in whole years from an ISO-8601 date-of-birth string, or null if
  /// [dob] is null, empty, or unparseable.
  static int? ageFromDob(String? dob) {
    if (dob == null || dob.isEmpty) return null;
    final parsed = DateTime.tryParse(dob);
    if (parsed == null) return null;
    final now = DateTime.now();
    var years = now.year - parsed.year;
    if (now.month < parsed.month ||
        (now.month == parsed.month && now.day < parsed.day)) {
      years--;
    }
    return years < 0 ? 0 : years;
  }
}
