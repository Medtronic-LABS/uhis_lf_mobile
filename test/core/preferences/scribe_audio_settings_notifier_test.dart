/// Unit tests for [ScribeAudioSettingsNotifier]. Swaps in an in-memory fake
/// [FlutterSecureStoragePlatform] so no real platform channel is needed —
/// same pattern as test/core/preferences/vad_tuning_notifier_test.dart.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/config/app_config.dart';
import 'package:uhis_next/core/preferences/scribe_audio_settings_notifier.dart';

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
  const key = 'scribe_raw_mic_capture_v1';

  test('raw mic capture is off by default in a stock build', () {
    // The whole point of the flag: normal field builds keep the handset's
    // processed audio chain, which is right for someone speaking directly
    // at the phone. Anything else is an opt-in for testing/demos.
    expect(AppConfig.rawMicCaptureDefault, isFalse);
  });

  test('with nothing persisted, load() resolves to the build-time default',
      () async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    final notifier = ScribeAudioSettingsNotifier(const FlutterSecureStorage());

    await notifier.load();

    expect(notifier.rawMicCaptureEnabled, AppConfig.rawMicCaptureDefault);
  });

  test('enabling persists and is read back on a fresh notifier', () async {
    final storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    final notifier = ScribeAudioSettingsNotifier(const FlutterSecureStorage());
    await notifier.load();

    await notifier.setRawMicCaptureEnabled(true);

    expect(notifier.rawMicCaptureEnabled, isTrue);
    expect(storage.values[key], 'true');

    final restored = ScribeAudioSettingsNotifier(const FlutterSecureStorage());
    await restored.load();
    expect(restored.rawMicCaptureEnabled, isTrue);
  });

  test('an explicitly persisted false survives load, not just the default',
      () async {
    FlutterSecureStoragePlatform.instance =
        _InMemorySecureStorage({key: 'false'});
    final notifier = ScribeAudioSettingsNotifier(const FlutterSecureStorage());

    await notifier.load();

    expect(notifier.rawMicCaptureEnabled, isFalse);
  });

  test('an unrecognised persisted value degrades to the build-time default',
      () async {
    FlutterSecureStoragePlatform.instance =
        _InMemorySecureStorage({key: 'garbage'});
    final notifier = ScribeAudioSettingsNotifier(const FlutterSecureStorage());

    await notifier.load();

    expect(notifier.rawMicCaptureEnabled, AppConfig.rawMicCaptureDefault);
  });

  test('resetToDefaults() drops the override so the build default applies',
      () async {
    final storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    final notifier = ScribeAudioSettingsNotifier(const FlutterSecureStorage());
    await notifier.load();
    await notifier.setRawMicCaptureEnabled(true);

    await notifier.resetToDefaults();

    expect(notifier.rawMicCaptureEnabled, AppConfig.rawMicCaptureDefault);
    expect(storage.values.containsKey(key), isFalse);
  });

  test('setting the value it already has does not notify listeners', () async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    final notifier = ScribeAudioSettingsNotifier(const FlutterSecureStorage());
    await notifier.load();
    var notifications = 0;
    notifier.addListener(() => notifications++);

    await notifier.setRawMicCaptureEnabled(AppConfig.rawMicCaptureDefault);

    expect(notifications, 0);
  });
}
