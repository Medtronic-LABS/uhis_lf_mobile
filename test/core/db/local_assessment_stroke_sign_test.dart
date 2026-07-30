import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late LocalAssessmentDao dao;

  setUp(() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    appDb = AppDatabase.forTesting(raw);
    dao = LocalAssessmentDao(appDb);
  });

  tearDown(() => appDb.close());

  Future<void> insert(String pid, Map<String, dynamic> details) async {
    await appDb.db.insert(LocalAssessmentDao.tableName, {
      'id': 'a-$pid',
      'household_member_local_id': 1,
      'patient_id': pid,
      'assessment_type': 'NCD',
      'assessment_details': jsonEncode(details),
      'is_referred': 0,
      'latitude': 0.0,
      'longitude': 0.0,
      'sync_status': 'pending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  test('flat oneSidedWeakness=true → hasStrokeSign=true', () async {
    await insert('p1', {
      'bloodPressureSystolic': 142,
      'bloodPressureDiastolic': 92,
      'oneSidedWeakness': true,
    });
    final vitals = await dao.latestClinicalVitalsForMany(['p1']);
    expect(vitals['p1']?.hasStrokeSign, isTrue);
  });

  test('nested htnScreening.oneSidedWeakness=true → hasStrokeSign=true',
      () async {
    await insert('p2', {
      'bloodPressureSystolic': 130,
      'bloodPressureDiastolic': 84,
      'htnScreening': {
        'oneSidedWeakness': true,
        'morningHeadaches': false,
      },
    });
    final vitals = await dao.latestClinicalVitalsForMany(['p2']);
    expect(vitals['p2']?.hasStrokeSign, isTrue);
  });

  test('missing → hasStrokeSign defaults to false', () async {
    await insert('p3', {
      'bloodPressureSystolic': 120,
      'bloodPressureDiastolic': 78,
    });
    final vitals = await dao.latestClinicalVitalsForMany(['p3']);
    expect(vitals['p3']?.hasStrokeSign, isFalse);
  });

  test('string "yes" / numeric 1 also accepted', () async {
    await insert('p4', {
      'bloodPressureSystolic': 120,
      'oneSidedWeakness': 'yes',
    });
    await insert('p5', {
      'bloodPressureSystolic': 120,
      'oneSidedWeakness': 1,
    });
    final vitals = await dao.latestClinicalVitalsForMany(['p4', 'p5']);
    expect(vitals['p4']?.hasStrokeSign, isTrue);
    expect(vitals['p5']?.hasStrokeSign, isTrue);
  });
}
