import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/encounter_dao.dart';

/// Covers [EncounterDao.findPendingDraftId] -- the reconciliation lookup
/// `OfflineSyncService`'s assessment-history ingestion uses to preserve a
/// draft encounter's own client-minted id across sync, instead of orphaning
/// it under a brand-new row keyed by the server's own numeric encounterId.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, EncounterDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, EncounterDao(app));
  }

  EncounterRow _draft({
    required String id,
    String patientId = 'p1',
    String programme = 'eyeCare',
    required int startedAt,
    SyncStatus syncStatus = SyncStatus.pending,
  }) {
    return EncounterRow(
      id: id,
      patientId: patientId,
      programme: programme,
      startedAt: startedAt,
      status: EncounterStatus.draft,
      syncStatus: syncStatus,
    );
  }

  final noon = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  group('EncounterDao.findPendingDraftId', () {
    test('returns null when no draft exists at all', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      final result = await dao.findPendingDraftId(
        patientId: 'p1',
        programme: 'eye_care',
        around: noon,
      );

      expect(result, isNull);
    });

    test('matches a pending draft, normalizing programme across naming conventions',
        () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(_draft(
        id: 'draft-1',
        programme: 'eyeCare', // draft-creation-time convention
        startedAt: noon.millisecondsSinceEpoch,
      ));

      final result = await dao.findPendingDraftId(
        patientId: 'p1',
        programme: 'eye_care', // assessment-history's own convention
        around: noon,
      );

      expect(result, 'draft-1');
    });

    test('ignores a draft for a different patient', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(_draft(
        id: 'draft-1',
        patientId: 'other-patient',
        startedAt: noon.millisecondsSinceEpoch,
      ));

      final result = await dao.findPendingDraftId(
        patientId: 'p1',
        programme: 'eye_care',
        around: noon,
      );

      expect(result, isNull);
    });

    test('ignores a draft for a different programme even after normalization',
        () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(_draft(
        id: 'draft-1',
        programme: 'anc',
        startedAt: noon.millisecondsSinceEpoch,
      ));

      final result = await dao.findPendingDraftId(
        patientId: 'p1',
        programme: 'eye_care',
        around: noon,
      );

      expect(result, isNull);
    });

    test('ignores a draft outside the time window', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(_draft(
        id: 'draft-1',
        startedAt: noon
            .subtract(const Duration(hours: 30))
            .millisecondsSinceEpoch,
      ));

      final result = await dao.findPendingDraftId(
        patientId: 'p1',
        programme: 'eye_care',
        around: noon,
        window: const Duration(hours: 20),
      );

      expect(result, isNull);
    });

    test('ignores a draft that is no longer pending (already reconciled/synced)',
        () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(_draft(
        id: 'draft-1',
        startedAt: noon.millisecondsSinceEpoch,
        syncStatus: SyncStatus.synced,
      ));

      final result = await dao.findPendingDraftId(
        patientId: 'p1',
        programme: 'eye_care',
        around: noon,
      );

      expect(result, isNull);
    });

    test('picks the closest-in-time candidate when multiple pending drafts match',
        () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.upsert(_draft(
        id: 'draft-far',
        startedAt: noon.subtract(const Duration(hours: 10)).millisecondsSinceEpoch,
      ));
      await dao.upsert(_draft(
        id: 'draft-close',
        startedAt: noon.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      ));

      final result = await dao.findPendingDraftId(
        patientId: 'p1',
        programme: 'eye_care',
        around: noon,
      );

      expect(result, 'draft-close');
    });
  });
}
