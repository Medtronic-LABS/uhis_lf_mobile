/// Unit tests for the "Session expired" fix in [AuthState.biometricUnlock] /
/// [AuthState.pinUnlock]: a genuinely expired persisted reentry session must
/// clear `biometricEnabled`/`pinEnabled` (so the router redirects cleanly to
/// `/login` instead of a stuck fingerprint/PIN retry loop) and must NEVER
/// wipe local offline data — only ask the user to sign in again.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';
import 'package:uhis_next/core/constants/app_strings.dart';

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(_values);
}

/// Simulates a genuinely expired local reentry session (e.g. the SK returns
/// to the app more than an hour after their last login).
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(super.api);

  @override
  Future<bool> restorePersistedSession() async => false;

  @override
  Future<bool> verifyPin(String pin) async => true;
}

/// Bypasses the real `local_auth` platform channel, which isn't available
/// under `flutter_test`.
class _AlwaysSucceedsBiometricService extends BiometricService {
  @override
  Future<bool> authenticate({String? reason}) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemorySecureStorage fakeStorage;
  late _FakeAuthRepository repo;
  late _AlwaysSucceedsBiometricService biometric;

  setUp(() async {
    fakeStorage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = fakeStorage;
    repo = _FakeAuthRepository(await ApiClient.create());
    biometric = _AlwaysSucceedsBiometricService();
  });

  test(
      'biometricUnlock on an expired restore signs out, clears reentry flags, '
      'and never wipes local data', () async {
    fakeStorage._values['biometric_enabled'] = 'true';

    var wipeCalled = false;
    final authState = AuthState(
      repo,
      biometric,
      onWipeLocalData: () async {
        wipeCalled = true;
      },
    );
    await authState.bootstrap();
    expect(authState.biometricEnabled, isTrue, reason: 'sanity check on seeded state');

    final ok = await authState.biometricUnlock();

    expect(ok, isFalse);
    expect(authState.error, AuthStrings.savedSessionExpired);
    expect(authState.biometricEnabled, isFalse);
    expect(authState.pinEnabled, isFalse);
    expect(authState.status, AuthStatus.signedOut);
    expect(authState.locked, isFalse);
    expect(wipeCalled, isFalse,
        reason: 'a session-expiry forced re-login must never wipe local data');
  });

  test(
      'pinUnlock on an expired restore signs out, clears reentry flags, and '
      'never wipes local data', () async {
    fakeStorage._values['pin_enabled'] = 'true';
    fakeStorage._values['pin_length'] = '4';

    var wipeCalled = false;
    final authState = AuthState(
      repo,
      biometric,
      onWipeLocalData: () async {
        wipeCalled = true;
      },
    );
    await authState.bootstrap();
    expect(authState.pinEnabled, isTrue, reason: 'sanity check on seeded state');

    final ok = await authState.pinUnlock('1234');

    expect(ok, isFalse);
    expect(authState.error, AuthStrings.savedSessionExpired);
    expect(authState.biometricEnabled, isFalse);
    expect(authState.pinEnabled, isFalse);
    expect(authState.status, AuthStatus.signedOut);
    expect(authState.locked, isFalse);
    expect(wipeCalled, isFalse,
        reason: 'a session-expiry forced re-login must never wipe local data');
  });
}
