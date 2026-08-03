/// Regression coverage for gap-analysis finding #1: a household/member the
/// server marks `'Failed'` must be retrievable again via `includeFailed`
/// (Manual/Initial sync), and counted separately via `getFailedCount()` so it
/// doesn't just silently vanish from the pending count.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/household_dao.dart';
import 'package:uhis_next/core/db/member_dao.dart';

Future<AppDatabase> _openInMemoryDb() async {
  // singleInstance: false — otherwise sqflite_ffi caches connections by path,
  // and every ":memory:" open in the same test process returns the SAME
  // cached database, leaking rows across tests instead of starting fresh.
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

  group('HouseholdDao — Failed status handling', () {
    late AppDatabase db;
    late HouseholdDao dao;

    setUp(() async {
      db = await _openInMemoryDb();
      dao = HouseholdDao(db);
    });

    test('Failed households are excluded from getUnsynced/getUnsyncedCount by default', () async {
      await dao.insertLocal(const HouseholdEntity(id: '', syncStatus: 'NotSynced'));
      await dao.insertLocal(const HouseholdEntity(id: '', syncStatus: 'Failed'));

      expect(await dao.getUnsyncedCount(), 1);
      final rows = await dao.getUnsynced();
      expect(rows, hasLength(1));
      expect(rows.single.syncStatus, 'NotSynced');
    });

    test('includeFailed:true recovers Failed households for Manual/Initial sync', () async {
      await dao.insertLocal(const HouseholdEntity(id: '', syncStatus: 'NotSynced'));
      await dao.insertLocal(const HouseholdEntity(id: '', syncStatus: 'Failed'));

      expect(await dao.getUnsyncedCount(includeFailed: true), 2);
      final rows = await dao.getUnsynced(includeFailed: true);
      expect(rows.map((r) => r.syncStatus), containsAll(['NotSynced', 'Failed']));
    });

    test('getFailedCount reports Failed rows regardless of includeFailed', () async {
      await dao.insertLocal(const HouseholdEntity(id: '', syncStatus: 'NotSynced'));
      await dao.insertLocal(const HouseholdEntity(id: '', syncStatus: 'Failed'));
      await dao.insertLocal(const HouseholdEntity(id: '', syncStatus: 'Failed'));

      expect(await dao.getFailedCount(), 2);
    });
  });

  group('MemberDao — Failed status handling', () {
    late AppDatabase db;
    late MemberDao dao;

    setUp(() async {
      db = await _openInMemoryDb();
      dao = MemberDao(db);
    });

    test('getOtherUnsyncedMembers excludes Failed by default, includes with includeFailed:true', () async {
      await dao.insertLocal(const HouseholdMemberEntity(id: '', syncStatus: 'NotSynced'));
      await dao.insertLocal(const HouseholdMemberEntity(id: '', syncStatus: 'Failed'));

      final defaultRows = await dao.getOtherUnsyncedMembers();
      expect(defaultRows, hasLength(1));
      expect(defaultRows.single.syncStatus, 'NotSynced');

      final withFailed = await dao.getOtherUnsyncedMembers(includeFailed: true);
      expect(withFailed, hasLength(2));
    });

    test('getFailedCount reports Failed member rows', () async {
      await dao.insertLocal(const HouseholdMemberEntity(id: '', syncStatus: 'NotSynced'));
      await dao.insertLocal(const HouseholdMemberEntity(id: '', syncStatus: 'Failed'));

      expect(await dao.getFailedCount(), 1);
    });
  });
}
