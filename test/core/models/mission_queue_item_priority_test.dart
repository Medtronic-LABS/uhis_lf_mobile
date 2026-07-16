import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/dashboard_tier.dart';
import 'package:uhis_next/core/models/mission_queue_item.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/core/models/risk.dart';

MissionQueueItem _item({
  required String name,
  required Band band,
  Modifier modifier = Modifier.none,
  bool pregnant = false,
  int daysOverdue = 0,
  DashboardTier tier = DashboardTier.upcoming,
}) {
  return MissionQueueItem(
    id: name,
    type: MissionItemType.patientVisit,
    priority: MissionPriority.medium,
    priorityScore: sortRankFor(band, modifier),
    patientName: name,
    patientId: name,
    programmes: pregnant ? {Programme.anc} : const <Programme>{},
    reason: 'test',
    daysOverdue: daysOverdue,
    aiInsight: '',
    band: band,
    modifier: modifier,
    isPregnant: pregnant,
    tier: tier,
  );
}

void main() {
  group('MissionQueueItem.compareByPriority — spec §2.8', () {
    test('orders 1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4', () {
      final items = [
        _item(name: '4', band: Band.band4),
        _item(name: '3', band: Band.band3),
        _item(name: '3b', band: Band.band3, modifier: Modifier.b, daysOverdue: 5),
        _item(name: '3a', band: Band.band3, modifier: Modifier.a),
        _item(name: '2', band: Band.band2),
        _item(name: '2b', band: Band.band2, modifier: Modifier.b, daysOverdue: 3),
        _item(name: '2a', band: Band.band2, modifier: Modifier.a),
        _item(name: '1', band: Band.band1),
        _item(name: '1b', band: Band.band1, modifier: Modifier.b, daysOverdue: 2),
        _item(name: '1a', band: Band.band1, modifier: Modifier.a),
      ]..sort(MissionQueueItem.compareByPriority);

      expect(
        items.map((e) => e.patientName).toList(),
        ['1a', '1b', '1', '2a', '2b', '2', '3a', '3b', '3', '4'],
      );
    });

    test('pregnant ranks above non-pregnant within same band+modifier', () {
      final items = [
        _item(name: 'np', band: Band.band2, modifier: Modifier.a),
        _item(name: 'preg', band: Band.band2, modifier: Modifier.a, pregnant: true),
      ]..sort(MissionQueueItem.compareByPriority);

      expect(items.first.patientName, 'preg');
    });

    test('longer overdue ranks higher within same band+mod+preg', () {
      final items = [
        _item(
          name: 'near',
          band: Band.band2,
          modifier: Modifier.b,
          daysOverdue: 2,
        ),
        _item(
          name: 'late',
          band: Band.band2,
          modifier: Modifier.b,
          daysOverdue: 20,
        ),
      ]..sort(MissionQueueItem.compareByPriority);

      expect(items.first.patientName, 'late');
    });

    test('hot date-tier does not lift a milder band above a worse band', () {
      // Band 4 "critical" must stay after Band 2 "upcoming".
      final items = [
        _item(
          name: 'mild-critical',
          band: Band.band4,
          tier: DashboardTier.critical,
        ),
        _item(
          name: 'worse-upcoming',
          band: Band.band2,
          tier: DashboardTier.upcoming,
        ),
      ]..sort(MissionQueueItem.compareByPriority);

      expect(items.first.patientName, 'worse-upcoming');
      expect(items.last.patientName, 'mild-critical');
    });
  });
}
