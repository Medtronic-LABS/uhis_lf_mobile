/// Unit tests for the PIN-length self-heal in [AuthRepository] —
/// GitHub issue #36 (PIN length 6→4). Swaps in an in-memory fake
/// [FlutterSecureStoragePlatform] so no real platform channel is needed;
/// exercises the real [AuthRepository]/[FlutterSecureStorage] with no
/// production constructor changes.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  test('a PIN stored under the current pinLength is reported as set',
      () async {
    // setPin() also persists a reentry session (requires an active login
    // token on ApiClient), which is unrelated to the length self-heal logic
    // under test here — seed storage directly instead, exactly as setPin()
    // itself would leave it.
    fakeStorage._values['pin_enabled'] = 'true';
    fakeStorage._values['pin_hash'] = 'some-hash';
    fakeStorage._values['pin_salt'] = 'some-salt';
    fakeStorage._values['pin_length'] = '4';

    expect(await repo.isPinSet(), isTrue);
  });

  test('a PIN set under a different length self-heals: isPinSet() clears it',
      () async {
    // Simulate a pre-migration 6-digit PIN: enabled + hash/salt present, but
    // no pin_length key (as no build ever stored one before this fix).
    fakeStorage._values['pin_enabled'] = 'true';
    fakeStorage._values['pin_hash'] = 'some-old-hash';
    fakeStorage._values['pin_salt'] = 'some-old-salt';
    fakeStorage._values['pin_failed_attempts'] = '0';

    expect(await repo.isPinSet(), isFalse,
        reason: 'stale-length PIN must not be reported as usable');

    // clearPin() should have run — every PIN key gone.
    expect(fakeStorage._values.containsKey('pin_enabled'), isFalse);
    expect(fakeStorage._values.containsKey('pin_hash'), isFalse);
    expect(fakeStorage._values.containsKey('pin_salt'), isFalse);
  });

  test('a PIN explicitly stored with a stale pin_length also self-heals',
      () async {
    fakeStorage._values['pin_enabled'] = 'true';
    fakeStorage._values['pin_hash'] = 'some-old-hash';
    fakeStorage._values['pin_salt'] = 'some-old-salt';
    fakeStorage._values['pin_length'] = '6';

    expect(await repo.isPinSet(), isFalse);
  });

  test('no PIN set at all reports false without touching storage', () async {
    expect(await repo.isPinSet(), isFalse);
  });
}
