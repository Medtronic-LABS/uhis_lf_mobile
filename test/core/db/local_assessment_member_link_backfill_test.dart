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

  test('syncPatientIdsFromMemberLinks repairs FHIR-only assessment rows', () async {
    await appDb.db.insert(AppDatabase.tableMembers, {
      'id': 7,
      'name': 'Roja',
      'fhir_id': 'fhir-roja',
    });

    await dao.insert(const LocalAssessmentEntity(
      id: 'assess-1',
      householdMemberLocalId: 0,
      memberId: 'fhir-roja',
      patientId: 'fhir-roja',
      assessmentType: 'PWPROFILE',
      assessmentDetails: '{}',
    ));

    final updated = await dao.syncPatientIdsFromMemberLinks();
    expect(updated, greaterThan(0));

    final rows = await dao.getByPatientIds(['7']);
    expect(rows, hasLength(1));
    expect(rows.single.householdMemberLocalId, 7);
    expect(rows.single.patientId, '7');
  });
}
