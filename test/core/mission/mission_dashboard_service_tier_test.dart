import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/mission/mission_dashboard_service.dart';
import 'package:uhis_next/core/mission/mission_pregnancy_facts.dart';
import 'package:uhis_next/core/models/dashboard_tier.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/core/models/risk.dart';
import 'package:uhis_next/core/models/worklist_entry.dart';

WorklistEntry _entry({
  required String patientId,
  String? name,
  int? age,
  DateTime? nextDueAt,
  Band band = Band.band4,
  Modifier modifier = Modifier.none,
  Set<Programme> programmes = const <Programme>{Programme.ncd},
}) =>
    WorklistEntry(
      patientId: patientId,
      displayName: name ?? 'Patient $patientId',
      age: age,
      band: band,
      modifier: modifier,
      programmes: programmes,
      nextDueAt: nextDueAt,
    );

void main() {
  const service = MissionDashboardService();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  group('MissionDashboardService.computeTieredQueue', () {
    test('neonate → CRITICAL with neonate driver', () {
      final input = MissionInputData(
        worklistEntries: [_entry(patientId: 'p1', age: 0)],
        neonatePatientIds: const {'p1'},
      );
      final queue = service.computeTieredQueue(input);
      expect(queue, hasLength(1));
      expect(queue.first.tier, DashboardTier.critical);
      expect(queue.first.drivers, contains('neonate'));
    });

    test('high-risk pregnancy + ANC gap → CRITICAL with hi-risk-anc-gap', () {
      final input = MissionInputData(
        worklistEntries: [_entry(patientId: 'p2')],
        pregnancyByPatientId: const {
          'p2': PregnancyFacts(
            highRiskPregnantWoman: true,
            hasGapsInAnc: true,
          ),
        },
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.first.tier, DashboardTier.critical);
      expect(queue.first.drivers, contains('hi-risk-anc-gap'));
    });

    test('postpartum window → CRITICAL with pnc-window', () {
      final input = MissionInputData(
        worklistEntries: [_entry(patientId: 'p3')],
        pregnancyByPatientId: const {
          'p3': PregnancyFacts(isPostpartumWindow: true),
        },
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.first.tier, DashboardTier.critical);
      expect(queue.first.drivers, contains('pnc-window'));
    });

    test('LTFU streak + due today → OVERDUE (promoted from dueToday)', () {
      final input = MissionInputData(
        worklistEntries: [
          _entry(patientId: 'p4', nextDueAt: today),
        ],
        unsuccessfulAttemptsByPatientId: const {'p4': 4},
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.first.tier, DashboardTier.overdue);
      expect(queue.first.drivers, contains('ltfu-streak'));
    });

    test('routine adult with due in 4 days → THIS WEEK', () {
      final input = MissionInputData(
        worklistEntries: [
          _entry(
            patientId: 'p5',
            age: 35,
            nextDueAt: today.add(const Duration(days: 4)),
          ),
        ],
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.first.tier, DashboardTier.thisWeek);
      expect(queue.first.drivers, isEmpty);
    });

    test('no due date and no drivers → UPCOMING', () {
      final input = MissionInputData(
        worklistEntries: [_entry(patientId: 'p6', age: 35)],
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.first.tier, DashboardTier.upcoming);
      expect(queue.first.drivers, isEmpty);
    });

    test('3+ days past due → OVERDUE; 1–2 days past → DUE TODAY', () {
      final overdue = _entry(
        patientId: 'late',
        nextDueAt: today.subtract(const Duration(days: 4)),
      );
      final dueToday = _entry(
        patientId: 'near',
        nextDueAt: today.subtract(const Duration(days: 1)),
      );
      final input = MissionInputData(
        worklistEntries: [overdue, dueToday],
      );
      final queue = service.computeTieredQueue(input);
      final byId = {for (final q in queue) q.patientId: q};
      expect(byId['late']!.tier, DashboardTier.overdue);
      expect(byId['near']!.tier, DashboardTier.dueToday);
    });

    test('hidden patient (inactive/deceased) → dropped from queue', () {
      final input = MissionInputData(
        worklistEntries: [
          _entry(patientId: 'hide-me', nextDueAt: today),
          _entry(patientId: 'keep-me', nextDueAt: today),
        ],
        hiddenPatientIds: const {'hide-me'},
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.map((q) => q.patientId), unorderedEquals(['keep-me']));
    });

    test(
      'stable tiebreak: same tier/band/modifier falls back to alphabetical name',
      () {
        final first = _entry(
          patientId: 'p-hi',
          age: 35,
          nextDueAt: today.add(const Duration(days: 3)),
        );
        final second = _entry(
          patientId: 'p-lo',
          age: 35,
          nextDueAt: today.add(const Duration(days: 3)),
        );
        final input = MissionInputData(
          worklistEntries: [second, first],
          unsuccessfulAttemptsByPatientId: const {'p-hi': 2, 'p-lo': 0},
        );
        final queue = service.computeTieredQueue(input);
        // 'p-hi' < 'p-lo' alphabetically — name is the final stable sort key
        expect(queue.first.patientId, 'p-hi');
        expect(queue[1].patientId, 'p-lo');
        expect(queue.first.tier, DashboardTier.thisWeek);
      },
    );

    test(
      'modifier b: longer overdue ranks higher within same band (spec §2.8 step 4)',
      () {
        final moreOverdue = _entry(
          patientId: 'late',
          modifier: Modifier.b,
          nextDueAt: today.subtract(const Duration(days: 7)),
        );
        final lessOverdue = _entry(
          patientId: 'near',
          modifier: Modifier.b,
          nextDueAt: today.subtract(const Duration(days: 2)),
        );
        final input = MissionInputData(
          worklistEntries: [lessOverdue, moreOverdue],
        );
        final queue = service.computeTieredQueue(input);
        expect(queue.first.patientId, 'late');
        expect(queue[1].patientId, 'near');
      },
    );

    test(
      'modifier order: a before b before none within same band',
      () {
        final modNone = _entry(patientId: 'none', modifier: Modifier.none);
        final modB = _entry(patientId: 'modB', modifier: Modifier.b);
        final modA = _entry(patientId: 'modA', modifier: Modifier.a);
        final input = MissionInputData(
          worklistEntries: [modNone, modB, modA],
        );
        final queue = service.computeTieredQueue(input);
        expect(queue.map((q) => q.patientId).toList(), ['modA', 'modB', 'none']);
      },
    );

    test(
      'pregnant ranks above non-pregnant within same band and modifier (spec §2.8 step 3)',
      () {
        final pregnant = _entry(
          patientId: 'preg',
          programmes: const {Programme.anc},
        );
        final notPregnant = _entry(patientId: 'npreg');
        final input = MissionInputData(
          worklistEntries: [notPregnant, pregnant],
        );
        final queue = service.computeTieredQueue(input);
        expect(queue.first.patientId, 'preg');
      },
    );

    test('band1 risk band → CRITICAL', () {
      final input = MissionInputData(
        worklistEntries: [
          _entry(patientId: 'r1', band: Band.band1),
        ],
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.first.tier, DashboardTier.critical);
      expect(queue.first.drivers, contains('red-flag'));
    });

    test('child < 5 with disability → OVERDUE (min)', () {
      final input = MissionInputData(
        worklistEntries: [
          _entry(patientId: 'c1', age: 3, nextDueAt: today.add(const Duration(days: 5))),
        ],
        disabilityByPatientId: const {'c1': true},
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.first.tier, DashboardTier.overdue);
      expect(queue.first.drivers, contains('child-disability'));
    });

    // PRD §2.8: sort is by band (not by scheduling tier). Tier labels are
    // derived from _classify() for display only — they do not affect sort.
    test('queue sorted by band rank — Band 1 before Band 4, tier is display-only', () {
      final input = MissionInputData(
        worklistEntries: [
          _entry(patientId: 'b4', band: Band.band4),
          _entry(patientId: 'b2', band: Band.band2),
          _entry(patientId: 'b1', band: Band.band1),
          _entry(patientId: 'b3', band: Band.band3),
        ],
      );
      final queue = service.computeTieredQueue(input);
      expect(queue.map((q) => q.band).toList(), [
        Band.band1,
        Band.band2,
        Band.band3,
        Band.band4,
      ]);
      // Band 1 → CRITICAL tier (red-flag driver fires for band1 patients)
      expect(queue[0].tier, DashboardTier.critical);
    });
  });

  group('DashboardTier.fromDaysToDue', () {
    test('boundary cases', () {
      expect(DashboardTier.fromDaysToDue(null), DashboardTier.upcoming);
      expect(DashboardTier.fromDaysToDue(-3), DashboardTier.overdue);
      expect(DashboardTier.fromDaysToDue(-2), DashboardTier.dueToday);
      expect(DashboardTier.fromDaysToDue(0), DashboardTier.dueToday);
      expect(DashboardTier.fromDaysToDue(1), DashboardTier.thisWeek);
      expect(DashboardTier.fromDaysToDue(7), DashboardTier.thisWeek);
      expect(DashboardTier.fromDaysToDue(8), DashboardTier.upcoming);
    });
  });
}
