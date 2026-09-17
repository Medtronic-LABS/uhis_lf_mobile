/// UHIS parity: explicit logout ends the session but keeps offline credentials.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/config/app_config.dart';

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
  late _InMemorySecureStorage storage;
  late AuthRepository repo;

  setUp(() async {
    storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    repo = AuthRepository(await ApiClient.create());
    storage._values['lastUsername'] = 'sk_one';
    storage._values['offline_pwd_hash'] = 'abc123';
    storage._values['localDataOwner'] = 'sk_one';
    storage._values['pin_enabled'] = 'true';
    storage._values['pin_hash'] = 'hash';
    storage._values['pin_length'] = '${AppConfig.pinLength}';
    storage._values['tenantId'] = '1';
    storage._values['firstName'] = 'Test';
  });

  test('logout(online: true) keeps username, password hash, and PIN', () async {
    await repo.logout(online: false);

    expect(await repo.lastUsername(), 'sk_one');
    expect(await repo.localDataOwnerUsername(), 'sk_one');
    expect(await repo.isPinSet(), isTrue);
    expect(storage._values['offline_pwd_hash'], 'abc123');
    expect(storage._values['tenantId'], '1');
    expect(storage._values['firstName'], 'Test');
  });
}
