/// Unit tests for the sliding-window reentry-session TTL renewal —
/// [AuthRepository.touchReentryExpiry] — which fixes the false "Session
/// expired" reported after the app sits idle for a while.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';

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

void main() {
  late _InMemorySecureStorage fakeStorage;
  late ApiClient api;
  late AuthRepository repo;

  setUp(() async {
    fakeStorage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = fakeStorage;
    api = await ApiClient.create();
    repo = AuthRepository(api);
  });

  test(
      'touchReentryExpiry extends the stored expiry for the mobile Bearer-token flow',
      () async {
    fakeStorage._values['biometric_enabled'] = 'true';
    fakeStorage._values['bio_authcookie_expiry'] =
        DateTime(2000).toIso8601String();

    await repo.touchReentryExpiry();

    final updated = fakeStorage._values['bio_authcookie_expiry'];
    expect(updated, isNotNull);
    expect(DateTime.parse(updated!).isAfter(DateTime(2000)), isTrue);
  });

  test('a second call within the throttle window is a no-op', () async {
    fakeStorage._values['biometric_enabled'] = 'true';
    fakeStorage._values['bio_authcookie_expiry'] =
        DateTime(2000).toIso8601String();

    await repo.touchReentryExpiry();
    final firstWrite = fakeStorage._values['bio_authcookie_expiry'];

    await repo.touchReentryExpiry();
    final secondWrite = fakeStorage._values['bio_authcookie_expiry'];

    expect(secondWrite, firstWrite,
        reason:
            'throttle window has not elapsed — second touch must not write again');
  });

  test('a real cookie-issued expiry (web flow) is never overridden',
      () async {
    fakeStorage._values['biometric_enabled'] = 'true';
    final originalExpiry = DateTime(2030);
    fakeStorage._values['bio_authcookie_expiry'] =
        originalExpiry.toIso8601String();
    await api.importAuthCookies(
      jsession: 'js',
      authCookie: 'ac',
      authCookieExpiry: originalExpiry,
    );

    await repo.touchReentryExpiry();

    expect(fakeStorage._values['bio_authcookie_expiry'],
        originalExpiry.toIso8601String());
  });

  test('no-op when reentry is not enabled', () async {
    fakeStorage._values['bio_authcookie_expiry'] =
        DateTime(2000).toIso8601String();

    await repo.touchReentryExpiry();

    expect(fakeStorage._values['bio_authcookie_expiry'],
        DateTime(2000).toIso8601String());
  });
}
