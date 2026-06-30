/// Unit tests for [AiResponseCacheDao].
///
/// Pins the contract every AI repo relies on:
///   - put() then get() with the matching hash returns the row.
///   - get() with a mismatched hash returns null AND drops the stale row.
///   - Expired rows are not surfaced and are deleted on lookup.
///   - invalidateKind() removes only entries of that kind.
///   - purgeExpired() returns the deletion count.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/ai_response_cache_dao.dart';
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
  late AiResponseCacheDao dao;

  setUp(() async {
    db = await _openInMemoryDb();
    dao = AiResponseCacheDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('put then get with matching hash returns the cached payload', () async {
    await dao.put(
      cacheKey: 'programme-reco:p-1',
      kind: 'programme-reco',
      contentHash: 'abc',
      payload: '{"recommendations":[]}',
    );

    final cached = await dao.get('programme-reco:p-1', contentHash: 'abc');

    expect(cached, isNotNull);
    expect(cached!.payload, '{"recommendations":[]}');
    expect(cached.kind, 'programme-reco');
    expect(cached.isExpired, isFalse);
  });

  test('get with a mismatched content_hash returns null and drops the row',
      () async {
    await dao.put(
      cacheKey: 'programme-reco:p-1',
      kind: 'programme-reco',
      contentHash: 'old-hash',
      payload: '{}',
    );

    final cached = await dao.get('programme-reco:p-1', contentHash: 'new-hash');
    expect(cached, isNull,
        reason: 'mismatched hash must invalidate the cached entry');

    // Same key with the OLD hash should now also miss — DAO eagerly deleted.
    final replay = await dao.get('programme-reco:p-1', contentHash: 'old-hash');
    expect(replay, isNull, reason: 'stale row must be deleted on lookup');
  });

  test('expired entries are not surfaced and are deleted', () async {
    await dao.put(
      cacheKey: 'visit-briefing:p-2',
      kind: 'visit-briefing',
      contentHash: 'h',
      payload: '{}',
      ttl: const Duration(milliseconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final cached = await dao.get('visit-briefing:p-2', contentHash: 'h');
    expect(cached, isNull);
  });

  test('invalidateKind removes only entries of that kind', () async {
    await dao.put(
      cacheKey: 'programme-reco:p-1',
      kind: 'programme-reco',
      contentHash: 'h',
      payload: '{}',
    );
    await dao.put(
      cacheKey: 'visit-briefing:p-1',
      kind: 'visit-briefing',
      contentHash: 'h',
      payload: '{}',
    );

    await dao.invalidateKind('programme-reco');

    expect(await dao.get('programme-reco:p-1', contentHash: 'h'), isNull);
    expect(await dao.get('visit-briefing:p-1', contentHash: 'h'), isNotNull);
  });

  test('purgeExpired returns the count of deleted rows', () async {
    await dao.put(
      cacheKey: 'a',
      kind: 'x',
      contentHash: 'h',
      payload: '{}',
      ttl: const Duration(milliseconds: 1),
    );
    await dao.put(
      cacheKey: 'b',
      kind: 'x',
      contentHash: 'h',
      payload: '{}',
      ttl: const Duration(hours: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final purged = await dao.purgeExpired();
    expect(purged, 1, reason: 'only the millisecond-TTL row should expire');

    // Surviving row still resolves.
    expect(await dao.get('b', contentHash: 'h'), isNotNull);
  });
}
