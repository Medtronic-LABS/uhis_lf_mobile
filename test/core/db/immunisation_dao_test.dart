import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/immunisation_dao.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase appDb;
  late ImmunisationDao dao;

  setUp(() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    appDb = AppDatabase.forTesting(raw);
    dao = ImmunisationDao(appDb);
  });

  tearDown(() => appDb.close());

  test(
      'fresh-install schema includes status, missed_reason and '
      'referral_facility columns', () async {
    final columns =
        await appDb.db.rawQuery('PRAGMA table_info(${AppDatabase.tableImmunisations})');
    final names = columns.map((c) => c['name'] as String).toSet();
    expect(names, containsAll(['status', 'missed_reason', 'referral_facility']));
  });

  test('status/missedReason round-trip through upsertMany/forMany', () async {
    await dao.upsertMany([
      const ImmunisationRow(
        id: 'p1_BCG',
        patientId: 'p1',
        vaccineCode: 'BCG',
        status: 'Missed',
        missedReason: 'Child was sick on scheduled date',
        rawJson: '{}',
      ),
    ]);

    final rows = await dao.forMany(['p1']);
    final row = rows['p1']!.single;

    expect(row.status, 'Missed');
    expect(row.missedReason, 'Child was sick on scheduled date');
  });

  test('referralFacility round-trips through upsertMany/forMany', () async {
    await dao.upsertMany([
      const ImmunisationRow(
        id: 'p1_BCG',
        patientId: 'p1',
        vaccineCode: 'BCG',
        status: 'Missed',
        missedReason: 'Child was sick on scheduled date',
        referralFacility: 'Upazila Health Complex',
        rawJson: '{}',
      ),
    ]);

    final rows = await dao.forMany(['p1']);
    final row = rows['p1']!.single;

    expect(row.referralFacility, 'Upazila Health Complex');
  });
}
