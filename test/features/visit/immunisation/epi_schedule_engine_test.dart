import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/immunisation_dao.dart';
import 'package:uhis_next/features/visit/immunisation/epi_schedule_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Far enough after dob that both "At Birth" (day 0) and "6 Weeks" (day 42)
  // are overdue relative to `today`.
  final dob = DateTime(2020, 1, 1);
  final today = DateTime(2020, 3, 1);

  test(
      'two simultaneously-overdue milestones both resolve dueNow independently',
      () async {
    final milestones = await EpiScheduleEngine.build(
      dob: dob,
      rows: const [],
      today: today,
    );

    final atBirth = milestones.firstWhere((m) => m.label == 'At Birth');
    final sixWeeks = milestones.firstWhere((m) => m.label == '6 Weeks');

    expect(atBirth.hasDueNow, isTrue);
    expect(sixWeeks.hasDueNow, isTrue,
        reason: '6 Weeks must be independently actionable even though At '
            'Birth is also overdue and unrecorded — this is the regression '
            'this fix targets.');
  });

  test('a vaccine recorded Missed resolves to missed, not dueNow', () async {
    final milestones = await EpiScheduleEngine.build(
      dob: dob,
      rows: [
        const ImmunisationRow(
          id: 'p1_BCG',
          patientId: 'p1',
          vaccineCode: 'BCG',
          status: 'Missed',
          missedReason: 'Child was sick on scheduled date',
          rawJson: '{}',
        ),
      ],
      today: today,
    );

    final atBirth = milestones.firstWhere((m) => m.label == 'At Birth');
    final bcg = atBirth.vaccines.firstWhere((v) => v.code == 'BCG');

    expect(bcg.status, VaccineStatus.missed);
    expect(bcg.missedReason, 'Child was sick on scheduled date');
    expect(atBirth.hasMissed, isTrue);
    // The other two "At Birth" vaccines (OPV0, HepB0) are still unrecorded
    // and independently overdue, so the milestone-level hasDueNow stays true
    // — only BCG itself should read as missed, not the whole milestone.
    expect(atBirth.hasDueNow, isTrue);
  });

  test('a given vaccine always resolves completed regardless of status',
      () async {
    final milestones = await EpiScheduleEngine.build(
      dob: dob,
      rows: [
        ImmunisationRow(
          id: 'p1_BCG',
          patientId: 'p1',
          vaccineCode: 'BCG',
          givenAt: today.millisecondsSinceEpoch,
          status: 'Missed', // stale/contradictory status — given wins
          rawJson: '{}',
        ),
      ],
      today: today,
    );

    final atBirth = milestones.firstWhere((m) => m.label == 'At Birth');
    final bcg = atBirth.vaccines.firstWhere((v) => v.code == 'BCG');

    expect(bcg.status, VaccineStatus.completed);
  });

  test('overdueCodesFor includes dueNow and excludes missed', () async {
    final codes = await EpiScheduleEngine.overdueCodesFor(
      dob: dob,
      rows: [
        const ImmunisationRow(
          id: 'p1_BCG',
          patientId: 'p1',
          vaccineCode: 'BCG',
          status: 'Missed',
          rawJson: '{}',
        ),
      ],
      today: today,
    );

    expect(codes, isNot(contains('BCG')));
    expect(codes, contains('OPV0')); // still dueNow, unrecorded
  });
}
