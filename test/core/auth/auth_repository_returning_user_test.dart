/// Unit tests for [AuthRepository.isReturningUser] — distinguishes a
/// same-user re-login (e.g. after a forced session-expiry sign-out, where
/// local offline data must be preserved) from a different user signing into
/// a shared device (where the previous user's stale caseload should be
/// cleared).
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
  late AuthRepository repo;

  setUp(() async {
    fakeStorage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = fakeStorage;
    repo = AuthRepository(await ApiClient.create());
  });

  test('same username as the last cached login is a returning user',
      () async {
    fakeStorage._values['lastUsername'] = 'sk_one';

    expect(await repo.isReturningUser('sk_one'), isTrue);
  });

  test('a different username is not a returning user', () async {
    fakeStorage._values['lastUsername'] = 'sk_one';

    expect(await repo.isReturningUser('sk_two'), isFalse);
  });

  test('no cached username at all (fresh device) is not a returning user',
      () async {
    expect(await repo.isReturningUser('sk_one'), isFalse);
  });
}
