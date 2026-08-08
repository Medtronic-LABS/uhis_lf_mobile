/// Tests the in-memory half of the soft-logout contract in [AuthState].
///
/// Sign-out no longer wipes the local database, so the device keeps one SK's
/// households, patients and clinical records. The only thing stopping a second
/// SK from signing in and inheriting them is the prefilled-and-disabled username
/// field on the login screen — and that field reads [AuthState.username].
/// `logout()` used to null it, which would unlock the field.
///
/// [auth_repository_soft_logout_test.dart] covers the persisted half (the
/// username and password hash surviving in secure storage).
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';

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

/// Keeps the test off the network and off the real secure-storage teardown so
/// it isolates AuthState's own orchestration.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(super.api);

  bool logoutCalled = false;

  @override
  Future<bool> restorePersistedSession() async => false;

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

/// Bypasses the real `local_auth` platform channel, unavailable under
/// flutter_test.
class _NoBiometricService extends BiometricService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate({String? reason}) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemorySecureStorage fakeStorage;
  late _FakeAuthRepository repo;

  setUp(() async {
    fakeStorage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = fakeStorage;
    repo = _FakeAuthRepository(await ApiClient.create());
  });

  test('logout keeps username in memory so the login field stays locked',
      () async {
    fakeStorage.values['lastUsername'] = 'sk_one';
    final authState = AuthState(repo, _NoBiometricService());
    await authState.bootstrap();
    expect(authState.username, 'sk_one', reason: 'sanity check on seeded state');

    await authState.logout();

    expect(repo.logoutCalled, isTrue);
    expect(authState.status, AuthStatus.signedOut);
    expect(authState.username, 'sk_one',
        reason: 'LoginScreen disables the username field on this value — '
            'clearing it would let a second SK sign in and inherit the '
            'previous SK\'s retained patient records');
  });

  test('logout clears re-entry so the password is required to come back',
      () async {
    fakeStorage.values['lastUsername'] = 'sk_one';
    fakeStorage.values['biometric_enabled'] = 'true';
    final authState = AuthState(repo, _NoBiometricService());
    await authState.bootstrap();

    await authState.logout();

    expect(authState.biometricEnabled, isFalse);
    expect(authState.pinEnabled, isFalse);
    expect(authState.reentryEnabled, isFalse,
        reason: 'a soft logout must still demand the password, not a PIN tap');
  });
}
