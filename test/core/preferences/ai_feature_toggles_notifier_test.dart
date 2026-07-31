/// Unit tests for [AiFeatureTogglesNotifier]. Swaps in an in-memory fake
/// [FlutterSecureStoragePlatform] so no real platform channel is needed —
/// same pattern as test/core/preferences/vad_tuning_notifier_test.dart.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/preferences/ai_feature_toggles_notifier.dart';

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
  test('with nothing persisted, load() resolves to factory defaults (all on)',
      () async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    final notifier = AiFeatureTogglesNotifier(const FlutterSecureStorage());

    await notifier.load();

    final defaults = AiFeatureToggles.defaults();
    expect(notifier.toggles.step1SummaryEnabled, defaults.step1SummaryEnabled);
    expect(notifier.toggles.step1AsrEnabled, defaults.step1AsrEnabled);
    expect(notifier.toggles.step2AsrEnabled, defaults.step2AsrEnabled);
    expect(notifier.toggles.step3SummaryEnabled, defaults.step3SummaryEnabled);
    expect(notifier.toggles.step3ReferralAlertEnabled,
        defaults.step3ReferralAlertEnabled);
    expect(
        notifier.toggles.step3WhatsAppEnabled, defaults.step3WhatsAppEnabled);
  });

  test('update() persists and is read back on a fresh notifier', () async {
    final storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    final notifier = AiFeatureTogglesNotifier(const FlutterSecureStorage());
    await notifier.load();

    final tuned = notifier.toggles.copyWith(
      step1AsrEnabled: false,
      step3WhatsAppEnabled: false,
    );
    await notifier.update(tuned);

    expect(storage.values.containsKey('ai_feature_toggles_v1'), isTrue);

    final restored = AiFeatureTogglesNotifier(const FlutterSecureStorage());
    await restored.load();
    expect(restored.toggles.step1AsrEnabled, isFalse);
    expect(restored.toggles.step3WhatsAppEnabled, isFalse);
    // Untouched fields keep their previous (default) value.
    expect(restored.toggles.step2AsrEnabled, isTrue);
    expect(restored.toggles.step3ReferralAlertEnabled, isTrue);
  });

  test('corrupt persisted value degrades to defaults rather than throwing',
      () async {
    FlutterSecureStoragePlatform.instance =
        _InMemorySecureStorage({'ai_feature_toggles_v1': 'not valid json'});
    final notifier = AiFeatureTogglesNotifier(const FlutterSecureStorage());

    await notifier.load();

    expect(notifier.toggles.step1SummaryEnabled, isTrue);
    expect(notifier.toggles.step2AsrEnabled, isTrue);
  });

  test('resetToDefaults() restores factory values and persists them',
      () async {
    final storage = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    final notifier = AiFeatureTogglesNotifier(const FlutterSecureStorage());
    await notifier.load();
    await notifier.update(notifier.toggles.copyWith(step2AsrEnabled: false));
    expect(notifier.toggles.step2AsrEnabled, isFalse);

    await notifier.resetToDefaults();

    expect(notifier.toggles.step2AsrEnabled, isTrue);
    final restored = AiFeatureTogglesNotifier(const FlutterSecureStorage());
    await restored.load();
    expect(restored.toggles.step2AsrEnabled, isTrue);
  });
}
