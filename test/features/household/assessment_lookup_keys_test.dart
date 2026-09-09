import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/member_dao.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/core/models/patient.dart';
import 'package:uhis_next/features/household/member_assessment_lookup.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late PatientDao patients;
  late MemberDao members;

  setUp(() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    appDb = AppDatabase.forTesting(raw);
    patients = PatientDao(appDb);
    members = MemberDao(appDb);
  });

  tearDown(() => appDb.close());

  test('maps server patients.patient_id to local assessment keys', () async {
    await patients.upsertMany([
      const Patient(id: '1', patientId: '646733', name: 'Aliya', rawJson: '{}'),
    ]);
    await appDb.db.insert(AppDatabase.tableMembers, {
      'id': 1,
      'name': 'Aliya',
      'patient_id': '1',
    });

    final keys = await assessmentLookupKeysForRoute(
      routePatientId: '646733',
      memberDao: members,
      patientDao: patients,
    );

    expect(keys, containsAll(['646733', '1']));
  });

  test('maps server FHIR id to local assessment keys', () async {
    await patients.upsertMany([
      const Patient(id: '1', patientId: '646733', name: 'Aliya', rawJson: '{}'),
    ]);
    await appDb.db.insert(AppDatabase.tableMembers, {
      'id': 1,
      'name': 'Aliya',
      'patient_id': '1',
      'fhir_id': 'fhir-abc-123',
    });

    final keys = await assessmentLookupKeysForRoute(
      routePatientId: 'fhir-abc-123',
      memberDao: members,
      patientDao: patients,
    );

    expect(keys, containsAll(['fhir-abc-123', '1', '646733']));
  });

  test('includes navigation extra local member id', () async {
    await patients.upsertMany([
      const Patient(id: '1', patientId: '646733', rawJson: '{}'),
    ]);

    final keys = await assessmentLookupKeysForRoute(
      routePatientId: '646733',
      memberDao: members,
      patientDao: patients,
      navigationExtra: const {
        'id': '1',
        'patientId': '646733',
      },
    );

    expect(keys, containsAll(['646733', '1']));
  });
}
