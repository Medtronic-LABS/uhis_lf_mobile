import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/pregnancy_episode_dao.dart';
import 'package:uhis_next/core/db/pregnancy_snapshot_dao.dart';
import 'package:uhis_next/core/mission/mission_pregnancy_facts.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // `sqflite`'s openDatabase caches connections by path with
  // singleInstance:true by default, and inMemoryDatabasePath is the same
  // constant on every call — so all tests in this file actually share one
  // underlying in-memory database. Each test therefore uses its own unique
  // patientId so leftover rows from earlier tests can't be mistaken for
  // this test's state (matters here specifically because several assertions
  // check for *absence* of an episode, unlike pregnancy_snapshot_dao_test.dart's
  // presence-only assertions, which don't need this).
  Future<(AppDatabase, PregnancySnapshotDao, PregnancyEpisodeDao)>
      openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    final snapshotDao = PregnancySnapshotDao(app);
    return (app, snapshotDao, PregnancyEpisodeDao(app, snapshotDao));
  }

  group('PregnancyEpisodeDao.startNewEpisode', () {
    test('creates an open episode and refreshes the snapshot projection',
        () async {
      final (_, snapshotDao, episodeDao) = await openTestDb();
      const patientId = 'start-episode';

      final episode = await episodeDao.startNewEpisode(
        patientId: patientId,
        obstetric: PregnancySnapshotRow(
          patientId: patientId,
          facts: PregnancyFacts.empty,
          lmpDate: 1000,
          eddDate: 2000,
          gravida: 1,
        ),
      );

      expect(episode.id, isNotEmpty);
      expect(episode.isOpen, isTrue);
      expect(episode.obstetric.lmpDate, 1000);

      final projected = await snapshotDao.byPatient(patientId);
      expect(projected?.lmpDate, 1000);
      expect(projected?.gravida, 1);
    });
  });

  group('PregnancyEpisodeDao.openEpisodeFor / mostRecentFor', () {
    test('openEpisodeFor returns null once the episode is closed', () async {
      final (_, _, episodeDao) = await openTestDb();
      const patientId = 'open-then-close';
      await episodeDao.startNewEpisode(
        patientId: patientId,
        obstetric: PregnancySnapshotRow(
            patientId: patientId, facts: PregnancyFacts.empty),
      );
      expect(await episodeDao.openEpisodeFor(patientId), isNotNull);

      await episodeDao.closeEpisode(
          patientId: patientId, deliveryDateMillis: 5000);
      expect(await episodeDao.openEpisodeFor(patientId), isNull);
      expect(await episodeDao.mostRecentFor(patientId), isNotNull);
    });

    test('returns null for a patient with no episode at all', () async {
      final (_, _, episodeDao) = await openTestDb();
      expect(await episodeDao.openEpisodeFor('never-had-one'), isNull);
      expect(await episodeDao.mostRecentFor('never-had-one'), isNull);
    });
  });

  group('PregnancyEpisodeDao.updateOpenEpisode', () {
    test('merges onto the open episode without creating a new one', () async {
      final (_, _, episodeDao) = await openTestDb();
      const patientId = 'update-open';
      final started = await episodeDao.startNewEpisode(
        patientId: patientId,
        obstetric: PregnancySnapshotRow(
          patientId: patientId,
          facts: PregnancyFacts.empty,
          lmpDate: 1000,
        ),
      );

      final updated = await episodeDao.updateOpenEpisode(
        patientId: patientId,
        patch: PregnancySnapshotRow(
          patientId: patientId,
          facts: PregnancyFacts.empty,
          ancVisitNo: 1,
        ),
      );

      expect(updated.id, started.id, reason: 'same episode, not a new one');
      expect(updated.obstetric.lmpDate, 1000,
          reason: 'patch omitted lmpDate — merge keeps the prior value');
      expect(updated.obstetric.ancVisitNo, 1);
    });

    test('falls back to starting a new episode when none is open', () async {
      final (_, _, episodeDao) = await openTestDb();
      const patientId = 'update-fallback';
      final updated = await episodeDao.updateOpenEpisode(
        patientId: patientId,
        patch: PregnancySnapshotRow(
          patientId: patientId,
          facts: PregnancyFacts.empty,
          ancVisitNo: 1,
        ),
      );
      expect(updated.isOpen, isTrue);
      expect(updated.obstetric.ancVisitNo, 1);
    });
  });

  group('PregnancyEpisodeDao.closeEpisode', () {
    test('sets closedAt and deliveryDateMillis on the open episode',
        () async {
      final (_, snapshotDao, episodeDao) = await openTestDb();
      const patientId = 'close-episode';
      await episodeDao.startNewEpisode(
        patientId: patientId,
        obstetric: PregnancySnapshotRow(
          patientId: patientId,
          facts: PregnancyFacts.empty,
          lmpDate: 1000,
        ),
      );

      final closed = await episodeDao.closeEpisode(
        patientId: patientId,
        deliveryDateMillis: 9999,
        facts: const PregnancyFacts(isPostpartumWindow: true),
      );

      expect(closed.closedAt, isNotNull);
      expect(closed.obstetric.deliveryDateMillis, 9999);
      expect(closed.obstetric.facts.isPostpartumWindow, isTrue);

      final projected = await snapshotDao.byPatient(patientId);
      expect(projected?.deliveryDateMillis, 9999);
    });

    test('a second pregnancy after closing starts a genuinely new episode',
        () async {
      final (_, snapshotDao, episodeDao) = await openTestDb();
      const patientId = 'second-pregnancy';
      final first = await episodeDao.startNewEpisode(
        patientId: patientId,
        obstetric: PregnancySnapshotRow(
          patientId: patientId,
          facts: PregnancyFacts.empty,
          lmpDate: 1000,
        ),
      );
      await episodeDao.closeEpisode(
          patientId: patientId, deliveryDateMillis: 2000);

      final second = await episodeDao.startNewEpisode(
        patientId: patientId,
        obstetric: PregnancySnapshotRow(
          patientId: patientId,
          facts: PregnancyFacts.empty,
          lmpDate: 50000,
        ),
      );

      expect(second.id, isNot(first.id));
      expect(second.isOpen, isTrue);
      expect(second.obstetric.deliveryDateMillis, isNull,
          reason: 'the new episode must not inherit the old delivery date — '
              'this is the exact bug the episode entity fixes');

      final projected = await snapshotDao.byPatient(patientId);
      expect(projected?.lmpDate, 50000);
      expect(projected?.deliveryDateMillis, isNull);
    });

    test(
        'creates-and-closes a fresh episode in one shot when no episode ever '
        'existed (direct Pregnancy Outcome entry, no prior PW/ANC)', () async {
      final (_, snapshotDao, episodeDao) = await openTestDb();
      const patientId = 'direct-outcome-entry';
      expect(await episodeDao.openEpisodeFor(patientId), isNull);
      expect(await episodeDao.mostRecentFor(patientId), isNull);

      final closed = await episodeDao.closeEpisode(
        patientId: patientId,
        deliveryDateMillis: 12345,
      );

      expect(closed.isOpen, isFalse);
      expect(closed.closedAt, isNotNull);
      expect(closed.obstetric.deliveryDateMillis, 12345);

      final projected = await snapshotDao.byPatient(patientId);
      expect(projected?.deliveryDateMillis, 12345);
    });
  });
}
