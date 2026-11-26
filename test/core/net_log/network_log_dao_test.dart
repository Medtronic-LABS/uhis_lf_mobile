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
}) => NetworkLogEntry(
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
      final newest = await dao.page(limit: 1, offset: 0);
      final oldest = await dao.page(limit: 1, offset: 1999);
      expect(newest.single.startedAtMs, 2049);
      expect(oldest.single.startedAtMs, 50);
    });

    test(
      'page orders newest first, filters by service and honours offset',
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
      },
    );

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

    test(
      'mergeNative dedupes on (native_id, started_at_ms) and honours floor',
      () async {
        final (db, dao) = await open();
        addTearDown(db.close);
        await db.db.update(
          AppDatabase.tableSyncMeta,
          {'last_sync_time': 100},
          where: 'entity = ?',
          whereArgs: [AppDatabase.networkLogNativeEntity],
        );
        final batch = [
          _e(100, source: 'native', nativeId: 1),
          _e(200, source: 'native', nativeId: 2),
          _e(50, source: 'native', nativeId: 3),
        ];

        expect(await dao.mergeNative(batch), 2);
        expect(await dao.mergeNative(batch), 0);
        // Same native id with a different timestamp is a different row.
        expect(
          await dao.mergeNative([_e(300, source: 'native', nativeId: 1)]),
          1,
        );
        expect(await dao.page(limit: 10, offset: 0), hasLength(3));
      },
    );

    test(
      'mergeNative forces source native and skips far-future rows',
      () async {
        final (db, dao) = await open();
        addTearDown(db.close);
        final now = DateTime.now().millisecondsSinceEpoch;

        final n = await dao.mergeNative([
          _e(now, source: 'dart', nativeId: 1),
          _e(now + 3600000, source: 'native', nativeId: 2),
        ]);

        expect(n, 1);
        final rows = await db.db.query(AppDatabase.tableNetworkLog);
        expect(rows.single['source'], 'native');
      },
    );

    test('mergeNative accepts a row at the max future skew and rejects one past it',
        () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      final before = DateTime.now().millisecondsSinceEpoch;

      // The DAO reads its own clock (no seam), so exact 1 ms is not testable:
      // 'before' is never later than that clock, 'now + 1 s' never earlier.
      final accepted = await dao.mergeNative([
        _e(before + NetworkLogDao.maxFutureSkewMs, source: 'native', nativeId: 1),
      ]);
      final rejected = await dao.mergeNative([
        _e(
          DateTime.now().millisecondsSinceEpoch +
              NetworkLogDao.maxFutureSkewMs +
              1000,
          source: 'native',
          nativeId: 2,
        ),
      ]);

      expect(accepted, 1);
      expect(rejected, 0);
    });

    test(
      'mergeNative caps a call at 200 rows and keeps Dart history',
      () async {
        final (db, dao) = await open();
        addTearDown(db.close);
        for (var s = 0; s < 1900; s += 50) {
          await dao.insertBatch([for (var i = s; i < s + 50; i++) _e(i)]);
        }

        final n = await dao.mergeNative([
          for (var i = 0; i < 300; i++)
            _e(10000 + i, source: 'native', nativeId: i),
        ]);

        expect(n, 200);
        final counts = await db.db.rawQuery(
          'SELECT source, COUNT(*) c FROM ${AppDatabase.tableNetworkLog} '
          'GROUP BY source',
        );
        final bySource = {for (final r in counts) r['source']: r['c']};
        expect(bySource['native'], 200);
        expect(bySource['dart'], 1800);
      },
    );

    test(
      'mergeNative cursorTo only updates the cursor, even backwards',
      () async {
        final (db, dao) = await open();
        addTearDown(db.close);
        await db.db.update(
          AppDatabase.tableSyncMeta,
          {'last_sync_time': 77},
          where: 'entity = ?',
          whereArgs: [AppDatabase.networkLogNativeEntity],
        );

        await dao.mergeNative(const [], cursorTo: 42);
        expect(await dao.nativeState(), (cursor: 42, floorMs: 77));
        await dao.mergeNative(const [], cursorTo: 0);
        expect(await dao.nativeState(), (cursor: 0, floorMs: 77));
      },
    );

    test('a merge using pre-wipe state cannot undo the wipe floor', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      final stale = await dao.nativeState();
      expect(stale.floorMs, 0);

      final before = DateTime.now().millisecondsSinceEpoch;
      await db.wipeAllData();
      final oldEvent = _e(before - 10000, source: 'native', nativeId: 5);

      final n = await dao.mergeNative([oldEvent], cursorTo: 99);

      expect(n, 0);
      expect(await db.db.query(AppDatabase.tableNetworkLog), isEmpty);
      final state = await dao.nativeState();
      expect(state.floorMs, greaterThanOrEqualTo(before));
    });

    test('error_type keeps only allowlisted names', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      NetworkLogEntry withType(int t, String type) => NetworkLogEntry(
        startedAtMs: t,
        source: 'dart',
        service: 'core',
        method: 'GET',
        url: 'https://example.test/a',
        errorType: type,
      );
      await dao.insertBatch([
        withType(1, 'connectionTimeout'),
        withType(2, 'wsError'),
        withType(3, 'SocketException'),
        withType(4, 'HttpRequestFailed'),
      ]);

      final rows = await db.db.query(
        AppDatabase.tableNetworkLog,
        orderBy: 'started_at_ms',
      );
      expect(rows.map((r) => r['error_type']), [
        'connectionTimeout',
        'wsError',
        'unknown',
        'unknown',
      ]);
    });

    test('write path sanitises urls and normalises text fields', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      await dao.insertBatch([
        NetworkLogEntry(
          startedAtMs: 1,
          source: 'native',
          service: 'Bad Service!',
          method: 'GET /x',
          url: 'https://user:pw@example.test/a/jane@example.org?token=abc',
          finalUrl: 'https://example.test/a/jane@example.org?token=abc',
          timing: 'whatever',
          errorType: 'SocketException: Failed host lookup',
        ),
      ]);

      final row = (await db.db.query(AppDatabase.tableNetworkLog)).single;
      expect(row['source'], 'dart');
      expect(row['service'], 'other');
      expect(row['method'], 'UNKNOWN');
      expect(row['timing'], 'total');
      expect(row['error_type'], 'unknown');
      expect(row['url'], 'https://example.test/a/{id}');
      expect(row['final_url'], 'https://example.test/a/{id}');
    });

    test('write path caps an over-long final url at 2048 characters', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      await dao.insertBatch([
        NetworkLogEntry(
          startedAtMs: 1,
          source: 'dart',
          service: 'core',
          method: 'GET',
          url: 'https://example.test/x',
          finalUrl: 'https://example.test/${'a' * 5000}',
        ),
      ]);

      final row = (await db.db.query(AppDatabase.tableNetworkLog)).single;
      expect((row['final_url'] as String).length, lessThanOrEqualTo(2048));
    });

    test('insertBatch runs one transaction per chunk of 50 rows', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      var checks = 0;

      await dao.insertBatch(
        [for (var i = 0; i < 120; i++) _e(i)],
        isCurrent: () {
          checks++;
          return true;
        },
      );

      expect(checks, 3, reason: 'isCurrent is re-checked per chunk transaction');
      expect(await db.db.query(AppDatabase.tableNetworkLog), hasLength(120));
    });

    test('a wipe between chunks stops the remaining chunks', () async {
      final (db, dao) = await open();
      addTearDown(db.close);
      var checks = 0;

      await dao.insertBatch(
        [for (var i = 0; i < 120; i++) _e(i)],
        isCurrent: () => ++checks == 1,
      );

      expect(await db.db.query(AppDatabase.tableNetworkLog), hasLength(50));
    });

    test(
      'insertBatch ignores duplicate native keys and chunks big batches',
      () async {
        final (db, dao) = await open();
        addTearDown(db.close);
        await dao.insertBatch([
          for (var i = 0; i < 120; i++) _e(i),
          _e(500, source: 'native', nativeId: 1),
          _e(500, source: 'native', nativeId: 1),
        ]);

        expect(await db.db.query(AppDatabase.tableNetworkLog), hasLength(122));
      },
    );

    test(
      'page and newest clamp negative or oversized limit and offset',
      () async {
        final (db, dao) = await open();
        addTearDown(db.close);
        await dao.insertBatch([_e(1), _e(2), _e(3)]);

        expect(await dao.page(limit: -1, offset: 0), isEmpty);
        expect((await dao.page(limit: 10, offset: -5)).length, 3);
        expect(await dao.newest(-1), isEmpty);
      },
    );

    test(
      'nativeState defaults to cursor 0 and floor 0 on a fresh install',
      () async {
        final (db, dao) = await open();
        addTearDown(db.close);

        expect(await dao.nativeState(), (cursor: 0, floorMs: 0));
      },
    );

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
      await dao.mergeNative(const [], cursorTo: 9);

      final before = DateTime.now().millisecondsSinceEpoch;
      await dao.clear();

      expect(await dao.page(limit: 10, offset: 0), isEmpty);
      final state = await dao.nativeState();
      expect(state.floorMs, greaterThanOrEqualTo(before));
      expect(state.cursor, 9);
    });
  });
}
