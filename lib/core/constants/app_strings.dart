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

import '../../features/visit/immunisation/epi_visit_summary.dart';
import '../i18n/app_locale.dart';
import '../models/dashboard_tier.dart';

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
String getTranslatedString(String code, String fallback, {Map<String, String>? params}) {
  final entry = _translations?[code];
  var result = entry?[AppLocale.isBangla ? 'bn' : 'en'];
  // Prefer the translated entry; otherwise use the English fallback. Params must
  // still be applied in the fallback path — DebugDb / Settings keys often have
  // no strings.json entry yet, and '{n} rows' must not render literally.
  result = (result == null || result.isEmpty) ? fallback : result;
  if (params != null) {
    for (final param in params.entries) {
      result = result!.replaceAll('{${param.key}}', param.value);
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
  static String versionLabel(String version) => getTranslatedString('versionLabel', 'v{version}', params: {'version': version});
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
  static String get verifyToAccess => getTranslatedString('verifyToAccess', 'Verify your identity to access your ward dashboard.');
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
  static String progressPercent(int pct) =>
      getTranslatedString('OfflineSync.progressPercent', '$pct%');
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
  static String get bloodPressure => getTranslatedString('bloodPressure', 'Blood Pressure');
  static String get bloodGlucose => getTranslatedString('bloodGlucose', 'Blood Glucose');
  static String get clinicalNotes => getTranslatedString('clinicalNotes', 'Clinical Notes');
  static String get chiefComplaints => getTranslatedString('chiefComplaints', 'Chief Complaints');
  static String get comorbidities => getTranslatedString('comorbidities', 'Comorbidities');
  static String get complications => getTranslatedString('complications', 'Complications');
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
  static String nid(Object nid) => getTranslatedString('nid', 'NID {nid}', params: {'nid': '$nid'});
  static String householdNo(Object no) => getTranslatedString('householdNo', 'No {no}', params: {'no': '$no'});
  static String memberCount(Object count) => getTranslatedString('memberCount', '{count} members', params: {'count': '$count'});
  static String get scanNidTooltip => getTranslatedString('scanNidTooltip', 'Scan NID or QR to find patient');
  static String get scanSearchTitle => getTranslatedString('scanSearchTitle', 'Scan to Search');
  static String get scanSearchSubtitle => getTranslatedString('scanSearchSubtitle', 'Point at NID card or QR code');
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
}

/// First-login data sync: the guided "downloading your ward" gate and the
/// dashboard data-freshness badge.
abstract final class SyncStrings {
  SyncStrings._();

  static String get title => getTranslatedString('Sync.title', 'Setting up your ward');
  static String get subtitle => getTranslatedString('Sync.subtitle', 'Downloading your households and patients so you can work offline.');

  // Per-entity labels used in progress lines and the data-as-of badge.
  static String get households => getTranslatedString('Sync.households', 'households');
  static String get members => getTranslatedString('members', 'members');
  static String get patients => getTranslatedString('Sync.patients', 'patients');

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

  static String householdsCount(int n) => getTranslatedString('householdsCount', '{n} households', params: {'n': '$n'});
  static String membersCount(int n) => getTranslatedString('membersCount', '{n} members', params: {'n': '$n'});

  // Header (v13 mockup: navy header, 🏠 title, combined live count)
  static String get headerTitle => getTranslatedString('headerTitle', '🏠 Households & Patients');
  static String headerSummary(int households, int patients) =>
      '${householdsCount(households)} · ${_patientsCount(patients)}';
  static String _patientsCount(int n) => AppLocale.isBangla
      ? '$n জন রোগী'
      : '$n patient${n == 1 ? '' : 's'}';
  static String get searchHint => getTranslatedString('HouseholdList.searchHint', 'Search by name, house no. or village…');

  // Household-card inline other-members panel
  static String otherMembersToggle(int n) => AppLocale.isBangla
      ? '+$n জন অন্যান্য পরিবার সদস্য'
      : '+$n other household member${n == 1 ? '' : 's'}';
  static String get enrolledTag => getTranslatedString('enrolledTag', 'Enrolled');

  // Manual server refresh
  static String refreshSummary(int patients, int assessments, int followUps) => getTranslatedString('refreshSummary', 'Updated: {patients} patients · {assessments} assessments · {followUps} follow-ups', params: {'patients': '$patients', 'assessments': '$assessments', 'followUps': '$followUps'});
  static String refreshFailed(String error) => getTranslatedString('HouseholdList.refreshFailed', 'Refresh failed: {error}', params: {'error': '$error'});
}

/// Household detail screen strings.
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
}

/// AI Worklist (Screen 2): chip filter labels, programme tags, urgent banner,
/// last-synced strip, and the empty/error states. All literal copy for the
/// worklist surface lives here — widgets never inline strings.
abstract final class WorklistStrings {
  WorklistStrings._();

  static String get urgencyToday => getTranslatedString('Worklist.urgencyToday', 'Today');
  static String get urgencyThisWeek => getTranslatedString('Worklist.urgencyThisWeek', 'This week');
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
  static const String greetingBangla = 'আপনাদের কেমন আছেন? রোগী কেমন আছে?';
  static const String greetingEnglish =
      'How is everyone? How is the patient today?';
  static String aiSummaryLead(String name) => getTranslatedString('aiSummaryLead', '{name} has the following risk drivers worth addressing today.', params: {'name': '$name'});

  static String get allAssessmentsTitle => getTranslatedString('allAssessmentsTitle', 'All assessments');

  // ── Header ────────────────────────────────────────────────────────────
  static String get urgentBadge => getTranslatedString('PatientContext.urgentBadge', 'URGENT');
  static String ageLabel(int age) => getTranslatedString('PatientContext.ageLabel', 'Age {age}', params: {'age': '$age'});
  static String ageMonthsLabel(int months) => AppLocale.isBangla
      ? '$months মাস'
      : '$months month${months == 1 ? '' : 's'}';
  static String get ageUnderOneYear => getTranslatedString('ageUnderOneYear', '< 1 yr');
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
  static String glucoseLabel(String? type) {
    if (AppLocale.isBangla) {
      return type != null ? 'গ্লুকোজ ($type)' : 'গ্লুকোজ';
    }
    return type != null ? 'Glucose ($type)' : 'Glucose';
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
  static String viewPatientSemantics(String name, int? age) => AppLocale.isBangla
      ? 'রোগী $name${age != null ? ', বয়স $age' : ''} দেখুন'
      : 'View patient $name${age != null ? ', age $age' : ''}';

  static String get statusIndicatorsTitle => getTranslatedString('statusIndicatorsTitle', 'Status Indicators');

  // ── Assessment list fallbacks ────────────────────────────────────────
  static String get genericAssessmentLabel => getTranslatedString('genericAssessmentLabel', 'Assessment');
  static String viewAssessmentSemantics(String type, String date) => getTranslatedString('viewAssessmentSemantics', 'View {type} assessment on {date}', params: {'type': '$type', 'date': '$date'});
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
  static String get aiInsightNotSynced => AppLocale.isBangla
      ? 'অফলাইন মোডে তথ্য পাওয়া যাচ্ছে না'
      : 'Data not available in offline mode';
  static String get enrolledInApp => getTranslatedString('enrolledInApp', 'Enrolled in Apon Sushashthya');
  static String get enrollmentMilestone => getTranslatedString('enrollmentMilestone', 'Enrollment date');
  static String get pregnancyRegistered => getTranslatedString('pregnancyRegistered', 'Pregnancy Registered');
  static String get pregnancyRegistrationCategory => getTranslatedString('pregnancyRegistrationCategory', 'Pregnancy Registration');
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
  static const List<String> defaultReferralReasons = [
    'High blood pressure',
    'High blood glucose',
    'Danger signs in pregnancy',
    'Severe malnutrition',
    'Danger signs in child',
    'TB symptoms',
    'Post-referral follow-up',
    'Other',
  ];

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
    if (AppLocale.isBangla) {
      if (villageCount <= 0) return 'কোনো গ্রাম নির্ধারিত নেই';
      if (villageCount == 1) return '1 গ্রাম';
      return '$villageCount টি গ্রাম';
    }
    if (villageCount <= 0) return 'No villages assigned';
    if (villageCount == 1) return '1 village';
    return '$villageCount villages';
  }

  static String get referralAlertsLabel => getTranslatedString('referralAlertsLabel', 'Referral alerts need follow-up');
  static String get tapToFollowUp => getTranslatedString('tapToFollowUp', 'Tap to follow up →');
  static String get referralCceComingSoon => getTranslatedString('referralCceComingSoon', 'CCE integration coming soon');
  static String get visitStartFailed => getTranslatedString('visitStartFailed', 'Could not start visit. Try again from the patient screen.');
  static String get visitMissingPatient => getTranslatedString('visitMissingPatient', 'No patient record — open the case to begin.');
  static String houseNumber(String no) => getTranslatedString('houseNumber', '#{no}', params: {'no': '$no'});
  static String moreVisits(int n) {
    if (AppLocale.isBangla) {
      return n == 1 ? '+ আরও 1টি ভিজিট আজ' : '+ আরও $n টি ভিজিট আজ';
    }
    return n == 1 ? '+ 1 more visit today' : '+ $n more visits today';
  }
  static String todaysVisits(String date) => getTranslatedString('todaysVisits', 'Today\'s visits · {date}', params: {'date': '$date'});
  static String get filterByLocation => getTranslatedString('filterByLocation', 'Village · SS · Area');
  static String get upcomingWorkHeader => getTranslatedString('upcomingWorkHeader', 'Upcoming work — earliest first');
  static String get aiSortedBadge => getTranslatedString('aiSortedBadge', '✦ sorted');

  /// Badge copy for the dashboard header — always the unfiltered today count.
  static String aiSortedVisitsToday(int n) {
    if (AppLocale.isBangla) {
      return n == 1 ? '✦ সাজানো 1 টি ভিজিট আজ' : '✦ সাজানো $n টি ভিজিট আজ';
    }
    return n == 1
        ? '✦ 1 visit today'
        : '✦ $n visits today';
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
  static String workloadHours(double hours) => AppLocale.isBangla
      ? '${hours.toStringAsFixed(1)} ঘণ্টা'
      : '${hours.toStringAsFixed(1)} Hours';

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
  static String childReferralOverdue(int days) => AppLocale.isBangla
      ? '$days শিশু রেফারেল বকেয়া'
      : '$days Child Referral${days == 1 ? '' : 's'} Overdue';
  static String highRiskPregnancyWaiting(String name, String duration) => getTranslatedString('highRiskPregnancyWaiting', '{name}: High-risk pregnancy waiting {duration} for OB review.', params: {'name': '$name', 'duration': '$duration'});

  // ── Mission Queue Card ───────────────────────────────────────────────────
  static String priorityRank(int rank) => getTranslatedString('priorityRank', 'Priority #{rank}', params: {'rank': '$rank'});
  static String daysOverdue(int days) => getTranslatedString('daysOverdue', '{days} Days Overdue', params: {'days': '$days'});
  static String get aiInsight => getTranslatedString('MissionDashboard.aiInsight', 'AI Insight');

  // ── Programme-smart reason badge (v13 design) ───────────────────────────
  static String get enrolled => getTranslatedString('MissionDashboard.enrolled', 'Enrolled');
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
  static String get today => getTranslatedString('MissionDashboard.today', 'Today');
  static String daysAway(int days) {
    if (days == 0) return today;
    if (days == 1) return tomorrow;
    return AppLocale.isBangla ? '$days দিনের মধ্যে' : 'In $days days';
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

  // ── "+ Enrol new" FAB ────────────────────────────────────────────────────
  static String get enrolNewCta => getTranslatedString('enrolNewCta', 'Enroll new');
  static String get enrolNewComingSoon => getTranslatedString('enrolNewComingSoon', 'QR enrolment flow coming soon. Use the Patients tab to view existing patients.');

  // ── Status pills (compact tier label shown in the card right-side pill) ───
  static String get statusPillNow => getTranslatedString('statusPillNow', 'Now');
  static String get statusPillOverdue => getTranslatedString('statusPillOverdue', 'Overdue');
  static String get statusPillToday => getTranslatedString('statusPillToday', 'Today');
  static String get statusPillThisWeek => getTranslatedString('statusPillThisWeek', 'This week');
  static String get statusPillRoutine => getTranslatedString('statusPillRoutine', 'Routine');

  static String statusPillForTier(DashboardTier tier) {
    switch (tier) {
      case DashboardTier.critical:
        // Folds into "Overdue" (red) rather than "Today" — only 3 status
        // labels (Today/This week/Overdue) are meant to reach the SK, and
        // critical is more urgent than a plain date-driven "Today".
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
    if (AppLocale.isBangla) {
      switch (tag) {
        case 'sla-breached':
          return 'রেফারেল SLA লঙ্ঘিত হয়েছে';
        case 'red-flag':
          return 'রেড-ফ্ল্যাগ রোগী';
        case 'hi-risk-anc-gap':
          return 'ANC ব্যবধানসহ উচ্চ-ঝুঁকিপূর্ণ গর্ভাবস্থা';
        case 'neonate':
          return 'নবজাতক (28 দিনের কম)';
        case 'young-infant':
          return 'শিশু (60 দিনের কম)';
        case 'pnc-window':
          return 'প্রসবোত্তর (42 দিনের মধ্যে)';
        case 'anc-near-term':
          return 'প্রসবের কাছাকাছি গর্ভাবস্থা (EDD 14 দিনের মধ্যে)';
        case 'delivery-complication':
          return 'প্রসবকালীন জটিলতা রেকর্ড করা হয়েছে';
        case 'pnc-illness':
          return 'প্রসবোত্তর অসুস্থতা রিপোর্ট করা হয়েছে';
        case 'ltfu-streak':
          return 'ধারাবাহিক ফলো-আপ হারানো';
        case 'tb-default-risk':
          return 'TB চিকিৎসা — ডিফল্ট ঝুঁকি';
        case 'ncd-drift':
          return 'NCD চিকিৎসা বকেয়া';
        case 'referral-arrival-pending':
          return 'রেফারেল আগমনের অপেক্ষায়';
        case 'child-disability':
          return 'প্রতিবন্ধী 5 বছরের কম বয়সী শিশু';
        default:
          return 'ক্লিনিক্যাল অগ্রাধিকার সংকেত';
      }
    }
    switch (tag) {
      case 'sla-breached':
        return 'Referral SLA breached';
      case 'red-flag':
        return 'Red-flag patient';
      case 'hi-risk-anc-gap':
        return 'High-risk pregnancy with ANC gap';
      case 'neonate':
        return 'Neonate (under 28 days)';
      case 'young-infant':
        return 'Young infant (under 60 days)';
      case 'pnc-window':
        return 'Postpartum (within 42 days)';
      case 'anc-near-term':
        return 'Near-term pregnancy (EDD within 14 days)';
      case 'delivery-complication':
        return 'Delivery complications recorded';
      case 'pnc-illness':
        return 'Postnatal illness reported';
      case 'ltfu-streak':
        return 'Lost-to-follow-up streak';
      case 'tb-default-risk':
        return 'TB treatment — default risk';
      case 'ncd-drift':
        return 'NCD treatment overdue';
      case 'referral-arrival-pending':
        return 'Referral pending arrival';
      case 'child-disability':
        return 'Child under 5 with disability';
      default:
        return 'Clinical priority signal';
    }
  }

  // ── Notification drawer ──────────────────────────────────────────────────
  static String get notificationsTitle => getTranslatedString('notificationsTitle', 'Notifications');
  static String get close => getTranslatedString('MissionDashboard.close', 'Close');
  static String get noNewNotifications => getTranslatedString('noNewNotifications', 'No new notifications');
  static String get cceEscalations => getTranslatedString('cceEscalations', 'CCE escalations');
  static String criticalReferralsSubtitle(int count) => AppLocale.isBangla
      ? '$count টি জরুরি রেফারেলের তাৎক্ষণিক মনোযোগ প্রয়োজন'
      : '$count critical referral${count == 1 ? '' : 's'} need immediate attention';
  static String pendingReferralsSubtitle(int count) => AppLocale.isBangla
      ? '$count টি অমীমাংসিত রেফারেল ফলো-আপের অপেক্ষায়'
      : '$count pending referral${count == 1 ? '' : 's'} awaiting follow-up';
  static String get viewAll => getTranslatedString('viewAll', 'View all');
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
  static const String skAsksBangla = 'রোগী কেমন আছে? কতদিন হলো অসুস্থ?';
  static const String skAsksEnglish =
      'How is the patient? How many days unwell?';

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

  static String uploadProgress(double pct) =>
      'Uploading…  ${pct.toStringAsFixed(0)}%';
  static String recordingTimer(int secs) {
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return 'Recording…  $mm:$ss';
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

  // ── Symptom labels ───────────────────────────────────────────────────────
  // Danger signs
  static const String symptomConvulsions = 'Fits / Convulsions';
  static const String symptomUnconscious = 'Unconscious / Unresponsive';
  static const String symptomLethargy = 'Unusually sleepy / Difficult to wake';
  static const String symptomNotEating = 'Not eating / drinking';
  static const String symptomChestIndrawing = 'Chest in-drawing';
  static const String symptomStridor = 'Stridor (noisy breathing)';
  static const String symptomVaginalBleeding = 'Vaginal bleeding';
  static const String symptomWaterBreak = 'Water break / Leaking';
  static const String symptomReducedFetalMovement = 'Baby not moving';
  static const String symptomChestPain = 'Chest pain';
  static const String symptomHemoptysis = 'Blood in sputum';

  // Fever & respiratory
  static const String symptomFever = 'Fever';
  static const String symptomCough = 'Cough';
  static const String symptomCoughOver2Weeks = 'Cough > 2 weeks';
  static const String symptomDifficultyBreathing = 'Difficulty breathing';
  static const String symptomFastBreathing = 'Fast breathing';
  static const String symptomShortnessBreath = 'Shortness of breath';

  // GI & nutrition
  static const String symptomDiarrhea = 'Diarrhea';
  static const String symptomBloodyDiarrhea = 'Bloody diarrhea';
  static const String symptomVomiting = 'Vomiting';
  static const String symptomLossAppetite = 'Loss of appetite';
  static const String symptomMuacRed = 'MUAC red zone';
  static const String symptomVisibleWasting = 'Visible wasting';
  static const String symptomEdemaBothFeet = 'Edema of both feet';
  static const String symptomWeightLoss = 'Weight loss';

  // Maternal
  static const String symptomPregnant = 'Pregnant / suspected';
  static const String symptomHeadacheSevere = 'Severe headache';
  static const String symptomBlurredVision = 'Blurred vision';
  static const String symptomAbdominalPain = 'Abdominal pain';
  static const String symptomSwellingFaceHands = 'Swelling';
  static const String symptomHighBpKnown = 'High BP known / suspected';
  static const String symptomLaborSigns = 'Labor signs';

  // NCD / metabolic
  static const String symptomDizziness = 'Dizziness';
  static const String symptomNumbness = 'Numbness / Tingling';
  static const String symptomPolyuria = 'Frequent urination';
  static const String symptomPolydipsia = 'Excessive thirst';
  static const String symptomFootPain = 'Foot pain';
  static const String symptomFootWound = 'Foot wound';

  // TB indicators
  static const String symptomNightSweats = 'Night sweats';
  static const String symptomFatigue = 'Fatigue';
  static const String symptomTbContact = 'TB contact history';

  // Mental health
  static const String symptomFeelingSad = 'Feeling sad / hopeless';
  static const String symptomAnxiety = 'Anxiety / Worry';
  static const String symptomSleepDifficulty = 'Difficulty sleeping';

  // Child health
  static const String symptomEarProblem = 'Ear problem';
  static const String symptomSkinRash = 'Skin rash';
  static const String symptomEyeDischarge = 'Eye discharge';
  static const String symptomUmbilicusRed = 'Umbilicus red / discharge';
  static const String symptomJaundice = 'Jaundice (yellow skin / eyes)';

  // ── AI Scribe vocab — codes present in [AiScribeTriageVocab.codes] that
  // don't have a [UnifiedSymptomCatalog] entry. Vocab is the Step 1 source of
  // truth; these labels render in the Step 1 chips + "Add symptom" sheet.
  static const String symptomHeavyBleeding = 'Heavy bleeding';
  static const String symptomFoulSmellingVaginalDischarge =
      'Foul-smelling vaginal discharge';
  static const String symptomEpigastricPain = 'Epigastric pain';
  static const String symptomHeadache = 'Headache';
  static const String symptomEdema = 'Edema';
  static const String symptomBreastPain = 'Breast pain';
  static const String symptomBreastSwelling = 'Breast swelling';
  static const String symptomPerinealWoundDischarge =
      'Perineal wound discharge';
  static const String symptomPainfulUrination = 'Painful urination';
  static const String symptomBreathlessness = 'Breathlessness';
  static const String symptomLeakingFluidVagina = 'Leaking fluids';
  static const String symptomPainfulUterineContractions =
      'Painful uterine contractions';
  static const String symptomOneSidedWeakness = 'One-sided weakness';
  static const String symptomSwellingBothFeet = 'Swelling of both feet';
  static const String symptomPalpitations = 'Palpitations';
  static const String symptomSwellingOneLeg = 'Swelling of one leg';
  static const String symptomExcessiveThirst = 'Excessive thirst';
  static const String symptomFootNumbness = 'Foot numbness';
  static const String symptomWeakness = 'Weakness';

  // ── Bangla symptom labels (shown as sub-label in tile) ───────────────────
  // Danger signs
  static const String symptomConvulsionsBn = 'খিঁচুনি';
  static const String symptomUnconsciousBn = 'অজ্ঞান / সাড়া নেই';
  static const String symptomLethargyBn = 'অস্বাভাবিক ঘুম ঘুম';
  static const String symptomNotEatingBn = 'খাচ্ছে না';
  static const String symptomChestIndrawingBn = 'বুক ঢুকে যাওয়া';
  static const String symptomStridorBn = 'শব্দ করে শ্বাস';
  static const String symptomVaginalBleedingBn = 'যোনিপথে রক্তপাত';
  static const String symptomWaterBreakBn = 'পানি ভাঙা';
  static const String symptomReducedFetalMovementBn = 'শিশুর নড়াচড়া কম';
  static const String symptomChestPainBn = 'বুকে ব্যথা';
  static const String symptomHemoptysisBn = 'কফে রক্ত';
  // Fever & respiratory
  static const String symptomFeverBn = 'জ্বর আছে?';
  static const String symptomCoughBn = 'কাশি আছে?';
  static const String symptomCoughOver2WeeksBn = '২ সপ্তাহ+ কাশি';
  static const String symptomDifficultyBreathingBn = 'শ্বাস নিতে কষ্ট';
  static const String symptomFastBreathingBn = 'দ্রুত শ্বাস';
  static const String symptomShortnessBreathBn = 'শ্বাসকষ্ট';
  // GI & nutrition
  static const String symptomDiarrheaBn = 'পাতলা পায়খানা';
  static const String symptomBloodyDiarrheaBn = 'রক্ত মিশ্রিত পায়খানা';
  static const String symptomVomitingBn = 'বমি হচ্ছে';
  static const String symptomLossAppetiteBn = 'খাওয়ার রুচি নেই';
  static const String symptomMuacRedBn = 'MUAC লাল';
  static const String symptomVisibleWastingBn = 'দেহ শীর্ণ';
  static const String symptomEdemaBothFeetBn = 'দুই পা ফোলা';
  static const String symptomWeightLossBn = 'ওজন কমে যাওয়া';
  // Maternal
  static const String symptomPregnantBn = 'গর্ভবতী';
  static const String symptomHeadacheSevereBn = 'তীব্র মাথাব্যথা';
  static const String symptomBlurredVisionBn = 'ঝাপসা দৃষ্টি';
  static const String symptomAbdominalPainBn = 'পেটে ব্যথা';
  static const String symptomSwellingFaceHandsBn = 'মুখ / হাত ফোলা';
  static const String symptomHighBpKnownBn = 'উচ্চ রক্তচাপ';
  static const String symptomLaborSignsBn = 'প্রসব লক্ষণ';
  // Eye
  static const String symptomEyePainBn = 'চোখে ব্যথা';
  static const String symptomGradualVisionLossBn = 'ধীরে দৃষ্টি কমছে';
  static const String symptomReducedVisionBn = 'দৃষ্টিশক্তি কমা';
  // Family planning
  static const String symptomNoFamilyPlanningBn = 'পরিবার পরিকল্পনা নেই';
  static const String symptomWantsContraceptionBn = 'গর্ভনিরোধক চান';
  // NCD / metabolic
  static const String symptomDizzinessBn = 'মাথা ঘোরা';
  static const String symptomNumbnessBn = 'অবশ / ঝিনঝিন';
  static const String symptomPolyuriaBn = 'ঘন ঘন প্রস্রাব';
  static const String symptomPolydipsiaBn = 'অতিরিক্ত তৃষ্ণা';
  static const String symptomFootPainBn = 'পায়ে ব্যথা';
  static const String symptomFootWoundBn = 'পায়ে ঘা';
  // TB indicators
  static const String symptomNightSweatsBn = 'রাতে ঘাম';
  static const String symptomFatigueBn = 'ক্লান্তি';
  static const String symptomTbContactBn = 'যক্ষ্মা রোগীর সংস্পর্শ';
  // Mental health
  static const String symptomFeelingSadBn = 'মন খারাপ / হতাশ';
  static const String symptomAnxietyBn = 'উদ্বেগ / দুশ্চিন্তা';
  static const String symptomSleepDifficultyBn = 'ঘুমের সমস্যা';
  // Child health
  static const String symptomEarProblemBn = 'কানের সমস্যা';
  static const String symptomSkinRashBn = 'চামড়ায় দাগ';
  static const String symptomEyeDischargeBn = 'চোখ দিয়ে পুঁজ';
  static const String symptomUmbilicusRedBn = 'নাভি লাল / পুঁজ';
  static const String symptomJaundiceBn = 'জন্ডিস (হলুদ ত্বক)';

  /// Returns the Bangla sub-label for a symptom code, or null if not translated.
  static String? symptomBangla(String code) {
    switch (code) {
      case 'convulsions':
        return symptomConvulsionsBn;
      case 'unconscious':
        return symptomUnconsciousBn;
      case 'lethargy':
        return symptomLethargyBn;
      case 'not_eating':
        return symptomNotEatingBn;
      case 'chest_indrawing':
        return symptomChestIndrawingBn;
      case 'stridor':
        return symptomStridorBn;
      case 'vaginal_bleeding':
        return symptomVaginalBleedingBn;
      case 'water_break':
        return symptomWaterBreakBn;
      case 'reduced_fetal_movement':
        return symptomReducedFetalMovementBn;
      case 'chest_pain':
        return symptomChestPainBn;
      case 'hemoptysis':
        return symptomHemoptysisBn;
      case 'fever':
        return symptomFeverBn;
      case 'cough':
        return symptomCoughBn;
      case 'cough_over_2_weeks':
        return symptomCoughOver2WeeksBn;
      case 'difficulty_breathing':
        return symptomDifficultyBreathingBn;
      case 'fast_breathing':
        return symptomFastBreathingBn;
      case 'shortness_breath':
        return symptomShortnessBreathBn;
      case 'diarrhea':
        return symptomDiarrheaBn;
      case 'bloody_diarrhea':
        return symptomBloodyDiarrheaBn;
      case 'vomiting':
        return symptomVomitingBn;
      case 'loss_appetite':
        return symptomLossAppetiteBn;
      case 'muac_red':
        return symptomMuacRedBn;
      case 'visible_wasting':
        return symptomVisibleWastingBn;
      case 'edema_both_feet':
        return symptomEdemaBothFeetBn;
      case 'weight_loss':
        return symptomWeightLossBn;
      case 'pregnant':
        return symptomPregnantBn;
      case 'headache_severe':
        return symptomHeadacheSevereBn;
      case 'blurred_vision':
        return symptomBlurredVisionBn;
      case 'abdominal_pain':
        return symptomAbdominalPainBn;
      case 'swelling_face_hands':
        return symptomSwellingFaceHandsBn;
      case 'high_bp_known':
        return symptomHighBpKnownBn;
      case 'labor_signs':
        return symptomLaborSignsBn;
      case 'eye_pain':
        return symptomEyePainBn;
      case 'gradual_vision_loss':
        return symptomGradualVisionLossBn;
      case 'reduced_vision':
        return symptomReducedVisionBn;
      case 'no_family_planning':
        return symptomNoFamilyPlanningBn;
      case 'wants_contraception':
        return symptomWantsContraceptionBn;
      case 'dizziness':
        return symptomDizzinessBn;
      case 'numbness':
        return symptomNumbnessBn;
      case 'polyuria':
        return symptomPolyuriaBn;
      case 'polydipsia':
        return symptomPolydipsiaBn;
      case 'foot_pain':
        return symptomFootPainBn;
      case 'foot_wound':
        return symptomFootWoundBn;
      case 'night_sweats':
        return symptomNightSweatsBn;
      case 'fatigue':
        return symptomFatigueBn;
      case 'tb_contact':
        return symptomTbContactBn;
      case 'feeling_sad':
        return symptomFeelingSadBn;
      case 'anxiety':
        return symptomAnxietyBn;
      case 'sleep_difficulty':
        return symptomSleepDifficultyBn;
      case 'ear_problem':
        return symptomEarProblemBn;
      case 'skin_rash':
        return symptomSkinRashBn;
      case 'eye_discharge':
        return symptomEyeDischargeBn;
      case 'umbilicus_red':
        return symptomUmbilicusRedBn;
      case 'jaundice':
        return symptomJaundiceBn;
      default:
        return null;
    }
  }

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
  static String get ancDeliveryConflictHint => getTranslatedString('ancDeliveryConflictHint', '⚠ ANC is unavailable on a pregnancy-outcome visit — deselect Pregnancy Outcome first');
  static String get pncOnlyPostpartumHint => getTranslatedString('pncOnlyPostpartumHint', '⚠ Mother PNC is available after delivery — use Pregnancy Outcome now');
  static String get vaccinationDefaultHint => getTranslatedString('vaccinationDefaultHint', 'Vaccination is always included for this visit — only Child Health is optional');

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

  // ── Section titles ──────────────────────────────────────────────────────────
  static const String sectionVitals = 'Vitals';
  static const String sectionDangerSigns = 'Danger Signs';
  static const String sectionSymptomDetail = 'Symptoms';
  static const String sectionIccmClassify = 'ICCM Assessment';
  static const String sectionTbDetail = 'TB Screening';

  /// Progress indicator label — e.g. `'Section 2 of 5 — Vitals'`.
  static String sectionProgress(int current, int total, String sectionTitle) => getTranslatedString('sectionProgress', 'Section {current} of {total} — {sectionTitle}', params: {'current': '$current', 'total': '$total', 'sectionTitle': '$sectionTitle'});

  // ── Field labels ────────────────────────────────────────────────────────────
  static const String fieldTemperature = 'Temperature';
  static const String fieldBreathsPerMinute = 'Respiratory rate';
  static const String fieldWeightKg = 'Weight (kg)';
  static const String fieldMuacCm = 'MUAC (cm)';
  static const String fieldSpo2 = 'SpO2 (%)';
  static const String fieldHasCough = 'Has cough';
  static const String fieldCoughDays = 'Cough duration (days)';
  static const String fieldHasFever = 'Has fever';
  static const String fieldFeverDays = 'Fever duration (days)';
  static const String fieldHasDiarrhea = 'Has diarrhea';
  static const String fieldUnableToBreastfeed = 'Unable to drink / breastfeed';
  static const String fieldVomitsEverything = 'Vomits everything';
  static const String fieldHasConvulsions = 'Has convulsions';
  static const String fieldLethargic = 'Lethargic / unconscious';
  static const String fieldChestIndrawing = 'Chest in-drawing';
  static const String fieldStridor = 'Stridor when calm';
  static const String fieldIsBloodyDiarrhea = 'Bloody diarrhea';
  static const String fieldHasFastBreathing = 'Fast breathing';
  static const String fieldRdtResult = 'RDT result';
  static const String fieldActDispensed = 'ACT dispensed';
  static const String fieldOrsDispensed = 'ORS dispensed';
  static const String fieldZincDispensed = 'Zinc dispensed';
  static const String fieldAmoxicillinDispensed = 'Amoxicillin dispensed';
  static const String fieldHasCoughLastedLonger = 'Cough ≥ 2 weeks';
  static const String fieldHasNightSweats = 'Night sweats';
  static const String fieldHasWeightLoss = 'Weight loss';
  static const String fieldRelationshipToIC = 'Relationship to index case';
  static const String fieldSleepLocation = 'Sleep location';
  static const String fieldPreviouslyTreatedForTB = 'Previously treated for TB';

  // ── Shared vitals labels ────────────────────────────────────────────────────
  static const String fieldHeight = 'Height (cm)';
  static const String fieldWeight = 'Weight (kg)';
  static const String fieldPulse = 'Pulse';

  // ── ANC field labels ────────────────────────────────────────────────────────
  static const String fieldBloodPressureSystolic = 'Systolic BP';
  static const String fieldBloodPressureDiastolic = 'Diastolic BP';
  static const String fieldAncWeight = 'Weight';
  static const String fieldFundalHeight = 'Fundal height';
  static const String fieldFetalHeartRate = 'Fetal heart rate';
  static const String fieldFetalMovement = 'Fetal movement';
  static const String fieldOedema = 'Oedema';
  static const String fieldEdema = 'Edema';
  static const String fieldPallor = 'Pallor';
  static const String fieldTtTdCompleted = 'TT/Td vaccination';
  static const String fieldIfaProvided = 'IFA tablets provided';
  static const String fieldCalciumProvided = 'Calcium tablets provided';
  static const String fieldFacilityIdentifiedForDelivery =
      'Has the PW identified a health facility for institutional delivery?';
  static const String fieldUltrasound = 'Ultrasound';
  static const String fieldHemoglobin = 'Hemoglobin (Hb)';
  static const String fieldBloodSugar = 'Blood sugar type';
  static const String fieldBloodSugarFasting = 'Fasting blood sugar';
  static const String fieldBloodSugarRandom = 'Random blood sugar';
  static const String fieldUrinaryAlbumin = 'Urinary albumin';
  static const String fieldUrinarySugar = 'Urinary sugar';
  static const String fieldUrinaryBilirubin = 'Urinary bilirubin';
  static const String fieldFolicAcidConsumed =
      'Folic acid consumed (last month)';
  static const String fieldFolicAcidProvided = 'Folic acid provided';
  static const String fieldIfaConsumed = 'IFA tablets consumed (last month)';
  static const String fieldCalciumConsumed = 'Calcium consumed (last month)';
  static const String fieldAncVisitsOtherProviders =
      'ANC visits with other providers';
  static const String fieldAncFromMedicalDoctor = 'ANC from medical doctor?';
  static const String fieldPreviousPregnancyComplications =
      'Previous pregnancy complications';
  static const String fieldDangerSigns12 = 'Danger signs (weeks 1–12)';
  static const String fieldDangerSigns13to27 = 'Danger signs (weeks 13–27)';
  static const String fieldDangerSigns28to40 = 'Danger signs (weeks 28–40)';
  static const String fieldReferralFacility = 'Referral facility';

  // ── NCD field labels ────────────────────────────────────────────────────────
  static const String fieldSystolic2 = 'Systolic BP (2nd reading)';
  static const String fieldDiastolic2 = 'Diastolic BP (2nd reading)';
  static const String fieldIsRegularSmoker = 'Regular smoker';
  static const String fieldMedAdherence = 'Medication adherence';
  static const String fieldNcdSymptoms = 'Symptoms';
  static const String fieldHasSymptoms = 'Had symptoms since last follow-up?';
  static const String fieldNewWorseningSymptoms = 'New or worsening symptoms';
  static const String fieldCompliance = 'Taking medication regularly?';
  static const String fieldGlucoseValue = 'Blood glucose';
  static const String fieldGlucoseType = 'Glucose measurement type';
  static const String fieldHba1c = 'HbA1c';
  static const String fieldFootExam = 'Foot examination';
  static const String fieldFootWound = 'Foot wound present';

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

  // ── Section titles (ANC + NCD) ──────────────────────────────────────────────
  static const String sectionAncVitals = 'ANC Vitals';
  static const String sectionAncSpecific = 'ANC Assessment';
  static const String sectionNcdHtn = 'Hypertension';
  static const String sectionNcdDm = 'Diabetes';
  static const String sectionNcdFindrisc = 'Diabetes Risk (FINDRISC)';
  static const String sectionFamilyPlanning = 'Family Planning';
  static const String sectionCataractExam = 'Cataract / Eye Disease';
  static const String sectionEyeCareExam = 'Eye Care';

  // ── Section titles (EPI + NUTRITION + PNC) ─────────────────────────────────
  static const String sectionEpiReview = 'EPI / Immunization';
  static const String sectionNutritionDetail = 'Nutrition Assessment';
  static const String sectionPncCheck = 'Postnatal Check';
  static const String sectionPncMother = 'Postnatal — Mother';
  static const String sectionPncNeonatal = 'Postnatal — Newborn';
  static const String sectionPncChild = 'Postnatal — Child';

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
  static String get glucoseValidationError => getTranslatedString('glucoseValidationError', 'Enter a glucose reading between 1.0 and 15.0 mmol/L');
  static String get haemoglobinValidationError => getTranslatedString('haemoglobinValidationError', 'Enter a Hb reading between 1.0 and 20.0 g/dL');
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

/// CDS (Clinical Decision Support) alert strings.
/// Phase 3: Symptom-Driven Unified Assessment — CDS rules layer.
///
/// All keys used in [CdsAlert.messageKey] and [CdsAlert.rationaleKey]
/// must resolve through this class.  No string literals in widgets.
abstract final class CdsStrings {
  CdsStrings._();

  // ── Alert messages ──────────────────────────────────────────────────────────
  static const String bpSevereMessage =
      'Severe hypertension detected — refer immediately';
  static const String bpStage1Message =
      'High BP — add NCD hypertension assessment';
  static const String dangerSignMessage =
      'Danger sign present — refer immediately';
  static const String severePneumoniaMessage =
      'Severe pneumonia — refer immediately';
  static const String pneumoniaMessage =
      'Pneumonia — treat or refer if worsening';
  static const String samMessage =
      'Severe acute malnutrition — refer immediately';
  static const String mamMessage = 'Moderate malnutrition — treat at community';
  static const String severeAnemiaMessage = 'Severe anemia — refer immediately';
  static const String anemiaMessage =
      'Anemia detected — supplement and follow up';
  static const String glucoseHighMessage =
      'High blood glucose — diabetes screening indicated';
  static const String tbScreenAddMessage =
      'TB screening added — cough ≥ 2 weeks';
  static const String conflictReferralOverridesKey =
      'Referral recommended — treat-at-community overridden';

  // ── Alert actions ───────────────────────────────────────────────────────────
  static String get referNowButton => getTranslatedString('referNowButton', 'Refer now');
  static String get addPathwayButton => getTranslatedString('addPathwayButton', 'Add to assessment');
  static String get dismissButton => getTranslatedString('dismissButton', 'Dismiss');

  // ── Rationale / explainability keys ────────────────────────────────────────
  static const String rationaleWhoHeartsBpSevere =
      'WHO HEARTS: systolic ≥ 160 or diastolic ≥ 100 = severe hypertension';
  static const String rationaleWhoHeartsStage1 =
      'WHO HEARTS: systolic ≥ 140 or diastolic ≥ 90 = stage 1 hypertension';
  static const String rationaleWhoImciDangerSign =
      'WHO IMCI: general danger sign = refer urgently';
  static const String rationaleWhoImciSeverePneumonia =
      'WHO IMCI: chest indrawing = severe pneumonia';
  static const String rationaleWhoImciPneumonia =
      'WHO IMCI: fast breathing without chest indrawing = pneumonia';
  static const String rationaleWhoMuacSam =
      'WHO: MUAC < 11.5 cm = severe acute malnutrition';
  static const String rationaleWhoMuacMam =
      'WHO: MUAC 11.5–12.5 cm = moderate acute malnutrition';
  static const String rationaleWhoAncAnemia =
      'WHO ANC: Hb < 7 g/dL = severe anemia requiring referral';
  static const String rationaleWhoAncMildAnemia =
      'WHO ANC: Hb < 11 g/dL = anemia in pregnancy';
  static const String rationaleWhoPenDm =
      'WHO PEN: glucose > 200 mg/dL random or > 126 mg/dL fasting = diabetes threshold';
  static const String rationaleWhoTb4Symptom =
      'WHO: cough ≥ 2 weeks is a TB indicator — screen urgently';

  // ── CDSS algorithm rationales ────────────────────────────────────────────────
  static const String rationaleFindriscModerate =
      'FINDRISC score 12–14: moderate diabetes risk (1 in 6 chance over 10 years)';
  static const String rationaleFindriscHigh =
      'FINDRISC score 15–20: high diabetes risk (1 in 3 chance over 10 years)';
  static const String rationaleFindriscVeryHigh =
      'FINDRISC score ≥ 21: very high diabetes risk (1 in 2 chance over 10 years)';
  static const String rationaleFraminghamTrigger =
      'Framingham No-Lab: 10-year CVD risk ≥ 10% — NCD management indicated';
  static const String rationaleFraminghamHigh =
      'Framingham No-Lab: 10-year CVD risk ≥ 20% — high cardiovascular risk';
  static const String rationaleBpTrendCusum =
      'CUSUM: cumulative BP rise exceeds decision threshold (h = 40 mmHg)';
  static const String rationaleBpTrendEwma =
      'EWMA: smoothed BP trend has crossed the upper control limit';
  static const String rationaleBpTrendSlope =
      'Linear slope: BP increasing at > 4 mmHg per visit';
  static const String rationaleMiniPiersHigh =
      'miniPIERS: predicted adverse maternal outcome risk ≥ 25%';
  static const String rationaleMiniPiersCritical =
      'miniPIERS: predicted adverse maternal outcome risk ≥ 50% — refer now';
  static const String rationaleCataractNcdCoenroll =
      'NCD service provided during cataract visit — NCD enrolment recommended';
  static const String rationaleEyeCareReferral =
      'Eye test outcome requires specialist referral';

  // ── CDSS algorithm alert messages ────────────────────────────────────────────
  static const String findriscModerateMessage =
      'Diabetes risk moderate (FINDRISC 12–14) — add NCD assessment';
  static const String findriscHighMessage =
      'Diabetes risk high (FINDRISC 15–20) — add NCD assessment';
  static const String findriscVeryHighMessage =
      'Diabetes risk very high (FINDRISC ≥ 21) — add NCD assessment';
  static const String framinghamTriggerMessage =
      'CVD risk ≥ 10% (Framingham) — NCD management indicated';
  static const String framinghamHighMessage =
      'CVD risk ≥ 20% (Framingham) — high cardiovascular risk';
  static const String bpTrendCusumMessage =
      'BP trend alert (CUSUM) — rising blood pressure pattern detected';
  static const String bpTrendEwmaMessage =
      'BP trend alert (EWMA) — blood pressure control worsening';
  static const String bpTrendSlopeMessage =
      'BP trend alert — increasing > 4 mmHg per visit';
  static const String miniPiersHighMessage =
      'High risk of adverse outcome (miniPIERS ≥ 25%) — close monitoring needed';
  static const String miniPiersCriticalMessage =
      'Critical risk of adverse outcome (miniPIERS ≥ 50%) — refer immediately';
  static const String cataractNcdCoenrollMessage =
      'NCD service provided — enrol patient in NCD programme';
  static const String eyeCareReferralMessage =
      'Patient requires eye care referral — document referral facility';

  /// Resolve a message string by its key (as stored in [CdsAlert.messageKey]).
  static String message(String key) {
    switch (key) {
      case 'bpSevereMessage':
        return getTranslatedString('Cds.message.bpSevereMessage', 'Severe hypertension detected — refer immediately');
      case 'bpStage1Message':
        return getTranslatedString('Cds.message.bpStage1Message', 'High BP — add NCD hypertension assessment');
      case 'dangerSignMessage':
        return getTranslatedString('Cds.message.dangerSignMessage', 'Danger sign present — refer immediately');
      case 'severePneumoniaMessage':
        return getTranslatedString('Cds.message.severePneumoniaMessage', 'Severe pneumonia — refer immediately');
      case 'pneumoniaMessage':
        return getTranslatedString('Cds.message.pneumoniaMessage', 'Pneumonia — treat or refer if worsening');
      case 'samMessage':
        return getTranslatedString('Cds.message.samMessage', 'Severe acute malnutrition — refer immediately');
      case 'mamMessage':
        return getTranslatedString('Cds.message.mamMessage', 'Moderate malnutrition — treat at community');
      case 'severeAnemiaMessage':
        return getTranslatedString('Cds.message.severeAnemiaMessage', 'Severe anemia — refer immediately');
      case 'anemiaMessage':
        return getTranslatedString('Cds.message.anemiaMessage', 'Anemia detected — supplement and follow up');
      case 'glucoseHighMessage':
        return getTranslatedString('Cds.message.glucoseHighMessage', 'High blood glucose — diabetes screening indicated');
      case 'tbScreenAddMessage':
        return getTranslatedString('Cds.message.tbScreenAddMessage', 'TB screening added — cough ≥ 2 weeks');
      case 'conflictReferralOverridesKey':
        return getTranslatedString('Cds.message.conflictReferralOverridesKey', 'Referral recommended — treat-at-community overridden');
      case 'findriscModerateMessage':
        return getTranslatedString('Cds.message.findriscModerateMessage', 'Diabetes risk moderate (FINDRISC 12–14) — add NCD assessment');
      case 'findriscHighMessage':
        return getTranslatedString('Cds.message.findriscHighMessage', 'Diabetes risk high (FINDRISC 15–20) — add NCD assessment');
      case 'findriscVeryHighMessage':
        return getTranslatedString('Cds.message.findriscVeryHighMessage', 'Diabetes risk very high (FINDRISC ≥ 21) — add NCD assessment');
      case 'framinghamTriggerMessage':
        return getTranslatedString('Cds.message.framinghamTriggerMessage', 'CVD risk ≥ 10% (Framingham) — NCD management indicated');
      case 'framinghamHighMessage':
        return getTranslatedString('Cds.message.framinghamHighMessage', 'CVD risk ≥ 20% (Framingham) — high cardiovascular risk');
      case 'bpTrendCusumMessage':
        return getTranslatedString('Cds.message.bpTrendCusumMessage', 'BP trend alert (CUSUM) — rising blood pressure pattern detected');
      case 'bpTrendEwmaMessage':
        return getTranslatedString('Cds.message.bpTrendEwmaMessage', 'BP trend alert (EWMA) — blood pressure control worsening');
      case 'bpTrendSlopeMessage':
        return getTranslatedString('Cds.message.bpTrendSlopeMessage', 'BP trend alert — increasing > 4 mmHg per visit');
      case 'miniPiersHighMessage':
        return getTranslatedString('Cds.message.miniPiersHighMessage', 'High risk of adverse outcome (miniPIERS ≥ 25%) — close monitoring needed');
      case 'miniPiersCriticalMessage':
        return getTranslatedString('Cds.message.miniPiersCriticalMessage', 'Critical risk of adverse outcome (miniPIERS ≥ 50%) — refer immediately');
      case 'cataractNcdCoenrollMessage':
        return getTranslatedString('Cds.message.cataractNcdCoenrollMessage', 'NCD service provided — enrol patient in NCD programme');
      case 'eyeCareReferralMessage':
        return getTranslatedString('Cds.message.eyeCareReferralMessage', 'Patient requires eye care referral — document referral facility');
      default:
        return key;
    }
  }

  /// Resolve a rationale string by its key (as stored in [CdsAlert.rationaleKey]).
  static String rationale(String key) {
    switch (key) {
      case 'rationaleWhoHeartsBpSevere':
        return getTranslatedString('Cds.rationale.rationaleWhoHeartsBpSevere', 'WHO HEARTS: systolic ≥ 160 or diastolic ≥ 100 = severe hypertension');
      case 'rationaleWhoHeartsStage1':
        return getTranslatedString('Cds.rationale.rationaleWhoHeartsStage1', 'WHO HEARTS: systolic ≥ 140 or diastolic ≥ 90 = stage 1 hypertension');
      case 'rationaleWhoImciDangerSign':
        return getTranslatedString('Cds.rationale.rationaleWhoImciDangerSign', 'WHO IMCI: general danger sign = refer urgently');
      case 'rationaleWhoImciSeverePneumonia':
        return getTranslatedString('Cds.rationale.rationaleWhoImciSeverePneumonia', 'WHO IMCI: chest indrawing = severe pneumonia');
      case 'rationaleWhoImciPneumonia':
        return getTranslatedString('Cds.rationale.rationaleWhoImciPneumonia', 'WHO IMCI: fast breathing without chest indrawing = pneumonia');
      case 'rationaleWhoMuacSam':
        return getTranslatedString('Cds.rationale.rationaleWhoMuacSam', 'WHO: MUAC < 11.5 cm = severe acute malnutrition');
      case 'rationaleWhoMuacMam':
        return getTranslatedString('Cds.rationale.rationaleWhoMuacMam', 'WHO: MUAC 11.5–12.5 cm = moderate acute malnutrition');
      case 'rationaleWhoAncAnemia':
        return getTranslatedString('Cds.rationale.rationaleWhoAncAnemia', 'WHO ANC: Hb < 7 g/dL = severe anemia requiring referral');
      case 'rationaleWhoAncMildAnemia':
        return getTranslatedString('Cds.rationale.rationaleWhoAncMildAnemia', 'WHO ANC: Hb < 11 g/dL = anemia in pregnancy');
      case 'rationaleWhoPenDm':
        return getTranslatedString('Cds.rationale.rationaleWhoPenDm', 'WHO PEN: glucose > 200 mg/dL random or > 126 mg/dL fasting = diabetes threshold');
      case 'rationaleWhoTb4Symptom':
        return getTranslatedString('Cds.rationale.rationaleWhoTb4Symptom', 'WHO: cough ≥ 2 weeks is a TB indicator — screen urgently');
      case 'rationaleFindriscModerate':
        return getTranslatedString('Cds.rationale.rationaleFindriscModerate', 'FINDRISC score 12–14: moderate diabetes risk (1 in 6 chance over 10 years)');
      case 'rationaleFindriscHigh':
        return getTranslatedString('Cds.rationale.rationaleFindriscHigh', 'FINDRISC score 15–20: high diabetes risk (1 in 3 chance over 10 years)');
      case 'rationaleFindriscVeryHigh':
        return getTranslatedString('Cds.rationale.rationaleFindriscVeryHigh', 'FINDRISC score ≥ 21: very high diabetes risk (1 in 2 chance over 10 years)');
      case 'rationaleFraminghamTrigger':
        return getTranslatedString('Cds.rationale.rationaleFraminghamTrigger', 'Framingham No-Lab: 10-year CVD risk ≥ 10% — NCD management indicated');
      case 'rationaleFraminghamHigh':
        return getTranslatedString('Cds.rationale.rationaleFraminghamHigh', 'Framingham No-Lab: 10-year CVD risk ≥ 20% — high cardiovascular risk');
      case 'rationaleBpTrendCusum':
        return getTranslatedString('Cds.rationale.rationaleBpTrendCusum', 'CUSUM: cumulative BP rise exceeds decision threshold (h = 40 mmHg)');
      case 'rationaleBpTrendEwma':
        return getTranslatedString('Cds.rationale.rationaleBpTrendEwma', 'EWMA: smoothed BP trend has crossed the upper control limit');
      case 'rationaleBpTrendSlope':
        return getTranslatedString('Cds.rationale.rationaleBpTrendSlope', 'Linear slope: BP increasing at > 4 mmHg per visit');
      case 'rationaleMiniPiersHigh':
        return getTranslatedString('Cds.rationale.rationaleMiniPiersHigh', 'miniPIERS: predicted adverse maternal outcome risk ≥ 25%');
      case 'rationaleMiniPiersCritical':
        return getTranslatedString('Cds.rationale.rationaleMiniPiersCritical', 'miniPIERS: predicted adverse maternal outcome risk ≥ 50% — refer now');
      case 'rationaleCataractNcdCoenroll':
        return getTranslatedString('Cds.rationale.rationaleCataractNcdCoenroll', 'NCD service provided during cataract visit — NCD enrolment recommended');
      case 'rationaleEyeCareReferral':
        return getTranslatedString('Cds.rationale.rationaleEyeCareReferral', 'Eye test outcome requires specialist referral');
      default:
        return key;
    }
  }
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
        return 'Step 1 of 3 · Tap all symptoms mentioned';
      case 1:
        return 'Step 2 of 3 · AI triage active';
      default:
        return 'Step 3 of 3 · Fill in what you see';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SymptomPickerStrings
// ─────────────────────────────────────────────────────────────────────────────

abstract final class SymptomPickerStrings {
  SymptomPickerStrings._();

  // ── AI Scribe triage banner (spec §4.1.2 / §5.1.1) ───────────────────────
  static String scribeBannerTitleFor({required bool isFemale}) =>
      isFemale
          ? '🎙 AI Scribe — tap and let her speak'
          : '🎙 AI Scribe — tap and let him speak';
  static String scribeBannerSubtitleFor({required bool isFemale}) =>
      isFemale
          ? 'Symptoms appear automatically as she talks'
          : 'Symptoms appear automatically as he talks';
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
      ? 'Scribe complete · 1 symptom detected'
      : n > 1
          ? 'Scribe complete · $n symptoms detected'
          : 'Scribe complete';
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

  /// Card 3 title — gendered. Spec §4.1 / §5.1: greet the patient before
  /// opening the symptom screen. Pronoun resolved from patient profile.
  static String briefCard3TitleFor({required bool isFemale}) =>
      'How is ${isFemale ? 'she' : 'he'} feeling today?';

  // ── Before You Knock instructional leading line ──────────────────────────
  /// Shown on the navy strip at the top of Card 1.
  static String beforeYouKnockGreetingFor({required bool isFemale}) =>
      'Sit with ${isFemale ? 'her' : 'him'} — greet them.';

  // ── "Sit with her / him — greet warmly" card (Step 1, between
  // Before-You-Knock and the AI Scribe). All static — never AI-generated.

  /// Header (uppercase, small). Gendered.
  static String sitWithGreetHeaderFor({required bool isFemale}) =>
      isFemale ? 'SIT WITH HER — GREET WARMLY' : 'SIT WITH HIM — GREET WARMLY';

  /// Bangla greeting the SK opens with. ANC variant for women of reproductive
  /// age; NCD/general variant otherwise. Includes the second-line ask so the
  /// SK has a natural pause before the AI Scribe records.
  static String sitWithGreetBanglaFor({required bool isFemale}) => isFemale
      ? '"আপু, আপনি কেমন আছেন?\nবাচ্চা কেমন নড়াচড়া করছে?"'
      : '"কাকা, আপনি কেমন আছেন?\nকোথাও কষ্ট আছে কি?"';

  /// English translation of [sitWithGreetBanglaFor].
  static String sitWithGreetEnglishFor({required bool isFemale}) => isFemale
      ? 'Sister, how are you? Is the baby moving well?'
      : 'Brother, how are you? Are you feeling any discomfort?';

  /// Helper hint below the greeting — primes the SK to talk about home life
  /// before launching the clinical conversation.
  static String sitWithGreetHintFor({required bool isFemale}) => isFemale
      ? 'Ask how she feels at home, with family, and about her sleep — before the pregnancy checkup'
      : 'Ask how he feels at home, with family, and about his sleep — before the visit';

  // ── "How is she feeling today?" heading shown just above the AI Scribe.
  static String howFeelingTodayHeadingFor({required bool isFemale}) =>
      'How is ${isFemale ? 'she' : 'he'} feeling today? 🎙️';

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
  static const String skOpenerPhraseBn = 'আজকে কে কে অসুস্থ আছে?';

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
  static String symptomsSelectedStatus(int n) =>
      '$n ${n == 1 ? 'symptom' : 'symptoms'} selected';
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
  static String symptomsSelected(int n) =>
      '$n ${n == 1 ? 'symptom' : 'symptoms'} selected';
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
  static String addSymptomSheetCounter(int added) =>
      added == 0 ? 'No symptoms selected' : '$added selected';
  static String get removeSymptomSemanticPrefix => getTranslatedString('removeSymptomSemanticPrefix', 'Remove symptom');
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
  static const String callDoctorNowBn = 'ডাক্তারকে ফোন করন';
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
  static const String strokeSignBn = 'এক পাশে দুর্বলতা / স্ট্রোকের লক্ষণ?';
  static String get strokeSignSubtitle => getTranslatedString('strokeSignSubtitle', 'Sudden numbness or weakness on one side — immediate emergency referral.');

  static String get morningHeadachesTitle => getTranslatedString('morningHeadachesTitle', 'Morning headaches?');
  static const String morningHeadachesBn = 'সকালে মাথা ব্যথা?';

  static String get chestTightnessTitle => getTranslatedString('chestTightnessTitle', 'Chest tightness or shortness of breath?');
  static const String chestTightnessBn = 'বুকে চাপ বা শ্বাসকষ্ট?';

  static String get highSaltTitle => getTranslatedString('highSaltTitle', 'High salt in daily food?');
  static const String highSaltBn = 'খাবারে অতিরিক্ত লবণ?';

  static String get familyHistoryTitle => getTranslatedString('familyHistoryTitle', 'Family history of high BP?');
  static const String familyHistoryBn = 'বাবা-মায়ের / পরিবারে উচ্চ রক্তচাপ?';
}

/// Visit form host screen (fallback, non-sectioned mode).
abstract final class VisitFormStrings {
  VisitFormStrings._();

  static String get saveFailed => getTranslatedString('saveFailed', 'Could not save the assessment. It is kept on this device — please try again.');
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
  static String get ifaPairLabel => getTranslatedString('ifaPairLabel', 'IFA tablets');
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
  static String validationFieldsRequired(int n) =>
      '$n required ${n == 1 ? 'field' : 'fields'} must be filled before submitting.';

  /// Badge label shown on the programme divider when AI pre-filled symptoms
  /// for that programme from triage Step 1.
  static String get aiBadgeLabel => getTranslatedString('aiBadgeLabel', 'AI');

  // Triage symptoms carry-over banner.
  static String get triageSymptomsTitle => getTranslatedString('triageSymptomsTitle', 'Symptoms from Step 1');
  static String triageSymptomsCount(int n) =>
      '$n ${n == 1 ? 'symptom' : 'symptoms'} from Step 1';
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
    if (days < 7) return days <= 1 ? '1d' : '${days}d';
    final weeks = (days / 7).round();
    return '${weeks}wks';
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

  static String vsLastWeight(double kg) => 'Last: ${kg.toStringAsFixed(1)} kg';

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

  /// Human-readable label for a formType key shown as a programme badge.
  ///
  /// Returns `null` for the synthetic `vitals` formType (no badge needed).
  static String? programmeBadgeLabel(String formType) {
    switch (formType) {
      case 'commonVitals':
        return 'Vitals';
      case 'anc':
        return 'ANC';
      case 'ncd':
        return 'NCD';
      case 'pncMother':
        return 'PNC';
      case 'pncChild':
        return 'Child';
      case 'pncNeonatal':
        return 'Neonate';
      case 'pregnancyOutcome':
        return 'Preg. Outcome';
      case 'cataract':
        return 'Cataract';
      case 'eye_care':
        return 'Eye Care';
      case 'family_planning':
        return 'FP';
      case 'pwProfile':
        return 'Profile';
      default:
        return null;
    }
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
      DateFormat('MMMM yyyy').format(date);

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
  static const List<String> weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const List<String> weekLabels = ['W1', 'W2', 'W3', 'W4'];
  static String get serviceAnc => getTranslatedString('serviceAnc', 'ANC');
  static String get serviceNcd => getTranslatedString('serviceNcd', 'NCD');
  static String get serviceChild => getTranslatedString('serviceChild', 'Child / Immunisation');
  static String get servicePnc => getTranslatedString('servicePnc', 'PNC');
  static String get serviceHousehold => getTranslatedString('serviceHousehold', 'Household enrolment');

  static String insightWeek(int pct) => getTranslatedString('insightWeek', 'You completed {pct}% more visits than the Manikganj Sadar area average this week.', params: {'pct': '$pct'});

  static String insightMonth(int pct) => getTranslatedString('insightMonth', 'You completed {pct}% more visits than the Manikganj Sadar area average this month.', params: {'pct': '$pct'});
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
  static const List<String> householdTypes = [
    'Single-family',
    'Multi-family',
    'Institutional',
    'Other',
  ];

  static String get numberOfMembersLabel => getTranslatedString('numberOfMembersLabel', 'Number of Members');
  static String get numberOfMembersHint => getTranslatedString('numberOfMembersHint', 'Estimated count');

  static String get houseNumberLabel => getTranslatedString('houseNumberLabel', 'House Number');
  static String get houseNumberHint => getTranslatedString('houseNumberHint', 'e.g., 123 A/B');

  static String get occupationLabel => getTranslatedString('occupationLabel', 'Primary Occupation');
  static String get occupationHint => getTranslatedString('occupationHint', 'Farmer, Labour, Business, etc.');

  static String get monthlyIncomeLabel => getTranslatedString('monthlyIncomeLabel', 'Monthly Income');
  static const List<String> incomeRanges = [
    '<10000',
    '10000-25000',
    '25000-50000',
    '>50000',
  ];

  static String get disabilityQuestionLabel => getTranslatedString('disabilityQuestionLabel', 'Does any household member have a disability?');
  static String get disabilityDetailsLabel => getTranslatedString('disabilityDetailsLabel', 'Please specify');
  static String get disabilityDetailsHint => getTranslatedString('disabilityDetailsHint', 'Type of disability');

  // ── Household Head Info Screen (Step 2) ──────────────────────────────────
  static String get householdHeadTitle => getTranslatedString('householdHeadTitle', 'Household Head Information');
  static String get householdHeadSubtitle => getTranslatedString('householdHeadSubtitle', 'Step 2 of 2');

  static String get headNameLabel => getTranslatedString('headNameLabel', 'Household Head Name');
  static String get headNameHint => getTranslatedString('headNameHint', 'Head\'s full name');

  static String get fatherNameLabel => getTranslatedString('fatherNameLabel', 'Father\'s Name');
  static String get fatherNameHint => getTranslatedString('fatherNameHint', 'As printed on the NID (Bangla)');
  static String get motherNameLabel => getTranslatedString('motherNameLabel', 'Mother\'s Name');
  static String get motherNameHint => getTranslatedString('motherNameHint', 'As printed on the NID (Bangla)');

  static String get idTypeLabel => getTranslatedString('idTypeLabel', 'ID Type');

  static String get mobileNumberLabel => getTranslatedString('mobileNumberLabel', 'Mobile Number');
  static String get mobileNumberHint => getTranslatedString('mobileNumberHint', '+880 1XXX XXXXXX');
  static String get mobileNotAvailableLabel => getTranslatedString('mobileNotAvailableLabel', 'Not Available');

  static String get dateOfBirthLabel => getTranslatedString('dateOfBirthLabel', 'Date of Birth');
  static String get dateOfBirthHint => getTranslatedString('dateOfBirthHint', 'DD-MM-YYYY');
  static String get approximateAgeLabel => getTranslatedString('approximateAgeLabel', 'Or Approximate Age');
  static String get approximateAgeHint => getTranslatedString('approximateAgeHint', 'Years');

  static String get ageLabel => getTranslatedString('Enrollment.ageLabel', 'Age');
  static String get ageHint => getTranslatedString('ageHint', 'Calculated from DOB');

  static String get genderLabel => getTranslatedString('genderLabel', 'Gender');

  static String get maritalStatusLabel => getTranslatedString('maritalStatusLabel', 'Marital Status');

  static String get disabilityStatusLabel => getTranslatedString('disabilityStatusLabel', 'Disability');
  static const List<String> disabilityStatuses = [
    'None',
    'Physical',
    'Sensory',
    'Cognitive',
    'Multiple',
  ];

  // ── Add Member Screen ────────────────────────────────────────────────────
  static String get addMemberTitle => getTranslatedString('addMemberTitle', 'Add Household Member');
  static String get memberNameLabel => getTranslatedString('memberNameLabel', 'Name');
  static String get memberNameHint => getTranslatedString('memberNameHint', 'Member\'s full name');

  static String get relationshipToHeadLabel => getTranslatedString('relationshipToHeadLabel', 'Relationship to Head');
  static const List<String> relationships = [
    'Spouse',
    'Child',
    'Parent',
    'Sibling',
    'Other',
  ];

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
  static String get disabilityPersonCountHint => getTranslatedString('disabilityPersonCountHint', 'e.g. 1');
  static String get disabilityPersonCountInfo => getTranslatedString('disabilityPersonCountInfo', 'Who has great difficulty or cannot see, hear, walk, climb, do things independently, remember, concentrate, communicate, or understand others');
  static String get phoneCategoryLabel => getTranslatedString('phoneCategoryLabel', 'Mobile number category');
  static String get phoneCategoryHint => getTranslatedString('phoneCategoryHint', 'Select category');

  static String get totalMembersLabel => getTranslatedString('totalMembersLabel', 'Total Household Members');
  static String get totalMembersHint => getTranslatedString('totalMembersHint', 'e.g. 5');

  static const List<String> householdTypesV2 = ['BRAC VO', 'NVO'];
  static const List<String> gendersHead = ['Male', 'Female', 'Other'];
  static const List<String> maritalStatusesV2 = [
    'Married',
    'Single',
    'Unmarried',
  ];
  static String get guardianLabel => getTranslatedString('guardianLabel', 'Guardian Name');
  static String get guardianHint => getTranslatedString('guardianHint', 'Select guardian from household');
  // Spice member_registration.json shows the `disability` question as Yes/No;
  // the wire values stay present/absent (see EnrollmentRepository).
  static const List<String> disabilityStatusesV2 = ['Yes', 'No'];
  static const List<String> disabilityYesNo = ['Yes', 'No'];
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

  static const List<String> healthWorkerOptions = [
    'Jahnara Begum — Char Bhadra',
    'Fatema Khatun — Bhadra',
    'Roksana Akter — Noyapara',
  ];
  static const List<String> villageOptions = [
    'Char Bhadra',
    'Bhadra',
    'Noyapara',
  ];
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
  static String get nidNumberLabel => getTranslatedString('nidNumberLabel', 'NID NUMBER');
  static String get nidNumberHint => getTranslatedString('nidNumberHint', 'Enter NID number');
  static String get nidScannedBadge => getTranslatedString('nidScannedBadge', '✓ Scanned');
  static String get nidClearScan => getTranslatedString('nidClearScan', 'Clear scan');
  static String get nidScanNoBrnHint => getTranslatedString('nidScanNoBrnHint', 'If member has no NID, enter Birth Registration ID instead.');
  static String nidNumberCaptured(String number) => getTranslatedString('nidNumberCaptured', '✓ NID number captured: {number}', params: {'number': '$number'});
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
abstract final class EpiStrings {
  EpiStrings._();

  static String get screenTitle => getTranslatedString('Epi.screenTitle', 'Vaccination');
  static String get vaccinationCta => getTranslatedString('Epi.vaccinationCta', 'Vaccination');
  static String get noDobError => getTranslatedString('noDobError', 'Date of birth not available — cannot compute schedule.');

  static String overdueBanner(int count) =>
      '$count ${count == 1 ? 'vaccine' : 'vaccines'} overdue · Action needed today.';

  static String get statusCompleted => getTranslatedString('statusCompleted', 'Completed');
  static String get statusDueNow => getTranslatedString('statusDueNow', 'Due now');
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
  static String get missedReasonLabel => getTranslatedString('missedReasonLabel', 'Reason for Missed Dose');
  static String get missedReasonHint => getTranslatedString('missedReasonHint', 'e.g. Child was sick on scheduled date');
  static String get missedReasonRequired => getTranslatedString('missedReasonRequired', 'Please enter a reason.');
  static String get childAssessmentSaveError => getTranslatedString('childAssessmentSaveError', 'Could not save the Child Health form. Please try again.');
}

/// EPI-specific Step 3 (AI recommendation) copy — visit summary, referral
/// reason, counselling, and follow-up text built from an [EpiVisitSummary].
abstract final class EpiVisitRecoStrings {
  EpiVisitRecoStrings._();

  static String get visitSummaryTitle => getTranslatedString(
      'EpiVisitReco.visitSummaryTitle', 'Vaccination Visit — Guideline Care Plan');

  static String visitSummary(EpiVisitSummary epi) => epi.overdueCount > 0
      ? '${epi.overdueCount} ${epi.overdueCount == 1 ? 'vaccine' : 'vaccines'} '
          'overdue — ${epi.currentMilestoneLabel} doses due now.'
      : 'All scheduled vaccines are up to date for this visit.';

  static String referralReason(String currentMilestoneLabel, List<String> names) =>
      '$currentMilestoneLabel doses overdue — ${_andJoin(names)} are due now.';

  static String catchUpAction(List<String> names) =>
      'All ${names.length} can be given in ONE visit — ${_andJoin(names)}.';

  static List<String> counsellingLines(EpiVisitSummary epi) => [
        '${epi.overdueCount} ${epi.overdueCount == 1 ? 'vaccine' : 'vaccines'} '
            'overdue — ${epi.currentMilestoneLabel} doses are due now.',
        'All ${epi.overdueVaccineNames.length} can be given in ONE visit — '
            '${_andJoin(epi.overdueVaccineNames)}.',
        if (epi.nextMilestoneLabel != null)
          'Next milestone: ${epi.nextMilestoneLabel} — '
              '${_andJoin(epi.nextMilestoneVaccineNames)}.',
        'Return at once if: high fever, rash, or breathing difficulty of any kind.',
      ];

  static String followUpActivity(String? label, List<String> names) => label == null
      ? 'Routine vaccination follow-up'
      : '$label milestone — ${_andJoin(names)}';

  static String whatsappMessage(EpiVisitSummary epi) {
    final next = epi.nextMilestoneLabel != null
        ? ' Next milestone: ${epi.nextMilestoneLabel} — '
            '${_andJoin(epi.nextMilestoneVaccineNames)}.'
        : '';
    if (epi.overdueCount == 0) {
      return 'All scheduled vaccines are up to date.$next';
    }
    return '${epi.overdueCount} ${epi.overdueCount == 1 ? 'vaccine' : 'vaccines'} '
        'overdue — ${epi.currentMilestoneLabel} doses are due now. '
        'All can be given in ONE visit — ${_andJoin(epi.overdueVaccineNames)}.$next '
        'Return at once if: high fever, rash, or breathing difficulty of any kind.';
  }

  static String _andJoin(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} & ${items.last}';
  }
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

  static const List<String> complicationOptions = [
    'Diarrhea',
    'Pneumonia',
    'Cannot stand or walk',
    'Cannot maintain body balance',
    'Cannot speak two meaningful words',
  ];

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
}

/// Care Coordination Engine (CCE) — the referral SLA alert drawer.
/// All widget-facing copy for `lib/features/cce/`. Derivation-time strings
/// interpolated by the pure-Dart model live in `cce_alert.dart`.
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
}

/// Follow-up call logging — the device-side close/update flow.
abstract final class FollowUpCallStrings {
  FollowUpCallStrings._();

  static String get logCall => getTranslatedString('logCall', 'Log call');
  static String get sheetTitle => getTranslatedString('FollowUpCall.sheetTitle', 'Log follow-up call');
  static String get outcomePrompt => getTranslatedString('outcomePrompt', 'How did the call go?');
  static String get outcomeSuccessful => getTranslatedString('outcomeSuccessful', 'Reached — successful');
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
  static const String pregnantWomanBengali = 'গর্ভবতী মা';
  static String get ancLabel => getTranslatedString('ancLabel', 'ANC Visit');
  static const String ancBengali = 'মাতৃস্বাস্থ্য সেবা';
  static String get pncLabel => getTranslatedString('pncLabel', 'PNC Visit');
  static const String pncBengali = 'প্রসবোত্তর সেবা';
  static String get ncdLabel => getTranslatedString('ncdLabel', 'NCD Check');
  static const String ncdBengali = 'অসংক্রামক রোগ';
  static String get tbLabel => getTranslatedString('tbLabel', 'TB Check');
  static const String tbBengali = 'যক্ষ্মা';
  static String get imciLabel => getTranslatedString('imciLabel', 'Child Visit');
  static const String imciBengali = 'শিশু স্বাস্থ্য সেবা';
  static String get epiLabel => getTranslatedString('epiLabel', 'Vaccination');
  static const String epiBengali = 'টিকা';
  static String get lockedToastAnc => getTranslatedString('lockedToastAnc', '⚠ Select "Pregnant Woman" first to unlock ANC');
  static String get lockedToastPnc => getTranslatedString('lockedToastPnc', '⚠ Select "Pregnant Woman" first to unlock PNC');
  static String get noProgrammes => getTranslatedString('noProgrammes', 'No eligible programmes for this patient based on age and gender.');
  static String confirmCta(int n) =>
      n == 0 ? 'Select Programmes' : 'Confirm Enrollment ($n selected)';
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

  static const List<String> starters = [
    'Any danger signs to check?',
    'What should I do this visit?',
    'Is a referral needed?',
  ];
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
  static String get general => getTranslatedString('general', 'General enrollment');
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
