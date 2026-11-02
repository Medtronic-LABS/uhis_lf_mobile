import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/sync_meta_dao.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, SyncMetaDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, SyncMetaDao(app));
  }

  group('SyncMetaDao', () {
    test('read returns null when nothing saved for that entity', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      expect(await dao.read('callLogs'), isNull);
    });

    test('stampCursor sets cursor on a fresh entity', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.stampCursor('callLogs', 42);

      final row = await dao.read('callLogs');
      expect(row!.cursor, 42);
    });

    test('stampCursor preserves lastSyncTime/lastFullSyncAt set by stampWarm/stampFull', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      final when = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      await dao.stampFull('callLogs', when);
      await dao.stampCursor('callLogs', 42);

      final row = await dao.read('callLogs');
      expect(row!.cursor, 42);
      expect(row.lastSyncTime, when.millisecondsSinceEpoch);
      expect(row.lastFullSyncAt, when.millisecondsSinceEpoch);
    });

    test('stampWarm/stampFull preserve a cursor already set by stampCursor', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.stampCursor('callLogs', 42);
      await dao.stampWarm('callLogs', DateTime.fromMillisecondsSinceEpoch(1800000000000));

      final row = await dao.read('callLogs');
      expect(row!.cursor, 42);
      expect(row.lastSyncTime, 1800000000000);
    });

    test('stampCursor advancing again overwrites the prior cursor value', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.stampCursor('callLogs', 42);
      await dao.stampCursor('callLogs', 99);

      final row = await dao.read('callLogs');
      expect(row!.cursor, 99);
    });

    test('different entities are independent', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      await dao.stampCursor('callLogs', 42);
      await dao.stampWarm('worklist', DateTime.fromMillisecondsSinceEpoch(1700000000000));

      expect((await dao.read('callLogs'))!.cursor, 42);
      expect((await dao.read('worklist'))!.cursor, isNull);
    });
  });
}
