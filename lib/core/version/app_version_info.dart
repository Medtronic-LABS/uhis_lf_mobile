import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The running app's version, read once from the platform package metadata.
/// Sent as `App-Version` / `App-Version-Code` on API requests and compared
/// against the server's policy by `AppVersionService` (LEAP-144).
class AppVersionInfo {
  const AppVersionInfo({required this.versionName, required this.versionCode});

  /// Semantic version string, e.g. `1.4.2`.
  final String versionName;

  /// Monotonic build number, e.g. `142`.
  final int versionCode;

  static AppVersionInfo _current =
      const AppVersionInfo(versionName: '0.0.0', versionCode: 0);

  /// The loaded version. Falls back to `0.0.0` / `0` until [ensureLoaded] runs.
  static AppVersionInfo get current => _current;

  /// Loads the version from the platform package info. Call once at startup.
  static Future<void> ensureLoaded() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _current = AppVersionInfo(
        versionName: info.version,
        versionCode: int.tryParse(info.buildNumber) ?? 0,
      );
    } on Exception catch (e) {
      debugPrint('AppVersionInfo.ensureLoaded failed: $e');
    }
  }
}
