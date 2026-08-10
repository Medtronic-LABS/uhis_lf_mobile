import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'battery_optimization_service.dart';

/// Decides whether to ask the SK to exempt the app from battery optimisation.
///
/// Kept separate from both the platform channel and the dialog so the rule is
/// testable on its own — the interesting part is *when not to ask*, and that
/// should not require a device or a widget tree to verify.
///
/// The rule: ask at most once, ever, and only when asking could actually help.
/// A CHW mid-visit does not need a settings prompt, and an app that nags is an
/// app whose prompts get dismissed reflexively.
class BatteryOptimizationGate {
  BatteryOptimizationGate({
    required BatteryOptimizationService service,
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  })  : _service = service,
        _storage = storage;

  final BatteryOptimizationService _service;
  final FlutterSecureStorage _storage;

  static const _kAsked = 'battery_optimization_asked';

  /// True when the SK should be shown the prompt now.
  ///
  /// False when: already asked, already exempt, or the platform cannot answer
  /// (web/iOS/API < 23, where [BatteryOptimizationService.isExempt] returns
  /// true by design).
  Future<bool> shouldPrompt() async {
    if (kIsWeb) return false;
    if (await hasAsked()) return false;
    try {
      return !await _service.isExempt();
    } catch (e) {
      // A platform that cannot answer is not a reason to bother the SK.
      debugPrint('[BatteryGate] isExempt failed, not prompting: $e');
      return false;
    }
  }

  Future<bool> hasAsked() async {
    try {
      return await _storage.read(key: _kAsked) == 'true';
    } catch (e) {
      // Treat an unreadable flag as "already asked": a storage fault must not
      // turn into a prompt on every launch.
      debugPrint('[BatteryGate] could not read asked flag: $e');
      return true;
    }
  }

  /// Records that the SK has been asked — called whether they accepted or
  /// declined, so declining is respected permanently.
  Future<void> markAsked() async {
    try {
      await _storage.write(key: _kAsked, value: 'true');
    } catch (e) {
      debugPrint('[BatteryGate] could not persist asked flag: $e');
    }
  }

  /// Sends the SK to the most useful screen available: the vendor autostart
  /// list when this device has one (Xiaomi/Oppo/Vivo/Transsion kill background
  /// work from there regardless of the system setting), otherwise the system
  /// battery-optimisation list.
  Future<bool> openBestSettingsScreen() async {
    if (await _service.hasOemAutoStartScreen()) {
      if (await _service.openOemAutoStartSettings()) return true;
    }
    return _service.openBatterySettings();
  }
}
