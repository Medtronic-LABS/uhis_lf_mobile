import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads and acts on Android's battery-optimisation state.
///
/// An interface so the decision logic and UI can be tested without a device;
/// [NoopBatteryOptimizationService] is used on web and in tests.
abstract class BatteryOptimizationService {
  /// True when the app is exempt from battery optimisation — or when the
  /// question does not apply (web, iOS, API < 23). Defaults to "exempt" so a
  /// platform that cannot answer never nags the SK.
  Future<bool> isExempt();

  /// `Build.MANUFACTURER`, lower-cased, or empty when unknown.
  Future<String> manufacturer();

  /// True when this device's vendor ships an autostart screen we know how to
  /// open. Xiaomi/Oppo/Vivo/Transsion kill background work through lists no API
  /// can read, so this is the only way to send the SK there.
  Future<bool> hasOemAutoStartScreen();

  /// Opens the system battery-optimisation list. Returns false if nothing could
  /// be opened.
  Future<bool> openBatterySettings();

  /// Opens the vendor autostart screen. Returns false when the device has none.
  Future<bool> openOemAutoStartSettings();
}

class NoopBatteryOptimizationService implements BatteryOptimizationService {
  const NoopBatteryOptimizationService();

  @override
  Future<bool> isExempt() async => true;

  @override
  Future<String> manufacturer() async => '';

  @override
  Future<bool> hasOemAutoStartScreen() async => false;

  @override
  Future<bool> openBatterySettings() async => false;

  @override
  Future<bool> openOemAutoStartSettings() async => false;
}

/// Android implementation over `com.medtroniclabs.uhis_next/device_battery`.
///
/// Every call degrades to the "nothing to do" answer on failure: this feature
/// is an aid, and a broken channel must never block the SK or throw into a
/// widget build.
class MethodChannelBatteryOptimizationService
    implements BatteryOptimizationService {
  const MethodChannelBatteryOptimizationService();

  static const _channel =
      MethodChannel('com.medtroniclabs.uhis_next/device_battery');

  Future<T> _guard<T>(String method, T fallback, [T Function(Object?)? map]) async {
    try {
      final value = await _channel.invokeMethod<Object?>(method);
      return map != null ? map(value) : (value as T? ?? fallback);
    } on PlatformException catch (e) {
      debugPrint('[DeviceBattery] $method failed: ${e.code} ${e.message}');
      return fallback;
    } on MissingPluginException {
      return fallback;
    }
  }

  @override
  Future<bool> isExempt() => _guard('isExempt', true);

  @override
  Future<String> manufacturer() =>
      _guard('manufacturer', '', (v) => (v as String? ?? '').toLowerCase());

  @override
  Future<bool> hasOemAutoStartScreen() => _guard('hasOemAutoStartScreen', false);

  @override
  Future<bool> openBatterySettings() => _guard('openBatterySettings', false);

  @override
  Future<bool> openOemAutoStartSettings() =>
      _guard('openOemAutoStartSettings', false);
}
