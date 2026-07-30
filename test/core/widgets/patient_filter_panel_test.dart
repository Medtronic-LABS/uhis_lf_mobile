import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/dashboard_tier.dart';
import 'package:uhis_next/core/models/mission_queue_item.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/core/models/risk.dart';
import 'package:uhis_next/core/widgets/patient_filter_panel.dart';

MissionQueueItem _item({
  required String name,
  Set<Programme> programmes = const {},
  DashboardTier tier = DashboardTier.dueToday,
  Band band = Band.band4,
}) {
  return MissionQueueItem(
    id: name,
    type: MissionItemType.patientVisit,
    priority: MissionPriority.medium,
    priorityScore: sortRankFor(band, Modifier.none),
    patientName: name,
    patientId: name,
    programmes: programmes,
    reason: 'test',
    daysOverdue: 0,
    aiInsight: '',
    band: band,
    modifier: Modifier.none,
    isPregnant: programmes.contains(Programme.anc) ||
        programmes.contains(Programme.pw),
    tier: tier,
  );
}

void main() {
  group('NeedFilter.ancMnch', () {
    test('matches ANC, PNC, and PW enrolments', () {
      expect(
        NeedFilter.ancMnch.matches(_item(name: 'a', programmes: {Programme.anc})),
        isTrue,
      );
      expect(
        NeedFilter.ancMnch.matches(_item(name: 'p', programmes: {Programme.pnc})),
        isTrue,
      );
      expect(
        NeedFilter.ancMnch.matches(_item(name: 'pw', programmes: {Programme.pw})),
        isTrue,
      );
      expect(
        NeedFilter.ancMnch.matches(
          _item(name: 'ncd', programmes: {Programme.ncd}),
        ),
        isFalse,
      );
    });

    test('computeAvailableNeeds includes ancMnch for PW-only cohort', () {
      final available = computeAvailableNeeds([
        _item(name: 'pw', programmes: {Programme.pw}),
      ]);
      expect(available, contains(NeedFilter.ancMnch));
    });
  });

  group('filterMissionQueue', () {
    final ancToday = _item(
      name: 'Yasmeen',
      programmes: {Programme.anc, Programme.pw},
      tier: DashboardTier.dueToday,
      band: Band.band2,
    );
    final pwUpcoming = _item(
      name: 'PwOnly',
      programmes: {Programme.pw},
      tier: DashboardTier.upcoming,
    );
    final ncdToday = _item(
      name: 'Jakir',
      programmes: {Programme.ncd},
      tier: DashboardTier.dueToday,
    );

    test('unfiltered drops upcoming', () {
      final result = filterMissionQueue(
        queue: [ancToday, pwUpcoming, ncdToday],
      );
      expect(result.map((e) => e.patientName), ['Yasmeen', 'Jakir']);
    });

    test('ANC/MNCH keeps PW upcoming and drops NCD', () {
      final result = filterMissionQueue(
        queue: [ancToday, pwUpcoming, ncdToday],
        selectedNeeds: {NeedFilter.ancMnch},
      );
      expect(result.map((e) => e.patientName).toSet(), {'Yasmeen', 'PwOnly'});
    });

    test('ANC/MNCH stacks completed-today after open visits', () {
      final doneYasmeen = _item(
        name: 'Yasmeen',
        programmes: {Programme.anc, Programme.pw},
        band: Band.band2,
      );
      final nonew = _item(
        name: 'nonew',
        programmes: {Programme.anc, Programme.pw},
        band: Band.band2,
      );
      final prachi = _item(
        name: 'Prachi',
        programmes: {Programme.anc, Programme.pw},
        band: Band.band4,
      );
      // Input already priority-ordered; Yasmeen is done and must sink.
      final result = filterMissionQueue(
        queue: [doneYasmeen, nonew, prachi],
        selectedNeeds: {NeedFilter.ancMnch},
        completedPatientIds: {'Yasmeen'},
      );
      expect(result.map((e) => e.patientName), [
        'nonew',
        'Prachi',
        'Yasmeen',
      ]);
    });

    test('unfiltered hides completed-today', () {
      final doneYasmeen = _item(
        name: 'Yasmeen',
        programmes: {Programme.anc, Programme.pw},
        band: Band.band2,
      );
      final result = filterMissionQueue(
        queue: [doneYasmeen, ncdToday],
        completedPatientIds: {'Yasmeen'},
      );
      expect(result.map((e) => e.patientName), ['Jakir']);
    });

    test('This week need keeps completed due-in-1–7 in list', () {
      final doneYasmeen = _item(
        name: 'Yasmeen',
        programmes: {Programme.anc, Programme.pw},
        band: Band.band2,
      ).copyWith(dueAt: DateTime.now().add(const Duration(days: 1)));
      final openPushp = _item(
        name: 'Pushp',
        programmes: {Programme.anc, Programme.pw},
        band: Band.band4,
      ).copyWith(dueAt: DateTime.now().add(const Duration(days: 3)));
      final prachiUpcoming = _item(
        name: 'Prachi',
        programmes: {Programme.anc, Programme.pw},
        band: Band.band4,
        tier: DashboardTier.upcoming,
      ).copyWith(dueAt: DateTime.now().add(const Duration(days: 20)));

      expect(NeedFilter.thisWeek.matches(doneYasmeen), isTrue);
      expect(NeedFilter.thisWeek.matches(openPushp), isTrue);
      expect(NeedFilter.thisWeek.matches(prachiUpcoming), isFalse);

      final result = filterMissionQueue(
        queue: [doneYasmeen, openPushp, prachiUpcoming],
        selectedNeeds: {NeedFilter.thisWeek},
        completedPatientIds: {'Yasmeen'},
      );
      expect(result.map((e) => e.patientName), ['Pushp', 'Yasmeen']);
    });

    test('NCD keeps only NCD and still drops unrelated upcoming', () {
      final result = filterMissionQueue(
        queue: [ancToday, pwUpcoming, ncdToday],
        selectedNeeds: {NeedFilter.ncd},
      );
      expect(result.map((e) => e.patientName), ['Jakir']);
    });
  });
}

