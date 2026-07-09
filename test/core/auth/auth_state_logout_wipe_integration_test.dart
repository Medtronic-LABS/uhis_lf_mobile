/// Integration test for the truncate-on-logout wiring — GitHub issue #37.
///
/// [auth_state_logout_wipe_test.dart] proves `AuthState.logout()` invokes
/// whatever `onWipeLocalData` callback it's given, using a fake callback.
/// [app_database_wipe_test.dart] proves `AppDatabase.wipeAllData()` truncates
/// every table, calling it directly. Neither exercises the two together the
/// way `main.dart` actually wires them
/// (`onWipeLocalData: appDb.wipeAllData`) — this test closes that gap by
/// driving a real in-memory [AppDatabase] through the real
/// [AuthState.logout] path.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';
import 'package:uhis_next/core/db/app_database.dart';

/// Bypasses the real network/secure-storage logout implementation so this
/// test can isolate the DB-wipe wiring, mirroring the fake used in
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

  setUp(() async {
    db = await _openInMemoryDb();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Seed rows across a representative spread of tables — household/member
    // data, sync bookkeeping, and a visit-capture table — so the assertion
    // below proves a real cross-table wipe, not a single-table coincidence.
    await db.db.insert(AppDatabase.tableHouseholds, {'id': 'hh-1'});
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
      onWipeLocalData: db.wipeAllData,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
      'AuthState.logout() drives a real AppDatabase.wipeAllData() and '
      'truncates every table', () async {
    for (final table in [
      AppDatabase.tableHouseholds,
      AppDatabase.tablePatients,
      AppDatabase.tableSyncMeta,
      AppDatabase.tableEncounters,
    ]) {
      final rows = await db.db.query(table);
      expect(rows, isNotEmpty, reason: '$table should be seeded before logout');
    }

    await authState.logout();

    for (final table in AppDatabase.allTablesForTesting) {
      final rows = await db.db.query(table);
      expect(rows, isEmpty, reason: '$table must be empty after logout()');
    }
    expect(authState.status, AuthStatus.signedOut);
  });
}
