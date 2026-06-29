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

  /// Human-readable app version (also sent as the `App-Version` header so the
  /// offline-sync service can gate compatibility). Mirrors the version in
  /// `pubspec.yaml` so a single bump propagates to the wire.
  static const String appVersionName = String.fromEnvironment(
    'APP_VERSION_NAME',
    defaultValue: '1.0.0',
  );

  /// Numeric app version code (also sent as the `App-Version-Code` header).
  /// Matches the Android reference contract for offline-sync request bodies.
  static const int appVersionCode = int.fromEnvironment(
    'APP_VERSION_CODE',
    defaultValue: 1,
  );

  /// Application type sent in offline-sync request bodies. Mirrors the
  /// Android reference `CommonUtils.isCommunityOrNot()` (`COMMUNITY` for SK
  /// builds; `FO` for field-officer builds when that variant ships).
  static const String appType = String.fromEnvironment(
    'APP_TYPE',
    defaultValue: 'COMMUNITY',
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
    defaultValue: 'Place your registered finger on the sensor below',
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

  /// Base URL for the AI Visit Briefing service.
  /// Empty = route through the nginx gateway (production path).
  /// Set to e.g. http://10.0.2.2:8096 to hit a locally-running service
  /// while keeping BASE_URL pointed at the remote backend.
  static const String aiServiceBaseUrl = String.fromEnvironment(
    'AI_SERVICE_URL',
    defaultValue: '',
  );

  /// Transcription model for AI Scribe.
  /// Options: 'gpt-4o-mini-transcribe', 'whisper-1', 'gemini-2.5-flash'
  static const String scribeTranscriptionModel = String.fromEnvironment(
    'SCRIBE_TRANSCRIPTION_MODEL',
    defaultValue: 'gemini-2.5-flash',
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

  /// Timeout in milliseconds for the AI pathway suggestion call.
  ///
  /// The call is fire-and-forget; the picker never blocks on it.
  /// Default is 3 000 ms — enough for a fast rural connection.
  static int get aiPathwayTimeoutMs =>
      int.tryParse(const String.fromEnvironment('AI_PATHWAY_TIMEOUT_MS')) ??
      3000;

  /// Whether AI pathway suggestions are enabled.
  ///
  /// Set `--dart-define=AI_PATHWAY_ENABLED=false` to disable without a rebuild.
  static bool get aiPathwayEnabled => const bool.fromEnvironment(
        'AI_PATHWAY_ENABLED',
        defaultValue: true,
      );

  // ── AI Scribe feature flags (S4.5) ────────────────────────────────────────

  /// Whether the AI Scribe feature is enabled at all.
  /// Set `--dart-define=SCRIBE_ENABLED=false` to hide all scribe UI and skip
  /// all scribe calls without a code change.
  static bool get scribeEnabled =>
      const bool.fromEnvironment('SCRIBE_ENABLED', defaultValue: true);

  /// Minimum confidence for a scribe-extracted symptom code to be
  /// auto-ticked on the triage picker. Codes below this floor are silently
  /// skipped so the SK is never burdened with low-confidence noise.
  static double get scribeSymptomConfidenceFloor =>
      double.tryParse(
        const String.fromEnvironment('SCRIBE_SYMPTOM_CONFIDENCE_FLOOR'),
      ) ??
      0.7;

  /// Minimum confidence for a scribe-extracted form field to be pre-filled
  /// in the sectioned assessment. Fields below this floor are not written
  /// to the draft.
  static double get scribeFieldConfidenceFloor =>
      double.tryParse(
        const String.fromEnvironment('SCRIBE_FIELD_CONFIDENCE_FLOOR'),
      ) ??
      0.6;

  // NOTE: scribeConsentGiven is intentionally NOT stored in AppConfig because
  // it is a per-user runtime preference, not a compile-time build flag.
  // It must be read from SharedPreferences / SecureStorage and managed by
  // a dedicated ConsentRepository (TODO: wire in a future sprint).
}
