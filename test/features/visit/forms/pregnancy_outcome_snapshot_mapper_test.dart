import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/db/pregnancy_snapshot_dao.dart';
import 'package:uhis_next/core/mission/mission_pregnancy_facts.dart';
import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/pregnancy_outcome_snapshot_mapper.dart';

void main() {
  group('PregnancyOutcomeSnapshotMapper', () {
    test('maps delivery date and postpartum facts onto snapshot row', () {
      final now = DateTime(2026, 9, 3);
      final delivery = DateTime(2026, 8, 20);
      final row = PregnancyOutcomeSnapshotMapper.fromPoData(
        patientId: 'p1',
        data: CanonicalVisitData({
          'dateOfDelivery': delivery.toIso8601String(),
          'placeOfDelivery': 'Home',
          'complicationsDuringDelivery': 'None',
        }),
        now: now,
      );

      expect(row.deliveryDateMillis, delivery.millisecondsSinceEpoch);
      expect(row.facts.isPostpartumWindow, isTrue);
      expect(row.facts.isNearTermAnc, isFalse);
      expect(row.facts.hadDeliveryComplications, isTrue,
          reason: 'home delivery mirrors sync pregnancyInfos flag');
    });

    test('preserves LMP and high-risk flags from existing episode', () {
      final now = DateTime(2026, 9, 3);
      final delivery = DateTime(2026, 8, 25);
      const existing = PregnancySnapshotRow(
        patientId: 'p1',
        facts: PregnancyFacts(
          highRiskPregnantWoman: true,
          hasGapsInAnc: true,
          isNearTermAnc: true,
        ),
        lmpDate: 1000,
        eddDate: 2000,
        ancVisitNo: 3,
        gravida: 2,
        parity: 1,
      );

      final row = PregnancyOutcomeSnapshotMapper.fromPoData(
        patientId: 'p1',
        data: CanonicalVisitData({
          'dateOfDelivery': delivery.toIso8601String(),
          'placeOfDelivery': 'Facility',
          'complicationsDuringDelivery': 'PPH',
        }),
        existing: existing,
        now: now,
      );

      expect(row.lmpDate, 1000);
      expect(row.eddDate, 2000);
      expect(row.ancVisitNo, 3);
      expect(row.gravida, 2);
      expect(row.parity, 1);
      expect(row.facts.highRiskPregnantWoman, isTrue);
      expect(row.facts.hasGapsInAnc, isTrue);
      expect(row.facts.isPostpartumWindow, isTrue);
      expect(row.facts.isNearTermAnc, isFalse);
      expect(row.facts.hadDeliveryComplications, isTrue);
      expect(row.facilityIdentifiedForDelivery, 'Facility');
    });
  });
}
