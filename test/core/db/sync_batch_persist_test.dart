import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/encounter_dao.dart';
import 'package:uhis_next/core/db/household_dao.dart';
import 'package:uhis_next/core/db/member_dao.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/core/db/patient_programmes_dao.dart';
import 'package:uhis_next/core/models/patient.dart';
import 'package:uhis_next/core/models/programme.dart';

Future<AppDatabase> _openInMemoryDb() async {
  final rawDb = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppDatabase.schemaVersion,
      onCreate: AppDatabase.createSchema,
      singleInstance: false,
    ),
  );
  return AppDatabase.forTesting(rawDb);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('HouseholdDao.upsertManyFromBE', () {
    late AppDatabase db;
    late HouseholdDao households;

    setUp(() async {
      db = await _openInMemoryDb();
      households = HouseholdDao(db);
    });

    test('batch upsert inserts and updates by fhir id', () async {
      final first = [
        HouseholdEntity(id: '0', fhirId: 'hh-1', name: 'House A'),
        HouseholdEntity(id: '0', fhirId: 'hh-2', name: 'House B'),
      ];

      final map1 = await households.upsertManyFromBE(first);
      expect(map1, hasLength(2));

      final updated = [
        first[0].copyWith(name: 'House A updated'),
        HouseholdEntity(id: '0', fhirId: 'hh-3', name: 'House C'),
      ];
      final map2 = await households.upsertManyFromBE(updated);
      expect(map2['hh-1'], map1['hh-1']);

      final row = await households.getByFhirId('hh-1');
      expect(row?.name, 'House A updated');
    });

    test('fhirToLocalIds resolves many ids in one query', () async {
      await households.upsertManyFromBE([
        HouseholdEntity(id: '0', fhirId: 'hh-a'),
        HouseholdEntity(id: '0', fhirId: 'hh-b'),
      ]);
      final map = await households.fhirToLocalIds(['hh-a', 'hh-b', 'missing']);
      expect(map, hasLength(2));
      expect(map['hh-a'], isNotEmpty);
      expect(map['hh-b'], isNotEmpty);
    });
  });

  group('MemberDao.upsertManyFromBE', () {
    late AppDatabase db;
    late MemberDao members;

    setUp(() async {
      db = await _openInMemoryDb();
      members = MemberDao(db);
    });

    test('batch upsert inserts and updates by fhir id', () async {
      final first = [
        HouseholdMemberEntity(
          id: '0',
          fhirId: 'm-1',
          name: 'A',
          referenceId: 'ref-1',
        ),
        HouseholdMemberEntity(
          id: '0',
          fhirId: 'm-2',
          name: 'B',
          referenceId: 'ref-2',
        ),
      ];

      final map1 = await members.upsertManyFromBE(first);
      expect(map1, hasLength(2));
      expect(map1['m-1'], isNotEmpty);
      expect(map1['m-2'], isNotEmpty);

      final updated = [
        first[0].copyWith(name: 'A-updated'),
        HouseholdMemberEntity(
          id: '0',
          fhirId: 'm-3',
          name: 'C',
          referenceId: 'ref-3',
        ),
      ];
      final map2 = await members.upsertManyFromBE(updated);
      expect(map2, hasLength(2));
      expect(map2['m-1'], map1['m-1']);

      final row = await members.getByFhirId('m-1');
      expect(row?.name, 'A-updated');
    });
  });

  group('PatientDao batch writes', () {
    late AppDatabase db;
    late PatientDao patients;

    setUp(() async {
      db = await _openInMemoryDb();
      patients = PatientDao(db);
      await patients.upsertMany([
        Patient(id: 'p1', rawJson: '{}'),
        Patient(id: 'p2', rawJson: '{}'),
      ]);
    });

    test('updateRiskMany writes risk columns for all patients', () async {
      await patients.updateRiskMany([
        const PatientRiskUpdate(
          patientId: 'p1',
          sortRank: 100,
          bandWireTag: '1',
          modifierWireTag: 'a',
          reasonsJson: '[]',
          nextDueAt: 1000,
          lastVisitAt: 900,
          missedVisitCount: 1,
          redFlag: true,
        ),
        const PatientRiskUpdate(
          patientId: 'p2',
          sortRank: 50,
          bandWireTag: '4',
          modifierWireTag: '',
          reasonsJson: '[]',
          clearNextDueAt: true,
        ),
      ]);

      final p1 = await patients.byId('p1');
      final p2 = await patients.byId('p2');
      expect(p1?.riskScore, 100);
      expect(p1?.redFlag, isTrue);
      expect(p2?.riskScore, 50);
      expect(p2?.nextDueAt, isNull);
    });

    test('patchVisitTimingMany updates scheduling columns', () async {
      await patients.patchVisitTimingMany([
        const PatientVisitTimingPatch(
          patientId: 'p1',
          lastVisitAt: 5000,
          nextDueAt: 6000,
        ),
      ]);
      final p1 = await patients.byId('p1');
      expect(p1?.lastVisitAt, 5000);
      expect(p1?.nextDueAt, 6000);
    });
  });

  group('PatientProgrammesDao.replaceForMany', () {
    late AppDatabase db;
    late PatientProgrammesDao programmes;

    setUp(() async {
      db = await _openInMemoryDb();
      programmes = PatientProgrammesDao(db);
    });

    test('replaces programme sets in one call', () async {
      await programmes.replaceForMany({
        'p1': {Programme.anc, Programme.pnc},
        'p2': {Programme.imci},
      });
      expect(await programmes.programmesFor('p1'), {Programme.anc, Programme.pnc});
      expect(await programmes.programmesFor('p2'), {Programme.imci});

      await programmes.replaceForMany({
        'p1': {Programme.ncd},
      });
      expect(await programmes.programmesFor('p1'), {Programme.ncd});
      expect(await programmes.programmesFor('p2'), {Programme.imci});
    });
  });

  group('EncounterDao.upsertMany', () {
    late AppDatabase db;
    late EncounterDao encounters;

    setUp(() async {
      db = await _openInMemoryDb();
      encounters = EncounterDao(db);
    });

    test('batch upserts encounter rows', () async {
      await encounters.upsertMany([
        EncounterRow(
          id: 'e1',
          patientId: 'p1',
          programme: 'anc',
          startedAt: 1000,
          status: EncounterStatus.synced,
          syncStatus: SyncStatus.synced,
          vitalsJson: '{"systolic":120}',
        ),
        EncounterRow(
          id: 'e2',
          patientId: 'p2',
          programme: 'ncd',
          startedAt: 2000,
          status: EncounterStatus.synced,
          syncStatus: SyncStatus.synced,
        ),
      ]);
      expect(await encounters.byId('e1'), isNotNull);
      expect(await encounters.byId('e2'), isNotNull);
    });
  });
}
