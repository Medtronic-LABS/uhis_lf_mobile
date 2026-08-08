/// Integration test for the soft-logout contract.
///
/// Sign-out used to truncate every local table (GitHub issue #37). It no longer
/// does: an SK who logs out — especially offline, with work that has not
/// reached the backend — must still find that work on the device when they log
/// back in. Clearing local data is Android Settings → Clear Data.
///
/// This drives a real in-memory [AppDatabase] through the real
/// [AuthState.logout] path, wired exactly as `main.dart` wires it
/// (`onWipeLocalData: appDb.wipeAllData`), and asserts the callback is NOT
/// invoked even though it is still supplied.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';
import 'package:uhis_next/core/db/app_database.dart';

/// Bypasses the real network/secure-storage logout implementation so this
/// test can isolate the DB wiring, mirroring the fake used in
/// auth_state_logout_wipe_test.dart.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(super.api);

  @override
  Future<void> logout() async {}
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late AuthState authState;
  late bool wipeInvoked;

  const seededTables = [
    AppDatabase.tableHouseholds,
    AppDatabase.tablePatients,
    AppDatabase.tableSyncMeta,
    AppDatabase.tableEncounters,
  ];

  setUp(() async {
    db = await _openInMemoryDb();
    wipeInvoked = false;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Seed a representative spread — household/member data, sync bookkeeping,
    // and a visit-capture table — so the assertion below proves data survives
    // across table kinds, not by single-table coincidence.
    // households.id is INTEGER PRIMARY KEY AUTOINCREMENT — seeding it with a
    // string is a datatype mismatch, not a valid row.
    await db.db.insert(AppDatabase.tableHouseholds, {'id': 1});
    await db.db.insert(AppDatabase.tablePatients, {'id': 'pt-1'});
    await db.db.insert(AppDatabase.tableSyncMeta, {
      'entity': 'worklist',
      'last_sync_time': now,
      'last_full_sync_at': now,
    });
    await db.db.insert(AppDatabase.tableEncounters, {
      'id': 'enc-1',
      'patient_id': 'pt-1',
      'programme': 'anc',
      'started_at': now,
    });

    final repo = _FakeAuthRepository(await ApiClient.create());
    authState = AuthState(
      repo,
      BiometricService(),
      // Still supplied, exactly as main.dart supplies it. logout() must not
      // call it — restoring the wipe should be a deliberate one-line change,
      // not an accident of wiring.
      onWipeLocalData: () async {
        wipeInvoked = true;
        await db.wipeAllData();
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('logout() signs out without truncating local data', () async {
    for (final table in seededTables) {
      expect(await db.db.query(table), isNotEmpty,
          reason: '$table should be seeded before logout');
    }

    await authState.logout();

    expect(authState.status, AuthStatus.signedOut);
    expect(wipeInvoked, isFalse,
        reason: 'soft logout must not invoke the local-data wipe');
    for (final table in seededTables) {
      expect(await db.db.query(table), isNotEmpty,
          reason: '$table must survive logout so unsynced work is not lost');
    }
  });

}
// Username/credential preservation across logout is asserted at the layer that
// owns it — see auth_repository_soft_logout_test.dart.
