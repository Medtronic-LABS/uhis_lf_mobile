import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/pregnancy_snapshot_dao.dart';
import 'package:uhis_next/core/mission/mission_pregnancy_facts.dart';
import 'package:uhis_next/core/risk/pregnancy_cohort_rules.dart';

void main() {
  final now = DateTime(2026, 6, 15);

  PregnancySnapshotRow row({
    int? lmpDaysAgo,
    int? eddDaysFromNow,
    int? deliveryDaysAgo,
  }) {
    return PregnancySnapshotRow(
      patientId: 'p1',
      facts: PregnancyFacts.empty,
      lmpDate: lmpDaysAgo == null
          ? null
          : now.subtract(Duration(days: lmpDaysAgo)).millisecondsSinceEpoch,
      eddDate: eddDaysFromNow == null
          ? null
          : now.add(Duration(days: eddDaysFromNow)).millisecondsSinceEpoch,
      deliveryDateMillis: deliveryDaysAgo == null
          ? null
          : now.subtract(Duration(days: deliveryDaysAgo)).millisecondsSinceEpoch,
    );
  }

  group('PregnancyCohortRules.isActivePregnancy', () {
    test('false when no snapshot row exists', () {
      expect(PregnancyCohortRules.isActivePregnancy(null, now: now), isFalse);
    });

    test('false when LMP is unknown', () {
      final r = row(eddDaysFromNow: 100);
      expect(PregnancyCohortRules.isActivePregnancy(r, now: now), isFalse);
    });

    test('false once delivery has been recorded', () {
      final r = row(lmpDaysAgo: 200, deliveryDaysAgo: 5);
      expect(PregnancyCohortRules.isActivePregnancy(r, now: now), isFalse);
    });

    test('true when LMP known and EDD unknown (assume active)', () {
      final r = row(lmpDaysAgo: 100);
      expect(PregnancyCohortRules.isActivePregnancy(r, now: now), isTrue);
    });

    test('true when EDD is within the 45-day overdue grace window', () {
      final r = row(lmpDaysAgo: 280, eddDaysFromNow: -44);
      expect(PregnancyCohortRules.isActivePregnancy(r, now: now), isTrue);
    });

    test('false once EDD is more than 45 days overdue', () {
      final r = row(lmpDaysAgo: 280, eddDaysFromNow: -46);
      expect(PregnancyCohortRules.isActivePregnancy(r, now: now), isFalse);
    });
  });

  group('PregnancyCohortRules.isPostnatal', () {
    test('false when no snapshot row exists', () {
      expect(PregnancyCohortRules.isPostnatal(null, now: now), isFalse);
    });

    test('false when no delivery has been recorded', () {
      final r = row(lmpDaysAgo: 100);
      expect(PregnancyCohortRules.isPostnatal(r, now: now), isFalse);
    });

    test('true exactly at the 42-day postnatal window boundary', () {
      final r = row(deliveryDaysAgo: 42);
      expect(PregnancyCohortRules.isPostnatal(r, now: now), isTrue);
    });

    test('false once more than 42 days past delivery', () {
      final r = row(deliveryDaysAgo: 43);
      expect(PregnancyCohortRules.isPostnatal(r, now: now), isFalse);
    });

    test('true for a delivery recorded today', () {
      final r = row(deliveryDaysAgo: 0);
      expect(PregnancyCohortRules.isPostnatal(r, now: now), isTrue);
    });
  });

  group('PregnancyCohortRules.daysSinceLmp / daysSinceDelivery', () {
    test('daysSinceLmp is null when unknown', () {
      expect(PregnancyCohortRules.daysSinceLmp(null, now: now), isNull);
      expect(PregnancyCohortRules.daysSinceLmp(row(), now: now), isNull);
    });

    test('daysSinceLmp reflects elapsed days', () {
      final r = row(lmpDaysAgo: 70);
      expect(PregnancyCohortRules.daysSinceLmp(r, now: now), 70);
    });

    test('daysSinceDelivery is null when no delivery recorded', () {
      expect(PregnancyCohortRules.daysSinceDelivery(row(), now: now), isNull);
    });

    test('daysSinceDelivery reflects elapsed days', () {
      final r = row(deliveryDaysAgo: 10);
      expect(PregnancyCohortRules.daysSinceDelivery(r, now: now), 10);
    });
  });
}
