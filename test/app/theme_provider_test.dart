/// Unit tests for [ThemeProvider]'s default mode. Swaps in an in-memory
/// fake [FlutterSecureStoragePlatform] so no real platform channel is
/// needed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/app/theme_provider.dart';

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
  test('defaults to light mode synchronously, before storage resolves', () {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();

    final provider = ThemeProvider();

    expect(provider.mode, ThemeMode.light);
    expect(provider.isLight, isTrue);
  });

  test('no stored preference resolves to light, not system', () async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();

    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);

    expect(provider.mode, ThemeMode.light);
  });

  test('an explicitly stored dark preference still wins over the default',
      () async {
    FlutterSecureStoragePlatform.instance =
        _InMemorySecureStorage({'theme_mode': 'dark'});

    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);

    expect(provider.mode, ThemeMode.dark);
  });

  test('setMode(system) is still selectable and persists, though it now '
      'resolves back to light on the next cold load', () async {
    final storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);

    await provider.setMode(ThemeMode.system);

    expect(provider.mode, ThemeMode.system);
    expect(storage.values.containsKey('theme_mode'), isFalse);
  });
}
