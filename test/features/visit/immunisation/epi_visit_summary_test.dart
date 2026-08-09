import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/immunisation/epi_schedule_engine.dart';
import 'package:uhis_next/features/visit/immunisation/epi_visit_summary.dart';

VaccineEntry _vaccine({
  required String code,
  required String display,
  required VaccineStatus status,
  required DateTime scheduledDate,
}) =>
    VaccineEntry(
      code: code,
      display: display,
      category: 'Routine',
      description: display,
      route: 'IM',
      cardGroup: 0,
      scheduledDate: scheduledDate,
      status: status,
    );

VaccineMilestone _milestone({
  required String label,
  String milestoneKey = '',
  required DateTime scheduledDate,
  required List<VaccineEntry> vaccines,
}) =>
    VaccineMilestone(
      label: label,
      milestoneKey: milestoneKey,
      scheduledDate: scheduledDate,
      vaccines: vaccines,
      offsetType: 'week',
      offsetValue: 0,
    );

void main() {
  test('all milestones completed → no overdue, no next milestone', () {
    final milestones = [
      _milestone(
        label: 'At Birth',
        scheduledDate: DateTime(2020, 1, 1),
        vaccines: [
          _vaccine(
            code: 'BCG',
            display: 'BCG',
            status: VaccineStatus.completed,
            scheduledDate: DateTime(2020, 1, 1),
          ),
        ],
      ),
    ];

    final summary = buildEpiVisitSummary(milestones);

    expect(summary.overdueCount, 0);
    expect(summary.overdueVaccineNames, isEmpty);
    expect(summary.currentMilestoneLabel, '');
    expect(summary.nextMilestoneLabel, isNull);
    expect(summary.nextMilestoneDate, isNull);
    expect(summary.nextMilestoneVaccineNames, isEmpty);
    expect(summary.referralWarranted, isFalse);
  });

  test('one due milestone + one upcoming → overdue names/count and next milestone fields', () {
    final nextDate = DateTime(2020, 4, 12);
    final milestones = [
      _milestone(
        label: '14 Weeks',
        milestoneKey: 'week14',
        scheduledDate: DateTime(2020, 1, 1),
        vaccines: [
          _vaccine(
            code: 'PENTA3',
            display: 'Pentavalent-3',
            status: VaccineStatus.dueNow,
            scheduledDate: DateTime(2020, 1, 1),
          ),
          _vaccine(
            code: 'OPV3',
            display: 'OPV-3',
            status: VaccineStatus.dueNow,
            scheduledDate: DateTime(2020, 1, 1),
          ),
        ],
      ),
      _milestone(
        label: '9 Months',
        milestoneKey: 'month9',
        scheduledDate: nextDate,
        vaccines: [
          _vaccine(
            code: 'MR1',
            display: 'MR Vaccine',
            status: VaccineStatus.upcoming,
            scheduledDate: nextDate,
          ),
        ],
      ),
    ];

    final summary = buildEpiVisitSummary(milestones);

    expect(summary.overdueCount, 2);
    expect(summary.overdueVaccineNames, ['Pentavalent-3', 'OPV-3']);
    expect(summary.overdueVaccineCodes, ['PENTA3', 'OPV3']);
    expect(summary.currentMilestoneLabel, '14 Weeks');
    expect(summary.currentMilestoneKey, 'week14');
    expect(summary.nextMilestoneLabel, '9 Months');
    expect(summary.nextMilestoneKey, 'month9');
    expect(summary.nextMilestoneDate, nextDate);
    expect(summary.nextMilestoneVaccineNames, ['MR Vaccine']);
    expect(summary.nextMilestoneVaccineCodes, ['MR1']);
    expect(summary.referralWarranted, isTrue);
  });

  test('two simultaneously-due milestones (catch-up) flatten overdue names, '
      'label picks the later milestone, next milestone skips both', () {
    final nextDate = DateTime(2020, 9, 1);
    final milestones = [
      _milestone(
        label: 'At Birth',
        scheduledDate: DateTime(2020, 1, 1),
        vaccines: [
          _vaccine(
            code: 'BCG',
            display: 'BCG',
            status: VaccineStatus.dueNow,
            scheduledDate: DateTime(2020, 1, 1),
          ),
        ],
      ),
      _milestone(
        label: '6 Weeks',
        scheduledDate: DateTime(2020, 2, 12),
        vaccines: [
          _vaccine(
            code: 'PENTA1',
            display: 'Pentavalent-1',
            status: VaccineStatus.dueNow,
            scheduledDate: DateTime(2020, 2, 12),
          ),
        ],
      ),
      _milestone(
        label: '9 Months',
        scheduledDate: nextDate,
        vaccines: [
          _vaccine(
            code: 'MR1',
            display: 'MR Vaccine',
            status: VaccineStatus.upcoming,
            scheduledDate: nextDate,
          ),
        ],
      ),
    ];

    final summary = buildEpiVisitSummary(milestones);

    expect(summary.overdueCount, 2);
    expect(summary.overdueVaccineNames, ['BCG', 'Pentavalent-1']);
    expect(summary.currentMilestoneLabel, '6 Weeks',
        reason: 'the chronologically-later due milestone drives the headline label');
    expect(summary.nextMilestoneLabel, '9 Months',
        reason: 'next milestone search must skip past both due milestones');
    expect(summary.nextMilestoneDate, nextDate);
    expect(summary.referralWarranted, isTrue);
  });
}
