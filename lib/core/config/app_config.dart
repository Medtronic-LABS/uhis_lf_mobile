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
  /// Production/Dev server → `https://spice-qa-backend.uhis.labsplatform.com/`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://spice-dev-backend.uhis.labsplatform.com/',
  );

  /// Value of the `client` request header expected by the auth pipeline.
  /// `mob` for mobile app (community-health field accounts).
  /// `web` for desktop browsers + dev-loaned web user accounts.
  static const String apiClient = String.fromEnvironment(
    'API_CLIENT',
    defaultValue: 'mob',
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

  /// Dev-only: comma-separated list of sub-village IDs for the dev user.
  /// The household/member list APIs filter by sub-village, not union.
  static const String devSubVillageIds = String.fromEnvironment(
    'DEV_SUB_VILLAGE_IDS',
    defaultValue: '',
  );

  /// Parsed list of dev sub-village IDs.
  static List<int> get devSubVillageIdList {
    if (devSubVillageIds.isEmpty) return const [];
    return devSubVillageIds
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
  }

  static bool get hasDevCredentials =>
      devUser.isNotEmpty && devPass.isNotEmpty;

  /// Length of the app-specific fallback PIN. Supported values: 4 or 6.
  /// Any other build-define value falls back to 6.
  static int get pinLength {
    const raw = int.fromEnvironment('PIN_LENGTH', defaultValue: 6);
    return raw == 4 ? 4 : 6;
  }

  /// Base URL for the AI Scribe service.
  /// Bypasses the main nginx gateway so the scribe container can be run
  /// locally independently of the UHIS backend. Nginx strips the
  /// `/ai-scribe-service/` routing prefix; direct calls omit it.
  /// Android emulator → `http://10.0.2.2:8095/`
  /// When deployed behind nginx, set this to the same value as [apiBaseUrl].
  static const String scribeBaseUrl = String.fromEnvironment(
    'SCRIBE_BASE_URL',
    defaultValue: 'http://10.0.2.2:8095/',
  );

  /// Wrong-PIN attempts allowed before the user is pushed to password sign-in.
  static const int pinMaxAttempts = int.fromEnvironment(
    'PIN_MAX_ATTEMPTS',
    defaultValue: 5,
  );

  /// Page size used when paginating the spice-service list endpoints during
  /// the offline-cache sync. The backend caps a page at 1000; a smaller page
  /// gives smoother progress feedback over slow links.
  static const int syncPageSize = int.fromEnvironment(
    'SYNC_PAGE_SIZE',
    defaultValue: 500,
  );

  /// Safety cap on pages fetched per entity in a single sync, so a runaway
  /// (non-terminating) backend response cannot loop forever.
  static const int syncMaxPages = int.fromEnvironment(
    'SYNC_MAX_PAGES',
    defaultValue: 200,
  );
}
