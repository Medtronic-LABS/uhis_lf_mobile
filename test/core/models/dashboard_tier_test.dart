import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/dashboard_tier.dart';

void main() {
  group('DashboardTier.fromDueAt', () {
    final now = DateTime(2026, 7, 14, 21, 3);

    test('due tomorrow evening-clock is thisWeek (calendar), not dueToday', () {
      final due = DateTime(2026, 7, 15);
      expect(DashboardTier.fromDueAt(due, now: now), DashboardTier.thisWeek);
      // Wall-clock trap still exists — helper must not use it.
      expect(due.difference(now).inDays, 0);
    });

    test('due in 1..7 maps to thisWeek', () {
      for (var d = 1; d <= 7; d++) {
        final due = DateTime(2026, 7, 14).add(Duration(days: d));
        expect(
          DashboardTier.fromDueAt(due, now: now),
          DashboardTier.thisWeek,
          reason: 'd=$d',
        );
      }
    });

    test('due in 8+ is upcoming', () {
      final due = DateTime(2026, 7, 22);
      expect(DashboardTier.fromDueAt(due, now: now), DashboardTier.upcoming);
    });
  });

  group('DashboardTier.matchesVisitFilter', () {
    final now = DateTime(2026, 7, 14, 21);

    test('This week chip matches date schedule even when clinically critical', () {
      final due = DateTime(2026, 7, 15); // +1 calendar day
      expect(
        DashboardTier.matchesVisitFilter(
          filter: DashboardTier.thisWeek,
          itemTier: DashboardTier.critical,
          dueAt: due,
          now: now,
        ),
        isTrue,
      );
      expect(
        DashboardTier.matchesVisitFilter(
          filter: DashboardTier.critical,
          itemTier: DashboardTier.critical,
          dueAt: due,
          now: now,
        ),
        isTrue,
      );
    });

    test('This week chip rejects due today by date', () {
      final due = DateTime(2026, 7, 14);
      expect(
        DashboardTier.matchesVisitFilter(
          filter: DashboardTier.thisWeek,
          itemTier: DashboardTier.dueToday,
          dueAt: due,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
