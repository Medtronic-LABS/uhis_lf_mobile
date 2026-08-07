import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/time/calendar_day.dart';

void main() {
  group('CalendarDay.daysBetween', () {
    test('evening today vs midnight tomorrow is 1 day, not 0', () {
      final evening = DateTime(2026, 7, 14, 21, 3);
      final dueMidnight = DateTime(2026, 7, 15);
      expect(evening.difference(dueMidnight).inDays.abs(), 0); // wall-clock trap
      expect(CalendarDay.daysBetween(evening, dueMidnight), 1);
    });

    test('same calendar day is 0 regardless of clock', () {
      final morning = DateTime(2026, 7, 15, 8);
      final evening = DateTime(2026, 7, 15, 22);
      expect(CalendarDay.daysBetween(morning, evening), 0);
      expect(CalendarDay.isSameDay(morning, evening), isTrue);
    });

    test('overdue by calendar day', () {
      final now = DateTime(2026, 7, 15, 9);
      final due = DateTime(2026, 7, 14);
      expect(CalendarDay.daysBetween(now, due), -1);
      expect(CalendarDay.daysBetween(due, now), 1);
    });
  });

  group('CalendarDay today/tomorrow window', () {
    test('half-open today window spans exactly one local day', () {
      final now = DateTime(2026, 7, 14, 21, 3);
      final start = CalendarDay.todayStart(now);
      final end = CalendarDay.tomorrowStart(now);
      expect(start, DateTime(2026, 7, 14));
      expect(end, DateTime(2026, 7, 15));
      expect(end.difference(start).inDays, 1);
    });
  });

  group('CalendarDay.ageMonthsFromDob', () {
    final now = DateTime(2026, 7, 15);

    test('null/empty/unparseable dob returns null', () {
      expect(CalendarDay.ageMonthsFromDob(null, now), isNull);
      expect(CalendarDay.ageMonthsFromDob('', now), isNull);
      expect(CalendarDay.ageMonthsFromDob('not-a-date', now), isNull);
    });

    test('9-month-old (the reported "0Y" bug) resolves to 9', () {
      expect(CalendarDay.ageMonthsFromDob('2025-10-15', now), 9);
    });

    test('day-of-month not yet reached borrows a month', () {
      // 15 Jul minus 20 Jan is 6 months by month-diff alone, but the 20th
      // hasn't happened yet this month, so only 5 full months have elapsed.
      expect(CalendarDay.ageMonthsFromDob('2026-01-20', now), 5);
    });

    test('exactly 12 months old', () {
      expect(CalendarDay.ageMonthsFromDob('2025-07-15', now), 12);
    });

    test('future dob (clock skew) floors at 0, not negative', () {
      expect(CalendarDay.ageMonthsFromDob('2026-08-01', now), 0);
    });
  });
}
