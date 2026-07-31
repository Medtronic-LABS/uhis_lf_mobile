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

  test('fresh-install schema includes custom_status column', () async {
    final columns = await appDb.db
        .rawQuery('PRAGMA table_info(${LocalAssessmentDao.tableName})');
    final names = columns.map((c) => c['name'] as String).toSet();
    expect(names, contains('custom_status'));
  });

  test('insert() succeeds — regression for the missing custom_status column',
      () async {
    // LocalAssessmentEntity.toDb() has always included custom_status; before
    // the v32 migration the table itself never had that column, so every
    // insert() (any assessment type) threw "no column named custom_status"
    // at the SQLite layer. Most callers swallowed the error and proceeded
    // anyway, so it never surfaced -- this locks in the real fix.
    await dao.insert(const LocalAssessmentEntity(
      id: 'a1',
      householdMemberLocalId: 1,
      patientId: 'p1',
      assessmentType: 'CHILD_IMMUNIZATION',
      assessmentDetails: '{"vaccinations":[]}',
      customStatus: '["Referred"]',
    ));

    final rows = await appDb.db
        .query(LocalAssessmentDao.tableName, where: 'id = ?', whereArgs: ['a1']);
    expect(rows.single['custom_status'], '["Referred"]');
  });
}
