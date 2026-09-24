import '../api/api_client.dart';

/// Outcome of a server-side app-version check. Sealed so callers must handle
/// every case (see `AuthRepository.login`).
sealed class AppVersionCheckResult {
  const AppVersionCheckResult();
}

/// The installed app satisfies the server's minimum and latest version.
class AppVersionUpToDate extends AppVersionCheckResult {
  const AppVersionUpToDate();
}

/// A newer version exists but the current one is still allowed (optional update).
class AppVersionUpdateAvailable extends AppVersionCheckResult {
  const AppVersionUpdateAvailable();
}

/// The installed version is below the server's enforced minimum — login is
/// blocked until the user updates. [minVersionLabel] is shown to the user.
class AppVersionUpdateRequired extends AppVersionCheckResult {
  const AppVersionUpdateRequired(this.minVersionLabel);
  final String minVersionLabel;
}

/// The version check could not be completed (transport / server error).
class AppVersionCheckFailed extends AppVersionCheckResult {
  const AppVersionCheckFailed();
}

/// Checks the running app version against the backend's minimum/latest.
///
/// > **Reconstructed file** — see the note in `app_version_info.dart`. This
/// > placeholder is deliberately **permissive**: [check] always reports
/// > up-to-date so authentication is never blocked by a missing/unknown version
/// > endpoint. Restore PR #689's original service to re-enable real enforcement.
class AppVersionService {
  AppVersionService(this._api);

  // ignore: unused_field
  final ApiClient _api;

  /// Whether the login screen should surface a one-time optional-update prompt.
  /// Permissive reconstruction: never prompts.
  static bool get needsOptionalPrompt => false;

  /// Clears any cached version-check state on logout. No-op in this
  /// reconstruction. Shape matches `AuthState.registerLogoutHook`.
  static void invalidateSessionCache() {}

  /// Runs the version check. Permissive reconstruction: always up-to-date.
  Future<AppVersionCheckResult> check() async => const AppVersionUpToDate();
}
