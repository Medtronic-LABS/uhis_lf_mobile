import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

/// The permissions the app asks for, in the order they are requested.
///
/// Notifications last, deliberately: it is the least alarming of the four, so
/// if an SK fatigue-denies by the final dialog it costs least.
const List<Permission> kOnboardingPermissions = <Permission>[
  Permission.camera,
  Permission.microphone,
  Permission.locationWhenInUse,
  Permission.notification,
];

/// Decides whether to run the consolidated permission request, and runs it.
///
/// Kept separate from both the UI and `permission_handler` so the rule — ask
/// once, never block, never nag — is testable without a device or a widget
/// tree.
///
/// Android shows one dialog per permission group and offers no combined
/// prompt, so this delivers *one moment* with several taps rather than one
/// tap. The win is that it happens while the SK is set up, instead of four
/// separate interruptions mid-visit: recording symptoms, scanning an ID with
/// the patient waiting.
class PermissionGate {
  PermissionGate({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    Future<Map<Permission, PermissionStatus>> Function(List<Permission>)?
        requester,
    Future<bool> Function()? openSettings,
  })  : _storage = storage,
        _requester = requester ?? _defaultRequester,
        _openSettings = openSettings ?? openAppSettings;

  final FlutterSecureStorage _storage;
  final Future<Map<Permission, PermissionStatus>> Function(List<Permission>)
      _requester;
  final Future<bool> Function() _openSettings;

  static const _kAsked = 'permissions_asked';

  static Future<Map<Permission, PermissionStatus>> _defaultRequester(
    List<Permission> permissions,
  ) =>
      permissions.request();

  /// True when the consolidated step should be shown.
  ///
  /// False once asked, and on web where these permissions do not apply.
  Future<bool> shouldPrompt() async {
    if (kIsWeb) return false;
    return !await hasAsked();
  }

  Future<bool> hasAsked() async {
    try {
      return await _storage.read(key: _kAsked) == 'true';
    } catch (e) {
      // An unreadable flag must not turn into a prompt on every launch.
      debugPrint('[Permissions] could not read asked flag: $e');
      return true;
    }
  }

  /// Requests every permission in [kOnboardingPermissions] back to back.
  ///
  /// Records "asked" whatever the outcome, so a denial is respected instead of
  /// re-prompted next launch. Returns the per-permission statuses; callers use
  /// them for reporting only — nothing here blocks onboarding, because an SK
  /// who declines must still reach the dashboard with a working app.
  Future<Map<Permission, PermissionStatus>> requestAll() async {
    Map<Permission, PermissionStatus> statuses = {};
    try {
      statuses = await _requester(kOnboardingPermissions);
    } catch (e) {
      // A platform fault must not strand the SK on the onboarding step.
      debugPrint('[Permissions] request failed: $e');
    }
    await _markAsked();
    debugPrint('[Permissions] result: '
        '${statuses.map((k, v) => MapEntry(k.toString().split('.').last, v.name))}');
    return statuses;
  }

  /// Records "asked" without prompting — used when the SK declines at the
  /// rationale step. Re-prompting on the next launch is exactly the nagging
  /// this step exists to remove; the point-of-use checks remain the way back
  /// in if they later reach a feature that needs a permission.
  Future<void> declineWithoutAsking() => _markAsked();

  Future<void> _markAsked() async {
    try {
      await _storage.write(key: _kAsked, value: 'true');
    } catch (e) {
      debugPrint('[Permissions] could not persist asked flag: $e');
    }
  }

  /// True when at least one permission is permanently denied.
  ///
  /// This is the state that needs handling rather than retrying: once Android
  /// marks a permission permanently denied, requesting it again shows no
  /// dialog and returns immediately, so a "grant" button would look dead.
  static bool anyPermanentlyDenied(Map<Permission, PermissionStatus> statuses) =>
      statuses.values.any((s) => s.isPermanentlyDenied);

  /// Sends the SK to app settings, the only route back from permanent denial.
  Future<bool> openSettings() async {
    try {
      return await _openSettings();
    } catch (e) {
      debugPrint('[Permissions] could not open settings: $e');
      return false;
    }
  }
}
