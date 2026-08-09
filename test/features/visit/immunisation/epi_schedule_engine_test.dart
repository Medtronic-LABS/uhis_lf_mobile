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
    // At Birth is BCG-only on the national schedule — once BCG is Missed
    // there is no remaining dueNow vaccine in that milestone.
    expect(atBirth.hasDueNow, isFalse);
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
    // Next due doses are the 6-week set (OPV0/HepB0 are not on the national table).
    expect(codes, contains('OPV1'));
    expect(codes, isNot(contains('OPV0')));
  });

  test('referralFacility threads through from ImmunisationRow', () async {
    final milestones = await EpiScheduleEngine.build(
      dob: dob,
      rows: [
        const ImmunisationRow(
          id: 'p1_BCG',
          patientId: 'p1',
          vaccineCode: 'BCG',
          status: 'Missed',
          missedReason: 'Child was sick on scheduled date',
          referralFacility: 'Upazila Health Complex',
          rawJson: '{}',
        ),
      ],
      today: today,
    );

    final atBirth = milestones.firstWhere((m) => m.label == 'At Birth');
    final bcg = atBirth.vaccines.firstWhere((v) => v.code == 'BCG');
    expect(bcg.referralFacility, 'Upazila Health Complex');
  });

  group('applySequencing', () {
    test(
        'only the earliest unresolved due-now milestone is enabled; later '
        'ones are visible (still hasDueNow) but disabled', () async {
      final milestones = EpiScheduleEngine.applySequencing(
        await EpiScheduleEngine.build(dob: dob, rows: const [], today: today),
      );

      final atBirth = milestones.firstWhere((m) => m.label == 'At Birth');
      final sixWeeks = milestones.firstWhere((m) => m.label == '6 Weeks');

      expect(atBirth.hasDueNow, isTrue);
      expect(atBirth.actionEnabled, isTrue);
      expect(sixWeeks.hasDueNow, isTrue,
          reason: 'still independently due — button must stay visible');
      expect(sixWeeks.actionEnabled, isFalse,
          reason: "not this milestone's turn yet");
    });

    test('referring the earlier milestone unlocks the next one', () async {
      final rows = [
        const ImmunisationRow(
          id: 'p1_BCG',
          patientId: 'p1',
          vaccineCode: 'BCG',
          status: 'Missed',
          missedReason: 'Referred',
          rawJson: '{}',
        ),
        const ImmunisationRow(
          id: 'p1_OPV0',
          patientId: 'p1',
          vaccineCode: 'OPV0',
          status: 'Missed',
          missedReason: 'Referred',
          rawJson: '{}',
        ),
        const ImmunisationRow(
          id: 'p1_HepB0',
          patientId: 'p1',
          vaccineCode: 'HepB0',
          status: 'Missed',
          missedReason: 'Referred',
          rawJson: '{}',
        ),
      ];
      final milestones = EpiScheduleEngine.applySequencing(
        await EpiScheduleEngine.build(dob: dob, rows: rows, today: today),
      );

      final atBirth = milestones.firstWhere((m) => m.label == 'At Birth');
      final sixWeeks = milestones.firstWhere((m) => m.label == '6 Weeks');

      expect(atBirth.hasMissed, isTrue);
      expect(atBirth.actionEnabled, isTrue,
          reason: 'a referred milestone stays actionable (Mark as Complete)');
      expect(sixWeeks.actionEnabled, isTrue,
          reason: 'resolving At Birth (by referring) unlocks 6 Weeks');
    });

    test('a referred milestone is always actionEnabled regardless of order',
        () async {
      // Only "6 Weeks" is referred; "At Birth" is still unresolved dueNow.
      // Self-healing: 6 Weeks stays actionable, At Birth still gates
      // anything further, but does not retroactively disable 6 Weeks.
      final rows = [
        const ImmunisationRow(
          id: 'p1_OPV1',
          patientId: 'p1',
          vaccineCode: 'OPV1',
          status: 'Missed',
          missedReason: 'Referred',
          rawJson: '{}',
        ),
      ];
      final built = await EpiScheduleEngine.build(dob: dob, rows: rows, today: today);
      final sixWeeksBuilt = built.firstWhere((m) => m.label == '6 Weeks');
      // Sanity: OPV1 is a 6 Weeks vaccine per the schedule asset.
      expect(sixWeeksBuilt.vaccines.any((v) => v.code == 'OPV1'), isTrue);

      final milestones = EpiScheduleEngine.applySequencing(built);
      final sixWeeks = milestones.firstWhere((m) => m.label == '6 Weeks');
      expect(sixWeeks.hasMissed, isTrue);
      expect(sixWeeks.actionEnabled, isTrue);
    });
  });

  group('outcomesFromRawJsonList', () {
    test(
        'recovers vaccinations from the real member-assessment-history shape '
        '(top-level immunization + referralFacilityType/referralReason) — '
        'captured live from spice-dev-backend, this is the regression test '
        'for the read-side bug where the app parsed only guessed shapes and '
        'silently found nothing', () {
      final outcomes = EpiScheduleEngine.outcomesFromRawJsonList([
        {
          'householdMemberId': 820536,
          'observations': null,
          'visitDate': '2026-07-31T09:04:44+00:00',
          'serviceProvided': 'CHILD_IMMUNIZATION',
          'referralStatus': 'Referred',
          'referralReason': 'Health & Family Welfare Center',
          'referralFacilityType': 'hwc',
          'encounterId': 840604,
          'customStatus': ['Referred'],
          'immunization': [
            {
              'vaccineName': 'Polio-(OPV 2)',
              'vaccinatedDate': null,
              'status': 'Missed',
              'reason': 'vvv',
            },
            {
              'vaccineName': 'Penta-2',
              'vaccinatedDate': null,
              'status': 'Missed',
              'reason': 'vvv',
            },
          ],
          'latestVisit': true,
        },
      ]);

      expect(outcomes, hasLength(2));
      final opv2 = outcomes.firstWhere((o) => o.vaccineName == 'Polio-(OPV 2)');
      expect(opv2.status, 'Missed');
      expect(opv2.reason, 'vvv');
      expect(opv2.facility, 'Health & Family Welfare Center',
          reason: 'resolved via the referralFacilityType id → label lookup');
      expect(opv2.givenAtMs, isNull);
    });

    test('recovers vaccinations from the observations.vaccinations shape',
        () {
      final outcomes = EpiScheduleEngine.outcomesFromRawJsonList([
        {
          'observations': {
            'vaccinations': [
              {'vaccineName': 'BCG', 'status': 'Vaccinated', 'vaccinatedDate': '2020-01-15T00:00:00+00:00'},
            ],
          },
        },
      ]);
      expect(outcomes, hasLength(1));
      expect(outcomes.single.vaccineName, 'BCG');
      expect(outcomes.single.status, 'Vaccinated');
      expect(outcomes.single.givenAtMs, isNotNull);
    });

    test(
        'recovers vaccinations from the assessmentDetails.childImmunization shape',
        () {
      final outcomes = EpiScheduleEngine.outcomesFromRawJsonList([
        {
          'assessmentDetails': {
            'childImmunization': {
              'vaccinations': [
                {'vaccineName': 'OPV0', 'status': 'Missed', 'reason': 'Sick'},
              ],
            },
          },
        },
      ]);
      expect(outcomes, hasLength(1));
      expect(outcomes.single.vaccineName, 'OPV0');
      expect(outcomes.single.status, 'Missed');
      expect(outcomes.single.reason, 'Sick');
    });

    test('recovers vaccinations from the bare childImmunization shape', () {
      final outcomes = EpiScheduleEngine.outcomesFromRawJsonList([
        {
          'childImmunization': {
            'vaccinations': [
              {'vaccineName': 'HepB0', 'status': 'Vaccinated'},
            ],
          },
        },
      ]);
      expect(outcomes, hasLength(1));
      expect(outcomes.single.vaccineName, 'HepB0');
    });

    test('resolves the facility label from summary.referralFacilityType', () {
      final outcomes = EpiScheduleEngine.outcomesFromRawJsonList([
        {
          'summary': {'referralFacilityType': 'upazilaHealthComplex'},
          'observations': {
            'vaccinations': [
              {'vaccineName': 'BCG', 'status': 'Missed', 'reason': 'Sick'},
            ],
          },
        },
      ]);
      expect(outcomes.single.facility, 'Upazila Health Complex');
    });

    test('newest-first list: first occurrence per vaccine name wins', () {
      final outcomes = EpiScheduleEngine.outcomesFromRawJsonList([
        {
          'observations': {
            'vaccinations': [
              {'vaccineName': 'BCG', 'status': 'Vaccinated', 'vaccinatedDate': '2020-06-01T00:00:00+00:00'},
            ],
          },
        },
        {
          'observations': {
            'vaccinations': [
              {'vaccineName': 'BCG', 'status': 'Missed', 'reason': 'Sick'},
            ],
          },
        },
      ]);
      expect(outcomes, hasLength(1));
      expect(outcomes.single.status, 'Vaccinated',
          reason: 'the first (newest) row in the list wins');
    });

    test('returns cleanly, never throws, when no shape matches', () {
      final outcomes = EpiScheduleEngine.outcomesFromRawJsonList([
        {'someUnrelatedField': 'x'},
        <String, dynamic>{},
      ]);
      expect(outcomes, isEmpty);
    });
  });
}
