import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:leapwell/core/api/api_client.dart';
import 'package:leapwell/core/clinical/briefing_rules/briefing_findings_aggregator.dart';
import 'package:leapwell/core/db/app_database.dart';
import 'package:leapwell/core/db/assessment_dao.dart';
import 'package:leapwell/core/db/immunisation_dao.dart';
import 'package:leapwell/core/db/local_assessment_dao.dart';
import 'package:leapwell/core/db/patient_dao.dart';
import 'package:leapwell/core/models/programme.dart';
import 'package:leapwell/features/patient/followup_repository.dart';
import 'package:leapwell/features/patient/member_detail_repository.dart';
import 'package:leapwell/features/visit/triage/patient_context_builder.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDatabase> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    return AppDatabase.forTesting(db);
  }

  Future<void> insertAssessment(
    AppDatabase app, {
    required String patientId,
    required String assessmentType,
    required Map<String, dynamic> details,
    required int createdAt,
  }) async {
    await app.db.insert('local_assessments', {
      'id': '$patientId-$assessmentType-$createdAt',
      'household_member_local_id': 1,
      'patient_id': patientId,
      'assessment_type': assessmentType,
      'assessment_details': jsonEncode(details),
      'created_at': createdAt,
    });
  }

  /// Inserts a row into the server-synced `assessments` table (as
  /// `offline_sync_service.dart` would after fetching assessment history) —
  /// a flat `observations`-shaped payload, not the nested local_assessments
  /// shape.
  Future<void> insertHistoryAssessment(
    AppDatabase app, {
    required String patientId,
    required String kind,
    required Map<String, dynamic> observations,
    required int occurredAt,
  }) async {
    await AssessmentDao(app).upsertMany([
      AssessmentRow(
        id: '$patientId-history-$kind-$occurredAt',
        patientId: patientId,
        kind: kind,
        occurredAt: occurredAt,
        rawJson: jsonEncode({'observations': observations}),
      ),
    ]);
  }

  PatientContext patientCtx({
    bool isPregnant = false,
    int ageMonths = 300,
    int? deliveryDateMillis,
    Set<Programme> activeProgrammes = const {},
  }) =>
      PatientContext(
        patientId: 'p1',
        ageMonths: ageMonths,
        sex: Sex.female,
        isPregnant: isPregnant,
        deliveryDateMillis: deliveryDateMillis,
        activeProgrammes: activeProgrammes,
      );

  group('BriefingFindingsAggregator.build — dispatch gating', () {
    test('ANC row exists but only NCD is selected → ANC findings absent, NCD present', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      await insertAssessment(db,
          patientId: 'p1',
          assessmentType: 'ANC',
          details: {
            'dangerSignsRiskIdentification': {
              'dangerSignsExperienced12': ['Vaginal bleeding'],
            },
          },
          createdAt: 1000);
      await insertAssessment(db,
          patientId: 'p1',
          assessmentType: 'NCD',
          details: {
            'bpLog': {'avgSystolic': 150, 'avgDiastolic': 95},
          },
          createdAt: 1000);

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.ncd}),
        selectedProgrammes: {Programme.ncd},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      expect(findings.any((f) => f.programme == 'anc'), isFalse);
      expect(findings.any((f) => f.programme == 'ncd'), isTrue);
    });

    test('stale PREGNANCY_OUTCOME row but not postpartum → no pregnancyOutcome findings', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      await insertAssessment(db,
          patientId: 'p1',
          assessmentType: 'PREGNANCY_OUTCOME',
          details: {
            'deliveryOutcomes': {
              'deliveryOutcome': 'liveBirth',
              'anyComplicationsDuringDelivery': 'No',
            },
            'newbornDetails': [
              {'isBabyAlive': true},
            ],
          },
          createdAt: 1000);

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        // isPostpartum requires deliveryDateMillis within 42 days — omitted here.
        patientCtx: patientCtx(),
        selectedProgrammes: const {},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      expect(findings.any((f) => f.programme == 'pregnancyOutcome'), isFalse);
    });

    test('recent postpartum delivery + PREGNANCY_OUTCOME row → findings surfaced', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      await insertAssessment(db,
          patientId: 'p1',
          assessmentType: 'PREGNANCY_OUTCOME',
          details: {
            'deliveryOutcomes': {
              'deliveryOutcome': 'liveBirth',
              'anyComplicationsDuringDelivery': 'No',
            },
            'newbornDetails': [
              {'isBabyAlive': true},
            ],
          },
          createdAt: 1000);

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(
          deliveryDateMillis:
              DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        ),
        selectedProgrammes: const {},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      expect(
        findings.any((f) =>
            f.programme == 'pregnancyOutcome' && f.code == 'pregnancyOutcome.healthy'),
        isTrue,
      );
    });

    test('no ANC/PNC/NCD/child selection and no postpartum → empty result', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(ageMonths: 300),
        selectedProgrammes: const {},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      expect(findings, isEmpty);
    });
  });

  group('BriefingFindingsAggregator.build — history fallback', () {
    test('no local ANC row, but synced history has BP → history-derived finding fires', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      await insertHistoryAssessment(db,
          patientId: 'p1',
          kind: 'ANC',
          observations: {'systolic': 150, 'diastolic': 95},
          occurredAt: 1000);

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.anc}),
        selectedProgrammes: {Programme.anc},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      expect(findings.map((f) => f.code), contains('anc.highBp'));
    });

    test('local ANC row exists → history is never consulted, even if present', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      // Local row: normal BP, no concerns.
      await insertAssessment(db,
          patientId: 'p1',
          assessmentType: 'ANC',
          details: {
            'medicalHistoryPhysicalExamination': {'systolic': 110, 'diastolic': 70},
          },
          createdAt: 2000);
      // History row: high BP — must NOT be used since local data exists.
      await insertHistoryAssessment(db,
          patientId: 'p1',
          kind: 'ANC',
          observations: {'systolic': 160, 'diastolic': 100},
          occurredAt: 1000);

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.anc}),
        selectedProgrammes: {Programme.anc},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      expect(findings.map((f) => f.code), isNot(contains('anc.highBp')));
      expect(findings.map((f) => f.code), contains('anc.routine'));
    });

    test('no local NCD row, synced history has fasting glucose → history-derived finding fires', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      await insertHistoryAssessment(db,
          patientId: 'p1',
          kind: 'NCD',
          observations: {'bg': 9.0},
          occurredAt: 1000);

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.ncd}),
        selectedProgrammes: {Programme.ncd},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      expect(findings.map((f) => f.code), contains('ncd.glucoseAlone'));
    });

    test('no local PNC row, synced history has severe-anaemia Hb → history-derived finding fires', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      await insertHistoryAssessment(db,
          patientId: 'p1',
          kind: 'PNC_MOTHER',
          observations: {'hemoglobin': 6.5},
          occurredAt: 1000);

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.pnc}),
        selectedProgrammes: {Programme.pnc},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      expect(findings.map((f) => f.code), contains('pnc.severeAnaemia'));
    });

    test('no local and no history data at all → still falls through to routine fallback', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.anc}),
        selectedProgrammes: {Programme.anc},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      );

      // No local, no history → latest stays null → evaluateAncFindings
      // returns const [] (no visit at all yet), not a fabricated routine msg.
      expect(findings, isEmpty);
    });
  });

  group('BriefingFindingsAggregator.build — remoteAssessments fallback (never-synced patient)', () {
    test('no local ANC row, no history, but remoteAssessments has BP → remote-derived finding fires', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.anc}),
        selectedProgrammes: {Programme.anc},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
        remoteAssessments: [
          MemberAssessment(
            id: 'remote-1',
            type: 'ANC',
            date: DateTime.now(),
            rawJson: const {
              'observations': {'systolic': 150, 'diastolic': 95},
            },
          ),
        ],
      );

      expect(findings.map((f) => f.code), contains('anc.highBp'));
    });

    test('history row exists → remoteAssessments never consulted, even if present', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      // History row: normal BP, no concerns.
      await insertHistoryAssessment(db,
          patientId: 'p1',
          kind: 'ANC',
          observations: {'systolic': 110, 'diastolic': 70},
          occurredAt: 1000);

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.anc}),
        selectedProgrammes: {Programme.anc},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
        // Remote row: high BP — must NOT be used since history data exists.
        remoteAssessments: [
          MemberAssessment(
            id: 'remote-1',
            type: 'ANC',
            date: DateTime.now(),
            rawJson: const {
              'observations': {'systolic': 160, 'diastolic': 100},
            },
          ),
        ],
      );

      expect(findings.map((f) => f.code), isNot(contains('anc.highBp')));
      expect(findings.map((f) => f.code), contains('anc.routine'));
    });

    test('no local, no history, remoteAssessments has severe-anaemia PNC Hb → remote-derived finding fires', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final assessmentDao = LocalAssessmentDao(db);
      final patientDao = PatientDao(db);
      final immunisationDao = ImmunisationDao(db);
      final followUpRepo = FollowUpRepository(await ApiClient.create());

      final findings = await BriefingFindingsAggregator.build(
        patientId: 'p1',
        patientCtx: patientCtx(activeProgrammes: {Programme.pnc}),
        selectedProgrammes: {Programme.pnc},
        assessmentDao: assessmentDao,
        historyAssessmentDao: AssessmentDao(db),
        followUpRepo: followUpRepo,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
        remoteAssessments: [
          MemberAssessment(
            id: 'remote-1',
            type: 'PNC',
            date: DateTime.now(),
            rawJson: const {
              'observations': {'hemoglobin': 6.5},
            },
          ),
        ],
      );

      expect(findings.map((f) => f.code), contains('pnc.severeAnaemia'));
    });
  });
}
