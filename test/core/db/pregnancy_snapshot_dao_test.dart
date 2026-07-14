import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/pregnancy_snapshot_dao.dart';
import 'package:uhis_next/core/mission/mission_pregnancy_facts.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, PregnancySnapshotDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, PregnancySnapshotDao(app));
  }

  group('PregnancySnapshotDao.mergePreservingDates', () {
    test('keeps prior LMP/EDD when incoming omits them', () {
      final prior = {
        'p1': PregnancySnapshotRow(
          patientId: 'p1',
          facts: const PregnancyFacts(highRiskPregnantWoman: false),
          lmpDate: 1000,
          eddDate: 2000,
        ),
      };
      final incoming = [
        PregnancySnapshotRow(
          patientId: 'p1',
          facts: const PregnancyFacts(highRiskPregnantWoman: true),
          updatedAt: 9,
          // Server sent facts but no dates.
        ),
      ];

      final merged = PregnancySnapshotDao.mergePreservingDates(
        incoming: incoming,
        prior: prior,
      );

      expect(merged, hasLength(1));
      expect(merged.first.facts.highRiskPregnantWoman, isTrue);
      expect(merged.first.lmpDate, 1000);
      expect(merged.first.eddDate, 2000);
    });

    test('keeps local-only enroll when patient absent from incoming', () {
      final prior = {
        'local-only': PregnancySnapshotRow(
          patientId: 'local-only',
          facts: PregnancyFacts.empty,
          lmpDate: 555,
        ),
      };

      final merged = PregnancySnapshotDao.mergePreservingDates(
        incoming: const [],
        prior: prior,
      );

      expect(merged, hasLength(1));
      expect(merged.first.patientId, 'local-only');
      expect(merged.first.lmpDate, 555);
    });

    test('incoming dates override prior', () {
      final prior = {
        'p1': PregnancySnapshotRow(
          patientId: 'p1',
          facts: PregnancyFacts.empty,
          lmpDate: 1,
          eddDate: 2,
        ),
      };
      final incoming = [
        PregnancySnapshotRow(
          patientId: 'p1',
          facts: PregnancyFacts.empty,
          lmpDate: 99,
          eddDate: 88,
        ),
      ];

      final merged = PregnancySnapshotDao.mergePreservingDates(
        incoming: incoming,
        prior: prior,
      );

      expect(merged.first.lmpDate, 99);
      expect(merged.first.eddDate, 88);
    });

    test('coalesces duplicate incoming episodes so later null LMP cannot wipe',
        () {
      // Mirrors spice-dev pregnancyInfos for one member: first episode has
      // lastMenstrualPeriod, a later episode row omits it.
      final incoming = [
        PregnancySnapshotRow(
          patientId: '05501421602887',
          facts: PregnancyFacts.empty,
          updatedAt: 1,
          lmpDate: 1746921600000, // 2026-05-11
          eddDate: 1771113600000,
        ),
        PregnancySnapshotRow(
          patientId: '05501421602887',
          facts: const PregnancyFacts(isPostpartumWindow: true),
          updatedAt: 2,
          // later episode — LMP/EDD null on wire
        ),
      ];

      final merged = PregnancySnapshotDao.mergePreservingDates(
        incoming: incoming,
        prior: const {},
      );

      expect(merged, hasLength(1));
      expect(merged.first.lmpDate, 1746921600000);
      expect(merged.first.eddDate, 1771113600000);
      expect(merged.first.facts.isPostpartumWindow, isTrue);
    });
  });

  group('PregnancySnapshotDao.getAllRows', () {
    test('round-trips lmp_date and edd_date', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsertOne(PregnancySnapshotRow(
        patientId: 'p1',
        facts: const PregnancyFacts(isNearTermAnc: true),
        lmpDate: 111,
        eddDate: 222,
      ));

      final rows = await dao.getAllRows();
      expect(rows['p1']?.lmpDate, 111);
      expect(rows['p1']?.eddDate, 222);
      expect(rows['p1']?.facts.isNearTermAnc, isTrue);

      final factsOnly = await dao.getAll();
      expect(factsOnly['p1']?.isNearTermAnc, isTrue);
    });
  });
}
