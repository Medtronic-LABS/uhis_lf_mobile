import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/follow_up_dao.dart';
import 'package:uhis_next/core/db/immunisation_dao.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/core/db/patient_programmes_dao.dart';
import 'package:uhis_next/core/db/sync_meta_dao.dart';
import 'package:uhis_next/core/models/patient.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/core/models/risk.dart';
import 'package:uhis_next/core/risk/risk_scoring_service.dart';
import 'package:uhis_next/features/worklist/worklist_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late PatientDao patients;
  late PatientProgrammesDao programmes;
  late FollowUpDao followUps;
  late ImmunisationDao immunisations;
  late SyncMetaDao syncMeta;
  late LocalAssessmentDao localAssessments;
  late WorklistRepository repo;

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
    programmes = PatientProgrammesDao(appDb);
    followUps = FollowUpDao(appDb);
    immunisations = ImmunisationDao(appDb);
    syncMeta = SyncMetaDao(appDb);
    localAssessments = LocalAssessmentDao(appDb);
    repo = WorklistRepository(
      patients: patients,
      programmes: programmes,
      followUps: followUps,
      immunisations: immunisations,
      syncMeta: syncMeta,
      risk: const RiskScoringService(),
      localAssessments: localAssessments,
    );
  });

  tearDown(() async {
    await appDb.close();
  });

  Patient mkPatient(String id, {String? name, int? age, String? villageId}) {
    return Patient(
      id: id,
      patientId: id,
      name: name ?? 'Patient $id',
      villageId: villageId ?? 'v1',
      isActive: true,
      rawJson: '{}',
      age: age,
    );
  }

  test('recompute orders by risk_score DESC and exposes urgent at index 0',
      () async {
    await patients.upsertMany([
      mkPatient('a', name: 'Low Adult', age: 30),
      mkPatient('b', name: 'TB Mid', age: 45),
      mkPatient('c', name: 'Urgent Pregnant', age: 28),
    ]);
    await programmes.replaceFor('b', {Programme.tb});
    await programmes.replaceFor('c', {Programme.anc});
    // Make 'c' urgent via redFlag.
    await patients.upsertMany([
      Patient(
        id: 'c',
        patientId: 'c',
        name: 'Urgent Pregnant',
        villageId: 'v1',
        rawJson: '{}',
        age: 28,
        redFlag: true,
      ),
    ]);

    final n = await repo.recomputeAllAfterSync();
    expect(n, 3);

    final list = await repo.load();
    expect(list, isNotEmpty);
    expect(list.first.patientId, 'c');
    expect(list.first.band, RiskBand.urgent);
    expect(list.first.isUrgent, isTrue);
    expect(list.last.band, RiskBand.low);
  });

  test('chip filter narrows the list to a programme', () async {
    await patients.upsertMany([
      mkPatient('a', name: 'NCD A', age: 70),
      mkPatient('b', name: 'ANC B', age: 25),
      mkPatient('c', name: 'TB C', age: 45),
    ]);
    await programmes.replaceFor('a', {Programme.ncd});
    await programmes.replaceFor('b', {Programme.anc});
    await programmes.replaceFor('c', {Programme.tb});

    await repo.recomputeAllAfterSync();

    final ancOnly = await repo.load(filter: {Programme.anc});
    expect(ancOnly.map((e) => e.patientId).toList(), ['b']);

    final tbOnly = await repo.load(filter: {Programme.tb});
    expect(tbOnly.map((e) => e.patientId).toList(), ['c']);
  });

  test('null risk_score rows do not steal the urgent slot', () async {
    await patients.upsertMany([
      mkPatient('a', name: 'Unscored', age: 30),
      mkPatient('b', name: 'Scored Mid', age: 30),
    ]);
    await programmes.replaceFor('b', {Programme.ncd});
    await patients.updateRisk(
      patientId: 'b',
      score: 65,
      bandWireTag: RiskBand.high.wireTag,
      reasonsJson: '[]',
    );

    final list = await repo.load();
    expect(list.first.patientId, 'b');
    // Unscored row still appears, just at the bottom.
    expect(list.last.patientId, 'a');
  });
}
