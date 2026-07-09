/// Unit tests for the [OfflineSyncService.coldSync] `wipeBeforeSync` gate —
/// GitHub issue #37. Scoped narrowly to the wipe-gate behavior itself: the
/// fake [AuthRepository.userId] returns null, so `_runSync` fails fast right
/// after the wipe check and before any real network call — no HTTP mocking
/// library is a dependency of this project, so exercising the full sync
/// payload pipeline is out of scope here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/assessment_dao.dart';
import 'package:uhis_next/core/db/follow_up_dao.dart';
import 'package:uhis_next/core/db/immunisation_dao.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/core/db/patient_programmes_dao.dart';
import 'package:uhis_next/core/db/sync_meta_dao.dart';
import 'package:uhis_next/core/sync/offline_sync_service.dart';

class _NoUserIdAuthRepository extends AuthRepository {
  _NoUserIdAuthRepository(super.api);

  @override
  Future<int?> userId() async => null;
}

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
  late OfflineSyncService sync;

  setUp(() async {
    db = await _openInMemoryDb();
    final auth = _NoUserIdAuthRepository(await ApiClient.create());
    sync = OfflineSyncService(
      api: await ApiClient.create(),
      auth: auth,
      db: db,
      patients: PatientDao(db),
      programmes: PatientProgrammesDao(db),
      followUps: FollowUpDao(db),
      immunisations: ImmunisationDao(db),
      assessments: AssessmentDao(db),
      syncMeta: SyncMetaDao(db),
    );
    // Seed one row so a wipe is observable.
    await db.db.insert(AppDatabase.tableHouseholds, {'id': 'hh-seed'});
  });

  tearDown(() async {
    await db.close();
  });

  test('coldSync(wipeBeforeSync: true) wipes local data even though sync '
      'itself fails fast (no userId)', () async {
    final report = await sync.coldSync(wipeBeforeSync: true);

    expect(report.errors, isNotEmpty,
        reason: 'no userId — sync should fail fast, not touch network');
    final rows = await db.db.query(AppDatabase.tableHouseholds);
    expect(rows, isEmpty, reason: 'wipeBeforeSync must run before the userId check');
  });

  test('coldSync() (default) never wipes local data', () async {
    await sync.coldSync();

    final rows = await db.db.query(AppDatabase.tableHouseholds);
    expect(rows, isNotEmpty,
        reason: 'plain coldSync() must never truncate local data');
  });

  test('warmSync() never wipes local data', () async {
    await sync.warmSync();

    final rows = await db.db.query(AppDatabase.tableHouseholds);
    expect(rows, isNotEmpty,
        reason: 'warmSync() must never truncate local data');
  });
}
