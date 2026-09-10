import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/member_dao.dart';

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
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v45 migration adds deceased_reason column', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE ${AppDatabase.tableMembers} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        is_active INTEGER,
        sync_status TEXT
      )''');

    await AppDatabase.onUpgrade(db, 44, AppDatabase.schemaVersion);

    final cols = await db.rawQuery(
      'PRAGMA table_info(${AppDatabase.tableMembers})',
    );
    expect(
      cols.map((c) => c['name']),
      contains('deceased_reason'),
    );
    await db.close();
  });

  test('updateMemberDeceasedReason persists inactive + reason + NotSynced',
      () async {
    final db = await _openInMemoryDb();
    final dao = MemberDao(db);
    final id = await dao.insertLocal(
      const HouseholdMemberEntity(
        id: '0',
        name: 'Test Member',
        isActive: true,
        syncStatus: 'Success',
      ),
    );

    await dao.updateMemberDeceasedReason(
      id,
      isActive: false,
      deceasedReason: '__mother__:infection',
    );

    final row = await dao.getById(id);
    expect(row, isNotNull);
    expect(row!.isActive, isFalse);
    expect(row.deceasedReason, '__mother__:infection');
    expect(row.syncStatus, 'NotSynced');

    await db.close();
  });
}
