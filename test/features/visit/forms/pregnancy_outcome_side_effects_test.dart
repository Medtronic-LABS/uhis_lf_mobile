library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/member_dao.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/pregnancy_outcome_side_effects.dart';

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

  group('PregnancyOutcomeSideEffects', () {
    late AppDatabase db;
    late MemberDao memberDao;
    late PatientDao patientDao;

    late String motherLocalId;

    setUp(() async {
      db = await _openInMemoryDb();
      memberDao = MemberDao(db);
      patientDao = PatientDao(db);

      motherLocalId = await memberDao.insertLocal(
        const HouseholdMemberEntity(
          id: '0',
          householdId: '10',
          householdFhirId: 'hh-fhir-10',
          householdReferenceId: '10',
          name: 'Test Mother',
          gender: 'female',
          syncStatus: 'Success',
        ),
      );
      await memberDao.setReferenceId(motherLocalId);
    });

    test('registers live baby with NotSynced status for push queue', () async {
      final wire = await PregnancyOutcomeSideEffects(
        memberDao: memberDao,
        patientDao: patientDao,
      ).apply(
        data: CanonicalVisitData({
          'dateOfDelivery': '2026-09-22',
          'newbornDetails': [
            {'isBabyAlive': 'Yes', 'sex': 'female'},
          ],
        }),
        motherMemberId: motherLocalId,
        motherPatientId: null,
        householdId: '10',
      );

      expect(wire, hasLength(1));
      expect(wire.first['referenceId'], isNotEmpty);
      expect(wire.first['householdId'], 'hh-fhir-10');

      final pending = await memberDao.getUnsynced();
      expect(pending, hasLength(1));
      expect(pending.single.syncStatus, 'NotSynced');
      expect(pending.single.name, 'Baby 1 of Test Mother');
      expect(pending.single.motherReferenceId, isNotEmpty);

      final patient = await patientDao.byId(pending.single.id);
      expect(patient, isNotNull);
      expect(patient!.name, 'Baby 1 of Test Mother');
    });

    test('maternal death marks mother NotSynced for member push', () async {
      await PregnancyOutcomeSideEffects(
        memberDao: memberDao,
        patientDao: patientDao,
      ).apply(
        data: CanonicalVisitData({
          'timeOfDeath': '2026-09-22T10:00:00',
        }),
        motherMemberId: motherLocalId,
        motherPatientId: null,
        householdId: '10',
      );

      final mother = await memberDao.getById(motherLocalId);
      expect(mother, isNotNull);
      expect(mother!.isActive, isFalse);
      expect(mother.syncStatus, 'NotSynced');
    });

    test('skips stillborn entries — only live babies are registered', () async {
      await PregnancyOutcomeSideEffects(
        memberDao: memberDao,
        patientDao: patientDao,
      ).apply(
        data: CanonicalVisitData({
          'dateOfDelivery': '2026-09-22',
          'newbornDetails': [
            {'isBabyAlive': 'No', 'sex': 'male'},
          ],
        }),
        motherMemberId: motherLocalId,
        motherPatientId: null,
        householdId: '10',
      );

      expect(await memberDao.getUnsynced(), isEmpty);
    });
  });
}
