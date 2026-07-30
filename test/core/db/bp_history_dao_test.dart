import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/bp_history_dao.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, BpHistoryDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, BpHistoryDao(app));
  }

  Future<void> insertAssessment(
    AppDatabase app, {
    required String patientId,
    required String type,
    required Map<String, dynamic> details,
    required int createdAt,
  }) async {
    await app.db.insert('local_assessments', {
      'id': '$patientId-$type-$createdAt',
      'household_member_local_id': 1,
      'patient_id': patientId,
      'assessment_type': type,
      'assessment_details': jsonEncode(details),
      'created_at': createdAt,
    });
  }

  group('BpHistoryDao', () {
    test('no prior assessments → empty list', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      final result = await dao.getForPatient('patient-1');
      expect(result, isEmpty);
    });

    test('3 NCD assessments with avgSystolic → correct readings, oldest first', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      await insertAssessment(db,
          patientId: 'p1', type: 'NCD',
          details: {'avgSystolic': 120}, createdAt: 1000);
      await insertAssessment(db,
          patientId: 'p1', type: 'NCD',
          details: {'avgSystolic': 130}, createdAt: 2000);
      await insertAssessment(db,
          patientId: 'p1', type: 'NCD',
          details: {'avgSystolic': 140}, createdAt: 3000);

      final readings = await dao.getForPatient('p1');
      expect(readings.length, 3);
      expect(readings[0].systolic, 120);
      expect(readings[1].systolic, 130);
      expect(readings[2].systolic, 140);
      expect(readings[0].visitIndex, 0);
      expect(readings[2].visitIndex, 2);
    });

    test('mixed ANC + NCD types → both included', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      await insertAssessment(db,
          patientId: 'p2', type: 'NCD',
          details: {'avgSystolic': 125}, createdAt: 1000);
      await insertAssessment(db,
          patientId: 'p2', type: 'ANC',
          details: {'systolic': 118}, createdAt: 2000);
      await insertAssessment(db,
          patientId: 'p2', type: 'PNC',
          details: {'systolic': 122}, createdAt: 3000);

      final readings = await dao.getForPatient('p2');
      expect(readings.length, 3);
      expect(readings[0].systolic, 125);
      expect(readings[1].systolic, 118);
      expect(readings[2].systolic, 122);
    });

    test('bpLogDetails shape → first reading used', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      await insertAssessment(db,
          patientId: 'p3', type: 'NCD',
          details: {
            'bpLogDetails': [
              {'systolic': 135, 'diastolic': 85},
              {'systolic': 138, 'diastolic': 88},
            ]
          },
          createdAt: 1000);

      final readings = await dao.getForPatient('p3');
      expect(readings.length, 1);
      expect(readings.first.systolic, 135);
    });

    test('assessment with no BP field → silently skipped', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      await insertAssessment(db,
          patientId: 'p4', type: 'NCD',
          details: {'someOtherField': 'value'}, createdAt: 1000);
      await insertAssessment(db,
          patientId: 'p4', type: 'NCD',
          details: {'avgSystolic': 128}, createdAt: 2000);

      final readings = await dao.getForPatient('p4');
      expect(readings.length, 1);
      expect(readings.first.systolic, 128);
    });

    test('other patient\'s assessments not included', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      await insertAssessment(db,
          patientId: 'other', type: 'NCD',
          details: {'avgSystolic': 155}, createdAt: 1000);

      final readings = await dao.getForPatient('target-patient');
      expect(readings, isEmpty);
    });

    test('visitIndex assigned sequentially 0..n-1', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      for (int i = 0; i < 5; i++) {
        await insertAssessment(db,
            patientId: 'p5', type: 'NCD',
            details: {'avgSystolic': 120 + i * 5},
            createdAt: 1000 + i * 1000);
      }
      final readings = await dao.getForPatient('p5');
      for (int i = 0; i < 5; i++) {
        expect(readings[i].visitIndex, i);
      }
    });
  });
}
