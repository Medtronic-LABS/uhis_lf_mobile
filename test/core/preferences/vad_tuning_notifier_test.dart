/// Unit tests for [VadTuningNotifier]. Swaps in an in-memory fake
/// [FlutterSecureStoragePlatform] so no real platform channel is needed —
/// same pattern as test/app/theme_provider_test.dart.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/preferences/vad_tuning_notifier.dart';

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
  test('with nothing persisted, load() resolves to factory defaults', () async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    final notifier = VadTuningNotifier(const FlutterSecureStorage());

    await notifier.load();

    final defaults = VadTuningConfig.defaults();
    expect(notifier.config.enterMarginDb, defaults.enterMarginDb);
    expect(notifier.config.floorCeilingDbfs, defaults.floorCeilingDbfs);
    expect(notifier.config.hangoverMs, defaults.hangoverMs);
  });

  test('update() persists and is read back on a fresh notifier', () async {
    final storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    final notifier = VadTuningNotifier(const FlutterSecureStorage());
    await notifier.load();

    final tuned = notifier.config.copyWith(enterMarginDb: 6, hangoverMs: 900);
    await notifier.update(tuned);

    expect(storage.values.containsKey('vad_tuning_v1'), isTrue);

    final restored = VadTuningNotifier(const FlutterSecureStorage());
    await restored.load();
    expect(restored.config.enterMarginDb, 6);
    expect(restored.config.hangoverMs, 900);
    // Untouched fields keep their previous (default) value.
    expect(restored.config.floorAlpha, VadTuningConfig.defaults().floorAlpha);
  });

  test('corrupt persisted value degrades to defaults rather than throwing',
      () async {
    FlutterSecureStoragePlatform.instance =
        _InMemorySecureStorage({'vad_tuning_v1': 'not valid json'});
    final notifier = VadTuningNotifier(const FlutterSecureStorage());

    await notifier.load();

    expect(notifier.config.enterMarginDb, VadTuningConfig.defaults().enterMarginDb);
  });

  test('resetToDefaults() restores factory values and persists them', () async {
    final storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    final notifier = VadTuningNotifier(const FlutterSecureStorage());
    await notifier.load();
    await notifier.update(notifier.config.copyWith(enterMarginDb: 20));
    expect(notifier.config.enterMarginDb, 20);

    await notifier.resetToDefaults();

    expect(notifier.config.enterMarginDb, VadTuningConfig.defaults().enterMarginDb);
    final restored = VadTuningNotifier(const FlutterSecureStorage());
    await restored.load();
    expect(restored.config.enterMarginDb, VadTuningConfig.defaults().enterMarginDb);
  });
}
