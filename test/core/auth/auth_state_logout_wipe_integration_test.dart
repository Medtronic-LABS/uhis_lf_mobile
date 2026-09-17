/// Integration test: logout keeps the local offline DB (UHIS parity).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';
import 'package:uhis_next/core/db/app_database.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(super.api);

  @override
  Future<void> logout({bool online = true}) async {}

  @override
  Future<String?> lastUsername() async => null;

  @override
  Future<bool> isBiometricEnabled() async => false;

  @override
  Future<bool> isPinSet() async => false;
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

    // sync_meta.lastSyncTime is the cursor used for delta re-sync after logout.
    await db.db.insert(AppDatabase.tableSyncMeta, {
      'entity': 'worklist',
      'last_sync_time': now,
      'last_full_sync_at': now,
    });
    await db.db.insert(AppDatabase.tableSyncMeta, {
      'entity': 'assessment_history',
      'last_sync_time': now,
      'last_full_sync_at': now,
    });

    authState = AuthState(
      _FakeAuthRepository(await ApiClient.create()),
      BiometricService(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('AuthState.logout() does not truncate local offline data', () async {
    final before = await db.db.query(AppDatabase.tableSyncMeta);
    expect(before, isNotEmpty);

    await authState.logout();

    final after = await db.db.query(AppDatabase.tableSyncMeta);
    expect(after, equals(before),
        reason: 'sync_meta must survive logout for UHIS-parity delta sync');
    expect(authState.status, AuthStatus.signedOut);
  });
}
