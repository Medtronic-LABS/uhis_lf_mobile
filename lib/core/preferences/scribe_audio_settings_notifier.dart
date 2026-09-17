import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// On-device microphone capture preferences for both scribe paths,
/// persisted so a supervisor can change them in the field without a
/// rebuild (Settings → Microphone capture).
///
/// Mirrors [ScribeEngineNotifier]'s shape and the same three-tier
/// precedence doctrine as [VadTuningNotifier]: [AppConfig] holds the
/// build-time default, this notifier's persisted value overrides it, and a
/// future server-driven config API would slot in above both.
///
/// Kept separate from [AiFeatureTogglesNotifier] deliberately — that type
/// owns which AI *surfaces* an SK sees, this one owns how the mic is
/// opened. Folding the two together would also drag mic capture into the
/// "Select all" AI-widgets switch, where it does not belong.
class ScribeAudioSettingsNotifier extends ChangeNotifier {
  ScribeAudioSettingsNotifier(this._storage);

  final FlutterSecureStorage _storage;
  static const _rawMicCaptureKey = 'scribe_raw_mic_capture_v1';

  bool _rawMicCaptureEnabled = AppConfig.rawMicCaptureDefault;

  /// Whether scribe capture bypasses the handset's echo-cancellation /
  /// noise-suppression chain. See `ScribeRecordConfig` for what this
  /// changes and when it is the right choice.
  bool get rawMicCaptureEnabled => _rawMicCaptureEnabled;

  Future<void> load() async {
    final raw = await _storage.read(key: _rawMicCaptureKey);
    // No saved value (fresh install, or the setting never touched) falls
    // back to the build-time default rather than a hardcoded false, so a
    // `--dart-define=RAW_MIC_CAPTURE=true` test build starts in the mode
    // it was built for.
    _rawMicCaptureEnabled = switch (raw) {
      'true' => true,
      'false' => false,
      _ => AppConfig.rawMicCaptureDefault,
    };
    notifyListeners();
  }

  Future<void> setRawMicCaptureEnabled(bool enabled) async {
    if (_rawMicCaptureEnabled == enabled) return;
    _rawMicCaptureEnabled = enabled;
    await _storage.write(key: _rawMicCaptureKey, value: '$enabled');
    notifyListeners();
  }

  /// Drops the on-device override so the build-time default applies again.
  Future<void> resetToDefaults() async {
    _rawMicCaptureEnabled = AppConfig.rawMicCaptureDefault;
    await _storage.delete(key: _rawMicCaptureKey);
    notifyListeners();
  }
}
