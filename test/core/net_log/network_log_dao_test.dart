import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/net_log/network_log_dao.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';

NetworkLogEntry _e(
  int t, {
  String service = 'core',
  String source = 'dart',
  int? nativeId,
}) =>
    NetworkLogEntry(
      startedAtMs: t,
      source: source,
      nativeId: nativeId,
      service: service,
      method: 'GET',
      url: 'https://example.test/x/$t',
      statusCode: 200,
      durationMs: 5,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, NetworkLogDao)> open() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(raw);
    return (app, NetworkLogDao(app));
  }

  group('NetworkLogDao', () {
    test('inserting 2,050 rows keeps the newest 2,000', () async {
      final (db, dao) = await open();
      addTearDown(db.close);

      for (var s = 0; s < 2050; s += 50) {
        await dao.insertBatch([for (var i = s; i < s + 50; i++) _e(i)]);
      }

      final rows = await db.db.query(AppDatabase.tableNetworkLog);
      expect(rows.length, 2000);
      final all = await dao.page(limit: 5000, offset: 0);
      expect(all.first.startedAtMs, 2049);
      expect(all.last.startedAtMs, 50);
    });

    test('page orders newest first, filters by service and honours offset',
        () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      await dao.insertBatch([
        _e(1),
        _e(3, service: 'ai'),
        _e(2),
        _e(4, service: 'ai'),
      ]);

      final all = await dao.page(limit: 10, offset: 0);
      expect(all.map((e) => e.startedAtMs), [4, 3, 2, 1]);
      final ai = await dao.page(limit: 10, offset: 0, service: 'ai');
      expect(ai.map((e) => e.startedAtMs), [4, 3]);
      final off = await dao.page(limit: 2, offset: 1);
      expect(off.map((e) => e.startedAtMs), [3, 2]);
      final top = await dao.newest(1, service: 'core');
      expect(top.single.startedAtMs, 2);
    });

    test('countsByService groups rows', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      await dao.insertBatch([_e(1), _e(2), _e(3, service: 'ai')]);

      expect(await dao.countsByService(), {'core': 2, 'ai': 1});
    });

    test('insertBatch writes nothing when isCurrent returns false', () async {
      final (db, dao) = await open();
      addTearDown(db.close);

      await dao.insertBatch([_e(1)], isCurrent: () => false);
      expect(await dao.page(limit: 10, offset: 0), isEmpty);

      await dao.insertBatch([_e(1)], isCurrent: () => true);
      expect(await dao.page(limit: 10, offset: 0), hasLength(1));
    });

    test('mergeNative dedupes on (native_id, started_at_ms) and honours floor',
        () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      final batch = [
        _e(100, source: 'native', nativeId: 1),
        _e(200, source: 'native', nativeId: 2),
        _e(50, source: 'native', nativeId: 3),
      ];

      expect(await dao.mergeNative(batch, floorMs: 100), 2);
      expect(await dao.mergeNative(batch, floorMs: 100), 0);
      // Same native id with a different timestamp is a different row.
      expect(
          await dao.mergeNative([_e(300, source: 'native', nativeId: 1)],
              floorMs: 0),
          1);
      expect(await dao.page(limit: 10, offset: 0), hasLength(3));
    });

    test('nativeState defaults to cursor 0 and floor 0, then follows cursor',
        () async {
      final (db, dao) = await open();
      addTearDown(db.close);

      expect(await dao.nativeState(), (cursor: 0, floorMs: 0));
      await dao.setNativeCursor(42);
      expect(await dao.nativeState(), (cursor: 42, floorMs: 0));
    });

    test('nativeState treats a missing row as floor = now', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      await db.db.delete(AppDatabase.tableSyncMeta);

      final before = DateTime.now().millisecondsSinceEpoch;
      final state = await dao.nativeState();
      expect(state.cursor, 0);
      expect(state.floorMs, greaterThanOrEqualTo(before));
    });

    test('clear deletes every row and sets the floor to now', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      await dao.insertBatch([_e(1), _e(2)]);
      await dao.setNativeCursor(9);

      final before = DateTime.now().millisecondsSinceEpoch;
      await dao.clear();

      expect(await dao.page(limit: 10, offset: 0), isEmpty);
      final state = await dao.nativeState();
      expect(state.floorMs, greaterThanOrEqualTo(before));
      expect(state.cursor, 9);
    });
  });
}
