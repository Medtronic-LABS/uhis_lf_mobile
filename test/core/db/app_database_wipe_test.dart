/// Unit tests for [AppDatabase.wipeAllData] — the truncate-on-logout /
/// truncate-on-online-login mechanism for GitHub issue #37.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';

Future<AppDatabase> _openInMemoryDb() async {
  final rawDb = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppDatabase.schemaVersion,
      onCreate: AppDatabase.createSchema,
    ),
  );
  return AppDatabase.forTesting(rawDb);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;

  setUp(() async {
    db = await _openInMemoryDb();
  });

  tearDown(() async {
    await db.close();
  });

  test('wipeAllData truncates every table, schema stays intact', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.db.insert(AppDatabase.tableHouseholds, {'id': 'hh-1'});
    await db.db.insert(AppDatabase.tableSyncMeta, {
      'entity': 'worklist',
      'last_sync_time': now,
      'last_full_sync_at': now,
    });
    await db.db.insert(AppDatabase.tableAiResponseCache, {
      'cache_key': 'k-1',
      'kind': 'programme-reco',
      'content_hash': 'h',
      'payload': '{}',
      'created_at': now,
      'expires_at': now + 1000,
    });
    await db.db.insert(AppDatabase.tableCoachingProgress, {
      'module_id': 'm-1',
      'updated_at': now,
    });

    for (final table in [
      AppDatabase.tableHouseholds,
      AppDatabase.tableSyncMeta,
      AppDatabase.tableAiResponseCache,
      AppDatabase.tableCoachingProgress,
    ]) {
      final rows = await db.db.query(table);
      expect(rows, isNotEmpty, reason: '$table should be seeded before wipe');
    }

    await db.wipeAllData();

    for (final table in AppDatabase.allTablesForTesting) {
      final rows = await db.db.query(table);
      expect(rows, isEmpty, reason: '$table must be empty after wipeAllData()');
    }
  });

  test('wipeAllData leaves the schema queryable (tables not dropped)',
      () async {
    await db.wipeAllData();

    // A query against every table must succeed (no "no such table" error) —
    // proves wipeAllData() deletes rows, not the tables themselves.
    for (final table in AppDatabase.allTablesForTesting) {
      await expectLater(db.db.query(table), completes);
    }
  });
}
