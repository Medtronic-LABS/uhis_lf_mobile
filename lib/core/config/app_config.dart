/// Build-time configuration. Every value is sourced via
/// [String.fromEnvironment], which is populated by either
/// `--dart-define=KEY=VALUE` or `--dart-define-from-file=env.*.json`
/// at compile time.
///
/// Defaults here exist only to keep `flutter run` working with no flags.
/// Real values must be supplied at build / CI time.
class AppConfig {
  AppConfig._();

  /// Base URL for the UHIS nginx gateway.
  /// Android emulator → `http://10.0.2.2`. Physical device → host LAN IP.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2',
  );

  /// Value of the `client` request header expected by the auth pipeline.
  /// `web` for desktop browsers + dev-loaned web user accounts.
  /// `mob` for community-health field accounts (when those are seeded).
  static const String apiClient = String.fromEnvironment(
    'API_CLIENT',
    defaultValue: 'web',
  );

  /// HmacSHA512 key the React frontend (and now this app) uses to hash the
  /// password before posting to `/auth-service/session`. Empty in dev.
  static const String passwordHashKey = String.fromEnvironment(
    'PASSWORD_HASH_KEY',
    defaultValue: '',
  );

  /// Fallback TTL (seconds) for the AuthCookie when the response omits
  /// a `Max-Age` attribute.
  static const int authCookieTtlSeconds = int.fromEnvironment(
    'AUTH_COOKIE_TTL_SECONDS',
    defaultValue: 3600,
  );

  /// Localized reason shown by Android `BiometricPrompt`.
  static const String biometricReason = String.fromEnvironment(
    'BIOMETRIC_REASON',
    defaultValue: 'Unlock UHIS Next',
  );

  /// Dev-only autologin. Leave blank in any non-dev build.
  static const String devUser = String.fromEnvironment(
    'DEV_USER',
    defaultValue: '',
  );

  /// Dev-only autologin. Leave blank in any non-dev build.
  static const String devPass = String.fromEnvironment(
    'DEV_PASS',
    defaultValue: '',
  );

  static bool get hasDevCredentials =>
      devUser.isNotEmpty && devPass.isNotEmpty;
}
