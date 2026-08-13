/// Centralized, multilingual-ready content constants for LEAPWELL.
///
/// **Design pattern — single source of UI copy.** Every user-facing string
/// (labels, hints, button text, dialog copy, snackbars, validation messages)
/// lives here, grouped by feature. Widgets must reference these constants
/// instead of inlining string literals. This mirrors the React `spice_web`
/// `appConstants.ts` convention and gives the app one localization seam: to
/// add a language later, swap each `static const String` for a locale lookup
/// (e.g. an `AppLocalizations` delegate) without touching a single widget.
///
/// Rules:
///   * No hardcoded user-facing text in widgets — pull it from here.
///   * Interpolated copy is exposed as a `static` method, never built ad hoc
///     in the widget with raw literals.
///   * Keep the rendered value stable — e2e selectors match on these strings.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

import '../../features/visit/immunisation/epi_schedule_engine.dart';
import '../../features/visit/immunisation/epi_visit_summary.dart';
import '../i18n/app_locale.dart';
import '../i18n/bn_numerals.dart';
import '../models/dashboard_tier.dart';
import '../models/programme.dart';
import '../i18n/app_date_format.dart';

Map<String, Map<String, String>>? _translations;

/// Loads `assets/translations/strings.json` into memory once, during app
/// bootstrap (`main.dart`, awaited before `runApp`) so every
/// [getTranslatedString] lookup after that is a synchronous map read rather
/// than an async asset load per string.
///
/// Safe to skip or to fail: every getter that calls [getTranslatedString]
/// carries its own English fallback, so a missing/malformed asset degrades
/// to English text everywhere rather than crashing or blanking the UI.
Future<void> loadTranslations() async {
  try {
    final raw = await rootBundle.loadString('assets/translations/strings.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _translations = decoded.map(
      (key, value) => MapEntry(key, Map<String, String>.from(value as Map)),
    );
  } on Exception catch (e) {
    debugPrint('[AppStrings] loadTranslations failed, falling back to English defaults: $e');
    _translations = null;
  }
}

/// Returns the localized string for [code] in the current [AppLocale], or
/// [fallback] if translations haven't loaded or have no entry for [code].
/// [params] substitutes `{name}` tokens in the resolved string with
/// caller-supplied values, for parameterized strings.
String getTranslatedString(
  String code,
  String fallback, {
  Map<String, String>? params,
  bool localizeDigits = true,
}) {
  final entry = _translations?[code];
  var result = entry?[AppLocale.isBangla ? 'bn' : 'en'];
  // Prefer the translated entry; otherwise use the English fallback. Params must
  // still be applied in the fallback path — DebugDb / Settings keys often have
  // no strings.json entry yet, and '{n} rows' must not render literally.
  result = (result == null || result.isEmpty) ? fallback : result;
  if (params != null) {
    for (final param in params.entries) {
      // Interpolated values carry the numbers an SK reads — counts, ages,
      // measurements. Converting here catches every templated string at once
      // rather than at hundreds of call sites.
      //
      // Opt out with localizeDigits: false where Latin digits are REQUIRED,
      // not merely preferred: phone numbers (a Bengali-digit number is not
      // dialable), NIDs, HTTP status codes and version strings.
      final value =
          localizeDigits ? BnNumerals.localize(param.value) : param.value;
      result = result!.replaceAll('{${param.key}}', value);
    }
  }
  return result!;
}

/// App-wide identity strings.
abstract final class AppStrings {
  AppStrings._();

  static String get appName => getTranslatedString('appName', 'LEAPWELL');
  static String get appTagline => getTranslatedString('appTagline', 'MedtronicLabs · Frontline Health');
  static String get poweredBy => getTranslatedString('App.poweredBy', 'Powered by Medtronic Labs');

  // ── ANC visit blocking ────────────────────────────────────────────────────
  static String get ancBlockedPostpartumTitle => getTranslatedString('ancBlockedPostpartumTitle', 'ANC Not Available');
  static String get ancBlockedPostpartumMessage => getTranslatedString('ancBlockedPostpartumMessage', 'This patient has completed a delivery or PNC visit. ANC assessments cannot be started after delivery.');
  static String get ancBlockedDuplicateTitle => getTranslatedString('ancBlockedDuplicateTitle', 'ANC Already Recorded Today');
  static String get ancBlockedDuplicateMessage => getTranslatedString('ancBlockedDuplicateMessage', 'An ANC assessment has already been recorded for this patient today. Only one ANC visit is allowed per day.');

  // ── PW registration blocking ──────────────────────────────────────────────
  static String get pwAlreadyEnrolledTitle => getTranslatedString('pwAlreadyEnrolledTitle', 'Already Registered');
  static String get pwAlreadyEnrolledMessage => getTranslatedString('pwAlreadyEnrolledMessage', 'Pregnant Woman registration has already been completed for this patient. The PW profile cannot be re-submitted.');
}

/// Shared, cross-screen labels reused in more than one feature.
abstract final class CommonStrings {
  CommonStrings._();

  static String get required => getTranslatedString('required', 'Required');
  static String get or => getTranslatedString('or', 'or');
  static String get retry => getTranslatedString('Common.retry', 'Retry');
  static String get usePassword => getTranslatedString('usePassword', 'Use password');
  static String get unnamed => getTranslatedString('unnamed', '(unnamed)');
  static String get remove => getTranslatedString('remove', 'Remove');
  static String versionLabel(String version) => getTranslatedString('versionLabel', 'v{version}', params: {'version': version}, localizeDigits: false);
  static String get comingSoon => getTranslatedString('Common.comingSoon', 'Coming soon');
}

/// Offline-capability indicator copy — `lib/core/widgets/offline_capability_banner.dart`.
abstract final class OfflineCapabilityStrings {
  OfflineCapabilityStrings._();

  static String get worksOffline => getTranslatedString('OfflineCapability.worksOffline', 'Works offline');
  static String get onDeviceSubtitle => getTranslatedString('OfflineCapability.onDeviceSubtitle', 'On-device model · No internet needed');
  static String get offlineReady => getTranslatedString('OfflineCapability.offlineReady', 'Offline ready');
}

/// Login screen + login-flow feedback.
///
/// Pilot slice of the localization seam described at the top of this file —
/// these getters (not `static const`) check [AppLocale.isBangla] at read
/// time so `LoginStrings.signIn` etc. render in the current language without
/// any call site changing.
abstract final class LoginStrings {
  LoginStrings._();

  static String get usernameLabel => getTranslatedString('usernameLabel', 'Username');
  static String get passwordLabel => getTranslatedString('passwordLabel', 'Password');
  static String get signIn => getTranslatedString('signIn', 'Sign in');
  static String get loginFailed => getTranslatedString('loginFailed', 'Login failed');
  static String get useDeviceUnlock => getTranslatedString('useDeviceUnlock', 'Use device unlock');
  static String get fromLockBanner => getTranslatedString('fromLockBanner', 'Biometric cancelled — sign in with password.');
  static String get offlineUsePinHint => getTranslatedString('offlineUsePinHint', 'No internet connection. Use your PIN to continue working.');
  static String get sessionExpiredNeedOnline => getTranslatedString('sessionExpiredNeedOnline', 'Session expired. Connect to the internet to sign in again.');
  static String get forgotPassword => getTranslatedString('forgotPassword', 'Forgot password?');
  static String get forgotPasswordTitle => getTranslatedString('forgotPasswordTitle', 'Reset password');
  static String get forgotPasswordHint => getTranslatedString('forgotPasswordHint', 'Enter your registered email address');
  static String get forgotPasswordSend => getTranslatedString('forgotPasswordSend', 'Send reset link');
  static String get forgotPasswordSuccess => getTranslatedString('forgotPasswordSuccess', 'Password reset link sent. Check your email.');
  static String get emailLabel => getTranslatedString('emailLabel', 'Email');
  static String get showPasswordTooltip => getTranslatedString('Login.showPasswordTooltip', 'Show password');
  static String get hidePasswordTooltip => getTranslatedString('Login.hidePasswordTooltip', 'Hide password');
}

/// Lock / unlock screen + mid-session lock barrier.
///
/// Pilot slice of the localization seam (see [LoginStrings] doc comment).
/// `aponSushashthya`/`aponSushashthyaBn`/`programSubtitle` are NOT
/// converted — they're the app's bilingual brand tagline, always shown
/// beneath the [leapwell] header regardless of UI language, not alternates
/// of each other.
abstract final class LockStrings {
  LockStrings._();

  static String get welcomeBack => getTranslatedString('welcomeBack', 'Welcome back');
  static String get verifyToAccess => getTranslatedString('verifyToAccess', 'Verify your identity to access your dashboard.');
  static String get biometricCancelled => getTranslatedString('biometricCancelled', 'Biometric cancelled');
  static String get unlockWithBiometrics => getTranslatedString('unlockWithBiometrics', 'Unlock with device');

  /// @deprecated Use [unlockWithBiometrics] instead. Kept for migration.
  static String get unlockWithPhonePasswordOrBiometrics =>
      unlockWithBiometrics;
  static String get profileLoading => getTranslatedString('profileLoading', 'Profile loading…');
  static String get offlinePasswordDisabled => getTranslatedString('offlinePasswordDisabled', 'You are offline. Connect to the internet to sign in with password.');

  // Connectivity status row (bottom of the lock screen).
  static String get onlineStatus => getTranslatedString('onlineStatus', 'Online');
  static String get offlineLoginAvailable => getTranslatedString('offlineLoginAvailable', 'Offline login available');

  // Profile detail row labels.
  static String get skIdLabel => getTranslatedString('skIdLabel', 'SK ID');
  static String get upazilaLabel => getTranslatedString('upazilaLabel', 'UPAZILA');
  static String get nidLabel => getTranslatedString('nidLabel', 'NID');
  static String get wardLabel => getTranslatedString('wardLabel', 'Ward');
  static String get households => getTranslatedString('Lock.households', 'households');

  static String welcomeBackNamed(String name) => getTranslatedString('welcomeBackNamed', 'Welcome back, {name}', params: {'name': '$name'});

  static String get signInToStartYourDay => getTranslatedString('signInToStartYourDay', 'Sign in to start your day');
  static String get shasthyaKormi => getTranslatedString('shasthyaKormi', 'SHASTHYA KORMI');
  static String get verifyFingerprint => getTranslatedString('verifyFingerprint', 'Verify fingerprint');
  static String get tapToPlaceFinger => getTranslatedString('tapToPlaceFinger', 'Touch sensor to begin');
  static String get tapToPlaceFingerSubtitle => getTranslatedString('tapToPlaceFingerSubtitle', 'Tap to place your finger and sign in');
  /// Primary header text for the splash and lock screens. LEAPWELL and Apon
  /// Sushashthya were both approved by BRAC; LEAPWELL is the app's primary
  /// name for recall, with Apon Sushashthya shown as the tagline/subtitle
  /// beneath it (see [aponSushashthya], [programSubtitle]).
  static const String leapwell = 'LEAPWELL';
  static const String aponSushashthya = 'Apon Sushashthya';
  static const String aponSushashthyaBn = 'আপন সুস্বাস্থ্য';
  static String get splashTagline => getTranslatedString('splashTagline', 'AI-powered community health for every household in Bangladesh');
  static String get readingFingerprint => getTranslatedString('readingFingerprint', 'Reading fingerprint…');
  static String get fingerprintVerified => getTranslatedString('fingerprintVerified', 'Verified!');
  static String get communityHealth => getTranslatedString('communityHealth', 'Community Health');
  static String get programSubtitle => getTranslatedString('programSubtitle', 'Apon Sushashthya · Community Health');
  static String orUsePin(int len) => getTranslatedString('orUsePin', 'Use {len}-digit PIN', params: {'len': '$len'});
  static String get orDividerLabel => getTranslatedString('Lock.orDividerLabel', 'OR');
  static String get fingerprintSemanticLabel => getTranslatedString('Lock.fingerprintSemanticLabel', 'Authenticate with fingerprint');
}

/// Android `BiometricPrompt` copy + biometric unlock messages.
abstract final class BiometricStrings {
  BiometricStrings._();

  static String get promptTitle => getTranslatedString('promptTitle', 'Fingerprint verification');
  static String get promptHint => getTranslatedString('promptHint', 'Place your finger on the sensor');
  static String get cancelButton => CommonStrings.usePassword;
}

/// Auth/session error messages surfaced to the user.
abstract final class AuthStrings {
  AuthStrings._();

  static String get savedSessionExpired => getTranslatedString('savedSessionExpired', 'Saved session expired — sign in again');
  static String get sessionExpired => getTranslatedString('sessionExpired', 'Session expired');
  static String get invalidCredentials => getTranslatedString('Auth.invalidCredentials', 'Invalid credentials');
  static String get tenantIdMissing => getTranslatedString('Auth.tenantIdMissing', 'Login response missing tenantId');
  static String get noActiveSessionToEnrol => getTranslatedString('Auth.noActiveSessionToEnrol', 'No active session to enrol');
}

/// Network / transport failure copy. Single source for every message
/// `NetworkErrorMapper` surfaces in login, lock, PIN, scribe and assistant.
abstract final class NetworkErrorStrings {
  NetworkErrorStrings._();

  static String get connectionTimedOut => getTranslatedString(
      'NetworkError.connectionTimedOut', 'Connection timed out. Check your signal and try again.');
  static String get requestCancelled => getTranslatedString(
      'NetworkError.requestCancelled', 'Request was cancelled. Please try again.');
  static String get noInternet => getTranslatedString(
      'NetworkError.noInternet', 'No internet connection. Check your signal and try again.');
  static String get accessDenied => getTranslatedString(
      'NetworkError.accessDenied', 'Access denied. Please log out and log back in.');
  static String get notFound => getTranslatedString(
      'NetworkError.notFound', 'The requested data was not found.');
  static String get serverBusy => getTranslatedString(
      'NetworkError.serverBusy', 'Server is busy. Please try again in a moment.');
  static String get serverError => getTranslatedString(
      'NetworkError.serverError', 'Server error. Please try again in a moment.');

  /// Reuses [SyncStrings.syncErrorGeneric] — identical English copy, so it
  /// shares that translation key rather than registering a duplicate.
  static String get somethingWentWrong => SyncStrings.syncErrorGeneric;
}

/// Dashboard screen: greeting, stat cards, biometric-offer dialog, menu.
abstract final class DashboardStrings {
  DashboardStrings._();

  // Greeting parts. Pilot slice of the localization seam (see
  // LoginStrings doc comment).
  static String get goodMorning => getTranslatedString('goodMorning', 'Good Morning');
  static String get goodAfternoon => getTranslatedString('goodAfternoon', 'Good Afternoon');
  static String get goodEvening => getTranslatedString('goodEvening', 'Good Evening');
  static String get communityAtAGlance => getTranslatedString('communityAtAGlance', 'Serving your community');
  static String get refreshTooltip => getTranslatedString('refreshTooltip', 'Refresh');

  // Stat cards.
  static String get totalMembers => getTranslatedString('totalMembers', 'Total\nMembers');
  static String get totalHouseholds => getTranslatedString('totalHouseholds', 'Total\nHouseholds');
  static String get highRiskPatients => getTranslatedString('highRiskPatients', 'High-Risk\nPatients');
  static String get soonBadge => getTranslatedString('soonBadge', 'SOON');
  static String get lookUpMembers => getTranslatedString('lookUpMembers', 'Use the search bar above to look up members');
  static String get lookUpHouseholds => getTranslatedString('lookUpHouseholds', 'Use the search bar above to look up households');
  static String get aiTriageComingSoon => getTranslatedString('aiTriageComingSoon', 'AI triage coming soon — not wired yet');

  // Biometric-offer dialog.
  static String get useDeviceUnlockTitle => getTranslatedString('useDeviceUnlockTitle', 'Use device unlock?');
  static String get biometricOfferSupported => getTranslatedString('biometricOfferSupported', 'Sign in next time with your fingerprint, face, or device PIN — no password needed.');
  static String get biometricOfferUnsupported => getTranslatedString('biometricOfferUnsupported', 'Sign in next time with your fingerprint, face, or device PIN. You may need to set up a screen lock in Android Settings first.');
  static String get notNow => getTranslatedString('notNow', 'Not now');
  static String get enable => getTranslatedString('enable', 'Enable');
  static String get setUpScreenLock => getTranslatedString('setUpScreenLock', 'Set up a screen lock (PIN, pattern, or fingerprint) in Android Settings, then try again.');
  static String get deviceUnlockEnabled => getTranslatedString('deviceUnlockEnabled', 'Device unlock enabled');
  static String get deviceUnlockDisabled => getTranslatedString('deviceUnlockDisabled', 'Device unlock disabled');

  // Overflow menu. Pilot slice of the localization seam.
  static String get enableDeviceUnlock => getTranslatedString('enableDeviceUnlock', 'Enable device unlock');
  static String get disableDeviceUnlock => getTranslatedString('disableDeviceUnlock', 'Disable device unlock');
  static String get signOut => getTranslatedString('signOut', 'Sign out');

  // Confirmation dialogs.
  static String get confirmDisableDeviceUnlock => getTranslatedString('confirmDisableDeviceUnlock', 'Disable device unlock?');
  static String get confirmDisableDeviceUnlockBody => getTranslatedString('confirmDisableDeviceUnlockBody', 'You will need to use your password or PIN to sign in next time.');
  static String get confirmSignOut => getTranslatedString('confirmSignOut', 'Sign out?');
  static String get confirmSignOutBody => getTranslatedString('confirmSignOutBody', 'You will need to sign in again with your password.');
  static String get cancel => getTranslatedString('Dashboard.cancel', 'Cancel');
  static String get disable => getTranslatedString('disable', 'Disable');

  // Sign-out pending-data safety flow.
  static String get syncingBeforeSignOut => getTranslatedString('syncingBeforeSignOut', 'Syncing your data before signing out…');
  static String get signOutOfflineWarningTitle => getTranslatedString('signOutOfflineWarningTitle', 'You\'re offline');
  static String signOutOfflineWarningBody(int count) => getTranslatedString(
        'signOutOfflineWarningBody',
        'You have {count} unsynced record(s). Signing out now will permanently delete them from this device. Continue?',
        params: {'count': '$count'},
      );
  static String get signOutAnyway => getTranslatedString('signOutAnyway', 'Sign out anyway');

  static String couldNotEnable(Object error) => getTranslatedString('couldNotEnable', 'Could not enable: {error}', params: {'error': '$error'});

  /// `Good Morning, Asha` style greeting.
  static String greetingNamed(String part, String name) => getTranslatedString('greetingNamed', '{part}, {name}', params: {'part': '$part', 'name': '$name'});

  // Last-refreshed relative-time labels.
  static String get updatedJustNow => getTranslatedString('updatedJustNow', 'updated just now');
  static String updatedSecondsAgo(int s) => getTranslatedString('updatedSecondsAgo', 'updated {s}s ago', params: {'s': '$s'});
  static String updatedMinutesAgo(int m) => getTranslatedString('updatedMinutesAgo', 'updated {m}m ago', params: {'m': '$m'});
  static String updatedHoursAgo(int h) => getTranslatedString('updatedHoursAgo', 'updated {h}h ago', params: {'h': '$h'});
}

/// Settings menu strings.
/// Copy for the one-time prompt asking the SK to exempt the app from battery
/// optimisation, so a multi-minute sync is not killed by the OEM.
/// Copy for the consolidated permission step shown once during onboarding.
///
/// Explains each permission before Android asks, so the SK sees a reason in
/// Bangla rather than four bare system dialogs mid-visit.
abstract final class PermissionStrings {
  PermissionStrings._();

  static String get title =>
      getTranslatedString('Permissions.title', 'A few permissions to get started');
  /// Framed as a heads-up, not a request. The sheet cannot grant anything —
  /// only Android's own dialogs can — so wording it like an ask makes the
  /// system prompts that follow read as being asked twice.
  static String get subtitle => getTranslatedString(
        'Permissions.subtitle',
        'Next, your phone will ask a few questions. Tap "Allow" on each one, '
        'so you are not interrupted during a visit.',
      );

  static String get cameraTitle =>
      getTranslatedString('Permissions.cameraTitle', 'Camera');
  static String get cameraBody => getTranslatedString(
      'Permissions.cameraBody', 'To scan a National ID card during enrolment.');

  static String get microphoneTitle =>
      getTranslatedString('Permissions.microphoneTitle', 'Microphone');
  static String get microphoneBody => getTranslatedString(
      'Permissions.microphoneBody',
      'To record what the patient says so the app can fill the form for you.');

  static String get locationTitle =>
      getTranslatedString('Permissions.locationTitle', 'Location');
  static String get locationBody => getTranslatedString(
      'Permissions.locationBody', 'To record where a household is, so you can find it again.');

  static String get notificationTitle =>
      getTranslatedString('Permissions.notificationTitle', 'Notifications');
  static String get notificationBody => getTranslatedString(
      'Permissions.notificationBody',
      'To remind you about referrals and follow-ups that are due.');

  static String get allow =>
      getTranslatedString('Permissions.allow', 'OK, got it');
  static String get skip =>
      getTranslatedString('Permissions.skip', 'Not now');

  /// Shown when one or more permissions were permanently denied — requesting
  /// again would show no dialog at all, so the SK must be sent to Settings.
  static String get blockedMessage => getTranslatedString(
        'Permissions.blockedMessage',
        'Some permissions were turned off. You can allow them in Android '
        'Settings whenever you need those features.',
      );
  static String get openSettings =>
      getTranslatedString('Permissions.openSettings', 'Open settings');
}

abstract final class BatteryOptimizationStrings {
  BatteryOptimizationStrings._();

  static String get title =>
      getTranslatedString('BatteryOptimization.title', 'Keep sync running');
  static String get body => getTranslatedString(
        'BatteryOptimization.body',
        'Your phone may stop this app from finishing a sync in the background. '
        'Allowing it to run in the background keeps your households and visits '
        'up to date.',
      );
  static String get openSettings => getTranslatedString(
      'BatteryOptimization.openSettings', 'Open settings');

  /// Settings-screen entry. Deliberately not shown to every SK during setup:
  /// the destination is a vendor battery screen that a frontline user cannot
  /// realistically navigate, and the sync foreground service already survives
  /// Doze without it (verified on device). Kept as an escape hatch for a
  /// supervisor troubleshooting a handset that kills background work.
  static String get settingsRowTitle => getTranslatedString(
      'BatteryOptimization.settingsRowTitle', 'Background sync');
  static String get settingsRowSubtitle => getTranslatedString(
      'BatteryOptimization.settingsRowSubtitle',
      'Allow syncing when the app is closed');
  static String get notNow =>
      getTranslatedString('BatteryOptimization.notNow', 'Not now');
  static String get couldNotOpen => getTranslatedString(
        'BatteryOptimization.couldNotOpen',
        'Could not open your phone\'s settings. You can allow background '
        'activity for this app from Android Settings.',
      );
}

abstract final class SettingsStrings {
  SettingsStrings._();

  static String get darkMode => getTranslatedString('darkMode', 'Dark Mode');
  static String get lightMode => getTranslatedString('lightMode', 'Light Mode');
  static String get systemMode => getTranslatedString('systemMode', 'System Mode');
  static String get appearance => getTranslatedString('appearance', 'Appearance');

  // ── Language row ──────────────────────────────────────────────────────
  static String get language => getTranslatedString('language', 'Language preference');
  static String get english => getTranslatedString('english', 'English');
  static String get bangla => getTranslatedString('bangla', 'বাংলা (Bangla)');

  // ── Settings row ──────────────────────────────────────────────────────
  static String get settings => getTranslatedString('settings', 'Settings');
  static String get settingsSubtitle => getTranslatedString('settingsSubtitle', 'Account, security & app preferences');

  // ── Offline DB browser row (kDebugMode only) ──────────────────────────
  static String get debugDbViewer => getTranslatedString('Settings.debugDbViewer', 'Offline Database');
  static String get debugDbViewerSubtitle => getTranslatedString('Settings.debugDbViewerSubtitle', 'Browse local SQLCipher tables');

  // ── Offline Sync (Spice parity) ───────────────────────────────────────
  static String get offlineSync =>
      getTranslatedString('Settings.offlineSync', 'Offline Sync');
  static String get offlineSyncSubtitle => getTranslatedString(
        'Settings.offlineSyncSubtitle',
        'Push pending households, members & visits',
      );
}

/// Offline Sync screen copy (Spice OfflineSyncActivity).
abstract final class OfflineSyncStrings {
  OfflineSyncStrings._();

  static String get title =>
      getTranslatedString('OfflineSync.title', 'Offline Sync');
  static String get lastSyncedAt =>
      getTranslatedString('OfflineSync.lastSyncedAt', 'Last synced at');
  static String get startPrompt => getTranslatedString(
        'OfflineSync.startPrompt',
        'Start offline sync now?',
      );
  static String get households =>
      getTranslatedString('OfflineSync.households', 'Households');
  static String get householdMembers => getTranslatedString(
        'OfflineSync.householdMembers',
        'Household Members',
      );
  static String get assessments =>
      getTranslatedString('OfflineSync.assessments', 'Assessments');
  static String get failedPendingRetry => getTranslatedString(
        'OfflineSync.failedPendingRetry',
        'Failed — will retry on Start',
      );
  static String get followUps =>
      getTranslatedString('OfflineSync.followUps', 'Follow-ups');
  static String get cancel =>
      getTranslatedString('OfflineSync.cancel', 'Cancel');
  static String get start =>
      getTranslatedString('OfflineSync.start', 'Start');
  static String get started => getTranslatedString(
        'OfflineSync.started',
        'Offline data has started to sync',
      );
  static String get offlineData =>
      getTranslatedString('OfflineSync.offlineData', 'Offline data');
  static String progressPercent(int pct) => getTranslatedString(
      'OfflineSync.progressPercent', '{pct}%', params: {'pct': '$pct'});
  static String get completed => getTranslatedString(
        'OfflineSync.completed',
        'Offline data sync completed',
      );
  static String get failed => getTranslatedString(
        'OfflineSync.failed',
        'Offline data sync failed',
      );
  static String get okay => getTranslatedString('OfflineSync.okay', 'Okay');
  static String get retry => getTranslatedString('OfflineSync.retry', 'Retry');
  static String get alreadyRunning => getTranslatedString(
        'OfflineSync.alreadyRunning',
        'A sync is already in progress',
      );

  // `OfflinePushService` outcome messages. These carry the exact English the
  // service used to hardcode, so the refactor changes no visible copy. They are
  // deliberately NOT folded into [completed] / [failed] / [alreadyRunning],
  // whose wording differs.
  static String get notAuthenticated => getTranslatedString(
      'OfflineSync.notAuthenticated', 'Not authenticated — sign in again before syncing');
  static String get syncAlreadyInProgress =>
      getTranslatedString('OfflineSync.syncAlreadyInProgress', 'Sync already in progress');
  static String get nothingPendingToSync =>
      getTranslatedString('OfflineSync.nothingPendingToSync', 'Nothing pending to sync');
  static String get noNetworkChangesKept =>
      getTranslatedString('OfflineSync.noNetworkChangesKept', 'No network — changes kept for retry');
  static String get followUpSyncFailedRetry => getTranslatedString(
      'OfflineSync.followUpSyncFailedRetry', 'Follow-up sync failed — retry Offline Sync');
  static String get reportedFailedForSomeRecords => getTranslatedString(
      'OfflineSync.reportedFailedForSomeRecords', 'Sync reported Failed for some records');
  static String get acceptedStillProcessing => getTranslatedString(
      'OfflineSync.acceptedStillProcessing',
      'Sync accepted — server still processing. Open Offline Sync again to refresh.');
  static String get offlineSyncCompleted =>
      getTranslatedString('OfflineSync.offlineSyncCompleted', 'Offline sync completed');

  /// [status] is passed pre-stringified so a null status code still renders as
  /// it does today.
  static String syncFailedHttp(String status) => getTranslatedString(
      'OfflineSync.syncFailedHttp', 'Sync failed (HTTP {status})', params: {'status': status}, localizeDigits: false);
}

/// AI Settings sub-page — realtime-ASR VAD gate tuning UI. An internal/ops
/// tool (data-cost tuning for field conditions), not part of the CHW visit
/// flow, so English-only for now rather than the dual-language getter
/// pattern used for clinical-workflow copy elsewhere in this file.
abstract final class AiSettingsStrings {
  AiSettingsStrings._();

  static String get title => getTranslatedString('AiSettings.title', 'AI Settings');
  static String get appBarSubtitle => getTranslatedString('AiSettings.appBarSubtitle', 'Realtime ASR — voice detection tuning');
  static String get sectionHeader => getTranslatedString('sectionHeader', 'Voice activity gate (VAD)');
  static String get sectionDescription => getTranslatedString('sectionDescription', 'Controls which mic audio is worth sending to the server during a live scribe session — saves mobile data, since the CHW pays for their own connection. A gate that is too strict can silently drop real speech from a quiet speaker; too loose sends more silence than necessary. Changes apply to the next recording session.');
  static String get resetToDefaults => getTranslatedString('resetToDefaults', 'Reset to defaults');
  static String get resetConfirmation => getTranslatedString('resetConfirmation', 'Tuning reset to factory defaults.');
  static String get savedConfirmation => getTranslatedString('savedConfirmation', 'Tuning saved.');

  static String get enterMarginLabel => getTranslatedString('enterMarginLabel', 'Entry sensitivity');
  static String get enterMarginDesc => getTranslatedString('enterMarginDesc', 'How many dB above the room\'s noise floor a sound must be to start being treated as speech. Lower = more sensitive to quiet speakers, but more likely to also pick up background noise.');

  static String get sustainMarginLabel => getTranslatedString('sustainMarginLabel', 'Sustain sensitivity');
  static String get sustainMarginDesc => getTranslatedString('sustainMarginDesc', 'Lower bar used to *stay* in speech mode once started, so a natural dip in volume mid-sentence doesn\'t cut the recording. Should stay below entry sensitivity.');

  static String get floorCeilingLabel => getTranslatedString('floorCeilingLabel', 'Noise floor ceiling');
  static String get floorCeilingDesc => getTranslatedString('floorCeilingDesc', 'Caps how high the "background noise" estimate is allowed to climb in a loud room. Lower ceiling = easier for a quiet speaker to be heard over noisy surroundings.');

  static String get floorAlphaLabel => getTranslatedString('floorAlphaLabel', 'Noise floor adaptation speed');
  static String get floorAlphaDesc => getTranslatedString('floorAlphaDesc', 'How quickly the background-noise estimate adjusts to the room. Higher = adapts faster to a changing environment.');

  static String get bootstrapLabel => getTranslatedString('bootstrapLabel', 'Startup calibration window');
  static String get bootstrapDesc => getTranslatedString('bootstrapDesc', 'How long at the very start of a recording is assumed silent, to measure the room\'s baseline noise. Longer reduces the risk of an immediate opening sentence skewing that baseline.');

  static String get debounceLabel => getTranslatedString('debounceLabel', 'Speech confirmation window');
  static String get debounceDesc => getTranslatedString('debounceDesc', 'How long a sound must stay above the entry threshold before it\'s confirmed as real speech (filters out a single click or cough).');

  static String get hangoverLabel => getTranslatedString('hangoverLabel', 'Trailing silence window');
  static String get hangoverDesc => getTranslatedString('hangoverDesc', 'How long to keep recording after volume drops, to bridge a natural pause between words or sentences without cutting them apart.');

  static String get preRollLabel => getTranslatedString('preRollLabel', 'Pre-speech buffer');
  static String get preRollDesc => getTranslatedString('preRollDesc', 'How much audio just before speech is confirmed gets included anyway, so the very first word isn\'t clipped.');

  static String get widgetsSectionHeader => getTranslatedString('widgetsSectionHeader', 'AI widgets');
  static String get widgetsSectionDescription => getTranslatedString('widgetsSectionDescription', 'Turn off any AI-generated surface the SK doesn\'t want — each one still shows the equivalent local, rule-based content instead of nothing, and skips the network call, saving mobile data.');
  static String get widgetsResetToDefaults => getTranslatedString('widgetsResetToDefaults', 'Reset to default');
  static String get selectAllLabel => getTranslatedString('selectAllLabel', 'Select all');
  static String get selectAllDesc => getTranslatedString('selectAllDesc', 'Turn every AI widget below on or off at once.');

  static String get step1Header => getTranslatedString('step1Header', 'Step 1 — Symptoms');
  static String get step1SummaryLabel => getTranslatedString('step1SummaryLabel', 'Visit summary');
  static String get step1SummaryDesc => getTranslatedString('step1SummaryDesc', 'The "Before You Knock" briefing cards shown before symptom entry.');
  static String get step1AsrLabel => getTranslatedString('step1AsrLabel', 'Voice symptom capture');
  static String get step1AsrDesc => getTranslatedString('step1AsrDesc', 'AI Scribe voice capture that pre-ticks symptom cards from what the SK says.');

  static String get step2Header => getTranslatedString('step2Header', 'Step 2 — Assessment form');
  static String get step2AsrLabel => getTranslatedString('step2AsrLabel', 'Voice form fill');
  static String get step2AsrDesc => getTranslatedString('step2AsrDesc', 'AI Scribe voice capture that fills in the vitals and clinical form fields.');

  static String get step3Header => getTranslatedString('step3Header', 'Step 3 — Recommendation');
  static String get step3SummaryLabel => getTranslatedString('step3SummaryLabel', 'Visit summary & recommendations');
  static String get step3SummaryDesc => getTranslatedString('step3SummaryDesc', 'The AI-generated visit summary, next actions, counselling, and follow-up plan.');
  static String get step3ReferralAlertLabel => getTranslatedString('step3ReferralAlertLabel', 'Danger sign / referral alert');
  static String get step3ReferralAlertDesc => getTranslatedString('step3ReferralAlertDesc', 'The alert card that flags danger signs and recommends a referral.');
  static String get step3WhatsAppLabel => getTranslatedString('step3WhatsAppLabel', 'WhatsApp draft');
  static String get step3WhatsAppDesc => getTranslatedString('step3WhatsAppDesc', 'The pre-written WhatsApp message summarising the visit for the patient.');

  static String get micSectionHeader => getTranslatedString('micSectionHeader', 'Microphone capture');
  static String get micSectionDescription => getTranslatedString('micSectionDescription', 'How AI Scribe opens the microphone. Leave off for normal visits — the handset\'s built-in audio processing gives the clearest recording of someone speaking directly at the phone.');
  static String get rawMicCaptureLabel => getTranslatedString('rawMicCaptureLabel', 'Raw microphone capture');
  static String get rawMicCaptureDesc => getTranslatedString('rawMicCaptureDesc', 'Bypasses the phone\'s echo cancellation so audio played out loud near the handset — a recorded test clip, or a second phone on speaker — is picked up instead of being cancelled out as echo. Only needed for testing and demos. Applies from the next recording.');
}

/// Real-Time ASR screen — live streaming transcription + live clinical
/// extraction against the ai-scribe-service, triggered from Settings.
/// Strings for Step 2 ambient listening / form-fill banner.
abstract final class Step2AsrStrings {
  Step2AsrStrings._();

  static String get bannerTitle => getTranslatedString('bannerTitle', 'AI Form Fill');
  static String get bannerSubtitle => getTranslatedString('bannerSubtitle', 'Speak naturally — AI fills form fields as you talk.');
  static String get startListening => getTranslatedString('startListening', 'Start Listening');
  static String get stopListening => getTranslatedString('stopListening', 'Stop');
  static String get connecting => getTranslatedString('Step2Asr.connecting', 'Connecting…');
  static String get listening => getTranslatedString('Step2Asr.listening', 'Listening…');
  static String get stopping => getTranslatedString('Step2Asr.stopping', 'Stopping…');
  static String get notListening => getTranslatedString('notListening', 'Tap to start ambient form-fill');
  static String get transcriptEmpty => getTranslatedString('Step2Asr.transcriptEmpty', 'Speak — transcript will appear here.');
  static String get noFieldsYet => getTranslatedString('noFieldsYet', 'No fields extracted yet.');
  static String get extractNow => getTranslatedString('Step2Asr.extractNow', 'Fill Now');
  static String get extracting => getTranslatedString('Step2Asr.extracting', 'Filling…');
  static String get notSupportedOnWeb => getTranslatedString('Step2Asr.notSupportedOnWeb', 'Step 2 AI form-fill is not available in the web preview.');
  static String get micPermissionDenied => getTranslatedString('Step2Asr.micPermissionDenied', 'Microphone permission is required.');
  static String get fieldsFilled => getTranslatedString('fieldsFilled', 'fields filled');
  static String get tapToEdit => getTranslatedString('tapToEdit', 'Review highlighted fields in the form below.');
  static String get unmappedLabel => getTranslatedString('unmappedLabel', 'Not matched:');
  static String get aiFilledBadge => getTranslatedString('aiFilledBadge', 'AI · verify');

  static String filledCount(int n) => '$n $fieldsFilled';
}

abstract final class RealtimeAsrStrings {
  RealtimeAsrStrings._();

  static String get title => getTranslatedString('RealtimeAsr.title', 'Real-Time ASR (Beta)');
  static String get subtitle => getTranslatedString('RealtimeAsr.subtitle', 'Live transcript and detected symptoms while you talk. Not saved as a visit note — use AI Scribe during the visit for that.');
  static String get start => getTranslatedString('start', 'Start Listening');
  static String get stop => getTranslatedString('stop', 'Stop');

  /// Accessibility label for the AI Scribe banner's tap target while the
  /// realtime "LIVE" ASR toggle is active.
  static String get stopLiveLabel => getTranslatedString('RealtimeAsr.stopLiveLabel', 'Stop live ASR');
  static String get connecting => getTranslatedString('RealtimeAsr.connecting', 'Connecting…');
  static String get listening => getTranslatedString('RealtimeAsr.listening', 'Listening…');
  static String get stopping => getTranslatedString('RealtimeAsr.stopping', 'Stopping…');
  static String get idle => getTranslatedString('RealtimeAsr.idle', 'Idle');
  static String get transcriptEmpty => getTranslatedString('RealtimeAsr.transcriptEmpty', 'Tap Start Listening and speak — the live transcript appears here.');
  static String get extractNow => getTranslatedString('RealtimeAsr.extractNow', 'Extract Now');
  static String get extracting => getTranslatedString('RealtimeAsr.extracting', 'Extracting…');
  static String get symptomsEmpty => getTranslatedString('symptomsEmpty', 'No extraction yet.');
  static String get notSupportedOnWeb => getTranslatedString('RealtimeAsr.notSupportedOnWeb', 'Real-time ASR is not available in the web preview — use the Android or iOS app.');
  static String get micPermissionDenied => getTranslatedString('RealtimeAsr.micPermissionDenied', 'Microphone permission is required for real-time ASR.');

  /// Banner title shown while a live-ASR session is in [RealtimeAsrState.error]
  /// — distinct from [title] so the SK can tell an errored session apart from
  /// one that is actively listening.
  static String get errorTitle => getTranslatedString('RealtimeAsr.errorTitle', 'Real-Time ASR — Error');

  /// Fallback banner subtitle for a [RealtimeAsrState.error] session whose
  /// [RealtimeAsrController.errorMessage] is somehow null — should not occur
  /// in practice ([RealtimeAsrController] always sets a message alongside the
  /// error state), but keeps the banner from ever rendering an empty subtitle.
  static String get genericError => getTranslatedString('RealtimeAsr.genericError', 'Real-time ASR ran into a problem.');

  /// Generic connectivity-failure message shown to the SK whenever the live
  /// session cannot reach (or loses) the realtime ASR WebSocket — covers the
  /// "channel never came up" start failure, a mid-session socket error, and
  /// any other exception raised while starting the session. Deliberately
  /// generic and non-technical: the underlying exception text (`'$e'`) is
  /// never shown to the user, only logged via [AsrDiagnostics.event]'s
  /// diagnostic-only `category` field.
  static String get connectionUnavailable => getTranslatedString(
      'RealtimeAsr.connectionUnavailable', "Couldn't connect — check your network and try again.");

  /// Shown when the server's `{"type":"error"}` frame carries the
  /// `audio_transcription_failed` code — the one raw backend error code this
  /// controller recognizes and gives a specific, localized message for.
  /// Any other/unrecognized code falls back to [genericError].
  static String get audioTranscriptionFailed => getTranslatedString(
      'RealtimeAsr.audioTranscriptionFailed', "Couldn't transcribe the audio — try speaking again.");

  static String get bloodPressure => getTranslatedString('bloodPressure', 'Blood Pressure');
  static String get bloodGlucose => getTranslatedString('bloodGlucose', 'Blood Glucose');
  static String get clinicalNotes => getTranslatedString('clinicalNotes', 'Clinical Notes');
  static String get chiefComplaints => getTranslatedString('chiefComplaints', 'Chief Complaints');
  static String get comorbidities => getTranslatedString('comorbidities', 'Comorbidities');
  static String get complications => getTranslatedString('complications', 'Complications');

  static String connectionError(String detail) => getTranslatedString(
      'RealtimeAsr.connectionError', 'Connection error: {detail}', params: {'detail': detail});
  static String couldNotStart(String detail) => getTranslatedString(
      'RealtimeAsr.couldNotStart', 'Could not start real-time ASR: {detail}', params: {'detail': detail});
  static String get noMicSignal => getTranslatedString(
      'RealtimeAsr.noMicSignal', 'No mic signal detected — check the device microphone.');
  static String get micSignalStuck => getTranslatedString(
      'RealtimeAsr.micSignalStuck',
      'Mic signal looks stuck/invalid — check the device microphone '
          '(on an emulator, try a cold restart with host audio input enabled, '
          'or test on a physical device).');

  // "Label: {value}" prefixes for the live-extraction summary line. Distinct
  // from the bare-label getters above, which carry no colon and no value.
  static String bloodPressurePrefix(String bp) => getTranslatedString(
      'RealtimeAsr.bloodPressurePrefix', 'BP: {bp}', params: {'bp': bp});
  static String glucosePrefix(String glucose) => getTranslatedString(
      'RealtimeAsr.glucosePrefix', 'Glucose: {glucose}', params: {'glucose': glucose});
  static String diagnosisPrefix(String diagnosis) => getTranslatedString(
      'RealtimeAsr.diagnosisPrefix', 'Diagnosis: {diagnosis}', params: {'diagnosis': diagnosis});
  static String comorbiditiesPrefix(String list) => getTranslatedString(
      'RealtimeAsr.comorbiditiesPrefix', 'Comorbidities: {list}', params: {'list': list});
}

/// Global search bar, scopes, result sections, and detail snackbars.
abstract final class SearchStrings {
  SearchStrings._();

  static String get barHint => getTranslatedString('barHint', 'Name, Mobile, NID');
  static String get scopeAll => getTranslatedString('scopeAll', 'All');
  static String get scopePatients => getTranslatedString('scopePatients', 'Patients');
  static String get scopeHouseholds => getTranslatedString('scopeHouseholds', 'Households');
  static String get searchFailed => getTranslatedString('searchFailed', 'Search failed — try again.');
  static String get emptyPrompt => getTranslatedString('emptyPrompt', 'Type a name, phone, NID, or household number');
  static String get noMatches => getTranslatedString('noMatches', 'No matches.');
  static String get noPatientMatches => getTranslatedString('noPatientMatches', 'No patient matches.');
  static String get noHouseholdMatches => getTranslatedString('noHouseholdMatches', 'No household matches.');
  static String get resultsCapped => getTranslatedString('resultsCapped', 'Result list capped — refine your query');
  static String get patientDetailNotImplemented => getTranslatedString('patientDetailNotImplemented', 'Patient detail not implemented');
  static String get householdDetailNotImplemented => getTranslatedString('householdDetailNotImplemented', 'Household detail not implemented');

  static String scanningHouseholds(int loaded, int cap) => getTranslatedString('scanningHouseholds', 'Scanning households {loaded}/{cap}…', params: {'loaded': '$loaded', 'cap': '$cap'});
  static String age(Object age) => getTranslatedString('age', 'Age {age}', params: {'age': '$age'});
  static String nid(Object nid) => getTranslatedString('nid', 'NID {nid}', params: {'nid': '$nid'}, localizeDigits: false);
  static String householdNo(Object no) => getTranslatedString('householdNo', 'No {no}', params: {'no': '$no'});
  static String memberCount(Object count) => getTranslatedString('memberCount', '{count} members', params: {'count': '$count'});
  static String get scanNidTooltip => getTranslatedString('scanNidTooltip', 'Scan NID or QR to find patient');
  static String get scanSearchTitle => getTranslatedString('scanSearchTitle', 'Scan to Search');
  static String get scanSearchSubtitle => getTranslatedString('scanSearchSubtitle', 'Point at NID card or QR code');
  static String get memberIdNotAvailable => getTranslatedString('Search.memberIdNotAvailable', 'Member ID not available');
  static String get householdIdNotAvailable => getTranslatedString('Search.householdIdNotAvailable', 'Household ID not available');
}

/// App-specific fallback PIN: setup (create + confirm), unlock, and management.
/// Length-aware copy, parameterized by [AppConfig.pinLength] (fixed at 4).
abstract final class PinStrings {
  PinStrings._();

  static String get confirmTitle => getTranslatedString('confirmTitle', 'Confirm your PIN');
  static String get createSubtitle => getTranslatedString('createSubtitle', 'Use this PIN when fingerprint is unavailable.');
  static String get mismatch => getTranslatedString('mismatch', 'PINs do not match — try again');
  static String get wrong => getTranslatedString('wrong', 'Incorrect PIN');
  static String get tooManyAttempts => getTranslatedString('tooManyAttempts', 'Too many attempts — sign in with password');
  static String get enabledSnack => getTranslatedString('enabledSnack', 'PIN enabled');
  static String get disabledSnack => getTranslatedString('disabledSnack', 'PIN disabled');
  static String get enablePin => getTranslatedString('enablePin', 'Set up PIN');
  static String get disablePin => getTranslatedString('disablePin', 'Remove PIN');

  // Confirmation dialog.
  static String get confirmRemovePin => getTranslatedString('confirmRemovePin', 'Remove PIN?');
  static String get confirmRemovePinBody => getTranslatedString('confirmRemovePinBody', 'You will need to use your password or biometrics to sign in next time.');
  static String get deleteKey => getTranslatedString('deleteKey', 'Delete');

  static String createTitle(int len) => getTranslatedString('createTitle', 'Create a {len}-digit PIN', params: {'len': '$len'});
  static String enterTitle(int len) => getTranslatedString('enterTitle', 'Enter your {len}-digit PIN', params: {'len': '$len'});
  static String usePin(int len) => getTranslatedString('usePin', 'Use {len}-digit PIN', params: {'len': '$len'});
  static String get usePinShort => getTranslatedString('usePinShort', 'Use PIN');
  static String attemptsRemaining(int n) => getTranslatedString('attemptsRemaining', '{n} attempts remaining', params: {'n': '$n'});
  static String get backTooltip => getTranslatedString('Pin.backTooltip', 'Back');
}

/// First-login data sync: the guided "downloading your data" gate and the
/// dashboard data-freshness badge.
abstract final class SyncStrings {
  SyncStrings._();

  static String get title => getTranslatedString('Sync.title', 'Setting up your data');
  static String get subtitle => getTranslatedString('Sync.subtitle', 'Downloading your households and patients so you can work offline.');

  // Per-entity labels used in progress lines and the data-as-of badge.
  static String get households => getTranslatedString('Sync.households', 'households');
  static String get members => getTranslatedString('members', 'members');
  static String get patients => getTranslatedString('Sync.patients', 'patients');

  /// Shown while a slow bulk pull is being replayed, so the sync screen reports
  /// activity instead of sitting still for the whole retry budget.
  static String retryingAttempt(int n, int of) => getTranslatedString(
        'Sync.retryingAttempt',
        'Retrying… ({n} of {of})',
        params: {'n': '$n', 'of': '$of'},
      );

  // Foreground-service notification shown while sync runs with the app
  // minimized or the screen off, plus the in-app strip on every tab.
  static String get notificationChannelName =>
      getTranslatedString('Sync.notificationChannelName', 'Data sync');
  static String get notificationTitle =>
      getTranslatedString('Sync.notificationTitle', 'Apon Sushashthya');
  static String get notificationStarting =>
      getTranslatedString('Sync.notificationStarting', 'Syncing your data…');
  static String get notificationFailedTitle =>
      getTranslatedString('Sync.notificationFailedTitle', 'Sync failed');
  static String notificationProgress(String entity, int done, int total) =>
      getTranslatedString(
        'Sync.notificationProgress',
        'Syncing {entity} {done}/{total}',
        params: {'entity': entity, 'done': '$done', 'total': '$total'},
      );

  /// Label on the in-app sync strip shown across every tab while syncing.
  static String get inProgressStrip =>
      getTranslatedString('Sync.inProgressStrip', 'Syncing your data…');

  // Persist sub-phases — what the app is writing locally after the download.
  static String get savingHouseholds =>
      getTranslatedString('Sync.savingHouseholds', 'Saving households');
  static String get savingMembers =>
      getTranslatedString('Sync.savingMembers', 'Saving members');
  static String get savingPatients =>
      getTranslatedString('Sync.savingPatients', 'Saving patient records');
  static String get savingProgrammes =>
      getTranslatedString('Sync.savingProgrammes', 'Saving programmes');
  static String get savingFollowUps =>
      getTranslatedString('Sync.savingFollowUps', 'Saving follow-ups');
  static String get finalising =>
      getTranslatedString('Sync.finalising', 'Finishing up');

  /// Strip text combining the step description with its counts, e.g.
  /// "Downloading patients · 240/1200". Kept separate from
  /// [notificationProgress] because that one takes a bare entity noun; this
  /// one takes a full step label and must not read "Syncing Downloading …".
  static String stripProgress(String label, int done, int total) =>
      getTranslatedString(
        'Sync.stripProgress',
        '{label} · {done}/{total}',
        params: {'label': label, 'done': '$done', 'total': '$total'},
      );

  static String get done => getTranslatedString('Sync.done', 'Ready to go');
  static String get syncFailed => getTranslatedString('Sync.syncFailed', 'We couldn\'t finish downloading your data.');
  static String get syncErrorNoInternet => getTranslatedString('syncErrorNoInternet', 'No internet connection. Please check your network and try again.');
  static String get syncErrorTimeout => getTranslatedString('syncErrorTimeout', 'Connection timed out. Please try again.');
  static String get syncErrorServer => getTranslatedString('syncErrorServer', 'Could not reach the server. Please try again later.');
  static String get syncErrorGeneric => getTranslatedString('syncErrorGeneric', 'Something went wrong. Please try again.');
  static String get syncErrorSessionExpired => getTranslatedString(
        'syncErrorSessionExpired',
        'Your session expired. Sign in again online before syncing.',
      );
  static String get signInAgain => getTranslatedString('Sync.signInAgain', 'Sign in again');
  static String get continueOffline => getTranslatedString('continueOffline', 'Continue with what we have');
  static String get retry => CommonStrings.retry;

  static String get refreshing => getTranslatedString('Sync.refreshing', 'Updating your data…');
  static String get upToDate => getTranslatedString('upToDate', 'Data up to date');

  /// `Downloading households… 120 of 340`.
  static String progressNamed(String entity, int done, int total) => total > 0
      ? 'Downloading $entity… $done of $total'
      : 'Downloading $entity… $done';

  /// `Households 340 · Patients 512` style summary line on completion.
  static String entityCount(String entity, int count) => getTranslatedString('entityCount', '{entity} {count}', params: {'entity': '$entity', 'count': '$count'});

  /// Relative-time data-freshness badge, e.g. `Data as of 2 days ago`.
  static String dataAsOf(String relative) => getTranslatedString('dataAsOf', 'Data as of {relative}', params: {'relative': '$relative'});
  static String get dataAsOfJustNow => getTranslatedString('dataAsOfJustNow', 'Data as of just now');
  static String dataAsOfMinutes(int m) => getTranslatedString('dataAsOfMinutes', 'Data as of {m}m ago', params: {'m': '$m'});
  static String dataAsOfHours(int h) => getTranslatedString('dataAsOfHours', 'Data as of {h}h ago', params: {'h': '$h'});
  static String dataAsOfDays(int d) => getTranslatedString('dataAsOfDays', 'Data as of {d}d ago', params: {'d': '$d'});

  // Dashboard preparation phase (after sync, before navigation)
  static String get almostReady => getTranslatedString('almostReady', 'Almost ready');
  static String get preparingVisits => getTranslatedString('preparingVisits', 'Preparing today\'s visits…');
  static String get preparingDashboard => getTranslatedString('preparingDashboard', 'Setting up your dashboard…');
  static String get dataReady => getTranslatedString('Sync.dataReady', 'Your data is ready');

  // `SyncStep` labels.
  static String get connectingToServer =>
      getTranslatedString('Sync.connectingToServer', 'Connecting to server');
  static String get downloadingPatients =>
      getTranslatedString('Sync.downloadingPatients', 'Downloading patients');
  static String get downloadingFollowUps =>
      getTranslatedString('Sync.downloadingFollowUps', 'Downloading follow-ups');
  static String get downloadingReferrals =>
      getTranslatedString('Sync.downloadingReferrals', 'Downloading referrals');
  static String get processingData => getTranslatedString('Sync.processingData', 'Processing data');
  static String get readyStatus => getTranslatedString('Sync.readyStatus', 'Ready');
}

/// First-login onboarding: security setup prompt.
abstract final class OnboardingStrings {
  OnboardingStrings._();

  static String get title => getTranslatedString('Onboarding.title', 'Secure Your Account');
  static String get subtitle => getTranslatedString('Onboarding.subtitle', 'Set up quick, secure access to LEAPWELL using your device\'s biometrics and a backup PIN.');

  static String get biometricFeatureTitle => getTranslatedString('biometricFeatureTitle', 'Device Unlock');
  static String get biometricFeatureDesc => getTranslatedString('biometricFeatureDesc', 'Use fingerprint, face, or device PIN for fast sign-in.');
  static String get biometricNotAvailable => getTranslatedString('biometricNotAvailable', 'Set up a screen lock in Android Settings to enable this feature.');

  static String get pinFeatureDesc => getTranslatedString('pinFeatureDesc', 'A backup option when biometrics are unavailable.');

  static String get setupButton => getTranslatedString('setupButton', 'Set Up Security');
  static String get skipButton => getTranslatedString('Onboarding.skipButton', 'Skip for Now');
  static String get pinRequiredNote => getTranslatedString('pinRequiredNote', 'Note: You can set up security options later from the settings menu.');

  static String get skipConfirmTitle => getTranslatedString('Onboarding.skipConfirmTitle', 'Skip Security Setup?');
  static String get skipConfirmBody => getTranslatedString('Onboarding.skipConfirmBody', 'Without biometric or PIN authentication, you will need to enter your password each time you open the app. You can set these up later from settings.');
  static String get cancelButton => getTranslatedString('cancelButton', 'Cancel');
  static String get skipAnywayButton => getTranslatedString('Onboarding.skipAnywayButton', 'Skip Anyway');

  static String get notAvailable => getTranslatedString('Onboarding.notAvailable', 'Not available');
  static String get biometricSetupFailed => getTranslatedString('biometricSetupFailed', 'Could not enable device unlock. You can enable it later from the menu.');

  static String pinFeatureTitle(int len) => getTranslatedString('pinFeatureTitle', '{len}-Digit Backup PIN', params: {'len': '$len'});
}

/// Household / member list screens.
abstract final class HouseholdListStrings {
  HouseholdListStrings._();

  static String get loadError => getTranslatedString('HouseholdList.loadError', 'Could not load data');
  static String get noMembers => getTranslatedString('HouseholdList.noMembers', 'No members found');
  static String get unnamedHousehold => getTranslatedString('HouseholdList.unnamedHousehold', '(Unnamed household)');
  static String get unnamedMember => getTranslatedString('unnamedMember', '(Unnamed)');

  /// UHIS-aligned possessive household name (`{name}-এর খানা`).
  static String namedHousehold(String headName) => getTranslatedString(
        'Household.namedHousehold',
        "{name}'s Household",
        params: {'name': headName},
      );

  static String householdsCount(int n) => getTranslatedString('householdsCount', '{n} households', params: {'n': '$n'});
  static String membersCount(int n) => getTranslatedString('membersCount', '{n} members', params: {'n': '$n'});

  // Header (v13 mockup: navy header, 🏠 title, combined live count)
  static String get headerTitle => getTranslatedString('headerTitle', '🏠 Households & Patients');
  static String headerSummary(int households, int patients) =>
      '${householdsCount(households)} · ${_patientsCount(patients)}';
  static String _patientsCount(int n) => getTranslatedString(
        'HouseholdList.patientsCount',
        '$n patient${n == 1 ? '' : 's'}',
        params: {'n': '$n'},
      );
  static String get searchHint => getTranslatedString('HouseholdList.searchHint', 'Search by name or village…');

  // Household-card inline other-members panel
  static String otherMembersToggle(int n) => getTranslatedString(
        'HouseholdList.otherMembersToggle',
        '+$n other household member${n == 1 ? '' : 's'}',
        params: {'n': '$n'},
      );
  static String get enrolledTag => getTranslatedString('enrolledTag', 'Registered');

  // Manual server refresh
  static String refreshSummary(int patients, int assessments, int followUps) => getTranslatedString('refreshSummary', 'Updated: {patients} patients · {assessments} assessments · {followUps} follow-ups', params: {'patients': '$patients', 'assessments': '$assessments', 'followUps': '$followUps'});
  static String refreshFailed(String error) => getTranslatedString('HouseholdList.refreshFailed', 'Refresh failed: {error}', params: {'error': '$error'});
}

/// Household detail screen strings.
/// Shared date-formatting copy. Single home for month abbreviations, which
/// were previously duplicated as a raw `['Jan', 'Feb', …]` array in three files.
abstract final class DateFormatStrings {
  DateFormatStrings._();

  static const _codes = [
    'DateFormat.monthJan', 'DateFormat.monthFeb', 'DateFormat.monthMar',
    'DateFormat.monthApr', 'DateFormat.monthMay', 'DateFormat.monthJun',
    'DateFormat.monthJul', 'DateFormat.monthAug', 'DateFormat.monthSep',
    'DateFormat.monthOct', 'DateFormat.monthNov', 'DateFormat.monthDec',
  ];
  static const _fallbacks = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// [month] is 1-indexed (1 = January).
  static String monthAbbrev(int month) =>
      getTranslatedString(_codes[month - 1], _fallbacks[month - 1]);
}

abstract final class HouseholdDetailStrings {
  HouseholdDetailStrings._();

  static String get unnamedHousehold => getTranslatedString('HouseholdDetail.unnamedHousehold', '(Unnamed household)');
  static String get householdMembers => getTranslatedString('householdMembers', 'Household Members');
  static String get noMembers => getTranslatedString('HouseholdDetail.noMembers', 'No members found');
  static String get notAvailable => getTranslatedString('HouseholdDetail.notAvailable', 'N/A');
  static String get householdNumber => getTranslatedString('HouseholdDetail.householdNumber', 'Household No.');
  static String get village => getTranslatedString('village', 'Village');
  static String get ssName => getTranslatedString('ssName', 'Shasthya Shebika');
  static String get lastVisitDate => getTranslatedString('lastVisitDate', 'Last Visit');
  static String get neverVisited => getTranslatedString('neverVisited', 'Never visited');
  static String get noSsAssigned => getTranslatedString('noSsAssigned', 'Not assigned');
  static String get back => getTranslatedString('back', 'Back');
  static String get loadingMembers => getTranslatedString('loadingMembers', 'Loading members…');
  static String get couldNotLoadMembers => getTranslatedString('couldNotLoadMembers', 'Could not load members');
  static String get loadMembers => getTranslatedString('loadMembers', 'Load members');
  static String get householdIdNotAvailable => getTranslatedString('householdIdNotAvailable', 'Household ID not available');

  static String memberDataNotLoaded(int count) => getTranslatedString('memberDataNotLoaded', 'This household has {count} members.\nDetailed member information will be available once data is synced.', params: {'count': '$count'});

  static String get addMember => getTranslatedString('HouseholdDetail.addMember', 'Add Member');
}

/// AI Worklist (Screen 2): chip filter labels, programme tags, urgent banner,
/// last-synced strip, and the empty/error states. All literal copy for the
/// worklist surface lives here — widgets never inline strings.
abstract final class WorklistStrings {
  WorklistStrings._();

  static String get urgencyToday => getTranslatedString('Worklist.urgencyToday', 'Today');
  static String get urgencyThisWeek => getTranslatedString('Worklist.urgencyThisWeek', 'This week');
  static String get unnamedPatient => getTranslatedString('Worklist.unnamedPatient', '(Unnamed patient)');
}

/// Patient Context Screen (stub) strings. Full design lives in a later spec.
abstract final class PatientContextStrings {
  PatientContextStrings._();

  static String get fallbackTitle => getTranslatedString('PatientContext.fallbackTitle', 'Patient');
  static String get loading => getTranslatedString('loading', 'Loading patient…');
  static String get notFound => getTranslatedString('notFound', 'Patient not in local cache');
  static String get idLabel => getTranslatedString('idLabel', 'Patient ID');
  static String get householdLabel => getTranslatedString('householdLabel', 'Household');
  static String get villageLabel => getTranslatedString('PatientContext.villageLabel', 'Village');
  static String get programmesLabel => getTranslatedString('programmesLabel', 'Programmes');
  static String get riskLabel => getTranslatedString('riskLabel', 'Risk');
  static String get sectionRecentVisits => getTranslatedString('sectionRecentVisits', 'Recent visits');
  static String get sectionVitals => getTranslatedString('sectionVitals', 'Vitals');
  static String get sectionAiSuggestions => getTranslatedString('sectionAiSuggestions', 'AI suggestions');
  static String get sectionActions => getTranslatedString('sectionActions', 'Actions');
  static String get comingSoon => getTranslatedString('PatientContext.comingSoon', 'Coming in a future release');
  static String get refresh => getTranslatedString('refresh', 'Refresh from server');
  static String get refreshing => getTranslatedString('PatientContext.refreshing', 'Refreshing…');
  static String get refreshDone => getTranslatedString('refreshDone', 'Patient refreshed');
  static String get refreshFailed => getTranslatedString('PatientContext.refreshFailed', 'Refresh failed');

  // ── Action buttons ───────────────────────────────────────────────────────
  static String get actionsTitle => getTranslatedString('actionsTitle', 'Actions');
  static String get startVisit => getTranslatedString('startVisit', 'Start Visit');
  static String get callHousehold => getTranslatedString('callHousehold', 'Call');
  static String get callComingSoon => getTranslatedString('callComingSoon', 'Call household coming soon');

  static String get storedDataTitle => getTranslatedString('storedDataTitle', 'Stored data');

  // ── HTML detail composition ──────────────────────────────────────────────
  static String get backToWorklist => getTranslatedString('backToWorklist', 'Back to worklist');
  static String get sayHelloFirst => getTranslatedString('sayHelloFirst', ' Say hello first');
  // Bilingual communication script the SK reads aloud to the patient — shown
  // regardless of the app's own UI language, not a language toggle target.
  static String aiSummaryLead(String name) => getTranslatedString('aiSummaryLead', '{name} has the following risk drivers worth addressing today.', params: {'name': '$name'});

  static String get allAssessmentsTitle => getTranslatedString('allAssessmentsTitle', 'All assessments');

  // ── Header ────────────────────────────────────────────────────────────
  static String get urgentBadge => getTranslatedString('PatientContext.urgentBadge', 'URGENT');
  static String ageLabel(int age) => getTranslatedString('PatientContext.ageLabel', 'Age {age}', params: {'age': '$age'});
  static String ageMonthsLabel(int months) => getTranslatedString(
        'PatientContext.ageMonthsLabel',
        '$months month${months == 1 ? '' : 's'}',
        params: {'months': '$months'},
      );
  static String get ageUnderOneYear => getTranslatedString('ageUnderOneYear', '< 1 yr');
  /// Compact "9m" form for space-constrained cards (dashboard patient card).
  static String ageMonthsCompact(int months) => getTranslatedString('PatientContext.ageMonthsCompact', '{months}m', params: {'months': '$months'});
  static String householdFallback(String householdId) => getTranslatedString('householdFallback', 'HH {householdId}', params: {'householdId': '$householdId'});
  static String get pregnantChip => getTranslatedString('pregnantChip', 'Pregnant');

  // ── Assessments section ──────────────────────────────────────────────
  static String get noAssessmentsYet => getTranslatedString('noAssessmentsYet', 'No assessments yet');
  static String assessmentsTotal(int n) => getTranslatedString('assessmentsTotal', '{n} total', params: {'n': '$n'});
  static String viewAllAssessments(int n) => getTranslatedString('viewAllAssessments', 'View all {n} assessments', params: {'n': '$n'});
  static String visitNumberLabel(int n) => getTranslatedString('visitNumberLabel', 'Visit {n}', params: {'n': '$n'});
  static String get latestBadge => getTranslatedString('latestBadge', 'Latest');
  static String visitOnLabel(String date) => getTranslatedString('visitOnLabel', 'Visit on {date}', params: {'date': '$date'});
  static String get close => getTranslatedString('PatientContext.close', 'Close');
  static String get serviceLabel => getTranslatedString('serviceLabel', 'Service');
  static String get visitNumberFieldLabel => getTranslatedString('visitNumberFieldLabel', 'Visit Number');
  static String get encounterIdLabel => getTranslatedString('encounterIdLabel', 'Encounter ID');
  static String get memberIdLabel => getTranslatedString('memberIdLabel', 'Member ID');
  static String get referralStatusLabel => getTranslatedString('referralStatusLabel', 'Referral Status');
  static String get referralReasonLabel => getTranslatedString('referralReasonLabel', 'Referral Reason');
  static String get nextFollowUpLabel => getTranslatedString('nextFollowUpLabel', 'Next Follow-up');

  // ── Clinical field labels ────────────────────────────────────────────
  static String get yes => getTranslatedString('PatientContext.yes', 'Yes');
  static String get no => getTranslatedString('PatientContext.no', 'No');
  static String get clinicalFindingsTitle => getTranslatedString('clinicalFindingsTitle', 'Clinical Findings');
  static String get ncdFindingsTitle => getTranslatedString('ncdFindingsTitle', 'NCD Screening Findings');
  static String get ancFindingsTitle => getTranslatedString('ancFindingsTitle', 'Antenatal Care Findings');
  static String get pncFindingsTitle => getTranslatedString('pncFindingsTitle', 'Postnatal Care Findings');
  static String get childHealthFindingsTitle => getTranslatedString('childHealthFindingsTitle', 'Child Health Findings');
  static String get tbFindingsTitle => getTranslatedString('tbFindingsTitle', 'TB Screening Findings');
  static String get bloodPressureLabel => getTranslatedString('bloodPressureLabel', 'Blood Pressure');
  static String get glucoseFastingLabel => getTranslatedString(
        'PatientContext.glucoseFasting',
        'Blood Glucose (FBS)',
      );
  static String get glucoseRandomLabel => getTranslatedString(
        'PatientContext.glucoseRandom',
        'Blood Glucose (RBS)',
      );
  static String get respiratoryRateLabel => getTranslatedString(
        'PatientContext.respiratoryRateLabel',
        'Respiratory Rate',
      );
  static String get ancGapsLabel => getTranslatedString(
        'PatientContext.ancGapsLabel',
        'Gaps in ANC',
      );
  static String glucoseLabel(String? type) {
    final t = type?.toLowerCase();
    if (t == 'fasting' || t == 'fbs') return glucoseFastingLabel;
    if (t == 'random' || t == 'rbs') return glucoseRandomLabel;
    final base = getTranslatedString('PatientContext.glucoseLabel', 'Glucose');
    return type != null ? '$base ($type)' : base;
  }
  static String get heightLabel => getTranslatedString('heightLabel', 'Height');
  static String get weightLabel => getTranslatedString('weightLabel', 'Weight');
  static String get bmiLabel => getTranslatedString('bmiLabel', 'BMI');
  static String get haemoglobinLabel => getTranslatedString('haemoglobinLabel', 'Haemoglobin');
  static String get smokingLabel => getTranslatedString('smokingLabel', 'Smoking');
  static String get alcoholLabel => getTranslatedString('alcoholLabel', 'Alcohol');
  static String get ancVisitLabel => getTranslatedString('PatientContext.ancVisitLabel', 'ANC Visit');
  static String get gestationalAgeLabel => getTranslatedString('PatientContext.gestationalAgeLabel', 'Gestational Age');
  static String get fetusesLabel => getTranslatedString('fetusesLabel', 'Fetuses');
  static String get fundalHeightLabel => getTranslatedString('fundalHeightLabel', 'Fundal Height');
  static String get fetalMovementLabel => getTranslatedString('fetalMovementLabel', 'Fetal Movement');
  static String get pncVisitLabel => getTranslatedString('PatientContext.pncVisitLabel', 'PNC Visit');
  static String get breastfeedingLabel => getTranslatedString('breastfeedingLabel', 'Breastfeeding');
  static String get muacLabel => getTranslatedString('PatientContext.muacLabel', 'MUAC');
  static String get temperatureLabel => getTranslatedString('temperatureLabel', 'Temperature');
  static String get diagnosisLabel => getTranslatedString('diagnosisLabel', 'Diagnosis');
  static String get coughDurationLabel => getTranslatedString('coughDurationLabel', 'Cough Duration');
  static String get diabetesLabel => getTranslatedString('diabetesLabel', 'Diabetes');
  static String get tbContactLabel => getTranslatedString('tbContactLabel', 'TB Contact');
  static String get gravidaParityLabel => getTranslatedString('gravidaParityLabel', 'G/P');
  static String get normal => getTranslatedString('normal', 'Normal');
  static String get abnormal => getTranslatedString('abnormal', 'Abnormal');

  // ── AI summary ────────────────────────────────────────────────────────
  static String get aiSummaryBadge => getTranslatedString('aiSummaryBadge', '✦ AI SUMMARY');
  static String get aiReadHerRecordBadge => getTranslatedString('aiReadHerRecordBadge', '✦ AI READ HER RECORD');
  static String riskReasonChip(String reason) => getTranslatedString('riskReasonChip', '⚠ {reason}', params: {'reason': '$reason'});

  // ── Same-household strip ─────────────────────────────────────────────
  static String get sameHousehold => getTranslatedString('sameHousehold', 'Same household');
  static String get viewHouseholdDetails => getTranslatedString('viewHouseholdDetails', 'View household details');
  static String get unknownMemberName => getTranslatedString('unknownMemberName', 'Unknown');
  static String viewPatientSemantics(String name, int? age) {
    if (age != null) {
      return getTranslatedString(
        'PatientContext.viewPatientSemanticsWithAge',
        'View patient {name}, age {age}',
        params: {'name': name, 'age': '$age'},
      );
    }
    return getTranslatedString(
      'PatientContext.viewPatientSemantics',
      'View patient {name}',
      params: {'name': name},
    );
  }

  static String get statusIndicatorsTitle => getTranslatedString('statusIndicatorsTitle', 'Status Indicators');

  // ── Assessment list fallbacks ────────────────────────────────────────
  static String get genericAssessmentLabel => getTranslatedString('genericAssessmentLabel', 'Assessment');
  static String viewAssessmentSemantics(String type, String date) => getTranslatedString('viewAssessmentSemantics', 'View {type} assessment on {date}', params: {'type': '$type', 'date': '$date'});

  // ── Timeline entry titles/categories/badges (_assessmentToEntry) ────────
  static String get ancCheckupTitle => getTranslatedString('ancCheckupTitle', 'ANC Checkup');
  static String get antenatalCareCategory => getTranslatedString('antenatalCareCategory', 'Antenatal Care');
  static String get dangerHighBpBadge => getTranslatedString('dangerHighBpBadge', 'Danger — High BP');
  static String get severeAnemiaBadge => getTranslatedString('severeAnemiaBadge', 'Severe anemia');
  static String get anemiaBadge => getTranslatedString('anemiaBadge', 'Anemia');
  static String get mildAnemiaBadge => getTranslatedString('mildAnemiaBadge', 'Mild anemia');
  static String get pregnancyOutcomeTitle => getTranslatedString('pregnancyOutcomeTitle', 'Pregnancy Outcome');
  static String get deliveryCategory => getTranslatedString('deliveryCategory', 'Delivery');
  static String get stillbirthNeonatalDeathBadge => getTranslatedString('stillbirthNeonatalDeathBadge', 'Stillbirth / Neonatal death');
  static String get pregnancyLossBadge => getTranslatedString('pregnancyLossBadge', 'Pregnancy loss');
  static String get normalDeliveryBadge => getTranslatedString('normalDeliveryBadge', 'Normal delivery');
  static String get postnatalCareCategory => getTranslatedString('postnatalCareCategory', 'Postnatal Care');
  static String get dangerSignBadge => getTranslatedString('dangerSignBadge', 'Danger sign');
  static String get urgentPncBadge => getTranslatedString('urgentPncBadge', 'Urgent');
  static String get ncdVisitTitle => getTranslatedString('ncdVisitTitle', 'NCD Visit');
  static String get ncdHighRiskBadge => getTranslatedString('ncdHighRiskBadge', 'High-risk');
  static String get highBpBadge => getTranslatedString('highBpBadge', 'High BP');
  static String get highBloodSugarBadge => getTranslatedString('highBloodSugarBadge', 'High blood sugar');
  static String get childHealthVisitTitle => getTranslatedString('childHealthVisitTitle', 'Child health visit');
  static String get imciChildCareCategory => getTranslatedString('imciChildCareCategory', 'IMCI / Child care');
  static String get tbFollowUpTitle => getTranslatedString('tbFollowUpTitle', 'TB follow-up');
  static String get tbProgrammeCategory => getTranslatedString('tbProgrammeCategory', 'TB Programme');
  static String get familyPlanningLabel => getTranslatedString('PatientContext.familyPlanningLabel', 'Family Planning');
  static String get malariaTreatedTitle => getTranslatedString('malariaTreatedTitle', 'Malaria — treated');
  static String get severeDiarrheaVomitingTreatedTitle => getTranslatedString('severeDiarrheaVomitingTreatedTitle', 'Severe diarrhea & vomiting — treated');
  static String get feverTreatedTitle => getTranslatedString('feverTreatedTitle', 'Fever — treated');
  static String get generalVisitTitle => getTranslatedString('generalVisitTitle', 'General visit');
  static String get generalCategory => getTranslatedString('PatientContext.generalCategory', 'General');
  static String get referredBadge => getTranslatedString('PatientContext.referredBadge', 'Referred');
  static String get onTreatmentBadge => getTranslatedString('onTreatmentBadge', 'On treatment');
  static String get recoveredBadge => getTranslatedString('PatientContext.recoveredBadge', 'Recovered');

  // ── Stat history sheet (_showStatHistory) ────────────────────────────
  static String get visitHistoryTitle => getTranslatedString('visitHistoryTitle', 'Visit history');
  static String recordsTapToOpen(int count) => getTranslatedString(
        'recordsTapToOpen',
        '$count record${count == 1 ? '' : 's'}  ·  tap to open visit',
        params: {'count': '$count'},
      );

  static String get startVisitFailed => getTranslatedString('PatientContext.startVisitFailed', 'Failed to start visit');
  static String get startingEllipsis => getTranslatedString('PatientContext.startingEllipsis', 'Starting...');
  static String get notApplicable => getTranslatedString('PatientContext.notApplicable', 'N/A');

  // ── Timeline / care-history copy (from missing_bangla product sheet) ──
  static String timelineAncVisitN(Object n) => getTranslatedString(
        'PatientContext.timeline.ancVisitN',
        'ANC Visit $n',
        params: {'n': '$n'},
      );
  static String timelinePncVisitN(Object n) => getTranslatedString(
        'PatientContext.timeline.pncVisitN',
        'PNC Visit $n',
        params: {'n': '$n'},
      );
  static String timelineVaccinationVisitN(Object n) => getTranslatedString(
        'PatientContext.timeline.vaccinationVisitN',
        'Vaccination visit $n',
        params: {'n': '$n'},
      );
  static String timelineAnemiaHb(Object n) => getTranslatedString(
        'PatientContext.timeline.anemiaHb',
        'Anemia (Hb {n}g/dL)',
        params: {'n': '$n'},
      );
  static String get approachingEdd => getTranslatedString(
        'PatientContext.approachingEdd',
        'Approaching EDD — monitor closely',
      );
  static String timelineBabyWeight(Object wt) => getTranslatedString(
        'PatientContext.timeline.babyWeight',
        'Baby {wt} kg.',
        params: {'wt': '$wt'},
      );
  static String get timelineBpRecheckDue => getTranslatedString(
        'PatientContext.timeline.bpRecheckDue',
        'BP recheck due',
      );
  static String timelineBpAboveTarget(Object bp) => getTranslatedString(
        'PatientContext.timeline.bpAboveTarget',
        'BP {bp} above target',
        params: {'bp': '$bp'},
      );
  static String timelineBpIsAboveTarget(Object bp) => getTranslatedString(
        'PatientContext.timeline.bpIsAboveTarget',
        'BP {bp} is above target',
        params: {'bp': '$bp'},
      );
  static String get timelineChildVisitOverdue => getTranslatedString(
        'PatientContext.timeline.childVisitOverdue',
        'Child visit overdue',
      );
  static String timelineDangerSignReported(Object sign) => getTranslatedString(
        'PatientContext.timeline.dangerSignReported',
        'Danger sign reported: {sign}.',
        params: {'sign': '$sign'},
      );
  static String timelineDangerSignUrgentReferral(Object sign) =>
      getTranslatedString(
        'PatientContext.timeline.dangerSignUrgentReferral',
        'Danger sign: {sign} — urgent referral needed.',
        params: {'sign': '$sign'},
      );
  static String get timelineFollowUpOverdue => getTranslatedString(
        'PatientContext.timeline.followUpOverdue',
        'Follow-up overdue',
      );
  static String timelineHbAnemiaReviewIron(Object n) => getTranslatedString(
        'PatientContext.timeline.hbAnemiaReviewIron',
        'Hb {n}g/dL — anemia. Review iron supplementation.',
        params: {'n': '$n'},
      );
  static String timelineHbMildAnemia(Object n) => getTranslatedString(
        'PatientContext.timeline.hbMildAnemia',
        'Hb {n}g/dL — mild anemia. Ensure iron supplementation continues.',
        params: {'n': '$n'},
      );
  static String timelineHbSevereAnemia(Object n) => getTranslatedString(
        'PatientContext.timeline.hbSevereAnemia',
        'Hb {n}g/dL — severe anemia. Urgent review needed.',
        params: {'n': '$n'},
      );
  static String get timelineHealthyDelivery => getTranslatedString(
        'PatientContext.timeline.healthyDelivery',
        'Healthy delivery outcome — mother and baby both doing well.',
      );
  static String get timelineHighBpDetected => getTranslatedString(
        'PatientContext.timeline.highBpDetected',
        'High BP detected — monitor closely.',
      );
  static String get highRiskElevatedBp => getTranslatedString(
        'PatientContext.highRiskElevatedBp',
        'High risk — elevated BP or other flag',
      );
  static String get timelineImciChildCare => getTranslatedString(
        'PatientContext.timeline.imciChildCare',
        'IMCI / Child care',
      );
  static String timelineLastChildVisitDaysAgo(Object n) => getTranslatedString(
        'PatientContext.timeline.lastChildVisitDaysAgo',
        'Last child health visit was {n} days ago — check growth & vaccines',
        params: {'n': '$n'},
      );
  static String timelineMethodFp(Object fp) => getTranslatedString(
        'PatientContext.timeline.methodFp',
        'Method: {fp}',
        params: {'fp': '$fp'},
      );
  static String timelineNcdFollowUpDue(Object n) => getTranslatedString(
        'PatientContext.timeline.ncdFollowUpDue',
        'NCD follow-up due — last visit {n} days ago',
        params: {'n': '$n'},
      );
  static String get timelineNcdEnrollmentRecorded => getTranslatedString(
        'PatientContext.timeline.ncdEnrollmentRecorded',
        'NCD programme enrollment recorded.',
      );
  static String get timelineNoContraception => getTranslatedString(
        'PatientContext.timeline.noContraception',
        'No contraception method in use — counsel on options.',
      );
  static String get timelinePreEclampsiaWatch => getTranslatedString(
        'PatientContext.timeline.preEclampsiaWatch',
        'Pre-eclampsia watch',
      );
  static String get timelinePregnancyLoss => getTranslatedString(
        'PatientContext.timeline.pregnancyLoss',
        'Pregnancy loss (abortion) recorded — follow-up care advised.',
      );
  static String get timelinePregnancyOutcomeRecorded => getTranslatedString(
        'PatientContext.timeline.pregnancyOutcomeRecorded',
        'Pregnancy outcome recorded.',
      );
  static String get timelinePwProfileCreated => getTranslatedString(
        'PatientContext.timeline.pwProfileCreated',
        'Pregnant woman profile created — ANC care started',
      );
  static String timelinePulseAboveNormal(Object n) => getTranslatedString(
        'PatientContext.timeline.pulseAboveNormal',
        'Pulse {n} bpm is above normal',
        params: {'n': '$n'},
      );
  static String timelinePulseBelowNormal(Object n) => getTranslatedString(
        'PatientContext.timeline.pulseBelowNormal',
        'Pulse {n} bpm is below normal',
        params: {'n': '$n'},
      );
  static String get timelineRecoveringWellPnc => getTranslatedString(
        'PatientContext.timeline.recoveringWellPnc',
        'Recovering well — no concerns at this PNC visit.',
      );
  static String get timelineRisingTrendFlagged => getTranslatedString(
        'PatientContext.timeline.risingTrendFlagged',
        'Rising trend flagged — check urine protein & danger signs',
      );
  static String get timelineRoutineAnc => getTranslatedString(
        'PatientContext.timeline.routineAnc',
        'Routine antenatal visit — vitals within normal range.',
      );
  static String timelineSevereAnemiaHb(Object n) => getTranslatedString(
        'PatientContext.timeline.severeAnemiaHb',
        'Severe anemia (Hb {n} g/dL).',
        params: {'n': '$n'},
      );
  static String timelineStatusDx(Object dx) => getTranslatedString(
        'PatientContext.timeline.statusDx',
        'Status: {dx}',
        params: {'dx': '$dx'},
      );
  static String get timelineStillbirthNeonatalDeath => getTranslatedString(
        'PatientContext.timeline.stillbirthNeonatalDeath',
        'Stillbirth or neonatal death recorded — follow-up and counselling needed.',
      );
  static String get timelineTemperatureElevated => getTranslatedString(
        'PatientContext.timeline.temperatureElevated',
        'Temperature is elevated',
      );
  static String get timelineMalariaTreated => getTranslatedString(
        'PatientContext.timeline.malariaTreated',
        'Tested positive, completed antimalarial course',
      );
  static String get timelineOrsAntibioticsRecovered => getTranslatedString(
        'PatientContext.timeline.orsAntibioticsRecovered',
        'Treated with ORS & antibiotics, fully recovered',
      );
  static String timelineVaccinesList(Object list) => getTranslatedString(
        'PatientContext.timeline.vaccinesList',
        'Vaccines: {list}',
        params: {'list': '$list'},
      );
  static String timelineWeightKg(Object n) => getTranslatedString(
        'PatientContext.timeline.weightKg',
        'Weight {n} kg',
        params: {'n': '$n'},
      );
  static String timelinePartsUrgentAttention(Object parts) =>
      getTranslatedString(
        'PatientContext.timeline.partsUrgentAttention',
        '{parts} — needs urgent attention.',
        params: {'parts': '$parts'},
      );
  static String timelineVaccineDoseAdministered(
    Object vaccineName,
    Object dose,
  ) =>
      getTranslatedString(
        'PatientContext.timeline.vaccineDoseAdministered',
        '{vaccineName} — Dose {dose} administered.',
        params: {'vaccineName': '$vaccineName', 'dose': '$dose'},
      );
  static String timelineVaccineAdministered(Object vaccineName) =>
      getTranslatedString(
        'PatientContext.timeline.vaccineAdministered',
        '{vaccineName} administered.',
        params: {'vaccineName': '$vaccineName'},
      );
}

/// Copy for the patient profile card — collapsible demographic section
/// shown inside PatientContextScreen below the header.
abstract final class PatientProfileStrings {
  PatientProfileStrings._();

  static String get profileTitle => getTranslatedString('profileTitle', 'Patient Profile');
  static String get showMore => getTranslatedString('showMore', 'Show full profile');
  static String get hide => getTranslatedString('hide', 'Hide profile');
  static String get servicesProvidedTitle => getTranslatedString('servicesProvidedTitle', 'Services Provided');
  static String get recentStatusTitle => getTranslatedString('recentStatusTitle', 'Recent Status');

  static String get sectionIdentity => getTranslatedString('sectionIdentity', 'Identity');
  static String get sectionLocation => getTranslatedString('sectionLocation', 'Location');
  static String get sectionContact => getTranslatedString('sectionContact', 'Contact');
  static String get sectionCareTeam => getTranslatedString('sectionCareTeam', 'Care Team');
  static String get sectionHousehold => getTranslatedString('sectionHousehold', 'Household Role');

  static String get labelNid => getTranslatedString('labelNid', 'NID / BRN');
  static String get labelGender => getTranslatedString('labelGender', 'Gender');
  static String get labelDob => getTranslatedString('labelDob', 'Date of Birth');
  static String get labelIdType => getTranslatedString('labelIdType', 'ID Type');
  static String get labelMaritalStatus => getTranslatedString('labelMaritalStatus', 'Marital Status');
  static String get labelDisability => getTranslatedString('labelDisability', 'Disability');
  static String get labelVillage => getTranslatedString('labelVillage', 'Village');
  static String get labelPhone => getTranslatedString('labelPhone', 'Phone');
  static String get labelIsHouseholdHead => getTranslatedString('labelIsHouseholdHead', 'HH Head');
  static String get labelRelation => getTranslatedString('labelRelation', 'Relation to HH Head');
  static String get labelSk => getTranslatedString('labelSk', 'Assigned SK');
  static String get labelGuardian => getTranslatedString('labelGuardian', 'Guardian');
  static String get labelMother => getTranslatedString('labelMother', 'Mother Ref');
  static String get labelGps => getTranslatedString('labelGps', 'GPS');
  static String get labelIsPregnant => getTranslatedString('labelIsPregnant', 'Pregnant');
  static String get yes => getTranslatedString('PatientProfile.yes', 'Yes');
  static String get no => getTranslatedString('PatientProfile.no', 'No');
  static String get notAvailable => getTranslatedString('PatientProfile.notAvailable', '—');
  static String get dialFailed => getTranslatedString('PatientProfile.dialFailed', 'Could not open the dialer');
  static String get mapsOpenFailed => getTranslatedString('mapsOpenFailed', 'Could not open maps');

  static String get activeCareThreads => getTranslatedString('activeCareThreads', 'Active care threads');
  static String get editProgrammesCta => getTranslatedString('editProgrammesCta', '+ Edit');
  static String get aiInsight => getTranslatedString('PatientProfile.aiInsight', 'AI Insight');
  static String get pregnancyProgress => getTranslatedString('pregnancyProgress', 'Pregnancy progress');
  static String get careHistory => getTranslatedString('careHistory', 'Care history');
  static String get noVitalsYet => getTranslatedString('noVitalsYet', 'No vitals recorded yet');
  static String get showLess => getTranslatedString('showLess', 'Show less');
  static String showMoreEntries(int n) => getTranslatedString('showMoreEntries', 'Show {n} more', params: {'n': '$n'});
  static String get vitalsConfirmAtVisit => getTranslatedString('vitalsConfirmAtVisit', 'Confirm at today\'s visit');
  static String get weeksToGo => getTranslatedString('weeksToGo', 'weeks to go');
  static String get visitsCompleted => getTranslatedString('PatientProfile.visitsCompleted', 'Visits completed');
  static String get enrolled => getTranslatedString('PatientProfile.enrolled', 'Enrolled');
  static String get dosesCompleted => getTranslatedString('dosesCompleted', 'Doses completed');
  static String get dosesOverdue => getTranslatedString('dosesOverdue', 'Doses overdue');
  static String get growthTrend => getTranslatedString('growthTrend', 'Growth trend');
  static String get bpTarget => getTranslatedString('bpTarget', 'BP target');
  static String get lastCheckup => getTranslatedString('lastCheckup', 'Last check-up');
  static String get medicationAdherence => getTranslatedString('medicationAdherence', 'Medication adherence');
  static String get bloodSugar => getTranslatedString('bloodSugar', 'Blood sugar (fasting)');
  static String get pncVisitsDone => getTranslatedString('pncVisitsDone', 'PNC visits done');
  static String get delivery => getTranslatedString('delivery', 'Delivery');
  static String get newbornAge => getTranslatedString('newbornAge', 'Newborn age');
  static String get breastfeeding => getTranslatedString('breastfeeding', 'Breastfeeding');
  static String get aiInsightUnavailable => getTranslatedString('aiInsightUnavailable', 'AI insight unavailable — check patient record manually');
  static String get aiInsightNotSynced => getTranslatedString(
        'PatientProfile.aiInsightNotSynced',
        'Data not available in offline mode',
      );
  static String get enrolledInApp => getTranslatedString('enrolledInApp', 'Registered in Apon Sushashthya');
  static String get enrolledInAppDescription => getTranslatedString(
        'enrolledInAppDescription',
        'Patient registered in Apon Sushashthya',
      );
  static String get enrollmentMilestone => getTranslatedString('enrollmentMilestone', 'Registration date');
  static String get pregnancyRegistered => getTranslatedString('pregnancyRegistered', 'Pregnancy Registered');
  static String get pregnancyRegistrationCategory => getTranslatedString('pregnancyRegistrationCategory', 'Pregnancy Registration');
  static String get ncdFollowUp => getTranslatedString('ncdFollowUp', 'NCD Follow Up');
  static String get ncdFollowUpCategory => getTranslatedString('ncdFollowUpCategory', 'NCD Follow-up');
  static String get ncdEnrollment => getTranslatedString('ncdEnrollment', 'NCD Enrollment');
  static String get ncdEnrollmentCategory => getTranslatedString('ncdEnrollmentCategory', 'NCD Enrollment');

  // ── Patient context screen — headers/labels formerly hardcoded ─────────
  static String get whyHeader => getTranslatedString('whyHeader', 'WHY');
  static String gestationalWeekBadge(int weeks) => getTranslatedString('gestationalWeekBadge', 'Wk {weeks}', params: {'weeks': '$weeks'});
  static String get lmpLabel => getTranslatedString('lmpLabel', 'LMP');
  static String get eddLabel => getTranslatedString('eddLabel', 'EDD');
  static String get pregnancySnapshotHeader => getTranslatedString('pregnancySnapshotHeader', 'PREGNANCY SNAPSHOT');
  static String get checkupHistoryTitle => getTranslatedString('checkupHistoryTitle', 'Check-up history');
  static String get atAGlanceHeader => getTranslatedString('atAGlanceHeader', 'AT A GLANCE');
  static String get lastCheckupLabel => getTranslatedString('lastCheckupLabel', 'Last check-up');
  static String get careHistoryHeader => getTranslatedString('careHistoryHeader', 'CARE HISTORY');
  static String get notesLabel => getTranslatedString('notesLabel', 'Notes');
  static String get schedulingSectionTitle => getTranslatedString('schedulingSectionTitle', 'Scheduling');
  static String overdueByDaysBadge(int overdueDays) => getTranslatedString('overdueByDaysBadge', 'Overdue $overdueDays day${overdueDays == 1 ? '' : 's'}', params: {'overdueDays': '$overdueDays'});
  static String dueSoonBadge(int dueSoonDays) => getTranslatedString('dueSoonBadge', 'Due in $dueSoonDays day${dueSoonDays == 1 ? '' : 's'}', params: {'dueSoonDays': '$dueSoonDays'});
  static String get lastVitalsSectionTitle => getTranslatedString('lastVitalsSectionTitle', 'Last Vitals');
  static String vitalsRecordedOn(String date) => getTranslatedString('vitalsRecordedOn', 'Recorded {date}', params: {'date': date});
}

/// Patient-context "Recent Vitals" section — `lib/features/patient/recent_vitals_section.dart`.
abstract final class RecentVitalsStrings {
  RecentVitalsStrings._();

  static String get sectionTitle => getTranslatedString('RecentVitals.sectionTitle', 'Recent Vitals');
  static String get loadError => getTranslatedString('RecentVitals.loadError', 'Failed to load vitals');
  static String get emptyState => getTranslatedString('RecentVitals.emptyState', 'No vitals recorded yet');
  static String get latestBadge => getTranslatedString('RecentVitals.latestBadge', 'Latest');
}

abstract final class ContactSheetStrings {
  ContactSheetStrings._();

  static String get noContactAvailable => getTranslatedString('noContactAvailable', 'No contact number available for this household');
  static String get whatsAppFailed => getTranslatedString('whatsAppFailed', 'Could not open WhatsApp');
  static String get smsFailed => getTranslatedString('smsFailed', 'Could not open SMS');
  static String get householdHead => getTranslatedString('householdHead', 'Household head');
  static String get familyMember => getTranslatedString('familyMember', 'Family member');
  static String get unknownPatient => getTranslatedString('unknownPatient', 'Patient');

  /// Shown when contacting a household member on behalf of the patient.
  static String fallbackBanner(String patientName, String recipientName, String relationship) => getTranslatedString('fallbackBanner', '{patientName} has no registered number. Contacting {recipientName} ({relationship}) on their behalf.', params: {'patientName': '$patientName', 'recipientName': '$recipientName', 'relationship': '$relationship'});
}

/// Copy for the Referral SLA dashboard, cards, banners, and notifications.
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §11.
abstract final class ReferralStrings {
  ReferralStrings._();

  // ── Create referral sheet ────────────────────────────────────────────────
  static String get createSheetTitle => getTranslatedString('createSheetTitle', 'Refer Patient');
  static String get createReasonLabel => getTranslatedString('createReasonLabel', 'Reason for referral');
  static String get createReasonHint => getTranslatedString('createReasonHint', 'Select a reason');
  static String get createTierLabel => getTranslatedString('createTierLabel', 'Urgency level');
  static String get createNotesLabel => getTranslatedString('createNotesLabel', 'Additional notes (optional)');
  static String get createNotesHint => getTranslatedString('createNotesHint', 'Enter any notes for the receiving facility');
  static String get createSubmit => getTranslatedString('createSubmit', 'Submit Referral');
  static String get createCancel => getTranslatedString('createCancel', 'Cancel');
  static String get createSuccess => getTranslatedString('createSuccess', 'Referral created');
  static String get createFailed => getTranslatedString('createFailed', 'Failed to create referral — please try again');
  static String get createReasonRequired => getTranslatedString('createReasonRequired', 'Please select a reason');
  static String get tierEmergencyLabel => getTranslatedString('tierEmergencyLabel', 'Emergency (6h SLA)');
  static String get tierUrgentLabel => getTranslatedString('tierUrgentLabel', 'Urgent (24h SLA)');
  static String get tierRoutineLabel => getTranslatedString('tierRoutineLabel', 'Routine (72h SLA)');

  // ── Dashboard ────────────────────────────────────────────────────────────
  static String get loadFailed => getTranslatedString('Referral.loadFailed', 'Could not load referrals');

  // ── Card labels ──────────────────────────────────────────────────────────
  static String get modelVersionLabel => getTranslatedString('Referral.modelVersionLabel', 'Model version');

  // ── Dashboard chip on home screen ────────────────────────────────────────
  static String dashboardChipCritical(int n) => getTranslatedString('dashboardChipCritical', '{n} critical referrals', params: {'n': '$n'});
  static String dashboardChipActive(int n) => getTranslatedString('dashboardChipActive', '{n} active referrals', params: {'n': '$n'});

  // ── Notification copy (Bangla-ready: titles only here) ───────────────────
  static String get notifCriticalTitle => getTranslatedString('notifCriticalTitle', '🔴 SLA BREACHED');
  static String get notifWarningTitle => getTranslatedString('notifWarningTitle', '🟠 Referral warning');
  static String get notifCompletionTitle => getTranslatedString('notifCompletionTitle', '🟢 Treatment completed');
  static String notifCriticalBody(String patient, String reason) => getTranslatedString('notifCriticalBody', '{patient} — {reason}', params: {'patient': '$patient', 'reason': '$reason'});
  static String notifWarningBody(String patient, String reason) => getTranslatedString('notifWarningBody', '{patient} — {reason}', params: {'patient': '$patient', 'reason': '$reason'});
  static String notifCompletionBody(String patient) => getTranslatedString('notifCompletionBody', '{patient} discharged successfully.', params: {'patient': '$patient'});

  // `ReferralRepository._titleFor` / `._bodyFor`. Deliberately distinct from
  // notifCriticalTitle ('🔴 SLA BREACHED') and notifCompletionTitle
  // ('🟢 Treatment completed') — that copy differs and must not be swapped in.
  static String get notifSlaBreachTitle =>
      getTranslatedString('Referral.notifSlaBreachTitle', '🔴 SLA breach');
  static String get notifReferralCompletedTitle =>
      getTranslatedString('Referral.notifReferralCompletedTitle', '🟢 Referral completed');
  static String get notifGenericTitle =>
      getTranslatedString('Referral.notifGenericTitle', 'Referral update');
  static String get notifReminderTitle =>
      getTranslatedString('notifReminderTitle', 'Referral reminder');
  static String get notifReminderBody =>
      getTranslatedString('notifReminderBody', 'You have a pending referral alert.');
  static String get notifDefaultBody =>
      getTranslatedString('Referral.notifDefaultBody', 'Open referral needs your attention.');

  // Status-event reasons, persisted on ReferralStatusEventRow.reason.
  static String escalatedToLevel(int level) => getTranslatedString(
      'Referral.escalatedToLevel', 'Escalated to level {level}', params: {'level': '$level'});
  static String bulkClosedBy(String actor) => getTranslatedString(
      'Referral.bulkClosedBy', 'Bulk closed by {actor}', params: {'actor': actor});

  // ── Permission rationale (in-app card before OS prompt) ─────────────────
  static String get permissionRationaleTitle => getTranslatedString('permissionRationaleTitle', 'Enable referral alerts');
  static String get permissionRationaleBody => getTranslatedString('permissionRationaleBody', 'Get notified when a referral is delayed or breaches its SLA — even when the app is closed.');
  static String get permissionRationaleAction => getTranslatedString('permissionRationaleAction', 'Enable');
  static String get permissionRationaleDismiss => getTranslatedString('permissionRationaleDismiss', 'Not now');

  // ── Triage Card — Referral Metadata ──────────────────────────────────────
  static String get metaFacility => getTranslatedString('metaFacility', 'Facility:');

  // ── Triage Card — Operational Status ─────────────────────────────────────
  static String get statusAwaitingReview => getTranslatedString('statusAwaitingReview', 'Awaiting review');
  static String get statusDischarged => getTranslatedString('statusDischarged', 'Discharged');

  // ── Triage Card — Timeline Progress ──────────────────────────────────────
  static String get timelineOBReview => getTranslatedString('timelineOBReview', 'OB Review');

  // ── Contact Sheet ────────────────────────────────────────────────────────
  static String contactSheetTitle(String name) => getTranslatedString('contactSheetTitle', 'Contact {name}', params: {'name': '$name'});
  static String get contactCall => getTranslatedString('contactCall', 'Call');
  static String get contactCallSubtitle => getTranslatedString('contactCallSubtitle', 'Open phone dialer');
  static String get contactWhatsApp => getTranslatedString('contactWhatsApp', 'WhatsApp');
  static String get contactWhatsAppSubtitle => getTranslatedString('contactWhatsAppSubtitle', 'Send message via WhatsApp');
  static String get contactSms => getTranslatedString('contactSms', 'SMS');
  static String get contactSmsSubtitle => getTranslatedString('contactSmsSubtitle', 'Send text message');

  // ── Contact Messages ─────────────────────────────────────────────────────
  static String msgGreeting(String name) => getTranslatedString('msgGreeting', 'Hello {name}, ', params: {'name': '$name'});
  static String get msgIntro => getTranslatedString('msgIntro', 'this is UHIS Health Worker. ');
  static String get msgGenericOutreach => getTranslatedString('msgGenericOutreach', 'we are reaching out regarding your health care. ');

  // ── Narrative — short reason labels (referral_narrative.shortReasonLabel) ─
  // 'Danger sign' / 'High BP' duplicate PatientContextStrings.dangerSignBadge /
  // .highBpBadge by text only — those back timeline badges, an unrelated
  // surface, so they stay independently translatable.
  static String get shortReasonBloodGlucoseElevated =>
      getTranslatedString('Referral.shortReasonBloodGlucoseElevated', 'Blood glucose elevated');
  /// Spice NCD wire reason `High BG` (UHIS `high_bg`).
  static String get shortReasonHighBg =>
      getTranslatedString('Referral.shortReasonHighBg', 'High BG');
  static String get shortReasonAbnormalPulse =>
      getTranslatedString('Referral.shortReasonAbnormalPulse', 'Abnormal pulse');
  static String get shortReasonHighBp =>
      getTranslatedString('Referral.shortReasonHighBp', 'High BP');
  /// ANC AI-trend wire reason [kAncRisingBpTrendCondition].
  static String get shortReasonRisingBpTrend => getTranslatedString(
        'Referral.shortReasonRisingBpTrend',
        'Rising BP trend',
      );
  static String get shortReasonLowHbAnemia =>
      getTranslatedString('Referral.shortReasonLowHbAnemia', 'Low Hb / Anemia');
  static String get shortReasonDangerSign =>
      getTranslatedString('Referral.shortReasonDangerSign', 'Danger sign');
  static String get shortReasonElevatedTemp =>
      getTranslatedString('Referral.shortReasonElevatedTemp', 'Elevated temperature');
  static String get shortReasonLowWeight =>
      getTranslatedString('Referral.shortReasonLowWeight', 'Low weight');
  static String get shortReasonLowAdherence =>
      getTranslatedString('Referral.shortReasonLowAdherence', 'Low medication adherence');
  static String get shortReasonNoFpMethod =>
      getTranslatedString('Referral.shortReasonNoFpMethod', 'No FP method');
  static String get shortReasonSupplementGap =>
      getTranslatedString('Referral.shortReasonSupplementGap', 'Supplement gap');
  static String get shortReasonVisitOverdue =>
      getTranslatedString('Referral.shortReasonVisitOverdue', 'Visit overdue');
  static String get shortReasonClinicalSymptoms =>
      getTranslatedString('Referral.shortReasonClinicalSymptoms', 'Clinical symptoms');

  // ── Narrative — findings sentences (referral_narrative.buildReferralNarrative)
  static String dangerSignReported(String dSign) => getTranslatedString(
      'Referral.dangerSignReported', 'Danger sign reported: {dSign}.', params: {'dSign': dSign});
  static String get dangerSignReportedGeneric => getTranslatedString(
      'Referral.dangerSignReportedGeneric', 'Danger sign reported — urgent attention required.');

  static String bpDangerouslyElevated(String bp) => getTranslatedString(
      'Referral.bpDangerouslyElevated', 'BP {bp} is dangerously elevated — urgent referral needed.',
      params: {'bp': bp});
  static String bpAboveNormal(String bp) => getTranslatedString(
      'Referral.bpAboveNormal', 'BP {bp} is above the normal — review and follow-up required.',
      params: {'bp': bp});
  static String get bpAboveNormalGeneric => getTranslatedString(
      'Referral.bpAboveNormalGeneric', 'BP is above the normal — review and follow-up required.');

  static String bloodSugarElevated(String bg, String bgType) => getTranslatedString(
      'Referral.bloodSugarElevated',
      'Blood sugar {bg} mmol/L ({bgType}) is elevated — review and follow-up required.',
      params: {'bg': bg, 'bgType': bgType});
  static String get bloodSugarElevatedGeneric => getTranslatedString(
      'Referral.bloodSugarElevatedGeneric', 'Blood sugar is elevated — review and follow-up required.');

  static String severeAnemiaWithValue(String hb) => getTranslatedString(
      'Referral.severeAnemiaWithValue', 'Severe anemia (Hb {hb} g/dL) — urgent review needed.',
      params: {'hb': hb});
  static String anemiaWithValue(String hb) => getTranslatedString(
      'Referral.anemiaWithValue', 'Anemia (Hb {hb} g/dL) — review iron supplementation.',
      params: {'hb': hb});
  static String get severeAnemiaGeneric => getTranslatedString(
      'Referral.severeAnemiaGeneric', 'Severe anemia — urgent review needed.');

  // Two full sentences rather than splicing a translated 'above'/'below'
  // fragment mid-sentence, which breaks word order in many languages.
  static String pulseAboveNormal(String pulse) => getTranslatedString(
      'Referral.pulseAboveNormal', 'Pulse {pulse} bpm is above normal — needs urgent attention.',
      params: {'pulse': pulse});
  static String pulseBelowNormal(String pulse) => getTranslatedString(
      'Referral.pulseBelowNormal', 'Pulse {pulse} bpm is below normal — needs urgent attention.',
      params: {'pulse': pulse});
  static String get pulseAbnormalGeneric => getTranslatedString(
      'Referral.pulseAbnormalGeneric', 'Pulse is abnormal — needs urgent attention.');

  static String temperatureElevated(String tempC) => getTranslatedString(
      'Referral.temperatureElevated', 'Temperature {tempC}°C is elevated — needs urgent attention.',
      params: {'tempC': tempC});
  static String get elevatedTemperatureGeneric => getTranslatedString(
      'Referral.elevatedTemperatureGeneric', 'Elevated temperature — needs urgent attention.');

  static String lowWeightWithValue(String wt) => getTranslatedString(
      'Referral.lowWeightWithValue', 'Low weight ({wt} kg) — monitor nutrition.', params: {'wt': wt});
  static String get lowWeightGeneric => getTranslatedString(
      'Referral.lowWeightGeneric', 'Low weight detected — monitor nutrition.');

  static String get medicationAdherenceLow => getTranslatedString(
      'Referral.medicationAdherenceLow', 'Medication adherence is low — confirm daily intake.');
  static String get noContraceptionMethod => getTranslatedString(
      'Referral.noContraceptionMethod', 'No contraception method in use — counsel on options.');
  static String get supplementGapNarrative => getTranslatedString(
      'Referral.supplementGapNarrative', 'Supplement gap — ensure continued supplementation.');
  static String get visitOverdueNarrative => getTranslatedString(
      'Referral.visitOverdueNarrative', 'Visit overdue — schedule follow-up urgently.');
  static String get clinicalSymptomsPresent => getTranslatedString(
      'Referral.clinicalSymptomsPresent', 'Clinical symptoms present — review and follow-up required.');
  static String get risingBpTrendNarrative => getTranslatedString(
        'Referral.risingBpTrendNarrative',
        'BP is rising across recent visits — referral recommended.',
      );

  /// Terminates an already-localized [label]; a getter so locales that end
  /// sentences differently (e.g. '।') can override the punctuation.
  static String labelWithPeriod(String label) => getTranslatedString(
      'Referral.labelWithPeriod', '{label}.', params: {'label': label});
  static String get referredForClinicalReviewFallback => getTranslatedString(
      'Referral.referredForClinicalReviewFallback', 'Referred for clinical review — follow-up required.');
}

/// AI Mission Dashboard strings (Screen 2 redesign).
/// Spec: AI Mission Dashboard — action page answering "Who needs me next?"
abstract final class MissionDashboardStrings {
  MissionDashboardStrings._();

  // ── HTML Dashboard composition ───────────────────────────────────────────
  static String aiSortedVisits(int n) => getTranslatedString('aiSortedVisits', 'Sorted your {n} visits overnight', params: {'n': '$n'});
  static String get visitsToday => getTranslatedString('visitsToday', 'Visits today');

  /// Stat subline built from the SK's actual worklist. Returns `'No villages'`
  /// when the queue is empty (cold start, before sync), `'1 village'` or
  /// `'N villages'` once data lands. Distance estimate dropped — no source
  /// data yet; bring it back when geo is wired.
  static String visitsTodaySubline(int villageCount) {
    if (villageCount <= 0) {
      return getTranslatedString(
        'MissionDashboard.visitsTodaySublineNone',
        'No villages assigned',
      );
    }
    if (villageCount == 1) {
      return getTranslatedString('MissionDashboard.visitsTodaySublineOne', '1 village');
    }
    return getTranslatedString(
      'MissionDashboard.visitsTodaySublineMany',
      '$villageCount villages',
      params: {'count': '$villageCount'},
    );
  }

  static String get referralAlertsLabel => getTranslatedString('referralAlertsLabel', 'Referral alerts need follow-up');
  static String get tapToFollowUp => getTranslatedString('tapToFollowUp', 'Tap to follow up →');
  static String get referralCceComingSoon => getTranslatedString('referralCceComingSoon', 'CCE integration coming soon');
  static String get visitStartFailed => getTranslatedString('visitStartFailed', 'Could not start visit. Try again from the patient screen.');
  static String get visitMissingPatient => getTranslatedString('visitMissingPatient', 'No patient record — open the case to begin.');
  static String houseNumber(String no) => getTranslatedString('houseNumber', '#{no}', params: {'no': '$no'});
  static String moreVisits(int n) {
    if (n == 1) {
      return getTranslatedString('MissionDashboard.moreVisitsOne', '+ 1 more visit today');
    }
    return getTranslatedString(
      'MissionDashboard.moreVisitsMany',
      '+ $n more visits today',
      params: {'n': '$n'},
    );
  }
  static String todaysVisits(String date) => getTranslatedString('todaysVisits', 'Today\'s visits · {date}', params: {'date': '$date'});
  static String get filterByLocation => getTranslatedString('filterByLocation', 'Village · SS · Area');
  static String get upcomingWorkHeader => getTranslatedString('upcomingWorkHeader', 'Upcoming work — earliest first');
  static String get aiSortedBadge => getTranslatedString('aiSortedBadge', '✦ sorted');

  /// Badge copy for the dashboard header — always the unfiltered today count.
  static String aiSortedVisitsToday(int n) {
    if (n == 1) {
      return getTranslatedString('MissionDashboard.aiSortedVisitsTodayOne', '✦ 1 visit today');
    }
    return getTranslatedString(
      'MissionDashboard.aiSortedVisitsTodayMany',
      '✦ $n visits today',
      params: {'n': '$n'},
    );
  }
  static String get actionVisitNow => getTranslatedString('actionVisitNow', 'Visit now');
  static String get actionVisitToday => getTranslatedString('actionVisitToday', 'Visit today');
  static String get actionThisWeek => getTranslatedString('actionThisWeek', 'This week');
  static String get actionRoutine => getTranslatedString('actionRoutine', 'Routine');

  // ── AI Daily Brief Card ──────────────────────────────────────────────────
  static String get aiBriefTitle => getTranslatedString('aiBriefTitle', 'Today\'s AI Brief');
  static String get visitsRecommended => getTranslatedString('visitsRecommended', 'Visits Recommended');
  static String get childDangerCases => getTranslatedString('childDangerCases', 'Child Danger Cases');
  static String get slaBreachedReferrals => getTranslatedString('slaBreachedReferrals', 'SLA Breached Referrals');
  static String get ancFollowUps => getTranslatedString('ancFollowUps', 'ANC Follow-ups');
  static String get highRiskDiabeticPatients => getTranslatedString('highRiskDiabeticPatients', 'High-Risk Diabetic Patients');
  static String get expectedWorkload => getTranslatedString('expectedWorkload', 'Expected Workload');
  static String get priorityLevel => getTranslatedString('priorityLevel', 'Priority Level');
  static String get whyQuestion => getTranslatedString('whyQuestion', 'Why?');
  static String get riskFactorsIdentified => getTranslatedString('riskFactorsIdentified', 'Risk Factors Identified');

  /// Localised display for PW risk wire labels (UHIS `riskFactorDisplayText`).
  /// Unknown labels (medical/obstetric history) stay as the English wire value.
  static String pwRiskFactorDisplay(String wire) {
    switch (wire) {
      case 'Age <18 years':
        return getTranslatedString('PwRisk.ageUnder18', 'Age <18 years');
      case 'Age >35 years':
        return getTranslatedString('PwRisk.ageOver35', 'Age >35 years');
      case 'Short birth spacing <2 year':
        return getTranslatedString(
          'PwRisk.shortBirthSpacing',
          'Short birth spacing <2 year',
        );
      case 'Multipara >3':
        return getTranslatedString('PwRisk.multipara', 'Multipara >3');
      default:
        return wire;
    }
  }

  static String workloadHours(double hours) => getTranslatedString(
        'MissionDashboard.workloadHours',
        '${hours.toStringAsFixed(1)} Hours',
        params: {'hours': hours.toStringAsFixed(1)},
      );

  // ── Mission Progress Card ────────────────────────────────────────────────
  static String get todaysProgress => getTranslatedString('todaysProgress', 'Today\'s Progress');
  static String get visitsCompleted => getTranslatedString('MissionDashboard.visitsCompleted', 'Visits Completed');
  static String get visitsRemaining => getTranslatedString('visitsRemaining', 'Visits Remaining');
  static String get estimatedTime => getTranslatedString('estimatedTime', 'Estimated Time');
  static String progressFraction(int done, int total) => getTranslatedString('progressFraction', '{done} / {total}', params: {'done': '$done', 'total': '$total'});
  static String progressPercent(int percent) => getTranslatedString('progressPercent', '{percent}%', params: {'percent': '$percent'});
  static String remainingVisits(int n) => getTranslatedString('remainingVisits', '{n} Visits Remaining', params: {'n': '$n'});
  static String estimatedDuration(String duration) => getTranslatedString('estimatedDuration', 'Estimated Time: {duration}', params: {'duration': '$duration'});
  static String completionPrediction(String time) => getTranslatedString('completionPrediction', 'At current pace, all visits can be completed by {time}', params: {'time': '$time'});

  // ── Critical Alert Banner ────────────────────────────────────────────────
  static String get criticalAlert => getTranslatedString('criticalAlert', '🔴 Critical Alert');
  static String get emergencyAncAlert => getTranslatedString('emergencyAncAlert', '🔴 Emergency ANC Alert');
  static String get immediateFollowUpRequired => getTranslatedString('immediateFollowUpRequired', 'Immediate follow-up required.');
  static String childReferralOverdue(int days) => getTranslatedString(
        'MissionDashboard.childReferralOverdue',
        '$days Child Referral${days == 1 ? '' : 's'} Overdue',
        params: {'days': '$days'},
      );
  static String highRiskPregnancyWaiting(String name, String duration) => getTranslatedString('highRiskPregnancyWaiting', '{name}: High-risk pregnancy waiting {duration} for OB review.', params: {'name': '$name', 'duration': '$duration'});

  // ── Mission Queue Card ───────────────────────────────────────────────────
  static String priorityRank(int rank) => getTranslatedString('priorityRank', 'Priority #{rank}', params: {'rank': '$rank'});
  static String daysOverdue(int days) => getTranslatedString('daysOverdue', '{days} Days Overdue', params: {'days': '$days'});
  static String get aiInsight => getTranslatedString('MissionDashboard.aiInsight', 'AI Insight');

  // ── Programme-smart reason badge (v13 design) ───────────────────────────
  static String get enrolled => getTranslatedString('MissionDashboard.enrolled', 'Registered');
  static String get ancVisitLabel => getTranslatedString('MissionDashboard.ancVisitLabel', 'ANC Visit');
  static String get pncVisitLabel => getTranslatedString('MissionDashboard.pncVisitLabel', 'PNC Visit');
  static String get childImmunisation => getTranslatedString('childImmunisation', 'Child immunisation');
  static String get ncdCheckup => getTranslatedString('ncdCheckup', 'NCD checkup');
  static String get tbCheck => getTranslatedString('tbCheck', 'TB check');
  static String get newVisit => getTranslatedString('newVisit', 'New visit');
  static String get aiPrioritisedBecause => getTranslatedString('aiPrioritisedBecause', 'AI Prioritised because:');
  static String get reason => getTranslatedString('reason', 'Reason');

  // ── AI Insight Reasons (human-readable) ──────────────────────────────────
  static String get insightPatientNeverArrived => getTranslatedString('insightPatientNeverArrived', 'Patient never arrived at facility.');
  static String get insightPossibleTransportBarrier => getTranslatedString('insightPossibleTransportBarrier', 'Possible transport barrier.');
  static String get insightReferralOverdue => getTranslatedString('insightReferralOverdue', 'Referral overdue.');
  static String get insightChildUnder5 => getTranslatedString('insightChildUnder5', 'Child under 5.');
  static String get insightHighRiskPregnancy => getTranslatedString('insightHighRiskPregnancy', 'High-risk pregnancy.');
  static String get insightNoFacilityArrival => getTranslatedString('insightNoFacilityArrival', 'No facility arrival.');
  static String get insightMissedFollowUp => getTranslatedString('insightMissedFollowUp', 'Missed follow-up.');
  static String get insightSlaBreached => getTranslatedString('insightSlaBreached', 'SLA breached.');
  static String get insightEmergencyDiagnosis => getTranslatedString('insightEmergencyDiagnosis', 'Emergency diagnosis.');
  static String get insightDiabetesMissedFollowUp => getTranslatedString('insightDiabetesMissedFollowUp', 'Diabetes patient missed follow-up.');

  // ── Action Buttons ───────────────────────────────────────────────────────
  static String get callFamily => getTranslatedString('callFamily', 'Call Family');
  static String get locate => getTranslatedString('locate', 'Locate');
  static String get openCase => getTranslatedString('openCase', 'Open Case');
  static String get callFacility => getTranslatedString('callFacility', 'Call Facility');
  static String get openReferral => getTranslatedString('openReferral', 'Open Referral');
  static String get scheduleVisit => getTranslatedString('scheduleVisit', 'Schedule Visit');
  static String get visitHousehold => getTranslatedString('visitHousehold', 'Visit Household');
  static String get startRoute => getTranslatedString('startRoute', 'Start Route');
  static String get continueTodaysWork => getTranslatedString('continueTodaysWork', 'Continue Today\'s Work');

  // ── Household Enrollment CTA ─────────────────────────────────────────────
  static String get enrollHouseholdTitle => getTranslatedString('enrollHouseholdTitle', 'Enrol a new household');
  static String get enrollHouseholdSubtitle => getTranslatedString('enrollHouseholdSubtitle', 'Register a family not yet in the programme');
  static String get enrollHouseholdAction => getTranslatedString('enrollHouseholdAction', 'Enrol now');

  // ── Referral Operations Widget ───────────────────────────────────────────
  static String get referralStatus => getTranslatedString('referralStatus', 'Referral Status');
  static String get active => getTranslatedString('active', 'Active');
  static String get breached => getTranslatedString('breached', 'Breached');
  static String get awaitingReview => getTranslatedString('awaitingReview', 'Awaiting Review');
  static String get completed => getTranslatedString('completed', 'Completed');
  static String referralCount(int count, String status) => getTranslatedString('referralCount', '{count} {status}', params: {'count': '$count', 'status': '$status'});

  // ── Follow-Ups Due Widget ────────────────────────────────────────────────
  static String get followUpsDue => getTranslatedString('followUpsDue', 'Follow-Ups Due');
  static String get discharged => getTranslatedString('discharged', 'Discharged');
  static String get followUpDue => getTranslatedString('MissionDashboard.followUpDue', 'Follow-up Due');
  static String get tomorrow => getTranslatedString('tomorrow', 'Tomorrow');
  static String get yesterday => getTranslatedString('MissionDashboard.yesterday', 'Yesterday');
  static String daysAgo(int n) => getTranslatedString('MissionDashboard.daysAgo', '{n} days ago', params: {'n': '$n'});
  static String get today => getTranslatedString('MissionDashboard.today', 'Today');
  static String daysAway(int days) {
    if (days == 0) return today;
    if (days == 1) return tomorrow;
    return getTranslatedString(
      'MissionDashboard.daysAway',
      'In $days days',
      params: {'days': '$days'},
    );
  }

  // ── Household Opportunities Widget ───────────────────────────────────────
  static String get householdOpportunities => getTranslatedString('householdOpportunities', 'Household Opportunities');
  static String get potentialServices => getTranslatedString('potentialServices', 'Potential Services');
  static String get mother => getTranslatedString('mother', 'Mother');
  static String get child => getTranslatedString('child', 'Child');
  static String get father => getTranslatedString('father', 'Father');
  static String get ancFollowUpDue => getTranslatedString('ancFollowUpDue', 'ANC Follow-up Due');
  static String get epiVaccineDue => getTranslatedString('epiVaccineDue', 'EPI Vaccine Due');
  static String get bpReviewPending => getTranslatedString('bpReviewPending', 'BP Review Pending');
  static String householdNumber(int number) => getTranslatedString('MissionDashboard.householdNumber', '#{number}', params: {'number': '$number'});
  static String potentialServicesCount(int count) => getTranslatedString('potentialServicesCount', 'Potential Services: {count}', params: {'count': '$count'});

  // ── Route Optimization Widget ────────────────────────────────────────────
  static String get optimalRoute => getTranslatedString('optimalRoute', 'Optimal Route');
  static String get distance => getTranslatedString('distance', 'Distance');
  static String get estimatedTravelTime => getTranslatedString('estimatedTravelTime', 'Estimated Time');
  static String distanceKm(double km) => '${km.toStringAsFixed(1)} km';
  static String travelDuration(String duration) => duration;

  // ── Learning Recommendations Widget ──────────────────────────────────────
  static String get todaysLearning => getTranslatedString('todaysLearning', 'Today\'s Learning');
  static String learningDuration(int minutes) => getTranslatedString('learningDuration', '{minutes} Minutes', params: {'minutes': '$minutes'});
  static String get triggeredByTodaysCases => getTranslatedString('triggeredByTodaysCases', 'Triggered by today\'s cases');

  // ── Floating AI Assistant ────────────────────────────────────────────────
  static String get aiAssistant => getTranslatedString('aiAssistant', 'AI Assistant');
  static String get askAiAssistant => getTranslatedString('askAiAssistant', 'Ask AI Assistant');
  static String get aiAssistantHint => getTranslatedString('aiAssistantHint', 'Ask about patient care, guidelines, or procedures…');

  // ── Priority Levels ──────────────────────────────────────────────────────
  static String get priorityCritical => getTranslatedString('priorityCritical', 'Critical');
  static String get priorityHigh => getTranslatedString('priorityHigh', 'High');
  static String get priorityMedium => getTranslatedString('priorityMedium', 'Medium');
  static String get priorityLow => getTranslatedString('priorityLow', 'Low');

  // ── Programme Badges ─────────────────────────────────────────────────────
  // Standardized clinical shorthand SKs are trained on — kept in Latin
  // script regardless of UI language (not translated by design).
  static String get badgeAnc => getTranslatedString('badgeAnc', 'ANC');
  static String get badgeImci => getTranslatedString('badgeImci', 'IMCI');
  static String get badgeNcd => getTranslatedString('badgeNcd', 'NCD');
  static String get badgeTb => getTranslatedString('badgeTb', 'TB');
  static String get badgeEpi => getTranslatedString('badgeEpi', 'EPI');
  static String get badgeReferral => getTranslatedString('badgeReferral', 'Referral');

  // ── Empty States ─────────────────────────────────────────────────────────
  static String get noMissionsToday => getTranslatedString('noMissionsToday', 'No missions for today');
  static String get allCaughtUp => getTranslatedString('allCaughtUp', 'All caught up! Great work.');
  static String get noCriticalAlerts => getTranslatedString('noCriticalAlerts', 'No critical alerts');
  static String get noFollowUpsDue => getTranslatedString('noFollowUpsDue', 'No follow-ups due');
  static String get noHouseholdOpportunities => getTranslatedString('noHouseholdOpportunities', 'No household opportunities identified');

  // ── 5-Tier Dashboard Model ───────────────────────────────────────────────
  // Single source of UI copy for tier headers, CTAs, and driver rationales.
  // Widgets must call these helpers instead of inlining tier labels.

  static String get tierLabelCritical => getTranslatedString('tierLabelCritical', 'Critical');
  static String get tierLabelOverdue => getTranslatedString('tierLabelOverdue', 'Overdue');
  static String get tierLabelDueToday => getTranslatedString('tierLabelDueToday', 'Due today');
  static String get tierLabelThisWeek => getTranslatedString('tierLabelThisWeek', 'This week');
  static String get tierLabelUpcoming => getTranslatedString('tierLabelUpcoming', 'Upcoming');

  /// Localised label for a [DashboardTier]. Used by inline tier headers and
  /// the patient-list filter chip row.
  static String tierLabel(DashboardTier tier) {
    switch (tier) {
      case DashboardTier.critical:
        return tierLabelCritical;
      case DashboardTier.overdue:
        return tierLabelOverdue;
      case DashboardTier.dueToday:
        return tierLabelDueToday;
      case DashboardTier.thisWeek:
        return tierLabelThisWeek;
      case DashboardTier.upcoming:
        return tierLabelUpcoming;
    }
  }

  /// Inline tier-section header, e.g. `'Overdue · 3'`. Renders above the
  /// first card of each tier on the Mission Dashboard.
  static String tierHeaderWithCount(DashboardTier tier, int count) =>
      '${tierLabel(tier)} · $count';

  // Tier-varied CTA pill labels.
  static String get ctaVisitNow => getTranslatedString('ctaVisitNow', 'Visit now');
  static String get ctaVisitToday => getTranslatedString('ctaVisitToday', 'Visit today');
  static String get ctaPlanVisit => getTranslatedString('ctaPlanVisit', 'Plan visit');
  static String get ctaSchedule => getTranslatedString('ctaSchedule', 'Schedule');

  /// CTA pill label for a card in a given tier:
  ///   critical / overdue → `'Visit now'`
  ///   dueToday           → `'Visit today'`
  ///   thisWeek           → `'Plan visit'`
  ///   upcoming           → `'Schedule'`
  static String ctaForTier(DashboardTier tier) {
    switch (tier) {
      case DashboardTier.critical:
      case DashboardTier.overdue:
        return ctaVisitNow;
      case DashboardTier.dueToday:
        return ctaVisitToday;
      case DashboardTier.thisWeek:
        return ctaPlanVisit;
      case DashboardTier.upcoming:
        return ctaSchedule;
    }
  }

  // ── Inline Village + Need filter ─────────────────────────────────────────
  static String get whichVillageVisiting => getTranslatedString('whichVillageVisiting', 'WHICH VILLAGE ARE YOU VISITING?');
  static String get allVillages => getTranslatedString('allVillages', 'All villages');
  static String get filterByNeed => getTranslatedString('filterByNeed', 'FILTER BY NEED');
  static String get filterByNeedOptional => getTranslatedString('filterByNeedOptional', 'optional');
  static String get needHighRisk => getTranslatedString('needHighRisk', 'High-risk');
  static String get needAncMnch => getTranslatedString('needAncMnch', 'ANC / MNCH');
  static String get needChildImmunisation => getTranslatedString('needChildImmunisation', 'Child / Immun.');
  static String get needNcd => getTranslatedString('needNcd', 'NCD');
  static String get needEyeCare => getTranslatedString('needEyeCare', 'Eye care');
  static String get needMissedFollowUp => getTranslatedString('needMissedFollowUp', 'Missed');
  static String get needPendingReferral => getTranslatedString('needPendingReferral', 'Referral');
  static String get needHomeVisit => getTranslatedString('needHomeVisit', 'Home visit');
  static String get needFacilityReferral => getTranslatedString('needFacilityReferral', 'Facility');
  static String get needThisWeek => getTranslatedString('needThisWeek', 'This week');
  static String get clearNeedFilters => getTranslatedString('clearNeedFilters', 'Clear');
  static String get filterByProgramme => getTranslatedString('filterByProgramme', 'Programme');
  static String get noNeedsInQueue => getTranslatedString('noNeedsInQueue', 'No priority needs in today\'s list');
  static String get noVisitsMatchFilters => getTranslatedString('noVisitsMatchFilters', 'No visits match these filters');
  static String get noVisitsMatchFiltersHint => getTranslatedString('noVisitsMatchFiltersHint', 'Try another village or clear the filters');
  static String completedVisitToast(String name) => getTranslatedString('completedVisitToast', '{name}\'s visit already done today ✓', params: {'name': '$name'});

  // ── AI sorted info card tags ──────────────────────────────────────────────
  static String get aiSortedTagRisk => getTranslatedString('aiSortedTagRisk', '✦Risk scoring');
  static String get aiSortedTagOverdue => getTranslatedString('aiSortedTagOverdue', '✦Overdue flags');
  static String get aiSortedTagCce => getTranslatedString('aiSortedTagCce', '✦CCE alerts');

  // ── Home FAB — Spice R.string.add_household ──────────────────────────────
  static String get addHousehold =>
      getTranslatedString('addHousehold', 'Add Household');
  static String get enrolNewCta => getTranslatedString('enrolNewCta', 'Enroll new');
  static String get enrolNewComingSoon => getTranslatedString('enrolNewComingSoon', 'QR enrolment flow coming soon. Use the Patients tab to view existing patients.');

  // ── Status pills (compact tier label shown in the card right-side pill) ───
  static String get statusPillNow => getTranslatedString('statusPillNow', 'Now');
  static String get statusPillOverdue => getTranslatedString('statusPillOverdue', 'Overdue');
  static String get statusPillToday => getTranslatedString('statusPillToday', 'Today');
  static String get statusPillThisWeek => getTranslatedString('statusPillThisWeek', 'This week');
  static String get statusPillRoutine => getTranslatedString('statusPillRoutine', 'Routine');

  /// Status pill copy for a **schedule** tier ([DashboardTier.fromDueAt]).
  /// Home cards pass the date tier only — clinical risk must not change this.
  static String statusPillForTier(DashboardTier tier) {
    switch (tier) {
      case DashboardTier.critical:
        // Defensive: schedule mapping never yields critical; keep Overdue.
        return statusPillOverdue;
      case DashboardTier.overdue:
        return statusPillOverdue;
      case DashboardTier.dueToday:
        return statusPillToday;
      case DashboardTier.thisWeek:
        return statusPillThisWeek;
      case DashboardTier.upcoming:
        return statusPillRoutine;
    }
  }

  /// Human-readable rationale for a driver tag on `MissionQueueItem.drivers`.
  /// Unknown tags fall back to a generic phrase so the rationale sheet never
  /// shows a raw tag identifier to the SK.
  static String driverLabel(String tag) {
    switch (tag) {
      case 'sla-breached':
        return getTranslatedString('MissionDashboard.driverSlaBreached', 'Referral SLA breached');
      case 'red-flag':
        return getTranslatedString('MissionDashboard.driverRedFlag', 'Red-flag patient');
      case 'hi-risk-anc-gap':
        return getTranslatedString(
            'MissionDashboard.driverHiRiskAncGap', 'High-risk pregnancy with ANC gap');
      case 'neonate':
        return getTranslatedString('MissionDashboard.driverNeonate', 'Neonate (under 28 days)');
      case 'young-infant':
        return getTranslatedString(
            'MissionDashboard.driverYoungInfant', 'Young infant (under 60 days)');
      case 'pnc-window':
        return getTranslatedString(
            'MissionDashboard.driverPncWindow', 'Postpartum (within 42 days)');
      case 'anc-near-term':
        return getTranslatedString('MissionDashboard.driverAncNearTerm',
            'Near-term pregnancy (EDD within 14 days)');
      case 'delivery-complication':
        return getTranslatedString(
            'MissionDashboard.driverDeliveryComplication', 'Delivery complications recorded');
      case 'pnc-illness':
        return getTranslatedString(
            'MissionDashboard.driverPncIllness', 'Postnatal illness reported');
      case 'ltfu-streak':
        return getTranslatedString(
            'MissionDashboard.driverLtfuStreak', 'Lost-to-follow-up streak');
      case 'tb-default-risk':
        return getTranslatedString(
            'MissionDashboard.driverTbDefaultRisk', 'TB treatment — default risk');
      case 'ncd-drift':
        return getTranslatedString('MissionDashboard.driverNcdDrift', 'NCD treatment overdue');
      case 'referral-arrival-pending':
        return getTranslatedString(
            'MissionDashboard.driverReferralArrivalPending', 'Referral pending arrival');
      case 'child-disability':
        return getTranslatedString(
            'MissionDashboard.driverChildDisability', 'Child under 5 with disability');
      default:
        return getTranslatedString('MissionDashboard.driverDefault', 'Clinical priority signal');
    }
  }

  // ── `_buildAiInsight` envelope sentences ─────────────────────────────────
  static String get insightScheduledCheckUp =>
      getTranslatedString('MissionDashboard.insightScheduledCheckUp', 'Scheduled for regular check-up.');
  static String get insightRequiresAttention =>
      getTranslatedString('MissionDashboard.insightRequiresAttention', 'Requires attention.');

  /// AI-insight sentence for a driver tag. Twin of [driverLabel].
  /// [days] carries the numeric suffix of an `overdue:<n>` tag.
  static String driverInsight(String tag, {String? days}) =>
      driverInsightOrNull(tag, days: days) ?? insightRequiresAttention;

  /// Null-returning variant. `MissionDashboardService._buildAiInsight` relies
  /// on `null` to mean "this tag contributes no sentence" (e.g. `band1-severe`,
  /// `danger-sign`, `stroke-sign`, `eclampsia`); substituting the generic
  /// default there would add a sentence that today's output does not have.
  static String? driverInsightOrNull(String tag, {String? days}) {
    switch (tag) {
      case 'sla-breached':
        return getTranslatedString(
            'MissionDashboard.driverInsightSlaBreached', 'SLA breached — immediate action required.');
      case 'child-under-5':
        return getTranslatedString(
            'MissionDashboard.driverInsightChildUnder5', 'Child under 5 — higher priority.');
      case 'pregnancy':
        return insightHighRiskPregnancy;
      case 'urgent-risk':
        return getTranslatedString(
            'MissionDashboard.driverInsightUrgentRisk', 'Urgent clinical risk identified.');
      case 'high-risk':
        return getTranslatedString('MissionDashboard.driverInsightHighRisk', 'High clinical risk.');
      case 'overdue':
        return (days != null && days.isNotEmpty)
            ? getTranslatedString('MissionDashboard.driverInsightOverdueDays',
                'Overdue by {days} days.', params: {'days': days})
            : getTranslatedString('MissionDashboard.driverInsightVisitOverdue', 'Visit overdue.');
      case 'no-arrival':
        return insightPatientNeverArrived;
      case 'emergency-dx':
        return insightEmergencyDiagnosis;
      case 'missed-follow-up':
        return getTranslatedString(
            'MissionDashboard.driverInsightMissedFollowUp', 'Missed scheduled follow-up.');
      case 'referral':
        return getTranslatedString(
            'MissionDashboard.driverInsightReferral', 'Active referral requires tracking.');
      case 'follow-up':
        return getTranslatedString(
            'MissionDashboard.driverInsightFollowUp', 'Post-discharge follow-up due.');
      default:
        return null;
    }
  }

  // ── MissionDashboardService fallbacks ────────────────────────────────────
  static String get memberFallback => getTranslatedString('MissionDashboard.memberFallback', 'Member');
  static String get checkUpFallback => getTranslatedString('MissionDashboard.checkUpFallback', 'Check-up');

  /// Placeholder title for a referral whose patient record has not synced yet.
  /// The caller passes the already-truncated id, so one getter covers both the
  /// long- and short-id branches.
  static String patientLabel(String id) =>
      getTranslatedString('MissionDashboard.patientLabel', 'Patient {id}', params: {'id': id});

  /// Distinct from `badgeReferral`, whose block is deliberately kept in Latin
  /// script; this reason line must stay translatable.
  static String get referralFallback =>
      getTranslatedString('MissionDashboard.referralFallback', 'Referral');

  /// Distinct from `followUpDue` ('Follow-up Due') — this fallback is lower-case.
  static String get followUpDueFallback =>
      getTranslatedString('MissionDashboard.followUpDueFallback', 'Follow-up due');

  // AI brief risk factors — no trailing periods, matching the live literals.
  static String riskReferralOverdue(int days) => getTranslatedString(
      'MissionDashboard.riskReferralOverdue', 'Referral overdue by {days} days', params: {'days': '$days'});
  static String riskPatientsWaiting(int n) => getTranslatedString(
      'MissionDashboard.riskPatientsWaiting', '{n} patient(s) waiting for facility review',
      params: {'n': '$n'});
  static String riskMissedFollowUps(int n) => getTranslatedString(
      'MissionDashboard.riskMissedFollowUps', '{n} patient(s) missed follow-up', params: {'n': '$n'});

  /// Trailing word of the visit badge, e.g. 'ANC Visit 3 due'.
  static String get dueSuffix => getTranslatedString('MissionDashboard.dueSuffix', 'due');

  /// Title-case twin used only by the PNC badge, which renders 'PNC Visit 2 Due'
  /// today. Both badges are drawn by byte-identical `Text` widgets, so this is
  /// an inconsistency rather than deliberate title-case — kept separate to
  /// preserve current rendering until product signs off on unifying the casing.
  static String get dueSuffixTitleCase =>
      getTranslatedString('MissionDashboard.dueSuffixTitleCase', 'Due');

  // ── Notification drawer ──────────────────────────────────────────────────
  static String get notificationsTitle => getTranslatedString('notificationsTitle', 'Notifications');
  static String get close => getTranslatedString('MissionDashboard.close', 'Close');
  static String get noNewNotifications => getTranslatedString('noNewNotifications', 'No new notifications');
  static String get cceEscalations => getTranslatedString('cceEscalations', 'CCE escalations');
  static String criticalReferralsSubtitle(int count) => getTranslatedString(
        'MissionDashboard.criticalReferralsSubtitle',
        '$count critical referral${count == 1 ? '' : 's'} need immediate attention',
        params: {'count': '$count'},
      );
  static String pendingReferralsSubtitle(int count) => getTranslatedString(
        'MissionDashboard.pendingReferralsSubtitle',
        '$count pending referral${count == 1 ? '' : 's'} awaiting follow-up',
        params: {'count': '$count'},
      );
  static String get viewAll => getTranslatedString('viewAll', 'View all');
  static String get visitedBadge => getTranslatedString('MissionDashboard.visitedBadge', 'Visited');
  static String get startVisit => getTranslatedString('MissionDashboard.startVisit', 'Start Visit');
  static String aiBriefTodayHeader(String date) => getTranslatedString('MissionDashboard.aiBriefTodayHeader', 'Today · {date}', params: {'date': date});
  static String get visitsUnitLabel => getTranslatedString('MissionDashboard.visitsUnitLabel', 'visits');
  static String get completedTodayHeader => getTranslatedString('MissionDashboard.completedTodayHeader', 'COMPLETED TODAY');
  static String get noVisitsScheduledToday => getTranslatedString('MissionDashboard.noVisitsScheduledToday', 'No visits scheduled today');
  static String get aiIdentifiedMultiServiceVisits => getTranslatedString('MissionDashboard.aiIdentifiedMultiServiceVisits', 'AI-identified multi-service visits');
  static String get celebrationEmoji => getTranslatedString('MissionDashboard.celebrationEmoji', '🎉');

  // ── Shared filter-chip Semantics template ────────────────────────────────
  static String filterBy(String label) =>
      getTranslatedString('MissionDashboard.filterBy', 'Filter by {label}', params: {'label': label});
  static String filterSelected(String label) => getTranslatedString(
      'MissionDashboard.filterSelected', '{label} filter, selected', params: {'label': label});
  static String filterUnavailable(String label) => getTranslatedString(
      'MissionDashboard.filterUnavailable', '{label} filter, unavailable', params: {'label': label});

  /// Selected-state Semantics label for `VisitTierChip`. Deliberately NOT the
  /// same text as [filterSelected] — the tier chip toggles off, the need
  /// bubble does not.
  static String removeFilter(String label) => getTranslatedString(
      'MissionDashboard.removeFilter', 'Remove filter: {label}', params: {'label': label});

  static String get searchResultsNotInQueue => getTranslatedString(
      'MissionDashboard.searchResultsNotInQueue', "Search results — not in today's queue");

  /// Gender wire value → display label. The value arrives raw and unnormalised
  /// from the sync payload's `gender`/`sex` field, so unrecognised values pass
  /// through untranslated rather than being swallowed.
  static const Map<String, String> _genderFallbackLabels = {
    'male': 'Male',
    'm': 'Male',
    'female': 'Female',
    'f': 'Female',
    'other': 'Other',
    'o': 'Other',
  };

  static String genderLabel(String raw) {
    final key = raw.trim().toLowerCase();
    final fallback = _genderFallbackLabels[key];
    if (fallback == null) return raw;
    return getTranslatedString('MissionDashboard.gender_$key', fallback);
  }

  static String referralAlertsSemantic(int total) => getTranslatedString(
      'MissionDashboard.referralAlertsSemantic', 'Referral alerts: {total}', params: {'total': '$total'});
  static String notificationsCountSemantic(int count) => getTranslatedString(
      'MissionDashboard.notificationsCountSemantic', '{count} notifications', params: {'count': '$count'});

  static String get expandRiskFactors =>
      getTranslatedString('MissionDashboard.expandRiskFactors', 'Expand risk factors');
  static String get collapseRiskFactors =>
      getTranslatedString('MissionDashboard.collapseRiskFactors', 'Collapse risk factors');

  static String get openAiBriefCritical =>
      getTranslatedString('MissionDashboard.openAiBriefCritical', 'Open AI brief — critical items today');
  static String get openAiBrief => getTranslatedString('MissionDashboard.openAiBrief', 'Open AI brief');

  static String get urgentSuffix => getTranslatedString('MissionDashboard.urgentSuffix', 'urgent');
  static String get workSuffix => getTranslatedString('MissionDashboard.workSuffix', 'work');

  static String todaysProgressHeader(String date) => getTranslatedString(
      'MissionDashboard.todaysProgressHeader', "Today's Progress · {date}", params: {'date': date});

  static String openCriticalCase(String name) => getTranslatedString(
      'MissionDashboard.openCriticalCase', 'Open critical case: {name}', params: {'name': name});
  static String moreAlerts(int n) => getTranslatedString(
      'MissionDashboard.moreAlerts', '+$n more alert${n == 1 ? '' : 's'}', params: {'n': '$n'});
  static String get dismissAlertTooltip =>
      getTranslatedString('MissionDashboard.dismissAlertTooltip', 'Dismiss alert');

  /// Compact overdue badge, e.g. `+3d`. Shared by `critical_alert_banner.dart`
  /// and `referral_operations_widget.dart`, where it was duplicated verbatim.
  static String daysOverdueSuffix(int n) =>
      getTranslatedString('MissionDashboard.daysOverdueSuffix', '+{n}d', params: {'n': '$n'});

  static String get viewReferralStatusSemantic =>
      getTranslatedString('MissionDashboard.viewReferralStatusSemantic', 'View referral status');
}

/// Visit triage step (HTML composition) — bilingual symptom prompts.
abstract final class VisitTriageStrings {
  VisitTriageStrings._();

  static String get triage => getTranslatedString('triage', 'Triage');
  static String get patient => getTranslatedString('patient', 'patient');
  static String get sessionMissing => getTranslatedString('sessionMissing', 'Visit not found. Please start a new visit.');
  static String get leaveVisitTitle => getTranslatedString('leaveVisitTitle', 'Leave visit?');
  static String get leaveVisitBody => getTranslatedString('leaveVisitBody', 'Your progress will be saved. You can resume later.');
  static String get stay => getTranslatedString('stay', 'Stay');
  static String get leave => getTranslatedString('leave', 'Leave');

  static String stepOneOfThree(String programme) => getTranslatedString('stepOneOfThree', 'STEP 1 OF 3 · AI TRIAGE · {programme}', params: {'programme': '$programme'});
  static String get stepLabel1 => getTranslatedString('stepLabel1', 'How are you feeling?');
  static String get stepLabel2 => getTranslatedString('stepLabel2', 'AI triage');
  static String get stepLabel3 => getTranslatedString('stepLabel3', 'Detailed check');

  static String get beforeYouKnock => getTranslatedString('beforeYouKnock', 'Before you knock · AI brief');
  static String briefBody(String name) => getTranslatedString('briefBody', '⚠ {name} · current concerns flagged — act today if symptoms persist', params: {'name': '$name'});

  static String get skAsksFamily => getTranslatedString('skAsksFamily', 'SK ASKS THE FAMILY ');

  static String get durationQuestion => getTranslatedString('durationQuestion', 'How many days? · How many days sick?');
  static String get aiCheckingCta => getTranslatedString('aiCheckingCta', 'AI is checking — see what to do next');
}

/// AI Scribe strings — voice recording → SOAP note flow.
abstract final class ScribeStrings {
  ScribeStrings._();

  static String get fabIdle => getTranslatedString('fabIdle', 'Record consultation');
  static String get fabStop => getTranslatedString('fabStop', 'Stop recording');
  static String get fabReview => getTranslatedString('fabReview', 'Review AI note');
  static String get fabRetry => getTranslatedString('fabRetry', 'Retry upload');

  static String get pillRecording => getTranslatedString('pillRecording', 'Recording…');
  static String get pillUploading => getTranslatedString('pillUploading', 'Uploading…');
  static String get pillProcessing => getTranslatedString('pillProcessing', 'AI processing note…');
  static String get pillReady => getTranslatedString('pillReady', 'AI note ready — tap ✦ to review');

  static String get rationaleTitle => getTranslatedString('rationaleTitle', 'AI Scribe');
  static String get rationaleSubtitle => getTranslatedString('rationaleSubtitle', 'Voice → clinical note');
  static String get rationaleAllow => getTranslatedString('rationaleAllow', 'Allow');
  static String get rationaleNotNow => getTranslatedString('rationaleNotNow', 'Not now');

  static String get reviewAccept => getTranslatedString('reviewAccept', 'Accept Note');
  static String get reviewReject => getTranslatedString('reviewReject', 'Reject');
  static String get reviewRequired => getTranslatedString('reviewRequired', 'Review required');
  static String get reviewWarning => getTranslatedString('reviewWarning', 'Please review all sections before accepting.');

  static String get acceptedSnackbar => getTranslatedString('acceptedSnackbar', 'Note accepted ✓');
  static String get rejectedSnackbar => getTranslatedString('rejectedSnackbar', 'Note discarded');

  static String get settingsTitle => getTranslatedString('settingsTitle', 'Microphone access needed');
  static String get settingsBody => getTranslatedString('settingsBody', 'AI Scribe needs microphone access to record consultations. Enable it in Settings → App permissions.');
  static String get settingsOpen => getTranslatedString('settingsOpen', 'Open Settings');
  static String get settingsCancel => getTranslatedString('settingsCancel', 'Cancel');

  static String uploadProgress(double pct) => getTranslatedString(
      'Scribe.uploadProgress', 'Uploading…  {pct}%', params: {'pct': pct.toStringAsFixed(0)});
  static String recordingTimer(int secs) {
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return getTranslatedString('Scribe.recordingTimer', 'Recording…  {mm}:{ss}',
        params: {'mm': mm, 'ss': ss});
  }

  // ── S4 triage pre-tick hook (S4.6) ───────────────────────────────────────
  static String get triageConsentPrompt => getTranslatedString('triageConsentPrompt', 'Record conversation to auto-select symptoms?');
  static String get triageConsentAllow => getTranslatedString('triageConsentAllow', 'Allow');
  static String get triageConsentDeny => getTranslatedString('triageConsentDeny', 'Not now');

  static String get transcriptionFailed => getTranslatedString('transcriptionFailed', 'Transcription failed.');
  static String get pollTimeout => getTranslatedString('pollTimeout', 'AI is taking too long. Tap to try again.');
  static String get pollUnreachable => getTranslatedString('pollUnreachable', 'Could not reach AI Scribe. Tap to try again.');
  static String get recordingNotFinalized => getTranslatedString('recordingNotFinalized', 'Recording could not be saved. Please record again.');
  static String get recordingNoOutput => getTranslatedString('recordingNoOutput', 'Recording produced no output. Please record again.');
  static String get noSpeechDetected => getTranslatedString('noSpeechDetected', 'No speech detected — please speak closer to the microphone and try again.');
  static String get recordingStartFailed => getTranslatedString('recordingStartFailed', 'Could not start recording. Check microphone permissions and try again.');
  static String get noteNotAvailable => getTranslatedString('noteNotAvailable', 'Note not available.');
  static String get transcriptLabel => getTranslatedString('transcriptLabel', 'Transcript');

  // Mic-permission rationale sheet bullets.
  static String get bulletRecordsAudio =>
      getTranslatedString('Scribe.bulletRecordsAudio', 'Records consultation audio');
  static String get bulletReviewBeforeSave =>
      getTranslatedString('Scribe.bulletReviewBeforeSave', 'You review and accept before it saves');
  static String get bulletAudioDeletedAfterProcessing => getTranslatedString(
      'Scribe.bulletAudioDeletedAfterProcessing', 'Audio deleted from server after processing');

  // SOAP section headings in the review sheet.
  static String get soapSubjectiveTitle => getTranslatedString('Scribe.soapSubjectiveTitle', 'Subjective');
  static String get soapSubjectiveSubtitle =>
      getTranslatedString('Scribe.soapSubjectiveSubtitle', "Patient's reported symptoms");
  static String get soapObjectiveTitle => getTranslatedString('Scribe.soapObjectiveTitle', 'Objective');
  static String get soapObjectiveSubtitle =>
      getTranslatedString('Scribe.soapObjectiveSubtitle', 'Clinical findings & vitals');
  static String get soapAssessmentTitle => getTranslatedString('Scribe.soapAssessmentTitle', 'Assessment');
  static String get soapAssessmentSubtitle =>
      getTranslatedString('Scribe.soapAssessmentSubtitle', 'Diagnosis / impression');
  static String get soapPlanTitle => getTranslatedString('Scribe.soapPlanTitle', 'Plan');
  static String get soapPlanSubtitle =>
      getTranslatedString('Scribe.soapPlanSubtitle', 'Treatment & follow-up');

  static String get aiModelFallback => getTranslatedString('Scribe.aiModelFallback', 'AI');
  /// [pct] arrives pre-formatted (`toStringAsFixed(0)`) from the call site.
  static String confidencePctModel(String pct, String model) => getTranslatedString(
      'Scribe.confidencePctModel', '{pct}% confidence · {model}',
      params: {'pct': pct, 'model': model});
}

/// AI Scribe inline banner strings (replaces FAB labels for the new single-form layout).
abstract final class ScribeBannerStrings {
  ScribeBannerStrings._();

  static String get idle => getTranslatedString('ScribeBanner.idle', '🎙 AI Scribe — tap and let him/her speak');
  static String get idleSub => getTranslatedString('idleSub', 'Tap a mode to start');
  static String get recording => getTranslatedString('recording', 'Recording…');
  static String get uploading => getTranslatedString('uploading', 'Uploading…');
  static String get processing => getTranslatedString('processing', 'AI processing note…');
  static String get ready => getTranslatedString('ready', 'AI note ready — tap to review');
  static String get error => getTranslatedString('error', 'Upload failed — tap to retry');

  /// Badge shown once the "Other" (standard/batch) mode is active, so it's
  /// always clear which engine — this or Real-Time ASR — is running.
  static String get modeOtherBadge => getTranslatedString('modeOtherBadge', 'OTHER');

  static String get modeGemini => getTranslatedString('modeGemini', 'Gemini');
  static String get modeGeminiFull => getTranslatedString('modeGeminiFull', 'AI Scribe · Gemini');
  static String get modeAsrFull => getTranslatedString('modeAsrFull', 'Live ASR · Sarvam');
  static String get modeSheetTitle => getTranslatedString('modeSheetTitle', 'AI Scribe mode');
  static String get modeGeminiTitle => getTranslatedString('modeGeminiTitle', 'AI Scribe (Gemini)');
  static String get modeGeminiDesc => getTranslatedString('modeGeminiDesc', 'Records full consultation. AI analyzes after recording ends.');
  static String get modeAsrTitle => getTranslatedString('modeAsrTitle', 'Live ASR (Sarvam)');
  static String get modeAsrDesc => getTranslatedString('modeAsrDesc', 'Real-time Bengali transcript + live detected symptoms.');
  static String get modeGeminiDefault => getTranslatedString('modeGeminiDefault', 'Default');
  static String get preFillTitle => getTranslatedString('ScribeBanner.preFillTitle', 'AI Scribe');
  static String get reviewAllCta => getTranslatedString('ScribeBanner.reviewAllCta', 'Review All');
  static String get acceptAllCta => getTranslatedString('ScribeBanner.acceptAllCta', 'Accept All');

  static String get confidenceHigh => getTranslatedString('ScribeBanner.confidenceHigh', 'High confidence');
  static String get confidenceMedium => getTranslatedString('ScribeBanner.confidenceMedium', 'Medium');
  static String get confidenceReviewNeeded => getTranslatedString('ScribeBanner.confidenceReviewNeeded', 'Review needed');
  static String get statusAccepted => getTranslatedString('ScribeBanner.statusAccepted', 'Accepted');
  static String get statusModified => getTranslatedString('ScribeBanner.statusModified', 'Modified');
  /// Source literal is three ASCII periods, not U+2026 — kept byte-identical.
  static String get processingEllipsis => getTranslatedString('ScribeBanner.processingEllipsis', 'Processing...');
  static String get stopLabel => getTranslatedString('ScribeBanner.stopLabel', 'Stop');
  static String get aiScribeLabel => getTranslatedString('ScribeBanner.aiScribeLabel', 'AI Scribe');
  static String fieldsExtractedCount(int n) => getTranslatedString(
      'ScribeBanner.fieldsExtractedCount', '{fieldCount} fields extracted from recording',
      params: {'fieldCount': '$n'});
  static String get acceptTooltip => getTranslatedString('ScribeBanner.acceptTooltip', 'Accept');
  static String get editTooltip => getTranslatedString('ScribeBanner.editTooltip', 'Edit');
  static String get rejectTooltip => getTranslatedString('ScribeBanner.rejectTooltip', 'Reject');
}

/// Bottom-nav tab labels + placeholder copy.
/// Pilot slice of the localization seam (see [LoginStrings] doc comment).
abstract final class BottomNavStrings {
  BottomNavStrings._();

  static String get home => getTranslatedString('home', 'Home');
  static String get patients => getTranslatedString('BottomNav.patients', 'Patients');
  static String get assistant => getTranslatedString('assistant', 'Assistant');

  static String get pressBackAgainToExit => getTranslatedString('pressBackAgainToExit', 'Press back again to exit');
}

/// Symptom triage picker screen strings.
/// Phase 1: Symptom-driven unified assessment flow.
abstract final class TriageStrings {
  TriageStrings._();

  // ── Screen titles ────────────────────────────────────────────────────────
  static String get pickerTitle => getTranslatedString('pickerTitle', 'What symptoms does the patient have?');
  static String get pickerSubtitle => getTranslatedString('pickerSubtitle', 'Select all that apply');
  static String get noSymptomsRoutineVisit => getTranslatedString('noSymptomsRoutineVisit', 'No symptoms / routine visit');
  static String get continueButton => getTranslatedString('continueButton', 'Continue');
  static String get skipButton => getTranslatedString('Triage.skipButton', 'Skip');
  static String get retryButton => getTranslatedString('Triage.retryButton', 'Retry');

  // ── Cluster headers ──────────────────────────────────────────────────────
  static String get clusterDangerSigns => getTranslatedString('clusterDangerSigns', 'Danger Signs');
  static String get clusterFeverRespiratory => getTranslatedString('clusterFeverRespiratory', 'Fever & Respiratory');
  static String get clusterGiNutrition => getTranslatedString('clusterGiNutrition', 'GI & Nutrition');
  static String get clusterMaternal => getTranslatedString('clusterMaternal', 'Maternal');
  static String get clusterNcdMetabolic => getTranslatedString('clusterNcdMetabolic', 'NCD / Metabolic');
  static String get clusterTbIndicators => getTranslatedString('clusterTbIndicators', 'TB Indicators');
  static String get clusterMentalHealth => getTranslatedString('clusterMentalHealth', 'Mental Health');
  static String get clusterChildHealth => getTranslatedString('clusterChildHealth', 'Child Health');


  /// Returns the localized label for a symptom code.
  static String symptomLabel(String code) {
    switch (code) {
      // Danger signs
      case 'convulsions':
        return getTranslatedString('Triage.symptom.convulsions', 'Fits / Convulsions');
      case 'unconscious':
        return getTranslatedString('Triage.symptom.unconscious', 'Unconscious / Unresponsive');
      case 'lethargy':
        return getTranslatedString('Triage.symptom.lethargy', 'Unusually sleepy / Difficult to wake');
      case 'not_eating':
        return getTranslatedString('Triage.symptom.not_eating', 'Not eating / drinking');
      case 'chest_indrawing':
        return getTranslatedString('Triage.symptom.chest_indrawing', 'Chest in-drawing');
      case 'stridor':
        return getTranslatedString('Triage.symptom.stridor', 'Stridor (noisy breathing)');
      case 'vaginal_bleeding':
        return getTranslatedString('Triage.symptom.vaginal_bleeding', 'Vaginal bleeding');
      case 'water_break':
        return getTranslatedString('Triage.symptom.water_break', 'Water break / Leaking');
      case 'reduced_fetal_movement':
        return getTranslatedString('Triage.symptom.reduced_fetal_movement', 'Baby not moving');
      case 'chest_pain':
        return getTranslatedString('Triage.symptom.chest_pain', 'Chest pain');
      case 'hemoptysis':
        return getTranslatedString('Triage.symptom.hemoptysis', 'Blood in sputum');
      // Fever & respiratory
      case 'fever':
        return getTranslatedString('Triage.symptom.fever', 'Fever');
      case 'cough':
        return getTranslatedString('Triage.symptom.cough', 'Cough');
      case 'cough_over_2_weeks':
        return getTranslatedString('Triage.symptom.cough_over_2_weeks', 'Cough > 2 weeks');
      case 'difficulty_breathing':
        return getTranslatedString('Triage.symptom.difficulty_breathing', 'Difficulty breathing');
      case 'fast_breathing':
        return getTranslatedString('Triage.symptom.fast_breathing', 'Fast breathing');
      case 'shortness_breath':
        return getTranslatedString('Triage.symptom.shortness_breath', 'Shortness of breath');
      // GI & nutrition
      case 'diarrhea':
        return getTranslatedString('Triage.symptom.diarrhea', 'Diarrhea');
      case 'bloody_diarrhea':
        return getTranslatedString('Triage.symptom.bloody_diarrhea', 'Bloody diarrhea');
      case 'vomiting':
        return getTranslatedString('Triage.symptom.vomiting', 'Vomiting');
      case 'loss_appetite':
        return getTranslatedString('Triage.symptom.loss_appetite', 'Loss of appetite');
      case 'muac_red':
        return getTranslatedString('Triage.symptom.muac_red', 'MUAC red zone');
      case 'visible_wasting':
        return getTranslatedString('Triage.symptom.visible_wasting', 'Visible wasting');
      case 'edema_both_feet':
        return getTranslatedString('Triage.symptom.edema_both_feet', 'Edema of both feet');
      case 'weight_loss':
        return getTranslatedString('Triage.symptom.weight_loss', 'Weight loss');
      // Maternal
      case 'pregnant':
        return getTranslatedString('Triage.symptom.pregnant', 'Pregnant / suspected');
      case 'headache_severe':
        return getTranslatedString('Triage.symptom.headache_severe', 'Severe headache');
      case 'blurred_vision':
        return getTranslatedString('Triage.symptom.blurred_vision', 'Blurred vision');
      case 'abdominal_pain':
        return getTranslatedString('Triage.symptom.abdominal_pain', 'Abdominal pain');
      case 'swelling_face_hands':
        return getTranslatedString('Triage.symptom.swelling_face_hands', 'Swelling');
      case 'high_bp_known':
        return getTranslatedString('Triage.symptom.high_bp_known', 'High BP known / suspected');
      case 'labor_signs':
        return getTranslatedString('Triage.symptom.labor_signs', 'Labor signs');
      // NCD / metabolic
      case 'dizziness':
        return getTranslatedString('Triage.symptom.dizziness', 'Dizziness');
      case 'numbness':
        return getTranslatedString('Triage.symptom.numbness', 'Numbness / Tingling');
      case 'polyuria':
        return getTranslatedString('Triage.symptom.polyuria', 'Frequent urination');
      case 'polydipsia':
        return getTranslatedString('Triage.symptom.polydipsia', 'Excessive thirst');
      case 'foot_pain':
        return getTranslatedString('Triage.symptom.foot_pain', 'Foot pain');
      case 'foot_wound':
        return getTranslatedString('Triage.symptom.foot_wound', 'Foot wound');
      // TB indicators
      case 'night_sweats':
        return getTranslatedString('Triage.symptom.night_sweats', 'Night sweats');
      case 'fatigue':
        return getTranslatedString('Triage.symptom.fatigue', 'Fatigue');
      case 'tb_contact':
        return getTranslatedString('Triage.symptom.tb_contact', 'TB contact history');
      // Mental health
      case 'feeling_sad':
        return getTranslatedString('Triage.symptom.feeling_sad', 'Feeling sad / hopeless');
      case 'anxiety':
        return getTranslatedString('Triage.symptom.anxiety', 'Anxiety / Worry');
      case 'sleep_difficulty':
        return getTranslatedString('Triage.symptom.sleep_difficulty', 'Difficulty sleeping');
      // Child health
      case 'ear_problem':
        return getTranslatedString('Triage.symptom.ear_problem', 'Ear problem');
      case 'skin_rash':
        return getTranslatedString('Triage.symptom.skin_rash', 'Skin rash');
      case 'eye_discharge':
        return getTranslatedString('Triage.symptom.eye_discharge', 'Eye discharge');
      case 'umbilicus_red':
        return getTranslatedString('Triage.symptom.umbilicus_red', 'Umbilicus red / discharge');
      case 'jaundice':
        return getTranslatedString('Triage.symptom.jaundice', 'Jaundice (yellow skin / eyes)');
      // AI Scribe triage vocab — codes not in the cluster catalog
      case 'heavy_bleeding':
        return getTranslatedString('Triage.symptom.heavy_bleeding', 'Heavy bleeding');
      case 'foul_smelling_vaginal_discharge':
        return getTranslatedString('Triage.symptom.foul_smelling_vaginal_discharge', 'Foul-smelling vaginal discharge');
      case 'epigastric_pain':
        return getTranslatedString('Triage.symptom.epigastric_pain', 'Epigastric pain');
      case 'headache':
        return getTranslatedString('Triage.symptom.headache', 'Headache');
      case 'edema':
        return getTranslatedString('Triage.symptom.edema', 'Edema');
      case 'breast_pain':
        return getTranslatedString('Triage.symptom.breast_pain', 'Breast pain');
      case 'breast_swelling':
        return getTranslatedString('Triage.symptom.breast_swelling', 'Breast swelling');
      case 'perineal_wound_discharge':
        return getTranslatedString('Triage.symptom.perineal_wound_discharge', 'Perineal wound discharge');
      case 'painful_urination':
        return getTranslatedString('Triage.symptom.painful_urination', 'Painful urination');
      case 'breathlessness':
        return getTranslatedString('Triage.symptom.breathlessness', 'Breathlessness');
      case 'leaking_fluid_vagina':
        return getTranslatedString('Triage.symptom.leaking_fluid_vagina', 'Leaking fluids');
      case 'painful_uterine_contractions':
        return getTranslatedString('Triage.symptom.painful_uterine_contractions', 'Painful uterine contractions');
      case 'one_sided_weakness':
        return getTranslatedString('Triage.symptom.one_sided_weakness', 'One-sided weakness');
      case 'swelling_both_feet':
        return getTranslatedString('Triage.symptom.swelling_both_feet', 'Swelling of both feet');
      case 'palpitations':
        return getTranslatedString('Triage.symptom.palpitations', 'Palpitations');
      case 'swelling_one_leg':
        return getTranslatedString('Triage.symptom.swelling_one_leg', 'Swelling of one leg');
      case 'excessive_thirst':
        return getTranslatedString('Triage.symptom.excessive_thirst', 'Excessive thirst');
      case 'foot_numbness':
        return getTranslatedString('Triage.symptom.foot_numbness', 'Foot numbness');
      case 'weakness':
        return getTranslatedString('Triage.symptom.weakness', 'Weakness');
      default:
        return code;
    }
  }

  // ── Eligible services grid (Step 1) ───────────────────────────────────────
  static String get eligibleServicesHeader => getTranslatedString('Triage.eligibleServicesHeader', '✦ Eligible services');
  static String get eligibleServicesTag => getTranslatedString('Triage.eligibleServicesTag', 'Age & gender based');
  static String get enrolledBadge => getTranslatedString('enrolledBadge', 'Enrolled');
  static String get pwHint => getTranslatedString('Triage.pwHint', '⚠ Select \'PW\' first to unlock ANC');
  /// Chip label — Android "Pregnancy Outcome" menu (not mother PNC).
  static String get pregnancyOutcomeChip => getTranslatedString('pregnancyOutcomeChip', 'Pregnancy Outcome');
  static String get deliveryHint => getTranslatedString('deliveryHint', 'Pregnancy Outcome documents the birth this visit and clears ANC');
  static String get ancDeliveryConflictHint => getTranslatedString('ancDeliveryConflictHint', '⚠ Unavailable on a pregnancy-outcome visit — deselect Pregnancy Outcome first');
  static String get pncOnlyPostpartumHint => getTranslatedString('pncOnlyPostpartumHint', '⚠ Mother PNC is available after delivery — use Pregnancy Outcome now');
  static String get pwLockedPostpartumHint => getTranslatedString('pwLockedPostpartumHint', '⚠ This pregnancy has already ended — PW registration is only for a new pregnancy');
  static String get pregnancyOutcomeLockedHint => getTranslatedString('pregnancyOutcomeLockedHint', '⚠ Pregnancy Outcome is not available for this patient right now');
  static String get fpLockedPregnantHint => getTranslatedString('fpLockedPregnantHint', '⚠ Family Planning is unavailable during an active pregnancy');
  static String get vaccinationDefaultHint => getTranslatedString('vaccinationDefaultHint', 'Vaccination is always included for this visit — only Child Health is optional');
  static String pwEpisodeSubtitle({required String lmp, required String edd}) => getTranslatedString('Triage.pwEpisodeSubtitle', 'LMP: {lmp} · EDD: {edd}', params: {'lmp': lmp, 'edd': edd});
  static String get ancVisitedTodayMessage => getTranslatedString('Triage.ancVisitedTodayMessage', 'ANC already recorded today');
  static String ancRevisitMessageNormal({required String lastVisit, required String nextDue}) => getTranslatedString('Triage.ancRevisitMessageNormal', 'Last visit: {lastVisit} · next due {nextDue}', params: {'lastVisit': lastVisit, 'nextDue': nextDue});
  static String ancRevisitMessageHighRisk({required String lastVisit}) => getTranslatedString('Triage.ancRevisitMessageHighRisk', 'Last visit: {lastVisit} (high-risk — 1-day interval)', params: {'lastVisit': lastVisit});

  static String selectProgrammeA11y(String label) => getTranslatedString('selectProgrammeA11y', 'Select {label}', params: {'label': '$label'});
  static String deselectProgrammeA11y(String label) => getTranslatedString('deselectProgrammeA11y', 'Deselect {label}', params: {'label': '$label'});
  static String enrolledProgrammeA11y(String label) => getTranslatedString('enrolledProgrammeA11y', 'Enrolled {label} — tap to include or exclude from this visit', params: {'label': '$label'});
}

/// Form compositor strings — section titles, field labels, banners, and
/// orchestrator progress copy for the Phase 2 sectioned assessment flow.
///
/// All user-facing strings for the composer pipeline live here — widgets must
/// never inline string literals.
abstract final class ComposerStrings {
  ComposerStrings._();


  /// Resolve a field label by its [labelKey].  Matches the key constants used
  /// in [FieldDef.labelKey] and returns the localized string.  Unknown keys
  /// fall back to [key] (raw) so the UI never shows blank labels.
  static String fieldLabel(String key) {
    switch (key) {
      case 'fieldTemperature':
        return getTranslatedString('Composer.field.fieldTemperature', 'Temperature');
      case 'fieldBreathsPerMinute':
        return getTranslatedString('Composer.field.fieldBreathsPerMinute', 'Respiratory rate');
      case 'fieldWeightKg':
        return getTranslatedString('Composer.field.fieldWeightKg', 'Weight (kg)');
      case 'fieldMuacCm':
        return getTranslatedString('Composer.field.fieldMuacCm', 'MUAC (cm)');
      case 'fieldSpo2':
        return getTranslatedString('Composer.field.fieldSpo2', 'SpO2 (%)');
      case 'fieldHasCough':
        return getTranslatedString('Composer.field.fieldHasCough', 'Has cough');
      case 'fieldCoughDays':
        return getTranslatedString('Composer.field.fieldCoughDays', 'Cough duration (days)');
      case 'fieldHasFever':
        return getTranslatedString('Composer.field.fieldHasFever', 'Has fever');
      case 'fieldFeverDays':
        return getTranslatedString('Composer.field.fieldFeverDays', 'Fever duration (days)');
      case 'fieldHasDiarrhea':
        return getTranslatedString('Composer.field.fieldHasDiarrhea', 'Has diarrhea');
      case 'fieldUnableToBreastfeed':
        return getTranslatedString('Composer.field.fieldUnableToBreastfeed', 'Unable to drink / breastfeed');
      case 'fieldVomitsEverything':
        return getTranslatedString('Composer.field.fieldVomitsEverything', 'Vomits everything');
      case 'fieldHasConvulsions':
        return getTranslatedString('Composer.field.fieldHasConvulsions', 'Has convulsions');
      case 'fieldLethargic':
        return getTranslatedString('Composer.field.fieldLethargic', 'Lethargic / unconscious');
      case 'fieldChestIndrawing':
        return getTranslatedString('Composer.field.fieldChestIndrawing', 'Chest in-drawing');
      case 'fieldStridor':
        return getTranslatedString('Composer.field.fieldStridor', 'Stridor when calm');
      case 'fieldIsBloodyDiarrhea':
        return getTranslatedString('Composer.field.fieldIsBloodyDiarrhea', 'Bloody diarrhea');
      case 'fieldHasFastBreathing':
        return getTranslatedString('Composer.field.fieldHasFastBreathing', 'Fast breathing');
      case 'fieldRdtResult':
        return getTranslatedString('Composer.field.fieldRdtResult', 'RDT result');
      case 'fieldActDispensed':
        return getTranslatedString('Composer.field.fieldActDispensed', 'ACT dispensed');
      case 'fieldOrsDispensed':
        return getTranslatedString('Composer.field.fieldOrsDispensed', 'ORS dispensed');
      case 'fieldZincDispensed':
        return getTranslatedString('Composer.field.fieldZincDispensed', 'Zinc dispensed');
      case 'fieldAmoxicillinDispensed':
        return getTranslatedString('Composer.field.fieldAmoxicillinDispensed', 'Amoxicillin dispensed');
      case 'fieldHasCoughLastedLonger':
        return getTranslatedString('Composer.field.fieldHasCoughLastedLonger', 'Cough ≥ 2 weeks');
      case 'fieldHasNightSweats':
        return getTranslatedString('Composer.field.fieldHasNightSweats', 'Night sweats');
      case 'fieldHasWeightLoss':
        return getTranslatedString('Composer.field.fieldHasWeightLoss', 'Weight loss');
      case 'fieldRelationshipToIC':
        return getTranslatedString('Composer.field.fieldRelationshipToIC', 'Relationship to index case');
      case 'fieldSleepLocation':
        return getTranslatedString('Composer.field.fieldSleepLocation', 'Sleep location');
      case 'fieldPreviouslyTreatedForTB':
        return getTranslatedString('Composer.field.fieldPreviouslyTreatedForTB', 'Previously treated for TB');
      // Shared vitals
      case 'fieldHeight':
        return getTranslatedString('Composer.field.fieldHeight', 'Height (cm)');
      case 'fieldWeight':
        return getTranslatedString('Composer.field.fieldWeight', 'Weight (kg)');
      case 'fieldPulse':
        return getTranslatedString('Composer.field.fieldPulse', 'Pulse');
      // ANC fields
      case 'fieldBloodPressureSystolic':
        return getTranslatedString('Composer.field.fieldBloodPressureSystolic', 'Systolic BP');
      case 'fieldBloodPressureDiastolic':
        return getTranslatedString('Composer.field.fieldBloodPressureDiastolic', 'Diastolic BP');
      case 'fieldAncWeight':
        return getTranslatedString('Composer.field.fieldAncWeight', 'Weight');
      case 'fieldFundalHeight':
        return getTranslatedString('Composer.field.fieldFundalHeight', 'Fundal height');
      case 'fieldFetalHeartRate':
        return getTranslatedString('Composer.field.fieldFetalHeartRate', 'Fetal heart rate');
      case 'fieldFetalMovement':
        return getTranslatedString('Composer.field.fieldFetalMovement', 'Fetal movement');
      case 'fieldOedema':
        return getTranslatedString('Composer.field.fieldOedema', 'Oedema');
      case 'fieldEdema':
        return getTranslatedString('Composer.field.fieldEdema', 'Edema');
      case 'fieldPallor':
        return getTranslatedString('Composer.field.fieldPallor', 'Pallor');
      case 'fieldTtTdCompleted':
        return getTranslatedString('Composer.field.fieldTtTdCompleted', 'TT/Td vaccination');
      case 'fieldIfaProvided':
        return getTranslatedString('Composer.field.fieldIfaProvided', 'IFA tablets provided');
      case 'fieldCalciumProvided':
        return getTranslatedString('Composer.field.fieldCalciumProvided', 'Calcium tablets provided');
      case 'fieldFacilityIdentifiedForDelivery':
        return getTranslatedString('Composer.field.fieldFacilityIdentifiedForDelivery', 'Has the PW identified a health facility for institutional delivery?');
      case 'fieldUltrasound':
        return getTranslatedString('Composer.field.fieldUltrasound', 'Ultrasound');
      case 'fieldHemoglobin':
        return getTranslatedString('Composer.field.fieldHemoglobin', 'Hemoglobin (Hb)');
      case 'fieldBloodSugar':
        return getTranslatedString('Composer.field.fieldBloodSugar', 'Blood sugar type');
      case 'fieldBloodSugarFasting':
        return getTranslatedString('Composer.field.fieldBloodSugarFasting', 'Fasting blood sugar');
      case 'fieldBloodSugarRandom':
        return getTranslatedString('Composer.field.fieldBloodSugarRandom', 'Random blood sugar');
      case 'fieldUrinaryAlbumin':
        return getTranslatedString('Composer.field.fieldUrinaryAlbumin', 'Urinary albumin');
      case 'fieldUrinarySugar':
        return getTranslatedString('Composer.field.fieldUrinarySugar', 'Urinary sugar');
      case 'fieldUrinaryBilirubin':
        return getTranslatedString('Composer.field.fieldUrinaryBilirubin', 'Urinary bilirubin');
      case 'fieldFolicAcidConsumed':
        return getTranslatedString('Composer.field.fieldFolicAcidConsumed', 'Folic acid consumed (last month)');
      case 'fieldFolicAcidProvided':
        return getTranslatedString('Composer.field.fieldFolicAcidProvided', 'Folic acid provided');
      case 'fieldIfaConsumed':
        return getTranslatedString('Composer.field.fieldIfaConsumed', 'IFA tablets consumed (last month)');
      case 'fieldCalciumConsumed':
        return getTranslatedString('Composer.field.fieldCalciumConsumed', 'Calcium consumed (last month)');
      case 'fieldAncVisitsOtherProviders':
        return getTranslatedString('Composer.field.fieldAncVisitsOtherProviders', 'ANC visits with other providers');
      case 'fieldAncFromMedicalDoctor':
        return getTranslatedString('Composer.field.fieldAncFromMedicalDoctor', 'ANC from medical doctor?');
      case 'fieldPreviousPregnancyComplications':
        return getTranslatedString('Composer.field.fieldPreviousPregnancyComplications', 'Previous pregnancy complications');
      case 'fieldDangerSigns12':
        return getTranslatedString('Composer.field.fieldDangerSigns12', 'Danger signs (weeks 1–12)');
      case 'fieldDangerSigns13to27':
        return getTranslatedString('Composer.field.fieldDangerSigns13to27', 'Danger signs (weeks 13–27)');
      case 'fieldDangerSigns28to40':
        return getTranslatedString('Composer.field.fieldDangerSigns28to40', 'Danger signs (weeks 28–40)');
      case 'fieldReferralFacility':
        return getTranslatedString('Composer.field.fieldReferralFacility', 'Referral facility');
      // NCD fields
      case 'fieldSystolic2':
        return getTranslatedString('Composer.field.fieldSystolic2', 'Systolic BP (2nd reading)');
      case 'fieldDiastolic2':
        return getTranslatedString('Composer.field.fieldDiastolic2', 'Diastolic BP (2nd reading)');
      case 'fieldIsRegularSmoker':
        return getTranslatedString('Composer.field.fieldIsRegularSmoker', 'Regular smoker');
      case 'fieldMedAdherence':
        return getTranslatedString('Composer.field.fieldMedAdherence', 'Medication adherence');
      case 'fieldNcdSymptoms':
        return getTranslatedString('Composer.field.fieldNcdSymptoms', 'Symptoms');
      case 'fieldHasSymptoms':
        return getTranslatedString('Composer.field.fieldHasSymptoms', 'Had symptoms since last follow-up?');
      case 'fieldNewWorseningSymptoms':
        return getTranslatedString('Composer.field.fieldNewWorseningSymptoms', 'New or worsening symptoms');
      case 'fieldCompliance':
        return getTranslatedString('Composer.field.fieldCompliance', 'Taking medication regularly?');
      case 'fieldGlucoseValue':
        return getTranslatedString('Composer.field.fieldGlucoseValue', 'Blood glucose');
      case 'fieldGlucoseType':
        return getTranslatedString('Composer.field.fieldGlucoseType', 'Glucose measurement type');
      case 'fieldHba1c':
        return getTranslatedString('Composer.field.fieldHba1c', 'HbA1c');
      case 'fieldFootExam':
        return getTranslatedString('Composer.field.fieldFootExam', 'Foot examination');
      case 'fieldFootWound':
        return getTranslatedString('Composer.field.fieldFootWound', 'Foot wound present');
      // EPI fields
      case 'fieldOverdueVaccines':
        return fieldOverdueVaccines;
      case 'fieldVaccinesGivenToday':
        return fieldVaccinesGivenToday;
      // NUTRITION fields
      case 'fieldEdemaOfBothFeet':
        return fieldEdemaOfBothFeet;
      case 'fieldVisibleWasting':
        return fieldVisibleWasting;
      case 'fieldFeedingDifficulty':
        return fieldFeedingDifficulty;
      case 'fieldSupplementaryFoodGiven':
        return fieldSupplementaryFoodGiven;
      case 'fieldReferredForSam':
        return fieldReferredForSam;
      // PNC fields (legacy)
      case 'fieldDaysPostDelivery':
        return fieldDaysPostDelivery;
      case 'fieldHasUterinePain':
        return fieldHasUterinePain;
      case 'fieldHasExcessiveBleeding':
        return fieldHasExcessiveBleeding;
      case 'fieldHasBreastProblem':
        return fieldHasBreastProblem;
      case 'fieldNewbornPresent':
        return fieldNewbornPresent;
      case 'fieldNewbornBreastfeeding':
        return fieldNewbornBreastfeeding;
      case 'fieldPncVitaminsGiven':
        return fieldPncVitaminsGiven;
      // PNC Mother fields
      case 'fieldGravida':
        return fieldGravida;
      case 'fieldParity':
        return fieldParity;
      case 'fieldLivingChildren':
        return fieldLivingChildren;
      case 'fieldHtnPatient':
        return fieldHtnPatient;
      case 'fieldEclampsia':
        return fieldEclampsia;
      case 'fieldOnTreatmentHtnEclampsia':
        return fieldOnTreatmentHtnEclampsia;
      case 'fieldDmPatient':
        return fieldDmPatient;
      case 'fieldGdmPatient':
        return fieldGdmPatient;
      case 'fieldOnTreatmentDmGdm':
        return fieldOnTreatmentDmGdm;
      case 'fieldFastingBloodSugar':
        return fieldFastingBloodSugar;
      case 'fieldRandomBloodSugar':
        return fieldRandomBloodSugar;
      case 'fieldPostpartumDangerSigns':
        return fieldPostpartumDangerSigns;
      case 'fieldVitaminAConsumed':
        return fieldVitaminAConsumed;
      case 'fieldIfaTabletsConsumed':
        return fieldIfaTabletsConsumed;
      case 'fieldIfaTabletsProvided':
        return fieldIfaTabletsProvided;
      case 'fieldCalciumTabletsConsumed':
        return fieldCalciumTabletsConsumed;
      case 'fieldCalciumTabletsProvided':
        return fieldCalciumTabletsProvided;
      case 'fieldFamilyPlanningMethods':
        return fieldFamilyPlanningMethods;
      // PNC Neonatal fields
      case 'fieldPncNeonateSigns':
        return fieldPncNeonateSigns;
      case 'fieldOtherPncNeonateSigns':
        return fieldOtherPncNeonateSigns;
      case 'fieldNewbornReferredToSbcu':
        return fieldNewbornReferredToSbcu;
      case 'fieldLowBirthWeight':
        return fieldLowBirthWeight;
      case 'fieldDeathOfNewborn':
        return fieldDeathOfNewborn;
      // PNC Child fields
      case 'fieldCongenitalDefect':
        return fieldCongenitalDefect;
      case 'fieldPncChildWeight':
        return fieldPncChildWeight;
      case 'fieldChildFeedLast24Hrs':
        return fieldChildFeedLast24Hrs;
      case 'fieldOtherChildFeed':
        return fieldOtherChildFeed;
      case 'fieldHrsBreastFed':
        return fieldHrsBreastFed;
      case 'fieldMonthAdditionalFeedGiven':
        return fieldMonthAdditionalFeedGiven;
      case 'fieldChildBreastFeeding':
        return fieldChildBreastFeeding;
      case 'fieldAdditionalFood24Hrs':
        return fieldAdditionalFood24Hrs;
      case 'fieldReceivedVaccine':
        return fieldReceivedVaccine;
      case 'fieldDewormingMedicine':
        return fieldDewormingMedicine;
      case 'fieldAnyIllness':
        return fieldAnyIllness;
      case 'fieldChildIllnessType':
        return fieldChildIllnessType;
      case 'fieldChildReferral':
        return fieldChildReferral;
      case 'fieldChildReferralFacilityType':
        return fieldChildReferralFacilityType;
      case 'fieldOnBpMedication':
        return fieldOnBpMedication;
      case 'fieldWaistCircumference':
        return fieldWaistCircumference;
      case 'fieldIsPhysicallyActive':
        return fieldIsPhysicallyActive;
      case 'fieldEatsDailyFruitVeg':
        return fieldEatsDailyFruitVeg;
      case 'fieldHadPreviousHighGlucose':
        return fieldHadPreviousHighGlucose;
      case 'fieldHasFamilyHistoryDm':
        return fieldHasFamilyHistoryDm;
      case 'fieldNumberOfLivingChildren':
        return fieldNumberOfLivingChildren;
      case 'fieldAgeOfLastChildMonths':
        return fieldAgeOfLastChildMonths;
      case 'fieldDesireForFutureChildren':
        return fieldDesireForFutureChildren;
      case 'fieldCurrentFpMethod':
        return fieldCurrentFpMethod;
      case 'fieldEyeDiseaseTypes':
        return fieldEyeDiseaseTypes;
      case 'fieldReferredForOperation':
        return fieldReferredForOperation;
      case 'fieldNcdServiceProvided':
        return fieldNcdServiceProvided;
      case 'fieldEyeTestOutcome':
        return fieldEyeTestOutcome;
      case 'fieldGlassPrescription':
        return fieldGlassPrescription;
      case 'fieldGlassesSold':
        return fieldGlassesSold;
      case 'fieldReferPlace':
        return fieldReferPlace;
      case 'fieldMorningHeadaches':
        return fieldMorningHeadaches;
      case 'fieldChestTightnessOrSob':
        return fieldChestTightnessOrSob;
      case 'fieldHighSaltIntake':
        return fieldHighSaltIntake;
      case 'fieldFamilyHistoryHtn':
        return fieldFamilyHistoryHtn;
      case 'fieldOneSidedWeakness':
        return fieldOneSidedWeakness;
      default:
        return key;
    }
  }

  // ── Section title resolver ──────────────────────────────────────────────────

  // ── NCD HTN screening fields (spec §5.2.2) ──────────────────────────────────
  static String get fieldMorningHeadaches => getTranslatedString('fieldMorningHeadaches', 'Morning headaches?');
  static String get fieldChestTightnessOrSob => getTranslatedString('fieldChestTightnessOrSob', 'Chest tightness or shortness of breath?');
  static String get fieldHighSaltIntake => getTranslatedString('fieldHighSaltIntake', 'High salt in daily food?');
  static String get fieldFamilyHistoryHtn => getTranslatedString('fieldFamilyHistoryHtn', 'Family history of high BP?');
  static String get fieldOneSidedWeakness => getTranslatedString('fieldOneSidedWeakness', 'One-sided weakness or stroke signs?');

  // ── FINDRISC / Framingham fields ────────────────────────────────────────────
  static String get fieldOnBpMedication => getTranslatedString('fieldOnBpMedication', 'On BP medication?');
  static String get fieldWaistCircumference => getTranslatedString('fieldWaistCircumference', 'Waist circumference (cm)');
  static String get fieldIsPhysicallyActive => getTranslatedString('fieldIsPhysicallyActive', 'Physically active ≥ 30 min/day?');
  static String get fieldEatsDailyFruitVeg => getTranslatedString('fieldEatsDailyFruitVeg', 'Eats fruit / vegetables daily?');
  static String get fieldHadPreviousHighGlucose => getTranslatedString('fieldHadPreviousHighGlucose', 'Previous high blood glucose?');
  static String get fieldHasFamilyHistoryDm => getTranslatedString('fieldHasFamilyHistoryDm', 'Family history of diabetes?');

  // ── Family planning fields ───────────────────────────────────────────────────
  static String get fieldNumberOfLivingChildren => getTranslatedString('fieldNumberOfLivingChildren', 'Number of living children');
  static String get fieldAgeOfLastChildMonths => getTranslatedString('fieldAgeOfLastChildMonths', 'Age of last child (months)');
  static String get fieldDesireForFutureChildren => getTranslatedString('fieldDesireForFutureChildren', 'Desire for future children');
  static String get fieldCurrentFpMethod => getTranslatedString('fieldCurrentFpMethod', 'Current FP method');

  // ── Eye / cataract fields ────────────────────────────────────────────────────
  static String get fieldEyeDiseaseTypes => getTranslatedString('fieldEyeDiseaseTypes', 'Eye disease type(s)');
  static String get fieldReferredForOperation => getTranslatedString('fieldReferredForOperation', 'Referred for operation?');
  static String get fieldNcdServiceProvided => getTranslatedString('fieldNcdServiceProvided', 'NCD service provided?');
  static String get fieldEyeTestOutcome => getTranslatedString('fieldEyeTestOutcome', 'Eye test outcome');
  static String get fieldGlassPrescription => getTranslatedString('fieldGlassPrescription', 'Glasses prescription');
  static String get fieldGlassesSold => getTranslatedString('fieldGlassesSold', 'Glasses sold?');
  static String get fieldReferPlace => getTranslatedString('fieldReferPlace', 'Referral facility');

  // ── Programme group headers ─────────────────────────────────────────────────
  static String get groupGeneral => getTranslatedString('groupGeneral', 'General checks');
  static String get groupNcd => getTranslatedString('groupNcd', 'NCD checks');
  static String get groupTb => getTranslatedString('groupTb', 'TB checks');
  static String get groupAnc => getTranslatedString('groupAnc', 'Antenatal checks');
  static String get groupPnc => getTranslatedString('groupPnc', 'Postnatal checks');
  static String get groupImci => getTranslatedString('groupImci', 'Child health checks');
  static String get groupEpi => getTranslatedString('groupEpi', 'Immunization');
  static String get groupNutrition => getTranslatedString('groupNutrition', 'Nutrition');
  static String get groupFamilyPlanning => getTranslatedString('groupFamilyPlanning', 'Family planning');
  static String get groupCataract => getTranslatedString('groupCataract', 'Cataract / eye disease');
  static String get groupEyeCare => getTranslatedString('groupEyeCare', 'Eye care');


  // ── Field labels (EPI) ──────────────────────────────────────────────────────
  static String get fieldOverdueVaccines => getTranslatedString('fieldOverdueVaccines', 'Overdue vaccines');
  static String get fieldVaccinesGivenToday => getTranslatedString('fieldVaccinesGivenToday', 'Vaccines given today');

  // ── Field labels (NUTRITION) ────────────────────────────────────────────────
  static String get fieldEdemaOfBothFeet => getTranslatedString('fieldEdemaOfBothFeet', 'Edema of both feet');
  static String get fieldVisibleWasting => getTranslatedString('fieldVisibleWasting', 'Visible wasting');
  static String get fieldFeedingDifficulty => getTranslatedString('fieldFeedingDifficulty', 'Feeding difficulty');
  static String get fieldSupplementaryFoodGiven => getTranslatedString('fieldSupplementaryFoodGiven', 'Supplementary food given');
  static String get fieldReferredForSam => getTranslatedString('fieldReferredForSam', 'Referred for SAM');

  // ── Field labels (PNC) ──────────────────────────────────────────────────────
  static String get fieldDaysPostDelivery => getTranslatedString('fieldDaysPostDelivery', 'Days post-delivery');
  static String get fieldHasUterinePain => getTranslatedString('fieldHasUterinePain', 'Uterine pain');
  static String get fieldHasExcessiveBleeding => getTranslatedString('fieldHasExcessiveBleeding', 'Excessive bleeding');
  static String get fieldHasBreastProblem => getTranslatedString('fieldHasBreastProblem', 'Breast problem');
  static String get fieldNewbornPresent => getTranslatedString('fieldNewbornPresent', 'Newborn present');
  static String get fieldNewbornBreastfeeding => getTranslatedString('fieldNewbornBreastfeeding', 'Newborn breastfeeding');
  static String get fieldPncVitaminsGiven => getTranslatedString('fieldPncVitaminsGiven', 'PNC vitamins given');
  // PNC Mother
  static String get fieldGravida => getTranslatedString('fieldGravida', 'Gravida');
  static String get fieldParity => getTranslatedString('fieldParity', 'Parity (total births)');
  static String get fieldLivingChildren => getTranslatedString('fieldLivingChildren', 'Living children');
  static String get fieldHtnPatient => getTranslatedString('fieldHtnPatient', 'Known HTN patient?');
  static String get fieldEclampsia => getTranslatedString('fieldEclampsia', 'Pre-eclampsia / eclampsia?');
  static String get fieldOnTreatmentHtnEclampsia => getTranslatedString('fieldOnTreatmentHtnEclampsia', 'On treatment for HTN / eclampsia?');
  static String get fieldDmPatient => getTranslatedString('fieldDmPatient', 'Known DM patient?');
  static String get fieldGdmPatient => getTranslatedString('fieldGdmPatient', 'Known GDM patient?');
  static String get fieldOnTreatmentDmGdm => getTranslatedString('fieldOnTreatmentDmGdm', 'On treatment for DM / GDM?');
  static String get fieldFastingBloodSugar => getTranslatedString('fieldFastingBloodSugar', 'Fasting blood sugar (mmol/L)');
  static String get fieldRandomBloodSugar => getTranslatedString('fieldRandomBloodSugar', 'Random blood sugar (mmol/L)');
  static String get fieldPostpartumDangerSigns => getTranslatedString('fieldPostpartumDangerSigns', 'Postpartum danger signs');
  static String get fieldVitaminAConsumed => getTranslatedString('fieldVitaminAConsumed', 'Vitamin A capsule consumed?');
  static String get fieldIfaTabletsConsumed => getTranslatedString('fieldIfaTabletsConsumed', 'IFA tablets consumed');
  static String get fieldIfaTabletsProvided => getTranslatedString('fieldIfaTabletsProvided', 'IFA tablets provided');
  static String get fieldCalciumTabletsConsumed => getTranslatedString('fieldCalciumTabletsConsumed', 'Calcium tablets consumed');
  static String get fieldCalciumTabletsProvided => getTranslatedString('fieldCalciumTabletsProvided', 'Calcium tablets provided');
  static String get fieldFamilyPlanningMethods => getTranslatedString('fieldFamilyPlanningMethods', 'Family planning method');
  // PNC Neonatal
  static String get fieldPncNeonateSigns => getTranslatedString('fieldPncNeonateSigns', 'Newborn danger signs');
  static String get fieldOtherPncNeonateSigns => getTranslatedString('fieldOtherPncNeonateSigns', 'Other newborn signs');
  static String get fieldNewbornReferredToSbcu => getTranslatedString('fieldNewbornReferredToSbcu', 'Newborn referred to SBCU?');
  static String get fieldLowBirthWeight => getTranslatedString('fieldLowBirthWeight', 'Low birth weight?');
  static String get fieldDeathOfNewborn => getTranslatedString('fieldDeathOfNewborn', 'Death of newborn?');
  // PNC Child
  static String get fieldCongenitalDefect => getTranslatedString('fieldCongenitalDefect', 'Congenital defect?');
  static String get fieldPncChildWeight => getTranslatedString('fieldPncChildWeight', 'Child weight (kg)');
  static String get fieldChildFeedLast24Hrs => getTranslatedString('fieldChildFeedLast24Hrs', 'Child feeding in last 24 hours');
  static String get fieldOtherChildFeed => getTranslatedString('fieldOtherChildFeed', 'Other feed');
  static String get fieldHrsBreastFed => getTranslatedString('fieldHrsBreastFed', 'Hours after birth breastfeeding started');
  static String get fieldMonthAdditionalFeedGiven => getTranslatedString('fieldMonthAdditionalFeedGiven', 'Month additional food started');
  static String get fieldChildBreastFeeding => getTranslatedString('fieldChildBreastFeeding', 'Child breastfeeding?');
  static String get fieldAdditionalFood24Hrs => getTranslatedString('fieldAdditionalFood24Hrs', 'Additional food in last 24 hours?');
  static String get fieldReceivedVaccine => getTranslatedString('fieldReceivedVaccine', 'Child received vaccines?');
  static String get fieldDewormingMedicine => getTranslatedString('fieldDewormingMedicine', 'Child took deworming medicine?');
  static String get fieldAnyIllness => getTranslatedString('fieldAnyIllness', 'Any illness / complications?');
  static String get fieldChildIllnessType => getTranslatedString('fieldChildIllnessType', 'Type of illness / complication');
  static String get fieldChildReferral => getTranslatedString('fieldChildReferral', 'Referral made?');
  static String get fieldChildReferralFacilityType => getTranslatedString('fieldChildReferralFacilityType', 'Referral facility type');

  /// Resolve a section title from its [sectionId].
  static String sectionTitle(String sectionId) {
    switch (sectionId) {
      case 'vitals':
        return getTranslatedString('Composer.section.vitals', 'Vitals');
      case 'danger-signs':
        return getTranslatedString('Composer.section.danger-signs', 'Danger Signs');
      case 'symptom-detail':
        return getTranslatedString('Composer.section.symptom-detail', 'Symptoms');
      case 'iccm-classify':
        return getTranslatedString('Composer.section.iccm-classify', 'ICCM Assessment');
      case 'tb-screen-detail':
        return getTranslatedString('Composer.section.tb-screen-detail', 'TB Screening');
      case 'anc-vitals':
        return getTranslatedString('Composer.section.anc-vitals', 'ANC Vitals');
      case 'anc-specific':
        return getTranslatedString('Composer.section.anc-specific', 'ANC Assessment');
      case 'ncd-htn':
        return getTranslatedString('Composer.section.ncd-htn', 'Hypertension');
      case 'ncd-dm':
        return getTranslatedString('Composer.section.ncd-dm', 'Diabetes');
      case 'epi-review':
        return getTranslatedString('Composer.section.epi-review', 'EPI / Immunization');
      case 'nutrition-detail':
        return getTranslatedString('Composer.section.nutrition-detail', 'Nutrition Assessment');
      case 'pnc-check':
        return getTranslatedString('Composer.section.pnc-check', 'Postnatal Check');
      case 'pnc-mother':
        return getTranslatedString('Composer.section.pnc-mother', 'Postnatal — Mother');
      case 'pnc-neonatal':
        return getTranslatedString('Composer.section.pnc-neonatal', 'Postnatal — Newborn');
      case 'pnc-child':
        return getTranslatedString('Composer.section.pnc-child', 'Postnatal — Child');
      case 'ncd-findrisc':
        return getTranslatedString('Composer.section.ncd-findrisc', 'Diabetes Risk (FINDRISC)');
      case 'family-planning':
        return getTranslatedString('Composer.section.family-planning', 'Family Planning');
      case 'cataract-exam':
        return getTranslatedString('Composer.section.cataract-exam', 'Cataract / Eye Disease');
      case 'eye-care-exam':
        return getTranslatedString('Composer.section.eye-care-exam', 'Eye Care');
      default:
        return sectionId;
    }
  }

  // ── AI Scribe pre-fill indicators (S4.6) ───────────────────────────────────
  static String get unmappedFindingsTitle => getTranslatedString('unmappedFindingsTitle', 'Also mentioned');
  static String get scribeAiBadge => getTranslatedString('scribeAiBadge', 'AI');
  static String get scribeAiPreFilledHint => getTranslatedString('scribeAiPreFilledHint', 'Pre-filled by AI — please verify');
  static String get scribeRecordButton => getTranslatedString('scribeRecordButton', 'Record');

  // ── Cross-section reveal banner ─────────────────────────────────────────────
  static String get tbAddedBannerText => getTranslatedString('tbAddedBannerText', 'TB screening added — cough ≥ 2 weeks');

  // ── Submit / orchestrator ───────────────────────────────────────────────────
  static String syncProgress(int done, int total) => getTranslatedString('syncProgress', '{done} of {total} programmes synced', params: {'done': '$done', 'total': '$total'});
  static String get submitButton => getTranslatedString('submitButton', 'Submit Assessment');
  static String get resumeDraftTitle => getTranslatedString('resumeDraftTitle', 'Resume visit?');
  static String get resumeDraftMessage => getTranslatedString('resumeDraftMessage', 'An unfinished assessment was found.');
  static String get resumeButton => getTranslatedString('resumeButton', 'Resume');
  static String get discardButton => getTranslatedString('discardButton', 'Discard');
  static String get startOverButton => getTranslatedString('startOverButton', 'Start Over');
  static String get offlineFallbackBannerText => getTranslatedString('offlineFallbackBannerText', 'Offline — showing basic guidance. Connect to internet for the full AI recommendation.');
  static String get nextButton => getTranslatedString('nextButton', 'Next');
  static String get dismissOkButton => getTranslatedString('dismissOkButton', 'OK');

  // ── Extended field widget strings ───────────────────────────────────────────
  static String get selectDateHint => getTranslatedString('selectDateHint', 'Select date');
  static String get bpSystolicHint => getTranslatedString('bpSystolicHint', 'SYS');
  static String get bpDiastolicHint => getTranslatedString('bpDiastolicHint', 'DIA');
  static String get bpUnit => getTranslatedString('Composer.bpUnit', 'mmHg');
  static String get bpValidationError => getTranslatedString('bpValidationError', 'Enter a valid reading');
  static String get bpDiastolicExceedsSystolicError => getTranslatedString('bpDiastolicExceedsSystolicError', 'Diastolic must be less than systolic');
  static String get pulseValidationError => getTranslatedString('pulseValidationError', 'Enter a pulse between 50 and 300 bpm');
  static String get glucoseValidationError => getTranslatedString('glucoseValidationError', 'Enter a glucose reading between 0 and 33 mmol/L');
  static String get haemoglobinValidationError => getTranslatedString('haemoglobinValidationError', 'Enter a Hb reading between 1.0 and 20.0 g/dL');
  static String get tabletCountValidationError => getTranslatedString('tabletCountValidationError', 'Enter a value between 0 and 60');
  static String get temperatureValidationError => getTranslatedString('temperatureValidationError', 'Enter a temperature between 90 and 110°F, or 0 if it could not be measured');
  static String get fundalHeightValidationError => getTranslatedString('fundalHeightValidationError', 'Enter a fundal height between 8 and 45 cm');
  static String get hba1cValidationError => getTranslatedString('hba1cValidationError', 'Enter an HbA1c reading between 4.0% and 14.0%');
  static String get ageLabel => getTranslatedString('Composer.ageLabel', 'Age');
  static String get dobLabel => getTranslatedString('dobLabel', 'Date of Birth');
  static String get yearsShort => getTranslatedString('yearsShort', 'Y');
  static String get monthsShort => getTranslatedString('monthsShort', 'M');
  static String get daysShort => getTranslatedString('daysShort', 'D');
  static String get noneSelected => getTranslatedString('noneSelected', 'None selected');
  static String get tapToSelect => getTranslatedString('tapToSelect', 'Tap to select');
  static String get doneLabel => getTranslatedString('doneLabel', 'Done');
  static String nSelected(int n) => getTranslatedString('nSelected', '{n} selected', params: {'n': '$n'});

  // ── BP / glucose range status labels ────────────────────────────────────────
  static String get rangeNormal => getTranslatedString('rangeNormal', 'Normal');
  static String get rangeElevated => getTranslatedString('rangeElevated', 'Elevated');
  static String get rangeBpStage1 => getTranslatedString('rangeBpStage1', 'Slightly elevated');
  static String get rangeBpStage2 => getTranslatedString('rangeBpStage2', 'Stage 2 HTN');
  static String get rangeBpCrisis => getTranslatedString('rangeBpCrisis', 'Hypertensive Crisis ⚠');
  static String get rangeInRange => getTranslatedString('rangeInRange', 'In Range');
  static String get rangeOutOfRange => getTranslatedString('rangeOutOfRange', 'Out of Range');

  // ── Vital flag labels (abnormal indicator badges) ───────────────────────────
  static String get vitalFlagHigh => getTranslatedString('vitalFlagHigh', 'High ⚠');
  static String get vitalFlagLow => getTranslatedString('vitalFlagLow', 'Low ⚠');

  // ── MUAC classification labels ───────────────────────────────────────────────
  static String get muacLabel => getTranslatedString('Composer.muacLabel', 'MUAC (cm)');
  static String get muacSam => getTranslatedString('muacSam', 'SAM');
  static String get muacMam => getTranslatedString('muacMam', 'MAM');
  static String get muacNormal => getTranslatedString('muacNormal', 'Normal');

  // ── Lab result reference prefix ──────────────────────────────────────────────
  static String get labReferencePrefix => getTranslatedString('labReferencePrefix', 'Ref:');

  // ── Referral urgency labels ──────────────────────────────────────────────────
  static String get referralUrgencyLabel => getTranslatedString('referralUrgencyLabel', 'Urgency');
  static String get referralRoutine => getTranslatedString('referralRoutine', 'Routine');
  static String get referralUrgent => getTranslatedString('referralUrgent', 'Urgent');
  static String get referralEmergency => getTranslatedString('referralEmergency', 'Emergency');

  // ── Pregnancy profile labels ─────────────────────────────────────────────────
  static String get lmpLabel => getTranslatedString('Composer.lmpLabel', 'Last Menstrual Period');
  static String get eddLabel => getTranslatedString('Composer.eddLabel', 'Estimated Due Date');
  static String get gestationalAgeLabel => getTranslatedString('Composer.gestationalAgeLabel', 'Gestational Age');
  static String get gestationalAgeWeeks => getTranslatedString('gestationalAgeWeeks', 'wks');
  static String get gestationalAgeDays => getTranslatedString('gestationalAgeDays', 'days');
  static String get gestationalAgePreterm => getTranslatedString('gestationalAgePreterm', 'Preterm (< 37 weeks)');
  static String get pregnancyOverviewNoData => getTranslatedString('pregnancyOverviewNoData', 'Pregnancy data not available');
  static String get pregnancyOverviewLmp => getTranslatedString('pregnancyOverviewLmp', 'LMP');
  static String get pregnancyOverviewEdd => getTranslatedString('pregnancyOverviewEdd', 'EDD');

  // ── Glass prescription labels ────────────────────────────────────────────────
  static String get eyeOd => getTranslatedString('eyeOd', 'OD (Right)');
  static String get eyeOs => getTranslatedString('eyeOs', 'OS (Left)');
  static String get sphereLabel => getTranslatedString('sphereLabel', 'Sphere');
  static String get cylinderLabel => getTranslatedString('cylinderLabel', 'Cylinder');
  static String get axisLabel => getTranslatedString('axisLabel', 'Axis');
  static String get glassPrescriptionSummary => getTranslatedString('glassPrescriptionSummary', 'Prescription recorded');

  // ── ANC visit summary chip (Step 1 — Before You Knock) ──────────────────────
  static String get ancSummaryEyebrow => getTranslatedString('ancSummaryEyebrow', 'ANC VISIT');
  static String get ancSummaryGaUnit => getTranslatedString('ancSummaryGaUnit', 'wks GA');
  static String get ancSummaryVisitPrefix => getTranslatedString('ancSummaryVisitPrefix', '#');
  static String get ancSummaryHighRisk => getTranslatedString('ancSummaryHighRisk', 'High-risk');
  static String get ancSummaryNearTerm => getTranslatedString('ancSummaryNearTerm', 'Near-term');
  static String get ancSummaryAncGap => getTranslatedString('ancSummaryAncGap', 'ANC gap');
  static String get ancSummaryBpElevated => getTranslatedString('ancSummaryBpElevated', 'BP elevated');
  static String get ancSummaryParityFormat => getTranslatedString('ancSummaryParityFormat', 'G{g}P{p}');
  static String ancSummaryParity(int g, int p) => getTranslatedString('ancSummaryParity', 'G{g}P{p}', params: {'g': '$g', 'p': '$p'});

  // ── Compound-widget column sub-labels ────────────────────────────────────────
  static String get heightShort => getTranslatedString('heightShort', 'Height');
  static String get weightShort => getTranslatedString('weightShort', 'Weight');
  static String get parityShort => getTranslatedString('parityShort', 'Parity');
  static String get livingShort => getTranslatedString('livingShort', 'Living');

  // ── Urine test sub-labels ────────────────────────────────────────────────────
  static String get urinaryAlbuminShort => getTranslatedString('urinaryAlbuminShort', 'Albumin');
  static String get urinarySugarShort => getTranslatedString('urinarySugarShort', 'Sugar');
  static String get urinaryBilirubinShort => getTranslatedString('urinaryBilirubinShort', 'Bilirubin');

  // ── Supply pair sub-labels ───────────────────────────────────────────────────
  static String get supplyConsumedShort => getTranslatedString('supplyConsumedShort', 'Consumed');
  static String get supplyProvidedShort => getTranslatedString('supplyProvidedShort', 'Provided today');
}

// ─────────────────────────────────────────────────────────────────────────────
// TriageResultStrings
// ─────────────────────────────────────────────────────────────────────────────

/// Only the step-bar labels remain live — consumed by [VisitStepHeader],
/// which is still shared with the live SymptomPickerScreen. The rest of this
/// class served the now-deleted TriageResultScreen.
abstract final class TriageResultStrings {
  TriageResultStrings._();

  // ── Step bar ────────────────────────────────────────────────────────────────
  static String get step1Label => getTranslatedString('TriageResult.step1Label', 'Step 1 · Symptoms');
  static String get step2Label => getTranslatedString('TriageResult.step2Label', 'Step 2 · Triage');
  static String get step3Label => getTranslatedString('TriageResult.step3Label', 'Step 3 · Assessment');

  static String stepSubtitle(int stepIndex) {
    switch (stepIndex) {
      case 0:
        return getTranslatedString(
            'TriageResult.stepSubtitle1', 'Step 1 of 3 · Tap all symptoms mentioned');
      case 1:
        return getTranslatedString('TriageResult.stepSubtitle2', 'Step 2 of 3 · AI triage active');
      default:
        return getTranslatedString(
            'TriageResult.stepSubtitle3', 'Step 3 of 3 · Fill in what you see');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SymptomPickerStrings
// ─────────────────────────────────────────────────────────────────────────────

/// Which service the Greet Warmly card's coaching hint is written for —
/// see [SymptomPickerStrings.sitWithGreetHintFor]. Only pregnancy and
/// postpartum name a distinct checkup; every other service (TB, NCD, or
/// nothing selected) shares one generic line.
///
/// The spoken greeting line deliberately does NOT branch on this — see
/// [SymptomPickerStrings.sitWithGreetEnglishFor].
enum _GreetWarmlyService { pregnancy, postpartum, general }

abstract final class SymptomPickerStrings {
  SymptomPickerStrings._();

  // ── AI Scribe triage banner (spec §4.1.2 / §5.1.1) ───────────────────────
  static String scribeBannerTitleFor({required bool isFemale}) => isFemale
      ? getTranslatedString('SymptomPicker.scribeBannerTitleFemale', '🎙 AI Scribe — tap and let her speak')
      : getTranslatedString('SymptomPicker.scribeBannerTitleMale', '🎙 AI Scribe — tap and let him speak');
  static String scribeBannerSubtitleFor({required bool isFemale}) => isFemale
      ? getTranslatedString('SymptomPicker.scribeBannerSubtitleFemale',
          'Symptoms appear automatically as she talks')
      : getTranslatedString('SymptomPicker.scribeBannerSubtitleMale',
          'Symptoms appear automatically as he talks');
  // Legacy non-gendered variants — kept for the realtime-ASR triage banner
  // (feat/asr-bruger) which does not thread patient sex into the banner copy.
  static String get scribeBannerTitle => getTranslatedString('scribeBannerTitle', '🎙 AI Scribe — tap to fill the form by voice');
  static String get scribeBannerSubtitle => getTranslatedString('scribeBannerSubtitle', 'SK talks to her/him — fields fill automatically');
  static String get scribeBannerDone => getTranslatedString('scribeBannerDone', 'Voice capture complete');
  static String get scribeBannerRecording => getTranslatedString('scribeBannerRecording', 'Listening… tap to stop');
  static String get scribeBannerProcessing => getTranslatedString('scribeBannerProcessing', 'AI is reviewing the recording');
  static String get scribeBannerTriageProcessing => getTranslatedString('scribeBannerTriageProcessing', 'Analysing symptoms…');
  static String get scribeBannerProcessingSubtitle => getTranslatedString('scribeBannerProcessingSubtitle', 'Transcribing your recording…');
  static String scribeDoneWithCount(int n) => n == 1
      ? getTranslatedString(
          'SymptomPicker.scribeDoneOneSymptom', 'Scribe complete · 1 symptom detected')
      : n > 1
          ? getTranslatedString('SymptomPicker.scribeDoneManySymptoms',
              'Scribe complete · {n} symptoms detected', params: {'n': '$n'})
          : getTranslatedString('SymptomPicker.scribeDoneNoSymptoms', 'Scribe complete');
  static String get scribeBannerDoneSubtitle => getTranslatedString('scribeBannerDoneSubtitle', 'Tap to record again');
  static String get scribeBannerRecordingSubtitle => getTranslatedString('scribeBannerRecordingSubtitle', 'Tap anywhere to stop');
  static String get scribeBannerError => getTranslatedString('scribeBannerError', 'Voice review failed');
  static String get scribeBannerErrorSubtitle => getTranslatedString('scribeBannerErrorSubtitle', 'Tap to try again');
  static String get scribeBannerNoSymptoms => getTranslatedString('scribeBannerNoSymptoms', 'No symptoms detected');
  static String get scribeBannerNoSymptomsSubtitle => getTranslatedString('scribeBannerNoSymptomsSubtitle', 'Speak the patient\'s symptoms clearly, then tap to try again');

  /// Accessibility label for the in-circle stop affordance shown while the
  /// AI Scribe is recording.
  static String get scribeStopRecordingLabel => getTranslatedString('scribeStopRecordingLabel', 'Stop recording');

  // ── AI briefing cards ────────────────────────────────────────────────────
  static String get briefCardTitle => getTranslatedString('briefCardTitle', 'Before you knock · AI brief');
  static String get briefCard1Title => getTranslatedString('briefCard1Title', 'Before You Knock');

  // ── Before You Knock instructional leading line ──────────────────────────
  /// Shown on the navy strip at the top of Card 1.
  static String beforeYouKnockGreetingFor({required bool isFemale}) => isFemale
      ? getTranslatedString('SymptomPicker.beforeYouKnockGreetingFemale', 'Sit with her — greet them.')
      : getTranslatedString('SymptomPicker.beforeYouKnockGreetingMale', 'Sit with him — greet them.');

  // ── "Sit with her / him — greet warmly" card (Step 1, between
  // Before-You-Knock and the AI Scribe). Header and hint are app UI/
  // instructions *to the SK* — locale-aware via getTranslatedString, so they
  // follow the app's language setting; the greeting line the SK reads aloud
  // is also locale-aware (single language, never both at once — see
  // GreetWarmlyCard). All four are AI-preferred (from the briefing
  // response's `greeting` block) with these as the offline / AI-unavailable
  // fallback.
  //
  // `isChild` (under-5 patient) redirects every line to the guardian —
  // an under-5 patient cannot answer for themselves, so the SK greets and
  // questions the guardian *about* the child rather than addressing the
  // child directly. Gender-neutral: a guardian greeting doesn't depend on
  // the child's sex.
  //
  // The hint keys off `selectedProgrammes` (the SK's currently-ticked
  // service cards) so it names the actual checkup instead of always
  // assuming a pregnancy one. The spoken greeting line does not — see
  // [sitWithGreetEnglishFor].

  /// Which service the coaching hint should be written for, derived from the
  /// SK's currently-selected programme cards. Pregnancy takes priority over
  /// any other simultaneously-selected service since it's the most
  /// safety-relevant context. TB and NCD don't get a distinct hint — they
  /// fall through to the general bucket.
  static _GreetWarmlyService _greetWarmlyServiceFor(
    Set<Programme>? selectedProgrammes,
  ) {
    final p = selectedProgrammes ?? const <Programme>{};
    if (p.contains(Programme.anc) || p.contains(Programme.pw)) {
      return _GreetWarmlyService.pregnancy;
    }
    if (p.contains(Programme.pnc)) return _GreetWarmlyService.postpartum;
    return _GreetWarmlyService.general;
  }

  /// Header (uppercase, small). Gendered + locale-aware; guardian-directed
  /// for a child patient. Not service-specific — the instruction to the SK
  /// doesn't change with the visit type.
  ///
  /// `isFemale` is tri-state: `true` female, `false` male, **`null` when the
  /// patient's sex isn't recorded** — which says "HIM/HER" rather than
  /// silently picking one. An unrecorded sex used to collapse into the male
  /// branch, so the card confidently told the SK to sit with "HIM" for a
  /// patient nobody had recorded a sex for.
  static String sitWithGreetHeaderFor({
    required bool? isFemale,
    bool isChild = false,
  }) {
    if (isChild) {
      return getTranslatedString(
        'sitWithGreetHeaderGuardian',
        '👋 SIT WITH THE GUARDIAN — GREET WARMLY',
      );
    }
    if (isFemale == null) {
      return getTranslatedString(
        'sitWithGreetHeaderUnknownSex',
        '👋 SIT WITH HIM/HER — GREET WARMLY',
      );
    }
    return getTranslatedString(
      isFemale ? 'sitWithGreetHeaderFemale' : 'sitWithGreetHeaderMale',
      isFemale
          ? '👋 SIT WITH HER — GREET WARMLY'
          : '👋 SIT WITH HIM — GREET WARMLY',
    );
  }

  /// Bangla greeting the SK opens with. Two cases only — a child patient
  /// (the guardian is addressed about the child) and everyone else — see
  /// [sitWithGreetEnglishFor] for why nothing else branches.
  ///
  /// Deliberately NOT routed through `getTranslatedString`/`strings.json`
  /// like the rest of this file: this method (and [sitWithGreetEnglishFor])
  /// must return Bangla/English text unconditionally, independent of the
  /// live `AppLocale.isBangla` flag — `getTranslatedString` reads that flag
  /// internally, so delegating through it would make `sitWithGreetEnglishFor`
  /// silently return Bangla whenever the app happens to be in Bangla mode.
  /// `greet_warmly_card_test.dart` calls both methods explicitly regardless
  /// of the current locale specifically to catch that class of bug — see
  /// "Bangla app language falls back to static Bangla when greeting is
  /// null", which fails if this is refactored to share a
  /// `getTranslatedString`-based helper with [sitWithGreetEnglishFor].
  static String sitWithGreetBanglaFor({bool isChild = false}) => isChild
      ? 'বাবুটি কেমন আছে?\nঠিকমতো খাচ্ছে ও ঘুমাচ্ছে তো?'
      : 'আপনি কেমন বোধ করছেন?\nকোনো সমস্যা আছে কি?';

  /// English translation of [sitWithGreetBanglaFor] — same two cases. See
  /// that method's doc comment for why this stays hardcoded rather than
  /// routed through `getTranslatedString`.
  ///
  /// Carries no salutation and no gendered wording, at any age, whether or
  /// not the patient's sex is recorded. This mirrors the AI greeting
  /// contract in leapfrog-ai-service (`_EN_SALUTATION_RE` /
  /// `_BN_SALUTATION_RE` in `briefing_service.py`, and the `greeting` spec in
  /// `prompts/briefing_visit.txt`), which forbids "আপু" / "কাকা" / "Sister" /
  /// "Brother" and opens with the question itself in the genderless polite
  /// আপনি form. Keeping the offline fallback salutation-free means the SK
  /// reads the same register whether or not the briefing call succeeded, and
  /// it removes the mis-address risk that a gendered vocative carries when
  /// the patient's sex is unrecorded — the online path hit exactly that (a
  /// male NCD patient greeted "Sister") before the vocative was dropped.
  ///
  /// The greeting also does not branch on the visit type or gestational age,
  /// so it can never ask a question the visit doesn't warrant. The AI path
  /// still tailors both when it is reachable — including the fetal-movement
  /// question, which that service permits only once a gestational age is
  /// known and indicates late pregnancy.
  ///
  /// `isChild` (under-5) is the one branch: the child cannot answer for
  /// themselves, so both lines ask the guardian *about* the child. No
  /// pronoun for the child either — the Bangla line never had one, and the
  /// guardian's own gender is never known.
  static String sitWithGreetEnglishFor({bool isChild = false}) => isChild
      ? 'How is the little one? Eating and sleeping well?'
      : 'How are you feeling? Do you have any concern?';

  /// Helper hint below the greeting — primes the SK to talk about home life
  /// before launching the clinical conversation. Gendered + locale-aware;
  /// guardian-directed for a child patient; names the actual visit type
  /// instead of always assuming a pregnancy checkup.
  ///
  /// `isFemale` is tri-state exactly as in [sitWithGreetHeaderFor] — `null`
  /// (sex not recorded) gets he/she wording rather than the male line, so
  /// this stays consistent with the header directly above it.
  static String sitWithGreetHintFor({
    required bool? isFemale,
    bool isChild = false,
    Set<Programme>? selectedProgrammes,
  }) {
    if (isChild) {
      return getTranslatedString(
        'sitWithGreetHintGuardian',
        'Ask the guardian about feeding, sleep, and any danger signs — before starting the checkup',
      );
    }
    if (isFemale == null) {
      // Visit-type-neutral like the male line: with no recorded sex we can't
      // assume a pregnancy or postnatal checkup either.
      return getTranslatedString(
        'sitWithGreetHintUnknownSex',
        'Ask how he/she feels at home, with family, and about his/her sleep — before the visit',
      );
    }
    if (!isFemale) {
      // No non-pregnancy male branch needed — sitWithGreetHintMale was
      // already visit-type-neutral ("before the visit").
      return _sitWithGreetHintAdultFor(isFemale: false);
    }
    switch (_greetWarmlyServiceFor(selectedProgrammes)) {
      case _GreetWarmlyService.pregnancy:
        return _sitWithGreetHintAdultFor(isFemale: true);
      case _GreetWarmlyService.postpartum:
        return getTranslatedString(
          'sitWithGreetHintPostpartum',
          'Ask how she feels at home, with family, and about her sleep — before the postnatal checkup',
        );
      case _GreetWarmlyService.general:
        return getTranslatedString(
          'sitWithGreetHintFemaleGeneral',
          'Ask how she feels at home, with family, and about her sleep — before the visit',
        );
    }
  }

  static String _sitWithGreetHintAdultFor({required bool isFemale}) =>
      getTranslatedString(
        isFemale ? 'sitWithGreetHintFemale' : 'sitWithGreetHintMale',
        isFemale
            ? 'Ask how she feels at home, with family, and about her sleep — before the pregnancy checkup'
            : 'Ask how he feels at home, with family, and about his sleep — before the visit',
      );

  // ── "How is she feeling today?" heading shown just above the AI Scribe.
  static String howFeelingTodayHeadingFor({required bool isFemale}) => isFemale
      ? getTranslatedString('SymptomPicker.howFeelingTodayHeadingFemale', 'How is she feeling today? 🎙️')
      : getTranslatedString('SymptomPicker.howFeelingTodayHeadingMale', 'How is he feeling today? 🎙️');

  // ── Patient context chips ────────────────────────────────────────────────
  static String get chipPregnant => getTranslatedString('chipPregnant', 'Pregnant · ANC');
  static String get chipHtn => getTranslatedString('chipHtn', 'Known HTN');
  static String get chipDm => getTranslatedString('chipDm', 'Known DM');
  static String get chipTbDue => getTranslatedString('chipTbDue', 'TB screen due');
  static String get chipUnder5 => getTranslatedString('chipUnder5', 'Under 5 · IMCI');
  static String get chipRoutine => getTranslatedString('chipRoutine', 'Routine visit');

  // ── SK opener card ───────────────────────────────────────────────────────
  static String get skAsksLabel => getTranslatedString('skAsksLabel', 'SK ASKS THE FAMILY 👋');
  static String get skOpenerPhrase => getTranslatedString('skOpenerPhrase', 'How is the family? Who needs to be seen today?');

  // ── Duration picker ──────────────────────────────────────────────────────
  static String get durationTitle => getTranslatedString('durationTitle', 'How many days unwell?');
  static String get duration1Day => getTranslatedString('duration1Day', '1 day');
  static String get duration2To3Days => getTranslatedString('duration2To3Days', '2–3 days');
  static String get duration4Plus => getTranslatedString('duration4Plus', '4+ days');

  // Duration values (stored in TriageViewModel)
  static String get durationValue1 => getTranslatedString('durationValue1', '1');
  static String get durationValue2to3 => getTranslatedString('durationValue2to3', '2-3');
  static String get durationValue4plus => getTranslatedString('durationValue4plus', '4+');

  // ── CTA button ───────────────────────────────────────────────────────────
  static String get ctaStartCheckup => getTranslatedString('ctaStartCheckup', 'Start Checkup →');
  static String get ctaRoutine => getTranslatedString('ctaRoutine', 'Start Checkup →');

  // ── Status bar above CTA ────────────────────────────────────────────────
  static String symptomsSelectedStatus(int n) => n == 1
      ? getTranslatedString(
          'SymptomPicker.symptomsSelectedOne', '{n} symptom selected', params: {'n': '$n'})
      : getTranslatedString(
          'SymptomPicker.symptomsSelectedMany', '{n} symptoms selected', params: {'n': '$n'});
  static String servicesOpeningStatus(List<String> labels) {
    if (labels.isEmpty) return '';
    if (labels.length == 1) return labels[0];
    return '${labels.sublist(0, labels.length - 1).join(', ')} & ${labels.last}';
  }

  // ── Other symptoms free-text ─────────────────────────────────────────────
  static String get otherSymptomsLabel => getTranslatedString('otherSymptomsLabel', 'Other symptoms / Notes');
  static String get otherSymptomsHint => getTranslatedString('otherSymptomsHint', 'Type symptom manually…');
  static String get otherSymptomsAddFromList => getTranslatedString('otherSymptomsAddFromList', 'Add from list');

  // ── AI-driven symptom list (replaces the hardcoded cluster grid) ─────────
  static String get detectedSymptomsTitle => getTranslatedString('detectedSymptomsTitle', 'AI-Detected Symptoms');
  static String get detectedSymptomsSubtitleFilled => getTranslatedString('detectedSymptomsSubtitleFilled', 'Review each symptom. Tap × to remove anything incorrect, or add what is missing.');
  static String get addSymptomSearchHint => getTranslatedString('addSymptomSearchHint', 'Search or type symptom…');
  static String get searchSymptomsHint => getTranslatedString('searchSymptomsHint', 'Search symptoms…');
  static String get searchMoreHint => getTranslatedString('searchMoreHint', 'Type 3+ letters to find more symptoms');
  static String get searchNoResults => getTranslatedString('searchNoResults', 'No symptoms found');

  /// Header for the shared (cross-programme) symptom section in the grid.
  static String get sectionGeneral => getTranslatedString('sectionGeneral', 'General');

  /// Header for selected symptoms that fall outside the default sections.
  static String get sectionFromSearch => getTranslatedString('sectionFromSearch', 'Added from search');

  /// Shown below the default chip grid when enrolled-programme filtering is
  /// active, to let the SK know general + other-programme symptoms are via search.
  static String get searchOtherProgramsHint => getTranslatedString('searchOtherProgramsHint', 'Search to add more symptoms');

  /// Shown as the empty-state body when the patient has no enrolled programmes
  /// and the default grid is intentionally empty.
  static String get searchOnlyEmptyHint => getTranslatedString('searchOnlyEmptyHint', 'Search for symptoms');

  // ── Non-enrolled programme enrollment prompt ──────────────────────────────
  /// Title for the bottom sheet shown when the SK selects a symptom that
  /// belongs to a programme the patient is not yet enrolled in.
  static String get enrollProgrammeSheetTitle => getTranslatedString('enrollProgrammeSheetTitle', 'New program assessment');

  /// Body copy for the enrollment prompt. {symptom} and {programmes} are
  /// interpolated by the caller.
  static String enrollProgrammeSheetBody(String symptomLabel, String programmeNames) => getTranslatedString('enrollProgrammeSheetBody', '"{symptomLabel}" is associated with the {programmeNames} program. Adding it will include the {programmeNames} assessment in this visit.', params: {'symptomLabel': '$symptomLabel', 'programmeNames': '$programmeNames'});

  static String get enrollProgrammeConfirmCta => getTranslatedString('enrollProgrammeConfirmCta', 'Add to this visit');
  static String get enrollProgrammeCancelCta => getTranslatedString('enrollProgrammeCancelCta', 'Skip for now');
  static String get symptomsSelectedCount => getTranslatedString('symptomsSelectedCount', 'symptom selected'); // prefix with count: "$n symptom(s) selected"
  /// Byte-identical to [symptomsSelectedStatus]; delegates rather than
  /// registering a second translation code for the same copy.
  static String symptomsSelected(int n) => symptomsSelectedStatus(n);
  static String get addSymptomInlineHint => getTranslatedString('addSymptomInlineHint', 'Or type a symptom manually…');
  static String get addSymptomInlineButton => getTranslatedString('addSymptomInlineButton', '+ Add');
  static String get addSymptomListExpand => getTranslatedString('addSymptomListExpand', 'Show symptom list');
  static String get addSymptomListCollapse => getTranslatedString('addSymptomListCollapse', 'Hide symptom list');
  static String get addSymptomCta => getTranslatedString('addSymptomCta', 'Add symptoms');
  static String get addSymptomFromList => getTranslatedString('addSymptomFromList', 'Add from list');
  static String get addSymptomSheetTitle => getTranslatedString('addSymptomSheetTitle', 'Add symptoms');
  static String get addSymptomSheetSubtitle => getTranslatedString('addSymptomSheetSubtitle', 'Tap to add or remove. AI-detected symptoms are already ticked — press Done when finished.');
  static String get addSymptomSheetEmpty => getTranslatedString('addSymptomSheetEmpty', 'All symptoms already added.');
  static String get addSymptomSheetDone => getTranslatedString('addSymptomSheetDone', 'Done');
  static String addSymptomSheetCounter(int added) => added == 0
      ? getTranslatedString('SymptomPicker.addSymptomSheetCounterNone', 'No symptoms selected')
      : getTranslatedString('SymptomPicker.addSymptomSheetCounterSome', '{added} selected',
          params: {'added': '$added'});
  static String get removeSymptomSemanticPrefix => getTranslatedString('removeSymptomSemanticPrefix', 'Remove symptom');
  static String get aiOfflineLocalContext => getTranslatedString('SymptomPicker.aiOfflineLocalContext', 'AI offline · local context');
}

/// Visit-completion copy. `VisitCompleteScreen` itself was deleted (superseded
/// by `VisitFlowScreen`'s inline Step 3) — these 4 members remain live,
/// consumed directly by `VisitFlowScreen`'s Step 3 body and its widget test.
abstract final class VisitCompleteStrings {
  VisitCompleteStrings._();

  static String get saved => getTranslatedString('VisitComplete.saved', 'Assessment saved');
  static String get referralWarning => getTranslatedString('referralWarning', 'Referral recommended based on clinical findings');
  static String get sendCounsellingMessage => getTranslatedString('sendCounsellingMessage', 'Send Counselling Message');
  static String get backToHome => getTranslatedString('backToHome', 'Back to Home');
}

/// Strings for the unified 3-step visit flow (spec §3.1).
///
/// One `VisitFlowScreen` hosts: Step 1 Symptom check → Step 2 Vitals + form →
/// Step 3 AI Recommendation. Progress header shows step labels.
abstract final class VisitFlowStrings {
  VisitFlowStrings._();

  static String get step1Label => getTranslatedString('VisitFlow.step1Label', 'Symptoms');
  static String get step2Label => getTranslatedString('VisitFlow.step2Label', 'Vitals & form');
  static String get step3Label => getTranslatedString('VisitFlow.step3Label', 'AI recommends');

  // Step-pill titles inside the navy flow header.
  // Step 2 is the composite "AI programme recommendation → assessment form"
  // phase, so the pill label stays static and does NOT carry the programme
  // name (which is only known after the SK confirms).
  static String get step1Title => getTranslatedString('step1Title', 'How are you?');
  static String get step2Title => getTranslatedString('step2Title', 'Assessment forms');

  /// ANC/PNC variant of the Step-2 pill title, chosen by `VisitFlowHeader`
  /// when the primary programme is anc or pnc.
  static String get step2TitlePregnancyChecks =>
      getTranslatedString('VisitFlow.step2TitlePregnancyChecks', 'Pregnancy checks');
  // Retained for backwards-compatibility with tests pinning the legacy
  // interpolation contract — the header no longer references this string.
  static String get step2TitleSuffix => getTranslatedString('step2TitleSuffix', 'form');
  static String get step3Title => getTranslatedString('step3Title', 'Summary');
  static String get alsoCoverWhileHere => getTranslatedString('alsoCoverWhileHere', 'ALSO COVER WHILE YOU\'RE HERE');
  static String get aiCheckedFindings => getTranslatedString('aiCheckedFindings', 'AI checked all findings');

  static String get stepIndicator => getTranslatedString('stepIndicator', 'Step %1 of 3');
  static String stepIndicatorFor(int oneBased) =>
      stepIndicator.replaceFirst('%1', oneBased.toString());

  static String get backToVisits => getTranslatedString('backToVisits', 'Back to visits');
  static String get discardConfirmTitle => getTranslatedString('discardConfirmTitle', 'Leave this visit?');
  static String get discardConfirm => getTranslatedString('discardConfirm', 'The symptoms, programmes and form entries on this visit will be discarded. You will start fresh next time.');
  static String get discardCancel => getTranslatedString('discardCancel', 'Stay on this visit');
  static String get discardConfirmCta => getTranslatedString('discardConfirmCta', 'Yes, leave');
  static String get referralBadge => getTranslatedString('VisitFlow.referralBadge', 'Referred');
  static String get followUpLabel => getTranslatedString('VisitFlow.followUpLabel', 'Follow-up');
  static String get followUpAutoScheduledNote => getTranslatedString('VisitFlow.followUpAutoScheduledNote', 'Auto-scheduled · already saved');

  // ── Referral banner (Step 3) — raw API/legacy reason code → display label.
  // Map keys themselves (Spice ReferredReason / ANC LABEL_* / camelCase) are
  // never translated — only the mapped display value is user-facing.
  static String get reasonHighRiskPregnantWoman => getTranslatedString('VisitFlow.reasonHighRiskPregnantWoman', 'High-risk pregnant woman');
  static String get reasonGapsInAntenatalCare => getTranslatedString('VisitFlow.reasonGapsInAntenatalCare', 'Gaps in antenatal care');
  static String get reasonHighRiskMother => getTranslatedString('VisitFlow.reasonHighRiskMother', 'High-risk mother');
  static String get reasonGapsInPnc => getTranslatedString('VisitFlow.reasonGapsInPnc', 'Gaps in postnatal care');
  static String get reasonChildIllnessReferral => getTranslatedString('VisitFlow.reasonChildIllnessReferral', 'Child illness referral');
  static String get reasonHighBloodPressure => getTranslatedString('VisitFlow.reasonHighBloodPressure', 'High blood pressure');
  static String get reasonHighBloodGlucose => getTranslatedString('VisitFlow.reasonHighBloodGlucose', 'High blood glucose');
  static String get reasonReportedSymptoms => getTranslatedString('VisitFlow.reasonReportedSymptoms', 'Reported symptoms');
  static String get reasonLowHaemoglobin => getTranslatedString('VisitFlow.reasonLowHaemoglobin', 'Low haemoglobin');
  static String get reasonAbnormalWeight => getTranslatedString('VisitFlow.reasonAbnormalWeight', 'Abnormal weight');
  static String get reasonUrineProteinDetected => getTranslatedString('VisitFlow.reasonUrineProteinDetected', 'Urine protein detected');
  static String get reasonDangerSignsPresent => getTranslatedString('VisitFlow.reasonDangerSignsPresent', 'Danger signs present');
  static String get reasonAbnormalBmi => getTranslatedString('VisitFlow.reasonAbnormalBmi', 'Abnormal BMI');
  static String get reasonGestationalAgeConcern => getTranslatedString('VisitFlow.reasonGestationalAgeConcern', 'Gestational age concern');

  /// Localises Spice visit suffixes (`ANC Visit 2`, `PNC Visit 1`) on Step 3.
  static String ancVisitLabel([Object? visitNo]) {
    final n = visitNo?.toString().trim();
    if (n == null || n.isEmpty) {
      return getTranslatedString('VisitFlow.ancVisitLabel', 'ANC Visit');
    }
    return getTranslatedString(
      'VisitFlow.ancVisitWithNo',
      'ANC Visit $n',
      params: {'n': n},
    );
  }

  static String pncVisitLabel([Object? visitNo]) {
    final n = visitNo?.toString().trim();
    if (n == null || n.isEmpty) {
      return getTranslatedString('VisitFlow.pncVisitLabel', 'PNC Visit');
    }
    return getTranslatedString(
      'VisitFlow.pncVisitWithNo',
      'PNC Visit $n',
      params: {'n': n},
    );
  }

  // Referred-card title — bare form reuses [referralBadge] (same English text).
  static String referredTitleFor(String finding) => getTranslatedString(
        'VisitFlow.referredTitleFor',
        'Referred — $finding',
        params: {'finding': finding},
      );
  static String get referralRecommendedFallback => getTranslatedString('VisitFlow.referralRecommendedFallback', 'Referral recommended');

  // ── Rule-based referral recommendation (offline / AI-unavailable fallback) ──
  static String get referralDestinationUpazilaHealthComplex => getTranslatedString('VisitFlow.referralDestinationUpazilaHealthComplex', 'Upazila Health Complex');
  static String get referralReasonClinicalAssessment => getTranslatedString('VisitFlow.referralReasonClinicalAssessment', 'Referral recommended based on clinical assessment');

  // ── Household member strip (Step 3) — programme → visit-label pill ─────────
  static String get visitLabelAnc => getTranslatedString('VisitFlow.visitLabelAnc', 'ANC visit');
  static String get visitLabelPncDue => getTranslatedString('VisitFlow.visitLabelPncDue', 'PNC due');
  static String get visitLabelChildVisit => getTranslatedString('VisitFlow.visitLabelChildVisit', 'Child visit');
  static String get visitLabelBpCheck => getTranslatedString('VisitFlow.visitLabelBpCheck', 'BP check');
  static String get visitLabelTbCheck => getTranslatedString('VisitFlow.visitLabelTbCheck', 'TB check');
  static String get visitLabelVaccines => getTranslatedString('VisitFlow.visitLabelVaccines', 'Vaccines');
  static String get visitLabelNutrition => getTranslatedString('VisitFlow.visitLabelNutrition', 'Nutrition');
  static String get visitLabelScheduled => getTranslatedString('VisitFlow.visitLabelScheduled', 'Scheduled');
  static String get viewingLabel => getTranslatedString('VisitFlow.viewingLabel', 'Viewing');

  // ── AI Counselling Guide (WhatsApp preview) recipient line ──────────────────
  static String recipientLineFor(String patientLabel, String? patientPhone) => patientPhone != null
      ? getTranslatedString(
          'VisitFlow.recipientLineWithPhone',
          'To: $patientLabel · $patientPhone',
          params: {'label': patientLabel, 'phone': patientPhone},
        )
      : getTranslatedString(
          'VisitFlow.recipientLine',
          'To: $patientLabel',
          params: {'label': patientLabel},
        );

  // ── Rule-based (offline / AI-unavailable) Step 3 content generator ─────────
  // `_ruleBasedNaba()` / `_ruleBasedWhatsAppMessage()` in `visit_flow_screen.dart`
  // — only rendered when the AI recommendation service cannot be reached.

  // Visit-summary title, by primary programme.
  static String get summaryTitleAnc => getTranslatedString('VisitFlow.summaryTitleAnc', 'ANC Visit — Guideline Care Plan');
  static String get summaryTitlePnc => getTranslatedString('VisitFlow.summaryTitlePnc', 'PNC Visit — Guideline Care Plan');
  static String get summaryTitleNcd => getTranslatedString('VisitFlow.summaryTitleNcd', 'NCD Visit — Guideline Care Plan');
  static String get summaryTitleImci => getTranslatedString('VisitFlow.summaryTitleImci', 'Child Health Visit — Guideline Care Plan');
  static String get summaryTitleTb => getTranslatedString('VisitFlow.summaryTitleTb', 'TB Follow-up — Guideline Care Plan');
  static String get summaryTitleDefault => getTranslatedString('VisitFlow.summaryTitleDefault', 'Visit — Guideline Care Plan');

  // Visit-summary body, for programmes without a dedicated vitals summary.
  static String get summaryBodyPnc => getTranslatedString('VisitFlow.summaryBodyPnc', 'Mother and neonate assessed — lochia, cord, and breastfeeding. Continuing post-natal care.');
  static String get summaryBodyImci => getTranslatedString('VisitFlow.summaryBodyImci', 'Child assessed for fever, respiratory rate, and hydration. IMCI classification applied.');
  static String get summaryBodyTb => getTranslatedString('VisitFlow.summaryBodyTb', 'TB treatment adherence reviewed. Continuing directly observed therapy (DOT).');
  static String get summaryBodyDefault => getTranslatedString('VisitFlow.summaryBodyDefault', 'Vital signs assessed. Routine care plan generated per clinical guidelines.');

  // ANC vitals summary.
  static String get ancVitalsNoData => getTranslatedString('VisitFlow.ancVitalsNoData', 'BP, weight, urine protein, and fetal movement assessed. Continuing routine ANC care per WHO guidelines.');
  static String bpPartFor(int sys, int dia) => getTranslatedString(
        'VisitFlow.bpPartFor',
        'BP $sys/$dia mmHg',
        params: {'sys': '$sys', 'dia': '$dia'},
      );
  static String get bpAssessedFallback => getTranslatedString('VisitFlow.bpAssessedFallback', 'BP assessed');
  static String weightPartFor(String weight) => getTranslatedString(
        'VisitFlow.weightPartFor',
        ', weight $weight kg',
        params: {'weight': weight},
      );
  static String get _hbLowSuffix => getTranslatedString('VisitFlow.hbLowSuffix', ' — low');
  static String hbPartFor(String value, bool abnormal) => getTranslatedString(
        'VisitFlow.hbPartFor',
        ', Hb $value g/dL${abnormal ? " — low" : ""}',
        params: {'value': value, 'suffix': abnormal ? _hbLowSuffix : ''},
      );
  static String get ancStatusHigh => getTranslatedString('VisitFlow.ancStatusHigh', 'BP elevated — monitor for pre-eclampsia.');
  static String get ancStatusNormal => getTranslatedString('VisitFlow.ancStatusNormal', 'Vitals within expected range.');

  // NCD vitals summary.
  static String get ncdVitalsNoData => getTranslatedString('VisitFlow.ncdVitalsNoData', 'Blood pressure and blood glucose reviewed. Continuing NCD management per Bangladesh guidelines.');
  static String bpAvgPartFor(int sys, int dia) => getTranslatedString(
        'VisitFlow.bpAvgPartFor',
        'BP avg $sys/$dia mmHg',
        params: {'sys': '$sys', 'dia': '$dia'},
      );
  static String get _glucoseElevatedSuffix => getTranslatedString('VisitFlow.glucoseElevatedSuffix', ' — elevated');
  static String glucosePartFor(String value, String unit, bool abnormal) => getTranslatedString(
        'VisitFlow.glucosePartFor',
        ', glucose $value $unit${abnormal ? " — elevated" : ""}',
        params: {'value': value, 'unit': unit, 'suffix': abnormal ? _glucoseElevatedSuffix : ''},
      );
  static String get ncdStatusHigh => getTranslatedString('VisitFlow.ncdStatusHigh', 'BP above target — review medication and refer if persistent.');
  static String get ncdStatusNormal => getTranslatedString('VisitFlow.ncdStatusNormal', 'BP within controlled range.');

  // Shared follow-up timelines (reused across programmes with identical text).
  static String get followUpTimelineFourWeeks => getTranslatedString('VisitFlow.followUpTimelineFourWeeks', 'In 4 weeks');
  static String get followUpTimelineTwoWeeks => getTranslatedString('VisitFlow.followUpTimelineTwoWeeks', 'In 2 weeks');
  static String get followUpTimelineSevenDays => getTranslatedString('VisitFlow.followUpTimelineSevenDays', 'In 7 days');
  static String get followUpTimelineTwoDays => getTranslatedString('VisitFlow.followUpTimelineTwoDays', 'In 2 days');
  static String get followUpTimelineRoutine => getTranslatedString('VisitFlow.followUpTimelineRoutine', 'Routine');

  // ANC next actions / counselling / follow-up.
  static String get ancActionNearTerm => getTranslatedString('VisitFlow.ancActionNearTerm', 'Patient is at or near term (≥36 weeks). Advise to go to facility immediately if labour starts.');
  static String get ancAction1 => getTranslatedString('VisitFlow.ancAction1', 'Measure blood pressure, weight, and fundal height');
  static String get ancAction2 => getTranslatedString('VisitFlow.ancAction2', 'Check for danger signs: heavy bleeding, severe headache, blurred vision, convulsions, no fetal movement');
  static String get ancAction3 => getTranslatedString('VisitFlow.ancAction3', 'Confirm iron-folic acid supply for next 4 weeks');
  static String get ancAction4 => getTranslatedString('VisitFlow.ancAction4', 'Schedule next ANC visit in 4 weeks');
  static String get ancCounselling1 => getTranslatedString('VisitFlow.ancCounselling1', 'Take iron-folic acid tablet every day, even when feeling well');
  static String get ancCounselling2 => getTranslatedString('VisitFlow.ancCounselling2', 'Eat nutritious food: green vegetables, lentils, fish, eggs');
  static String get ancCounselling3 => getTranslatedString('VisitFlow.ancCounselling3', 'Sleep under a bednet every night');
  static String get ancCounselling4 => getTranslatedString('VisitFlow.ancCounselling4', 'Plan delivery with a skilled attendant at a health facility');
  static String get ancCounselling5 => getTranslatedString('VisitFlow.ancCounselling5', 'Go to facility immediately if any danger sign occurs');
  static String get ancFollowUpActivity => getTranslatedString('VisitFlow.ancFollowUpActivity', 'ANC visit — BP, weight, fundal height, fetal position');

  // NCD next actions / counselling / follow-up.
  static String get ncdAction1 => getTranslatedString('VisitFlow.ncdAction1', 'Measure blood pressure in both arms');
  static String get ncdAction2 => getTranslatedString('VisitFlow.ncdAction2', 'Check fasting blood glucose if patient has diabetes');
  static String get ncdAction3 => getTranslatedString('VisitFlow.ncdAction3', 'Verify medication supply — patient must not run out');
  static String get ncdAction4 => getTranslatedString('VisitFlow.ncdAction4', 'Counsel on lifestyle: salt reduction, daily walking, no tobacco');
  static String get ncdCounselling1 => getTranslatedString('VisitFlow.ncdCounselling1', 'Take all prescribed medications every day without skipping');
  static String get ncdCounselling2 => getTranslatedString('VisitFlow.ncdCounselling2', 'Reduce salt in cooking — avoid processed and salty foods');
  static String get ncdCounselling3 => getTranslatedString('VisitFlow.ncdCounselling3', 'Walk at least 30 minutes every day');
  static String get ncdCounselling4 => getTranslatedString('VisitFlow.ncdCounselling4', 'Avoid tobacco and alcohol');
  static String get ncdCounselling5 => getTranslatedString('VisitFlow.ncdCounselling5', 'Return immediately for one-sided weakness, sudden severe headache, or chest pain');
  static String get ncdFollowUpActivity => getTranslatedString('VisitFlow.ncdFollowUpActivity', 'BP and glucose re-check');

  // PNC next actions / counselling / follow-up.
  static String get pncAction1 => getTranslatedString('VisitFlow.pncAction1', "Check mother's BP and temperature; assess lochia and wound healing");
  static String get pncAction2 => getTranslatedString('VisitFlow.pncAction2', 'Weigh neonate; check cord stump; observe breastfeeding latch');
  static String get pncAction3 => getTranslatedString('VisitFlow.pncAction3', 'Confirm vitamin A given to mother within 8 weeks of delivery');
  static String get pncAction4 => getTranslatedString('VisitFlow.pncAction4', 'Counsel on family planning options');
  static String get pncCounselling1 => getTranslatedString('VisitFlow.pncCounselling1', 'Breastfeed exclusively for 6 months — no water, no other food');
  static String get pncCounselling2 => getTranslatedString('VisitFlow.pncCounselling2', 'Keep baby warm and cord stump clean and dry');
  static String get pncCounselling3 => getTranslatedString('VisitFlow.pncCounselling3', 'Eat nutritious food to support breast milk production');
  static String get pncCounselling4 => getTranslatedString('VisitFlow.pncCounselling4', 'Seek care immediately for heavy bleeding, fever, foul-smelling discharge, or baby not feeding');
  static String get pncFollowUpActivity => getTranslatedString('VisitFlow.pncFollowUpActivity', 'PNC follow-up — mother and neonate');

  // IMCI next actions / counselling / follow-up.
  static String get imciAction1 => getTranslatedString('VisitFlow.imciAction1', 'Measure temperature and respiratory rate; assess hydration status');
  static String get imciAction2 => getTranslatedString('VisitFlow.imciAction2', 'Classify illness per IMCI chart; prescribe ORS and zinc if diarrhoea');
  static String get imciAction3 => getTranslatedString('VisitFlow.imciAction3', 'Check for danger signs: not able to drink, persistent vomiting, convulsions, very sleepy');
  static String get imciCounselling1 => getTranslatedString('VisitFlow.imciCounselling1', 'Continue breastfeeding or usual feeding during illness');
  static String get imciCounselling2 => getTranslatedString('VisitFlow.imciCounselling2', 'Give ORS frequently if child has diarrhoea');
  static String get imciCounselling3 => getTranslatedString('VisitFlow.imciCounselling3', 'Complete full zinc course (10 days) for diarrhoea');
  static String get imciCounselling4 => getTranslatedString('VisitFlow.imciCounselling4', 'Return immediately if child is not improving or has a danger sign');
  static String get imciFollowUpActivity => getTranslatedString('VisitFlow.imciFollowUpActivity', 'Follow-up sick child visit');

  // TB next actions / counselling / follow-up.
  static String get tbAction1 => getTranslatedString('VisitFlow.tbAction1', 'Confirm TB treatment adherence — check pill count and any side effects');
  static String get tbAction2 => getTranslatedString('VisitFlow.tbAction2', 'Counsel on infection control: cough hygiene, ventilation, mask use');
  static String get tbCounselling1 => getTranslatedString('VisitFlow.tbCounselling1', 'Take TB medicines every day without stopping — stopping leads to drug resistance');
  static String get tbCounselling2 => getTranslatedString('VisitFlow.tbCounselling2', 'Cover mouth when coughing; keep rooms well-ventilated');
  static String get tbCounselling3 => getTranslatedString('VisitFlow.tbCounselling3', 'All household contacts should be screened for TB symptoms');
  static String get tbFollowUpActivity => getTranslatedString('VisitFlow.tbFollowUpActivity', 'TB treatment adherence check');

  // No confirmed programme — generic fallback next-action/counselling/follow-up.
  static String get noActionsFallback => getTranslatedString('VisitFlow.noActionsFallback', 'Record vital signs and complete routine clinical assessment');
  static String get noActionsCounselling => getTranslatedString('VisitFlow.noActionsCounselling', 'Follow up as scheduled and contact the health worker if symptoms worsen');
  static String get noActionsFollowUpActivity => getTranslatedString('VisitFlow.noActionsFollowUpActivity', 'Routine follow-up visit');

  // ── Rule-based WhatsApp follow-up message (offline / AI-unavailable) ───────
  static String get whatsappGreeting => getTranslatedString('VisitFlow.whatsappGreeting', 'Hello! Your health worker visited you today.');
  static String get whatsappRemindersHeader => getTranslatedString('VisitFlow.whatsappRemindersHeader', 'Reminders:');
  static String get whatsappClosing => getTranslatedString('VisitFlow.whatsappClosing', 'Contact your health worker if your condition worsens.');
  static String get whatsappReferralWarning => getTranslatedString('VisitFlow.whatsappReferralWarning', '⚠️ *Please go to the Upazila Health Complex today for further care.*');

  static String get whatsappAncHeader => getTranslatedString('VisitFlow.whatsappAncHeader', '*Pregnancy (ANC) visit completed.*');
  static String whatsappAncGestationalAge(int gw) => getTranslatedString(
        'VisitFlow.whatsappAncGestationalAge',
        'Gestational age: $gw weeks.',
        params: {'gw': '$gw'},
      );
  static String get whatsappAncBullet1 => getTranslatedString('VisitFlow.whatsappAncBullet1', '• Take iron-folic acid every day');
  static String get whatsappAncBullet2 => getTranslatedString('VisitFlow.whatsappAncBullet2', '• Eat well: vegetables, fish, eggs, lentils');
  static String get whatsappAncBullet3 => getTranslatedString('VisitFlow.whatsappAncBullet3', '• Sleep under a bednet every night');
  static String get whatsappAncBullet4 => getTranslatedString('VisitFlow.whatsappAncBullet4', '• Plan delivery at a health facility');
  static String get whatsappAncBullet5 => getTranslatedString('VisitFlow.whatsappAncBullet5', '• Go to facility immediately for: heavy bleeding, severe headache, blurred vision, no fetal movement, swollen hands/feet');
  static String get whatsappAncNextVisit => getTranslatedString('VisitFlow.whatsappAncNextVisit', '*Next ANC visit: in 4 weeks.*');

  static String get whatsappNcdHeader => getTranslatedString('VisitFlow.whatsappNcdHeader', '*BP/Diabetes (NCD) visit completed.*');
  static String get whatsappNcdBullet1 => getTranslatedString('VisitFlow.whatsappNcdBullet1', '• Take all medicines every day — never skip');
  static String get whatsappNcdBullet2 => getTranslatedString('VisitFlow.whatsappNcdBullet2', '• Reduce salt; avoid processed food');
  static String get whatsappNcdBullet3 => getTranslatedString('VisitFlow.whatsappNcdBullet3', '• Walk 30 minutes daily');
  static String get whatsappNcdBullet4 => getTranslatedString('VisitFlow.whatsappNcdBullet4', '• Avoid tobacco and alcohol');
  static String get whatsappNcdBullet5 => getTranslatedString('VisitFlow.whatsappNcdBullet5', '• Go to facility immediately for: one-sided weakness, sudden severe headache, or chest pain');
  static String get whatsappNcdNextVisit => getTranslatedString('VisitFlow.whatsappNcdNextVisit', '*Next visit: in 2 weeks.*');

  static String get whatsappPncHeader => getTranslatedString('VisitFlow.whatsappPncHeader', '*Post-natal care (PNC) visit completed.*');
  static String get whatsappPncBullet1 => getTranslatedString('VisitFlow.whatsappPncBullet1', '• Breastfeed exclusively for 6 months — no water or other food');
  static String get whatsappPncBullet2 => getTranslatedString('VisitFlow.whatsappPncBullet2', '• Keep baby warm; keep cord stump clean and dry');
  static String get whatsappPncBullet3 => getTranslatedString('VisitFlow.whatsappPncBullet3', '• Eat well to support breast milk');
  static String get whatsappPncBullet4 => getTranslatedString('VisitFlow.whatsappPncBullet4', '• Seek care immediately for: heavy bleeding, fever, foul discharge, or baby not feeding');
  static String get whatsappPncNextVisit => getTranslatedString('VisitFlow.whatsappPncNextVisit', '*Next PNC visit: in 7 days.*');

  static String get whatsappImciHeader => getTranslatedString('VisitFlow.whatsappImciHeader', '*Child health (IMCI) visit completed.*');
  static String get whatsappImciBullet1 => getTranslatedString('VisitFlow.whatsappImciBullet1', '• Continue feeding normally during illness');
  static String get whatsappImciBullet2 => getTranslatedString('VisitFlow.whatsappImciBullet2', '• Give ORS often if child has diarrhoea');
  static String get whatsappImciBullet3 => getTranslatedString('VisitFlow.whatsappImciBullet3', '• Return immediately if child cannot drink, has convulsions, or is very sleepy');
  static String get whatsappImciNextVisit => getTranslatedString('VisitFlow.whatsappImciNextVisit', '*Follow-up visit: in 2 days.*');

  static String get whatsappTbHeader => getTranslatedString('VisitFlow.whatsappTbHeader', '*TB treatment follow-up visit completed.*');
  static String get whatsappTbBullet1 => getTranslatedString('VisitFlow.whatsappTbBullet1', '• Take TB medicines every day — stopping causes drug resistance');
  static String get whatsappTbBullet2 => getTranslatedString('VisitFlow.whatsappTbBullet2', '• Cover mouth when coughing; keep rooms ventilated');
  static String get whatsappTbBullet3 => getTranslatedString('VisitFlow.whatsappTbBullet3', '• All household members should be screened for TB');
  static String get whatsappTbNextCheck => getTranslatedString('VisitFlow.whatsappTbNextCheck', '*Next TB check: in 2 weeks.*');

  static String get whatsappRoutineHeader => getTranslatedString('VisitFlow.whatsappRoutineHeader', '*Routine health visit completed.*');
  static String get whatsappRoutineBody => getTranslatedString('VisitFlow.whatsappRoutineBody', 'Continue your medications and attend your next scheduled visit.');
  static String get whatsappRoutineNextVisit => getTranslatedString('VisitFlow.whatsappRoutineNextVisit', '*Next visit: in 4 weeks.*');
}

/// Strings for the AI Next Best Action (NABA) Step 3 screen.
abstract final class NabaStrings {
  NabaStrings._();

  static String get loadingTitle => getTranslatedString('Naba.loadingTitle', 'Generating care plan…');
  static String get loadingSubtitle => getTranslatedString('Naba.loadingSubtitle', 'AI is reviewing the assessment. This takes a few seconds.');

  static String get errorTitle => getTranslatedString('errorTitle', 'Could not generate care plan');
  static String get errorSubtitle => getTranslatedString('errorSubtitle', 'The assessment has been saved. Tap Retry to try again, or continue without AI recommendations.');
  static String get retryButton => getTranslatedString('Naba.retryButton', 'Retry');
  static String get skipButton => getTranslatedString('Naba.skipButton', 'Skip — go to home');

  static String get sectionDangerSigns => getTranslatedString('sectionDangerSigns', 'Danger signs to watch for');
  static String get sectionFindings => getTranslatedString('sectionFindings', 'Clinical findings');
  static String get sectionNextActions => getTranslatedString('sectionNextActions', 'Next actions');
  static String get sectionCounselling => getTranslatedString('sectionCounselling', 'Counselling points');
  static String get sectionMedication => getTranslatedString('sectionMedication', 'Medication advice');
  static String get sectionFollowUp => getTranslatedString('sectionFollowUp', 'Follow-up schedule');
  static String get sectionReferral => getTranslatedString('sectionReferral', 'Referral recommendation');
  static String get sectionWhatsApp => getTranslatedString('sectionWhatsApp', 'WhatsApp counselling (Bangla)');
  static String get sectionRationale => getTranslatedString('sectionRationale', 'AI rationale');

  static String get humanReviewBadge => getTranslatedString('humanReviewBadge', 'Human review recommended');
  static String get highConfidence => getTranslatedString('highConfidence', 'High confidence');
  static String get referralRequired => getTranslatedString('referralRequired', 'Referral required');
  static String get referralNotRequired => getTranslatedString('referralNotRequired', 'No referral needed');

  static String get urgencyNow => getTranslatedString('Naba.urgencyNow', 'NOW');
  static String get urgencyToday => getTranslatedString('Naba.urgencyToday', 'TODAY');
  static String get urgencyThisWeek => getTranslatedString('Naba.urgencyThisWeek', 'THIS WEEK');
  static String get urgencyRoutine => getTranslatedString('Naba.urgencyRoutine', 'ROUTINE');

  static String get severityHigh => getTranslatedString('severityHigh', 'High');
  static String get severityMedium => getTranslatedString('severityMedium', 'Medium');
  static String get severityLow => getTranslatedString('severityLow', 'Low');

  static String get copyWhatsApp => getTranslatedString('copyWhatsApp', 'Copy');
  static String get whatsAppCopied => getTranslatedString('whatsAppCopied', 'Copied!');
  static String get sendViaSms => getTranslatedString('sendViaSms', 'Send via SMS');
  static String get sendViaWhatsApp => getTranslatedString('sendViaWhatsApp', 'Send via WhatsApp');
  static String get sendThisMessage => getTranslatedString('sendThisMessage', 'Send this message');
  static String get aiCounsellingGuide => getTranslatedString('aiCounsellingGuide', 'AI Counselling Guide');
  static String get whatsAppNotInstalled => getTranslatedString('Naba.whatsAppNotInstalled', 'WhatsApp is not installed on this device.');
  static String get smsNotAvailable => getTranslatedString('Naba.smsNotAvailable', 'SMS is not available on this device.');

  static String get acceptProposal => getTranslatedString('acceptProposal', 'Save & Go Home');
  static String get proposalNote => getTranslatedString('proposalNote', 'This is an AI proposal. Review and accept to proceed.');

  static String get callDoctorNow => getTranslatedString('callDoctorNow', 'Call a doctor now');
  static String get callDoctorNowBn => getTranslatedString('Naba.callDoctorNowBn', 'ডাক্তারকে ফোন করন');
  static String get callDoctorOfflineHint => getTranslatedString('callDoctorOfflineHint', 'Available when online');

  static String get fallbackNotice => getTranslatedString('fallbackNotice', 'AI service was unavailable. Care plan is based on clinical guidelines. Review and adjust based on your assessment.');
}

/// Teleconsult placeholder screen strings.
/// Used by [TeleconsultScreen].
abstract final class TeleconsultStrings {
  TeleconsultStrings._();

  static String get title => getTranslatedString('Teleconsult.title', 'Teleconsult');
  static String get comingSoon => getTranslatedString('Teleconsult.comingSoon', 'Coming soon');
  static String get placeholder => getTranslatedString('placeholder', 'Video consultation with a doctor will be available here.\nThe SK can initiate a call directly from a completed visit.');
  static String get callAction => getTranslatedString('callAction', 'Start Video Call');
  static String get smsAction => getTranslatedString('smsAction', 'Send SMS to Doctor');
  static String get doneButton => getTranslatedString('Teleconsult.doneButton', 'Done');
}

/// Counselling messages placeholder screen strings.
/// Used by [CounsellingScreen].
abstract final class CounsellingStrings {
  CounsellingStrings._();

  static String get title => getTranslatedString('Counselling.title', 'Counselling Messages');
  static String get subtitle => getTranslatedString('Counselling.subtitle', 'AI-generated health counselling');
  static String get sendWhatsApp => getTranslatedString('sendWhatsApp', 'Send via WhatsApp');
  static String get sendSms => getTranslatedString('sendSms', 'Send via SMS');
  static String get copyMessage => getTranslatedString('copyMessage', 'Copy message');
  static String get noMessage => getTranslatedString('noMessage', 'No counselling message generated for this visit.');
  static String get whatsAppNotInstalled => getTranslatedString('Counselling.whatsAppNotInstalled', 'WhatsApp is not installed on this device.');
  static String get smsNotAvailable => getTranslatedString('Counselling.smsNotAvailable', 'SMS is not available on this device.');
}

/// Training Hub placeholder screen strings.
/// Used by [TrainingScreen].
abstract final class TrainingStrings {
  TrainingStrings._();

  static String get title => getTranslatedString('Training.title', 'Training Hub');
  static String get subtitle => getTranslatedString('Training.subtitle', 'Short videos · Learn at your own pace');
  static String get comingSoon => getTranslatedString('Training.comingSoon', 'Coming soon');
  static String get certificatesTitle => getTranslatedString('certificatesTitle', 'Certificates');
  static String get certificatesSubtitle => getTranslatedString('certificatesSubtitle', 'Complete modules to earn programme certificates');

  // Leaderboard
  static String get leaderboardTitle => getTranslatedString('leaderboardTitle', '🏆 Top SKs this month');
  static String get leaderboardYou => getTranslatedString('leaderboardYou', '(You)');
  static String get leaderboardMotivationPrefix => getTranslatedString('leaderboardMotivationPrefix', '⚡ ');
  static String get leaderboardMotivationSuffix => getTranslatedString('leaderboardMotivationSuffix', ' pts away from 1st place · Watch 3 more videos to catch up!');

  // Section labels
  static String get sectionTodaysLessons => getTranslatedString('sectionTodaysLessons', 'TODAY\'S LESSONS — BASED ON YOUR VISITS');
  static String get sectionMonthlyProgress => getTranslatedString('sectionMonthlyProgress', 'Your progress this month');

  // Video states
  static String get badgeNowPlaying => getTranslatedString('badgeNowPlaying', 'NOW PLAYING');
  static String get badgeCompleted => getTranslatedString('Training.badgeCompleted', '✓ COMPLETED');
  static String get badgeLocked => getTranslatedString('badgeLocked', '🔒 LOCKED');

  // Pill badges
  static String pillTriggered(String reason) => getTranslatedString('pillTriggered', 'New · Triggered by {reason}', params: {'reason': '$reason'});
  static String pillDonePoints(int pts) => getTranslatedString('pillDonePoints', 'Done · +{pts} pts', params: {'pts': '$pts'});
  static String get pillNew => getTranslatedString('pillNew', 'New');
  static String pillUnlockAfter(int n) => getTranslatedString('pillUnlockAfter', 'Complete {n} more to unlock', params: {'n': '$n'});
  static String get pillLocked => getTranslatedString('pillLocked', 'Locked');

  // Monthly stats
  static String get statVideos => getTranslatedString('statVideos', 'Videos watched');
  static String get statPoints => getTranslatedString('statPoints', 'Points earned');
  static String get statStreak => getTranslatedString('statStreak', 'Day streak 🔥');

  // Locked snackbar
  static String get lockedSnackbar => getTranslatedString('lockedSnackbar', 'Complete earlier lessons to unlock this one');

  // SDK-matching strings
  static String get personalisedCoaching => getTranslatedString('personalisedCoaching', 'Personalised Coaching');
  static String get lastSynced => getTranslatedString('lastSynced', 'Last synced');
  static String get tabCoaching => getTranslatedString('tabCoaching', 'Coaching');
  static String get tabLeaderboard => getTranslatedString('tabLeaderboard', 'Leaderboard');
  static String get morningCardMicrocoaching => getTranslatedString('morningCardMicrocoaching', 'MICRO-COACHING');
  static String get morningCardTapToAnswer => getTranslatedString('morningCardTapToAnswer', 'Tap to answer');
  static String get refreshersSection => getTranslatedString('refreshersSection', 'Refreshers');
  static String get noRefreshersYet => getTranslatedString('noRefreshersYet', 'No refreshers yet.');
  static String get trainingSection => getTranslatedString('trainingSection', 'Training');
  static String get seeAll => getTranslatedString('Training.seeAll', 'See all');
  static String get allModulesTitle => getTranslatedString('Training.allModulesTitle', 'All Modules');
  static String get leaderboardFilterAllTime => getTranslatedString('leaderboardFilterAllTime', 'All Time');
  static String get leaderboardFilterThisMonth => getTranslatedString('leaderboardFilterThisMonth', 'This Month');
  static String get leaderboardFilterThisWeek => getTranslatedString('leaderboardFilterThisWeek', 'This Week');
  static String get leaderboardContext => getTranslatedString('leaderboardContext', 'Dhamrai Upazila · 28 SKs');
  static String get leaderboardUpdated => getTranslatedString('leaderboardUpdated', 'Updated');
  static String get xpSuffix => getTranslatedString('xpSuffix', 'XP');
  static String get streakDaySuffix => getTranslatedString('streakDaySuffix', 'd');
  static String get youLabel => getTranslatedString('youLabel', 'You');
  static String get loadFailedGeneric => getTranslatedString('Training.loadFailedGeneric', 'Something went wrong loading this content.');
}

/// Micro-coaching pilot strings — three-loop system:
/// Learn (morning cards + quiz) → Apply (visit-triggered) → Measure (telemetry).
abstract final class CoachingStrings {
  CoachingStrings._();

  static String get sectionTodayFocus => getTranslatedString('sectionTodayFocus', 'TODAY\'S FOCUS');
  static String get sectionAllModules => getTranslatedString('sectionAllModules', 'ALL MODULES');
  static String get minLabel => getTranslatedString('minLabel', 'min');
  static String get passedLabel => getTranslatedString('passedLabel', 'Passed');
  static String get startLabel => getTranslatedString('startLabel', 'Start');
  static String get reviewLabel => getTranslatedString('reviewLabel', 'Review');
  static String get cardOf => getTranslatedString('cardOf', 'of');
  static String get nextCard => getTranslatedString('nextCard', 'Next');
  static String get prevCard => getTranslatedString('prevCard', 'Back');
  static String get startQuiz => getTranslatedString('startQuiz', 'Take Quiz');
  static String get quizTitle => getTranslatedString('quizTitle', 'Quick Quiz');
  static String get questionOf => getTranslatedString('questionOf', 'Question');
  static String get checkAnswer => getTranslatedString('checkAnswer', 'Check Answer');
  static String get nextQuestion => getTranslatedString('nextQuestion', 'Next');
  static String get quizResult => getTranslatedString('quizResult', 'Quiz Complete');
  static String get quizPassed => getTranslatedString('quizPassed', 'You passed!');
  static String get quizFailed => getTranslatedString('quizFailed', 'Not quite — review the module and try again.');
  static String get tryAgain => getTranslatedString('tryAgain', 'Try Again');
  static String get backToModules => getTranslatedString('backToModules', 'Back to Training');
  static String get quizNotReady => getTranslatedString('quizNotReady', 'Quiz not available yet');
  static String get quizNotReadySub => getTranslatedString('quizNotReadySub', 'Questions for this module are being prepared. Complete the lesson cards and check back later.');
  static String get rationaleLabel => getTranslatedString('rationaleLabel', 'Why?');
  static String get domainAnc => getTranslatedString('domainAnc', 'ANC');
  static String get domainNcd => getTranslatedString('domainNcd', 'NCD');
  static String get domainImci => getTranslatedString('domainImci', 'IMCI');
  static String get domainTb => getTranslatedString('domainTb', 'TB');
  static String get domainEpi => getTranslatedString('domainEpi', 'EPI');
  static String get domainNutrition => getTranslatedString('domainNutrition', 'Nutrition');

  // Module detail screen
  static String get detailCards => getTranslatedString('detailCards', 'cards');
  static String get detailQuestions => getTranslatedString('detailQuestions', 'questions');
  static String get startCourse => getTranslatedString('startCourse', 'Start Course');
  static String get doQuiz => getTranslatedString('doQuiz', 'Take Quiz');
  static String get reviewCourse => getTranslatedString('reviewCourse', 'Review');
  static String get curriculumLabel => getTranslatedString('curriculumLabel', 'CURRICULUM');
  static String get quizLabel => getTranslatedString('quizLabel', 'Quick Quiz');
  static String statMinLabel(int n) => getTranslatedString('statMinLabel', '{n} min read', params: {'n': '$n'});

  // Morning card
  static String get morningCardEyebrow => getTranslatedString('morningCardEyebrow', 'TODAY\'S FOCUS');
  static String get morningCardStart => getTranslatedString('morningCardStart', 'Start');
  static String get morningCardSkip => getTranslatedString('morningCardSkip', 'Skip');
  static String get refresherTypeMicrocoaching => getTranslatedString('refresherTypeMicrocoaching', 'Micro-coaching');
  static String get refresherTypeLearningCard => getTranslatedString('refresherTypeLearningCard', 'Learning Card');
  static String get refresherTypeQuiz => getTranslatedString('refresherTypeQuiz', 'Quiz');
  static String get sectionMorningCards => getTranslatedString('sectionMorningCards', 'TODAY\'S FOCUS — BASED ON YOUR GAPS');
  static String get lessonPlayerProgress => getTranslatedString('lessonPlayerProgress', 'Learning {i} of {n}');
  static String lessonProgress(int i, int n) => getTranslatedString('lessonProgress', 'Learning {i} of {n}', params: {'i': '$i', 'n': '$n'});

  // All modules grid
  static String get sectionAllModulesGrid => getTranslatedString('sectionAllModulesGrid', 'ALL TRAINING MODULES');

  static String quizScore(int correct, int total) => getTranslatedString('quizScore', '{correct} / {total} correct', params: {'correct': '$correct', 'total': '$total'});
  static String cardProgress(int current, int total) => getTranslatedString('cardProgress', '{current} of {total}', params: {'current': '$current', 'total': '$total'});
  static String questionProgress(int current, int total) => getTranslatedString('questionProgress', 'Question {current} of {total}', params: {'current': '$current', 'total': '$total'});

  // Module detail — locale-aware
  static String get detailLearningCardsSection => getTranslatedString('detailLearningCardsSection', 'Learning cards');
  static String get detailQuizSection => getTranslatedString('detailQuizSection', 'Quiz');
  static String get detailKnowledgeCheck => getTranslatedString('detailKnowledgeCheck', 'Knowledge check');
  static String get detailCurriculumCardMin => getTranslatedString('detailCurriculumCardMin', '1 min');
  static String get detailReadCourse => getTranslatedString('detailReadCourse', 'Read course');
  static String quizCurriculumQuestions(int n) => getTranslatedString('quizCurriculumQuestions', '{n} questions', params: {'n': '$n'});

  // Quiz question — locale-aware
  static String get quizSelectAnswer => getTranslatedString('quizSelectAnswer', 'Select an answer');
  static String quizQuestionCounter(int n, int total) => getTranslatedString('quizQuestionCounter', 'Q {n} of {total}', params: {'n': '$n', 'total': '$total'});

  // Quiz result — locale-aware
  static String get yourAnswers => getTranslatedString('yourAnswers', 'Your answers');
  static String get quizDone => getTranslatedString('quizDone', 'Done');
  static String get badgeLabelExpert => getTranslatedString('badgeLabelExpert', 'Expert');
  static String get badgeLabelWellDone => getTranslatedString('badgeLabelWellDone', 'Well Done!');
  static String get badgeLabelKeepPractising => getTranslatedString('badgeLabelKeepPractising', 'Keep Practising');
  static String badgeLabel(double score) {
    if (score >= 0.9) return badgeLabelExpert;
    if (score >= 0.7) return badgeLabelWellDone;
    return badgeLabelKeepPractising;
  }

  // Knowledge & Training Requests (mock — no API)
  static String get knowledgeSection => getTranslatedString('knowledgeSection', 'Knowledge');
  static String get trainingRequestsSection => getTranslatedString('trainingRequestsSection', 'Training Requests');
  static String get requestTrainingCta => getTranslatedString('requestTrainingCta', 'Request Training');
  static String get requestTopicHint => getTranslatedString('requestTopicHint', 'Training topic');
  static String get requestNotesHint => getTranslatedString('requestNotesHint', 'Add a note (optional)');
  static String get requestSubmit => getTranslatedString('requestSubmit', 'Submit Request');
  static String get requestSubmitted => getTranslatedString('requestSubmitted', 'Request submitted');
  static String get requestStatusPending => getTranslatedString('requestStatusPending', 'Pending');
  static String get requestStatusApproved => getTranslatedString('requestStatusApproved', 'Approved');
  static String get requestStatusRejected => getTranslatedString('requestStatusRejected', 'Rejected');
  static String get seeAll => getTranslatedString('Coaching.seeAll', 'See all');
  static String get noTrainingRequests => getTranslatedString('noTrainingRequests', 'No training requests yet.');
  static String docTypePages(int n) => getTranslatedString('docTypePages', '{n} pages', params: {'n': '$n'});
  static String get allModulesTitle => getTranslatedString('Coaching.allModulesTitle', 'All Modules');
}

/// NCD assessment form copy — spec §5.2.2 Hypertension Screening section.
///
/// Bengali secondary labels mirror the spec wording so the SK can match the
/// printed flow charts during home visits.
abstract final class NcdScreeningStrings {
  NcdScreeningStrings._();

  static String get sectionTitle => getTranslatedString('NcdScreening.sectionTitle', 'Hypertension screening');
  static String get sectionSubtitle => getTranslatedString('sectionSubtitle', 'Yes / No — strengthens AI clinical decision support.');

  // Stroke sign — band 1 short-circuit (§2.8.2).
  static String get strokeSignTitle => getTranslatedString('strokeSignTitle', 'One-sided weakness or stroke signs?');
  static String get strokeSignSubtitle => getTranslatedString('strokeSignSubtitle', 'Sudden numbness or weakness on one side — immediate emergency referral.');

  static String get morningHeadachesTitle => getTranslatedString('morningHeadachesTitle', 'Morning headaches?');

  static String get chestTightnessTitle => getTranslatedString('chestTightnessTitle', 'Chest tightness or shortness of breath?');

  static String get highSaltTitle => getTranslatedString('highSaltTitle', 'High salt in daily food?');

  static String get familyHistoryTitle => getTranslatedString('familyHistoryTitle', 'Family history of high BP?');
}

/// Visit form host screen (fallback, non-sectioned mode).
abstract final class VisitFormStrings {
  VisitFormStrings._();

  static String get saveFailed => getTranslatedString('saveFailed', 'Could not save the assessment. It is kept on this device — please try again.');
  static String get appBarTitle => getTranslatedString('VisitForm.appBarTitle', 'Visit');
  static String get sessionNotFound => getTranslatedString('VisitForm.sessionNotFound', 'Visit session not found.');
  static String get routineVisitTitle => getTranslatedString('VisitForm.routineVisitTitle', 'Routine Visit');
  static String get noPathwaysActivated => getTranslatedString('VisitForm.noPathwaysActivated', 'No assessment pathways activated.');
}

/// Unified JSON-driven form screen strings.
abstract final class UnifiedFormStrings {
  UnifiedFormStrings._();

  static String get submitLabel => getTranslatedString('submitLabel', 'Submit Assessment');
  static String get configLoadError => getTranslatedString('configLoadError', 'Form configuration could not be loaded. Please restart the app.');
  static String get noPathways => getTranslatedString('noPathways', 'No assessment pathways activated.');

  // BP reading field labels (must not be hardcoded in widget).
  static String get bpSystolicLabel => getTranslatedString('bpSystolicLabel', 'Systolic');
  static String get bpDiastolicLabel => getTranslatedString('bpDiastolicLabel', 'Diastolic');
  static String get bpPulseLabel => getTranslatedString('bpPulseLabel', 'Pulse');
  static String get bpUnit => getTranslatedString('UnifiedForm.bpUnit', 'mmHg');
  static String get bpPulseUnit => getTranslatedString('bpPulseUnit', '/min');

  // Multi-reading BP widget (Android parity — up to 3 readings).
  static String get bpAddReadingLabel => getTranslatedString('bpAddReadingLabel', '+ Add Reading');
  static String get bpReadingNumberLabel => getTranslatedString('bpReadingNumberLabel', 'Reading');
  static String get bpRemoveReadingTooltip => getTranslatedString('bpRemoveReadingTooltip', 'Remove reading');

  // Combined BP card (v13 reference — one card, side-by-side systolic|diastolic).
  static String get bpCardLabel => getTranslatedString('bpCardLabel', 'Blood Pressure');
  /// @Deprecated — kept for call-site compatibility; prefer unit-only sublabels.
  static String get bpCardSubLabel => bpUnit;

  // Supplement pair cards (consumed + provided side-by-side).
  static String get supplementConsumedLabel => getTranslatedString('supplementConsumedLabel', 'Consumed last month');
  static String get supplementProvidedLabel => getTranslatedString('supplementProvidedLabel', 'Provided this visit');
  static String get folatePairLabel => getTranslatedString('folatePairLabel', 'Folic acid tablets');
  static String get folatePairSubLabel => getTranslatedString('folatePairSubLabel', 'Folic Acid');
  static String get ifaPairLabel => getTranslatedString('ifaPairLabel', 'IFA tables');
  static String get ifaPairSubLabel => getTranslatedString('ifaPairSubLabel', 'Iron-Folic Acid');
  static String get calciumPairLabel => getTranslatedString('calciumPairLabel', 'Calcium tablets');
  static String get calciumPairSubLabel => getTranslatedString('calciumPairSubLabel', 'Calcium');

  /// Trailing tag shown on read-only computed fields (e.g. BMI, EDD, gest. week)
  /// to signal the value is auto-derived and not manually entered.
  static String get autoComputedTag => getTranslatedString('autoComputedTag', '(auto)');

  /// Placeholder shown in a computed field before its value is available.
  static String get autoComputedPlaceholder => getTranslatedString('autoComputedPlaceholder', '—');

  // Validation messages.
  static String get validationBannerTitle => getTranslatedString('validationBannerTitle', 'Please complete required fields');
  static String validationFieldsRequired(int n) => n == 1
      ? getTranslatedString('UnifiedForm.validationFieldRequiredOne',
          '{n} required field must be filled before submitting.', params: {'n': '$n'})
      : getTranslatedString('UnifiedForm.validationFieldsRequiredMany',
          '{n} required fields must be filled before submitting.', params: {'n': '$n'});

  /// Badge label shown on the programme divider when AI pre-filled symptoms
  /// for that programme from triage Step 1.
  static String get aiBadgeLabel => getTranslatedString('aiBadgeLabel', 'AI');

  // Triage symptoms carry-over banner.
  static String get triageSymptomsTitle => getTranslatedString('triageSymptomsTitle', 'Symptoms from Step 1');
  static String triageSymptomsCount(int n) => n == 1
      ? getTranslatedString(
          'UnifiedForm.triageSymptomsCountOne', '{n} symptom from Step 1', params: {'n': '$n'})
      : getTranslatedString(
          'UnifiedForm.triageSymptomsCountMany', '{n} symptoms from Step 1', params: {'n': '$n'});
  static String get triageSymptomsEmpty => getTranslatedString('triageSymptomsEmpty', 'No symptoms selected in Step 1.');

  // Section group labels shown as divider rows.
  static String get vitalsGroupLabel => getTranslatedString('vitalsGroupLabel', 'Vitals');
  static String get enrolledGroupLabel => getTranslatedString('enrolledGroupLabel', 'Enrolled Programmes');
  static String get recommendedGroupLabel => getTranslatedString('recommendedGroupLabel', 'Recommended Programmes');

  // ── Vitals-trend card ("AI sees a trend across her N visits") ──────────────
  /// Header title; [n] is the number of visits shown (priors + today).
  static String trendCardTitle(int n) => getTranslatedString('trendCardTitle', 'AI sees a trend across her {n} visits', params: {'n': '$n'});

  /// "Today" column header for the trend table.
  static String get trendTodayColumn => getTranslatedString('trendTodayColumn', 'Today');

  /// Prior-visit column header, e.g. `V1`, `V2`.
  static String trendVisitColumn(int n) => getTranslatedString('trendVisitColumn', 'V{n}', params: {'n': '$n'});

  /// Column sub-label describing how long ago a prior visit was.
  static String trendWeeksAgo(int days) {
    if (days < 7) {
      final d = days <= 1 ? 1 : days;
      return getTranslatedString('UnifiedForm.trendDaysAgo', '{d}d', params: {'d': '$d'});
    }
    final weeks = (days / 7).round();
    return getTranslatedString('UnifiedForm.trendWeeksAgo', '{weeks}wks', params: {'weeks': '$weeks'});
  }

  /// Metric row labels.
  static String get trendSystolic => getTranslatedString('trendSystolic', 'Systolic');
  static String get trendDiastolic => getTranslatedString('trendDiastolic', 'Diastolic');
  static String get trendWeight => getTranslatedString('trendWeight', 'Weight');
  static String get trendWeightGain => getTranslatedString('trendWeightGain', 'Weight gain');
  static String get trendUrineProtein => getTranslatedString('trendUrineProtein', 'Urine protein');

  /// Urine-protein grade labels used in the trend table.
  static String get trendUrineAbsent => getTranslatedString('trendUrineAbsent', 'Neg');
  static String get trendUrineTrace => getTranslatedString('trendUrineTrace', 'Trace');
  static String get trendUrinePresent => getTranslatedString('trendUrinePresent', 'Present');

  /// Placeholder for a metric not captured a given visit.
  static String get trendMissingValue => getTranslatedString('trendMissingValue', '—');

  /// Explanatory footer under the trend table — shown when BP is rising.
  static String get trendFooter => getTranslatedString('trendFooter', 'Each reading is below its alert line — but they are climbing together across visits. No single rule fires.');

  /// Footer when readings are stable (no rising BP trend detected).
  static String get trendFooterStable => getTranslatedString('trendFooterStable', 'Readings are stable across visits. No rising trend detected.');

  // ── BMI classification labels (WHO thresholds) ──────────────────────────────
  static String get vsBmiUnderweight => getTranslatedString('vsBmiUnderweight', 'Underweight');
  static String get vsBmiNormal => getTranslatedString('vsBmiNormal', 'Normal');
  static String get vsBmiOverweight => getTranslatedString('vsBmiOverweight', 'Overweight');
  static String get vsBmiObese => getTranslatedString('vsBmiObese', 'Obese');

  // ── Live vital-status badge labels (rule-based, no ML) ─────────────────────
  static String get vsBpNormal => getTranslatedString('vsBpNormal', 'Normal');
  static String get vsBpElevated => getTranslatedString('vsBpElevated', 'Elevated');
  static String get vsBpSlightlyElevated => getTranslatedString('vsBpSlightlyElevated', 'Slightly Elevated');
  static String get vsBpHigh => getTranslatedString('vsBpHigh', 'High');
  static String get vsBpSevere => getTranslatedString('vsBpSevere', 'Severe');

  static String get vsHbNormal => getTranslatedString('vsHbNormal', 'Normal');
  static String get vsHbMild => getTranslatedString('vsHbMild', 'Mild Anaemia');
  static String get vsHbModerate => getTranslatedString('vsHbModerate', 'Moderate Anaemia');
  static String get vsHbSevere => getTranslatedString('vsHbSevere', 'Severe Anaemia');
  static String get vsHbWarningShort => getTranslatedString('vsHbWarningShort', 'Anaemia');
  static String get vsHbWarningLong => getTranslatedString('vsHbWarningLong', 'Below 11 g/dL — Anaemia. Counsel on iron-rich diet and IFA adherence.');

  static String get vsUrineAbsent => getTranslatedString('vsUrineAbsent', 'Absent');
  static String get vsUrineTrace => getTranslatedString('vsUrineTrace', 'Trace');
  static String get vsUrinePresent => getTranslatedString('vsUrinePresent', 'Present');

  static String vsWeightDelta(double delta) {
    final sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)} kg';
  }

  static String vsLastWeight(double kg) => getTranslatedString(
      'UnifiedForm.vsLastWeight', 'Last: {kg} kg', params: {'kg': kg.toStringAsFixed(1)});

  static String vsFhLag(int cm) => getTranslatedString('vsFhLag', '{cm} cm lag ⚠️', params: {'cm': '$cm'});
  static String vsFhAhead(int cm) => getTranslatedString('vsFhAhead', '{cm} cm ahead', params: {'cm': '$cm'});
  static String get vsFhExpected => getTranslatedString('vsFhExpected', 'Expected');
  static String vsFhExpectedSubLabel(int gestWeeks) => getTranslatedString('vsFhExpectedSubLabel', 'Expected ~{gestWeeks} cm at {gestWeeks} wks', params: {'gestWeeks': '$gestWeeks'});

  // ── Blood glucose status badges ─────────────────────────────────────────────
  static String get vsGlucoseNormal => getTranslatedString('vsGlucoseNormal', 'Normal');
  static String get vsGlucoseElevated => getTranslatedString('vsGlucoseElevated', 'Elevated');
  static String get vsGlucoseHigh => getTranslatedString('vsGlucoseHigh', 'High');
  static String get vsGlucoseWarningElevated => getTranslatedString('vsGlucoseWarningElevated', 'Elevated — advise dietary modification and refer for GDM screening.');
  static String get vsGlucoseWarningHigh => getTranslatedString('vsGlucoseWarningHigh', 'High blood sugar — refer urgently for diabetes evaluation.');

  // ── Blood glucose combined entry card ───────────────────────────────────────
  static String get bloodGlucoseEntryLabel => getTranslatedString('bloodGlucoseEntryLabel', 'Blood Glucose');
  static String get bloodGlucoseEntrySubLabel => bloodGlucoseEntryUnit;
  static String get bloodGlucoseEntryHint => getTranslatedString('bloodGlucoseEntryHint', 'Enter value (mmol/L)');
  static String get bloodGlucoseEntryUnit => getTranslatedString('bloodGlucoseEntryUnit', 'mmol/L');

  // ── Blood glucose pair-card chrome ──────────────────────────────────────────
  static String get glucosePairLabel => getTranslatedString('glucosePairLabel', 'Blood Sugar');
  static String get glucosePairSubLabel => bloodGlucoseEntryUnit;
  static String get glucoseFastingLabel => getTranslatedString('glucoseFastingLabel', 'Fasting');
  static String get glucoseRandomLabel => getTranslatedString('glucoseRandomLabel', 'Random');

  // ── Height + Weight pair-card chrome ────────────────────────────────────────
  static String get heightWeightPairLabel => getTranslatedString('heightWeightPairLabel', 'Height & Weight');
  static String get heightWeightPairSubLabel => getTranslatedString('heightWeightPairSubLabel', 'Height & Weight');
  static String get heightSubLabel => getTranslatedString('heightSubLabel', 'Height');
  static String get weightSubLabel => getTranslatedString('weightSubLabel', 'Weight');
  static String babyNumberLabel(int n) => getTranslatedString('UnifiedForm.babyNumberLabel', 'Baby {n}', params: {'n': '$n'});
  static String get newbornDetailsPrompt => getTranslatedString('UnifiedForm.newbornDetailsPrompt', 'Enter number of live births to add newborn details.');
  static String get selectAtLeastOneOptionError => getTranslatedString('UnifiedForm.selectAtLeastOneOptionError', 'Please select at least one option');
  static String get babyAliveLabel => getTranslatedString(
        'UnifiedForm.babyAliveLabel',
        'Is the baby alive?',
      );
  static String get babySexLabel =>
      getTranslatedString('UnifiedForm.babySexLabel', 'Sex');
  static String get neonatalDeathCauseLabel => getTranslatedString(
        'UnifiedForm.neonatalDeathCauseLabel',
        'Cause of neonatal death',
      );

  /// Human-readable label for a formType key shown as a programme badge.
  ///
  /// Returns `null` for the synthetic `vitals` formType (no badge needed).
  static String? programmeBadgeLabel(String formType) {
    switch (formType) {
      case 'commonVitals':
        return getTranslatedString('UnifiedForm.badgeVitals', 'Vitals');
      case 'anc':
        return getTranslatedString('UnifiedForm.badgeAnc', 'ANC');
      case 'ncd':
        return getTranslatedString('UnifiedForm.badgeNcd', 'NCD');
      case 'pncMother':
        return getTranslatedString('UnifiedForm.badgePnc', 'PNC');
      case 'pncChild':
        return getTranslatedString('UnifiedForm.badgeChild', 'Child');
      case 'pncNeonatal':
        return getTranslatedString('UnifiedForm.badgeNeonate', 'Neonate');
      case 'pregnancyOutcome':
        return getTranslatedString('UnifiedForm.badgePregnancyOutcome', 'Preg. Outcome');
      case 'cataract':
        return getTranslatedString('UnifiedForm.badgeCataract', 'Cataract');
      case 'eye_care':
        return getTranslatedString('UnifiedForm.badgeEyeCare', 'Eye Care');
      case 'family_planning':
        return getTranslatedString('UnifiedForm.badgeFamilyPlanning', 'FP');
      case 'pwProfile':
        return getTranslatedString('UnifiedForm.badgeProfile', 'Profile');
      default:
        return null;
    }
  }
}

/// Locale seam for `FormSection.title` values baked into
/// `assets/forms/layout_manifests.json`, which carries no locale field of
/// its own. Keyed off each section's stable `sectionId` (not the title text,
/// which is English-only and would break as a lookup key the moment it's
/// edited) so a translation can be added per section without touching the
/// manifest or its loader.
abstract final class FormSectionStrings {
  FormSectionStrings._();

  /// Renders a section header, uppercased to match the existing visual
  /// style. Falls back to `fallbackTitle.toUpperCase()` — byte-identical to
  /// the pre-existing `section.title.toUpperCase()` call sites — for any
  /// `sectionId` without a translation yet.
  static String headerFor(String sectionId, String fallbackTitle) {
    if (sectionId.isEmpty) return fallbackTitle.toUpperCase();
    return getTranslatedString('FormSection.$sectionId', fallbackTitle)
        .toUpperCase();
  }
}

abstract final class FormGalleryStrings {
  FormGalleryStrings._();
  static String get tabLabel => getTranslatedString('tabLabel', 'Gallery');
  static String get screenTitle => getTranslatedString('FormGallery.screenTitle', 'Form Gallery');
  static String get vitalsTab => getTranslatedString('vitalsTab', 'Vitals');
  static String get symptomsTab => getTranslatedString('symptomsTab', 'Symptoms');
  static String get programmesTab => getTranslatedString('programmesTab', 'Programmes');
  static String get fields => getTranslatedString('fields', 'fields');
}

abstract final class PerformanceStrings {
  static String get title => getTranslatedString('Performance.title', 'My Performance');
  static String get periodWeek => getTranslatedString('periodWeek', 'Week');
  static String get periodMonth => getTranslatedString('periodMonth', 'Month');
  static String get heroSubline => getTranslatedString('heroSubline', 'visits this period');
  static String get weeklyTarget => getTranslatedString('weeklyTarget', 'Weekly target');
  static String get statVisitsToday => getTranslatedString('statVisitsToday', 'Visits today');
  static String get statVisitsTodaySub => getTranslatedString('statVisitsTodaySub', 'so far');
  static String get statHouseholds => getTranslatedString('statHouseholds', 'Households');
  static String get statHouseholdsSub => getTranslatedString('statHouseholdsSub', 'enrolled');
  static String get statReferrals => getTranslatedString('statReferrals', 'Referrals');
  static String get statReferralsSub => getTranslatedString('statReferralsSub', 'this week');
  static String get statThisWeek => getTranslatedString('statThisWeek', 'Visits');
  static String get statThisMonth => getTranslatedString('statThisMonth', 'Visits');
  static String get statTotalVisitsSub => getTranslatedString('statTotalVisitsSub', 'this period');
  static String get sectionProgramme => getTranslatedString('sectionProgramme', 'VISITS BY PROGRAMME');
  static String get sectionRecent => getTranslatedString('sectionRecent', 'RECENT ACTIVITY');
  static String get today => getTranslatedString('Performance.today', 'Today');
  static String get yesterday => getTranslatedString('yesterday', 'Yesterday');
  static String get badgeCompleted => getTranslatedString('Performance.badgeCompleted', 'Completed');
  static String get badgeReferred => getTranslatedString('badgeReferred', 'Referred');
  static String get loadError => getTranslatedString('Performance.loadError', 'Could not load performance data');
  static String get iconTooltip => getTranslatedString('iconTooltip', 'My performance');

  static String periodLabelWeek(DateTime start, DateTime end) {
    final fmt = DateFormat('MMM d');
    return '${fmt.format(start)} – ${DateFormat('d').format(end)}';
  }

  static String periodLabelMonth(DateTime date) =>
      AppDateFormat.monthYearFmt.format(date);

  // ── Wireframe v2 additions ──────────────────────────────────────────────────
  static String get appBarSubtitle => getTranslatedString('Performance.appBarSubtitle', 'Jahnara Begum · SK ID 4521 · Manikganj Sadar');
  static String get heroScoreLabel => getTranslatedString('heroScoreLabel', 'PERFORMANCE SCORE');
  static String get heroDesc => getTranslatedString('heroDesc', 'Blends visit completion, referral follow-through & SLA compliance');
  static String get slaLabel => getTranslatedString('slaLabel', 'SLA COMPLIANCE');
  static String get highRiskLabel => getTranslatedString('highRiskLabel', 'HIGH-RISK RESPONSE');
  static String get visitTrendLabel => getTranslatedString('visitTrendLabel', 'VISIT TREND');
  static String get trendSteady => getTranslatedString('trendSteady', '↑ steady');
  static String get statVisitsCompleted => getTranslatedString('statVisitsCompleted', 'Visits Completed');
  static String get statReferralsMade => getTranslatedString('statReferralsMade', 'Referrals Made');
  static String get statReferralsCompleted => getTranslatedString('statReferralsCompleted', 'Referrals Completed');
  static String get statHouseholdsCovered => getTranslatedString('statHouseholdsCovered', 'Households Covered');
  static String get statAvgVisitsDay => getTranslatedString('statAvgVisitsDay', 'Avg Visits / Day');
  static String get statMissedOverdue => getTranslatedString('statMissedOverdue', 'Missed / Overdue');
  static String get sectionServiceBreakdown => getTranslatedString('sectionServiceBreakdown', 'SERVICE-WISE BREAKDOWN');
  static String get insightBoldPhrase => getTranslatedString('insightBoldPhrase', 'more visits');
  static List<String> get weekdayLabels => [
        getTranslatedString('Performance.weekdayMon', 'M'),
        getTranslatedString('Performance.weekdayTue', 'T'),
        getTranslatedString('Performance.weekdayWed', 'W'),
        getTranslatedString('Performance.weekdayThu', 'T'),
        getTranslatedString('Performance.weekdayFri', 'F'),
        getTranslatedString('Performance.weekdaySat', 'S'),
        getTranslatedString('Performance.weekdaySun', 'S'),
      ];
  static List<String> get weekLabels => [
        getTranslatedString('Performance.week1', 'W1'),
        getTranslatedString('Performance.week2', 'W2'),
        getTranslatedString('Performance.week3', 'W3'),
        getTranslatedString('Performance.week4', 'W4'),
      ];
  static String get serviceAnc => getTranslatedString('serviceAnc', 'ANC');
  static String get serviceNcd => getTranslatedString('serviceNcd', 'NCD');
  static String get serviceChild => getTranslatedString('serviceChild', 'Child / Immunisation');
  static String get servicePnc => getTranslatedString('servicePnc', 'PNC');
  static String get serviceHousehold => getTranslatedString('serviceHousehold', 'Household enrolment');

  static String insightWeek(int pct) => getTranslatedString('insightWeek', 'You completed {pct}% more visits than the Manikganj Sadar area average this week.', params: {'pct': '$pct'});

  static String insightMonth(int pct) => getTranslatedString('insightMonth', 'You completed {pct}% more visits than the Manikganj Sadar area average this month.', params: {'pct': '$pct'});
  static String get noPatients => getTranslatedString('Performance.noPatients', 'No patients');

  static String get performanceTab => getTranslatedString('Performance.performanceTab', 'Performance');
  static String get myPatientsTab => getTranslatedString('Performance.myPatientsTab', 'My Patients');

  // Namespaced separately from PatientContextStrings.serviceLabel /
  // HouseholdDetailStrings.lastVisitDate, which carry the same English for
  // unrelated surfaces, so this screen stays independently translatable.
  static String get serviceLabel => getTranslatedString('Performance.serviceLabel', 'Service');
  static String get nextVisitLabel => getTranslatedString('Performance.nextVisitLabel', 'Next Visit');
  static String get lastVisitLabel => getTranslatedString('Performance.lastVisitLabel', 'Last Visit');

  static String get outOf100 => getTranslatedString('Performance.outOf100', '/ 100');

  // `_SpiceDueText._resolve()` branch labels — that method returns a
  // `(String, Color)` record; only the String comes from here.
  static String get dueRoutine => getTranslatedString('Performance.dueRoutine', 'Routine');
  static String get dueTomorrow => getTranslatedString('Performance.dueTomorrow', 'Tomorrow');
  static String dueUpcomingInDays(int days) => getTranslatedString(
      'Performance.dueUpcomingInDays', 'Upcoming in {days} days', params: {'days': '$days'});
  /// Preserves the existing literal `day(s)` — it is not pluralised in code.
  static String overdueByDays(int d) => getTranslatedString(
      'Performance.overdueByDays', '{d} day(s) Overdue', params: {'d': '$d'});

  // `SkPerformanceStats.ratingFor()` branch labels.
  static String get ratingExcellent => getTranslatedString('Performance.ratingExcellent', 'Excellent');
  static String get ratingGood => getTranslatedString('Performance.ratingGood', 'Good');
  static String get ratingFair => getTranslatedString('Performance.ratingFair', 'Fair');
  static String get ratingNeedsImprovement =>
      getTranslatedString('Performance.ratingNeedsImprovement', 'Needs Improvement');
}

/// Household enrollment flow strings.
abstract final class EnrollmentStrings {
  EnrollmentStrings._();

  // ── NID Scan Screen ──────────────────────────────────────────────────────
  static String get nidScanTitle => getTranslatedString('nidScanTitle', 'Scan Head\'s ID');
  static String get nidScanSubtitle => getTranslatedString('nidScanSubtitle', 'Position ID card in the frame');
  static String get nidScanOrCreate => getTranslatedString('nidScanOrCreate', 'Or create household manually');
  static String get nidScanCameraHint => getTranslatedString('nidScanCameraHint', 'Place ID card here');

  // ── Create Household Screen (Step 1) ──────────────────────────────────────
  static String get createHouseholdTitle => getTranslatedString('createHouseholdTitle', 'Household Information');
  static String get createHouseholdSubtitle => getTranslatedString('createHouseholdSubtitle', 'Step 1 of 2');
  /// Spice R.string.household_registration — create-household AppBar.
  static String get enrollHouseholdAppBar =>
      getTranslatedString('enrollHouseholdAppBar', 'Enroll Household');
  /// Spice R.string.member_registration — add-member AppBar.
  static String get addMemberAppBar =>
      getTranslatedString('addMemberAppBar', 'Add Member');

  static String get householdNumberLabel => getTranslatedString('householdNumberLabel', 'Household Number');
  static String get householdNumberHint => getTranslatedString('householdNumberHint', 'Auto-generated');

  static String get healthWorkerLabel => getTranslatedString('healthWorkerLabel', 'SS Name');
  static String get healthWorkerHint => getTranslatedString('healthWorkerHint', 'Select SS');

  // Spice household_registration.json names `village_id` "Union" and
  // `sub_village_id` "Village"; keep the same wording so SKs see the labels
  // they were trained on in Android. Keys are Enrollment-scoped so other
  // screens that still say "Sub-Village" are unaffected.
  static String get villageLabel => getTranslatedString('Enrollment.villageLabel', 'Union');
  static String get villageHint => getTranslatedString('Enrollment.villageHint', 'Select union');
  static String get subVillageLabel => getTranslatedString('Enrollment.subVillageLabel', 'Village');
  static String get subVillageHint => getTranslatedString('Enrollment.subVillageHint', 'Select village');

  static String get householdTypeLabel => getTranslatedString('householdTypeLabel', 'Household Type');

  static String get numberOfMembersLabel => getTranslatedString('numberOfMembersLabel', 'Number of Members');
  static String get numberOfMembersHint => getTranslatedString('numberOfMembersHint', 'Estimated count');

  static String get houseNumberLabel => getTranslatedString('houseNumberLabel', 'House Number');
  static String get houseNumberHint => getTranslatedString('houseNumberHint', 'e.g., 123 A/B');

  static String get occupationLabel => getTranslatedString('occupationLabel', 'Primary Occupation');
  static String get occupationHint => getTranslatedString('occupationHint', 'Farmer, Labour, Business, etc.');

  static String get monthlyIncomeLabel => getTranslatedString('monthlyIncomeLabel', 'Monthly Income');

  static String get disabilityQuestionLabel => getTranslatedString('disabilityQuestionLabel', 'Does any household member have a disability?');
  static String get disabilityDetailsLabel => getTranslatedString('disabilityDetailsLabel', 'Please specify');
  static String get disabilityDetailsHint => getTranslatedString('disabilityDetailsHint', 'Type of disability');

  // ── Household Head Info Screen (Step 2) ──────────────────────────────────
  static String get householdHeadTitle => getTranslatedString('householdHeadTitle', 'Household Head Information');
  static String get householdHeadSubtitle => getTranslatedString('householdHeadSubtitle', 'Step 2 of 2');

  static String get headNameLabel => getTranslatedString('headNameLabel', 'Name');
  static String get headNameHint => getTranslatedString('headNameHint', 'Enter Name');

  static String get fatherNameLabel => getTranslatedString('fatherNameLabel', 'Father\'s Name');
  static String get fatherNameHint => getTranslatedString('fatherNameHint', 'As printed on the NID (Bangla)');
  static String get motherNameLabel => getTranslatedString('motherNameLabel', 'Mother\'s Name');
  static String get motherNameHint => getTranslatedString('motherNameHint', 'As printed on the NID (Bangla)');

  static String get idTypeLabel => getTranslatedString('idTypeLabel', 'ID Type');

  static String get mobileNumberLabel => getTranslatedString('mobileNumberLabel', 'Mobile Number');
  static String get mobileNumberHint => getTranslatedString('mobileNumberHint', '01XXXXXXXXX');
  static String get mobileNotAvailableLabel => getTranslatedString('mobileNotAvailableLabel', 'Not Available');

  static String get dateOfBirthLabel => getTranslatedString('dateOfBirthLabel', 'Date of Birth');
  static String get dateOfBirthHint => getTranslatedString('dateOfBirthHint', 'DD-MM-YYYY');
  static String get approximateAgeLabel => getTranslatedString('approximateAgeLabel', 'Or Approximate Age');
  static String get approximateAgeHint => getTranslatedString('approximateAgeHint', 'Years');

  static String get ageLabel => getTranslatedString('Enrollment.ageLabel', 'Age');
  static String get ageHint => getTranslatedString('ageHint', 'Calculated from DOB');

  static String get genderLabel => getTranslatedString('genderLabel', 'Gender');

  static String get maritalStatusLabel => getTranslatedString('maritalStatusLabel', 'Marital Status');
  static String get maritalStatusHint =>
      getTranslatedString('maritalStatusHint', 'Select status');
  static String get maritalStatusInfo => getTranslatedString(
        'maritalStatusInfo',
        'Select single if (Separated/Divorced/Partner deceased)',
      );

  /// Member-level disability (Spice member_registration.json title / titleCulture).
  static String get disabilityStatusLabel =>
      getTranslatedString('disabilityMemberQuestion', 'Disability');

  /// Spice member_registration.json `infoTitle` under Disability.
  static String get disabilityMemberInfo => getTranslatedString(
        'disabilityMemberInfo',
        'Who has great difficulty or cannot see, hear, walk, climb, do things independently',
      );


  // ── Add Member Screen ────────────────────────────────────────────────────
  static String get addMemberTitle => getTranslatedString('addMemberTitle', 'Bio Data');
  static String get memberNameLabel => getTranslatedString('memberNameLabel', 'Name');
  static String get memberNameHint => getTranslatedString('memberNameHint', 'Enter Name');

  static String get relationshipToHeadLabel => getTranslatedString('relationshipToHeadLabel', 'Relationship to Head');

  static String get memberVillageLabel => getTranslatedString('memberVillageLabel', 'Village (if different)');
  static String get memberVillageHint => getTranslatedString('memberVillageHint', 'For external members');

  static String get nidScanCTA => getTranslatedString('nidScanCTA', 'Scan ID (Optional)');

  // ── Success Screen ───────────────────────────────────────────────────────
  static String get householdCreatedTitle => getTranslatedString('householdCreatedTitle', 'Household Enrolled!');
  static String get householdCreatedSubtitle => getTranslatedString('householdCreatedSubtitle', 'Your household has been created successfully.');

  static String get householdDetailsTitle => getTranslatedString('householdDetailsTitle', 'Household Details');

  static String get membersAddedLabel => getTranslatedString('membersAddedLabel', 'Members Added');
  static String membersAddedCount(int count) => getTranslatedString('membersAddedCount', '{count} members', params: {'count': '$count'});

  static String get addMoreMembers => getTranslatedString('addMoreMembers', 'Add Member');
  static String get saveHousehold => getTranslatedString('saveHousehold', 'Save & Continue');

  // ── Shared validation messages ───────────────────────────────────────────
  static String get invalidEmail => getTranslatedString('invalidEmail', 'Please enter a valid email');
  static String get invalidPhone => getTranslatedString('invalidPhone', 'Please enter a valid phone number');
  static String get invalidAge => getTranslatedString('invalidAge', 'Please enter a valid age');
  static String get invalidDate => getTranslatedString('invalidDate', 'Please enter a valid date');

  static String get enrollmentFailed => getTranslatedString('enrollmentFailed', 'Enrollment failed');
  static String get enrollmentSuccess => getTranslatedString('enrollmentSuccess', 'Household enrolled successfully');

  // ── Common CTA buttons ───────────────────────────────────────────────────
  static String get next => getTranslatedString('next', 'Next');
  static String get previous => getTranslatedString('previous', 'Previous');
  static String get save => getTranslatedString('Enrollment.save', 'Save');
  static String get cancel => getTranslatedString('Enrollment.cancel', 'Cancel');
  static String get submit => getTranslatedString('submit', 'Submit');
  static String get createHousehold => getTranslatedString('createHousehold', 'Create Household');
  static String get scanAgain => getTranslatedString('scanAgain', 'Scan Again');

  // ── Redesign (v2) additions ───────────────────────────────────────────────
  static String get createHouseholdAppBarSubtitle => getTranslatedString('createHouseholdAppBarSubtitle', 'Register a new household in your catchment area');

  static String get householdInfoSectionHeader => getTranslatedString('householdInfoSectionHeader', '🏠 Household Information');
  static String get householdHeadSectionHeader => getTranslatedString('householdHeadSectionHeader', '👤 Household Head Information');

  static String get autoGeneratedSuffix => getTranslatedString('autoGeneratedSuffix', '(auto-generated)');

  static String get householdTypeHint => getTranslatedString('householdTypeHint', 'Select type');
  static String get householdHeadOccupationLabel => getTranslatedString('householdHeadOccupationLabel', 'Household Head\'s Occupation');
  static String get otherOccupationLabel => getTranslatedString('otherOccupationLabel', 'If Other Occupation');
  static String get otherOccupationHint => getTranslatedString('otherOccupationHint', 'Enter other occupation');
  static String get monthlyIncomeRangeLabel => getTranslatedString('monthlyIncomeRangeLabel', 'Monthly Income Range');
  static String get monthlyIncomeRangeHint => getTranslatedString('monthlyIncomeRangeHint', 'Select income range');
  static String get disabilityPersonCountLabel => getTranslatedString('disabilityPersonCountLabel', 'Persons with disability in the HH');
  static String get disabilityPersonCountHint => getTranslatedString('disabilityPersonCountHint', 'Enter number');
  static String get disabilityPersonCountInfo => getTranslatedString('disabilityPersonCountInfo', 'Who has great difficulty or cannot see, hear, walk, climb, do things independently, remember, concentrate, communicate, or understand others');
  static String get phoneCategoryLabel => getTranslatedString('phoneCategoryLabel', 'Mobile number category');
  static String get phoneCategoryHint => getTranslatedString('phoneCategoryHint', 'Select category');
  static String get occupationSelectHint =>
      getTranslatedString('occupationHintSelect', 'Select occupation');

  static String get totalMembersLabel => getTranslatedString('totalMembersLabel', 'Total Household Members');
  static String get totalMembersHint => getTranslatedString('totalMembersHint', 'Enter Total Members');

  static const List<String> householdTypesV2 = ['BRAC VO', 'NVO'];
  static const List<String> gendersHead = ['Male', 'Female', 'Other'];
  static const List<String> maritalStatusesV2 = [
    'Married',
    'Single',
    'Unmarried',
  ];
  static String get guardianLabel => getTranslatedString('guardianLabel', 'Guardian Name');
  static String get guardianHint => getTranslatedString('guardianHint', 'Select guardian from household');
  /// Spice R.string.add_guardian
  static String get addGuardian =>
      getTranslatedString('addGuardian', '+ Add Guardian');
  /// Spice R.string.alert — Add Guardian leave confirm title.
  static String get alertTitle => getTranslatedString('alertTitle', 'Alert');
  /// Spice R.string.exit_reason — Add Guardian leave confirm body.
  static String get exitReason => getTranslatedString(
        'exitReason',
        'If you leave this screen, your entered data will not be saved.',
      );
  // Spice member_registration.json shows the `disability` question as Yes/No;
  // the wire values stay present/absent (see EnrollmentRepository).
  /// Wire values for member disability (mapped to present/absent on sync).
  /// Display stays Yes/No ids so [_disabilityValue] keeps working; Bangla
  /// mode shows translated labels via [disabilityStatusDisplay].
  static const List<String> disabilityStatusesV2 = ['Yes', 'No'];
  static const List<String> disabilityYesNo = ['Yes', 'No'];

  static String disabilityStatusDisplay(String wire) {
    switch (wire) {
      case 'Yes':
        return getTranslatedString('PatientContext.yes', 'Yes');
      case 'No':
        return getTranslatedString('PatientContext.no', 'No');
      default:
        return wire;
    }
  }

  /// Bangla/English display for enrollment option ids (occupation, income,
  /// gender, marital, phone category, ID type, household type). Wire value
  /// stays the English/list entry — matches Spice cultureValue.
  static String optionDisplay(String option) {
    final key = 'Enrollment.opt.$option';
    return getTranslatedString(key, option);
  }

  static const List<String> gendersMember = ['Male', 'Female', 'Other'];

  /// Spice member_registration.json `phone_number_category` options, in order.
  static const List<String> phoneCategoryOptions = [
    'Personal (Self)',
    'Head of Household',
    'Family Member',
    'Friend',
  ];

  /// Display label → wire id for [phoneCategoryOptions].
  static const Map<String, String> phoneCategoryIds = {
    'Personal (Self)': 'personal',
    'Head of Household': 'household_head',
    'Family Member': 'family',
    'Friend': 'friend',
  };
  static const List<String> idTypesV2 = ['National ID', 'BRN', 'Not Available'];

  /// Spice household_registration.json `householdHeadOccupation` options, in
  /// order. The option id and display name are identical there, so these
  /// strings go on the wire verbatim.
  static const List<String> occupationOptions = [
    'Agriculture',
    'Garments worker',
    'Service/Job',
    'Technical worker',
    'Day laborer',
    'Vendor/Shopkeeper/Vegetable',
    'Businessman',
    'Foreign worker',
    'Self-employed',
    'Unemployed',
    'Other',
  ];

  /// Spice household_registration.json `monthlyIncomeRange` options, in order.
  /// Displayed with the ৳ symbol; [incomeRangeIds] holds the wire values, whose
  /// middle brackets use an en-dash exactly as Android's
  /// `HouseHoldRegistration.rangeFromExactValue` produces them.
  static const List<String> incomeRangeOptions = [
    '< ৳5000',
    '৳5001 – ৳10000',
    '৳10001 – ৳15000',
    '৳15001 – ৳20000',
    '৳20001 – ৳30000',
    '৳30001 – ৳40000',
    '৳40001 – ৳70000',
    '> ৳70000',
  ];

  static const Map<String, String> incomeRangeIds = {
    '< ৳5000': '<5000',
    '৳5001 – ৳10000': '5001–10000',
    '৳10001 – ৳15000': '10001–15000',
    '৳15001 – ৳20000': '15001–20000',
    '৳20001 – ৳30000': '20001–30000',
    '৳30001 – ৳40000': '30001–40000',
    '৳40001 – ৳70000': '40001–70000',
    '> ৳70000': '>70000',
  };

  static String get continueArrow => getTranslatedString('continueArrow', 'Continue →');
  static String get saveMemberCTA => getTranslatedString('saveMemberCTA', 'Save Member →');

  static String get nidScanButtonLabel => getTranslatedString('nidScanButtonLabel', 'Scan NID card to read number');
  static String get nidNumberLabel =>
      getTranslatedString('nidNumberLabel', 'National ID');
  static String get nidNumberHint =>
      getTranslatedString('nidNumberHint', 'Enter National ID');
  static String get brnNumberLabel =>
      getTranslatedString('brnNumberLabel', 'BRN');
  static String get brnNumberHint =>
      getTranslatedString('brnNumberHint', 'Enter BRN');
  static String get nidScannedBadge => getTranslatedString('nidScannedBadge', '✓ Scanned');
  static String get nidClearScan => getTranslatedString('nidClearScan', 'Clear scan');
  static String get nidScanNoBrnHint => getTranslatedString('nidScanNoBrnHint', 'If member has no NID, enter Birth Registration ID instead.');
  static String nidNumberCaptured(String number) => getTranslatedString('nidNumberCaptured', '✓ NID number captured: {number}', params: {'number': '$number'}, localizeDigits: false);
  static String get autoScanActive => getTranslatedString('autoScanActive', 'Auto-scanning — hold card steady');
  static String get autoScanHint => getTranslatedString('autoScanHint', 'Scanning every ~2 s · tap button to force capture');
  static String get nidScanNotFound => getTranslatedString('nidScanNotFound', 'Could not read the NID number. Try again or type it in below.');
  static String get nidScanError => getTranslatedString('nidScanError', 'Camera unavailable. Please type the NID number below.');
  static String get headPrefilledFromScan => getTranslatedString('headPrefilledFromScan', 'Name, date of birth & NID read from the card — verify, then add father\'s & mother\'s names (Bangla) manually.');
  static String nidDetailsCaptured(String number) => getTranslatedString('nidDetailsCaptured', '✓ Read from NID · verify the details below', params: {});

  // ── Existing-patient lookup (POST /spice-service/patient/search) ───────────
  /// Shown in the Add Member form after a scanned NID matches an existing
  /// registration and the server demographics have been loaded in.
  static String existingPatientLoaded(String name) => getTranslatedString('existingPatientLoaded', '✓ Already registered as {name} — details loaded from server', params: {'name': '$name'});

  /// Compact banner shown on the post-scan sheet when the scanned NID already
  /// belongs to a registered patient.
  static String existingPatientFound(String name) => getTranslatedString('existingPatientFound', 'Already registered as {name}', params: {'name': '$name'});

  static String get existingPatientHint => getTranslatedString('existingPatientHint', 'This person is already in the system — link them to a household instead of registering again.');

  static String get dobHelperText => getTranslatedString('dobHelperText', 'If exact DOB is unknown, leave blank and enter approximate age below.');
  static String get villageHelperText => getTranslatedString('villageHelperText', 'Only if member lives outside this household\'s village');
  static String get villageMemberHint => getTranslatedString('villageMemberHint', 'Leave blank if same village');
  static String get otpHelperText => getTranslatedString('otpHelperText', 'OTP verification required');

  static String get addMemberSubtitle => getTranslatedString('addMemberSubtitle', 'Adding to');

  static String get householdMembersSectionHeader => getTranslatedString('householdMembersSectionHeader', '👪 Household Members');

  static String get householdCreatedTitle2 => getTranslatedString('householdCreatedTitle2', 'Household Created');

  // Detail card labels
  static String get detailLabelHouseholdNo => getTranslatedString('detailLabelHouseholdNo', 'Household No.');
  static String get detailLabelHouseholdType => getTranslatedString('detailLabelHouseholdType', 'Household Type');
  static String get detailLabelVillage => getTranslatedString('detailLabelVillage', 'Village');
  static String get detailLabelTotalMembers => getTranslatedString('detailLabelTotalMembers', 'Total Members');

  // ── Duplicate detection ───────────────────────────────────────────────
  static String get duplicateTitle => getTranslatedString('duplicateTitle', 'Patient already registered');
  static String get duplicateBody => getTranslatedString('duplicateBody', 'A member with this ID is already in your records. Registering again may create a duplicate.');
  static String get duplicateViewRecord => getTranslatedString('duplicateViewRecord', 'View record');
  static String get duplicateContinue => getTranslatedString('duplicateContinue', 'Continue anyway');

  // ── Entry sheet (choose: create household / link to existing / scan NID) ─
  static String get entrySheetCreateHouseholdSubtitle => getTranslatedString('entrySheetCreateHouseholdSubtitle', 'Register a new household manually');
  static String get entrySheetLinkExistingTitle => getTranslatedString('entrySheetLinkExistingTitle', 'Add to Existing Household');
  static String get entrySheetLinkExistingSubtitle => getTranslatedString('entrySheetLinkExistingSubtitle', 'Link a new member to an existing household');
  static String get entrySheetRegisterManuallyTitle => getTranslatedString('entrySheetRegisterManuallyTitle', 'No NID? Register manually');
  static String get entrySheetRegisterManuallySubtitle => getTranslatedString('entrySheetRegisterManuallySubtitle', 'Fill in member details by hand');
  static String get orScanNid => getTranslatedString('orScanNid', 'or scan NID');
  static String get nidScanCardTypesCaption => getTranslatedString('nidScanCardTypesCaption', 'Bangladesh National ID Card · Smart NID · Birth Registration');
  static String get tapToCapture => getTranslatedString('tapToCapture', 'Tap to capture');
  static String get nidScanningLabel => getTranslatedString('nidScanningLabel', 'Scanning...');
  static String get postScanSheetTitle => getTranslatedString('postScanSheetTitle', 'NID card scanned');
  static String get linkToHouseholdLabel => getTranslatedString('linkToHouseholdLabel', 'Link to household');

  // ── Add/create member — NID-scanned confirmation, shared across the
  // add-existing-household-member and create-new-household flows (identical
  // text/meaning in both) ───────────────────────────────────────────────
  static String get memberAddedSuccess => getTranslatedString('Enrollment.memberAddedSuccess', 'Member added successfully');
  static String memberAddFailed(Object error) => getTranslatedString('Enrollment.memberAddFailed', 'Failed to add member: {error}', params: {'error': '$error'});
  static String get nidScannedHint => getTranslatedString('Enrollment.nidScannedHint', 'Scanned from NID — edit if needed');
  static String get clearNidScan => getTranslatedString('Enrollment.clearNidScan', 'Clear');
  static String get nidScannedChipLabel => getTranslatedString('Enrollment.nidScannedChipLabel', 'NID Scanned');
  static String get headBadgeLabel => getTranslatedString('Enrollment.headBadgeLabel', 'Head');

  // ── Entry sheet — scanner body headline/subtitle ternaries ─────────────
  static String get nidReadingCardDetailsHeadline => getTranslatedString('Enrollment.nidReadingCardDetailsHeadline', '🔍 Reading card details…');
  static String get nidAutoScanningHeadline => getTranslatedString('Enrollment.nidAutoScanningHeadline', '✦ Auto-scanning');
  static String get nidTakePhotoHeadline => getTranslatedString('Enrollment.nidTakePhotoHeadline', 'Take a Photo of NID Card');
  static String get nidReadingNumberSubtitle => getTranslatedString('Enrollment.nidReadingNumberSubtitle', 'Reading the NID number…');
  static String get cameraUnavailableLabel => getTranslatedString('Enrollment.cameraUnavailableLabel', 'Camera unavailable');
  static String get positionCardSubtitle => getTranslatedString('Enrollment.positionCardSubtitle', 'Position the card within the frame');

  // ── Entry sheet — post-scan sheet ───────────────────────────────────────
  static String get detailsReadOnDeviceLabel => getTranslatedString('Enrollment.detailsReadOnDeviceLabel', '✦ Details read on-device');
  static String get nidFieldNameLabel => getTranslatedString('Enrollment.nidFieldNameLabel', 'NAME');
  static String get nidFieldDobLabel => getTranslatedString('Enrollment.nidFieldDobLabel', 'DATE OF BIRTH');
  static String get nidFieldNidLabel => getTranslatedString('Enrollment.nidFieldNidLabel', 'NID NUMBER');
  static String get nidFieldNotReadValue => getTranslatedString('Enrollment.nidFieldNotReadValue', 'Not read — enter manually');
  static String get banglaNamesHint => getTranslatedString('Enrollment.banglaNamesHint', "Father's & mother's names are printed in Bangla — please type them in.");
  static String get postScanLinkOptionTitle => getTranslatedString('Enrollment.postScanLinkOptionTitle', 'Link to existing household');
  static String get postScanLinkOptionSubtitle => getTranslatedString('Enrollment.postScanLinkOptionSubtitle', 'Search and select from your households');
  static String get postScanCreateOptionTitle => getTranslatedString('Enrollment.postScanCreateOptionTitle', 'Create new household');
  static String get postScanCreateOptionSubtitle => getTranslatedString('Enrollment.postScanCreateOptionSubtitle', 'Register this member under a new household');

  // ── Mobile / ID number validation messages ──────────────────────────────
  static String mobileStartsWithError(String prefix) => getTranslatedString('Enrollment.mobileStartsWithError', 'Phone number should starts with {prefix}', params: {'prefix': prefix}, localizeDigits: false);
  static String mobileLengthError(int maxLength) => getTranslatedString('Enrollment.mobileLengthError', 'Mobile number must be {maxLength} digits', params: {'maxLength': '$maxLength'});
  static String get mobileInvalidError => getTranslatedString('Enrollment.mobileInvalidError', 'Please enter a valid mobile number');
  static String get nidFormatError => getTranslatedString('Enrollment.nidFormatError', 'National ID must be 10, 13, or 17 digits');
  static String get nidDuplicateAssignedError => getTranslatedString('Enrollment.nidDuplicateAssignedError', 'National ID is already assigned to another member');

  // ── Age unit / summary (EnrollmentAge.unit / .summary) ──────────────────
  static String get ageUnitYear => getTranslatedString('Enrollment.ageUnitYear', 'year');
  static String get ageUnitYears => getTranslatedString('Enrollment.ageUnitYears', 'years');
  static String get ageUnitMonth => getTranslatedString('Enrollment.ageUnitMonth', 'month');
  static String get ageUnitMonths => getTranslatedString('Enrollment.ageUnitMonths', 'months');
  static String get ageUnitDay => getTranslatedString('Enrollment.ageUnitDay', 'day');
  static String get ageUnitDays => getTranslatedString('Enrollment.ageUnitDays', 'days');
  static String ageSummaryYearMonth(int years, int months) => getTranslatedString('Enrollment.ageSummaryYearMonth', '{years} yr {months}m old', params: {'years': '$years', 'months': '$months'});
  static String ageSummaryYearSingular(int years) => getTranslatedString('Enrollment.ageSummaryYearSingular', '{years} year old', params: {'years': '$years'});
  static String ageSummaryYearPlural(int years) => getTranslatedString('Enrollment.ageSummaryYearPlural', '{years} years old', params: {'years': '$years'});
  static String ageSummaryMonthSingular(int months) => getTranslatedString('Enrollment.ageSummaryMonthSingular', '{months} month old', params: {'months': '$months'});
  static String ageSummaryMonthPlural(int months) => getTranslatedString('Enrollment.ageSummaryMonthPlural', '{months} months old', params: {'months': '$months'});
  /// Compact age chip on list rows and the patient header — `4m/F`, `33/M`.
  ///
  /// Suffixes are translated, not just the digits: converting digits alone
  /// left `৪m/F`, since `m`/`d`/`y` are English letters.
  static String ageChipDays(String days) => getTranslatedString(
      'Enrollment.ageChipDays', '{days}d', params: {'days': days});
  static String ageChipMonths(String months) => getTranslatedString(
      'Enrollment.ageChipMonths', '{months}m', params: {'months': months});
  static String ageChipYears(String years) => getTranslatedString(
      'Enrollment.ageChipYears', '{years}', params: {'years': years});
  static String get ageChipUnderOneDay =>
      getTranslatedString('Enrollment.ageChipUnderOneDay', '<1d');
  static String get ageChipUnderOneYear =>
      getTranslatedString('Enrollment.ageChipUnderOneYear', '<1y');

  static String get ageSummaryUnderOneDay => getTranslatedString('Enrollment.ageSummaryUnderOneDay', '< 1 day old');
  static String ageSummaryDays(int days) => getTranslatedString('Enrollment.ageSummaryDays', '{days} days old', params: {'days': '$days'});

  // ── Member / household forms ─────────────────────────────────────────────
  static String get dobRequired => getTranslatedString('Enrollment.dobRequired', 'Date of birth required');
  static String get brnFieldLabel => getTranslatedString('Enrollment.brnFieldLabel', 'Birth Registration Number (BRN)');

  // ── Dropdown default placeholder ─────────────────────────────────────────
  static String get dropdownDefaultHint => getTranslatedString('Enrollment.dropdownDefaultHint', 'Select…');

  // ── EnrollmentController validation errors ───────────────────────────────
  static String get householdNotInitializedError => getTranslatedString('Enrollment.householdNotInitializedError', 'Household not initialized');
  static String get membersCountRequiredError => getTranslatedString('Enrollment.membersCountRequiredError', 'Number of members must be greater than 0');
  static String get incomeRangeRequiredError => getTranslatedString('Enrollment.incomeRangeRequiredError', 'Monthly income range is required');
  static String get occupationSpecifyRequiredError => getTranslatedString('Enrollment.occupationSpecifyRequiredError', 'Please specify the occupation');
  static String get headInfoRequiredError => getTranslatedString('Enrollment.headInfoRequiredError', 'Head information not provided');
  static String get headNameRequiredError => getTranslatedString('Enrollment.headNameRequiredError', 'Head name is required');
  static String get idTypeRequiredError => getTranslatedString('Enrollment.idTypeRequiredError', 'ID type is required');
  static String get idNumberRequiredError => getTranslatedString('Enrollment.idNumberRequiredError', 'ID number is required');
  static String get maritalStatusRequiredError => getTranslatedString('Enrollment.maritalStatusRequiredError', 'Marital status is required');
  static String get disabilityStatusRequiredError => getTranslatedString('Enrollment.disabilityStatusRequiredError', 'Disability status is required');
  static String get mobileNumberRequiredError => getTranslatedString('Enrollment.mobileNumberRequiredError', 'Mobile number is required');
  static String get memberNameRequiredError => getTranslatedString('Enrollment.memberNameRequiredError', 'Member name is required');
  static String get ageInvalidError => getTranslatedString('Enrollment.ageInvalidError', 'Age must be valid');
  static String get memberDobRequiredError => getTranslatedString('Enrollment.memberDobRequiredError', 'Date of birth is required');
  static String get phoneCategoryRequiredError => getTranslatedString('Enrollment.phoneCategoryRequiredError', 'Mobile number category is required');
  static String get requiredFieldsMissingError => getTranslatedString('Enrollment.requiredFieldsMissingError', 'Please fill all required fields');
  static String get saveLocallyFailedError => getTranslatedString('Enrollment.saveLocallyFailedError', 'Failed to save household locally');
}

/// Strings for [AssistantScreen] — conversational AI Q&A tab.
abstract final class AssistantStrings {
  AssistantStrings._();

  static String get title => getTranslatedString('Assistant.title', 'AI Assistant');
  static String get subtitle => getTranslatedString('Assistant.subtitle', 'Apon Sushashthya');
  static String get inputHint => getTranslatedString('Assistant.inputHint', 'Ask a clinical question…');
  static String get errorMessage => getTranslatedString('errorMessage', 'Could not reach the assistant. Check your connection.');
  static String get suggestedMuac => getTranslatedString('suggestedMuac', 'How do I measure MUAC?');
  static String get suggestedAncDanger => getTranslatedString('suggestedAncDanger', 'ANC danger signs?');
  static String get suggestedNcd => getTranslatedString('suggestedNcd', 'NCD medication adherence tips');
  static String get suggestedReferChild => getTranslatedString('suggestedReferChild', 'When to refer a child?');
  static String get suggestedFindrisc => getTranslatedString('suggestedFindrisc', 'FINDRISC score interpretation');
  static String get emptyHeading => getTranslatedString('emptyHeading', 'Ask me anything');
  static String get emptySubheading => getTranslatedString('emptySubheading', 'Clinical guidance, protocol reminders,\nand care tips — always at hand.');
  static String get retryLabel => getTranslatedString('retryLabel', 'Retry');
  static String get poweredBy => getTranslatedString('Assistant.poweredBy', 'Powered by Gemini · For clinical guidance only');
  static String get badgeLabel => getTranslatedString('badgeLabel', 'AI');
  static String get tabAsk => getTranslatedString('tabAsk', 'Ask AI');
  static String get tabTraining => getTranslatedString('tabTraining', 'Training');
  static String get suggestedFollowUps => getTranslatedString('suggestedFollowUps', 'You might also ask:');
  static String get voiceStart => getTranslatedString('voiceStart', 'Tap to speak');
  static String get voiceStop => getTranslatedString('voiceStop', 'Tap to stop');
  static String get voiceListening => getTranslatedString('voiceListening', 'Listening…');
  static String get todayLabel => getTranslatedString('todayLabel', 'Today');
  static String get aiCoachTitle => getTranslatedString('aiCoachTitle', 'AI Coach');
  static String get welcomeMessage => getTranslatedString('welcomeMessage', 'How can I help you today? Ask me about patient counselling, clinical protocols, or SPICE.');
  static String get statusOnline => getTranslatedString('statusOnline', 'Online');
  static String get clearHistory => getTranslatedString('clearHistory', 'Clear chat history');
  static String get launchingMicroCoaching => getTranslatedString('launchingMicroCoaching', 'Opening coaching…');
  static String get openMicroCoaching => getTranslatedString('openMicroCoaching', 'Open Coaching');

  static String get enterAtLeast3Chars =>
      getTranslatedString('Assistant.enterAtLeast3Chars', 'Please enter at least 3 characters.');
  static String get settingUpRetryLater => getTranslatedString(
      'Assistant.settingUpRetryLater', 'Coaching assistant is being set up. Please try again later.');
  static String get emptyResponse =>
      getTranslatedString('Assistant.emptyResponse', 'Empty response');
  static String get noAnswerInResponse =>
      getTranslatedString('Assistant.noAnswerInResponse', 'No answer in response');
  static String get thinkingIndicator =>
      getTranslatedString('Assistant.thinkingIndicator', '✦ thinking…');

  // Action-chip labels. Kept as plain getters, and the switch over
  // AssistantActionType lives with the enum in assistant_models.dart, so this
  // core file does not import the feature layer.
  static String get actionStartVisit =>
      getTranslatedString('Assistant.actionStartVisit', 'Start visit');
  static String get actionOpenReferral =>
      getTranslatedString('Assistant.actionOpenReferral', 'Open referral');
  static String get actionScheduleFollowUp =>
      getTranslatedString('Assistant.actionScheduleFollowUp', 'Schedule follow-up');
  static String get actionCallPatient =>
      getTranslatedString('Assistant.actionCallPatient', 'Call patient');
}

// ─────────────────────────────────────────────────────────────────────────────
// Select Household screen (link member to existing household)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class SelectHouseholdStrings {
  static String get title => getTranslatedString('SelectHousehold.title', 'Select Household');
  static String get subtitle => getTranslatedString('SelectHousehold.subtitle', 'Choose the household to link this member to');
  static String get searchHint => getTranslatedString('SelectHousehold.searchHint', 'Search by name, house number, or village...');
  static String get catchmentCount => getTranslatedString('catchmentCount', 'households in your catchment');
  static String get emptyState => getTranslatedString('SelectHousehold.emptyState', 'No households found');
  static String get ctaPrefix => getTranslatedString('ctaPrefix', 'Link & Enrol');
  static String get unknownFamily => getTranslatedString('unknownFamily', 'Unknown family');
  static String get membersLabel => getTranslatedString('membersLabel', 'members');
}

// ─────────────────────────────────────────────────────────────────────────────
// EPI / Immunisation timeline
// ─────────────────────────────────────────────────────────────────────────────

/// Localised EPI vaccine / milestone labels for UI display only.
///
/// Never use the result as a persisted or transmitted value; that is
/// `VaccineEntry.display` (wire spelling stays English).
abstract final class EpiVaccineStrings {
  EpiVaccineStrings._();

  /// Update-status sheet title, e.g. "6 Weeks Vaccines". Takes the already
  /// localised milestone label.
  static String sheetTitle(String milestoneLabel) => getTranslatedString(
      'Epi.milestoneVaccinesTitle', '{milestone} Vaccines',
      params: {'milestone': milestoneLabel});

  static String display(String code, String fallback) =>
      getTranslatedString('Epi.vaccine.$code', fallback);

  /// Update-status card title (no dose number), e.g. "Pentavalent Vaccine".
  static String sheetDisplay(String code, String fallback) =>
      getTranslatedString('Epi.vaccineSheet.$code', fallback);

  static String description(String code, String fallback) =>
      getTranslatedString('Epi.vaccineDesc.$code', fallback);

  static String diseaseName(String code, String fallback) =>
      getTranslatedString('Epi.vaccineDisease.$code', fallback);

  static String milestone(String key, String fallback) =>
      key.isEmpty ? fallback : getTranslatedString('Epi.milestone.$key', fallback);
}

abstract final class EpiStrings {
  EpiStrings._();

  static String get screenTitle => getTranslatedString('Epi.screenTitle', 'Vaccination');
  static String get vaccinationCta => getTranslatedString('Epi.vaccinationCta', 'Vaccination');
  static String get noDobError => getTranslatedString('noDobError', 'Date of birth not available — cannot compute schedule.');

  static String overdueBanner(int count) => getTranslatedString(
        'Epi.overdueBanner',
        '$count ${count == 1 ? 'vaccine' : 'vaccines'} overdue · Action needed today.',
        params: {
          'count': '$count',
          'unit': count == 1 ? 'vaccine' : 'vaccines',
        },
      );

  static String get statusCompleted => getTranslatedString('statusCompleted', 'Completed');
  static String get statusDueNow => getTranslatedString('statusDueNow', 'Due now');
  static String dueNowPatientAge(String name, String age) => getTranslatedString(
        'Epi.dueNowPatientAge',
        'Due now · {name} is {age}',
        params: {'name': name, 'age': age},
      );
  static String statusDueNowPatientAge(String name, String age) =>
      getTranslatedString(
        'Epi.statusDueNowPatientAge',
        'Status: Due now · {name} is {age}',
        params: {'name': name, 'age': age},
      );
  static String statusLine(String status) => getTranslatedString(
        'Epi.statusLine',
        'Status: {status}',
        params: {'status': status},
      );
  static String get statusUpcoming => getTranslatedString('statusUpcoming', 'Upcoming');
  static String get statusNotYetDue => getTranslatedString('statusNotYetDue', 'Not yet due');
  static String get statusLocked => getTranslatedString('statusLocked', 'Locked');
  static String get statusMissed => getTranslatedString('statusMissed', 'Missed');
  static String get statusReferred => getTranslatedString('statusReferred', 'Referred');
  static String get referredToFacilityLabel => getTranslatedString('referredToFacilityLabel', 'Referred to facility');
  static String get missedReasonInlineLabel => getTranslatedString('missedReasonInlineLabel', 'Reason');

  static String get updateStatusCta => getTranslatedString('updateStatusCta', 'Update status →');
  static String get vaccinesDueLabel => getTranslatedString('vaccinesDueLabel', 'Vaccines due at this milestone');
  static String get dateAdministered => getTranslatedString('dateAdministered', 'Date Administered');
  static String get notesOptional => getTranslatedString('notesOptional', 'Notes (Optional)');
  static String get notesHint => getTranslatedString('notesHint', 'e.g. Child was well, no adverse reaction…');
  static String get markCompleted => getTranslatedString('markCompleted', 'Mark as Completed');
  static String get cancel => getTranslatedString('Epi.cancel', 'Cancel');
  static String get submitCta => getTranslatedString('submitCta', 'Submit');
  static String get givenOn => getTranslatedString('givenOn', 'Given');
  static String get doneVisitCta => getTranslatedString('doneVisitCta', 'Done → Continue Visit');

  static String get referCta => getTranslatedString('referCta', 'Refer to facility');
  static String get confirmReferralCta => getTranslatedString('confirmReferralCta', 'Confirm Referral');
  static String get back => getTranslatedString('Epi.back', 'Back');
  static String get referralFacilityLabel => getTranslatedString('referralFacilityLabel', 'Referral Facility');
  static String get referralFacilitySelectHint => getTranslatedString('referralFacilitySelectHint', 'Select facility…');
  static String get referralFacilityRequired => getTranslatedString('referralFacilityRequired', 'Please select a facility.');

  /// Locale-aware EPI referral-facility spinner label (UHIS Bangla when bn).
  static String referralFacilityLabelOf(FacilityOption option) {
    final banglaFallback =
        (option.cultureValue != null && option.cultureValue!.trim().isNotEmpty)
            ? option.cultureValue!
            : option.name;
    return getTranslatedString(
      'Epi.referralFacility.${option.id}',
      AppLocale.isBangla ? banglaFallback : option.name,
    );
  }

  /// Resolve a stored facility id or English name to a localized UI label.
  static String localizeReferralFacility(String? stored) {
    if (stored == null || stored.isEmpty) return stored ?? '';
    for (final o in referralFacilityOptions) {
      if (o.id == stored || o.name == stored) {
        return referralFacilityLabelOf(o);
      }
    }
    return stored;
  }
  static String get missedReasonLabel => getTranslatedString('missedReasonLabel', 'Reason for Missed Dose');
  static String get missedReasonHint => getTranslatedString('missedReasonHint', 'e.g. Child was sick on scheduled date');
  static String get missedReasonRequired => getTranslatedString('missedReasonRequired', 'Please enter a reason.');
  static String get childAssessmentSaveError => getTranslatedString('childAssessmentSaveError', 'Could not save the Child Health form. Please try again.');
  static String childAssessmentFieldsRequired(int n) => getTranslatedString(
        'childAssessmentFieldsRequired',
        '{n} required field(s) must be filled before continuing.',
        params: {'n': '$n'},
      );
  static String dueInMonths(int monthsUntil) => getTranslatedString(
        'Epi.dueInMonths',
        'Due in ~$monthsUntil ${monthsUntil == 1 ? 'month' : 'months'}',
        params: {
          'n': '$monthsUntil',
          'unit': monthsUntil == 1 ? 'month' : 'months',
        },
      );
}

/// EPI-specific Step 3 (AI recommendation) copy — visit summary, referral
/// reason, counselling, and follow-up text built from an [EpiVisitSummary].
abstract final class EpiVisitRecoStrings {
  EpiVisitRecoStrings._();

  /// Localised vaccine labels for the due doses, resolved from the summary's
  /// stable codes. [EpiVisitSummary] cannot do this itself — it must stay free
  /// of Flutter and of this file, which imports it.
  static List<String> overdueNames(EpiVisitSummary epi) => [
        for (var i = 0; i < epi.overdueVaccineNames.length; i++)
          EpiVaccineStrings.display(
            i < epi.overdueVaccineCodes.length ? epi.overdueVaccineCodes[i] : '',
            epi.overdueVaccineNames[i],
          ),
      ];

  /// Localised vaccine labels for the next milestone's doses.
  static List<String> nextMilestoneNames(EpiVisitSummary epi) => [
        for (var i = 0; i < epi.nextMilestoneVaccineNames.length; i++)
          EpiVaccineStrings.display(
            i < epi.nextMilestoneVaccineCodes.length
                ? epi.nextMilestoneVaccineCodes[i]
                : '',
            epi.nextMilestoneVaccineNames[i],
          ),
      ];

  static String currentMilestone(EpiVisitSummary epi) => EpiVaccineStrings
      .milestone(epi.currentMilestoneKey, epi.currentMilestoneLabel);

  static String? nextMilestone(EpiVisitSummary epi) =>
      epi.nextMilestoneLabel == null
          ? null
          : EpiVaccineStrings.milestone(
              epi.nextMilestoneKey ?? '', epi.nextMilestoneLabel!);

  static String get visitSummaryTitle => getTranslatedString(
      'EpiVisitReco.visitSummaryTitle', 'Vaccination Visit — Guideline Care Plan');

  /// Shared with the rule-based next-action fallback in `VisitFlowStrings`
  /// (`visit_flow_screen.dart`'s `_ruleBasedNaba()`), which surfaces the same
  /// English sentence when EPI has no overdue vaccines.
  static String get allVaccinesUpToDate => getTranslatedString(
      'EpiVisitReco.allVaccinesUpToDate', 'All scheduled vaccines are up to date for this visit.');

  static String visitSummary(EpiVisitSummary epi) => epi.overdueCount > 0
      ? getTranslatedString(
          'EpiVisitReco.visitSummaryOverdue',
          '${epi.overdueCount} ${epi.overdueCount == 1 ? 'vaccine' : 'vaccines'} '
              'overdue — ${epi.currentMilestoneLabel} doses due now.',
          params: {
            'count': '${epi.overdueCount}',
            'unit': epi.overdueCount == 1 ? 'vaccine' : 'vaccines',
            'milestone': currentMilestone(epi),
          },
        )
      : allVaccinesUpToDate;

  static String referralReason(String currentMilestoneLabel, List<String> names) =>
      getTranslatedString(
        'EpiVisitReco.referralReason',
        '$currentMilestoneLabel doses overdue — ${_andJoin(names)} are due now.',
        params: {'milestone': currentMilestoneLabel, 'names': _andJoin(names)},
      );

  static String catchUpAction(List<String> names) => getTranslatedString(
        'EpiVisitReco.catchUpAction',
        'All ${names.length} can be given in ONE visit — ${_andJoin(names)}.',
        params: {'count': '${names.length}', 'names': _andJoin(names)},
      );

  static List<String> counsellingLines(EpiVisitSummary epi) => [
        getTranslatedString(
          'EpiVisitReco.counsellingOverdueCount',
          '${epi.overdueCount} ${epi.overdueCount == 1 ? 'vaccine' : 'vaccines'} '
              'overdue — ${epi.currentMilestoneLabel} doses are due now.',
          params: {
            'count': '${epi.overdueCount}',
            'unit': epi.overdueCount == 1 ? 'vaccine' : 'vaccines',
            'milestone': currentMilestone(epi),
          },
        ),
        getTranslatedString(
          'EpiVisitReco.counsellingCatchUp',
          'All ${epi.overdueVaccineNames.length} can be given in ONE visit — '
              '${_andJoin(epi.overdueVaccineNames)}.',
          params: {
            'count': '${epi.overdueVaccineNames.length}',
            'names': _andJoin(overdueNames(epi)),
          },
        ),
        if (epi.nextMilestoneLabel != null)
          getTranslatedString(
            'EpiVisitReco.counsellingNextMilestone',
            'Next milestone: ${epi.nextMilestoneLabel} — '
                '${_andJoin(epi.nextMilestoneVaccineNames)}.',
            params: {
              'milestone': nextMilestone(epi)!,
              'names': _andJoin(nextMilestoneNames(epi)),
            },
          ),
        getTranslatedString('EpiVisitReco.counsellingReturnIfDanger',
            'Return at once if: high fever, rash, or breathing difficulty of any kind.'),
      ];

  static String followUpActivity(String? label, List<String> names) => label == null
      ? getTranslatedString(
          'EpiVisitReco.followUpActivityRoutine', 'Routine vaccination follow-up')
      : getTranslatedString(
          'EpiVisitReco.followUpActivityMilestone',
          '$label milestone — ${_andJoin(names)}',
          params: {'milestone': label, 'names': _andJoin(names)},
        );

  static String whatsappMessage(EpiVisitSummary epi) {
    final nextLabel = nextMilestone(epi);
    final nextNames = nextMilestoneNames(epi);
    final next = nextLabel != null
        ? getTranslatedString(
            'EpiVisitReco.whatsappNextMilestone',
            ' Next milestone: $nextLabel — ${_andJoin(nextNames)}.',
            params: {
              'milestone': nextLabel,
              'names': _andJoin(nextNames),
            },
          )
        : '';
    if (epi.overdueCount == 0) {
      return getTranslatedString(
        'EpiVisitReco.whatsappUpToDate',
        'All scheduled vaccines are up to date.$next',
        params: {'next': next},
      );
    }
    final overdue = overdueNames(epi);
    final milestone = currentMilestone(epi);
    return getTranslatedString(
      'EpiVisitReco.whatsappOverdue',
      '${epi.overdueCount} ${epi.overdueCount == 1 ? 'vaccine' : 'vaccines'} '
          'overdue — $milestone doses are due now. '
          'All can be given in ONE visit — ${_andJoin(overdue)}.$next '
          'Return at once if: high fever, rash, or breathing difficulty of any kind.',
      params: {
        'count': '${epi.overdueCount}',
        'unit': epi.overdueCount == 1 ? 'vaccine' : 'vaccines',
        'milestone': milestone,
        'names': _andJoin(overdue),
        'next': next,
      },
    );
  }

  static String _andJoin(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} & ${items.last}';
  }
}

/// Patient-facing clinical finding messages shown in the AI-insight /
/// "Before You Knock" summary (`ClinicalFinding.message`). Display only —
/// never sent to the backend and never compared by value.
///
/// Do NOT reuse these for `referral_evaluator.dart`: that file's reason/gap
/// strings cross the wire into the offline-sync payload and are compared by
/// value, so they are deliberately left unlocalized.
abstract final class ClinicalFindingStrings {
  ClinicalFindingStrings._();

  // ── Shared across programmes ──────────────────────────────────────────
  /// Shared by the ANC and PNC rules (three call sites, identical template).
  static String dangerSignReported(String label) => getTranslatedString(
      'ClinicalFinding.dangerSignReported', 'Danger sign reported: {label}.', params: {'label': label});

  /// Shared by the ANC and PNC rules — both emit byte-identical English.
  static String get pncSevereAnemia =>
      getTranslatedString('ClinicalFinding.pncSevereAnemia', 'Severe anemia.');

  // ── ANC ───────────────────────────────────────────────────────────────
  static String get ancBpAboveSafeThreshold => getTranslatedString(
      'ClinicalFinding.ancBpAboveSafeThreshold', 'BP is above the safe threshold. Watch for pre-eclampsia.');
  static String get ancBpRisingTwoVisits => getTranslatedString(
      'ClinicalFinding.ancBpRisingTwoVisits', 'BP has risen over the last two visits. Monitor closely.');
  static String get ancAnemiaReinforceIron => getTranslatedString(
      'ClinicalFinding.ancAnemiaReinforceIron', 'Anemia noted. Reinforce iron-folic intake.');
  static String get ancIronFolicBelowExpected => getTranslatedString(
      'ClinicalFinding.ancIronFolicBelowExpected', 'Iron-folic intake is below the expected daily rate.');
  static String ancMissedVisit(int daysOverdue) => getTranslatedString(
      'ClinicalFinding.ancMissedVisit', 'Missed ANC — gap of {daysOverdue} days.',
      params: {'daysOverdue': '$daysOverdue'});
  static String ancRoutineVisit(int visitNumber) => getTranslatedString(
      'ClinicalFinding.ancRoutineVisit', 'Routine visit — no concerns flagged. Visit {visitNumber} on track.',
      params: {'visitNumber': '$visitNumber'});

  // ── NCD ───────────────────────────────────────────────────────────────
  static String get ncdBpAndGlucoseCombined => getTranslatedString(
      'ClinicalFinding.ncdBpAndGlucoseCombined',
      'Both BP and blood sugar are above target — needs review today and planned follow-up.');
  static String get ncdBpAboveNormal => getTranslatedString(
      'ClinicalFinding.ncdBpAboveNormal', 'BP is above normal. Requires review and follow-up.');
  static String get ncdBloodSugarElevated => getTranslatedString(
      'ClinicalFinding.ncdBloodSugarElevated', 'Blood sugar is elevated. Requires review and follow-up.');
  static String get ncdTrendingDown => getTranslatedString(
      'ClinicalFinding.ncdTrendingDown', 'BP/sugar trending down — continue current plan.');
  static String get ncdWithinTarget => getTranslatedString(
      'ClinicalFinding.ncdWithinTarget', 'Vitals within target — continue current management.');
  static String get ncdLowAdherence => getTranslatedString(
      'ClinicalFinding.ncdLowAdherence', 'Medication adherence is low — confirm daily intake.');

  // ── PNC ───────────────────────────────────────────────────────────────
  static String get pncUrgentTemperature => getTranslatedString(
      'ClinicalFinding.pncUrgentTemperature', 'Temperature is above normal (≥102°F). Needs urgent attention.');
  static String get pncUrgentPulse => getTranslatedString(
      'ClinicalFinding.pncUrgentPulse', 'Pulse is abnormal (outside 60–90 bpm). Needs urgent attention.');
  static String get pncUrgentBp => getTranslatedString(
      'ClinicalFinding.pncUrgentBp', 'BP is above normal (≥140/90). Needs urgent attention.');
  static String get pncNoContraception => getTranslatedString(
      'ClinicalFinding.pncNoContraception', 'No contraception method in use — counsel on options.');
  static String get pncSupplementGapVitaminA => getTranslatedString(
      'ClinicalFinding.pncSupplementGapVitaminA', 'Supplement gap — Vitamin A not on track.');
  static String get pncSupplementGapIfa => getTranslatedString(
      'ClinicalFinding.pncSupplementGapIfa', 'Supplement gap — Iron-folic acid not on track.');
  static String get pncSupplementGapCalcium => getTranslatedString(
      'ClinicalFinding.pncSupplementGapCalcium', 'Supplement gap — Calcium not on track.');
  static String pncOverdueVisit(int visitNumber, int daysOverdue) => getTranslatedString(
      'ClinicalFinding.pncOverdueVisit', 'PNC Visit {visitNumber} is overdue by {daysOverdue} days.',
      params: {'visitNumber': '$visitNumber', 'daysOverdue': '$daysOverdue'});
  static String get pncRoutine => getTranslatedString(
      'ClinicalFinding.pncRoutine', 'Recovering well — no concerns at this PNC visit.');

  // ── Child immunization ────────────────────────────────────────────────
  static String childImmunizationOverdueDoses(int count, String names) => getTranslatedString(
      'ClinicalFinding.childImmunizationOverdueDoses', '{count} dose(s) overdue: {names}.',
      params: {'count': '$count', 'names': names});
  static String get childImmunizationWeightGainSlowed => getTranslatedString(
      'ClinicalFinding.childImmunizationWeightGainSlowed',
      'Weight gain has slowed since the last check — monitor nutrition.');
  static String childImmunizationDueSoon(String display) => getTranslatedString(
      'ClinicalFinding.childImmunizationDueSoon', '{display} due soon — plan for next visit.',
      params: {'display': display});
  static String get childImmunizationOnSchedule => getTranslatedString(
      'ClinicalFinding.childImmunizationOnSchedule', 'Immunization on schedule, growth on track.');

  // ── Pregnancy outcome ─────────────────────────────────────────────────
  static String get pregnancyOutcomeStillbirthOrNeonatalDeath => getTranslatedString(
      'ClinicalFinding.pregnancyOutcomeStillbirthOrNeonatalDeath', 'Stillbirth or neonatal death recorded.');
  static String pregnancyOutcomeAbortion(String abortionTypeLabel) => getTranslatedString(
      'ClinicalFinding.pregnancyOutcomeAbortion',
      'Pregnancy loss (abortion, {abortionTypeLabel}) recorded — follow-up care advised.',
      params: {'abortionTypeLabel': abortionTypeLabel});
  static String get pregnancyOutcomeHealthy => getTranslatedString(
      'ClinicalFinding.pregnancyOutcomeHealthy',
      'Healthy delivery outcome — mother and baby both doing well.');
}

/// Labels for [VitalClassification] band names.
abstract final class VitalClassifierStrings {
  VitalClassifierStrings._();

  static String get normal => getTranslatedString('VitalClassifier.normal', 'Normal');
  static String get low => getTranslatedString('VitalClassifier.low', 'Low');
  static String get high => getTranslatedString('VitalClassifier.high', 'High');
  static String get critical => getTranslatedString('VitalClassifier.critical', 'Critical');
}

abstract final class ChildAssessmentStrings {
  ChildAssessmentStrings._();

  static String get sectionTitle => getTranslatedString('ChildAssessment.sectionTitle', 'Child Assessment');
  static String get q6Label => getTranslatedString('q6Label', 'Does the child have any congenital defect?');
  static String get q7Label => getTranslatedString('q7Label', 'Weight');
  static String get q7Unit => getTranslatedString('q7Unit', 'kg');
  static String get q7Hint => getTranslatedString('q7Hint', 'e.g. 6.5');
  static String get q7RangeError => getTranslatedString('q7RangeError', 'Weight must be between 0 and 30 kg');
  static String get q7bLabel => getTranslatedString('q7bLabel', 'What was the child fed in the last 24 hours?');
  static String get q8Label => getTranslatedString('q8Label', 'Is the child breastfeeding?');
  static String get q9Label => getTranslatedString('q9Label', 'In the past 24 hours, was the child given additional food?');
  static String get q10Label => getTranslatedString('q10Label', 'Has the child received vaccines?');
  static String get q11Label => getTranslatedString('q11Label', 'Has the child taken deworming medicine?');
  static String get q12Label => getTranslatedString('q12Label', 'Any Illness/Complications?');
  static String get q13Label => getTranslatedString('q13Label', 'If any complication, specify');
  static String get q13SelectAll => getTranslatedString('q13SelectAll', 'Select all that apply');
  static String get q14Label => getTranslatedString('q14Label', 'Has referral been made?');
  static String get q15Label => getTranslatedString('q15Label', 'Referral place');
  static String get yesOption => getTranslatedString('yesOption', 'Yes');
  static String get noOption => getTranslatedString('noOption', 'No');
  static String get vaccinationCta => getTranslatedString('ChildAssessment.vaccinationCta', '💉  Vaccination  →');

  // WIRE CONTRACT: the selected complications are persisted straight into the
  // assessment payload's `complications` field, so these ids are the current
  // English strings and the transmitted value is unchanged. Only the rendered
  // label is localized — same split as [feedLast24hOptionIds] below.
  static const List<String> complicationOptionIds = [
    'Diarrhea',
    'Pneumonia',
    'Cannot stand or walk',
    'Cannot maintain body balance',
    'Cannot speak two meaningful words',
  ];

  static const Map<String, String> _complicationCodes = {
    'Diarrhea': 'ChildAssessment.complicationDiarrhea',
    'Pneumonia': 'ChildAssessment.complicationPneumonia',
    'Cannot stand or walk': 'ChildAssessment.complicationCannotStandOrWalk',
    'Cannot maintain body balance': 'ChildAssessment.complicationCannotMaintainBalance',
    'Cannot speak two meaningful words': 'ChildAssessment.complicationCannotSpeakTwoWords',
  };

  /// Each id doubles as its own English fallback, so an unrecognised id renders
  /// as itself rather than being swallowed.
  static String complicationOptionLabel(String id) {
    final code = _complicationCodes[id];
    return code == null ? id : getTranslatedString(code, id);
  }

  // Wire ids (Android rmnch_childhood_visit.json "childFeedLast24Hrs" optionsList
  // "value" fields, in declared order) — not display strings, so they must be
  // sent as-is in the childFeedLast24Hrs payload, not the translated label.
  static const List<String> feedLast24hOptionIds = [
    'mothersBreastMilk',
    'cowgoatMilk',
    'formulaMilk',
    'semolina',
    'ricePowder',
    'familyFood',
    'other',
  ];

  static const Map<String, String> _feedLast24hFallbackLabels = {
    'mothersBreastMilk': "Mother's breast milk",
    'cowgoatMilk': 'Cow/Goat milk',
    'formulaMilk': 'Formula milk',
    'semolina': 'Semolina',
    'ricePowder': 'Rice powder',
    'familyFood': 'Family Food',
    'other': 'Other',
  };

  static String feedLast24hOptionLabel(String id) => getTranslatedString(
        'feedOption_$id',
        _feedLast24hFallbackLabels[id] ?? id,
      );
  static String get q15Hint => getTranslatedString('ChildAssessment.q15Hint', 'Select…');
}

/// Care Coordination Engine (CCE) — the referral SLA alert drawer.
/// All copy for `lib/features/cce/`, including the strings the `CceAlert`
/// derivation interpolates. `cce_alert.dart` holds no copy of its own.
abstract final class CceStrings {
  CceStrings._();

  // ── Drawer header ─────────────────────────────────────────────────────────
  static String get drawerTitle => getTranslatedString('drawerTitle', 'Care Coordination Alerts');
  static String get poweredBy => getTranslatedString('Cce.poweredBy', 'Powered by CCE · Care Coordination Engine');
  static String actionsNeeded(int n) =>
      '$n action${n == 1 ? '' : 's'} needed';
  static String get done => getTranslatedString('Cce.done', 'Done');

  static String get explainer => getTranslatedString('explainer', 'CCE tracks every patient after referral and triggers alerts when SLAs are breached — so no patient is lost between SK and facility.');

  // ── Bell entry point ──────────────────────────────────────────────────────
  static String get bellTooltip => getTranslatedString('bellTooltip', 'Care Coordination Alerts');

  // ── Search ───────────────────────────────────────────────────────────────
  static String get searchHint => getTranslatedString('Cce.searchHint', 'Search by name or village…');
  static String get searchNoResultsTitle => getTranslatedString('searchNoResultsTitle', 'No alerts match your search');
  static String get searchNoResultsBody => getTranslatedString('searchNoResultsBody', 'Try a different patient name or village.');

  // ── Empty state ───────────────────────────────────────────────────────────
  static String get emptyTitle => getTranslatedString('Cce.emptyTitle', 'All referrals on track');
  static String get emptyBody => getTranslatedString('Cce.emptyBody', 'No SLA breaches. Every referred patient is accounted for between SK and facility.');

  // ── Card actions ──────────────────────────────────────────────────────────
  static String get actionCallFamily => getTranslatedString('Cce.actionCallFamily', 'Call family');
  static String get actionUpdateStatus => getTranslatedString('Cce.actionUpdateStatus', 'Update status');
  static String get actionLocate => getTranslatedString('Cce.actionLocate', 'Locate');
  static String get actionCheckIn => getTranslatedString('actionCheckIn', 'Check in');

  static String get noPhone => getTranslatedString('Cce.noPhone', 'No phone number on file for this patient');
  static String get noLocation => getTranslatedString('noLocation', 'No location on file for this patient');
  static String get dialFailed => getTranslatedString('Cce.dialFailed', 'Could not open the dialer');
  static String get smsFailed => getTranslatedString('Cce.smsFailed', 'Could not open SMS');

  // ── Update-status sheet ───────────────────────────────────────────────────
  static String updateTitle(String patientName) => getTranslatedString('updateTitle', 'Update — {patientName}', params: {'patientName': '$patientName'});
  static String get updatePrompt => getTranslatedString('updatePrompt', 'Where is the patient now?');
  static String get updateOptNotLeft => getTranslatedString('updateOptNotLeft', 'Not yet left home');
  static String get updateOptOnWay => getTranslatedString('updateOptOnWay', 'On the way to facility');
  static String get updateOptArrived => getTranslatedString('updateOptArrived', 'Arrived at facility');
  static String get updateOptTreated => getTranslatedString('updateOptTreated', 'Seen by clinician / treated');
  static String get updateOptDischarged => getTranslatedString('updateOptDischarged', 'Discharged (recovered)');

  static String get barrierPrompt => getTranslatedString('barrierPrompt', 'Add a barrier tag (optional)');
  static String get barrierTransport => getTranslatedString('barrierTransport', 'Transport');
  static String get barrierCost => getTranslatedString('barrierCost', 'Cost');
  static String get barrierFamily => getTranslatedString('barrierFamily', 'Family');
  static String get barrierDistance => getTranslatedString('barrierDistance', 'Distance');

  static String get saveUpdate => getTranslatedString('saveUpdate', 'Save update');
  static String get saveHint => getTranslatedString('saveHint', 'Saves offline · syncs on next cycle');
  static String get updateSaved => getTranslatedString('updateSaved', 'Referral status updated');
  static String get selectStatus => getTranslatedString('selectStatus', 'Select the patient\'s current status');

  // ── Follow-up banner (completed cards) ───────────────────────────────────
  static String followUpDueBanner([String? date]) =>
      date != null ? 'Follow-up due · $date' : 'Follow-up due';

  // ── Update status sheet v2 (wireframe v14) ───────────────────────────────
  static String get updateSheetTitle => getTranslatedString('updateSheetTitle', 'Update patient status');
  static String get updateSyncNote => getTranslatedString('updateSyncNote', 'CCE will sync this update to the facility and supervisor');
  static String get updateOptReachedFacility => getTranslatedString('updateOptReachedFacility', 'Patient reached facility');
  static String get updateOptTransportIssue => getTranslatedString('updateOptTransportIssue', 'Unable to travel — transport issue');
  static String get updateOptRefused => getTranslatedString('updateOptRefused', 'Patient refused referral');
  static String get updateOptRecoveredHome => getTranslatedString('updateOptRecoveredHome', 'Patient recovered at home');
  static String get updateOptOther => getTranslatedString('updateOptOther', 'Other — add note');
  static String get updateConfirmSync => getTranslatedString('updateConfirmSync', 'Confirm & sync to CCE');
  static String get updateCancel => getTranslatedString('updateCancel', 'Cancel');
  static String get updateOtherHint => getTranslatedString('updateOtherHint', 'Describe what happened…');
  static String get updateOtherRequired => getTranslatedString('updateOtherRequired', 'Please add a note before saving');

  // ── Referred call result (SK parity) ─────────────────────────────────────
  static String get callResultTitle =>
      getTranslatedString('Cce.callResultTitle', 'Call result');
  static String get callResultPrompt =>
      getTranslatedString('Cce.callResultPrompt', 'How did the call go?');
  static String get willingToVisitUhc =>
      getTranslatedString('Cce.willingToVisitUhc', 'Willing to visit UHC?');
  static String get willingYes =>
      getTranslatedString('Cce.willingYes', 'Yes');
  static String get willingNo => getTranslatedString('Cce.willingNo', 'No');
  static String get notWillingReason =>
      getTranslatedString('Cce.notWillingReason', 'Reason for not visiting');
  static String get otherReasonHint =>
      getTranslatedString('Cce.otherReasonHint', 'Describe the reason…');
  static String get callResultSubmit =>
      getTranslatedString('Cce.callResultSubmit', 'Submit');
  static String get callLogged => getTranslatedString(
        'Cce.callLogged',
        'Call logged — will sync on next cycle',
      );

  // ── Derivation copy (previously a private copy holder in cce_alert.dart) ──

  static String get unknownPatient => getTranslatedString('Cce.unknownPatient', 'Patient');
  static String get referralReasonFallback =>
      getTranslatedString('Cce.referralReasonFallback', 'Referral');
  static String get attentionBadge => getTranslatedString('Cce.attentionBadge', 'Needs attention');
  static String get onTrackBadge => getTranslatedString('Cce.onTrackBadge', 'On track');
  static String get completedBadge => getTranslatedString('Cce.completedBadge', 'Completed');

  static String get slaEmergencyWindow => getTranslatedString('Cce.slaEmergencyWindow', '6 hours');
  static String get slaUrgentWindow => getTranslatedString('Cce.slaUrgentWindow', '24 hours');
  static String get slaRoutineWindow => getTranslatedString('Cce.slaRoutineWindow', '72 hours');

  static String get stepSkVisit => getTranslatedString('Cce.stepSkVisit', 'SK Visit');
  static String get stepReferred => getTranslatedString('Cce.stepReferred', 'Referred');
  static String get stepFacility => getTranslatedString('Cce.stepFacility', 'Facility');
  static String get stepArrived => getTranslatedString('Cce.stepArrived', 'Arrived');
  static String get stepNotArrived => getTranslatedString('Cce.stepNotArrived', 'Not arrived');
  static String get stepPending => getTranslatedString('Cce.stepPending', 'Pending');
  static String get stepTreatment => getTranslatedString('Cce.stepTreatment', 'Treatment');
  static String get stepTreated => getTranslatedString('Cce.stepTreated', 'Treated');
  static String get stepInProgress => getTranslatedString('Cce.stepInProgress', 'In progress');
  static String get stepDischarged => getTranslatedString('Cce.stepDischarged', 'Discharged');

  static String get tagCareComplete => getTranslatedString('Cce.tagCareComplete', 'Care completed');
  static String get tagAtFacility => getTranslatedString('Cce.tagAtFacility', 'At facility');
  static String get tagNotCheckedIn => getTranslatedString('Cce.tagNotCheckedIn', 'Not checked in');
  static String get tagTransportBarrier =>
      getTranslatedString('Cce.tagTransportBarrier', 'Transport barrier?');

  static String get actionRecommended =>
      getTranslatedString('Cce.actionRecommended', 'Action recommended');
  static String get atFacilityOnTrack =>
      getTranslatedString('Cce.atFacilityOnTrack', 'At facility — care in progress');
  static String get onTrackLine =>
      getTranslatedString('Cce.onTrackLine', 'On track — no action needed');

  /// [over] is a formatted duration such as '4d' or '6h', not a raw count.
  static String breachBadge(String over) =>
      getTranslatedString('Cce.breachBadge', 'SLA BREACHED +{over}', params: {'over': over});
  static String leftBadge(String left) =>
      getTranslatedString('Cce.leftBadge', 'SLA: {left} left', params: {'left': left});

  /// Kept as one method with a nullable [facility] so both call sites stay a
  /// pure rename; splitting it would push the null-check out to each caller.
  static String referredMeta(String date, String? facility, String reason) =>
      (facility != null && facility.isNotEmpty)
          ? getTranslatedString('Cce.referredMetaWithFacility',
              'Referred: {date} · {facility} · {reason}',
              params: {'date': date, 'facility': facility, 'reason': reason})
          : getTranslatedString('Cce.referredMeta', 'Referred: {date} · {reason}',
              params: {'date': date, 'reason': reason});

  static String notArrivedOverdue(String overdue, String slaWindow) => getTranslatedString(
      'Cce.notArrivedOverdue', 'Not arrived · {overdue} overdue · SLA was {slaWindow}',
      params: {'overdue': overdue, 'slaWindow': slaWindow});
  static String treatmentOverdue(String slaWindow) => getTranslatedString(
      'Cce.treatmentOverdue', 'Treatment overdue · SLA was {slaWindow}',
      params: {'slaWindow': slaWindow});
  static String awaitingReview(String waiting) => getTranslatedString(
      'Cce.awaitingReview', 'Checked in — awaiting review · {waiting} waiting',
      params: {'waiting': waiting});
  static String dueSoon(String left) =>
      getTranslatedString('Cce.dueSoon', 'Due in {left} · act soon', params: {'left': left});
  static String dischargedLine(String date) => getTranslatedString(
      'Cce.dischargedLine', 'Discharged {date} · care complete', params: {'date': date});
  static String closedDeceased(String date) => getTranslatedString(
      'Cce.closedDeceased', 'Closed {date} · deceased', params: {'date': date});
  static String tagEscalated(int level) =>
      getTranslatedString('Cce.tagEscalated', 'Escalated L{level}', params: {'level': '$level'});

  static String get wrongNumberClosed =>
      getTranslatedString('Cce.wrongNumberClosed', 'Wrong number · closed');
  static String callAttemptsStatus(int attempts, int retryAttempts, int remaining) =>
      getTranslatedString('Cce.callAttemptsStatus', '{attempts} of {retryAttempts} calls · {remaining} left',
          params: {
            'attempts': '$attempts',
            'retryAttempts': '$retryAttempts',
            'remaining': '$remaining',
          });
  static String get lastAttempt => getTranslatedString('Cce.lastAttempt', 'Last attempt');
  static String get followingUp => getTranslatedString('Cce.followingUp', 'Following up');

  // ── Reject reasons — key / label split ───────────────────────────────────
  //
  // WIRE CONTRACT: the selected reason is persisted to `follow_up_calls.reason`
  // and pushed to the server as `reason` / `visitRejectReason`. The keys below
  // are therefore the current English display strings, so the stored and
  // transmitted value stays byte-identical to today; only the rendered label is
  // localized. Compare against [rejectReasonOtherKey], never a literal.
  //
  // Mirrors the in-tree exemplar `ChildAssessmentStrings.feedLast24hOptionIds`.
  static const List<String> rejectReasonKeys = [
    'Treatment from other facility',
    'No Medicine',
    'Long Distance',
    'Transportation and unsupplied medicine cost',
    'Long waiting queue',
    'Migrated to other places',
    'Died',
    'Other',
  ];

  static const String rejectReasonOtherKey = 'Other';

  static const Map<String, String> _rejectReasonCodes = {
    'Treatment from other facility': 'Cce.rejectReasonTreatmentOtherFacility',
    'No Medicine': 'Cce.rejectReasonNoMedicine',
    'Long Distance': 'Cce.rejectReasonLongDistance',
    'Transportation and unsupplied medicine cost': 'Cce.rejectReasonTransportCost',
    'Long waiting queue': 'Cce.rejectReasonLongWaitingQueue',
    'Migrated to other places': 'Cce.rejectReasonMigrated',
    'Died': 'Cce.rejectReasonDied',
    'Other': 'Cce.rejectReasonOther',
  };

  /// Each key doubles as its own English fallback, so an unrecognised key
  /// renders as itself rather than being swallowed.
  static String rejectReasonLabel(String key) {
    final code = _rejectReasonCodes[key];
    return code == null ? key : getTranslatedString(code, key);
  }
}

/// Follow-up call logging — the device-side close/update flow.
abstract final class FollowUpCallStrings {
  FollowUpCallStrings._();

  static String get logCall => getTranslatedString('logCall', 'Log call');
  static String get sheetTitle => getTranslatedString('FollowUpCall.sheetTitle', 'Log follow-up call');
  static String get outcomePrompt => getTranslatedString('outcomePrompt', 'How did the call go?');
  static String get outcomeSuccessful => getTranslatedString('outcomeSuccessful', 'Successful');
  static String get outcomeUnsuccessful => getTranslatedString('outcomeUnsuccessful', 'Could not reach');
  static String get outcomeWrongNumber => getTranslatedString('outcomeWrongNumber', 'Wrong number');
  static String get reasonLabel => getTranslatedString('reasonLabel', 'Note (optional)');
  static String get reasonHint => getTranslatedString('reasonHint', 'e.g. no answer, will retry tomorrow');
  static String get save => getTranslatedString('FollowUpCall.save', 'Save call');
  static String get saved => getTranslatedString('FollowUpCall.saved', 'Call logged — will sync on next cycle');
  static String get schedule => getTranslatedString('schedule', 'Schedule');
  static String get scheduled => getTranslatedString('scheduled', 'Follow-up scheduled — will sync on next cycle');
  static String get scheduleFailed => getTranslatedString('scheduleFailed', 'Could not schedule the follow-up');
  static String get selectOutcome => getTranslatedString('selectOutcome', 'Select the call outcome');
  static String get closedNote => getTranslatedString('closedNote', 'Wrong number or exhausted attempts will close this follow-up.');
  static String get failed => getTranslatedString('failed', 'Could not log the call');

  // ── Open Follow-ups section (patient context) ───────────────────────────
  static String get openFollowUpsTitle => getTranslatedString('FollowUpCall.openFollowUpsTitle', 'Open Follow-ups');
  static String get openFollowUpsLoadError => getTranslatedString('FollowUpCall.openFollowUpsLoadError', 'Failed to load follow-ups');
  static String get openFollowUpsEmpty => getTranslatedString('FollowUpCall.openFollowUpsEmpty', 'No open follow-ups');
  static String facilityLabel(String siteId) => getTranslatedString('FollowUpCall.facilityLabel', 'Facility: {siteId}', params: {'siteId': siteId});

  /// Localized label for a follow-up `kind` wire value (e.g. `medical_review`).
  static String kindLabel(String? kind) {
    switch ((kind ?? '').toLowerCase().trim()) {
      case 'medical_review':
      case 'medicalreview':
      case 'ncdmedicalreview':
        return getTranslatedString('FollowUp.medicalReview', 'Medical Review');
      case 'screening':
        return getTranslatedString('FollowUp.screening', 'Screening follow-up');
      case 'assessment':
        return getTranslatedString('FollowUp.assessment', 'Assessment follow-up');
      case 'referred':
      case 'referral':
        return getTranslatedString(
            'FollowUp.referred', 'Referral — confirm facility arrival');
      case 'household_visit':
      case 'householdvisit':
        return getTranslatedString(
            'FollowUp.householdVisit', 'Household visit due');
      case 'lost':
      case 'lost_to_follow_up':
        return getTranslatedString(
            'FollowUp.lost', 'Lost to follow-up check');
      case 'ncd':
        return getTranslatedString('FollowUp.ncd', 'NCD follow-up');
      case 'registered':
        return getTranslatedString('FollowUp.registered', 'Registered');
      case 'generic':
      case '':
        return getTranslatedString('FollowUp.generic', 'Follow-up');
      default:
        return getTranslatedString('FollowUp.generic', 'Follow-up');
    }
  }
}


/// Localized programme titles for UI badges/headers.
/// Prefers UHIS Bangla via `Worklist.programme*` keys in strings.json.
abstract final class ProgrammeLabels {
  ProgrammeLabels._();

  /// Service-selector chip for IMCI (distinct from visit badge "Child Visit").
  static String get childHealthService =>
      getTranslatedString('Worklist.serviceChildHealth', 'Child Health');

  static String of(Programme programme) {
    switch (programme) {
      case Programme.imci:
        return getTranslatedString('Worklist.programmeImci', 'Child Visit');
      case Programme.anc:
        return getTranslatedString('Worklist.programmeAnc', 'ANC');
      case Programme.pw:
        return getTranslatedString('Worklist.programmePw', 'PW');
      case Programme.pnc:
        return getTranslatedString('Worklist.programmePnc', 'PNC');
      case Programme.ncd:
        return getTranslatedString('Worklist.programmeNcd', 'NCD');
      case Programme.tb:
        return getTranslatedString('Worklist.programmeTb', 'TB Check');
      case Programme.epi:
        return getTranslatedString('Worklist.programmeEpi', 'Vaccination');
      case Programme.nutrition:
        return getTranslatedString('Worklist.programmeNutrition', 'Nutrition');
      case Programme.familyPlanning:
        return getTranslatedString(
            'Worklist.programmeFamilyPlanning', 'Family Planning');
      case Programme.cataract:
        return getTranslatedString('Worklist.programmeCataract', 'Cataract');
      case Programme.eyeCare:
        return getTranslatedString('Worklist.programmeEyeCare', 'Eye Care');
      case Programme.unknown:
        return getTranslatedString(
            'Worklist.programmeUnknown', 'Scheduled Visit');
    }
  }
}

abstract final class EnrollStrings {
  EnrollStrings._();

  static String get screenTitle => getTranslatedString('Enroll.screenTitle', 'Add Services');
  static String selectFor(String name) => getTranslatedString('selectFor', 'Select services for {name}', params: {'name': '$name'});
  static String get subtitle => getTranslatedString('Enroll.subtitle', 'Add the health programmes this person needs. Tap a programme to select it.');
  static String get sectionPregnancy => getTranslatedString('sectionPregnancy', 'PREGNANCY CARE');
  static String get sectionChronic => getTranslatedString('sectionChronic', 'CHRONIC CONDITIONS');
  static String get sectionChild => getTranslatedString('sectionChild', 'CHILD HEALTH');
  static String get pregnantWomanLabel => getTranslatedString('pregnantWomanLabel', 'Pregnant Woman');
  static String get pregnantWomanBengali => getTranslatedString('Enroll.pregnantWomanBengali', 'গর্ভবতী মা');
  static String get ancLabel => getTranslatedString('ancLabel', 'ANC Visit');
  static String get ancBengali => getTranslatedString('Enroll.ancBengali', 'মাতৃস্বাস্থ্য সেবা');
  static String get pncLabel => getTranslatedString('pncLabel', 'PNC Visit');
  static String get pncBengali => getTranslatedString('Enroll.pncBengali', 'প্রসবোত্তর সেবা');
  static String get ncdLabel => getTranslatedString('ncdLabel', 'NCD Check');
  static String get ncdBengali => getTranslatedString('Enroll.ncdBengali', 'অসংক্রামক রোগ');
  static String get imciLabel => getTranslatedString('imciLabel', 'Child Visit');
  static String get imciBengali => getTranslatedString('Enroll.imciBengali', 'শিশু স্বাস্থ্য সেবা');
  static String get epiLabel => getTranslatedString('epiLabel', 'Vaccination');
  static String get epiBengali => getTranslatedString('Enroll.epiBengali', 'টিকা');
  static String get lockedToastAnc => getTranslatedString('lockedToastAnc', '⚠ Select "Pregnant Woman" first to unlock ANC');
  static String get lockedToastPnc => getTranslatedString('lockedToastPnc', '⚠ Select "Pregnant Woman" first to unlock PNC');
  static String get noProgrammes => getTranslatedString('noProgrammes', 'No eligible programmes for this patient based on age and gender.');
  static String confirmCta(int n) => n == 0
      ? getTranslatedString('Enroll.confirmCtaEmpty', 'Select Programmes')
      : getTranslatedString('Enroll.confirmCtaSelected', 'Confirm Enrollment ({n} selected)',
          params: {'n': '$n'});
  static String get savedToast => getTranslatedString('Enroll.savedToast', 'Programmes saved ✓');
  static String get addServicesCta => getTranslatedString('addServicesCta', 'Add Services');
  static String get noServicesTitle => getTranslatedString('noServicesTitle', 'No services enrolled');
  static String get noServicesSubtitle => getTranslatedString('noServicesSubtitle', 'Tap below to add health programmes for this patient.');
}

abstract final class PregnancyRegStrings {
  PregnancyRegStrings._();

  static String get sheetTitle => getTranslatedString('PregnancyReg.sheetTitle', 'Register Pregnancy');
  static String forPatient(String name) => getTranslatedString('forPatient', 'For {name}', params: {'name': '$name'});
  static String get sectionDates => getTranslatedString('sectionDates', 'PREGNANCY DATES');
  static String get lmpLabel => getTranslatedString('PregnancyReg.lmpLabel', 'Last Menstrual Period (LMP)');
  static String get lmpRequired => getTranslatedString('lmpRequired', '* Required');
  static String get lmpHint => getTranslatedString('lmpHint', 'Tap to select date');
  static String get eddLabel => getTranslatedString('PregnancyReg.eddLabel', 'Est. Due Date (EDD)');
  static String get gaLabel => getTranslatedString('gaLabel', 'Gestational Age');
  static String get tooEarlyWarning => getTranslatedString('tooEarlyWarning', '⚠ LMP is less than 6 weeks ago. Only basic details saved — full risk screening at next visit.');
  static String get sectionHistory => getTranslatedString('sectionHistory', 'OBSTETRIC HISTORY');
  static String get gravidaLabel => getTranslatedString('gravidaLabel', 'Gravida (total pregnancies)');
  static String get parityLabel => getTranslatedString('parityLabel', 'Parity (live births)');
  static String get firstPregnancy => getTranslatedString('firstPregnancy', 'First pregnancy');
  static String get sectionRisk => getTranslatedString('sectionRisk', 'RISK SCREENING');
  static String ageRiskNormal(int age) => getTranslatedString('ageRiskNormal', 'Age {age} · Normal age for pregnancy', params: {'age': '$age'});
  static String ageRiskLow(int age) => getTranslatedString('ageRiskLow', '⚠ Age {age} · Under 18 — high risk', params: {'age': '$age'});
  static String ageRiskHigh(int age) => getTranslatedString('ageRiskHigh', '⚠ Age {age} · Over 35 — high risk', params: {'age': '$age'});
  static String get conditionsLabel => getTranslatedString('conditionsLabel', 'Any existing conditions?');
  static String get conditionHtn => getTranslatedString('conditionHtn', 'Hypertension / High BP');
  static String get conditionDiabetes => getTranslatedString('conditionDiabetes', 'Diabetes');
  static String get conditionCsection => getTranslatedString('conditionCsection', 'Previous C-section');
  static String get conditionComplicated => getTranslatedString('conditionComplicated', 'Previous complicated delivery');
  static String get registerCta => getTranslatedString('registerCta', '🤰  Register Pregnancy');
  static String get skipCta => getTranslatedString('skipCta', 'Skip for now');
  static String get savedToast => getTranslatedString('PregnancyReg.savedToast', 'Pregnancy registered ✓');
  static String get lmpRequiredError => getTranslatedString('lmpRequiredError', 'Please select the LMP date');
  static String get lmpFutureError => getTranslatedString('lmpFutureError', 'LMP cannot be in the future');
  static String get multiparaWarning => getTranslatedString('multiparaWarning', '⚠ Gravida > 4 — multipara risk');
}

/// Patient-scoped AI assistant (the floating "✦" sheet).
abstract final class PatientAiStrings {
  PatientAiStrings._();

  static String title(String name) => getTranslatedString('PatientAi.title', 'Ask about {name}', params: {'name': '$name'});
  static String get intro => getTranslatedString('intro', 'I have this patient\'s record. I\'ll answer only from their data — ask about their care, or tap an action below.');
  static String get inputHint => getTranslatedString('PatientAi.inputHint', 'Ask about this patient...');
  static String get scopeNote => getTranslatedString('scopeNote', '🔒 Answers limited to this patient');
  static String get noPhone => getTranslatedString('PatientAi.noPhone', 'No phone number on file for this patient');
  static String get dialFailed => getTranslatedString('PatientAi.dialFailed', 'Could not open the dialer');
  static String get fabTooltip => getTranslatedString('fabTooltip', 'Ask AI about this patient');

  static List<String> get starters => [
        getTranslatedString('PatientAi.starter1', 'Any danger signs to check?'),
        getTranslatedString('PatientAi.starter2', 'What should I do this visit?'),
        getTranslatedString('PatientAi.starter3', 'Is a referral needed?'),
      ];

  // Dynamic context-aware starters
  static String get starterFollowUpsOverdue => getTranslatedString(
      'PatientAi.starterFollowUpsOverdue', 'What follow-ups are overdue?');
  static String get starterDangerSigns => getTranslatedString(
      'PatientAi.starterDangerSigns', 'Any danger signs to act on now?');
  static String get starterAncProgress => getTranslatedString(
      'PatientAi.starterAncProgress', 'How is the ANC progress going?');
  static String get starterBpDiabetes => getTranslatedString(
      'PatientAi.starterBpDiabetes', 'Is her BP and diabetes under control?');
  static String get starterVaccines => getTranslatedString(
      'PatientAi.starterVaccines', 'Which vaccines are due or overdue?');
  static String get starterTb => getTranslatedString(
      'PatientAi.starterTb', 'Is she taking TB medication regularly?');
  static String get starterPnc => getTranslatedString(
      'PatientAi.starterPnc', 'What postnatal checks are needed?');
  static String get starterHighBp => getTranslatedString(
      'PatientAi.starterHighBp', 'What should I do about her high BP?');
  static String get starterLastVisit => getTranslatedString(
      'PatientAi.starterLastVisit', 'What happened at the last visit?');
  static String get starterReferral => getTranslatedString(
      'PatientAi.starterReferral', 'Does she need a referral today?');
}

abstract final class ConsentStrings {
  ConsentStrings._();

  static String get title => getTranslatedString('Consent.title', 'Data Collection Consent');
  static String get subtitle => getTranslatedString('Consent.subtitle', 'Apon Sushashthya Health Programme');
  static String get introText => getTranslatedString('introText', 'Before we register this household, we need your permission to collect and use health information for the purpose of providing community healthcare services.');
  static String get section1Title => getTranslatedString('section1Title', 'What we collect');
  static String get section1Body => getTranslatedString('section1Body', 'We collect names, ages, health conditions, visit records, and contact details of household members enrolled in the UHIS Leapfrog programme.');
  static String get section2Title => getTranslatedString('section2Title', 'How we use it');
  static String get section2Body => getTranslatedString('section2Body', 'Information is used by trained health workers to provide follow-up care, track programme outcomes, and improve community health services. It is never shared with third parties outside the programme.');
  static String get section3Title => getTranslatedString('section3Title', 'Your rights');
  static String get section3Body => getTranslatedString('section3Body', 'You may withdraw consent at any time by contacting your village health worker. Data will be retained as required by national health regulations.');
  static String get checkboxLabel => getTranslatedString('checkboxLabel', 'I have read and understood the above. I give consent for health data collection for members of this household.');
  static String get confirmButton => getTranslatedString('confirmButton', 'I Agree');
  static String get declineButton => getTranslatedString('declineButton', 'Decline');
  static String get declineWarning => getTranslatedString('declineWarning', 'Without consent, household registration cannot be completed.');
  static String get declineConfirm => getTranslatedString('declineConfirm', 'Cancel registration');
  static String get declineCancel => getTranslatedString('declineCancel', 'Go back');
}

/// Labels and coded values shown in the assessment detail sheets.
///
/// The sheets previously rendered wire codes verbatim — `HIGH_RISK_PW`,
/// `UNCONTROLLED_BP`, `Referred` — and English labels, so a Bangla SK read raw
/// enum names for clinical status.
abstract final class ClinicalStatusStrings {
  ClinicalStatusStrings._();

  /// Localized label for a backend status/customStatus code.
  ///
  /// Unknown codes fall back to a humanized form (`SOME_NEW_CODE` →
  /// `Some new code`), never the raw enum — a new backend value should read as
  /// awkward English, not as a database identifier.
  static String label(String raw) {
    final key = raw.trim().toUpperCase().replaceAll(' ', '_');
    return switch (key) {
      'HIGH_RISK_PW' => getTranslatedString(
          'ClinicalStatus.highRiskPw', 'High-risk pregnancy'),
      'NORMAL_PREGNANCY' => getTranslatedString(
          'ClinicalStatus.normalPregnancy', 'Normal pregnancy'),
      'UNCONTROLLED_BP' => getTranslatedString(
          'ClinicalStatus.uncontrolledBp', 'Uncontrolled blood pressure'),
      'CONTROLLED_BP' => getTranslatedString(
          'ClinicalStatus.controlledBp', 'Controlled blood pressure'),
      'UNCONTROLLED_BG' => getTranslatedString(
          'ClinicalStatus.uncontrolledBg', 'Uncontrolled blood sugar'),
      'CONTROLLED_BG' => getTranslatedString(
          'ClinicalStatus.controlledBg', 'Controlled blood sugar'),
      'REFERRED' =>
        getTranslatedString('ClinicalStatus.referred', 'Referred'),
      'ONTREATMENT' || 'ON_TREATMENT' => getTranslatedString(
          'ClinicalStatus.onTreatment', 'On treatment'),
      'RECOVERED' =>
        getTranslatedString('ClinicalStatus.recovered', 'Recovered'),
      'RBS' => getTranslatedString('ClinicalStatus.rbs', 'Random blood sugar'),
      'FBS' => getTranslatedString('ClinicalStatus.fbs', 'Fasting blood sugar'),
      'PPBS' => getTranslatedString(
          'ClinicalStatus.ppbs', 'Post-prandial blood sugar'),
      _ => _humanize(raw),
    };
  }

  /// Maps a comma/JSON list of codes through [label].
  static String labelAll(Iterable<String> codes) =>
      codes.map(label).where((s) => s.isNotEmpty).join(', ');

  static String _humanize(String raw) {
    final cleaned = raw.trim().replaceAll('_', ' ').toLowerCase();
    if (cleaned.isEmpty) return raw;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }
}

/// Row labels in the assessment detail sheets.
abstract final class PatientDetailStrings {
  PatientDetailStrings._();

  static String get gestationalAge =>
      getTranslatedString('PatientDetail.gestationalAge', 'Gestational age');

  /// `9 weeks 1 day`. Singular/plural is handled per unit — the previous
  /// implementation always said "days", producing "1 days".
  static String gestationalWeeksDays(String weeks, String days, {required bool oneDay}) =>
      getTranslatedString(
        oneDay
            ? 'PatientDetail.gaWeeksOneDay'
            : 'PatientDetail.gaWeeksDays',
        oneDay ? '{weeks} weeks {days} day' : '{weeks} weeks {days} days',
        params: {'weeks': weeks, 'days': days},
      );
  static String gestationalWeeksOnly(String weeks, {required bool oneWeek}) =>
      getTranslatedString(
        oneWeek ? 'PatientDetail.gaOneWeek' : 'PatientDetail.gaWeeks',
        oneWeek ? '{weeks} week' : '{weeks} weeks',
        params: {'weeks': weeks},
      );

  static String get status =>
      getTranslatedString('PatientDetail.status', 'Status');
  static String get referralStatus =>
      getTranslatedString('PatientDetail.referralStatus', 'Referral status');
  static String get referralReason =>
      getTranslatedString('PatientDetail.referralReason', 'Referral reason');
  static String get referredTo =>
      getTranslatedString('PatientDetail.referredTo', 'Referred to');
  static String get referralMade =>
      getTranslatedString('PatientDetail.referralMade', 'Referral made');

  // ── Detail-sheet / care-thread labels (localized) ───────────────────────
  static String get bp => getTranslatedString('PatientDetail.bp', 'BP');
  static String get bloodGlucose => getTranslatedString('PatientDetail.bloodGlucose', 'Blood glucose');
  static String get glucoseType => getTranslatedString('PatientDetail.glucoseType', 'Glucose type');
  static String get bmi => getTranslatedString('PatientDetail.bmi', 'BMI');
  static String get weightKg => getTranslatedString('PatientDetail.weightKg', 'Weight (kg)');
  static String get heightCm => getTranslatedString('PatientDetail.heightCm', 'Height (cm)');
  static String get cvdRisk => getTranslatedString('PatientDetail.cvdRisk', 'CVD risk');
  static String get diagnosis => getTranslatedString('PatientDetail.diagnosis', 'Diagnosis');
  static String get symptoms => getTranslatedString('PatientDetail.symptoms', 'Symptoms');
  static String get takingMedication => getTranslatedString('PatientDetail.takingMedication', 'Taking medication');
  static String get heartAttackHistory => getTranslatedString('PatientDetail.heartAttackHistory', 'Heart attack history');
  static String get strokeHistory => getTranslatedString('PatientDetail.strokeHistory', 'Stroke history');
  static String get kidneyDisease => getTranslatedString('PatientDetail.kidneyDisease', 'Kidney disease');
  static String get copd => getTranslatedString('PatientDetail.copd', 'COPD');
  static String get hb => getTranslatedString('PatientDetail.hb', 'Hb (g/dL)');
  static String get fundalHeight => getTranslatedString('PatientDetail.fundalHeight', 'Fundal height (cm)');
  static String get gravida => getTranslatedString('PatientDetail.gravida', 'Gravida');
  static String get parity => getTranslatedString('PatientDetail.parity', 'Parity');
  static String get livingChildren => getTranslatedString('PatientDetail.livingChildren', 'Living children');
  static String get pregnancyTest => getTranslatedString('PatientDetail.pregnancyTest', 'Pregnancy test');
  static String get ageOfLastChild => getTranslatedString('PatientDetail.ageOfLastChild', 'Age of last child');
  static String get ageOfLastChildDob => getTranslatedString('PatientDetail.ageOfLastChildDob', 'Age of last child (DOB)');
  static String get ancVisitNo => getTranslatedString('PatientDetail.ancVisitNo', 'ANC visit no.');
  static String get highRisk => getTranslatedString('PatientDetail.highRisk', 'High risk');
  static String get ancGaps => getTranslatedString('PatientDetail.ancGaps', 'ANC gaps');
  static String get dangerSigns => getTranslatedString('PatientDetail.dangerSigns', 'Danger signs');
  static String get followUpVisit => getTranslatedString('PatientDetail.followUpVisit', 'Follow-up visit');
  static String get pncVisitNo => getTranslatedString('PatientDetail.pncVisitNo', 'PNC visit no.');
  static String get modeOfDelivery => getTranslatedString('PatientDetail.modeOfDelivery', 'Mode of delivery');
  static String get complications => getTranslatedString('PatientDetail.complications', 'Complications');
  static String get complicationDetails => getTranslatedString('PatientDetail.complicationDetails', 'Complication details');
  static String get postnatalCare => getTranslatedString('PatientDetail.postnatalCare', 'Postnatal care');
  static String get newbornCare => getTranslatedString('PatientDetail.newbornCare', 'Newborn care');
  static String get previousComplications => getTranslatedString('PatientDetail.previousComplications', 'Previous complications');
  static String get existingIllness => getTranslatedString('PatientDetail.existingIllness', 'Existing illness');
  static String get onTreatment => getTranslatedString('PatientDetail.onTreatment', 'On treatment');
  static String get ttTdCompleted => getTranslatedString('PatientDetail.ttTdCompleted', 'TT/Td completed');
  static String get deliveryFacility => getTranslatedString('PatientDetail.deliveryFacility', 'Delivery facility');
  static String get lastAncWeightKg => getTranslatedString('PatientDetail.lastAncWeightKg', 'Last ANC weight (kg)');
  static String get lastAncVisit => getTranslatedString('PatientDetail.lastAncVisit', 'Last ANC visit');
  static String get deliveryDate => getTranslatedString('PatientDetail.deliveryDate', 'Delivery date');
  static String get cough => getTranslatedString('PatientDetail.cough', 'Cough');
  static String get coughOver2Weeks => getTranslatedString('PatientDetail.coughOver2Weeks', 'Cough >2 weeks');
  static String get nightSweats => getTranslatedString('PatientDetail.nightSweats', 'Night sweats');
  static String get fever => getTranslatedString('PatientDetail.fever', 'Fever');
  static String get weightLoss => getTranslatedString('PatientDetail.weightLoss', 'Weight loss');
  static String get illnessComplication => getTranslatedString('PatientDetail.illnessComplication', 'Illness/complication');
  static String get complicationType => getTranslatedString('PatientDetail.complicationType', 'Complication type');
  static String get vaccinesReceived => getTranslatedString('PatientDetail.vaccinesReceived', 'Vaccines received');
  static String get breastfeeding => getTranslatedString('PatientDetail.breastfeeding', 'Breastfeeding');
  static String get deworming => getTranslatedString('PatientDetail.deworming', 'Deworming');
  static String get referTo => getTranslatedString('PatientDetail.referTo', 'Refer to');
  static String get eyeTestOutcome => getTranslatedString('PatientDetail.eyeTestOutcome', 'Eye test outcome');
  static String get eyeDisease => getTranslatedString('PatientDetail.eyeDisease', 'Eye disease');
  static String get glassPower => getTranslatedString('PatientDetail.glassPower', 'Glass power');
  static String get glassesSold => getTranslatedString('PatientDetail.glassesSold', 'Glasses sold');
  static String get glassType => getTranslatedString('PatientDetail.glassType', 'Glass type');
  static String get frameType => getTranslatedString('PatientDetail.frameType', 'Frame type');
  static String get firstTimeUser => getTranslatedString('PatientDetail.firstTimeUser', 'First time user');
  static String get referredForOperation => getTranslatedString('PatientDetail.referredForOperation', 'Referred for operation');
  static String get operation => getTranslatedString('PatientDetail.operation', 'Operation');
  static String get postSurgeryStatus => getTranslatedString('PatientDetail.postSurgeryStatus', 'Post-surgery status');
  static String get ncdServiceProvided => getTranslatedString('PatientDetail.ncdServiceProvided', 'NCD service provided');
  static String get fpMethod => getTranslatedString('PatientDetail.fpMethod', 'FP method');
  static String get desireForChildren => getTranslatedString('PatientDetail.desireForChildren', 'Desire for children');
  static String get lmp => getTranslatedString('PatientDetail.lmp', 'LMP');
  static String get edd => getTranslatedString('PatientDetail.edd', 'EDD');
  static String get weeksRemaining => getTranslatedString('PatientDetail.weeksRemaining', 'Weeks remaining');
  static String weeksValue(Object n) => getTranslatedString(
        'PatientDetail.weeksValue',
        '$n weeks',
        params: {'n': '$n'},
      );
  static String get risk => getTranslatedString('PatientDetail.risk', 'Risk');
  static String get nearTerm => getTranslatedString('PatientDetail.nearTerm', 'Near term');
  static String get missedVisitsDetected => getTranslatedString('PatientDetail.missedVisitsDetected', 'Missed visits detected');
  static String get lastBp => getTranslatedString('PatientDetail.lastBp', 'Last BP');
  static String get haemoglobin => getTranslatedString('PatientDetail.haemoglobin', 'Haemoglobin');
  static String get weight => getTranslatedString('PatientDetail.weight', 'Weight');
  static String get gravidaParity => getTranslatedString('PatientDetail.gravidaParity', 'Gravida / Parity');
  static String get ancVisits => getTranslatedString('PatientDetail.ancVisits', 'ANC visits');
  static String get ncdVisits => getTranslatedString('PatientDetail.ncdVisits', 'NCD visits');
  static String get pncVisits => getTranslatedString('PatientDetail.pncVisits', 'PNC visits');
  static String get imciVisits => getTranslatedString('PatientDetail.imciVisits', 'IMCI visits');
  static String get tbVisits => getTranslatedString('PatientDetail.tbVisits', 'TB visits');
  static String get bloodSugar => getTranslatedString('PatientDetail.bloodSugar', 'Blood sugar');
  static String bloodSugarWithType(Object type) => getTranslatedString(
        'PatientDetail.bloodSugarWithType',
        'Blood sugar ($type)',
        params: {'type': '$type'},
      );
  static String get lastWeight => getTranslatedString('PatientDetail.lastWeight', 'Last weight');
  static String get delivery => getTranslatedString('PatientDetail.delivery', 'Delivery');
  static String get yes => getTranslatedString('PatientDetail.yes', 'Yes');
  static String get lastVisit => getTranslatedString('PatientDetail.lastVisit', 'Last visit');
  static String get nextDue => getTranslatedString('PatientDetail.nextDue', 'Next due');
  static String get assessmentsThisVisit => getTranslatedString('PatientDetail.assessmentsThisVisit', 'Assessments this visit');
  static String get visits => getTranslatedString('PatientDetail.visits', 'Visits');
  static String get overdue => getTranslatedString('PatientDetail.overdue', 'OVERDUE');
  static String get critical => getTranslatedString('PatientDetail.critical', 'CRITICAL');
  static String get highRiskBadge => getTranslatedString('PatientDetail.highRiskBadge', 'HIGH RISK');
  static String get monitoring => getTranslatedString('PatientDetail.monitoring', 'MONITORING');
  static String get pregnancy => getTranslatedString('PatientDetail.pregnancy', 'Pregnancy');
  static String get pregnancyOutcome => getTranslatedString('PatientDetail.pregnancyOutcome', 'Pregnancy Outcome');
  static String get antenatalCare => getTranslatedString('PatientDetail.antenatalCare', 'Antenatal Care');
  static String get postnatalCareCategory => getTranslatedString('PatientDetail.postnatalCareCategory', 'Postnatal Care');
  static String get onTreatmentBadge => getTranslatedString('PatientDetail.onTreatmentBadge', 'on treatment');
  static String band(Object n) => getTranslatedString(
        'PatientDetail.band',
        'Band $n',
        params: {'n': '$n'},
      );
  static String get pregnantSuffix => getTranslatedString('PatientDetail.pregnantSuffix', 'Pregnant');
  static String get editPlus => getTranslatedString('PatientDetail.editPlus', '+ Edit');

  /// NCD `referralFacilityType` wire value → UI label.
  static String ncdFacilityType(String raw) {
    final t = raw.trim();
    if (t == 'Community Clinic' || t == 'communityClinic') {
      return getTranslatedString(
        'Epi.referralFacility.communityClinic',
        'Community Clinic',
      );
    }
    if (t == 'Upazila Health Complex' || t == 'upazilaHealthComplex') {
      return getTranslatedString(
        'VisitFlow.referralDestinationUpazilaHealthComplex',
        'Upazila Health Complex',
      );
    }
    return t;
  }

}

abstract final class CareThreadStrings {
  CareThreadStrings._();

  static String get anc => getTranslatedString('anc', 'ANC / Pregnancy');
  static String get bp => getTranslatedString('bp', 'Pre-eclampsia watch');
  static String get sugar => getTranslatedString('sugar', 'Blood sugar');
  static String get htn => getTranslatedString('htn', 'Hypertension');
  static String get imm => getTranslatedString('imm', 'Immunization');
  static String get growth => getTranslatedString('growth', 'Growth monitoring');
  static String get pnc => getTranslatedString('pnc', 'Postnatal recovery');
  static String get newborn => getTranslatedString('newborn', 'Newborn care');
  static String get general => getTranslatedString('general', 'Registered');
  static String get illness => getTranslatedString('illness', 'Past illness');
  static String get highrisk => getTranslatedString('highrisk', 'High-risk pregnancy');
  static String get csection => getTranslatedString('csection', 'Emergency C-section');
}

/// Debug-only offline SQLCipher DB browser (`DebugDbViewerScreen`).
///
/// Codes are namespaced because the bare keys (`title`, `close`, `refresh`,
/// `searchHint`) are already claimed by other features in `strings.json`.
abstract final class DebugDbStrings {
  DebugDbStrings._();

  static String get title => getTranslatedString('DebugDb.title', 'Offline Database');
  static String get subtitle => getTranslatedString('DebugDb.subtitle', 'Local SQLCipher tables');
  static String get refresh => getTranslatedString('DebugDb.refresh', 'Refresh');
  static String get close => getTranslatedString('DebugDb.close', 'Close');
  static String get searchHint => getTranslatedString('DebugDb.searchHint', 'Search rows…');
  static String get emptyTable => getTranslatedString('DebugDb.emptyTable', 'No rows');
  static String get counting => getTranslatedString('DebugDb.counting', 'Counting…');
  static String get countFailed => getTranslatedString('DebugDb.countFailed', 'Count failed');
  static String get prevPage => getTranslatedString('DebugDb.prevPage', 'Previous page');
  static String get nextPage => getTranslatedString('DebugDb.nextPage', 'Next page');

  static String loadError(String error) => getTranslatedString(
      'DebugDb.loadError', 'Could not read the database: {error}',
      params: {'error': error});

  /// Header line, e.g. `24 tables · 1830 rows`.
  static String summary(int tables, int rows) => getTranslatedString(
      'DebugDb.summary', '{tables} tables · {rows} rows',
      params: {'tables': '$tables', 'rows': '$rows'});

  static String rowCount(int n) =>
      getTranslatedString('DebugDb.rowCount', '{n} rows', params: {'n': '$n'});

  static String columnCount(int n) => getTranslatedString(
      'DebugDb.columnCount', '{n} cols',
      params: {'n': '$n'});

  /// Pagination line, e.g. `Showing 1–50 of 320`.
  static String pageLabel(int from, int to, int total) => getTranslatedString(
      'DebugDb.pageLabel', 'Showing {from}–{to} of {total}',
      params: {'from': '$from', 'to': '$to', 'total': '$total'});
}
