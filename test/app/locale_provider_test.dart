/// Unit tests for [LocaleProvider]'s default language and persistence.
/// Swaps in an in-memory fake [FlutterSecureStoragePlatform] so no real
/// platform channel is needed — mirrors theme_provider_test.dart.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/app/locale_provider.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> values;

  _InMemorySecureStorage([Map<String, String>? seed]) : values = seed ?? {};

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
  test('defaults to English synchronously, before storage resolves', () {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();

    final provider = LocaleProvider();

    expect(provider.language, AppLanguage.english);
    expect(provider.isBangla, isFalse);
  });

  test('no stored preference resolves to English', () async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();

    final provider = LocaleProvider();
    await Future<void>.delayed(Duration.zero);

    expect(provider.language, AppLanguage.english);
  });

  test('an explicitly stored Bangla preference wins over the default',
      () async {
    FlutterSecureStoragePlatform.instance =
        _InMemorySecureStorage({'app_language': 'bn'});

    final provider = LocaleProvider();
    await Future<void>.delayed(Duration.zero);

    expect(provider.language, AppLanguage.bangla);
    expect(provider.isBangla, isTrue);
  });

  test('setLanguage persists the choice and updates the global AppLocale flag',
      () async {
    final storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    final provider = LocaleProvider();
    await Future<void>.delayed(Duration.zero);

    await provider.setLanguage(AppLanguage.bangla);

    expect(provider.language, AppLanguage.bangla);
    expect(AppLocale.isBangla, isTrue);
    expect(storage.values['app_language'], 'bn');
  });

  test('setLanguage back to English persists and updates AppLocale', () async {
    final storage = _InMemorySecureStorage({'app_language': 'bn'});
    FlutterSecureStoragePlatform.instance = storage;
    final provider = LocaleProvider();
    await Future<void>.delayed(Duration.zero);

    await provider.setLanguage(AppLanguage.english);

    expect(provider.language, AppLanguage.english);
    expect(AppLocale.isBangla, isFalse);
    expect(storage.values['app_language'], 'en');
  });
}
