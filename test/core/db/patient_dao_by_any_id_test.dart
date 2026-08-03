import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/core/models/patient.dart';

/// `patients` rows are keyed by the local member PK, but the household screens
/// route with `members.patient_id` — which holds the server-assigned id when
/// the sync bundle supplies one. [PatientDao.byAnyId] has to span both id
/// spaces, otherwise Start Visit fails with "Patient not found in local
/// database" for exactly those members.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late PatientDao dao;

  setUp(() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    appDb = AppDatabase.forTesting(raw);
    dao = PatientDao(appDb);
  });

  tearDown(() => appDb.close());

  Future<void> insertMember({
    required int id,
    String? patientId,
    String? fhirId,
    String? referenceId,
  }) async {
    await appDb.db.insert(AppDatabase.tableMembers, {
      'id': id,
      'name': 'Member $id',
      'patient_id': patientId,
      'fhir_id': fhirId,
      'reference_id': referenceId,
    });
  }

  test('resolves by patients.id', () async {
    await dao.upsertMany([const Patient(id: '7', rawJson: '{}')]);

    expect((await dao.byAnyId('7'))?.id, '7');
  });

  test('resolves a server id held in patients.patient_id', () async {
    await dao.upsertMany([
      const Patient(id: '7', patientId: 'srv-abc', rawJson: '{}'),
    ]);

    expect(await dao.byId('srv-abc'), isNull);
    expect((await dao.byAnyId('srv-abc'))?.id, '7');
  });

  test('bridges through members.patient_id to the local PK', () async {
    await insertMember(id: 7, patientId: 'srv-abc');
    await dao.upsertMany([const Patient(id: '7', rawJson: '{}')]);

    expect((await dao.byAnyId('srv-abc'))?.id, '7');
  });

  test('bridges through members.fhir_id to the local PK', () async {
    await insertMember(id: 7, fhirId: 'fhir-xyz');
    await dao.upsertMany([const Patient(id: '7', rawJson: '{}')]);

    expect((await dao.byAnyId('fhir-xyz'))?.id, '7');
  });

  test('prefers members.patient_id over a lower-priority column match',
      () async {
    // Same string used as one member's patient_id and another's reference_id.
    await insertMember(id: 7, patientId: 'dup');
    await insertMember(id: 8, referenceId: 'dup');
    await dao.upsertMany([
      const Patient(id: '7', rawJson: '{}'),
      const Patient(id: '8', rawJson: '{}'),
    ]);

    expect((await dao.byAnyId('dup'))?.id, '7');
  });

  test('refuses to bridge an id that matches two members on one column',
      () async {
    await insertMember(id: 7, patientId: 'dup');
    await insertMember(id: 8, patientId: 'dup');
    await dao.upsertMany([
      const Patient(id: '7', rawJson: '{}'),
      const Patient(id: '8', rawJson: '{}'),
    ]);

    expect(await dao.byAnyId('dup'), isNull);
  });

  test('returns null for an unknown id and for an empty id', () async {
    await dao.upsertMany([const Patient(id: '7', rawJson: '{}')]);

    expect(await dao.byAnyId('nope'), isNull);
    expect(await dao.byAnyId(''), isNull);
  });
}
