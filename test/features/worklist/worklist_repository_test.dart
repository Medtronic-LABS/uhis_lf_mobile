import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/assessment_dao.dart';
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
  late AssessmentDao assessments;
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
    assessments = AssessmentDao(appDb);
    repo = WorklistRepository(
      patients: patients,
      programmes: programmes,
      followUps: followUps,
      immunisations: immunisations,
      syncMeta: syncMeta,
      risk: const RiskScoringService(),
      localAssessments: localAssessments,
      assessments: assessments,
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

  test('recompute orders by sortRank DESC and exposes band1 at index 0',
      () async {
    await patients.upsertMany([
      mkPatient('a', name: 'Low Adult', age: 30),
      mkPatient('b', name: 'TB Mid', age: 45),
      mkPatient('c', name: 'Urgent Pregnant', age: 28),
    ]);
    await programmes.replaceFor('b', {Programme.tb});
    await programmes.replaceFor('c', {Programme.anc});
    // Make 'c' band1 via redFlag.
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
    expect(list.first.band, Band.band1);
    expect(list.first.isUrgent, isTrue);
    expect(list.last.band, Band.band4);
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

  test('null risk_score rows do not steal the band1 slot', () async {
    await patients.upsertMany([
      mkPatient('a', name: 'Unscored', age: 30),
      mkPatient('b', name: 'Scored Mid', age: 30),
    ]);
    await programmes.replaceFor('b', {Programme.ncd});
    await patients.updateRisk(
      patientId: 'b',
      sortRank: sortRankFor(Band.band2, Modifier.none),
      bandWireTag: Band.band2.wireTag,
      modifierWireTag: Modifier.none.wireTag,
      reasonsJson: '[]',
    );

    final list = await repo.load();
    expect(list.first.patientId, 'b');
    // Unscored row still appears, just at the bottom.
    expect(list.last.patientId, 'a');
  });

  test('pregnant ranks above non-pregnant within the same band', () async {
    await patients.upsertMany([
      mkPatient('np', name: 'Non Pregnant', age: 30),
      mkPatient('preg', name: 'Pregnant', age: 28),
    ]);
    await programmes.replaceFor('preg', {Programme.anc});
    // Force both onto band2 with the same modifier so only pregnancy can
    // break the tie.
    final sortRank = sortRankFor(Band.band2, Modifier.none);
    await patients.updateRisk(
      patientId: 'np',
      sortRank: sortRank,
      bandWireTag: Band.band2.wireTag,
      modifierWireTag: Modifier.none.wireTag,
      reasonsJson: '[]',
    );
    await patients.updateRisk(
      patientId: 'preg',
      sortRank: sortRank,
      bandWireTag: Band.band2.wireTag,
      modifierWireTag: Modifier.none.wireTag,
      reasonsJson: '[]',
    );

    final list = await repo.load();
    expect(list.first.patientId, 'preg');
    expect(list.last.patientId, 'np');
  });

  test('longer overdue ranks higher within same band regardless of modifier',
      () async {
    final baseDate = DateTime.now();
    await patients.upsertMany([
      Patient(
        id: 'late',
        patientId: 'late',
        name: 'Late Patient',
        villageId: 'v1',
        rawJson: '{}',
        age: 35,
        nextDueAt: baseDate.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
      ),
      Patient(
        id: 'near',
        patientId: 'near',
        name: 'Near Patient',
        villageId: 'v1',
        rawJson: '{}',
        age: 35,
        nextDueAt: baseDate.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      ),
    ]);
    final sortRank = sortRankFor(Band.band3, Modifier.none);
    for (final id in ['late', 'near']) {
      await patients.updateRisk(
        patientId: id,
        sortRank: sortRank,
        bandWireTag: Band.band3.wireTag,
        modifierWireTag: Modifier.none.wireTag,
        reasonsJson: '[]',
      );
    }

    final list = await repo.load();
    expect(list.first.patientId, 'late');
    expect(list.last.patientId, 'near');
  });

  test('modifier order: a before b before none within same band and tier',
      () async {
    final due = DateTime.now().subtract(const Duration(days: 1));
    await patients.upsertMany([
      Patient(
        id: 'mNone',
        patientId: 'mNone',
        name: 'Mod None',
        villageId: 'v1',
        rawJson: '{}',
        nextDueAt: due.millisecondsSinceEpoch,
      ),
      Patient(
        id: 'mB',
        patientId: 'mB',
        name: 'Mod B',
        villageId: 'v1',
        rawJson: '{}',
        nextDueAt: due.millisecondsSinceEpoch,
      ),
      Patient(
        id: 'mA',
        patientId: 'mA',
        name: 'Mod A',
        villageId: 'v1',
        rawJson: '{}',
        nextDueAt: due.millisecondsSinceEpoch,
      ),
    ]);
    await patients.updateRisk(
      patientId: 'mNone',
      sortRank: sortRankFor(Band.band2, Modifier.none),
      bandWireTag: Band.band2.wireTag,
      modifierWireTag: Modifier.none.wireTag,
      reasonsJson: '[]',
    );
    await patients.updateRisk(
      patientId: 'mB',
      sortRank: sortRankFor(Band.band2, Modifier.b),
      bandWireTag: Band.band2.wireTag,
      modifierWireTag: Modifier.b.wireTag,
      reasonsJson: '[]',
    );
    await patients.updateRisk(
      patientId: 'mA',
      sortRank: sortRankFor(Band.band2, Modifier.a),
      bandWireTag: Band.band2.wireTag,
      modifierWireTag: Modifier.a.wireTag,
      reasonsJson: '[]',
    );

    final list = await repo.load();
    final ids = list.map((e) => e.patientId).toList();
    expect(ids.indexOf('mA'), lessThan(ids.indexOf('mB')));
    expect(ids.indexOf('mB'), lessThan(ids.indexOf('mNone')));
  });

  test('band ranks ahead of overdue duration (band2 before overdue band4)',
      () async {
    final now = DateTime.now();
    await patients.upsertMany([
      Patient(
        id: 'overdue4',
        patientId: 'overdue4',
        name: 'Overdue Band4',
        villageId: 'v1',
        rawJson: '{}',
        age: 40,
        nextDueAt:
            now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
      ),
      Patient(
        id: 'mild3',
        patientId: 'mild3',
        name: 'Mild Band3',
        villageId: 'v1',
        rawJson: '{}',
        age: 3,
      ),
    ]);
    await programmes.replaceFor('mild3', {Programme.imci});
    await patients.updateRisk(
      patientId: 'overdue4',
      sortRank: sortRankFor(Band.band4, Modifier.b),
      bandWireTag: Band.band4.wireTag,
      modifierWireTag: Modifier.b.wireTag,
      reasonsJson: '[]',
      nextDueAt:
          now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
    );
    await patients.updateRisk(
      patientId: 'mild3',
      sortRank: sortRankFor(Band.band3, Modifier.none),
      bandWireTag: Band.band3.wireTag,
      modifierWireTag: Modifier.none.wireTag,
      reasonsJson: '[]',
    );

    final list = await repo.load();
    expect(list.first.patientId, 'mild3');
    expect(list.last.patientId, 'overdue4');
  });

  test('recompute scores ANC Hb from assessment-history rows → band2',
      () async {
    await patients.upsertMany([
      mkPatient('naz', name: 'Nazmeen', age: 25),
    ]);
    await programmes.replaceFor('naz', {Programme.anc, Programme.pw});
    await assessments.upsertMany([
      AssessmentRow(
        id: 'enc-naz',
        patientId: 'naz',
        kind: 'ANC',
        occurredAt: DateTime.now().millisecondsSinceEpoch,
        rawJson:
            '{"serviceProvided":"ANC","observations":{"hemoglobin":7,"weight":45}}',
      ),
    ]);

    await repo.recomputeAllAfterSync();
    final list = await repo.load();
    expect(list.single.patientId, 'naz');
    expect(list.single.band, Band.band2);
    expect(
      list.single.reasons.any((r) => r.toLowerCase().contains('anaemia')),
      isTrue,
    );
  });

  test('village match within band ranks ahead when SK selects a village',
      () async {
    await patients.upsertMany([
      mkPatient('off', name: 'Off Village', age: 40, villageId: 'v2'),
      mkPatient('on', name: 'On Village', age: 40, villageId: 'v1'),
    ]);
    final sortRank = sortRankFor(Band.band3, Modifier.none);
    for (final id in ['off', 'on']) {
      await patients.updateRisk(
        patientId: id,
        sortRank: sortRank,
        bandWireTag: Band.band3.wireTag,
        modifierWireTag: Modifier.none.wireTag,
        reasonsJson: '[]',
      );
    }

    final list = await repo.load(selectedVillageId: 'v1');
    expect(list.first.patientId, 'on');
  });
}
