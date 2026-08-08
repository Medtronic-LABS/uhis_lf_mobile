/// Unit tests for the soft-logout credential contract in [AuthRepository].
///
/// Sign-out no longer wipes the local database, which only stays safe while a
/// device remains bound to one SK. That binding is the locked username field in
/// LoginScreen, and it is fed by the username this layer must now preserve
/// across logout. The stored password hash is preserved for the same reason —
/// an SK who logs out while offline still has to be able to get back in to
/// their unsynced work.
///
/// The explicit-logout flag is what stops the silent 401 recovery in
/// [AuthState] from quietly undoing a deliberate sign-out using those very
/// same retained credentials.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> values = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      values[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(values);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemorySecureStorage fakeStorage;
  late AuthRepository repo;

  setUp(() async {
    fakeStorage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = fakeStorage;
    repo = AuthRepository(await ApiClient.create());
  });

  /// State a device is in after one successful online login.
  void seedSignedInDevice() {
    fakeStorage.values['lastUsername'] = 'sk_one';
    fakeStorage.values['offline_pwd_hash'] = 'hashed-pwd-value';
    fakeStorage.values['tenantId'] = '42';
    fakeStorage.values['biometric_enabled'] = 'true';
  }

  test('logout keeps the username so the login field stays locked to this SK',
      () async {
    seedSignedInDevice();

    await repo.logout();

    expect(await repo.lastUsername(), 'sk_one',
        reason: 'the locked username field is what binds this device to one SK');
    expect(await repo.isReturningUser('sk_one'), isTrue);
  });

  test('logout keeps the stored password hash for offline re-login', () async {
    seedSignedInDevice();

    await repo.logout();

    expect(fakeStorage.values['offline_pwd_hash'], 'hashed-pwd-value',
        reason: 'an SK logging out offline must still be able to log back in');
    expect(await repo.verifyOfflinePassword('sk_one', 'wrong-password'), isFalse,
        reason: 'retaining the hash must not weaken verification');
  });

  test('logout clears session and re-entry material', () async {
    seedSignedInDevice();
    fakeStorage.values['bio_auth_token'] = 'token';
    fakeStorage.values['bio_jsessionid'] = 'jsession';

    await repo.logout();

    expect(fakeStorage.values['tenantId'], isNull);
    expect(fakeStorage.values['bio_auth_token'], isNull);
    expect(fakeStorage.values['bio_jsessionid'], isNull);
    expect(fakeStorage.values['biometric_enabled'], isNull,
        reason: 'password entry is required after an explicit sign-out');
  });

  test('logout marks the sign-out explicit so silent recovery stays disarmed',
      () async {
    seedSignedInDevice();
    expect(await repo.wasExplicitLogout(), isFalse);

    await repo.logout();

    expect(await repo.wasExplicitLogout(), isTrue);
  });

  test('session expiry does NOT mark the sign-out explicit', () async {
    seedSignedInDevice();

    await repo.handleSessionExpired();

    expect(await repo.wasExplicitLogout(), isFalse,
        reason: 'expiry must remain silently recoverable; only logout is not');
    expect(await repo.lastUsername(), 'sk_one');
  });

  test('loginWithStoredCredentials fails fast when nothing is stored',
      () async {
    // No seeded credentials — must not reach the network.
    expect(repo.loginWithStoredCredentials(), throwsA(isA<Exception>()));
  });
}
