import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/sync/pregnancy_delivery_sync.dart';

void main() {
  group('PregnancyDeliverySync.isWithinPostpartumWindow', () {
    test('true within 42 days inclusive', () {
      final now = DateTime(2026, 9, 2);
      final delivery = now.subtract(const Duration(days: 10));
      expect(
        PregnancyDeliverySync.isWithinPostpartumWindow(
          delivery.millisecondsSinceEpoch,
          now,
        ),
        isTrue,
      );
    });

    test('false after 42 days', () {
      final now = DateTime(2026, 9, 2);
      final delivery = now.subtract(const Duration(days: 43));
      expect(
        PregnancyDeliverySync.isWithinPostpartumWindow(
          delivery.millisecondsSinceEpoch,
          now,
        ),
        isFalse,
      );
    });
  });

  group('PregnancyDeliverySync.deliveryDateMillisFromMap', () {
    test('reads nested pregnancyOutcome.deliveryOutcomes.dateOfDelivery', () {
      final ms = DateTime.parse('2026-08-01T00:00:00Z').millisecondsSinceEpoch;
      final extracted = PregnancyDeliverySync.deliveryDateMillisFromMap({
        'assessmentDetails': {
          'pregnancyOutcome': {
            'deliveryOutcomes': {
              'dateOfDelivery': '2026-08-01T00:00:00.000Z',
            },
          },
        },
      });
      expect(extracted, ms);
    });

    test('reads flat deliveryOutcomes on assessmentDetails', () {
      final ms = DateTime.parse('2026-08-15T00:00:00Z').millisecondsSinceEpoch;
      final extracted = PregnancyDeliverySync.deliveryDateMillisFromMap({
        'assessmentDetails': {
          'deliveryOutcomes': {
            'dateOfDelivery': '2026-08-15T00:00:00.000Z',
          },
        },
      });
      expect(extracted, ms);
    });

    test('reads pregnancyInfos-style top-level dateOfDelivery', () {
      final ms = DateTime.parse('2026-07-20T00:00:00Z').millisecondsSinceEpoch;
      final extracted = PregnancyDeliverySync.deliveryDateMillisFromMap({
        'dateOfDelivery': '2026-07-20T00:00:00.000Z',
      });
      expect(extracted, ms);
    });
  });

  group('PregnancyDeliverySync.isPregnancyOutcomeType', () {
    test('accepts wire variants', () {
      expect(
        PregnancyDeliverySync.isPregnancyOutcomeType('PREGNANCYOUTCOME'),
        isTrue,
      );
      expect(
        PregnancyDeliverySync.isPregnancyOutcomeType('PREGNANCY_OUTCOME'),
        isTrue,
      );
      expect(PregnancyDeliverySync.isPregnancyOutcomeType('ANC'), isFalse);
    });
  });
}
