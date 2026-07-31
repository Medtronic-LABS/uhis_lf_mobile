import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/rmnch_follow_up_calculator.dart';

void main() {
  group('RmnchFollowUpCalculator', () {
    test('ANC community default is today + 28 days', () {
      final now = DateTime(2026, 7, 20);
      final next = RmnchFollowUpCalculator.ancCommunityDefault(now);
      expect(next, DateTime(2026, 8, 17));
      expect(RmnchFollowUpCalculator.toFormDate(next), '2026-08-17');
    });

    test('PNC bands match Android summary', () {
      final now = DateTime(2026, 7, 20);
      expect(
        RmnchFollowUpCalculator.pncFromDaysSinceDelivery(1, now),
        DateTime(2026, 7, 23),
      );
      expect(
        RmnchFollowUpCalculator.pncFromDaysSinceDelivery(4, now),
        DateTime(2026, 7, 27),
      );
      expect(
        RmnchFollowUpCalculator.pncFromDaysSinceDelivery(10, now),
        DateTime(2026, 8, 3),
      );
      expect(
        RmnchFollowUpCalculator.pncFromDaysSinceDelivery(20, now),
        DateTime(2026, 8, 31),
      );
    });

    test('ANC from LMP uses pregnancy-month bands (community −15d)', () {
      // ~8 weeks pregnant → month ≈ 2 → band 0–4 → LMP + (28*5 − 15)
      final lmp = DateTime(2026, 5, 25);
      final now = DateTime(2026, 7, 20);
      final next = RmnchFollowUpCalculator.ancFromLmp(
        lmp,
        now: now,
      );
      expect(next, DateTime(2026, 5, 25).add(const Duration(days: 125)));
    });
  });
}
