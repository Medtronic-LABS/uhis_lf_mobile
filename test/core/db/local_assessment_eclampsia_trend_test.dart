import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, LocalAssessmentDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, LocalAssessmentDao(app));
  }

  Future<void> insertAnc(
    AppDatabase app, {
    required String patientId,
    required int createdAt,
    int? systolic,
    double? weight,
    String? urineProtein,
    bool eclampsia = false,
  }) async {
    final details = <String, dynamic>{
      'medicalHistoryPhysicalExamination': {
        if (systolic != null) 'systolic': systolic,
        if (weight != null) 'weight': weight,
      },
      'pointOfCareInvestigations': {
        if (urineProtein != null) 'urineProtein': urineProtein,
      },
      if (eclampsia) 'eclampsia': true,
    };
    await app.db.insert('local_assessments', {
      'id': '$patientId-anc-$createdAt',
      'household_member_local_id': 1,
      'patient_id': patientId,
      'assessment_type': 'ANC',
      'assessment_details': jsonEncode(details),
      'created_at': createdAt,
    });
  }

  group('latestClinicalVitalsForMany — eclampsia trend (G8, PRD §2.8.1 Band 2)', () {
    test('3-visit rising BP + rising weight + latest urine protein → hasEclampsia', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await insertAnc(db, patientId: 'p1', createdAt: 1000,
          systolic: 130, weight: 60.0, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p1', createdAt: 2000,
          systolic: 138, weight: 63.5, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p1', createdAt: 3000,
          systolic: 145, weight: 67.0, urineProtein: 'Present');

      final vitals = await dao.latestClinicalVitalsForMany(['p1']);
      expect(vitals['p1']?.hasEclampsia, isTrue,
          reason: 'BP 130→138→145, weight 60→63.5→67, urine Present — trend fires');
    });

    test('BP not strictly increasing overall → no eclampsia', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await insertAnc(db, patientId: 'p2', createdAt: 1000,
          systolic: 145, weight: 60.0, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p2', createdAt: 2000,
          systolic: 148, weight: 63.0, urineProtein: 'Absent');
      // systolic drops back to 144 — overall not increasing
      await insertAnc(db, patientId: 'p2', createdAt: 3000,
          systolic: 144, weight: 67.0, urineProtein: 'Present');

      final vitals = await dao.latestClinicalVitalsForMany(['p2']);
      expect(vitals['p2']?.hasEclampsia, isFalse,
          reason: 'sys1(145) > sys3(144) — not an overall rise');
    });

    test('BP dips at intermediate visit → no eclampsia', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await insertAnc(db, patientId: 'p3', createdAt: 1000,
          systolic: 130, weight: 60.0, urineProtein: 'Absent');
      // systolic dips at visit 2 before rising at visit 3
      await insertAnc(db, patientId: 'p3', createdAt: 2000,
          systolic: 128, weight: 63.0, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p3', createdAt: 3000,
          systolic: 145, weight: 67.0, urineProtein: 'Present');

      final vitals = await dao.latestClinicalVitalsForMany(['p3']);
      expect(vitals['p3']?.hasEclampsia, isFalse,
          reason: 'sys1(130) > sys2(128) — dip at step 1→2');
    });

    test('urine protein absent at latest visit → no eclampsia', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await insertAnc(db, patientId: 'p4', createdAt: 1000,
          systolic: 130, weight: 60.0, urineProtein: 'Present');
      await insertAnc(db, patientId: 'p4', createdAt: 2000,
          systolic: 138, weight: 63.0, urineProtein: 'Present');
      await insertAnc(db, patientId: 'p4', createdAt: 3000,
          systolic: 145, weight: 67.0, urineProtein: 'Absent');

      final vitals = await dao.latestClinicalVitalsForMany(['p4']);
      expect(vitals['p4']?.hasEclampsia, isFalse,
          reason: 'latest urine protein Absent — trend requires it Present');
    });

    test('only 2 ANC visits → no eclampsia (insufficient data)', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await insertAnc(db, patientId: 'p5', createdAt: 1000,
          systolic: 130, weight: 60.0, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p5', createdAt: 2000,
          systolic: 145, weight: 67.0, urineProtein: 'Present');

      final vitals = await dao.latestClinicalVitalsForMany(['p5']);
      expect(vitals['p5']?.hasEclampsia, isFalse,
          reason: 'fewer than 3 ANC visits — trend cannot fire');
    });

    test('missing systolic in middle visit → conservative no-eclampsia', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await insertAnc(db, patientId: 'p6', createdAt: 1000,
          systolic: 130, weight: 60.0, urineProtein: 'Absent');
      // visit 2 has no systolic reading
      await insertAnc(db, patientId: 'p6', createdAt: 2000,
          weight: 63.0, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p6', createdAt: 3000,
          systolic: 148, weight: 67.0, urineProtein: 'Present');

      final vitals = await dao.latestClinicalVitalsForMany(['p6']);
      expect(vitals['p6']?.hasEclampsia, isFalse,
          reason: 'missing systolic — conservative: no-eclampsia');
    });

    test('weight absent across all visits + rising BP + urine → still fires', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await insertAnc(db, patientId: 'p7', createdAt: 1000,
          systolic: 130, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p7', createdAt: 2000,
          systolic: 138, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p7', createdAt: 3000,
          systolic: 146, urineProtein: 'Present');

      final vitals = await dao.latestClinicalVitalsForMany(['p7']);
      expect(vitals['p7']?.hasEclampsia, isTrue,
          reason: 'weight absent but BP rising + urine present — fires (weight optional)');
    });

    test('weight dips at intermediate visit → no eclampsia', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await insertAnc(db, patientId: 'p8', createdAt: 1000,
          systolic: 130, weight: 65.0, urineProtein: 'Absent');
      // weight drops at visit 2
      await insertAnc(db, patientId: 'p8', createdAt: 2000,
          systolic: 138, weight: 63.0, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'p8', createdAt: 3000,
          systolic: 145, weight: 68.0, urineProtein: 'Present');

      final vitals = await dao.latestClinicalVitalsForMany(['p8']);
      expect(vitals['p8']?.hasEclampsia, isFalse,
          reason: 'w1(65) > w2(63) — weight dip at step 1→2');
    });

    test('form-level eclampsia flag still works independently of trend', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      // Only 1 visit, but eclampsia explicitly recorded in the form
      await insertAnc(db, patientId: 'p9', createdAt: 1000,
          systolic: 160, urineProtein: 'Present', eclampsia: true);

      final vitals = await dao.latestClinicalVitalsForMany(['p9']);
      expect(vitals['p9']?.hasEclampsia, isTrue,
          reason: 'form-level eclampsia flag must survive alongside trend detection');
    });

    test('batch: two patients — one trend fires, other does not', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      // pa — rising trend
      for (final (t, sys, wt, urine) in [
        (1000, 130, 60.0, 'Absent'),
        (2000, 138, 63.0, 'Absent'),
        (3000, 145, 67.0, 'Present'),
      ]) {
        await insertAnc(db, patientId: 'pa', createdAt: t,
            systolic: sys, weight: wt, urineProtein: urine);
      }

      // pb — flat BP
      for (final (t, sys, urine) in [
        (1000, 130, 'Absent'),
        (2000, 130, 'Absent'),
        (3000, 130, 'Present'),
      ]) {
        await insertAnc(db, patientId: 'pb', createdAt: t,
            systolic: sys, urineProtein: urine);
      }

      final vitals = await dao.latestClinicalVitalsForMany(['pa', 'pb']);
      expect(vitals['pa']?.hasEclampsia, isTrue);
      expect(vitals['pb']?.hasEclampsia, isFalse,
          reason: 'flat BP (130→130→130) — overall not rising');
    });

    test('4th+ ANC visits are ignored — only last 3 count', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      // 4 visits: first 3 trend up, then 4th (oldest) had low values
      // We expect the trend to be computed on visits 2→3→4 (by created_at DESC),
      // so the LAST 3 chronologically (visits 2, 3, 4).
      await insertAnc(db, patientId: 'pq', createdAt: 1000,
          systolic: 110, weight: 55.0, urineProtein: 'Absent'); // oldest
      await insertAnc(db, patientId: 'pq', createdAt: 2000,
          systolic: 130, weight: 60.0, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'pq', createdAt: 3000,
          systolic: 140, weight: 64.0, urineProtein: 'Absent');
      await insertAnc(db, patientId: 'pq', createdAt: 4000,
          systolic: 148, weight: 68.0, urineProtein: 'Present'); // newest

      // The 3 newest are: t=4000 (sys148), t=3000 (sys140), t=2000 (sys130)
      // Oldest-first: 130→140→148 — rising BP, rising weight, urine present
      final vitals = await dao.latestClinicalVitalsForMany(['pq']);
      expect(vitals['pq']?.hasEclampsia, isTrue,
          reason: 'last 3 visits (t=2000→3000→4000) show a clear rising trend');
    });
  });
}
