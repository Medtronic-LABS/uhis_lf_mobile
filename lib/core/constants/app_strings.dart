/// Centralized, multilingual-ready content constants for UHIS Next.
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

import 'package:intl/intl.dart';

import '../i18n/app_locale.dart';
import '../models/dashboard_tier.dart';

/// App-wide identity strings.
abstract final class AppStrings {
  AppStrings._();

  static const String appName = 'UHIS Next';
  static const String appTagline = 'MedtronicLabs · Frontline Health';
  static const String poweredBy = 'Powered by Medtronic Labs';

  // ── ANC visit blocking ────────────────────────────────────────────────────
  static String get ancBlockedPostpartumTitle => AppLocale.isBangla ? 'এএনসি উপলব্ধ নয়' : 'ANC Not Available';
  static String get ancBlockedPostpartumMessage => AppLocale.isBangla
      ? 'এই রোগী একটি প্রসব বা পিএনসি ভিজিট সম্পন্ন করেছেন। প্রসবের পরে এএনসি সেবা শুরু করা যাবে না।'
      : 'This patient has completed a delivery or PNC visit. ANC assessments cannot be started after delivery.';
  static String get ancBlockedDuplicateTitle => AppLocale.isBangla ? 'আজকের এএনসি ইতিমধ্যে রেকর্ড হয়েছে' : 'ANC Already Recorded Today';
  static String get ancBlockedDuplicateMessage => AppLocale.isBangla
      ? 'আজকে এই রোগীর জন্য ইতিমধ্যে একটি এএনসি সেবা রেকর্ড করা হয়েছে। প্রতিদিন শুধুমাত্র একটি এএনসি ভিজিট অনুমোদিত।'
      : 'An ANC assessment has already been recorded for this patient today. Only one ANC visit is allowed per day.';

  // ── PW registration blocking ──────────────────────────────────────────────
  static String get pwAlreadyEnrolledTitle => AppLocale.isBangla ? 'ইতিমধ্যে নিবন্ধিত' : 'Already Registered';
  static String get pwAlreadyEnrolledMessage => AppLocale.isBangla
      ? 'এই রোগীর গর্ভবতী মা নিবন্ধন ইতিমধ্যে সম্পন্ন হয়েছে। পিডব্লিউ প্রোফাইল পুনরায় জমা দেওয়া যাবে না।'
      : 'Pregnant Woman registration has already been completed for this patient. The PW profile cannot be re-submitted.';
}

/// Shared, cross-screen labels reused in more than one feature.
abstract final class CommonStrings {
  CommonStrings._();

  static String get required => AppLocale.isBangla ? 'আবশ্যক' : 'Required';
  static String get or => AppLocale.isBangla ? 'অথবা' : 'or';
  static String get retry => AppLocale.isBangla ? 'পুনরায় চেষ্টা করুন' : 'Retry';
  static String get usePassword => AppLocale.isBangla ? 'পাসওয়ার্ড ব্যবহার করুন' : 'Use password';
  static String get unnamed => AppLocale.isBangla ? '(অনামিত)' : '(unnamed)';
  static String get remove => AppLocale.isBangla ? 'সরান' : 'Remove';
}

/// Login screen + login-flow feedback.
///
/// Pilot slice of the localization seam described at the top of this file —
/// these getters (not `static const`) check [AppLocale.isBangla] at read
/// time so `LoginStrings.signIn` etc. render in the current language without
/// any call site changing.
abstract final class LoginStrings {
  LoginStrings._();

  static String get usernameLabel =>
      AppLocale.isBangla ? 'ব্যবহারকারীর নাম' : 'Username';
  static String get passwordLabel =>
      AppLocale.isBangla ? 'পাসওয়ার্ড' : 'Password';
  static String get signIn => AppLocale.isBangla ? 'সাইন ইন' : 'Sign in';
  static String get loginFailed =>
      AppLocale.isBangla ? 'লগইন ব্যর্থ হয়েছে' : 'Login failed';
  static String get useDeviceUnlock =>
      AppLocale.isBangla ? 'ডিভাইস আনলক ব্যবহার করুন' : 'Use device unlock';
  static String get fromLockBanner => AppLocale.isBangla
      ? 'বায়োমেট্রিক বাতিল করা হয়েছে — পাসওয়ার্ড দিয়ে সাইন ইন করুন।'
      : 'Biometric cancelled — sign in with password.';
  static String get offlineUsePinHint =>
      'No internet connection. Use your PIN to continue working.';
  static String get forgotPassword =>
      AppLocale.isBangla ? 'পাসওয়ার্ড ভুলে গেছেন?' : 'Forgot password?';
  static String get forgotPasswordTitle =>
      AppLocale.isBangla ? 'পাসওয়ার্ড রিসেট করুন' : 'Reset password';
  static String get forgotPasswordHint =>
      AppLocale.isBangla
          ? 'আপনার নিবন্ধিত ইমেল ঠিকানা লিখুন'
          : 'Enter your registered email address';
  static String get forgotPasswordSend =>
      AppLocale.isBangla ? 'রিসেট লিংক পাঠান' : 'Send reset link';
  static String get forgotPasswordSuccess =>
      AppLocale.isBangla
          ? 'পাসওয়ার্ড রিসেট লিংক পাঠানো হয়েছে। আপনার ইমেল চেক করুন।'
          : 'Password reset link sent. Check your email.';
  static String get emailLabel =>
      AppLocale.isBangla ? 'ইমেল' : 'Email';
}

/// Lock / unlock screen + mid-session lock barrier.
///
/// Pilot slice of the localization seam (see [LoginStrings] doc comment).
/// `aponSushashthya`/`aponSushashthyaBn`/`programName`/`programSubtitle` are
/// NOT converted — they're the app's bilingual brand lockup, always shown
/// together regardless of UI language, not alternates of each other.
abstract final class LockStrings {
  LockStrings._();

  static String get welcomeBack =>
      AppLocale.isBangla ? 'ফিরে আসার জন্য স্বাগতম' : 'Welcome back';
  static String get verifyToAccess => AppLocale.isBangla
      ? 'আপনার ওয়ার্ড ড্যাশবোর্ড অ্যাক্সেস করতে আপনার পরিচয় যাচাই করুন।'
      : 'Verify your identity to access your ward dashboard.';
  static String get biometricCancelled =>
      AppLocale.isBangla ? 'বায়োমেট্রিক বাতিল করা হয়েছে' : 'Biometric cancelled';
  static String get unlockWithBiometrics =>
      AppLocale.isBangla ? 'ডিভাইস দিয়ে আনলক করুন' : 'Unlock with device';

  /// @deprecated Use [unlockWithBiometrics] instead. Kept for migration.
  static String get unlockWithPhonePasswordOrBiometrics =>
      unlockWithBiometrics;
  static String get profileLoading =>
      AppLocale.isBangla ? 'প্রোফাইল লোড হচ্ছে…' : 'Profile loading…';
  static String get offlinePasswordDisabled => AppLocale.isBangla
      ? 'আপনি অফলাইনে আছেন। পাসওয়ার্ড দিয়ে সাইন ইন করতে ইন্টারনেটে সংযুক্ত হন।'
      : 'You are offline. Connect to the internet to sign in with password.';

  // Connectivity status row (bottom of the lock screen).
  static String get onlineStatus => AppLocale.isBangla ? 'অনলাইন' : 'Online';
  static String get offlineLoginAvailable => AppLocale.isBangla
      ? 'অফলাইন লগইন উপলব্ধ'
      : 'Offline login available';

  // Profile detail row labels.
  static String get skIdLabel => AppLocale.isBangla ? 'এসকে আইডি' : 'SK ID';
  static String get upazilaLabel => AppLocale.isBangla ? 'উপজেলা' : 'UPAZILA';
  static String get nidLabel => AppLocale.isBangla ? 'এনআইডি' : 'NID';
  static String get wardLabel => AppLocale.isBangla ? 'ওয়ার্ড' : 'Ward';
  static String get households => AppLocale.isBangla ? 'পরিবার' : 'households';

  static String welcomeBackNamed(String name) => AppLocale.isBangla
      ? 'স্বাগতম, $name'
      : 'Welcome back, $name';

  static String get signInToStartYourDay => AppLocale.isBangla
      ? 'আপনার দিন শুরু করতে সাইন ইন করুন'
      : 'Sign in to start your day';
  static const String shasthyaKormi = 'SHASTHYA KORMI';
  static String get verifyFingerprint =>
      AppLocale.isBangla ? 'ফিঙ্গারপ্রিন্ট যাচাই করুন' : 'Verify fingerprint';
  static String get tapToPlaceFinger =>
      AppLocale.isBangla ? 'শুরু করতে সেন্সর স্পর্শ করুন' : 'Touch sensor to begin';
  static String get tapToPlaceFingerSubtitle => AppLocale.isBangla
      ? 'সাইন ইন করতে আপনার আঙুল রাখুন'
      : 'Tap to place your finger and sign in';
  static const String aponSushashthya = 'Apon Sushashthya';
  static const String aponSushashthyaBn = 'আপন সুস্বাস্থ্য';
  static String get splashTagline => AppLocale.isBangla
      ? 'বাংলাদেশের প্রতিটি পরিবারের জন্য এআই-চালিত কমিউনিটি স্বাস্থ্যসেবা'
      : 'AI-powered community health for every household in Bangladesh';
  static String get readingFingerprint =>
      AppLocale.isBangla ? 'ফিঙ্গারপ্রিন্ট পড়া হচ্ছে…' : 'Reading fingerprint…';
  static String get fingerprintVerified =>
      AppLocale.isBangla ? 'যাচাই সম্পন্ন!' : 'Verified!';
  static String get communityHealth =>
      AppLocale.isBangla ? 'কমিউনিটি স্বাস্থ্য' : 'Community Health';
  static const String programName = 'Apon Sushashthya';
  static String get programSubtitle =>
      AppLocale.isBangla ? 'আপন সুস্বাস্থ্য · কমিউনিটি স্বাস্থ্য' : 'Apon Sushashthya · Community Health';
  static String orUsePin(int len) => AppLocale.isBangla
      ? '$len-সংখ্যার পিন ব্যবহার করুন'
      : 'Use $len-digit PIN';
}

/// Android `BiometricPrompt` copy + biometric unlock messages.
abstract final class BiometricStrings {
  BiometricStrings._();

  static String get promptTitle => AppLocale.isBangla ? 'ফিঙ্গারপ্রিন্ট যাচাই' : 'Fingerprint verification';
  static String get promptHint => AppLocale.isBangla ? 'সেন্সরে আঙুল রাখুন' : 'Place your finger on the sensor';
  static String get cancelButton => CommonStrings.usePassword;
}

/// Auth/session error messages surfaced to the user.
abstract final class AuthStrings {
  AuthStrings._();

  static String get savedSessionExpired => AppLocale.isBangla
      ? 'সংরক্ষিত সেশন মেয়াদ শেষ — আবার সাইন ইন করুন'
      : 'Saved session expired — sign in again';
  static String get sessionExpired => AppLocale.isBangla ? 'সেশন মেয়াদ শেষ' : 'Session expired';
}

/// Dashboard screen: greeting, stat cards, biometric-offer dialog, menu.
abstract final class DashboardStrings {
  DashboardStrings._();

  // Greeting parts. Pilot slice of the localization seam (see
  // LoginStrings doc comment).
  static String get goodMorning =>
      AppLocale.isBangla ? 'শুভ সকাল' : 'Good Morning';
  static String get goodAfternoon =>
      AppLocale.isBangla ? 'শুভ অপরাহ্ন' : 'Good Afternoon';
  static String get goodEvening =>
      AppLocale.isBangla ? 'শুভ সন্ধ্যা' : 'Good Evening';
  static String get communityAtAGlance => AppLocale.isBangla
      ? 'আপনার কমিউনিটির সেবায়'
      : 'Serving your community';
  static const String refreshTooltip = 'Refresh';

  // Stat cards.
  static String get totalMembers =>
      AppLocale.isBangla ? 'মোট\nসদস্য' : 'Total\nMembers';
  static String get totalHouseholds =>
      AppLocale.isBangla ? 'মোট\nপরিবার' : 'Total\nHouseholds';
  static String get highRiskPatients =>
      AppLocale.isBangla ? 'উচ্চ-ঝুঁকি\nরোগী' : 'High-Risk\nPatients';
  static String get soonBadge => AppLocale.isBangla ? 'শীঘ্রই' : 'SOON';
  static String get lookUpMembers => AppLocale.isBangla
      ? 'সদস্য খুঁজতে উপরের সার্চ বার ব্যবহার করুন'
      : 'Use the search bar above to look up members';
  static String get lookUpHouseholds => AppLocale.isBangla
      ? 'পরিবার খুঁজতে উপরের সার্চ বার ব্যবহার করুন'
      : 'Use the search bar above to look up households';
  static String get aiTriageComingSoon => AppLocale.isBangla
      ? 'এআই ট্রায়াজ শীঘ্রই আসছে — এখনো যুক্ত করা হয়নি'
      : 'AI triage coming soon — not wired yet';

  // Biometric-offer dialog.
  static String get useDeviceUnlockTitle =>
      AppLocale.isBangla ? 'ডিভাইস আনলক ব্যবহার করবেন?' : 'Use device unlock?';
  static String get biometricOfferSupported => AppLocale.isBangla
      ? 'পরের বার আপনার ফিঙ্গারপ্রিন্ট, ফেস বা ডিভাইস পিন দিয়ে সাইন ইন করুন — পাসওয়ার্ডের প্রয়োজন নেই।'
      : 'Sign in next time with your fingerprint, face, or device PIN — no password needed.';
  static String get biometricOfferUnsupported => AppLocale.isBangla
      ? 'পরের বার আপনার ফিঙ্গারপ্রিন্ট, ফেস বা ডিভাইস পিন দিয়ে সাইন ইন করুন। এর আগে আপনাকে Android Settings-এ স্ক্রিন লক সেট আপ করতে হতে পারে।'
      : 'Sign in next time with your fingerprint, face, or device PIN. You may need to set up a screen lock in Android Settings first.';
  static String get notNow => AppLocale.isBangla ? 'এখন নয়' : 'Not now';
  static String get enable => AppLocale.isBangla ? 'চালু করুন' : 'Enable';
  static String get setUpScreenLock => AppLocale.isBangla
      ? 'Android Settings-এ একটি স্ক্রিন লক (পিন, প্যাটার্ন বা ফিঙ্গারপ্রিন্ট) সেট আপ করুন, তারপর আবার চেষ্টা করুন।'
      : 'Set up a screen lock (PIN, pattern, or fingerprint) in Android Settings, then try again.';
  static String get deviceUnlockEnabled =>
      AppLocale.isBangla ? 'ডিভাইস আনলক চালু হয়েছে' : 'Device unlock enabled';
  static String get deviceUnlockDisabled =>
      AppLocale.isBangla ? 'ডিভাইস আনলক বন্ধ হয়েছে' : 'Device unlock disabled';

  // Overflow menu. Pilot slice of the localization seam.
  static String get enableDeviceUnlock =>
      AppLocale.isBangla ? 'ডিভাইস আনলক চালু করুন' : 'Enable device unlock';
  static String get disableDeviceUnlock =>
      AppLocale.isBangla ? 'ডিভাইস আনলক বন্ধ করুন' : 'Disable device unlock';
  static String get signOut => AppLocale.isBangla ? 'সাইন আউট' : 'Sign out';

  // Confirmation dialogs.
  static String get confirmDisableDeviceUnlock => AppLocale.isBangla
      ? 'ডিভাইস আনলক বন্ধ করবেন?'
      : 'Disable device unlock?';
  static String get confirmDisableDeviceUnlockBody => AppLocale.isBangla
      ? 'পরের বার সাইন ইন করতে আপনাকে পাসওয়ার্ড বা পিন ব্যবহার করতে হবে।'
      : 'You will need to use your password or PIN to sign in next time.';
  static String get confirmSignOut =>
      AppLocale.isBangla ? 'সাইন আউট করবেন?' : 'Sign out?';
  static String get confirmSignOutBody => AppLocale.isBangla
      ? 'আপনাকে আবার পাসওয়ার্ড দিয়ে সাইন ইন করতে হবে।'
      : 'You will need to sign in again with your password.';
  static String get cancel => AppLocale.isBangla ? 'বাতিল' : 'Cancel';
  static String get disable => AppLocale.isBangla ? 'বন্ধ করুন' : 'Disable';

  static String couldNotEnable(Object error) => AppLocale.isBangla
      ? 'চালু করা যায়নি: $error'
      : 'Could not enable: $error';

  /// `Good Morning, Asha` style greeting.
  static String greetingNamed(String part, String name) => '$part, $name';

  // Last-refreshed relative-time labels.
  static String get updatedJustNow =>
      AppLocale.isBangla ? 'এইমাত্র আপডেট হয়েছে' : 'updated just now';
  static String updatedSecondsAgo(int s) => AppLocale.isBangla
      ? '$s সেকেন্ড আগে আপডেট হয়েছে'
      : 'updated ${s}s ago';
  static String updatedMinutesAgo(int m) => AppLocale.isBangla
      ? '$m মিনিট আগে আপডেট হয়েছে'
      : 'updated ${m}m ago';
  static String updatedHoursAgo(int h) => AppLocale.isBangla
      ? '$h ঘণ্টা আগে আপডেট হয়েছে'
      : 'updated ${h}h ago';
}

/// Settings menu strings.
abstract final class SettingsStrings {
  SettingsStrings._();

  static String get darkMode => AppLocale.isBangla ? 'ডার্ক মোড' : 'Dark Mode';
  static String get lightMode =>
      AppLocale.isBangla ? 'লাইট মোড' : 'Light Mode';
  static String get systemMode =>
      AppLocale.isBangla ? 'সিস্টেম মোড' : 'System Mode';
  static String get appearance => AppLocale.isBangla ? 'থিম' : 'Appearance';

  // ── Language row ──────────────────────────────────────────────────────
  static String get language =>
      AppLocale.isBangla ? 'ভাষা পছন্দ' : 'Language preference';
  static const String english = 'English';
  static const String bangla = 'বাংলা (Bangla)';

  // ── AI Settings row ───────────────────────────────────────────────────
  static String get aiSettings =>
      AppLocale.isBangla ? 'এআই সেটিংস' : 'AI Settings';
  static String get aiSettingsSubtitle => AppLocale.isBangla
      ? 'ভয়েস শনাক্তকরণ (VAD) টিউনিং'
      : 'Voice detection (VAD) tuning';

}

/// AI Settings sub-page — realtime-ASR VAD gate tuning UI. An internal/ops
/// tool (data-cost tuning for field conditions), not part of the CHW visit
/// flow, so English-only for now rather than the dual-language getter
/// pattern used for clinical-workflow copy elsewhere in this file.
abstract final class AiSettingsStrings {
  AiSettingsStrings._();

  static const String title = 'AI Settings';
  static const String appBarSubtitle = 'Realtime ASR — voice detection tuning';
  static const String sectionHeader = 'Voice activity gate (VAD)';
  static const String sectionDescription =
      'Controls which mic audio is worth sending to the server during a '
      'live scribe session — saves mobile data, since the CHW pays for '
      'their own connection. A gate that is too strict can silently drop '
      'real speech from a quiet speaker; too loose sends more silence than '
      'necessary. Changes apply to the next recording session.';
  static String get resetToDefaults => AppLocale.isBangla ? 'ডিফল্টে রিসেট করুন' : 'Reset to defaults';
  static String get resetConfirmation => AppLocale.isBangla ? 'টিউনিং ফ্যাক্টরি ডিফল্টে রিসেট হয়েছে।' : 'Tuning reset to factory defaults.';
  static String get savedConfirmation => AppLocale.isBangla ? 'টিউনিং সংরক্ষিত হয়েছে।' : 'Tuning saved.';

  static const String enterMarginLabel = 'Entry sensitivity';
  static const String enterMarginDesc =
      'How many dB above the room\'s noise floor a sound must be to start '
      'being treated as speech. Lower = more sensitive to quiet speakers, '
      'but more likely to also pick up background noise.';

  static const String sustainMarginLabel = 'Sustain sensitivity';
  static const String sustainMarginDesc =
      'Lower bar used to *stay* in speech mode once started, so a natural '
      'dip in volume mid-sentence doesn\'t cut the recording. Should stay '
      'below entry sensitivity.';

  static const String floorCeilingLabel = 'Noise floor ceiling';
  static const String floorCeilingDesc =
      'Caps how high the "background noise" estimate is allowed to climb '
      'in a loud room. Lower ceiling = easier for a quiet speaker to be '
      'heard over noisy surroundings.';

  static const String floorAlphaLabel = 'Noise floor adaptation speed';
  static const String floorAlphaDesc =
      'How quickly the background-noise estimate adjusts to the room. '
      'Higher = adapts faster to a changing environment.';

  static const String bootstrapLabel = 'Startup calibration window';
  static const String bootstrapDesc =
      'How long at the very start of a recording is assumed silent, to '
      'measure the room\'s baseline noise. Longer reduces the risk of an '
      'immediate opening sentence skewing that baseline.';

  static const String debounceLabel = 'Speech confirmation window';
  static const String debounceDesc =
      'How long a sound must stay above the entry threshold before it\'s '
      'confirmed as real speech (filters out a single click or cough).';

  static const String hangoverLabel = 'Trailing silence window';
  static const String hangoverDesc =
      'How long to keep recording after volume drops, to bridge a natural '
      'pause between words or sentences without cutting them apart.';

  static const String preRollLabel = 'Pre-speech buffer';
  static const String preRollDesc =
      'How much audio just before speech is confirmed gets included '
      'anyway, so the very first word isn\'t clipped.';
}

/// Real-Time ASR screen — live streaming transcription + live clinical
/// extraction against the ai-scribe-service, triggered from Settings.
/// Strings for Step 2 ambient listening / form-fill banner.
abstract final class Step2AsrStrings {
  Step2AsrStrings._();

  static String get bannerTitle => AppLocale.isBangla ? 'এআই ফর্ম ফিল' : 'AI Form Fill';
  static String get bannerSubtitle => AppLocale.isBangla
      ? 'স্বাভাবিকভাবে কথা বলুন — এআই ফর্মের ঘরগুলো পূরণ করবে।'
      : 'Speak naturally — AI fills form fields as you talk.';
  static String get startListening => AppLocale.isBangla ? 'শোনা শুরু করুন' : 'Start Listening';
  static String get stopListening => AppLocale.isBangla ? 'বন্ধ করুন' : 'Stop';
  static String get connecting => AppLocale.isBangla ? 'সংযুক্ত হচ্ছে…' : 'Connecting…';
  static String get listening => AppLocale.isBangla ? 'শুনছে…' : 'Listening…';
  static String get stopping => AppLocale.isBangla ? 'বন্ধ হচ্ছে…' : 'Stopping…';
  static String get notListening => AppLocale.isBangla ? 'ফর্ম ফিল শুরু করতে ট্যাপ করুন' : 'Tap to start ambient form-fill';
  static String get transcriptEmpty => AppLocale.isBangla
      ? 'কথা বলুন — ট্রান্সক্রিপ্ট এখানে দেখাবে।'
      : 'Speak — transcript will appear here.';
  static String get noFieldsYet => AppLocale.isBangla ? 'এখনো কোনো ঘর পূরণ হয়নি।' : 'No fields extracted yet.';
  static String get extractNow => AppLocale.isBangla ? 'এখনই পূরণ করুন' : 'Fill Now';
  static String get extracting => AppLocale.isBangla ? 'পূরণ হচ্ছে…' : 'Filling…';
  static String get notSupportedOnWeb => AppLocale.isBangla
      ? 'ওয়েব প্রিভিউতে স্টেপ ২ এআই ফর্ম ফিল উপলব্ধ নয়।'
      : 'Step 2 AI form-fill is not available in the web preview.';
  static String get micPermissionDenied => AppLocale.isBangla
      ? 'মাইক্রোফোনের অনুমতি প্রয়োজন।'
      : 'Microphone permission is required.';
  static String get fieldsFilled => AppLocale.isBangla ? 'টি ঘর পূরণ হয়েছে' : 'fields filled';
  static String get tapToEdit => AppLocale.isBangla
      ? 'নিচের ফর্মে হাইলাইট করা ঘরগুলো যাচাই করুন।'
      : 'Review highlighted fields in the form below.';
  static String get unmappedLabel => AppLocale.isBangla ? 'মেলেনি:' : 'Not matched:';
  static String get aiFilledBadge => AppLocale.isBangla ? 'এআই · যাচাই করুন' : 'AI · verify';

  static String filledCount(int n) => '$n $fieldsFilled';
}

abstract final class RealtimeAsrStrings {
  RealtimeAsrStrings._();

  static String get title => AppLocale.isBangla ? 'রিয়েল-টাইম এএসআর (বেটা)' : 'Real-Time ASR (Beta)';
  static String get subtitle => AppLocale.isBangla
      ? 'কথা বলার সময় লাইভ ট্রান্সক্রিপ্ট ও শনাক্ত করা লক্ষণ। ভিজিট নোট হিসেবে সংরক্ষিত হয় না — সেজন্য ভিজিটের সময় এআই স্ক্রাইব ব্যবহার করুন।'
      : 'Live transcript and detected symptoms while you talk. Not saved as a visit note — use AI Scribe during the visit for that.';
  static String get start => AppLocale.isBangla ? 'শোনা শুরু করুন' : 'Start Listening';
  static String get stop => AppLocale.isBangla ? 'থামুন' : 'Stop';
  static String get connecting => AppLocale.isBangla ? 'সংযুক্ত হচ্ছে…' : 'Connecting…';
  static String get listening => AppLocale.isBangla ? 'শোনা হচ্ছে…' : 'Listening…';
  static String get stopping => AppLocale.isBangla ? 'থামছে…' : 'Stopping…';
  static String get idle => AppLocale.isBangla ? 'নিষ্ক্রিয়' : 'Idle';
  static String get transcriptEmpty => AppLocale.isBangla
      ? 'শোনা শুরু করুন ট্যাপ করুন এবং কথা বলুন — লাইভ ট্রান্সক্রিপ্ট এখানে দেখাবে।'
      : 'Tap Start Listening and speak — the live transcript appears here.';
  static String get extractNow => AppLocale.isBangla ? 'এখনই বের করুন' : 'Extract Now';
  static String get extracting => AppLocale.isBangla ? 'বের করা হচ্ছে…' : 'Extracting…';
  static String get symptomsEmpty => AppLocale.isBangla ? 'এখনো কোনো তথ্য বের করা হয়নি।' : 'No extraction yet.';
  static String get notSupportedOnWeb => AppLocale.isBangla
      ? 'রিয়েল-টাইম এএসআর ওয়েব প্রিভিউতে পাওয়া যায় না — অ্যান্ড্রয়েড বা আইওএস অ্যাপ ব্যবহার করুন।'
      : 'Real-time ASR is not available in the web preview — use the Android or iOS app.';
  static String get micPermissionDenied => AppLocale.isBangla
      ? 'রিয়েল-টাইম এএসআরের জন্য মাইক্রোফোন অনুমতি প্রয়োজন।'
      : 'Microphone permission is required for real-time ASR.';
  static String get diagnosis => AppLocale.isBangla ? 'রোগ নির্ণয়' : 'Diagnosis';
  static String get bloodPressure => AppLocale.isBangla ? 'রক্তচাপ' : 'Blood Pressure';
  static String get bloodGlucose => AppLocale.isBangla ? 'রক্তের গ্লুকোজ' : 'Blood Glucose';
  static String get clinicalNotes => AppLocale.isBangla ? 'ক্লিনিক্যাল নোট' : 'Clinical Notes';
  static String get chiefComplaints => AppLocale.isBangla ? 'প্রধান অভিযোগ' : 'Chief Complaints';
  static String get comorbidities => AppLocale.isBangla ? 'সহরোগ' : 'Comorbidities';
  static String get complications => AppLocale.isBangla ? 'জটিলতা' : 'Complications';
}

/// Global search bar, scopes, result sections, and detail snackbars.
abstract final class SearchStrings {
  SearchStrings._();

  static String get barHint => AppLocale.isBangla ? 'নাম, মোবাইল, এনআইডি' : 'Name, Mobile, NID';
  static String get scopeAll => AppLocale.isBangla ? 'সব' : 'All';
  static String get scopePatients => AppLocale.isBangla ? 'রোগী' : 'Patients';
  static String get scopeHouseholds => AppLocale.isBangla ? 'পরিবার/খানা' : 'Households';
  static String get searchFailed => AppLocale.isBangla ? 'অনুসন্ধান ব্যর্থ হয়েছে — আবার চেষ্টা করুন।' : 'Search failed — try again.';
  static String get emptyPrompt => AppLocale.isBangla
      ? 'নাম, ফোন নম্বর, এনআইডি বা পরিবার নম্বর লিখুন'
      : 'Type a name, phone, NID, or household number';
  static String get noMatches => AppLocale.isBangla ? 'কোনো ফলাফল পাওয়া যায়নি।' : 'No matches.';
  static String get noPatientMatches => AppLocale.isBangla ? 'কোনো রোগী পাওয়া যায়নি।' : 'No patient matches.';
  static String get noHouseholdMatches => AppLocale.isBangla ? 'কোনো পরিবার/খানা পাওয়া যায়নি।' : 'No household matches.';
  static String get resultsCapped => AppLocale.isBangla ? 'ফলাফল সীমাবদ্ধ — অনুসন্ধান পরিমার্জন করুন' : 'Result list capped — refine your query';
  static String get patientDetailNotImplemented => AppLocale.isBangla
      ? 'রোগীর বিস্তারিত তথ্য এখনো পাওয়া যাচ্ছে না'
      : 'Patient detail not implemented';
  static String get householdDetailNotImplemented => AppLocale.isBangla
      ? 'পরিবারের বিস্তারিত তথ্য এখনো পাওয়া যাচ্ছে না'
      : 'Household detail not implemented';

  static String scanningHouseholds(int loaded, int cap) =>
      'Scanning households $loaded/$cap…';
  static String age(Object age) => 'Age $age';
  static String nid(Object nid) => 'NID $nid';
  static String householdNo(Object no) => 'No $no';
  static String memberCount(Object count) => '$count members';
  static String get scanNidTooltip => AppLocale.isBangla ? 'রোগী খুঁজতে এনআইডি বা কিউআর স্ক্যান করুন' : 'Scan NID or QR to find patient';
  static String get scanSearchTitle => AppLocale.isBangla ? 'স্ক্যান করে খুঁজুন' : 'Scan to Search';
  static String get scanSearchSubtitle => AppLocale.isBangla ? 'এনআইডি কার্ড বা কিউআর কোডে নির্দেশ করুন' : 'Point at NID card or QR code';
}

/// App-specific fallback PIN: setup (create + confirm), unlock, and management.
/// Length-aware copy, parameterized by [AppConfig.pinLength] (fixed at 4).
abstract final class PinStrings {
  PinStrings._();

  static String get confirmTitle => AppLocale.isBangla ? 'আপনার পিন নিশ্চিত করুন' : 'Confirm your PIN';
  static String get createSubtitle => AppLocale.isBangla
      ? 'ফিঙ্গারপ্রিন্ট পাওয়া না গেলে এই পিন ব্যবহার করুন।'
      : 'Use this PIN when fingerprint is unavailable.';
  static String get mismatch => AppLocale.isBangla ? 'পিন মিলছে না — আবার চেষ্টা করুন' : 'PINs do not match — try again';
  static String get wrong => AppLocale.isBangla ? 'ভুল পিন' : 'Incorrect PIN';
  static String get tooManyAttempts => AppLocale.isBangla
      ? 'অনেকবার চেষ্টা করা হয়েছে — পাসওয়ার্ড দিয়ে সাইন ইন করুন'
      : 'Too many attempts — sign in with password';
  static String get enabledSnack => AppLocale.isBangla ? 'পিন সক্রিয় হয়েছে' : 'PIN enabled';
  static String get disabledSnack => AppLocale.isBangla ? 'পিন নিষ্ক্রিয় হয়েছে' : 'PIN disabled';
  static String get enablePin => AppLocale.isBangla ? 'পিন সেট আপ করুন' : 'Set up PIN';
  static String get disablePin => AppLocale.isBangla ? 'পিন সরান' : 'Remove PIN';

  // Confirmation dialog.
  static String get confirmRemovePin => AppLocale.isBangla ? 'পিন সরাবেন?' : 'Remove PIN?';
  static String get confirmRemovePinBody => AppLocale.isBangla
      ? 'পরবর্তীবার সাইন ইন করতে আপনাকে পাসওয়ার্ড বা বায়োমেট্রিক্স ব্যবহার করতে হবে।'
      : 'You will need to use your password or biometrics to sign in next time.';
  static String get deleteKey => AppLocale.isBangla ? 'মুছুন' : 'Delete';

  static String createTitle(int len) => 'Create a $len-digit PIN';
  static String enterTitle(int len) => 'Enter your $len-digit PIN';
  static String usePin(int len) => 'Use $len-digit PIN';
  static String get usePinShort => AppLocale.isBangla ? 'পিন ব্যবহার করুন' : 'Use PIN';
  static String attemptsRemaining(int n) => '$n attempts remaining';
}

/// First-login data sync: the guided "downloading your ward" gate and the
/// dashboard data-freshness badge.
abstract final class SyncStrings {
  SyncStrings._();

  static String get title => AppLocale.isBangla ? 'আপনার ওয়ার্ড সেট আপ হচ্ছে' : 'Setting up your ward';
  static String get subtitle => AppLocale.isBangla
      ? 'অফলাইনে কাজ করার জন্য আপনার পরিবার ও রোগীদের তথ্য ডাউনলোড হচ্ছে।'
      : 'Downloading your households and patients so you can work offline.';

  // Per-entity labels used in progress lines and the data-as-of badge.
  static String get households => AppLocale.isBangla ? 'পরিবার/খানা' : 'households';
  static String get members => AppLocale.isBangla ? 'সদস্য' : 'members';
  static String get patients => AppLocale.isBangla ? 'রোগী' : 'patients';

  static String get done => AppLocale.isBangla ? 'যেতে প্রস্তুত' : 'Ready to go';
  static String get syncFailed => AppLocale.isBangla ? 'আপনার ডেটা ডাউনলোড সম্পন্ন করা যায়নি।' : 'We couldn\'t finish downloading your data.';
  static String get continueOffline => AppLocale.isBangla ? 'যা আছে তা দিয়ে চালিয়ে যান' : 'Continue with what we have';
  static String get retry => CommonStrings.retry;

  static String get refreshing => AppLocale.isBangla ? 'আপনার ডেটা আপডেট হচ্ছে…' : 'Updating your data…';
  static String get upToDate => AppLocale.isBangla ? 'ডেটা আপ টু ডেট' : 'Data up to date';

  /// `Downloading households… 120 of 340`.
  static String progressNamed(String entity, int done, int total) => total > 0
      ? 'Downloading $entity… $done of $total'
      : 'Downloading $entity… $done';

  /// `Households 340 · Patients 512` style summary line on completion.
  static String entityCount(String entity, int count) => '$entity $count';

  /// Relative-time data-freshness badge, e.g. `Data as of 2 days ago`.
  static String dataAsOf(String relative) => 'Data as of $relative';
  static String get dataAsOfJustNow => AppLocale.isBangla ? 'এইমাত্র আপডেট হওয়া ডেটা' : 'Data as of just now';
  static String dataAsOfMinutes(int m) => 'Data as of ${m}m ago';
  static String dataAsOfHours(int h) => 'Data as of ${h}h ago';
  static String dataAsOfDays(int d) => 'Data as of ${d}d ago';

  // Dashboard preparation phase (after sync, before navigation)
  static String get almostReady => AppLocale.isBangla ? 'প্রায় প্রস্তুত' : 'Almost ready';
  static String get preparingVisits => AppLocale.isBangla ? 'আজকের ভিজিটগুলো প্রস্তুত হচ্ছে…' : 'Preparing today\'s visits…';
  static String get preparingDashboard => AppLocale.isBangla ? 'আপনার ড্যাশবোর্ড সেট আপ হচ্ছে…' : 'Setting up your dashboard…';
}

/// First-login onboarding: security setup prompt.
abstract final class OnboardingStrings {
  OnboardingStrings._();

  static String get title => AppLocale.isBangla ? 'আপনার অ্যাকাউন্ট সুরক্ষিত করুন' : 'Secure Your Account';
  static String get subtitle => AppLocale.isBangla
      ? 'আপনার ডিভাইসের বায়োমেট্রিক্স ও ব্যাকআপ পিন ব্যবহার করে ইউএইচআইএস নেক্সটে দ্রুত ও নিরাপদ প্রবেশাধিকার সেট আপ করুন।'
      : 'Set up quick, secure access to UHIS Next using your device\'s biometrics and a backup PIN.';

  static String get biometricFeatureTitle => AppLocale.isBangla ? 'ডিভাইস আনলক' : 'Device Unlock';
  static String get biometricFeatureDesc => AppLocale.isBangla
      ? 'দ্রুত সাইন ইনের জন্য ফিঙ্গারপ্রিন্ট, ফেস বা ডিভাইস পিন ব্যবহার করুন।'
      : 'Use fingerprint, face, or device PIN for fast sign-in.';
  static String get biometricNotAvailable => AppLocale.isBangla
      ? 'এই বৈশিষ্ট্য সক্রিয় করতে অ্যান্ড্রয়েড সেটিংসে স্ক্রিন লক সেট আপ করুন।'
      : 'Set up a screen lock in Android Settings to enable this feature.';

  static String get pinFeatureDesc => AppLocale.isBangla
      ? 'বায়োমেট্রিক্স পাওয়া না গেলে ব্যাকআপ বিকল্প।'
      : 'A backup option when biometrics are unavailable.';

  static String get setupButton => AppLocale.isBangla ? 'সিকিউরিটি সেট আপ করুন' : 'Set Up Security';
  static String get skipButton => AppLocale.isBangla ? 'এখনের জন্য এড়িয়ে যান' : 'Skip for Now';
  static String get pinRequiredNote => AppLocale.isBangla
      ? 'দ্রষ্টব্য: পরে সেটিংস মেনু থেকে সিকিউরিটি বিকল্প সেট আপ করতে পারবেন।'
      : 'Note: You can set up security options later from the settings menu.';

  static String get skipConfirmTitle => AppLocale.isBangla ? 'সিকিউরিটি সেটআপ এড়িয়ে যাবেন?' : 'Skip Security Setup?';
  static String get skipConfirmBody => AppLocale.isBangla
      ? 'বায়োমেট্রিক বা পিন যাচাই ছাড়া অ্যাপ খোলার সময় প্রতিবার পাসওয়ার্ড দিতে হবে। পরে সেটিংস থেকে এগুলো সেট আপ করা যাবে।'
      : 'Without biometric or PIN authentication, you will need to enter your password each time you open the app. You can set these up later from settings.';
  static String get cancelButton => AppLocale.isBangla ? 'বাতিল' : 'Cancel';
  static String get skipAnywayButton => AppLocale.isBangla ? 'তবুও এড়িয়ে যান' : 'Skip Anyway';

  static String get notAvailable => AppLocale.isBangla ? 'পাওয়া যাচ্ছে না' : 'Not available';
  static String get biometricSetupFailed => AppLocale.isBangla
      ? 'ডিভাইস আনলক সক্রিয় করা যায়নি। পরে মেনু থেকে সক্রিয় করতে পারবেন।'
      : 'Could not enable device unlock. You can enable it later from the menu.';

  static String pinFeatureTitle(int len) => '$len-Digit Backup PIN';
}

/// Household / member list screens.
abstract final class HouseholdListStrings {
  HouseholdListStrings._();

  static String get loadError =>
      AppLocale.isBangla ? 'ডেটা লোড করা যায়নি' : 'Could not load data';
  static String get noMembers =>
      AppLocale.isBangla ? 'কোনো সদস্য পাওয়া যায়নি' : 'No members found';
  static String get unnamedHousehold =>
      AppLocale.isBangla ? '(নামহীন পরিবার)' : '(Unnamed household)';
  static String get unnamedMember =>
      AppLocale.isBangla ? '(নামহীন)' : '(Unnamed)';

  static String householdsCount(int n) =>
      AppLocale.isBangla ? '$n টি পরিবার' : '$n households';
  static String membersCount(int n) =>
      AppLocale.isBangla ? '$n জন সদস্য' : '$n members';

  // Header (v13 mockup: navy header, 🏠 title, combined live count)
  static String get headerTitle => AppLocale.isBangla
      ? '🏠 পরিবার ও রোগী'
      : '🏠 Households & Patients';
  static String headerSummary(int households, int patients) =>
      '${householdsCount(households)} · ${_patientsCount(patients)}';
  static String _patientsCount(int n) => AppLocale.isBangla
      ? '$n জন রোগী'
      : '$n patient${n == 1 ? '' : 's'}';
  static String get searchHint => AppLocale.isBangla
      ? 'নাম, বাড়ি নং বা গ্রাম দিয়ে খুঁজুন…'
      : 'Search by name, house no. or village…';

  // Household-card inline other-members panel
  static String otherMembersToggle(int n) => AppLocale.isBangla
      ? '+$n জন অন্যান্য পরিবার সদস্য'
      : '+$n other household member${n == 1 ? '' : 's'}';
  static String get enrolledTag =>
      AppLocale.isBangla ? 'নথিভুক্ত' : 'Enrolled';

  // Manual server refresh
  static String refreshSummary(int patients, int assessments, int followUps) =>
      AppLocale.isBangla
          ? 'হালনাগাদ: $patients জন রোগী · $assessments টি মূল্যায়ন · $followUps টি ফলো-আপ'
          : 'Updated: $patients patients · $assessments assessments · '
              '$followUps follow-ups';
  static String refreshFailed(String error) => AppLocale.isBangla
      ? 'রিফ্রেশ ব্যর্থ হয়েছে: $error'
      : 'Refresh failed: $error';
}

/// Household detail screen strings.
abstract final class HouseholdDetailStrings {
  HouseholdDetailStrings._();

  static String get unnamedHousehold =>
      AppLocale.isBangla ? '(নামহীন পরিবার)' : '(Unnamed household)';
  static String get householdMembers =>
      AppLocale.isBangla ? 'পরিবারের সদস্য' : 'Household Members';
  static String get noMembers =>
      AppLocale.isBangla ? 'কোনো সদস্য পাওয়া যায়নি' : 'No members found';
  static String get notAvailable => AppLocale.isBangla ? 'নেই' : 'N/A';
  static String get householdNumber =>
      AppLocale.isBangla ? 'পরিবার নং' : 'Household No.';
  static String get village => AppLocale.isBangla ? 'গ্রাম' : 'Village';
  static String get ssName =>
      AppLocale.isBangla ? 'স্বাস্থ্য কর্মী' : 'Shasthya Shebika';
  static String get lastVisitDate =>
      AppLocale.isBangla ? 'সর্বশেষ ভিজিট' : 'Last Visit';
  static String get neverVisited =>
      AppLocale.isBangla ? 'কখনো ভিজিট হয়নি' : 'Never visited';
  static String get noSsAssigned =>
      AppLocale.isBangla ? 'নির্ধারিত নেই' : 'Not assigned';
  static String get back => AppLocale.isBangla ? 'পেছনে' : 'Back';
  static String get loadingMembers =>
      AppLocale.isBangla ? 'সদস্য লোড হচ্ছে…' : 'Loading members…';
  static String get couldNotLoadMembers => AppLocale.isBangla
      ? 'সদস্য লোড করা যায়নি'
      : 'Could not load members';
  static String get loadMembers =>
      AppLocale.isBangla ? 'সদস্য লোড করুন' : 'Load members';
  static String get householdIdNotAvailable => AppLocale.isBangla
      ? 'পরিবার আইডি পাওয়া যায়নি'
      : 'Household ID not available';

  static String memberDataNotLoaded(int count) => AppLocale.isBangla
      ? 'এই পরিবারে $count জন সদস্য আছে।\nডেটা সিঙ্ক হলে বিস্তারিত সদস্যের তথ্য পাওয়া যাবে।'
      : 'This household has $count members.\nDetailed member information will be available once data is synced.';
}

/// AI Worklist (Screen 2): chip filter labels, programme tags, urgent banner,
/// last-synced strip, and the empty/error states. All literal copy for the
/// worklist surface lives here — widgets never inline strings.
abstract final class WorklistStrings {
  WorklistStrings._();

  // Programme labels — descriptive visit-type labels shown on patient cards.
  static String get programmeImci => AppLocale.isBangla ? 'শিশু ভিজিট' : 'Child Visit';
  static String get programmeAnc => AppLocale.isBangla ? 'এএনসি ভিজিট' : 'ANC Visit';
  static String get programmePnc => AppLocale.isBangla ? 'পিএনসি ভিজিট' : 'PNC Visit';
  static String get programmeNcd => AppLocale.isBangla ? 'এনসিডি চেক' : 'NCD Check';
  static String get programmeTb => AppLocale.isBangla ? 'টিবি চেক' : 'TB Check';
  static String get programmeEpi => AppLocale.isBangla ? 'টিকা' : 'Vaccination';
  static String get programmeNutrition => AppLocale.isBangla ? 'পুষ্টি' : 'Nutrition';
  static String get programmeFamilyPlanning => AppLocale.isBangla ? 'পরিবার পরিকল্পনা' : 'Family Planning';
  static String get programmeCataract => AppLocale.isBangla ? 'ছানি' : 'Cataract';
  static String get programmeEyeCare => AppLocale.isBangla ? 'চোখের যত্ন' : 'Eye Care';
  static String get programmeUnknown => AppLocale.isBangla ? 'নির্ধারিত ভিজিট' : 'Scheduled Visit';
  static String get selectService => AppLocale.isBangla ? '📋  সেবা নির্বাচন করুন' : '📋  Select service';

  // Chip filters.
  static String get filterAll => AppLocale.isBangla ? 'সকল' : 'All';
  static String get filterImci => AppLocale.isBangla ? 'আইএমসিআই' : 'IMCI';
  static String get filterAnc => AppLocale.isBangla ? 'এএনসি' : 'ANC';
  static String get filterNcd => AppLocale.isBangla ? 'এনসিডি' : 'NCD';
  static String get filterTb => AppLocale.isBangla ? 'টিবি' : 'TB';

  // Urgent banner.
  static String get urgentBadge => AppLocale.isBangla ? 'জরুরি' : 'URGENT';
  static String urgentBannerFmt(String name) => AppLocale.isBangla
      ? 'সর্বোচ্চ ঝুঁকি: $name — প্রথমে পর্যালোচনা করুন।'
      : 'Highest risk: $name — review first.';

  // Risk band labels (also serve as accessibility hints).
  static String get bandUrgent => AppLocale.isBangla ? 'জরুরি' : 'Urgent';
  static String get bandHigh => AppLocale.isBangla ? 'উচ্চ' : 'High';
  static String get bandModerate => AppLocale.isBangla ? 'মাঝারি' : 'Moderate';
  static String get bandLow => AppLocale.isBangla ? 'কম' : 'Low';

  // Empty / error / sync strip.
  static String get emptyTitle => AppLocale.isBangla ? 'আপনার ওয়ার্কলিস্টে এখনো কোনো রোগী নেই' : 'No patients on your worklist yet';
  static String get emptyBody => AppLocale.isBangla
      ? 'আপনার রোগীদের তথ্য আনতে সংযোগ থাকলে সার্ভারের সাথে সিঙ্ক করুন।'
      : 'Sync with the server when you have a connection to pull your patients.';
  static String get loadFailed => AppLocale.isBangla ? 'ওয়ার্কলিস্ট লোড করা যায়নি' : 'Could not load worklist';
  static String get syncNow => AppLocale.isBangla ? 'এখনই সিঙ্ক করুন' : 'Sync now';
  static String get syncing => AppLocale.isBangla ? 'সিঙ্ক হচ্ছে…' : 'Syncing…';
  static String get syncedJustNow => AppLocale.isBangla ? 'এইমাত্র সিঙ্ক হয়েছে' : 'Synced just now';
  static String get offlineSuffix => AppLocale.isBangla ? 'অফলাইন' : 'Offline';
  static String syncedMinutes(int m) => AppLocale.isBangla ? '${m} মিনিট আগে সিঙ্ক হয়েছে' : 'Synced ${m}m ago';
  static String syncedHours(int h) => AppLocale.isBangla ? '${h} ঘণ্টা আগে সিঙ্ক হয়েছে' : 'Synced ${h}h ago';
  static String syncedDays(int d) => AppLocale.isBangla ? '${d} দিন আগে সিঙ্ক হয়েছে' : 'Synced ${d}d ago';
  static String syncFailed(String reason) => AppLocale.isBangla ? 'সিঙ্ক ব্যর্থ হয়েছে: $reason' : 'Sync failed: $reason';
  static String syncSummary(int patients) => AppLocale.isBangla
      ? (patients == 0 ? 'কোনো নতুন আপডেট নেই' : '$patients জন রোগী আপডেট হয়েছে')
      : (patients == 0 ? 'No new updates' : 'Updated $patients patient(s)');

  // Card affordances.
  static String ageFmt(int age) => AppLocale.isBangla ? 'বয়স $age' : 'Age $age';
  static String get noAge => AppLocale.isBangla ? 'বয়স —' : 'Age —';
  static String get tapForDetails => AppLocale.isBangla ? 'বিস্তারিত দেখতে ট্যাপ করুন' : 'Tap for details';
  static String get rationaleHeader => AppLocale.isBangla ? 'এই স্কোরের কারণ' : 'Why this score';

  // Rationale bottom sheet.
  static String get whyThisScore => AppLocale.isBangla ? 'এই স্কোর কেন?' : 'Why this score?';
  static String get urgencyNow => AppLocale.isBangla ? 'এখনই' : 'Now';
  static String get urgencyToday => AppLocale.isBangla ? 'আজ' : 'Today';
  static String get urgencyThisWeek => AppLocale.isBangla ? 'এই সপ্তাহে' : 'This week';
  static String get urgencyRoutine => AppLocale.isBangla ? 'নিয়মিত' : 'Routine';
  static String get riskDriversHeader => AppLocale.isBangla ? 'ঝুঁকির কারণসমূহ' : 'Risk drivers';
  static String get modelVersionLabel => AppLocale.isBangla ? 'মডেল সংস্করণ' : 'Model version';
  static String get computedAtLabel => AppLocale.isBangla ? 'গণনা করা হয়েছে' : 'Computed';
  static String get humanReviewRequired => AppLocale.isBangla ? 'মানবিক পর্যালোচনা প্রয়োজন' : 'Human review required';
  static String get closeSheet => AppLocale.isBangla ? 'বন্ধ করুন' : 'Close';
}

/// Patient Context Screen (stub) strings. Full design lives in a later spec.
abstract final class PatientContextStrings {
  PatientContextStrings._();

  static String get fallbackTitle => AppLocale.isBangla ? 'রোগী' : 'Patient';
  static String get loading =>
      AppLocale.isBangla ? 'রোগীর তথ্য লোড হচ্ছে…' : 'Loading patient…';
  static String get notFound => AppLocale.isBangla
      ? 'রোগী স্থানীয় ক্যাশে নেই'
      : 'Patient not in local cache';
  static String get idLabel =>
      AppLocale.isBangla ? 'রোগীর আইডি' : 'Patient ID';
  static String get householdLabel =>
      AppLocale.isBangla ? 'পরিবার' : 'Household';
  static String get villageLabel => AppLocale.isBangla ? 'গ্রাম' : 'Village';
  static String get programmesLabel =>
      AppLocale.isBangla ? 'প্রোগ্রাম' : 'Programmes';
  static String get riskLabel => AppLocale.isBangla ? 'ঝুঁকি' : 'Risk';
  static String get sectionRecentVisits =>
      AppLocale.isBangla ? 'সাম্প্রতিক ভিজিট' : 'Recent visits';
  static String get sectionVitals =>
      AppLocale.isBangla ? 'ভাইটালস' : 'Vitals';
  static String get sectionAiSuggestions =>
      AppLocale.isBangla ? 'এআই পরামর্শ' : 'AI suggestions';
  static String get sectionActions =>
      AppLocale.isBangla ? 'কার্যক্রম' : 'Actions';
  static String get comingSoon => AppLocale.isBangla
      ? 'ভবিষ্যতের সংস্করণে আসছে'
      : 'Coming in a future release';
  static String get refresh =>
      AppLocale.isBangla ? 'সার্ভার থেকে রিফ্রেশ করুন' : 'Refresh from server';
  static String get refreshing =>
      AppLocale.isBangla ? 'রিফ্রেশ হচ্ছে…' : 'Refreshing…';
  static String get refreshDone =>
      AppLocale.isBangla ? 'রোগীর তথ্য রিফ্রেশ হয়েছে' : 'Patient refreshed';
  static String get refreshFailed =>
      AppLocale.isBangla ? 'রিফ্রেশ ব্যর্থ হয়েছে' : 'Refresh failed';

  // ── Action buttons ───────────────────────────────────────────────────────
  static String get actionsTitle =>
      AppLocale.isBangla ? 'কার্যক্রম' : 'Actions';
  static String get startVisit =>
      AppLocale.isBangla ? 'ভিজিট শুরু করুন' : 'Start Visit';
  static String get callHousehold =>
      AppLocale.isBangla ? 'কল করুন' : 'Call';
  static String get callComingSoon => AppLocale.isBangla
      ? 'পরিবারকে কল করার সুবিধা শীঘ্রই আসছে'
      : 'Call household coming soon';

  static String get storedDataTitle =>
      AppLocale.isBangla ? 'সংরক্ষিত তথ্য' : 'Stored data';

  // ── HTML detail composition ──────────────────────────────────────────────
  static String get backToWorklist =>
      AppLocale.isBangla ? 'ওয়ার্কলিস্টে ফিরে যান' : 'Back to worklist';
  static String get sayHelloFirst =>
      AppLocale.isBangla ? ' প্রথমে সালাম দিন' : ' Say hello first';
  // Bilingual communication script the SK reads aloud to the patient — shown
  // regardless of the app's own UI language, not a language toggle target.
  static const String greetingBangla = 'আপনাদের কেমন আছেন? রোগী কেমন আছে?';
  static const String greetingEnglish =
      'How is everyone? How is the patient today?';
  static String aiSummaryLead(String name) => AppLocale.isBangla
      ? '$name-এর আজ নিম্নলিখিত ঝুঁকির কারণগুলো বিবেচনা করা প্রয়োজন।'
      : '$name has the following risk drivers worth addressing today.';

  static String get allAssessmentsTitle =>
      AppLocale.isBangla ? 'সব মূল্যায়ন' : 'All assessments';

  // ── Header ────────────────────────────────────────────────────────────
  static String get urgentBadge => AppLocale.isBangla ? 'জরুরি' : 'URGENT';
  static String ageLabel(int age) =>
      AppLocale.isBangla ? 'বয়স $age' : 'Age $age';
  static String ageMonthsLabel(int months) => AppLocale.isBangla
      ? '$months মাস'
      : '$months month${months == 1 ? '' : 's'}';
  static String get ageUnderOneYear =>
      AppLocale.isBangla ? '< ১ বছর' : '< 1 yr';
  static String householdFallback(String householdId) =>
      AppLocale.isBangla ? 'পরিবার $householdId' : 'HH $householdId';
  static String get pregnantChip =>
      AppLocale.isBangla ? 'গর্ভবতী' : 'Pregnant';

  // ── Assessments section ──────────────────────────────────────────────
  static String get noAssessmentsYet =>
      AppLocale.isBangla ? 'এখনো কোনো মূল্যায়ন নেই' : 'No assessments yet';
  static String assessmentsTotal(int n) =>
      AppLocale.isBangla ? '$n টি মোট' : '$n total';
  static String viewAllAssessments(int n) => AppLocale.isBangla
      ? 'সব $n টি মূল্যায়ন দেখুন'
      : 'View all $n assessments';
  static String visitNumberLabel(int n) =>
      AppLocale.isBangla ? 'ভিজিট $n' : 'Visit $n';
  static String get latestBadge =>
      AppLocale.isBangla ? 'সর্বশেষ' : 'Latest';
  static String visitOnLabel(String date) =>
      AppLocale.isBangla ? '$date তারিখে ভিজিট' : 'Visit on $date';
  static String get close => AppLocale.isBangla ? 'বন্ধ করুন' : 'Close';
  static String get serviceLabel => AppLocale.isBangla ? 'সেবা' : 'Service';
  static String get visitNumberFieldLabel =>
      AppLocale.isBangla ? 'ভিজিট নম্বর' : 'Visit Number';
  static String get encounterIdLabel =>
      AppLocale.isBangla ? 'এনকাউন্টার আইডি' : 'Encounter ID';
  static String get memberIdLabel =>
      AppLocale.isBangla ? 'সদস্য আইডি' : 'Member ID';
  static String get referralStatusLabel =>
      AppLocale.isBangla ? 'রেফারেল অবস্থা' : 'Referral Status';
  static String get referralReasonLabel =>
      AppLocale.isBangla ? 'রেফারেলের কারণ' : 'Referral Reason';
  static String get nextFollowUpLabel =>
      AppLocale.isBangla ? 'পরবর্তী ফলো-আপ' : 'Next Follow-up';

  // ── Clinical field labels ────────────────────────────────────────────
  static String get yes => AppLocale.isBangla ? 'হ্যাঁ' : 'Yes';
  static String get no => AppLocale.isBangla ? 'না' : 'No';
  static String get clinicalFindingsTitle =>
      AppLocale.isBangla ? 'ক্লিনিক্যাল ফলাফল' : 'Clinical Findings';
  static String get ncdFindingsTitle =>
      AppLocale.isBangla ? 'NCD স্ক্রিনিং ফলাফল' : 'NCD Screening Findings';
  static String get ancFindingsTitle => AppLocale.isBangla
      ? 'প্রসবপূর্ব সেবার ফলাফল'
      : 'Antenatal Care Findings';
  static String get pncFindingsTitle => AppLocale.isBangla
      ? 'প্রসবোত্তর সেবার ফলাফল'
      : 'Postnatal Care Findings';
  static String get childHealthFindingsTitle =>
      AppLocale.isBangla ? 'শিশু স্বাস্থ্য ফলাফল' : 'Child Health Findings';
  static String get tbFindingsTitle =>
      AppLocale.isBangla ? 'TB স্ক্রিনিং ফলাফল' : 'TB Screening Findings';
  static String get bloodPressureLabel =>
      AppLocale.isBangla ? 'রক্তচাপ' : 'Blood Pressure';
  static String glucoseLabel(String? type) {
    if (AppLocale.isBangla) {
      return type != null ? 'গ্লুকোজ ($type)' : 'গ্লুকোজ';
    }
    return type != null ? 'Glucose ($type)' : 'Glucose';
  }
  static String get heightLabel => AppLocale.isBangla ? 'উচ্চতা' : 'Height';
  static String get weightLabel => AppLocale.isBangla ? 'ওজন' : 'Weight';
  static const String bmiLabel = 'BMI';
  static String get haemoglobinLabel =>
      AppLocale.isBangla ? 'হিমোগ্লোবিন' : 'Haemoglobin';
  static String get smokingLabel =>
      AppLocale.isBangla ? 'ধূমপান' : 'Smoking';
  static String get alcoholLabel =>
      AppLocale.isBangla ? 'মদ্যপান' : 'Alcohol';
  static String get ancVisitLabel =>
      AppLocale.isBangla ? 'ANC ভিজিট' : 'ANC Visit';
  static String get gestationalAgeLabel =>
      AppLocale.isBangla ? 'গর্ভকালীন বয়স' : 'Gestational Age';
  static String get fetusesLabel =>
      AppLocale.isBangla ? 'ভ্রূণ সংখ্যা' : 'Fetuses';
  static String get fundalHeightLabel =>
      AppLocale.isBangla ? 'ফান্ডাল হাইট' : 'Fundal Height';
  static String get fetalMovementLabel =>
      AppLocale.isBangla ? 'ভ্রূণের নড়াচড়া' : 'Fetal Movement';
  static String get pncVisitLabel =>
      AppLocale.isBangla ? 'PNC ভিজিট' : 'PNC Visit';
  static String get breastfeedingLabel =>
      AppLocale.isBangla ? 'বুকের দুধ খাওয়ানো' : 'Breastfeeding';
  static const String muacLabel = 'MUAC';
  static String get temperatureLabel =>
      AppLocale.isBangla ? 'তাপমাত্রা' : 'Temperature';
  static String get diagnosisLabel =>
      AppLocale.isBangla ? 'রোগ নির্ণয়' : 'Diagnosis';
  static String get coughDurationLabel =>
      AppLocale.isBangla ? 'কাশির স্থায়িত্ব' : 'Cough Duration';
  static String get diabetesLabel =>
      AppLocale.isBangla ? 'ডায়াবেটিস' : 'Diabetes';
  static String get tbContactLabel =>
      AppLocale.isBangla ? 'TB সংস্পর্শ' : 'TB Contact';
  static const String gravidaParityLabel = 'G/P';
  static String get normal => AppLocale.isBangla ? 'স্বাভাবিক' : 'Normal';
  static String get abnormal =>
      AppLocale.isBangla ? 'অস্বাভাবিক' : 'Abnormal';

  // ── AI summary ────────────────────────────────────────────────────────
  static String get aiSummaryBadge =>
      AppLocale.isBangla ? '✦ এআই সারাংশ' : '✦ AI SUMMARY';
  static String get aiReadHerRecordBadge => AppLocale.isBangla
      ? '✦ এআই তার রেকর্ড পড়েছে'
      : '✦ AI READ HER RECORD';
  static String riskReasonChip(String reason) => '⚠ $reason';

  // ── Same-household strip ─────────────────────────────────────────────
  static String get sameHousehold =>
      AppLocale.isBangla ? 'একই পরিবার' : 'Same household';
  static String get viewHouseholdDetails => AppLocale.isBangla
      ? 'পরিবারের বিবরণ দেখুন'
      : 'View household details';
  static String get unknownMemberName =>
      AppLocale.isBangla ? 'অজানা' : 'Unknown';
  static String viewPatientSemantics(String name, int? age) => AppLocale.isBangla
      ? 'রোগী $name${age != null ? ', বয়স $age' : ''} দেখুন'
      : 'View patient $name${age != null ? ', age $age' : ''}';

  static String get statusIndicatorsTitle =>
      AppLocale.isBangla ? 'অবস্থা নির্দেশক' : 'Status Indicators';

  // ── Assessment list fallbacks ────────────────────────────────────────
  static String get genericAssessmentLabel =>
      AppLocale.isBangla ? 'মূল্যায়ন' : 'Assessment';
  static String viewAssessmentSemantics(String type, String date) =>
      AppLocale.isBangla
          ? '$date তারিখে $type মূল্যায়ন দেখুন'
          : 'View $type assessment on $date';
}

/// Copy for the patient profile card — collapsible demographic section
/// shown inside PatientContextScreen below the header.
abstract final class PatientProfileStrings {
  PatientProfileStrings._();

  static String get profileTitle =>
      AppLocale.isBangla ? 'রোগীর প্রোফাইল' : 'Patient Profile';
  static String get showMore =>
      AppLocale.isBangla ? 'সম্পূর্ণ প্রোফাইল দেখুন' : 'Show full profile';
  static String get hide =>
      AppLocale.isBangla ? 'প্রোফাইল লুকান' : 'Hide profile';
  static String get servicesProvidedTitle =>
      AppLocale.isBangla ? 'প্রদত্ত সেবা' : 'Services Provided';
  static String get recentStatusTitle =>
      AppLocale.isBangla ? 'সাম্প্রতিক অবস্থা' : 'Recent Status';

  static String get sectionIdentity =>
      AppLocale.isBangla ? 'পরিচয়' : 'Identity';
  static String get sectionLocation =>
      AppLocale.isBangla ? 'অবস্থান' : 'Location';
  static String get sectionContact =>
      AppLocale.isBangla ? 'যোগাযোগ' : 'Contact';
  static String get sectionCareTeam =>
      AppLocale.isBangla ? 'সেবা দল' : 'Care Team';
  static String get sectionHousehold =>
      AppLocale.isBangla ? 'পরিবারে ভূমিকা' : 'Household Role';

  static const String labelNid = 'NID / BRN';
  static String get labelGender => AppLocale.isBangla ? 'লিঙ্গ' : 'Gender';
  static String get labelDob =>
      AppLocale.isBangla ? 'জন্ম তারিখ' : 'Date of Birth';
  static String get labelIdType =>
      AppLocale.isBangla ? 'আইডির ধরন' : 'ID Type';
  static String get labelMaritalStatus =>
      AppLocale.isBangla ? 'বৈবাহিক অবস্থা' : 'Marital Status';
  static String get labelDisability =>
      AppLocale.isBangla ? 'প্রতিবন্ধিতা' : 'Disability';
  static String get labelVillage => AppLocale.isBangla ? 'গ্রাম' : 'Village';
  static String get labelPhone => AppLocale.isBangla ? 'ফোন' : 'Phone';
  static String get labelIsHouseholdHead =>
      AppLocale.isBangla ? 'পরিবার প্রধান' : 'HH Head';
  static String get labelRelation => AppLocale.isBangla
      ? 'পরিবার প্রধানের সাথে সম্পর্ক'
      : 'Relation to HH Head';
  static String get labelSk =>
      AppLocale.isBangla ? 'নিযুক্ত এসকে' : 'Assigned SK';
  static String get labelGuardian =>
      AppLocale.isBangla ? 'অভিভাবক' : 'Guardian';
  static String get labelMother =>
      AppLocale.isBangla ? 'মায়ের রেফ' : 'Mother Ref';
  static const String labelGps = 'GPS';
  static String get labelIsPregnant =>
      AppLocale.isBangla ? 'গর্ভবতী' : 'Pregnant';
  static String get yes => AppLocale.isBangla ? 'হ্যাঁ' : 'Yes';
  static String get no => AppLocale.isBangla ? 'না' : 'No';
  static const String notAvailable = '—';
  static String get dialFailed => AppLocale.isBangla ? 'ডায়ালার খোলা যায়নি' : 'Could not open the dialer';
  static String get mapsOpenFailed => AppLocale.isBangla ? 'মানচিত্র খোলা যায়নি' : 'Could not open maps';

  static String get activeCareThreads => AppLocale.isBangla ? 'সক্রিয় সেবা থ্রেড' : 'Active care threads';
  static String get aiInsight => AppLocale.isBangla ? 'এআই অন্তর্দৃষ্টি' : 'AI Insight';
  static String get pregnancyProgress => AppLocale.isBangla ? 'গর্ভাবস্থার অগ্রগতি' : 'Pregnancy progress';
  static String get careHistory => AppLocale.isBangla ? 'সেবার ইতিহাস' : 'Care history';
  static String get noVitalsYet => AppLocale.isBangla ? 'এখনো কোনো ভাইটাল রেকর্ড হয়নি' : 'No vitals recorded yet';
  static String get showLess => AppLocale.isBangla ? 'কম দেখান' : 'Show less';
  static String showMoreEntries(int n) => AppLocale.isBangla ? 'আরো $n টি দেখান' : 'Show $n more';
  static String get vitalsConfirmAtVisit => AppLocale.isBangla ? 'আজকের ভিজিটে নিশ্চিত করুন' : "Confirm at today's visit";
  static String get weeksToGo => AppLocale.isBangla ? 'সপ্তাহ বাকি' : 'weeks to go';
  static String get visitsCompleted => AppLocale.isBangla ? 'ভিজিট সম্পন্ন' : 'Visits completed';
  static String get enrolled => AppLocale.isBangla ? 'নিবন্ধিত' : 'Enrolled';
  static String get dosesCompleted => AppLocale.isBangla ? 'ডোজ সম্পন্ন' : 'Doses completed';
  static String get dosesOverdue => AppLocale.isBangla ? 'ডোজ মেয়াদোত্তীর্ণ' : 'Doses overdue';
  static String get growthTrend => AppLocale.isBangla ? 'বৃদ্ধির ধারা' : 'Growth trend';
  static String get bpTarget => AppLocale.isBangla ? 'বিপি লক্ষ্যমাত্রা' : 'BP target';
  static String get lastCheckup => AppLocale.isBangla ? 'শেষ চেকআপ' : 'Last check-up';
  static String get medicationAdherence => AppLocale.isBangla ? 'ওষুধ সেবনের নিয়মানুবর্তিতা' : 'Medication adherence';
  static String get bloodSugar => AppLocale.isBangla ? 'রক্তের শর্করা (খালি পেটে)' : 'Blood sugar (fasting)';
  static String get pncVisitsDone => AppLocale.isBangla ? 'পিএনসি ভিজিট সম্পন্ন' : 'PNC visits done';
  static String get delivery => AppLocale.isBangla ? 'প্রসব' : 'Delivery';
  static String get newbornAge => AppLocale.isBangla ? 'নবজাতকের বয়স' : 'Newborn age';
  static String get breastfeeding => AppLocale.isBangla ? 'বুকের দুধ খাওয়ানো' : 'Breastfeeding';
  static String get aiInsightUnavailable => AppLocale.isBangla
      ? 'এআই অন্তর্দৃষ্টি অনুপলব্ধ — রোগীর রেকর্ড ম্যানুয়ালি পরীক্ষা করুন'
      : 'AI insight unavailable — check patient record manually';
  static String get trendsTitle => AppLocale.isBangla ? 'প্রবণতা' : 'Trends';
  static String get bpChartLabel => AppLocale.isBangla ? 'রক্তচাপ' : 'Blood Pressure';
  static String get bgChartLabel => AppLocale.isBangla ? 'রক্তের শর্করা' : 'Blood Glucose';
  static String get viewAllTrends => AppLocale.isBangla ? 'সব প্রবণতা দেখুন' : 'View all trends';
  static String get allTrendsTitle => AppLocale.isBangla ? 'সব প্রবণতা' : 'All Trends';
  static String get weightChartLabel => AppLocale.isBangla ? 'ওজন' : 'Weight';
  static String get spO2ChartLabel => AppLocale.isBangla ? 'এসপিও₂' : 'SpO₂';
  static String get haemoglobinChartLabel => AppLocale.isBangla ? 'হিমোগ্লোবিন' : 'Haemoglobin';
  static String get tempChartLabel => AppLocale.isBangla ? 'তাপমাত্রা' : 'Temperature';
}

abstract final class ContactSheetStrings {
  ContactSheetStrings._();

  static String get noContactAvailable => AppLocale.isBangla
      ? 'এই পরিবারের জন্য কোনো যোগাযোগ নম্বর পাওয়া যায়নি'
      : 'No contact number available for this household';
  static String get whatsAppFailed => AppLocale.isBangla ? 'হোয়াটসঅ্যাপ খোলা যায়নি' : 'Could not open WhatsApp';
  static String get smsFailed => AppLocale.isBangla ? 'এসএমএস খোলা যায়নি' : 'Could not open SMS';
  static String get householdHead => AppLocale.isBangla ? 'পরিবার প্রধান' : 'Household head';
  static String get familyMember => AppLocale.isBangla ? 'পরিবারের সদস্য' : 'Family member';
  static String get unknownPatient => AppLocale.isBangla ? 'রোগী' : 'Patient';

  /// Shown when contacting a household member on behalf of the patient.
  static String fallbackBanner(
          String patientName, String recipientName, String relationship) =>
      AppLocale.isBangla
          ? '$patientName-এর কোনো নিবন্ধিত নম্বর নেই। তাদের পক্ষে $recipientName ($relationship)-কে যোগাযোগ করা হচ্ছে।'
          : '$patientName has no registered number. Contacting $recipientName ($relationship) on their behalf.';
}

/// Copy for the Referral SLA dashboard, cards, banners, and notifications.
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §11.
abstract final class ReferralStrings {
  ReferralStrings._();

  // ── Create referral sheet ────────────────────────────────────────────────
  static String get createSheetTitle => AppLocale.isBangla ? 'রোগী রেফার করুন' : 'Refer Patient';
  static String get createReasonLabel => AppLocale.isBangla ? 'রেফারের কারণ' : 'Reason for referral';
  static String get createReasonHint => AppLocale.isBangla ? 'একটি কারণ নির্বাচন করুন' : 'Select a reason';
  static String get createTierLabel => AppLocale.isBangla ? 'জরুরি মাত্রা' : 'Urgency level';
  static String get createNotesLabel => AppLocale.isBangla ? 'অতিরিক্ত নোট (ঐচ্ছিক)' : 'Additional notes (optional)';
  static String get createNotesHint => AppLocale.isBangla
      ? 'গ্রহণকারী স্বাস্থ্য কেন্দ্রের জন্য যেকোনো নোট লিখুন'
      : 'Enter any notes for the receiving facility';
  static String get createSubmit => AppLocale.isBangla ? 'রেফারাল জমা দিন' : 'Submit Referral';
  static String get createCancel => AppLocale.isBangla ? 'বাতিল' : 'Cancel';
  static String get createSuccess => AppLocale.isBangla ? 'রেফারাল তৈরি হয়েছে' : 'Referral created';
  static String get createFailed => AppLocale.isBangla
      ? 'রেফারাল তৈরি করতে ব্যর্থ — আবার চেষ্টা করুন'
      : 'Failed to create referral — please try again';
  static String get createReasonRequired => AppLocale.isBangla ? 'একটি কারণ নির্বাচন করুন' : 'Please select a reason';
  static String get tierEmergencyLabel => AppLocale.isBangla ? 'জরুরি (৬ ঘণ্টা এসএলএ)' : 'Emergency (6h SLA)';
  static String get tierUrgentLabel => AppLocale.isBangla ? 'অতিজরুরি (২৪ ঘণ্টা এসএলএ)' : 'Urgent (24h SLA)';
  static String get tierRoutineLabel => AppLocale.isBangla ? 'নিয়মিত (৭২ ঘণ্টা এসএলএ)' : 'Routine (72h SLA)';
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
  static String get dashboardTitle => AppLocale.isBangla ? 'রেফারাল' : 'Referrals';
  static String get emptyTitle => AppLocale.isBangla ? 'কোনো সক্রিয় রেফারাল নেই' : 'No active referrals';
  static String get emptyBody => AppLocale.isBangla
      ? 'রেফারাল তৈরি করার পরে বা সুবিধা থেকে সিঙ্ক করার পরে আপনার এসএলএ ড্যাশবোর্ড পূরণ হবে।'
      : 'Your SLA dashboard populates after you create a referral or sync from the facility.';
  static String get loadFailed => AppLocale.isBangla ? 'রেফারাল লোড করা যায়নি' : 'Could not load referrals';

  // ── Filter chips (priority bands) ────────────────────────────────────────
  static String get filterAll => AppLocale.isBangla ? 'সব' : 'All';
  static String get filterCritical => AppLocale.isBangla ? 'সংকটাপন্ন' : 'Critical';
  static String get filterHigh => AppLocale.isBangla ? 'উচ্চ' : 'High';
  static String get filterMedium => AppLocale.isBangla ? 'মাঝারি' : 'Medium';
  static String get filterLow => AppLocale.isBangla ? 'কম' : 'Low';

  // ── SLA tier labels ──────────────────────────────────────────────────────
  static String get tierEmergency => AppLocale.isBangla ? 'জরুরি' : 'EMERGENCY';
  static String get tierUrgent => AppLocale.isBangla ? 'অতিজরুরি' : 'URGENT';
  static String get tierRoutine => AppLocale.isBangla ? 'নিয়মিত' : 'ROUTINE';

  // ── SLA strip / data-age badge ───────────────────────────────────────────
  static String syncedAgo(String relative) => AppLocale.isBangla ? '$relative আগে সিঙ্ক হয়েছে' : 'Synced $relative';
  static String breachesCount(int n) => AppLocale.isBangla ? '$n এসএলএ লঙ্ঘন' : '$n SLA breach${n == 1 ? "" : "es"}';
  static String escalationsCount(int n) =>
      AppLocale.isBangla ? '$n এস্কালেশন মুলতুবি' : '$n escalation${n == 1 ? "" : "s"} pending';

  // ── Critical banner ──────────────────────────────────────────────────────
  static String criticalBannerFmt(
    String patientName,
    String tier,
    String detail,
  ) => AppLocale.isBangla ? 'লঙ্ঘিত: $patientName · $tier · $detail' : 'BREACHED: $patientName · $tier · $detail';

  // ── Timeline node labels ─────────────────────────────────────────────────
  static String get stepCreated => AppLocale.isBangla ? 'তৈরি হয়েছে' : 'Created';
  static String get stepAcknowledged => AppLocale.isBangla ? 'স্বীকৃত' : 'Acked';
  static String get stepInTransit => AppLocale.isBangla ? 'যাত্রাপথে' : 'Travel';
  static String get stepArrived => AppLocale.isBangla ? 'পৌঁছেছেন' : 'Arrived';
  static String get stepTreatmentStarted => AppLocale.isBangla ? 'চিকিৎসা শুরু' : 'Treated';
  static String get stepClosedRecovered => AppLocale.isBangla ? 'সুস্থ হয়েছেন' : 'Recovered';
  static String get stepClosedDeceased => AppLocale.isBangla ? 'মৃত্যুবরণ' : 'Deceased';
  static String get stepBreached => AppLocale.isBangla ? 'লঙ্ঘিত' : 'BREACH';
  static String get stepPaused => AppLocale.isBangla ? 'বিরতি' : 'Paused';
  static String get stepRefused => AppLocale.isBangla ? 'প্রত্যাখ্যাত' : 'Refused';
  static String get stepTargetUnreachable => AppLocale.isBangla ? 'লক্ষ্যে পৌঁছানো যাচ্ছে না' : 'Target unreachable';
  static String get stepDuplicate => AppLocale.isBangla ? 'নকল' : 'Duplicate';
  static String get stepTransportDeclined => AppLocale.isBangla ? 'পরিবহন প্রত্যাখ্যাত' : 'Transport declined';
  static String get stepDiverted => AppLocale.isBangla ? 'পথ পরিবর্তিত' : 'Diverted';

  // ── Driver labels (extends RiskRationale._formatDriver vocabulary) ──────
  static String formatDriver(String driver) {
    final parts = driver.split(':');
    final key = parts[0];
    final value = parts.length > 1 ? parts[1] : null;
    switch (key) {
      case 'sla-breached':
        return 'SLA breached';
      case 'emergency-dx':
        return 'Emergency diagnosis';
      case 'no-arrival':
        return 'No arrival recorded';
      case 'delay-48h':
        return 'Delay over 48 h';
      case 'missed-follow-up':
        return value != null
            ? '$value missed follow-up(s)'
            : 'Missed follow-up';
      case 'escalation-pending':
        return 'Escalation pending';
      case 'under-5':
        return value != null ? 'Under-5 child (age $value)' : 'Under-5 child';
      case 'pregnancy':
        return 'Pregnancy / ANC enrolled';
      default:
        return driver;
    }
  }

  // ── Card labels ──────────────────────────────────────────────────────────
  static String get tapToSeeWhy => AppLocale.isBangla ? 'কারণ দেখতে ট্যাপ করুন' : 'Tap to see why';
  static String get rationaleSheetTitle => AppLocale.isBangla ? 'এই রেফারালটি কেন অগ্রাধিকারপ্রাপ্ত?' : 'Why is this referral prioritized?';
  static String get modelVersionLabel => AppLocale.isBangla ? 'মডেল সংস্করণ' : 'Model version';
  static String agedFmt(String relative) => AppLocale.isBangla ? '$relative আগে রেফার করা হয়েছে' : 'referred $relative ago';
  static String overdueFmt(String relative) => AppLocale.isBangla ? '$relative মেয়াদোত্তীর্ণ' : 'overdue by $relative';

  // ── Dashboard chip on home screen ────────────────────────────────────────
  static String dashboardChipCritical(int n) => AppLocale.isBangla ? '$n সংকটাপন্ন রেফারাল' : '$n critical referrals';
  static String dashboardChipActive(int n) => AppLocale.isBangla ? '$n সক্রিয় রেফারাল' : '$n active referrals';

  // ── Notification copy (Bangla-ready: titles only here) ───────────────────
  static String get notifCriticalTitle => AppLocale.isBangla ? '🔴 এসএলএ লঙ্ঘিত' : '🔴 SLA BREACHED';
  static String get notifWarningTitle => AppLocale.isBangla ? '🟠 রেফারাল সতর্কতা' : '🟠 Referral warning';
  static String get notifCompletionTitle => AppLocale.isBangla ? '🟢 চিকিৎসা সম্পন্ন' : '🟢 Treatment completed';
  static String notifCriticalBody(String patient, String reason) =>
      '$patient — $reason';
  static String notifWarningBody(String patient, String reason) =>
      '$patient — $reason';
  static String notifCompletionBody(String patient) =>
      AppLocale.isBangla ? '$patient সফলভাবে ছাড়পত্র পেয়েছেন।' : '$patient discharged successfully.';

  // ── Permission rationale (in-app card before OS prompt) ─────────────────
  static String get permissionRationaleTitle => AppLocale.isBangla ? 'রেফারাল সতর্কতা সক্রিয় করুন' : 'Enable referral alerts';
  static String get permissionRationaleBody => AppLocale.isBangla
      ? 'যখন কোনো রেফারাল বিলম্বিত হয় বা এসএলএ লঙ্ঘিত হয় তখন বিজ্ঞপ্তি পান — অ্যাপ বন্ধ থাকলেও।'
      : 'Get notified when a referral is delayed or breaches its SLA — even when the app is closed.';
  static String get permissionRationaleAction => AppLocale.isBangla ? 'সক্রিয় করুন' : 'Enable';
  static String get permissionRationaleDismiss => AppLocale.isBangla ? 'এখন নয়' : 'Not now';

  // ── Triage Card — Priority Badges ────────────────────────────────────────
  static String get badgeCritical => AppLocale.isBangla ? '🔴 সংকটাপন্ন' : '🔴 CRITICAL';
  static String get badgeHigh => AppLocale.isBangla ? '🟠 উচ্চ' : '🟠 HIGH';
  static String get badgeMedium => AppLocale.isBangla ? '🟡 মাঝারি' : '🟡 MEDIUM';
  static String get badgeLow => AppLocale.isBangla ? '🟢 কম' : '🟢 LOW';
  static String get badgeCompleted => AppLocale.isBangla ? '🟢 সম্পন্ন' : '🟢 COMPLETED';

  // ── Triage Card — SLA Status Layer ───────────────────────────────────────
  static String slaBreached(String overdue) => AppLocale.isBangla ? 'এসএলএ লঙ্ঘিত +$overdue' : 'SLA BREACHED +$overdue';
  static String slaWarning(String remaining) => AppLocale.isBangla ? 'এসএলএ: $remaining বাকি' : 'SLA: $remaining left';
  static String get slaCompleted => AppLocale.isBangla ? 'সম্পন্ন ✓' : 'Completed ✓';
  static String get slaOnTrack => AppLocale.isBangla ? 'সঠিক পথে' : 'On Track';

  // ── Triage Card — Referral Metadata ──────────────────────────────────────
  static String get metaReferred => AppLocale.isBangla ? 'রেফার করা হয়েছে:' : 'Referred:';
  static String get metaCondition => AppLocale.isBangla ? 'অবস্থা:' : 'Condition:';
  static String get metaFacility => AppLocale.isBangla ? 'স্বাস্থ্য কেন্দ্র:' : 'Facility:';
  static String get metaProgramme => AppLocale.isBangla ? 'প্রোগ্রাম:' : 'Programme:';
  static String get metaAssigned => AppLocale.isBangla ? 'নির্ধারিত:' : 'Assigned:';
  static String get metaReferralId => AppLocale.isBangla ? 'রেফ আইডি:' : 'Ref ID:';

  // ── Triage Card — Operational Status ─────────────────────────────────────
  static String get statusLabel => AppLocale.isBangla ? 'অবস্থা:' : 'Status:';
  static String get statusNotArrived => AppLocale.isBangla ? 'স্বাস্থ্য কেন্দ্রে পৌঁছাননি' : 'Not arrived at facility';
  static String get statusCheckedIn => AppLocale.isBangla ? 'চেক ইন করেছেন' : 'Checked in';
  static String get statusAwaitingReview => AppLocale.isBangla ? 'পর্যালোচনার অপেক্ষায়' : 'Awaiting review';
  static String get statusDischarged => AppLocale.isBangla ? 'ছাড়পত্র দেওয়া হয়েছে' : 'Discharged';
  static String get statusInTreatment => AppLocale.isBangla ? 'চিকিৎসাধীন' : 'In treatment';
  static String overdueStatus(String days) => AppLocale.isBangla ? '$days মেয়াদোত্তীর্ণ' : '$days overdue';
  static String slaWasStatus(String days) => AppLocale.isBangla ? 'এসএলএ ছিল $days' : 'SLA was $days';
  static String waitingStatus(String duration) => AppLocale.isBangla ? '$duration অপেক্ষায়' : '$duration waiting';
  static String followUpDue(String date) => AppLocale.isBangla ? 'ফলো-আপ বাকি $date' : 'Follow-up due $date';
  static String get prescriptionShared => AppLocale.isBangla ? 'প্রেসক্রিপশন শেয়ার করা হয়েছে' : 'Prescription shared';

  // ── Triage Card — Operational Status Hints ───────────────────────────────
  static String get hintNotCheckedIn => AppLocale.isBangla ? '📍 চেক ইন হয়নি' : '📍 Not checked in';
  static String get hintTransportBarrier => AppLocale.isBangla ? '🚌 পরিবহনে বাধা সম্ভব' : '🚌 Possible transport barrier';
  static String get hintAtFacility => AppLocale.isBangla ? '🏥 স্বাস্থ্য কেন্দ্রে আছেন' : '🏥 At facility';
  static String hintQueueWait(String department, String duration) =>
      AppLocale.isBangla ? '⏳ $department সারি $duration' : '⏳ $department queue $duration';
  static String get hintCareCompleted => AppLocale.isBangla ? '✅ সেবা সম্পন্ন' : '✅ Care completed';
  static String hintFollowUp(String duration) => AppLocale.isBangla ? '📋 $duration-এ ফলো-আপ' : '📋 Follow-up in $duration';

  // ── Triage Card — Timeline Progress ──────────────────────────────────────
  static String get timelineSKVisit => AppLocale.isBangla ? 'এসকে ভিজিট' : 'SK Visit';
  static String get timelineReferred => AppLocale.isBangla ? 'রেফার করা হয়েছে' : 'Referred';
  static String get timelineArrived => AppLocale.isBangla ? 'পৌঁছেছেন' : 'Arrived';
  static String get timelineOBReview => AppLocale.isBangla ? 'ওবি পর্যালোচনা' : 'OB Review';
  static String get timelineTreated => AppLocale.isBangla ? 'চিকিৎসা হয়েছে' : 'Treated';
  static String get timelineDischarged => AppLocale.isBangla ? 'ছাড়পত্র' : 'Discharged';
  static String get timelineWaiting => AppLocale.isBangla ? 'অপেক্ষায়' : 'Waiting';

  // ── Triage Card — Action Layer ───────────────────────────────────────────
  static String get actionCallFamily => AppLocale.isBangla ? 'পরিবারকে কল করুন' : 'Call Family';
  static String get actionUpdateStatus => AppLocale.isBangla ? 'অবস্থা আপডেট করুন' : 'Update Status';
  static String get actionLocate => AppLocale.isBangla ? 'অবস্থান খুঁজুন' : 'Locate';
  static String get actionEscalate => AppLocale.isBangla ? 'এস্কালেট করুন' : 'Escalate';
  static String get actionCallFacility => AppLocale.isBangla ? 'স্বাস্থ্য কেন্দ্রে কল করুন' : 'Call Facility';
  static String get actionUpdateQueue => AppLocale.isBangla ? 'সারি আপডেট করুন' : 'Update Queue';
  static String get actionOpenReferral => AppLocale.isBangla ? 'রেফারাল খুলুন' : 'Open Referral';
  static String get actionViewPrescription => AppLocale.isBangla ? 'প্রেসক্রিপশন দেখুন' : 'View Prescription';
  static String get actionScheduleFollowUp => AppLocale.isBangla ? 'ফলো-আপ নির্ধারণ করুন' : 'Schedule Follow-up';
  static String get actionSendReminder => AppLocale.isBangla ? 'রিমাইন্ডার পাঠান' : 'Send Reminder';
  static String get actionCloseCase => AppLocale.isBangla ? 'কেস বন্ধ করুন' : 'Close Case';

  // ── Contact Sheet ────────────────────────────────────────────────────────
  static String contactSheetTitle(String name) => AppLocale.isBangla ? '$name-এর সাথে যোগাযোগ করুন' : 'Contact $name';
  static String get contactCall => AppLocale.isBangla ? 'কল করুন' : 'Call';
  static String get contactCallSubtitle => AppLocale.isBangla ? 'ফোন ডায়ালার খুলুন' : 'Open phone dialer';
  static String get contactWhatsApp => AppLocale.isBangla ? 'হোয়াটসঅ্যাপ' : 'WhatsApp';
  static String get contactWhatsAppSubtitle => AppLocale.isBangla ? 'হোয়াটসঅ্যাপে বার্তা পাঠান' : 'Send message via WhatsApp';
  static String get contactSms => AppLocale.isBangla ? 'এসএমএস' : 'SMS';
  static String get contactSmsSubtitle => AppLocale.isBangla ? 'টেক্সট বার্তা পাঠান' : 'Send text message';

  // ── Contact Messages ─────────────────────────────────────────────────────
  static String msgGreeting(String name) => AppLocale.isBangla ? 'প্রিয় $name, ' : 'Hello $name, ';
  static String get msgIntro => AppLocale.isBangla ? 'এটি UHIS স্বাস্থ্যকর্মী। ' : 'this is UHIS Health Worker. ';
  static String msgReferralFor(String diagnosis) =>
      AppLocale.isBangla ? '$diagnosis-এর জন্য আপনার রেফারাল সম্পর্কে, ' : 'Regarding your referral for $diagnosis, ';
  static String get msgReferralGeneric => AppLocale.isBangla ? 'আপনার স্বাস্থ্য রেফারাল সম্পর্কে, ' : 'Regarding your health referral, ';
  static String get msgOverdue => AppLocale.isBangla
      ? 'আমরা লক্ষ্য করেছি আপনার অ্যাপয়েন্টমেন্টের সময় পেরিয়ে গেছে। অনুগ্রহ করে আমাদের সাথে যোগাযোগ করুন বা যত শীঘ্র সম্ভব স্বাস্থ্য কেন্দ্রে যান। '
      : 'we noticed your appointment is overdue. Please contact us or visit the health facility as soon as possible. ';
  static String get msgNewReferral => AppLocale.isBangla
      ? 'অনুগ্রহ করে যত দ্রুত সম্ভব রেফার করা স্বাস্থ্য কেন্দ্রে যান। '
      : 'please ensure you visit the referred health facility at your earliest convenience. ';
  static String get msgInTreatment => AppLocale.isBangla
      ? 'আমরা আপনার চিকিৎসার অগ্রগতি সম্পর্কে খোঁজ নিচ্ছি। কোনো সহায়তার প্রয়োজন হলে আমাদের জানান। '
      : 'we are following up on your treatment progress. Please let us know if you need any assistance. ';
  static String get msgCompleted => AppLocale.isBangla
      ? 'আমরা আশা করি আপনি সুস্থ হয়ে উঠছেন। অনুগ্রহ করে নির্ধারিত সময়ে ফলো-আপ অ্যাপয়েন্টমেন্টে আসুন। '
      : 'we hope you are recovering well. Please attend your follow-up appointment as scheduled. ';
  static String get msgGenericOutreach => AppLocale.isBangla
      ? 'আমরা আপনার স্বাস্থ্যসেবা সম্পর্কে যোগাযোগ করছি। '
      : 'we are reaching out regarding your health care. ';
  static String get msgClosing => AppLocale.isBangla
      ? 'যেকোনো প্রশ্নের জন্য এই বার্তার উত্তর দিন বা আমাদের কল করুন। ধন্যবাদ।'
      : 'Reply to this message or call us for any queries. Thank you.';

  // ── Error Messages ───────────────────────────────────────────────────────
  static String get errorNoPhone => AppLocale.isBangla ? 'কোনো ফোন নম্বর পাওয়া যায়নি' : 'No phone number available';
  static String get errorPhoneDialer => AppLocale.isBangla ? 'ফোন ডায়ালার খোলা যায়নি' : 'Could not open phone dialer';
  static String get errorWhatsApp => AppLocale.isBangla
      ? 'হোয়াটসঅ্যাপ খোলা যায়নি। এটি কি ইনস্টল করা আছে?'
      : 'Could not open WhatsApp. Is it installed?';
  static String get errorSms => AppLocale.isBangla ? 'এসএমএস অ্যাপ খোলা যায়নি' : 'Could not open SMS app';
  static String get errorMaps => AppLocale.isBangla ? 'গুগল ম্যাপস খোলা যায়নি' : 'Could not open Google Maps';
  static String errorOpening(String type, String error) =>
      AppLocale.isBangla ? '$type খুলতে ত্রুটি: $error' : 'Error opening $type: $error';

  // ── Location Sheet ───────────────────────────────────────────────────────
  static String locateSheetTitle(String name) => AppLocale.isBangla ? '$name-কে খুঁজুন' : 'Locate $name';
  static String get locateOpenMaps => AppLocale.isBangla ? 'গুগল ম্যাপসে খুলুন' : 'Open in Google Maps';
  static String get locateOpenMapsSubtitle => AppLocale.isBangla ? 'মানচিত্রে অবস্থান দেখুন' : 'View location on map';
  static String get locateGetDirections => AppLocale.isBangla ? 'দিকনির্দেশনা নিন' : 'Get Directions';
  static String get locateGetDirectionsSubtitle => AppLocale.isBangla ? 'রোগীর কাছে নেভিগেট করুন' : 'Navigate to patient';

  // ── Record outcome sheet ─────────────────────────────────────────────────
  static String get recordOutcomeTitle => AppLocale.isBangla ? 'ফলাফল রেকর্ড করুন' : 'Record outcome';
  static String get recordOutcomeSubtitle => AppLocale.isBangla
      ? 'এই রেফারালের বর্তমান অবস্থা আপডেট করুন'
      : 'Update the current status of this referral';
  static String get outcomeReferred => AppLocale.isBangla ? 'এখনো রেফার করা' : 'Still referred';
  static String get outcomeReferredSubtitle => AppLocale.isBangla ? 'রোগী এখনো স্বাস্থ্য কেন্দ্রে পৌঁছাননি' : 'Patient not yet arrived at facility';
  static String get outcomeOnTreatment => AppLocale.isBangla ? 'চিকিৎসাধীন' : 'On treatment';
  static String get outcomeOnTreatmentSubtitle => AppLocale.isBangla ? 'রোগী পৌঁছেছেন এবং চিকিৎসা শুরু হয়েছে' : 'Patient arrived and treatment started';
  static String get outcomeRecovered => AppLocale.isBangla ? 'সুস্থ হয়েছেন' : 'Recovered';
  static String get outcomeRecoveredSubtitle => AppLocale.isBangla ? 'চিকিৎসা সম্পন্ন, রোগীকে ছাড়পত্র দেওয়া হয়েছে' : 'Treatment complete, patient discharged';
  static String get outcomeDeceased => AppLocale.isBangla ? 'মৃত্যুবরণ করেছেন' : 'Deceased';
  static String get outcomeDeceasedSubtitle => AppLocale.isBangla ? 'রোগী মারা গেছেন' : 'Patient passed away';
  static String get outcomeUpdated => AppLocale.isBangla ? 'অবস্থা আপডেট হয়েছে' : 'Status updated';
  static String get outcomeUpdateFailed => AppLocale.isBangla
      ? 'অবস্থা আপডেট করা যায়নি — আবার চেষ্টা করুন'
      : 'Could not update status — please try again';
}

/// AI Mission Dashboard strings (Screen 2 redesign).
/// Spec: AI Mission Dashboard — action page answering "Who needs me next?"
abstract final class MissionDashboardStrings {
  MissionDashboardStrings._();

  // ── HTML Dashboard composition ───────────────────────────────────────────
  static String aiSortedVisits(int n) => AppLocale.isBangla
      ? 'এআই রাতারাতি আপনার $n টি ভিজিট সাজিয়েছে'
      : 'sorted your $n visits overnight';
  static String get visitsToday =>
      AppLocale.isBangla ? 'আজকের ভিজিট' : 'Visits today';

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

  static String get referralAlertsLabel => AppLocale.isBangla
      ? 'রেফারেল সতর্কতাগুলোর ফলো-আপ প্রয়োজন'
      : 'Referral alerts need follow-up';
  static String get tapToFollowUp =>
      AppLocale.isBangla ? 'ফলো-আপ করতে ট্যাপ করুন →' : 'Tap to follow up →';
  static String get referralCceComingSoon => AppLocale.isBangla
      ? 'CCE ইন্টিগ্রেশন শীঘ্রই আসছে'
      : 'CCE integration coming soon';
  static String get visitStartFailed => AppLocale.isBangla
      ? 'ভিজিট শুরু করা যায়নি। রোগীর স্ক্রিন থেকে আবার চেষ্টা করুন।'
      : 'Could not start visit. Try again from the patient screen.';
  static String get visitMissingPatient => AppLocale.isBangla
      ? 'কোনো রোগীর রেকর্ড নেই — শুরু করতে কেস খুলুন।'
      : 'No patient record — open the case to begin.';
  static String houseNumber(String no) =>
      AppLocale.isBangla ? 'বাড়ি #$no' : 'House #$no';
  static String moreVisits(int n) {
    if (AppLocale.isBangla) {
      return n == 1 ? '+ আরও 1টি ভিজিট আজ' : '+ আরও $n টি ভিজিট আজ';
    }
    return n == 1 ? '+ 1 more visit today' : '+ $n more visits today';
  }
  static String todaysVisits(String date) => AppLocale.isBangla
      ? 'আজকের ভিজিট · $date'
      : "Today's visits · $date";
  static String get filterByLocation =>
      AppLocale.isBangla ? 'গ্রাম · এসএস · এলাকা' : 'Village · SS · Area';
  static String get upcomingWorkHeader => AppLocale.isBangla
      ? 'আসন্ন কাজ — প্রথমে সবচেয়ে জরুরি'
      : 'Upcoming work — earliest first';
  static String get aiSortedBadge =>
      AppLocale.isBangla ? '✦ সাজানো' : '✦ sorted';

  /// Badge copy for the dashboard header — always the unfiltered today count.
  static String aiSortedVisitsToday(int n) {
    if (AppLocale.isBangla) {
      return n == 1 ? '✦ সাজানো 1 টি ভিজিট আজ' : '✦ সাজানো $n টি ভিজিট আজ';
    }
    return n == 1
        ? '✦ sorted 1 visit today'
        : '✦ sorted $n visits today';
  }
  static String get actionVisitNow =>
      AppLocale.isBangla ? 'এখনই ভিজিট করুন' : 'Visit now';
  static String get actionVisitToday =>
      AppLocale.isBangla ? 'আজ ভিজিট করুন' : 'Visit today';
  static String get actionThisWeek =>
      AppLocale.isBangla ? 'এই সপ্তাহে' : 'This week';
  static String get actionRoutine =>
      AppLocale.isBangla ? 'নিয়মিত' : 'Routine';

  // ── AI Daily Brief Card ──────────────────────────────────────────────────
  static String get aiBriefTitle =>
      AppLocale.isBangla ? 'আজকের এআই সংক্ষিপ্ত বিবরণ' : "Today's AI Brief";
  static String get visitsRecommended =>
      AppLocale.isBangla ? 'প্রস্তাবিত ভিজিট' : 'Visits Recommended';
  static String get childDangerCases =>
      AppLocale.isBangla ? 'শিশুদের বিপদ চিহ্নিত কেস' : 'Child Danger Cases';
  static String get slaBreachedReferrals => AppLocale.isBangla
      ? 'SLA লঙ্ঘিত রেফারেল'
      : 'SLA Breached Referrals';
  static String get ancFollowUps =>
      AppLocale.isBangla ? 'ANC ফলো-আপ' : 'ANC Follow-ups';
  static String get highRiskDiabeticPatients => AppLocale.isBangla
      ? 'উচ্চ-ঝুঁকিপূর্ণ ডায়াবেটিক রোগী'
      : 'High-Risk Diabetic Patients';
  static String get expectedWorkload =>
      AppLocale.isBangla ? 'প্রত্যাশিত কর্মভার' : 'Expected Workload';
  static String get priorityLevel =>
      AppLocale.isBangla ? 'অগ্রাধিকার স্তর' : 'Priority Level';
  static String get whyQuestion => AppLocale.isBangla ? 'কেন?' : 'Why?';
  static String get riskFactorsIdentified => AppLocale.isBangla
      ? 'শনাক্তকৃত ঝুঁকির কারণ'
      : 'Risk Factors Identified';
  static String workloadHours(double hours) => AppLocale.isBangla
      ? '${hours.toStringAsFixed(1)} ঘণ্টা'
      : '${hours.toStringAsFixed(1)} Hours';

  // ── Mission Progress Card ────────────────────────────────────────────────
  static String get todaysProgress =>
      AppLocale.isBangla ? 'আজকের অগ্রগতি' : "Today's Progress";
  static String get visitsCompleted =>
      AppLocale.isBangla ? 'সম্পন্ন ভিজিট' : 'Visits Completed';
  static String get visitsRemaining =>
      AppLocale.isBangla ? 'বাকি ভিজিট' : 'Visits Remaining';
  static String get estimatedTime =>
      AppLocale.isBangla ? 'আনুমানিক সময়' : 'Estimated Time';
  static String progressFraction(int done, int total) => '$done / $total';
  static String progressPercent(int percent) => '$percent%';
  static String remainingVisits(int n) =>
      AppLocale.isBangla ? '$n টি ভিজিট বাকি' : '$n Visits Remaining';
  static String estimatedDuration(String duration) => AppLocale.isBangla
      ? 'আনুমানিক সময়: $duration'
      : 'Estimated Time: $duration';
  static String completionPrediction(String time) => AppLocale.isBangla
      ? 'বর্তমান গতিতে, $time এর মধ্যে সব ভিজিট সম্পন্ন করা সম্ভব'
      : 'At current pace, all visits can be completed by $time';

  // ── Critical Alert Banner ────────────────────────────────────────────────
  static String get criticalAlert =>
      AppLocale.isBangla ? '🔴 জরুরি সতর্কতা' : '🔴 Critical Alert';
  static String get emergencyAncAlert =>
      AppLocale.isBangla ? '🔴 জরুরি ANC সতর্কতা' : '🔴 Emergency ANC Alert';
  static String get immediateFollowUpRequired => AppLocale.isBangla
      ? 'তাৎক্ষণিক ফলো-আপ প্রয়োজন।'
      : 'Immediate follow-up required.';
  static String childReferralOverdue(int days) => AppLocale.isBangla
      ? '$days শিশু রেফারেল বকেয়া'
      : '$days Child Referral${days == 1 ? '' : 's'} Overdue';
  static String highRiskPregnancyWaiting(String name, String duration) =>
      AppLocale.isBangla
          ? '$name: উচ্চ-ঝুঁকিপূর্ণ গর্ভাবস্থা $duration ধরে OB পর্যালোচনার অপেক্ষায়।'
          : '$name: High-risk pregnancy waiting $duration for OB review.';

  // ── Mission Queue Card ───────────────────────────────────────────────────
  static String priorityRank(int rank) =>
      AppLocale.isBangla ? 'অগ্রাধিকার #$rank' : 'Priority #$rank';
  static String daysOverdue(int days) =>
      AppLocale.isBangla ? '$days দিন বকেয়া' : '$days Days Overdue';
  static String get aiInsight =>
      AppLocale.isBangla ? 'এআই ইনসাইট' : 'AI Insight';

  // ── Programme-smart reason badge (v13 design) ───────────────────────────
  static String get enrolled => AppLocale.isBangla ? 'নথিভুক্ত' : 'Enrolled';
  static String get ancVisitLabel =>
      AppLocale.isBangla ? 'ANC ভিজিট' : 'ANC Visit';
  static String get pncVisitLabel =>
      AppLocale.isBangla ? 'PNC ভিজিট' : 'PNC Visit';
  static String get childImmunisation =>
      AppLocale.isBangla ? 'শিশু টিকাদান' : 'Child immunisation';
  static String get ncdCheckup =>
      AppLocale.isBangla ? 'NCD চেকআপ' : 'NCD checkup';
  static String get tbCheck => AppLocale.isBangla ? 'TB পরীক্ষা' : 'TB check';
  static String get newVisit =>
      AppLocale.isBangla ? 'নতুন ভিজিট' : 'New visit';
  static String get aiPrioritisedBecause => AppLocale.isBangla
      ? 'এআই অগ্রাধিকার দিয়েছে কারণ:'
      : 'AI Prioritised because:';
  static String get reason => AppLocale.isBangla ? 'কারণ' : 'Reason';

  // ── AI Insight Reasons (human-readable) ──────────────────────────────────
  static String get insightPatientNeverArrived => AppLocale.isBangla
      ? 'রোগী কখনও সুবিধায় পৌঁছাননি।'
      : 'Patient never arrived at facility.';
  static String get insightPossibleTransportBarrier => AppLocale.isBangla
      ? 'সম্ভাব্য যাতায়াত সমস্যা।'
      : 'Possible transport barrier.';
  static String get insightReferralOverdue =>
      AppLocale.isBangla ? 'রেফারেল বকেয়া।' : 'Referral overdue.';
  static String get insightChildUnder5 => AppLocale.isBangla
      ? '5 বছরের কম বয়সী শিশু।'
      : 'Child under 5.';
  static String get insightHighRiskPregnancy => AppLocale.isBangla
      ? 'উচ্চ-ঝুঁকিপূর্ণ গর্ভাবস্থা।'
      : 'High-risk pregnancy.';
  static String get insightNoFacilityArrival =>
      AppLocale.isBangla ? 'সুবিধায় পৌঁছাননি।' : 'No facility arrival.';
  static String get insightMissedFollowUp =>
      AppLocale.isBangla ? 'ফলো-আপ মিস হয়েছে।' : 'Missed follow-up.';
  static String get insightSlaBreached =>
      AppLocale.isBangla ? 'SLA লঙ্ঘিত হয়েছে।' : 'SLA breached.';
  static String get insightEmergencyDiagnosis =>
      AppLocale.isBangla ? 'জরুরি রোগ নির্ণয়।' : 'Emergency diagnosis.';
  static String get insightDiabetesMissedFollowUp => AppLocale.isBangla
      ? 'ডায়াবেটিস রোগীর ফলো-আপ মিস হয়েছে।'
      : 'Diabetes patient missed follow-up.';

  // ── Action Buttons ───────────────────────────────────────────────────────
  static String get callFamily =>
      AppLocale.isBangla ? 'পরিবারকে কল করুন' : 'Call Family';
  static String get locate => AppLocale.isBangla ? 'অবস্থান' : 'Locate';
  static String get openCase =>
      AppLocale.isBangla ? 'কেস খুলুন' : 'Open Case';
  static String get callFacility =>
      AppLocale.isBangla ? 'সুবিধায় কল করুন' : 'Call Facility';
  static String get openReferral =>
      AppLocale.isBangla ? 'রেফারেল খুলুন' : 'Open Referral';
  static String get scheduleVisit =>
      AppLocale.isBangla ? 'ভিজিট নির্ধারণ করুন' : 'Schedule Visit';
  static String get visitHousehold =>
      AppLocale.isBangla ? 'পরিবার ভিজিট করুন' : 'Visit Household';
  static String get startRoute =>
      AppLocale.isBangla ? 'রুট শুরু করুন' : 'Start Route';
  static String get continueTodaysWork => AppLocale.isBangla
      ? 'আজকের কাজ চালিয়ে যান'
      : "Continue Today's Work";

  // ── Household Enrollment CTA ─────────────────────────────────────────────
  static String get enrollHouseholdTitle => AppLocale.isBangla
      ? 'নতুন পরিবার নথিভুক্ত করুন'
      : 'Enrol a new household';
  static String get enrollHouseholdSubtitle => AppLocale.isBangla
      ? 'প্রোগ্রামে এখনো নেই এমন পরিবার নিবন্ধন করুন'
      : 'Register a family not yet in the programme';
  static String get enrollHouseholdAction =>
      AppLocale.isBangla ? 'এখনই নথিভুক্ত করুন' : 'Enrol now';

  // ── Referral Operations Widget ───────────────────────────────────────────
  static String get referralStatus =>
      AppLocale.isBangla ? 'রেফারেল অবস্থা' : 'Referral Status';
  static String get active => AppLocale.isBangla ? 'সক্রিয়' : 'Active';
  static String get breached => AppLocale.isBangla ? 'লঙ্ঘিত' : 'Breached';
  static String get awaitingReview =>
      AppLocale.isBangla ? 'পর্যালোচনার অপেক্ষায়' : 'Awaiting Review';
  static String get completed => AppLocale.isBangla ? 'সম্পন্ন' : 'Completed';
  static String referralCount(int count, String status) => '$count $status';

  // ── Follow-Ups Due Widget ────────────────────────────────────────────────
  static String get followUpsDue =>
      AppLocale.isBangla ? 'বকেয়া ফলো-আপ' : 'Follow-Ups Due';
  static String get discharged =>
      AppLocale.isBangla ? 'ছাড়প্রাপ্ত' : 'Discharged';
  static String get followUpDue =>
      AppLocale.isBangla ? 'ফলো-আপ বকেয়া' : 'Follow-up Due';
  static String get tomorrow => AppLocale.isBangla ? 'আগামীকাল' : 'Tomorrow';
  static String get today => AppLocale.isBangla ? 'আজ' : 'Today';
  static String daysAway(int days) {
    if (days == 0) return today;
    if (days == 1) return tomorrow;
    return AppLocale.isBangla ? '$days দিনের মধ্যে' : 'In $days days';
  }

  // ── Household Opportunities Widget ───────────────────────────────────────
  static String get householdOpportunities =>
      AppLocale.isBangla ? 'পরিবার সুযোগ' : 'Household Opportunities';
  static String get potentialServices =>
      AppLocale.isBangla ? 'সম্ভাব্য সেবা' : 'Potential Services';
  static String get mother => AppLocale.isBangla ? 'মা' : 'Mother';
  static String get child => AppLocale.isBangla ? 'শিশু' : 'Child';
  static String get father => AppLocale.isBangla ? 'বাবা' : 'Father';
  static String get ancFollowUpDue =>
      AppLocale.isBangla ? 'ANC ফলো-আপ বকেয়া' : 'ANC Follow-up Due';
  static String get epiVaccineDue =>
      AppLocale.isBangla ? 'EPI টিকা বকেয়া' : 'EPI Vaccine Due';
  static String get bpReviewPending =>
      AppLocale.isBangla ? 'BP পর্যালোচনা মুলতুবি' : 'BP Review Pending';
  static String householdNumber(int number) =>
      AppLocale.isBangla ? 'পরিবার #$number' : 'Household #$number';
  static String potentialServicesCount(int count) => AppLocale.isBangla
      ? 'সম্ভাব্য সেবা: $count'
      : 'Potential Services: $count';

  // ── Route Optimization Widget ────────────────────────────────────────────
  static String get optimalRoute =>
      AppLocale.isBangla ? 'সর্বোত্তম রুট' : 'Optimal Route';
  static String get distance => AppLocale.isBangla ? 'দূরত্ব' : 'Distance';
  static String get estimatedTravelTime =>
      AppLocale.isBangla ? 'আনুমানিক সময়' : 'Estimated Time';
  static String distanceKm(double km) => '${km.toStringAsFixed(1)} km';
  static String travelDuration(String duration) => duration;

  // ── Learning Recommendations Widget ──────────────────────────────────────
  static String get todaysLearning =>
      AppLocale.isBangla ? 'আজকের শিক্ষা' : "Today's Learning";
  static String learningDuration(int minutes) =>
      AppLocale.isBangla ? '$minutes মিনিট' : '$minutes Minutes';
  static String get triggeredByTodaysCases => AppLocale.isBangla
      ? 'আজকের কেস দ্বারা উদ্দীপিত'
      : 'Triggered by today\'s cases';

  // ── Floating AI Assistant ────────────────────────────────────────────────
  static String get aiAssistant =>
      AppLocale.isBangla ? 'এআই সহকারী' : 'AI Assistant';
  static String get askAiAssistant => AppLocale.isBangla
      ? 'এআই সহকারীকে জিজ্ঞাসা করুন'
      : 'Ask AI Assistant';
  static String get aiAssistantHint => AppLocale.isBangla
      ? 'রোগীর যত্ন, নির্দেশিকা বা পদ্ধতি সম্পর্কে জিজ্ঞাসা করুন…'
      : 'Ask about patient care, guidelines, or procedures…';

  // ── Priority Levels ──────────────────────────────────────────────────────
  static String get priorityCritical =>
      AppLocale.isBangla ? 'জরুরি' : 'Critical';
  static String get priorityHigh => AppLocale.isBangla ? 'উচ্চ' : 'High';
  static String get priorityMedium => AppLocale.isBangla ? 'মাঝারি' : 'Medium';
  static String get priorityLow => AppLocale.isBangla ? 'নিম্ন' : 'Low';

  // ── Programme Badges ─────────────────────────────────────────────────────
  // Standardized clinical shorthand SKs are trained on — kept in Latin
  // script regardless of UI language (not translated by design).
  static const String badgeAnc = 'ANC';
  static const String badgeImci = 'IMCI';
  static const String badgeNcd = 'NCD';
  static const String badgeTb = 'TB';
  static const String badgeEpi = 'EPI';
  static const String badgeReferral = 'Referral';

  // ── Empty States ─────────────────────────────────────────────────────────
  static String get noMissionsToday =>
      AppLocale.isBangla ? 'আজকের জন্য কোনো মিশন নেই' : 'No missions for today';
  static String get allCaughtUp => AppLocale.isBangla
      ? 'সব সম্পন্ন! দারুণ কাজ।'
      : 'All caught up! Great work.';
  static String get noCriticalAlerts =>
      AppLocale.isBangla ? 'কোনো জরুরি সতর্কতা নেই' : 'No critical alerts';
  static String get noFollowUpsDue =>
      AppLocale.isBangla ? 'কোনো ফলো-আপ বকেয়া নেই' : 'No follow-ups due';
  static String get noHouseholdOpportunities => AppLocale.isBangla
      ? 'কোনো পরিবার সুযোগ শনাক্ত হয়নি'
      : 'No household opportunities identified';

  // ── 5-Tier Dashboard Model ───────────────────────────────────────────────
  // Single source of UI copy for tier headers, CTAs, and driver rationales.
  // Widgets must call these helpers instead of inlining tier labels.

  static String get tierLabelCritical =>
      AppLocale.isBangla ? 'জরুরি' : 'Critical';
  static String get tierLabelOverdue =>
      AppLocale.isBangla ? 'বকেয়া' : 'Overdue';
  static String get tierLabelDueToday =>
      AppLocale.isBangla ? 'আজ বকেয়া' : 'Due today';
  static String get tierLabelThisWeek =>
      AppLocale.isBangla ? 'এই সপ্তাহে' : 'This week';
  static String get tierLabelUpcoming =>
      AppLocale.isBangla ? 'আসন্ন' : 'Upcoming';

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
  static String get ctaVisitNow =>
      AppLocale.isBangla ? 'এখনই ভিজিট করুন' : 'Visit now';
  static String get ctaVisitToday =>
      AppLocale.isBangla ? 'আজ ভিজিট করুন' : 'Visit today';
  static String get ctaPlanVisit =>
      AppLocale.isBangla ? 'ভিজিট পরিকল্পনা করুন' : 'Plan visit';
  static String get ctaSchedule =>
      AppLocale.isBangla ? 'নির্ধারণ করুন' : 'Schedule';

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
  static String get whichVillageVisiting => AppLocale.isBangla
      ? 'আপনি কোন গ্রাম পরিদর্শন করছেন?'
      : 'WHICH VILLAGE ARE YOU VISITING?';
  static String get allVillages =>
      AppLocale.isBangla ? 'সব গ্রাম' : 'All villages';
  static String get filterByNeed =>
      AppLocale.isBangla ? 'প্রয়োজন অনুযায়ী ফিল্টার' : 'FILTER BY NEED';
  static String get filterByNeedOptional =>
      AppLocale.isBangla ? 'ঐচ্ছিক' : 'optional';
  static String get needHighRisk =>
      AppLocale.isBangla ? 'উচ্চ-ঝুঁকি' : 'High-risk';
  static const String needAncMnch = 'ANC / MNCH';
  static String get needChildImmunisation =>
      AppLocale.isBangla ? 'শিশু / টিকা' : 'Child / Immun.';
  static const String needNcd = 'NCD';
  static String get needEyeCare =>
      AppLocale.isBangla ? 'চোখের যত্ন' : 'Eye care';
  static String get needMissedFollowUp =>
      AppLocale.isBangla ? 'মিস হয়েছে' : 'Missed';
  static String get needPendingReferral =>
      AppLocale.isBangla ? 'রেফারেল' : 'Referral';
  static String get needHomeVisit =>
      AppLocale.isBangla ? 'বাড়ি পরিদর্শন' : 'Home visit';
  static String get needFacilityReferral =>
      AppLocale.isBangla ? 'সুবিধা' : 'Facility';
  static String get needThisWeek =>
      AppLocale.isBangla ? 'এই সপ্তাহ' : 'This week';
  static String get clearNeedFilters =>
      AppLocale.isBangla ? 'সাফ করুন' : 'Clear';
  static String get filterByProgramme =>
      AppLocale.isBangla ? 'প্রোগ্রাম' : 'Programme';
  static String get noNeedsInQueue => AppLocale.isBangla
      ? 'আজকের তালিকায় কোনো অগ্রাধিকার প্রয়োজন নেই'
      : 'No priority needs in today\'s list';
  static String get noVisitsMatchFilters => AppLocale.isBangla
      ? 'এই ফিল্টারগুলোর সাথে কোনো ভিজিট মেলে না'
      : 'No visits match these filters';
  static String get noVisitsMatchFiltersHint => AppLocale.isBangla
      ? 'অন্য গ্রাম চেষ্টা করুন অথবা ফিল্টার সাফ করুন'
      : 'Try another village or clear the filters';
  static String completedVisitToast(String name) => AppLocale.isBangla
      ? '$name-এর ভিজিট আজ ইতিমধ্যে সম্পন্ন হয়েছে ✓'
      : "$name's visit already done today ✓";

  // ── AI sorted info card tags ──────────────────────────────────────────────
  static String get aiSortedTagRisk =>
      AppLocale.isBangla ? '✦ঝুঁকি স্কোরিং' : '✦Risk scoring';
  static String get aiSortedTagOverdue =>
      AppLocale.isBangla ? '✦বকেয়া ফ্ল্যাগ' : '✦Overdue flags';
  static String get aiSortedTagCce =>
      AppLocale.isBangla ? '✦CCE সতর্কতা' : '✦CCE alerts';

  // ── "+ Enrol new" FAB ────────────────────────────────────────────────────
  static String get enrolNewCta =>
      AppLocale.isBangla ? 'নতুন নথিভুক্ত করুন' : 'Enroll new';
  static String get enrolNewComingSoon => AppLocale.isBangla
      ? 'QR নথিভুক্তি প্রক্রিয়া শীঘ্রই আসছে। বিদ্যমান রোগী দেখতে Patients ট্যাব ব্যবহার করুন।'
      : 'QR enrolment flow coming soon. Use the Patients tab to view existing patients.';

  // ── Status pills (compact tier label shown in the card right-side pill) ───
  static String get statusPillNow => AppLocale.isBangla ? 'এখন' : 'Now';
  static String get statusPillOverdue =>
      AppLocale.isBangla ? 'বকেয়া' : 'Overdue';
  static String get statusPillToday => AppLocale.isBangla ? 'আজ' : 'Today';
  static String get statusPillThisWeek =>
      AppLocale.isBangla ? 'এই সপ্তাহে' : 'This week';
  static String get statusPillRoutine =>
      AppLocale.isBangla ? 'নিয়মিত' : 'Routine';

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
  static String get notificationsTitle =>
      AppLocale.isBangla ? 'বিজ্ঞপ্তি' : 'Notifications';
  static String get close => AppLocale.isBangla ? 'বন্ধ করুন' : 'Close';
  static String get noNewNotifications =>
      AppLocale.isBangla ? 'কোনো নতুন বিজ্ঞপ্তি নেই' : 'No new notifications';
  static String get cceEscalations =>
      AppLocale.isBangla ? 'CCE এসকেলেশন' : 'CCE escalations';
  static String criticalReferralsSubtitle(int count) => AppLocale.isBangla
      ? '$count টি জরুরি রেফারেলের তাৎক্ষণিক মনোযোগ প্রয়োজন'
      : '$count critical referral${count == 1 ? '' : 's'} need immediate attention';
  static String pendingReferralsSubtitle(int count) => AppLocale.isBangla
      ? '$count টি অমীমাংসিত রেফারেল ফলো-আপের অপেক্ষায়'
      : '$count pending referral${count == 1 ? '' : 's'} awaiting follow-up';
  static String get viewAll => AppLocale.isBangla ? 'সব দেখুন' : 'View all';
}

/// Visit triage step (HTML composition) — bilingual symptom prompts.
abstract final class VisitTriageStrings {
  VisitTriageStrings._();

  static const String triage = 'Triage';
  static const String patient = 'patient';
  static const String sessionMissing =
      'Visit not found. Please start a new visit.';
  static const String leaveVisitTitle = 'Leave visit?';
  static const String leaveVisitBody =
      'Your progress will be saved. You can resume later.';
  static const String stay = 'Stay';
  static const String leave = 'Leave';

  static String stepOneOfThree(String programme) =>
      'STEP 1 OF 3 · AI TRIAGE · $programme';
  static const String stepLabel1 = 'How are you feeling?';
  static const String stepLabel2 = 'AI triage';
  static const String stepLabel3 = 'Detailed check';

  static const String beforeYouKnock = 'Before you knock · AI brief';
  static String briefBody(String name) =>
      '⚠ $name · current concerns flagged — act today if symptoms persist';

  static const String skAsksFamily = 'SK ASKS THE FAMILY ';
  static const String skAsksBangla = 'রোগী কেমন আছে? কতদিন হলো অসুস্থ?';
  static const String skAsksEnglish =
      'How is the patient? How many days unwell?';

  static String get durationQuestion =>
      AppLocale.isBangla ? 'কতদিন হলো? · কতদিন অসুস্থ?' : 'How many days? · How many days sick?';
  static const String aiCheckingCta = 'AI is checking — see what to do next';
}

/// AI Scribe strings — voice recording → SOAP note flow.
abstract final class ScribeStrings {
  ScribeStrings._();

  static const String fabIdle = 'Record consultation';
  static const String fabStop = 'Stop recording';
  static const String fabReview = 'Review AI note';
  static const String fabRetry = 'Retry upload';

  static const String pillRecording = 'Recording…';
  static const String pillUploading = 'Uploading…';
  static const String pillProcessing = 'AI processing note…';
  static const String pillReady = 'AI note ready — tap ✦ to review';

  static const String rationaleTitle = 'AI Scribe';
  static const String rationaleSubtitle = 'Voice → clinical note';
  static const String rationaleAllow = 'Allow';
  static const String rationaleNotNow = 'Not now';

  static const String reviewAccept = 'Accept Note';
  static const String reviewReject = 'Reject';
  static const String reviewRequired = 'Review required';
  static const String reviewWarning =
      'Please review all sections before accepting.';

  static const String acceptedSnackbar = 'Note accepted ✓';
  static const String rejectedSnackbar = 'Note discarded';

  static const String settingsTitle = 'Microphone access needed';
  static const String settingsBody =
      'AI Scribe needs microphone access to record consultations. '
      'Enable it in Settings → App permissions.';
  static const String settingsOpen = 'Open Settings';
  static const String settingsCancel = 'Cancel';

  static String uploadProgress(double pct) =>
      'Uploading…  ${pct.toStringAsFixed(0)}%';
  static String recordingTimer(int secs) {
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return 'Recording…  $mm:$ss';
  }

  // ── S4 triage pre-tick hook (S4.6) ───────────────────────────────────────
  static const String triageConsentPrompt =
      'Record conversation to auto-select symptoms?';
  static const String triageConsentAllow = 'Allow';
  static const String triageConsentDeny = 'Not now';

  static const String transcriptionFailed = 'Transcription failed.';
  static const String pollTimeout = 'AI is taking too long. Tap to try again.';
  static const String pollUnreachable =
      'Could not reach AI Scribe. Tap to try again.';
  static const String recordingNotFinalized =
      'Recording could not be saved. Please record again.';
  static const String recordingNoOutput =
      'Recording produced no output. Please record again.';
  static const String noSpeechDetected =
      'No speech detected — please speak closer to the microphone and try again.';
  static const String recordingStartFailed =
      'Could not start recording. Check microphone permissions and try again.';
}

/// AI Scribe inline banner strings (replaces FAB labels for the new single-form layout).
abstract final class ScribeBannerStrings {
  ScribeBannerStrings._();

  static const String idle = '🎙 AI Scribe — tap and let him/her speak';
  static const String idleSub = 'Tap a mode to start';
  static const String recording = 'Recording…';
  static const String uploading = 'Uploading…';
  static const String processing = 'AI processing note…';
  static const String ready = 'AI note ready — tap to review';
  static const String error = 'Upload failed — tap to retry';

  /// Mode-chooser buttons shown only at idle (see [ScribeBanner]).
  static const String modeAsr = 'ASR';
  static const String modeOther = 'Other';

  /// Badge shown once the "Other" (standard/batch) mode is active, so it's
  /// always clear which engine — this or Real-Time ASR — is running.
  static const String modeOtherBadge = 'OTHER';

  static const String modeGemini = 'Gemini';
  static const String modeGeminiFull = 'AI Scribe · Gemini';
  static const String modeAsrFull = 'Live ASR · Sarvam';
  static const String modeSheetTitle = 'AI Scribe mode';
  static const String modeGeminiTitle = 'AI Scribe (Gemini)';
  static const String modeGeminiDesc = 'Records full consultation. AI analyzes after recording ends.';
  static const String modeAsrTitle = 'Live ASR (Sarvam)';
  static const String modeAsrDesc = 'Real-time Bengali transcript + live detected symptoms.';
  static const String modeGeminiDefault = 'Default';
}

/// Bottom-nav tab labels + placeholder copy.
/// Pilot slice of the localization seam (see [LoginStrings] doc comment).
abstract final class BottomNavStrings {
  BottomNavStrings._();

  static String get home => AppLocale.isBangla ? 'হোম' : 'Home';
  static String get patients => AppLocale.isBangla ? 'রোগী' : 'Patients';

  // TASKS-STASHED: unused by the nav bar itself (see bottom_nav.dart) since
  // GitHub issue #84 (2026-07-13) — reserved for the stashed Tasks tab, not
  // dead code. Do not remove.
  static String get tasks => AppLocale.isBangla ? 'কাজ' : 'Tasks';
  static String get assistant => AppLocale.isBangla ? 'সহকারী' : 'Assistant';

  // Assistant placeholder screen
  static String get assistantTitle => assistant;
  static String get assistantPlaceholderHeading =>
      AppLocale.isBangla ? 'এআই সহকারী' : 'AI Assistant';
  static String get assistantPlaceholderSubheading =>
      AppLocale.isBangla ? 'শীঘ্রই আসছে' : 'Coming soon';

  static String get pressBackAgainToExit => AppLocale.isBangla
      ? 'প্রস্থান করতে আবার ব্যাক চাপুন'
      : 'Press back again to exit';
}

/// Symptom triage picker screen strings.
/// Phase 1: Symptom-driven unified assessment flow.
abstract final class TriageStrings {
  TriageStrings._();

  // ── Screen titles ────────────────────────────────────────────────────────
  static const String pickerTitle = 'What symptoms does the patient have?';
  static const String pickerSubtitle = 'Select all that apply';
  static const String noSymptomsRoutineVisit = 'No symptoms / routine visit';
  static const String continueButton = 'Continue';
  static const String skipButton = 'Skip';
  static const String retryButton = 'Retry';

  // ── Cluster headers ──────────────────────────────────────────────────────
  static const String clusterDangerSigns = 'Danger Signs';
  static const String clusterFeverRespiratory = 'Fever & Respiratory';
  static const String clusterGiNutrition = 'GI & Nutrition';
  static const String clusterMaternal = 'Maternal';
  static const String clusterNcdMetabolic = 'NCD / Metabolic';
  static const String clusterTbIndicators = 'TB Indicators';
  static const String clusterMentalHealth = 'Mental Health';
  static const String clusterChildHealth = 'Child Health';

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
        return symptomConvulsions;
      case 'unconscious':
        return symptomUnconscious;
      case 'lethargy':
        return symptomLethargy;
      case 'not_eating':
        return symptomNotEating;
      case 'chest_indrawing':
        return symptomChestIndrawing;
      case 'stridor':
        return symptomStridor;
      case 'vaginal_bleeding':
        return symptomVaginalBleeding;
      case 'water_break':
        return symptomWaterBreak;
      case 'reduced_fetal_movement':
        return symptomReducedFetalMovement;
      case 'chest_pain':
        return symptomChestPain;
      case 'hemoptysis':
        return symptomHemoptysis;
      // Fever & respiratory
      case 'fever':
        return symptomFever;
      case 'cough':
        return symptomCough;
      case 'cough_over_2_weeks':
        return symptomCoughOver2Weeks;
      case 'difficulty_breathing':
        return symptomDifficultyBreathing;
      case 'fast_breathing':
        return symptomFastBreathing;
      case 'shortness_breath':
        return symptomShortnessBreath;
      // GI & nutrition
      case 'diarrhea':
        return symptomDiarrhea;
      case 'bloody_diarrhea':
        return symptomBloodyDiarrhea;
      case 'vomiting':
        return symptomVomiting;
      case 'loss_appetite':
        return symptomLossAppetite;
      case 'muac_red':
        return symptomMuacRed;
      case 'visible_wasting':
        return symptomVisibleWasting;
      case 'edema_both_feet':
        return symptomEdemaBothFeet;
      case 'weight_loss':
        return symptomWeightLoss;
      // Maternal
      case 'pregnant':
        return symptomPregnant;
      case 'headache_severe':
        return symptomHeadacheSevere;
      case 'blurred_vision':
        return symptomBlurredVision;
      case 'abdominal_pain':
        return symptomAbdominalPain;
      case 'swelling_face_hands':
        return symptomSwellingFaceHands;
      case 'high_bp_known':
        return symptomHighBpKnown;
      case 'labor_signs':
        return symptomLaborSigns;
      // NCD / metabolic
      case 'dizziness':
        return symptomDizziness;
      case 'numbness':
        return symptomNumbness;
      case 'polyuria':
        return symptomPolyuria;
      case 'polydipsia':
        return symptomPolydipsia;
      case 'foot_pain':
        return symptomFootPain;
      case 'foot_wound':
        return symptomFootWound;
      // TB indicators
      case 'night_sweats':
        return symptomNightSweats;
      case 'fatigue':
        return symptomFatigue;
      case 'tb_contact':
        return symptomTbContact;
      // Mental health
      case 'feeling_sad':
        return symptomFeelingSad;
      case 'anxiety':
        return symptomAnxiety;
      case 'sleep_difficulty':
        return symptomSleepDifficulty;
      // Child health
      case 'ear_problem':
        return symptomEarProblem;
      case 'skin_rash':
        return symptomSkinRash;
      case 'eye_discharge':
        return symptomEyeDischarge;
      case 'umbilicus_red':
        return symptomUmbilicusRed;
      case 'jaundice':
        return symptomJaundice;
      // AI Scribe triage vocab — codes not in the cluster catalog
      case 'heavy_bleeding':
        return symptomHeavyBleeding;
      case 'foul_smelling_vaginal_discharge':
        return symptomFoulSmellingVaginalDischarge;
      case 'epigastric_pain':
        return symptomEpigastricPain;
      case 'headache':
        return symptomHeadache;
      case 'edema':
        return symptomEdema;
      case 'breast_pain':
        return symptomBreastPain;
      case 'breast_swelling':
        return symptomBreastSwelling;
      case 'perineal_wound_discharge':
        return symptomPerinealWoundDischarge;
      case 'painful_urination':
        return symptomPainfulUrination;
      case 'breathlessness':
        return symptomBreathlessness;
      case 'leaking_fluid_vagina':
        return symptomLeakingFluidVagina;
      case 'painful_uterine_contractions':
        return symptomPainfulUterineContractions;
      case 'one_sided_weakness':
        return symptomOneSidedWeakness;
      case 'swelling_both_feet':
        return symptomSwellingBothFeet;
      case 'palpitations':
        return symptomPalpitations;
      case 'swelling_one_leg':
        return symptomSwellingOneLeg;
      case 'excessive_thirst':
        return symptomExcessiveThirst;
      case 'foot_numbness':
        return symptomFootNumbness;
      case 'weakness':
        return symptomWeakness;
      default:
        return code;
    }
  }

  // ── Eligible services grid (Step 1) ───────────────────────────────────────
  static const String eligibleServicesHeader = '✦ Eligible services';
  static const String eligibleServicesTag = 'Age & gender based';
  static const String enrolledBadge = 'Enrolled';
  static const String pwHint = "⚠ Select 'PW' first to unlock ANC";
  /// Chip label — Android "Pregnancy Outcome" menu (not mother PNC).
  static String get pregnancyOutcomeChip =>
      AppLocale.isBangla ? 'গর্ভাবস্থার ফলাফল' : 'Pregnancy Outcome';
  static String get deliveryHint => AppLocale.isBangla
      ? 'গর্ভাবস্থার ফলাফল এই পরিদর্শনে জন্ম নথিভুক্ত করে এবং এএনসি সরায়'
      : 'Pregnancy Outcome documents the birth this visit and clears ANC';
  static String get ancDeliveryConflictHint => AppLocale.isBangla
      ? '⚠ গর্ভাবস্থার ফলাফল পরিদর্শনে এএনসি উপলব্ধ নয় — আগে ফলাফল চিপ সরান'
      : '⚠ ANC is unavailable on a pregnancy-outcome visit — deselect Pregnancy Outcome first';
  static String get pncOnlyPostpartumHint => AppLocale.isBangla
      ? '⚠ প্রসবের পর মায়ের পিএনসি উপলব্ধ — এখন গর্ভাবস্থার ফলাফল ব্যবহার করুন'
      : '⚠ Mother PNC is available after delivery — use Pregnancy Outcome now';

  static String selectProgrammeA11y(String label) => 'Select $label';
  static String deselectProgrammeA11y(String label) => 'Deselect $label';
  static String enrolledProgrammeA11y(String label) =>
      'Enrolled $label — tap to include or exclude from this visit';
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
  static String sectionProgress(int current, int total, String sectionTitle) =>
      'Section $current of $total — $sectionTitle';

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
      'Facility identified for delivery';
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
        return fieldTemperature;
      case 'fieldBreathsPerMinute':
        return fieldBreathsPerMinute;
      case 'fieldWeightKg':
        return fieldWeightKg;
      case 'fieldMuacCm':
        return fieldMuacCm;
      case 'fieldSpo2':
        return fieldSpo2;
      case 'fieldHasCough':
        return fieldHasCough;
      case 'fieldCoughDays':
        return fieldCoughDays;
      case 'fieldHasFever':
        return fieldHasFever;
      case 'fieldFeverDays':
        return fieldFeverDays;
      case 'fieldHasDiarrhea':
        return fieldHasDiarrhea;
      case 'fieldUnableToBreastfeed':
        return fieldUnableToBreastfeed;
      case 'fieldVomitsEverything':
        return fieldVomitsEverything;
      case 'fieldHasConvulsions':
        return fieldHasConvulsions;
      case 'fieldLethargic':
        return fieldLethargic;
      case 'fieldChestIndrawing':
        return fieldChestIndrawing;
      case 'fieldStridor':
        return fieldStridor;
      case 'fieldIsBloodyDiarrhea':
        return fieldIsBloodyDiarrhea;
      case 'fieldHasFastBreathing':
        return fieldHasFastBreathing;
      case 'fieldRdtResult':
        return fieldRdtResult;
      case 'fieldActDispensed':
        return fieldActDispensed;
      case 'fieldOrsDispensed':
        return fieldOrsDispensed;
      case 'fieldZincDispensed':
        return fieldZincDispensed;
      case 'fieldAmoxicillinDispensed':
        return fieldAmoxicillinDispensed;
      case 'fieldHasCoughLastedLonger':
        return fieldHasCoughLastedLonger;
      case 'fieldHasNightSweats':
        return fieldHasNightSweats;
      case 'fieldHasWeightLoss':
        return fieldHasWeightLoss;
      case 'fieldRelationshipToIC':
        return fieldRelationshipToIC;
      case 'fieldSleepLocation':
        return fieldSleepLocation;
      case 'fieldPreviouslyTreatedForTB':
        return fieldPreviouslyTreatedForTB;
      // Shared vitals
      case 'fieldHeight':
        return fieldHeight;
      case 'fieldWeight':
        return fieldWeight;
      case 'fieldPulse':
        return fieldPulse;
      // ANC fields
      case 'fieldBloodPressureSystolic':
        return fieldBloodPressureSystolic;
      case 'fieldBloodPressureDiastolic':
        return fieldBloodPressureDiastolic;
      case 'fieldAncWeight':
        return fieldAncWeight;
      case 'fieldFundalHeight':
        return fieldFundalHeight;
      case 'fieldFetalHeartRate':
        return fieldFetalHeartRate;
      case 'fieldFetalMovement':
        return fieldFetalMovement;
      case 'fieldOedema':
        return fieldOedema;
      case 'fieldEdema':
        return fieldEdema;
      case 'fieldPallor':
        return fieldPallor;
      case 'fieldTtTdCompleted':
        return fieldTtTdCompleted;
      case 'fieldIfaProvided':
        return fieldIfaProvided;
      case 'fieldCalciumProvided':
        return fieldCalciumProvided;
      case 'fieldFacilityIdentifiedForDelivery':
        return fieldFacilityIdentifiedForDelivery;
      case 'fieldUltrasound':
        return fieldUltrasound;
      case 'fieldHemoglobin':
        return fieldHemoglobin;
      case 'fieldBloodSugar':
        return fieldBloodSugar;
      case 'fieldBloodSugarFasting':
        return fieldBloodSugarFasting;
      case 'fieldBloodSugarRandom':
        return fieldBloodSugarRandom;
      case 'fieldUrinaryAlbumin':
        return fieldUrinaryAlbumin;
      case 'fieldUrinarySugar':
        return fieldUrinarySugar;
      case 'fieldUrinaryBilirubin':
        return fieldUrinaryBilirubin;
      case 'fieldFolicAcidConsumed':
        return fieldFolicAcidConsumed;
      case 'fieldFolicAcidProvided':
        return fieldFolicAcidProvided;
      case 'fieldIfaConsumed':
        return fieldIfaConsumed;
      case 'fieldCalciumConsumed':
        return fieldCalciumConsumed;
      case 'fieldAncVisitsOtherProviders':
        return fieldAncVisitsOtherProviders;
      case 'fieldAncFromMedicalDoctor':
        return fieldAncFromMedicalDoctor;
      case 'fieldPreviousPregnancyComplications':
        return fieldPreviousPregnancyComplications;
      case 'fieldDangerSigns12':
        return fieldDangerSigns12;
      case 'fieldDangerSigns13to27':
        return fieldDangerSigns13to27;
      case 'fieldDangerSigns28to40':
        return fieldDangerSigns28to40;
      case 'fieldReferralFacility':
        return fieldReferralFacility;
      // NCD fields
      case 'fieldSystolic2':
        return fieldSystolic2;
      case 'fieldDiastolic2':
        return fieldDiastolic2;
      case 'fieldIsRegularSmoker':
        return fieldIsRegularSmoker;
      case 'fieldMedAdherence':
        return fieldMedAdherence;
      case 'fieldNcdSymptoms':
        return fieldNcdSymptoms;
      case 'fieldHasSymptoms':
        return fieldHasSymptoms;
      case 'fieldNewWorseningSymptoms':
        return fieldNewWorseningSymptoms;
      case 'fieldCompliance':
        return fieldCompliance;
      case 'fieldGlucoseValue':
        return fieldGlucoseValue;
      case 'fieldGlucoseType':
        return fieldGlucoseType;
      case 'fieldHba1c':
        return fieldHba1c;
      case 'fieldFootExam':
        return fieldFootExam;
      case 'fieldFootWound':
        return fieldFootWound;
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
  static const String fieldMorningHeadaches = 'Morning headaches?';
  static const String fieldChestTightnessOrSob =
      'Chest tightness or shortness of breath?';
  static const String fieldHighSaltIntake = 'High salt in daily food?';
  static const String fieldFamilyHistoryHtn = 'Family history of high BP?';
  static const String fieldOneSidedWeakness =
      'One-sided weakness or stroke signs?';

  // ── FINDRISC / Framingham fields ────────────────────────────────────────────
  static const String fieldOnBpMedication = 'On BP medication?';
  static const String fieldWaistCircumference = 'Waist circumference (cm)';
  static const String fieldIsPhysicallyActive =
      'Physically active ≥ 30 min/day?';
  static const String fieldEatsDailyFruitVeg = 'Eats fruit / vegetables daily?';
  static const String fieldHadPreviousHighGlucose =
      'Previous high blood glucose?';
  static const String fieldHasFamilyHistoryDm = 'Family history of diabetes?';

  // ── Family planning fields ───────────────────────────────────────────────────
  static const String fieldNumberOfLivingChildren = 'Number of living children';
  static const String fieldAgeOfLastChildMonths = 'Age of last child (months)';
  static const String fieldDesireForFutureChildren =
      'Desire for future children';
  static const String fieldCurrentFpMethod = 'Current FP method';

  // ── Eye / cataract fields ────────────────────────────────────────────────────
  static const String fieldEyeDiseaseTypes = 'Eye disease type(s)';
  static const String fieldReferredForOperation = 'Referred for operation?';
  static const String fieldNcdServiceProvided = 'NCD service provided?';
  static const String fieldEyeTestOutcome = 'Eye test outcome';
  static const String fieldGlassPrescription = 'Glasses prescription';
  static const String fieldGlassesSold = 'Glasses sold?';
  static const String fieldReferPlace = 'Referral facility';

  // ── Programme group headers ─────────────────────────────────────────────────
  static const String groupGeneral = 'General checks';
  static const String groupNcd = 'NCD checks';
  static const String groupTb = 'TB checks';
  static const String groupAnc = 'Antenatal checks';
  static const String groupPnc = 'Postnatal checks';
  static const String groupImci = 'Child health checks';
  static const String groupEpi = 'Immunization';
  static const String groupNutrition = 'Nutrition';
  static const String groupFamilyPlanning = 'Family planning';
  static const String groupCataract = 'Cataract / eye disease';
  static const String groupEyeCare = 'Eye care';

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
  static const String fieldOverdueVaccines = 'Overdue vaccines';
  static const String fieldVaccinesGivenToday = 'Vaccines given today';

  // ── Field labels (NUTRITION) ────────────────────────────────────────────────
  static const String fieldEdemaOfBothFeet = 'Edema of both feet';
  static const String fieldVisibleWasting = 'Visible wasting';
  static const String fieldFeedingDifficulty = 'Feeding difficulty';
  static const String fieldSupplementaryFoodGiven = 'Supplementary food given';
  static const String fieldReferredForSam = 'Referred for SAM';

  // ── Field labels (PNC) ──────────────────────────────────────────────────────
  static const String fieldDaysPostDelivery = 'Days post-delivery';
  static const String fieldHasUterinePain = 'Uterine pain';
  static const String fieldHasExcessiveBleeding = 'Excessive bleeding';
  static const String fieldHasBreastProblem = 'Breast problem';
  static const String fieldNewbornPresent = 'Newborn present';
  static const String fieldNewbornBreastfeeding = 'Newborn breastfeeding';
  static const String fieldPncVitaminsGiven = 'PNC vitamins given';
  // PNC Mother
  static const String fieldGravida = 'Gravida';
  static const String fieldParity = 'Parity (total births)';
  static const String fieldLivingChildren = 'Living children';
  static const String fieldHtnPatient = 'Known HTN patient?';
  static const String fieldEclampsia = 'Pre-eclampsia / eclampsia?';
  static const String fieldOnTreatmentHtnEclampsia =
      'On treatment for HTN / eclampsia?';
  static const String fieldDmPatient = 'Known DM patient?';
  static const String fieldGdmPatient = 'Known GDM patient?';
  static const String fieldOnTreatmentDmGdm = 'On treatment for DM / GDM?';
  static const String fieldFastingBloodSugar = 'Fasting blood sugar (mmol/L)';
  static const String fieldRandomBloodSugar = 'Random blood sugar (mmol/L)';
  static const String fieldPostpartumDangerSigns = 'Postpartum danger signs';
  static const String fieldVitaminAConsumed = 'Vitamin A capsule consumed?';
  static const String fieldIfaTabletsConsumed = 'IFA tablets consumed';
  static const String fieldIfaTabletsProvided = 'IFA tablets provided';
  static const String fieldCalciumTabletsConsumed = 'Calcium tablets consumed';
  static const String fieldCalciumTabletsProvided = 'Calcium tablets provided';
  static const String fieldFamilyPlanningMethods = 'Family planning method';
  // PNC Neonatal
  static const String fieldPncNeonateSigns = 'Newborn danger signs';
  static const String fieldOtherPncNeonateSigns = 'Other newborn signs';
  static const String fieldNewbornReferredToSbcu = 'Newborn referred to SBCU?';
  static const String fieldLowBirthWeight = 'Low birth weight?';
  static const String fieldDeathOfNewborn = 'Death of newborn?';
  // PNC Child
  static const String fieldCongenitalDefect = 'Congenital defect?';
  static const String fieldPncChildWeight = 'Child weight (kg)';
  static const String fieldChildFeedLast24Hrs =
      'Child feeding in last 24 hours';
  static const String fieldOtherChildFeed = 'Other feed';
  static const String fieldHrsBreastFed =
      'Hours after birth breastfeeding started';
  static const String fieldMonthAdditionalFeedGiven =
      'Month additional food started';
  static const String fieldChildBreastFeeding = 'Child breastfeeding?';
  static const String fieldAdditionalFood24Hrs =
      'Additional food in last 24 hours?';
  static const String fieldReceivedVaccine = 'Child received vaccines?';
  static const String fieldDewormingMedicine = 'Child took deworming medicine?';
  static const String fieldAnyIllness = 'Any illness / complications?';
  static const String fieldChildIllnessType = 'Type of illness / complication';
  static const String fieldChildReferral = 'Referral made?';
  static const String fieldChildReferralFacilityType = 'Referral facility type';

  /// Resolve a section title from its [sectionId].
  static String sectionTitle(String sectionId) {
    switch (sectionId) {
      case 'vitals':
        return sectionVitals;
      case 'danger-signs':
        return sectionDangerSigns;
      case 'symptom-detail':
        return sectionSymptomDetail;
      case 'iccm-classify':
        return sectionIccmClassify;
      case 'tb-screen-detail':
        return sectionTbDetail;
      case 'anc-vitals':
        return sectionAncVitals;
      case 'anc-specific':
        return sectionAncSpecific;
      case 'ncd-htn':
        return sectionNcdHtn;
      case 'ncd-dm':
        return sectionNcdDm;
      case 'epi-review':
        return sectionEpiReview;
      case 'nutrition-detail':
        return sectionNutritionDetail;
      case 'pnc-check':
        return sectionPncCheck;
      case 'pnc-mother':
        return sectionPncMother;
      case 'pnc-neonatal':
        return sectionPncNeonatal;
      case 'pnc-child':
        return sectionPncChild;
      case 'ncd-findrisc':
        return sectionNcdFindrisc;
      case 'family-planning':
        return sectionFamilyPlanning;
      case 'cataract-exam':
        return sectionCataractExam;
      case 'eye-care-exam':
        return sectionEyeCareExam;
      default:
        return sectionId;
    }
  }

  // ── AI Scribe pre-fill indicators (S4.6) ───────────────────────────────────
  static const String unmappedFindingsTitle = 'Also mentioned';
  static const String scribeAiBadge = 'AI';
  static const String scribeAiPreFilledHint =
      'Pre-filled by AI — please verify';
  static const String scribeRecordButton = 'Record';

  // ── Cross-section reveal banner ─────────────────────────────────────────────
  static const String tbAddedBannerText =
      'TB screening added — cough ≥ 2 weeks';

  // ── Submit / orchestrator ───────────────────────────────────────────────────
  static String syncProgress(int done, int total) =>
      '$done of $total programmes synced';
  static const String submitButton = 'Submit Assessment';
  static const String resumeDraftTitle = 'Resume visit?';
  static const String resumeDraftMessage =
      'An unfinished assessment was found.';
  static const String resumeButton = 'Resume';
  static const String discardButton = 'Discard';
  static const String startOverButton = 'Start Over';
  static const String offlineFallbackBannerText =
      'Offline — showing basic guidance. Connect to internet for the full AI recommendation.';
  static const String nextButton = 'Next';
  static const String dismissOkButton = 'OK';

  // ── Extended field widget strings ───────────────────────────────────────────
  static const String selectDateHint = 'Select date';
  static const String bpSystolicHint = 'SYS';
  static const String bpDiastolicHint = 'DIA';
  static const String bpUnit = 'mmHg';
  static const String bpValidationError = 'Enter a valid reading';
  static const String bpDiastolicExceedsSystolicError =
      'Diastolic must be less than systolic';
  static const String pulseValidationError = 'Enter a pulse between 50 and 300 bpm';
  static const String glucoseValidationError = 'Enter a glucose reading between 1.0 and 15.0 mmol/L';
  static const String haemoglobinValidationError = 'Enter a Hb reading between 1.0 and 20.0 g/dL';
  static const String temperatureValidationError = 'Enter a temperature between 90 and 110°F, or 0 if it could not be measured';
  static const String fundalHeightValidationError = 'Enter a fundal height between 8 and 45 cm';
  static const String hba1cValidationError = 'Enter an HbA1c reading between 4.0% and 14.0%';
  static const String ageLabel = 'Age';
  static const String dobLabel = 'Date of Birth';
  static const String yearsShort = 'Y';
  static const String monthsShort = 'M';
  static const String daysShort = 'D';
  static const String noneSelected = 'None selected';
  static const String tapToSelect = 'Tap to select';
  static const String doneLabel = 'Done';
  static String nSelected(int n) => '$n selected';

  // ── BP / glucose range status labels ────────────────────────────────────────
  static const String rangeNormal = 'Normal';
  static const String rangeElevated = 'Elevated';
  static const String rangeBpStage1 = 'Slightly elevated';
  static const String rangeBpStage2 = 'Stage 2 HTN';
  static const String rangeBpCrisis = 'Hypertensive Crisis ⚠';
  static const String rangeInRange = 'In Range';
  static const String rangeOutOfRange = 'Out of Range';

  // ── Vital flag labels (abnormal indicator badges) ───────────────────────────
  static const String vitalFlagHigh = 'High ⚠';
  static const String vitalFlagLow = 'Low ⚠';

  // ── MUAC classification labels ───────────────────────────────────────────────
  static const String muacLabel = 'MUAC (cm)';
  static const String muacSam = 'SAM';
  static const String muacMam = 'MAM';
  static const String muacNormal = 'Normal';

  // ── Lab result reference prefix ──────────────────────────────────────────────
  static const String labReferencePrefix = 'Ref:';

  // ── Referral urgency labels ──────────────────────────────────────────────────
  static const String referralUrgencyLabel = 'Urgency';
  static const String referralRoutine = 'Routine';
  static const String referralUrgent = 'Urgent';
  static const String referralEmergency = 'Emergency';

  // ── Pregnancy profile labels ─────────────────────────────────────────────────
  static const String lmpLabel = 'Last Menstrual Period';
  static const String eddLabel = 'Estimated Due Date';
  static const String gestationalAgeLabel = 'Gestational Age';
  static const String gestationalAgeWeeks = 'wks';
  static const String gestationalAgeDays = 'days';
  static const String gestationalAgePreterm = 'Preterm (< 37 weeks)';
  static const String pregnancyOverviewNoData = 'Pregnancy data not available';
  static const String pregnancyOverviewLmp = 'LMP';
  static const String pregnancyOverviewEdd = 'EDD';

  // ── Glass prescription labels ────────────────────────────────────────────────
  static const String eyeOd = 'OD (Right)';
  static const String eyeOs = 'OS (Left)';
  static const String sphereLabel = 'Sphere';
  static const String cylinderLabel = 'Cylinder';
  static const String axisLabel = 'Axis';
  static const String glassPrescriptionSummary = 'Prescription recorded';

  // ── ANC visit summary chip (Step 1 — Before You Knock) ──────────────────────
  static const String ancSummaryEyebrow = 'ANC VISIT';
  static const String ancSummaryGaUnit = 'wks GA';
  static const String ancSummaryVisitPrefix = '#';
  static const String ancSummaryHighRisk = 'High-risk';
  static const String ancSummaryNearTerm = 'Near-term';
  static const String ancSummaryAncGap = 'ANC gap';
  static const String ancSummaryBpElevated = 'BP elevated';
  static const String ancSummaryParityFormat = 'G{g}P{p}';
  static String ancSummaryParity(int g, int p) => 'G${g}P$p';

  // ── Compound-widget column sub-labels ────────────────────────────────────────
  static const String heightShort = 'Height';
  static const String weightShort = 'Weight';
  static const String parityShort = 'Parity';
  static const String livingShort = 'Living';

  // ── Urine test sub-labels ────────────────────────────────────────────────────
  static const String urinaryAlbuminShort = 'Albumin';
  static const String urinarySugarShort = 'Sugar';
  static const String urinaryBilirubinShort = 'Bilirubin';

  // ── Supply pair sub-labels ───────────────────────────────────────────────────
  static const String supplyConsumedShort = 'Consumed';
  static const String supplyProvidedShort = 'Provided today';
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
  static const String referNowButton = 'Refer now';
  static const String addPathwayButton = 'Add to assessment';
  static const String dismissButton = 'Dismiss';

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
        return bpSevereMessage;
      case 'bpStage1Message':
        return bpStage1Message;
      case 'dangerSignMessage':
        return dangerSignMessage;
      case 'severePneumoniaMessage':
        return severePneumoniaMessage;
      case 'pneumoniaMessage':
        return pneumoniaMessage;
      case 'samMessage':
        return samMessage;
      case 'mamMessage':
        return mamMessage;
      case 'severeAnemiaMessage':
        return severeAnemiaMessage;
      case 'anemiaMessage':
        return anemiaMessage;
      case 'glucoseHighMessage':
        return glucoseHighMessage;
      case 'tbScreenAddMessage':
        return tbScreenAddMessage;
      case 'conflictReferralOverridesKey':
        return conflictReferralOverridesKey;
      case 'findriscModerateMessage':
        return findriscModerateMessage;
      case 'findriscHighMessage':
        return findriscHighMessage;
      case 'findriscVeryHighMessage':
        return findriscVeryHighMessage;
      case 'framinghamTriggerMessage':
        return framinghamTriggerMessage;
      case 'framinghamHighMessage':
        return framinghamHighMessage;
      case 'bpTrendCusumMessage':
        return bpTrendCusumMessage;
      case 'bpTrendEwmaMessage':
        return bpTrendEwmaMessage;
      case 'bpTrendSlopeMessage':
        return bpTrendSlopeMessage;
      case 'miniPiersHighMessage':
        return miniPiersHighMessage;
      case 'miniPiersCriticalMessage':
        return miniPiersCriticalMessage;
      case 'cataractNcdCoenrollMessage':
        return cataractNcdCoenrollMessage;
      case 'eyeCareReferralMessage':
        return eyeCareReferralMessage;
      default:
        return key;
    }
  }

  /// Resolve a rationale string by its key (as stored in [CdsAlert.rationaleKey]).
  static String rationale(String key) {
    switch (key) {
      case 'rationaleWhoHeartsBpSevere':
        return rationaleWhoHeartsBpSevere;
      case 'rationaleWhoHeartsStage1':
        return rationaleWhoHeartsStage1;
      case 'rationaleWhoImciDangerSign':
        return rationaleWhoImciDangerSign;
      case 'rationaleWhoImciSeverePneumonia':
        return rationaleWhoImciSeverePneumonia;
      case 'rationaleWhoImciPneumonia':
        return rationaleWhoImciPneumonia;
      case 'rationaleWhoMuacSam':
        return rationaleWhoMuacSam;
      case 'rationaleWhoMuacMam':
        return rationaleWhoMuacMam;
      case 'rationaleWhoAncAnemia':
        return rationaleWhoAncAnemia;
      case 'rationaleWhoAncMildAnemia':
        return rationaleWhoAncMildAnemia;
      case 'rationaleWhoPenDm':
        return rationaleWhoPenDm;
      case 'rationaleWhoTb4Symptom':
        return rationaleWhoTb4Symptom;
      case 'rationaleFindriscModerate':
        return rationaleFindriscModerate;
      case 'rationaleFindriscHigh':
        return rationaleFindriscHigh;
      case 'rationaleFindriscVeryHigh':
        return rationaleFindriscVeryHigh;
      case 'rationaleFraminghamTrigger':
        return rationaleFraminghamTrigger;
      case 'rationaleFraminghamHigh':
        return rationaleFraminghamHigh;
      case 'rationaleBpTrendCusum':
        return rationaleBpTrendCusum;
      case 'rationaleBpTrendEwma':
        return rationaleBpTrendEwma;
      case 'rationaleBpTrendSlope':
        return rationaleBpTrendSlope;
      case 'rationaleMiniPiersHigh':
        return rationaleMiniPiersHigh;
      case 'rationaleMiniPiersCritical':
        return rationaleMiniPiersCritical;
      case 'rationaleCataractNcdCoenroll':
        return rationaleCataractNcdCoenroll;
      case 'rationaleEyeCareReferral':
        return rationaleEyeCareReferral;
      default:
        return key;
    }
  }
}

/// Pathway review sheet + activation rationales.
/// Phase 1: Symptom-driven unified assessment flow.
abstract final class PathwayStrings {
  PathwayStrings._();

  // ── Review sheet ─────────────────────────────────────────────────────────
  static const String reviewSubtitle = 'Based on symptoms and patient history';
  static const String startAssessment = 'Start Assessment';
  static const String addProgramme = 'Add section manually';
  static const String confirmRemoveTitle = 'Skip this assessment?';
  static String confirmRemoveBody(String programmeName, String trigger) =>
      '$programmeName was recommended because: $trigger.\n\n'
      'Skipping will create a follow-up task so it surfaces next visit.';
  static const String keepButton = 'Keep';
  static const String skipAnywayButton = 'Skip anyway';

  // ── Pathway rationales (localized explainability) ────────────────────────
  static const String pathwayNeonateRationale =
      'Neonate assessment (age < 2 months)';
  static const String pathwayIccmRationale =
      'Child illness assessment (WHO IMCI)';
  static const String pathwayAncRationale =
      'Antenatal care — pregnancy confirmed';
  static const String pathwayPncRationale =
      'Postnatal care — within 6 weeks of delivery';
  static const String pathwayTbScreenRationale =
      'TB screening — WHO 4-symptom screen';
  static const String pathwayNcdHtnRationale = 'NCD — hypertension review';
  static const String pathwayNcdDmRationale = 'NCD — diabetes symptoms';
  static const String pathwayNutritionRationale =
      'Nutrition assessment — malnutrition indicators';
  static const String pathwayEpiRationale = 'Immunization — vaccines overdue';
  static const String pathwayManualRationale = 'Manually added';
  static const String pathwayFamilyPlanningRationale =
      'Family planning — unmet need or counselling due';
  static const String pathwayCataractRationale =
      'Cataract / eye disease — visual symptoms or known diagnosis';
  static const String pathwayEyeCareRationale =
      'Eye care — visual symptoms requiring eye test';

  // ── Programme display names ──────────────────────────────────────────────
  static const String programmeImci = 'ICCM / Child Illness';
  static const String programmePw = 'Pregnant Woman Registration';
  static const String programmeAnc = 'ANC';
  static const String programmePnc = 'PNC';
  static const String programmeNcd = 'NCD';
  static const String programmeTb = 'TB Screening';
  static const String programmeEpi = 'EPI / Immunization';
  static const String programmeNeonate = 'Neonate Assessment';
  static const String programmeNutrition = 'Nutrition Assessment';
  static String get programmeFamilyPlanning => AppLocale.isBangla ? 'পরিবার পরিকল্পনা' : 'Family Planning';
  static const String programmeCataract = 'Cataract / Eye Disease';
  static String get programmeEyeCare => AppLocale.isBangla ? 'চোখের যত্ন' : 'Eye Care';
  static const String programmeUnknown = 'Assessment';

  // ── Progress indicator ───────────────────────────────────────────────────
  static String assessmentProgress(int current, int total, String programme) =>
      'Assessment $current of $total — $programme';

  /// Returns the localized rationale for a pathway rationale key.
  static String rationale(String key) {
    switch (key) {
      case 'pathwayNeonateRationale':
        return pathwayNeonateRationale;
      case 'pathwayIccmRationale':
        return pathwayIccmRationale;
      case 'pathwayAncRationale':
        return pathwayAncRationale;
      case 'pathwayPncRationale':
        return pathwayPncRationale;
      case 'pathwayTbScreenRationale':
        return pathwayTbScreenRationale;
      case 'pathwayNcdHtnRationale':
        return pathwayNcdHtnRationale;
      case 'pathwayNcdDmRationale':
        return pathwayNcdDmRationale;
      case 'pathwayNutritionRationale':
        return pathwayNutritionRationale;
      case 'pathwayEpiRationale':
        return pathwayEpiRationale;
      case 'pathwayManualRationale':
        return pathwayManualRationale;
      case 'pathwayFamilyPlanningRationale':
        return pathwayFamilyPlanningRationale;
      case 'pathwayCataractRationale':
        return pathwayCataractRationale;
      case 'pathwayEyeCareRationale':
        return pathwayEyeCareRationale;
      default:
        return key;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TriageResultStrings
// ─────────────────────────────────────────────────────────────────────────────

abstract final class TriageResultStrings {
  TriageResultStrings._();

  // ── Step bar ────────────────────────────────────────────────────────────────
  static const String step1Label = 'Step 1 · Symptoms';
  static const String step2Label = 'Step 2 · Triage';
  static const String step3Label = 'Step 3 · Assessment';

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

  // ── Urgency card ────────────────────────────────────────────────────────────
  static const String urgentTitle = 'AI noticed something serious';
  static const String warningTitle = 'AI flagged a concern';
  static const String infoTitle = 'AI identified a programme';

  // ── Measurements section ────────────────────────────────────────────────────
  static const String measureSectionLabel = 'AI asks you to check these now';

  // IMCI measurements
  static const String measureTempLabel = 'Take temperature';
  static const String measureTempHint =
      'Place thermometer under arm for 1 minute';
  static const String measureBreathLabel = 'Count breaths in 1 minute';
  static const String measureBreathHint =
      'Watch the chest go up and down — count for 60 seconds';
  static const String measureChestLabel = 'Look at the chest';
  static const String measureChestHint =
      'Does the chest go IN when breathing? (chest in-drawing)';

  // NCD measurements
  static const String measureBpLabel = 'Take blood pressure';
  static const String measureBpHint =
      'Left arm, patient seated, at rest for 5 minutes';
  static const String measureWeightLabel = 'Weigh the patient';
  static const String measureWeightHint =
      'Remove shoes — record to nearest 0.1 kg';

  // ANC measurements
  static const String measureFundalLabel = 'Measure fundal height';
  static const String measureFundalHint =
      'Pubic symphysis to uterine fundus in cm';

  // ── Programme banner ────────────────────────────────────────────────────────
  static const String programmeBannerPrefix = 'AI identified: ';
  static const String programmeBannerSuffix = ' programme';
  static const String programmeBannerCta = 'Opening checklist →';

  // ── CTA ─────────────────────────────────────────────────────────────────────
  static const String ctaOpenChecklist = 'Open checklist →';
  static const String ctaNoPathways = 'Start routine visit →';
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
  static const String scribeBannerTitle =
      '🎙 AI Scribe — tap to fill the form by voice';
  static const String scribeBannerSubtitle =
      'SK talks to her/him — fields fill automatically';
  static const String scribeBannerDone = 'Voice capture complete';
  static const String scribeBannerRecording = 'Listening… tap to stop';
  static const String scribeBannerProcessing = 'AI is reviewing the recording';
  static const String scribeBannerTriageProcessing = 'Analysing symptoms…';
  static const String scribeBannerProcessingSubtitle = 'Transcribing your recording…';
  static String scribeDoneWithCount(int n) => n == 1
      ? 'Scribe complete · 1 symptom detected'
      : n > 1
          ? 'Scribe complete · $n symptoms detected'
          : 'Scribe complete';
  static const String scribeBannerDoneSubtitle = 'Tap to record again';
  static const String scribeBannerRecordingSubtitle = 'Tap anywhere to stop';
  static const String scribeBannerError = 'Voice review failed';
  static const String scribeBannerErrorSubtitle = 'Tap to try again';
  static const String scribeBannerNoSymptoms = 'No symptoms detected';
  static const String scribeBannerNoSymptomsSubtitle =
      'Speak the patient\'s symptoms clearly, then tap to try again';

  /// Accessibility label for the in-circle stop affordance shown while the
  /// AI Scribe is recording.
  static const String scribeStopRecordingLabel = 'Stop recording';

  // ── AI briefing cards ────────────────────────────────────────────────────
  static const String briefCardTitle = 'Before you knock · AI brief';
  static const String briefCard1Title = 'Before You Knock';

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
  static const String chipPregnant = 'Pregnant · ANC';
  static const String chipHtn = 'Known HTN';
  static const String chipDm = 'Known DM';
  static const String chipTbDue = 'TB screen due';
  static const String chipUnder5 = 'Under 5 · IMCI';
  static const String chipRoutine = 'Routine visit';

  // ── SK opener card ───────────────────────────────────────────────────────
  static const String skAsksLabel = 'SK ASKS THE FAMILY 👋';
  static const String skOpenerPhrase =
      'How is the family? Who needs to be seen today?';
  static const String skOpenerPhraseBn = 'আজকে কে কে অসুস্থ আছে?';

  // ── Duration picker ──────────────────────────────────────────────────────
  static const String durationTitle = 'How many days unwell?';
  static const String duration1Day = '1 day';
  static const String duration2To3Days = '2–3 days';
  static const String duration4Plus = '4+ days';

  // Duration values (stored in TriageViewModel)
  static const String durationValue1 = '1';
  static const String durationValue2to3 = '2-3';
  static const String durationValue4plus = '4+';

  // ── CTA button ───────────────────────────────────────────────────────────
  static const String ctaStartCheckup = 'Start Checkup →';
  static const String ctaRoutine = 'Start Checkup →';

  // ── No-symptom guard ────────────────────────────────────────────────────
  static const String noSymptomsGuard =
      'No symptoms selected — please check symptoms before proceeding.';
  static const String noSymptomsGuardCta = 'Continue anyway';

  // ── Status bar above CTA ────────────────────────────────────────────────
  static String symptomsSelectedStatus(int n) =>
      '$n ${n == 1 ? 'symptom' : 'symptoms'} selected';
  static String servicesOpeningStatus(int count, List<String> labels) {
    if (labels.isEmpty) return '';
    final caps = labels.map((l) => l.toUpperCase()).toList();
    if (caps.length == 1) return 'This visit will cover ${caps[0]} screening';
    final joined = caps.sublist(0, caps.length - 1).join(', ') +
        ' & ${caps.last}';
    return 'This visit will cover $joined';
  }

  // ── Other symptoms free-text ─────────────────────────────────────────────
  static const String otherSymptomsLabel = 'Other symptoms / Notes';
  static const String otherSymptomsHint = 'Type symptom manually…';
  static const String otherSymptomsAddFromList = 'Add from list';

  // ── AI-driven symptom list (replaces the hardcoded cluster grid) ─────────
  static const String detectedSymptomsTitle = 'AI-Detected Symptoms';
  static const String detectedSymptomsSubtitleFilled =
      'Review each symptom. Tap × to remove anything incorrect, or add what is missing.';
  static const String addSymptomSearchHint = 'Search or type symptom…';
  static const String searchSymptomsHint = 'Search symptoms…';
  static const String searchMoreHint = 'Type 3+ letters to find more symptoms';
  static const String searchNoResults = 'No symptoms found';

  /// Header for the shared (cross-programme) symptom section in the grid.
  static const String sectionGeneral = 'General';

  /// Header for selected symptoms that fall outside the default sections.
  static const String sectionFromSearch = 'Added from search';

  /// Shown below the default chip grid when enrolled-programme filtering is
  /// active, to let the SK know general + other-programme symptoms are via search.
  static const String searchOtherProgramsHint =
      'Search to add more symptoms';

  /// Shown as the empty-state body when the patient has no enrolled programmes
  /// and the default grid is intentionally empty.
  static const String searchOnlyEmptyHint =
      'Search for symptoms';

  // ── Non-enrolled programme enrollment prompt ──────────────────────────────
  /// Title for the bottom sheet shown when the SK selects a symptom that
  /// belongs to a programme the patient is not yet enrolled in.
  static const String enrollProgrammeSheetTitle = 'New program assessment';

  /// Body copy for the enrollment prompt. {symptom} and {programmes} are
  /// interpolated by the caller.
  static String enrollProgrammeSheetBody(
    String symptomLabel,
    String programmeNames,
  ) =>
      '"$symptomLabel" is associated with the $programmeNames program. '
      'Adding it will include the $programmeNames assessment in this visit.';

  static const String enrollProgrammeConfirmCta = 'Add to this visit';
  static const String enrollProgrammeCancelCta = 'Skip for now';
  static const String symptomsSelectedCount =
      'symptom selected'; // prefix with count: "$n symptom(s) selected"
  static String symptomsSelected(int n) =>
      '$n ${n == 1 ? 'symptom' : 'symptoms'} selected';
  static const String addSymptomInlineHint = 'Or type a symptom manually…';
  static const String addSymptomInlineButton = '+ Add';
  static const String addSymptomListExpand = 'Show symptom list';
  static const String addSymptomListCollapse = 'Hide symptom list';
  static const String addSymptomCta = 'Add symptoms';
  static const String addSymptomFromList = 'Add from list';
  static const String addSymptomSheetTitle = 'Add symptoms';
  static const String addSymptomSheetSubtitle =
      'Tap to add or remove. AI-detected symptoms are already ticked — press Done when finished.';
  static const String addSymptomSheetEmpty = 'All symptoms already added.';
  static const String addSymptomSheetDone = 'Done';
  static String addSymptomSheetCounter(int added) =>
      added == 0 ? 'No symptoms selected' : '$added selected';
  static const String removeSymptomSemanticPrefix = 'Remove symptom';
}

/// Strings for the AI Programme Selection step (Step 2 of the visit flow).
///
/// Surfaces the AI's programme recommendations grounded in BRAC + Bangladesh
/// national clinical guidelines and lets the SK accept / reject before the
/// screening form loads.
abstract final class ProgrammeSelectionStrings {
  ProgrammeSelectionStrings._();

  static const String stepLabel = 'Programmes';
  static const String stepTitle = 'AI recommended programmes';

  // Loading / empty states
  static const String loadingTitle = 'AI is reviewing the symptoms…';
  static const String loadingSubtitle =
      'Checking BRAC protocols and Bangladesh national clinical guidelines';
  static const String failedTitle = 'Unable to load AI recommendations';
  static const String failedSubtitle =
      'Continue with the current enrolment or add a programme manually.';
  static const String retry = 'Retry';

  // Current Programme widget
  static const String currentProgrammeTitle = 'Current Programme';
  static const String currentProgrammeNone =
      'Patient is not enrolled in any programme yet.';
  static const String consistencyConsistent =
      'Selected symptoms are consistent with this programme.';
  static const String consistencyInconsistent =
      'Selected symptoms do not strongly match this programme.';

  // AI Recommended Programmes widget
  static const String aiRecommendedTitle = 'AI Recommended Programmes';
  static String confidenceChip(int pct) => '$pct% confidence';
  static const String currentBadge = 'Current';
  static const String acceptCta = 'Add';
  static const String acceptedCta = 'Added';
  static const String rejectCta = 'Skip';

  // ── Manual-add confirmation dialog ───────────────────────────────────────
  /// Title fires when the SK selects a programme directly from the manual
  /// add sheet — keeps a deliberate confirmation before opening the form.
  static String addConfirmTitle(String programmeTag) =>
      'Add $programmeTag assessment?';
  static const String addConfirmBody =
      'This will open the screening questions for the selected programme. '
      'You can remove it later from the recommendations list.';
  static const String addConfirmCta = 'Yes, add';
  static const String addConfirmCancel = 'Cancel';

  /// Skip confirmation when SK rejects an AI recommendation card.
  static String skipConfirmTitle(String programmeTag) =>
      'Skip $programmeTag for this visit?';
  static const String skipConfirmBody =
      'The AI recommended this programme based on the patient\'s symptoms and '
      'history. Are you sure you want to skip it?';
  static const String skipConfirmCta = 'Yes, skip';
  static const String skipConfirmCancel = 'Keep it';

  // ── Review-before-continue sheet ─────────────────────────────────────────
  /// Title — "Review N programme(s)".
  static String reviewSheetTitle(int count) =>
      count == 1 ? 'Review 1 programme' : 'Review $count programmes';
  static const String reviewSheetSubtitle =
      'Confirm the assessments below. You can add or remove before continuing.';
  static const String reviewSheetEmpty =
      'No programmes selected. Add one before continuing, or proceed with a '
      'routine visit.';
  static const String reviewSheetAddMore = 'Add another programme';
  static const String reviewSheetBack = 'Back';

  // Cross-program notice callout
  static const String crossNoticeTitle = 'Cross-programme alert';

  // Add programme sheet
  static const String addProgrammeCta = 'Add another programme';
  static const String addProgrammeSheetTitle = 'Add a programme';
  static const String addProgrammeSheetSubtitle =
      'Tap to select. Already-recommended programmes are hidden.';
  static const String addProgrammeSheetEmpty =
      'All programmes already selected.';

  // Continue
  static String continueCta(int count) => count <= 1
      ? 'Continue with $count programme'
      : 'Continue with $count programmes';
  static const String continueCtaEmpty = 'Continue (no programme)';

  // Rationale source labels — match RationaleSource.displayLabel but as
  // string constants so widgets can show them inline.
  static const String sourceBrac = 'BRAC';
  static const String sourceBdNational = 'BD national';
  static const String sourcePatientContext = 'Context';
  static const String sourceSymptom = 'Symptom';

  // Confirmation toasts shown when the SK accepts / removes a programme.
  static String toastAdded(String programmeTag) =>
      '$programmeTag added to this visit';
  static String toastRemoved(String programmeTag) =>
      '$programmeTag removed from this visit';
}

/// Visit completion screen strings.
/// Used by [VisitCompleteScreen].
abstract final class VisitCompleteStrings {
  VisitCompleteStrings._();

  static const String title = 'Visit Complete';
  static const String saved = 'Assessment saved';
  static const String referralWarning =
      'Referral recommended based on clinical findings';
  static const String bookTeleconsult = 'Book Teleconsult';
  static const String sendCounsellingMessage = 'Send Counselling Message';
  static const String createReferral = 'Create Referral';
  static const String backToHome = 'Back to Home';
  static const String doneForNow = 'Done for Now';
  static const String ncdCallDoctor = '📱 Call a doctor now';
  static const String ncdBookHospital = '🏥 Book hospital visit & refer';

  static const String householdMembersTitle = 'Members in this household';

  static const String ancFirstVisitCounsellingTitle =
      'First ANC Visit — Key Messages';
  static const String ancFirstVisitCounselling =
      'Congratulations on this pregnancy! Today we:\n'
      '• Registered you in the ANC programme\n'
      '• Measured your blood pressure and weight\n'
      '• Scheduled your next visit in 4 weeks\n\n'
      'Remember to:\n'
      '• Take your iron-folate tablet every day\n'
      '• Eat nutritious food — dal, eggs, leafy vegetables\n'
      '• Rest and avoid heavy lifting\n'
      '• Come immediately if you have heavy bleeding, severe headache, or blurred vision';
}

/// Strings for the unified 3-step visit flow (spec §3.1).
///
/// One `VisitFlowScreen` hosts: Step 1 Symptom check → Step 2 Vitals + form →
/// Step 3 AI Recommendation. Progress header shows step labels.
abstract final class VisitFlowStrings {
  VisitFlowStrings._();

  static const String step1Label = 'Symptoms';
  static const String step2Label = 'Vitals & form';
  static const String step3Label = 'AI recommends';

  // Step-pill titles inside the navy flow header.
  // Step 2 is the composite "AI programme recommendation → assessment form"
  // phase, so the pill label stays static and does NOT carry the programme
  // name (which is only known after the SK confirms).
  static const String step1Title = 'How are you?';
  static const String step2Title = 'Assessment forms';
  // Retained for backwards-compatibility with tests pinning the legacy
  // interpolation contract — the header no longer references this string.
  static const String step2TitleSuffix = 'form';
  static const String step3Title = 'Summary';
  static const String alsoCoverWhileHere = 'ALSO COVER WHILE YOU\'RE HERE';
  static const String aiCheckedFindings = 'AI checked all findings';

  static const String stepIndicator = 'Step %1 of 3';
  static String stepIndicatorFor(int oneBased) =>
      stepIndicator.replaceFirst('%1', oneBased.toString());

  static const String backToVisits = 'Back to visits';
  static const String discardConfirmTitle = 'Leave this visit?';
  static const String discardConfirm =
      'The symptoms, programmes and form entries on this visit will be '
      'discarded. You will start fresh next time.';
  static const String discardCancel = 'Stay on this visit';
  static const String discardConfirmCta = 'Yes, leave';
}

/// Strings for the AI Next Best Action (NABA) Step 3 screen.
abstract final class NabaStrings {
  NabaStrings._();

  static const String loadingTitle = 'Generating care plan…';
  static const String loadingSubtitle =
      'AI is reviewing the assessment. This takes a few seconds.';

  static const String errorTitle = 'Could not generate care plan';
  static const String errorSubtitle =
      'The assessment has been saved. Tap Retry to try again, or '
      'continue without AI recommendations.';
  static const String retryButton = 'Retry';
  static const String skipButton = 'Skip — go to home';

  static const String sectionDangerSigns = 'Danger signs to watch for';
  static const String sectionFindings = 'Clinical findings';
  static const String sectionNextActions = 'Next actions';
  static const String sectionCounselling = 'Counselling points';
  static const String sectionMedication = 'Medication advice';
  static const String sectionFollowUp = 'Follow-up schedule';
  static const String sectionReferral = 'Referral recommendation';
  static const String sectionWhatsApp = 'WhatsApp counselling (Bangla)';
  static const String sectionRationale = 'AI rationale';

  static const String humanReviewBadge = 'Human review recommended';
  static const String highConfidence = 'High confidence';
  static const String referralRequired = 'Referral required';
  static const String referralNotRequired = 'No referral needed';

  static const String urgencyNow = 'NOW';
  static const String urgencyToday = 'TODAY';
  static const String urgencyThisWeek = 'THIS WEEK';
  static const String urgencyRoutine = 'ROUTINE';

  static const String severityHigh = 'High';
  static const String severityMedium = 'Medium';
  static const String severityLow = 'Low';

  static const String copyWhatsApp = 'Copy';
  static const String whatsAppCopied = 'Copied!';
  static const String sendViaSms = 'Send via SMS';
  static const String sendViaWhatsApp = 'Send via WhatsApp';
  static const String sendThisMessage = 'Send this message';
  static const String aiCounsellingGuide = 'AI Counselling Guide';
  static const String whatsAppNotInstalled =
      'WhatsApp is not installed on this device.';
  static const String smsNotAvailable =
      'SMS is not available on this device.';

  static const String acceptProposal = 'Save & Go Home';
  static const String proposalNote =
      'This is an AI proposal. Review and accept to proceed.';

  static const String fallbackNotice =
      'AI service was unavailable. Care plan is based on clinical guidelines. '
      'Review and adjust based on your assessment.';
}

/// Teleconsult placeholder screen strings.
/// Used by [TeleconsultScreen].
abstract final class TeleconsultStrings {
  TeleconsultStrings._();

  static const String title = 'Teleconsult';
  static const String comingSoon = 'Coming soon';
  static const String placeholder =
      'Video consultation with a doctor will be available here.\n'
      'The SK can initiate a call directly from a completed visit.';
  static const String callAction = 'Start Video Call';
  static const String smsAction = 'Send SMS to Doctor';
}

/// Counselling messages placeholder screen strings.
/// Used by [CounsellingScreen].
abstract final class CounsellingStrings {
  CounsellingStrings._();

  static const String title = 'Counselling Messages';
  static const String subtitle = 'AI-generated health counselling';
  static const String sendWhatsApp = 'Send via WhatsApp';
  static const String sendSms = 'Send via SMS';
  static const String copyMessage = 'Copy message';
  static const String noMessage =
      'No counselling message generated for this visit.';
  static const String whatsAppNotInstalled =
      'WhatsApp is not installed on this device.';
  static const String smsNotAvailable = 'SMS is not available on this device.';
}

/// Training Hub placeholder screen strings.
/// Used by [TrainingScreen].
abstract final class TrainingStrings {
  TrainingStrings._();

  static const String title = 'Training Hub';
  static const String subtitle = 'Short videos · Learn at your own pace';
  static const String comingSoon = 'Coming soon';
  static const String certificatesTitle = 'Certificates';
  static const String certificatesSubtitle =
      'Complete modules to earn programme certificates';

  // Leaderboard
  static const String leaderboardTitle = '🏆 Top SKs this month';
  static const String leaderboardYou = '(You)';
  static const String leaderboardMotivationPrefix = '⚡ ';
  static const String leaderboardMotivationSuffix =
      ' pts away from 1st place · Watch 3 more videos to catch up!';

  // Section labels
  static const String sectionTodaysLessons = "TODAY'S LESSONS — BASED ON YOUR VISITS";
  static const String sectionMonthlyProgress = 'Your progress this month';

  // Video states
  static const String badgeNowPlaying = 'NOW PLAYING';
  static const String badgeCompleted = '✓ COMPLETED';
  static const String badgeLocked = '🔒 LOCKED';

  // Pill badges
  static String pillTriggered(String reason) => 'New · Triggered by $reason';
  static String pillDonePoints(int pts) => 'Done · +$pts pts';
  static const String pillNew = 'New';
  static String pillUnlockAfter(int n) => 'Complete $n more to unlock';
  static const String pillLocked = 'Locked';

  // Monthly stats
  static const String statVideos = 'Videos watched';
  static const String statPoints = 'Points earned';
  static const String statStreak = 'Day streak 🔥';

  // Locked snackbar
  static const String lockedSnackbar =
      'Complete earlier lessons to unlock this one';
}

/// Micro-coaching pilot strings — three-loop system:
/// Learn (morning cards + quiz) → Apply (visit-triggered) → Measure (telemetry).
abstract final class CoachingStrings {
  CoachingStrings._();

  static const String sectionTodayFocus = "TODAY'S FOCUS";
  static const String sectionAllModules = 'ALL MODULES';
  static const String minLabel = 'min';
  static const String passedLabel = 'Passed';
  static const String startLabel = 'Start';
  static const String reviewLabel = 'Review';
  static const String cardOf = 'of';
  static const String nextCard = 'Next';
  static const String prevCard = 'Back';
  static const String startQuiz = 'Take Quiz';
  static const String quizTitle = 'Quick Quiz';
  static const String questionOf = 'Question';
  static const String checkAnswer = 'Check Answer';
  static const String nextQuestion = 'Next';
  static const String quizResult = 'Quiz Complete';
  static const String quizPassed = 'You passed!';
  static const String quizFailed = 'Not quite — review the module and try again.';
  static const String tryAgain = 'Try Again';
  static const String backToModules = 'Back to Training';
  static const String rationaleLabel = 'Why?';
  static const String domainAnc = 'ANC';
  static const String domainNcd = 'NCD';
  static const String domainImci = 'IMCI';
  static const String domainTb = 'TB';
  static const String domainEpi = 'EPI';
  static const String domainNutrition = 'Nutrition';

  static String quizScore(int correct, int total) => '$correct / $total correct';
  static String cardProgress(int current, int total) => '$current of $total';
  static String questionProgress(int current, int total) => 'Question $current of $total';
}

/// NCD assessment form copy — spec §5.2.2 Hypertension Screening section.
///
/// Bengali secondary labels mirror the spec wording so the SK can match the
/// printed flow charts during home visits.
abstract final class NcdScreeningStrings {
  NcdScreeningStrings._();

  static const String sectionTitle = 'Hypertension screening';
  static const String sectionSubtitle =
      'Yes / No — strengthens AI clinical decision support.';

  // Stroke sign — band 1 short-circuit (§2.8.2).
  static const String strokeSignTitle = 'One-sided weakness or stroke signs?';
  static const String strokeSignBn = 'এক পাশে দুর্বলতা / স্ট্রোকের লক্ষণ?';
  static const String strokeSignSubtitle =
      'Sudden numbness or weakness on one side — immediate emergency referral.';

  static const String morningHeadachesTitle = 'Morning headaches?';
  static const String morningHeadachesBn = 'সকালে মাথা ব্যথা?';

  static const String chestTightnessTitle =
      'Chest tightness or shortness of breath?';
  static const String chestTightnessBn = 'বুকে চাপ বা শ্বাসকষ্ট?';

  static const String highSaltTitle = 'High salt in daily food?';
  static const String highSaltBn = 'খাবারে অতিরিক্ত লবণ?';

  static const String familyHistoryTitle = 'Family history of high BP?';
  static const String familyHistoryBn = 'বাবা-মায়ের / পরিবারে উচ্চ রক্তচাপ?';
}

/// Visit form host screen (fallback, non-sectioned mode).
abstract final class VisitFormStrings {
  VisitFormStrings._();

  static const String saveFailed =
      'Could not save the assessment. It is kept on this device — please try again.';
}

/// Unified JSON-driven form screen strings.
abstract final class UnifiedFormStrings {
  UnifiedFormStrings._();

  static const String submitLabel = 'Submit Assessment';
  static const String configLoadError =
      'Form configuration could not be loaded. Please restart the app.';
  static const String noPathways = 'No assessment pathways activated.';

  // BP reading field labels (must not be hardcoded in widget).
  static String get bpSystolicLabel =>
      AppLocale.isBangla ? 'সিস্টোলিক' : 'Systolic';
  static String get bpDiastolicLabel =>
      AppLocale.isBangla ? 'ডায়াস্টোলিক' : 'Diastolic';
  static String get bpPulseLabel =>
      AppLocale.isBangla ? 'নাড়ি' : 'Pulse';
  static const String bpUnit = 'mmHg';
  static const String bpPulseUnit = '/min';

  // Multi-reading BP widget (Android parity — up to 3 readings).
  static const String bpAddReadingLabel = '+ Add Reading';
  static const String bpReadingNumberLabel = 'Reading';
  static const String bpRemoveReadingTooltip = 'Remove reading';

  // Combined BP card (v13 reference — one card, side-by-side systolic|diastolic).
  static String get bpCardLabel =>
      AppLocale.isBangla ? 'রক্তচাপ' : 'Blood Pressure';
  /// @Deprecated — kept for call-site compatibility; prefer unit-only sublabels.
  static String get bpCardSubLabel => bpUnit;

  // Supplement pair cards (consumed + provided side-by-side).
  static String get supplementConsumedLabel =>
      AppLocale.isBangla ? 'গতমাসে সেবন' : 'Consumed last month';
  static String get supplementProvidedLabel =>
      AppLocale.isBangla ? 'এই পরিদর্শনে প্রদান' : 'Provided this visit';
  static String get folatePairLabel =>
      AppLocale.isBangla ? 'ফলিক অ্যাসিড ট্যাবলেট' : 'Folic acid tablets';
  static String get folatePairSubLabel =>
      AppLocale.isBangla ? 'ফলিক অ্যাসিড' : 'Folic Acid';
  static String get ifaPairLabel =>
      AppLocale.isBangla ? 'আইএফএ ট্যাবলেট' : 'IFA tablets';
  static String get ifaPairSubLabel =>
      AppLocale.isBangla ? 'আয়রন-ফলিক অ্যাসিড' : 'Iron-Folic Acid';
  static String get calciumPairLabel =>
      AppLocale.isBangla ? 'ক্যালসিয়াম ট্যাবলেট' : 'Calcium tablets';
  static String get calciumPairSubLabel =>
      AppLocale.isBangla ? 'ক্যালসিয়াম' : 'Calcium';

  /// Trailing tag shown on read-only computed fields (e.g. BMI, EDD, gest. week)
  /// to signal the value is auto-derived and not manually entered.
  static const String autoComputedTag = '(auto)';

  /// Placeholder shown in a computed field before its value is available.
  static const String autoComputedPlaceholder = '—';

  // Validation messages.
  static const String validationBannerTitle = 'Please complete required fields';
  static String validationFieldsRequired(int n) =>
      '$n required ${n == 1 ? 'field' : 'fields'} must be filled before submitting.';

  /// Badge label shown on the programme divider when AI pre-filled symptoms
  /// for that programme from triage Step 1.
  static const String aiBadgeLabel = 'AI';

  // Triage symptoms carry-over banner.
  static const String triageSymptomsTitle = 'Symptoms from Step 1';
  static String triageSymptomsCount(int n) =>
      '$n ${n == 1 ? 'symptom' : 'symptoms'} from Step 1';
  static const String triageSymptomsEmpty = 'No symptoms selected in Step 1.';

  // Section group labels shown as divider rows.
  static const String vitalsGroupLabel = 'Vitals';
  static const String enrolledGroupLabel = 'Enrolled Programmes';
  static const String recommendedGroupLabel = 'Recommended Programmes';

  // ── Vitals-trend card ("AI sees a trend across her N visits") ──────────────
  /// Header title; [n] is the number of visits shown (priors + today).
  static String trendCardTitle(int n) => 'AI sees a trend across her $n visits';

  /// "Today" column header for the trend table.
  static const String trendTodayColumn = 'Today';

  /// Prior-visit column header, e.g. `V1`, `V2`.
  static String trendVisitColumn(int n) => 'V$n';

  /// Column sub-label describing how long ago a prior visit was.
  static String trendWeeksAgo(int days) {
    if (days < 7) return days <= 1 ? '1d' : '${days}d';
    final weeks = (days / 7).round();
    return '${weeks}wks';
  }

  /// Metric row labels.
  static const String trendSystolic = 'Systolic';
  static const String trendDiastolic = 'Diastolic';
  static const String trendWeight = 'Weight';
  static const String trendWeightGain = 'Weight gain';
  static const String trendUrineProtein = 'Urine protein';

  /// Urine-protein grade labels used in the trend table.
  static const String trendUrineAbsent = 'Neg';
  static const String trendUrineTrace = 'Trace';
  static const String trendUrinePresent = 'Present';

  /// Placeholder for a metric not captured a given visit.
  static const String trendMissingValue = '—';

  /// Explanatory footer under the trend table — shown when BP is rising.
  static const String trendFooter =
      'Each reading is below its alert line — but they are climbing together '
      'across visits. No single rule fires.';

  /// Footer when readings are stable (no rising BP trend detected).
  static const String trendFooterStable =
      'Readings are stable across visits. No rising trend detected.';

  // ── BMI classification labels (WHO thresholds) ──────────────────────────────
  static const String vsBmiUnderweight = 'Underweight';
  static const String vsBmiNormal      = 'Normal';
  static const String vsBmiOverweight  = 'Overweight';
  static const String vsBmiObese       = 'Obese';

  // ── Live vital-status badge labels (rule-based, no ML) ─────────────────────
  static const String vsBpNormal           = 'Normal';
  static const String vsBpElevated         = 'Elevated';
  static const String vsBpSlightlyElevated = 'Slightly Elevated';
  static const String vsBpHigh             = 'High';
  static const String vsBpSevere           = 'Severe';

  static const String vsHbNormal           = 'Normal';
  static const String vsHbMild             = 'Mild Anaemia';
  static const String vsHbModerate         = 'Moderate Anaemia';
  static const String vsHbSevere           = 'Severe Anaemia';
  static const String vsHbWarningShort     = 'Anaemia';
  static const String vsHbWarningLong      =
      'Below 11 g/dL — Anaemia. Counsel on iron-rich diet and IFA adherence.';

  static const String vsUrineAbsent  = 'Absent';
  static const String vsUrineTrace   = 'Trace';
  static const String vsUrinePresent = 'Present';

  static String vsWeightDelta(double delta) {
    final sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)} kg';
  }

  static String vsLastWeight(double kg) => 'Last: ${kg.toStringAsFixed(1)} kg';

  static String vsFhLag(int cm)   => '$cm cm lag ⚠️';
  static String vsFhAhead(int cm) => '$cm cm ahead';
  static const String vsFhExpected = 'Expected';
  static String vsFhExpectedSubLabel(int gestWeeks) =>
      'Expected ~$gestWeeks cm at $gestWeeks wks';

  // ── Blood glucose status badges ─────────────────────────────────────────────
  static const String vsGlucoseNormal   = 'Normal';
  static const String vsGlucoseElevated = 'Elevated';
  static const String vsGlucoseHigh     = 'High';
  static const String vsGlucoseWarningElevated =
      'Elevated — advise dietary modification and refer for GDM screening.';
  static const String vsGlucoseWarningHigh =
      'High blood sugar — refer urgently for diabetes evaluation.';

  // ── Blood glucose combined entry card ───────────────────────────────────────
  static String get bloodGlucoseEntryLabel =>
      AppLocale.isBangla ? 'রক্তের শর্করা' : 'Blood Glucose';
  static String get bloodGlucoseEntrySubLabel => bloodGlucoseEntryUnit;
  static String get bloodGlucoseEntryHint =>
      AppLocale.isBangla ? 'মান লিখুন (mmol/L)' : 'Enter value (mmol/L)';
  static const String bloodGlucoseEntryUnit = 'mmol/L';

  // ── Blood glucose pair-card chrome ──────────────────────────────────────────
  static String get glucosePairLabel =>
      AppLocale.isBangla ? 'রক্তের শর্করা' : 'Blood Sugar';
  static String get glucosePairSubLabel => bloodGlucoseEntryUnit;
  static String get glucoseFastingLabel =>
      AppLocale.isBangla ? 'উপবাসকালীন' : 'Fasting';
  static String get glucoseRandomLabel =>
      AppLocale.isBangla ? 'এলোমেলো' : 'Random';

  // ── Height + Weight pair-card chrome ────────────────────────────────────────
  static String get heightWeightPairLabel =>
      AppLocale.isBangla ? 'উচ্চতা ও ওজন' : 'Height & Weight';
  static String get heightWeightPairSubLabel =>
      AppLocale.isBangla ? 'উচ্চতা ও ওজন' : 'Height & Weight';
  static String get heightSubLabel =>
      AppLocale.isBangla ? 'উচ্চতা' : 'Height';
  static String get weightSubLabel =>
      AppLocale.isBangla ? 'ওজন' : 'Weight';

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
  static const String tabLabel     = 'Gallery';
  static const String screenTitle  = 'Form Gallery';
  static const String vitalsTab    = 'Vitals';
  static const String symptomsTab  = 'Symptoms';
  static const String programmesTab = 'Programmes';
  static const String fields       = 'fields';
}

abstract final class PerformanceStrings {
  static const String title = 'My Performance';
  static const String periodWeek = 'Week';
  static const String periodMonth = 'Month';
  static const String heroSubline = 'visits this period';
  static const String weeklyTarget = 'Weekly target';
  static const String statVisitsToday = 'Visits today';
  static const String statVisitsTodaySub = 'so far';
  static const String statHouseholds = 'Households';
  static const String statHouseholdsSub = 'enrolled';
  static const String statReferrals = 'Referrals';
  static const String statReferralsSub = 'this week';
  static const String statThisWeek = 'Visits';
  static const String statThisMonth = 'Visits';
  static const String statTotalVisitsSub = 'this period';
  static const String sectionProgramme = 'VISITS BY PROGRAMME';
  static const String sectionRecent = 'RECENT ACTIVITY';
  static const String today = 'Today';
  static const String yesterday = 'Yesterday';
  static const String badgeCompleted = 'Completed';
  static const String badgeReferred = 'Referred';
  static const String loadError = 'Could not load performance data';
  static const String iconTooltip = 'My performance';

  static String periodLabelWeek(DateTime start, DateTime end) {
    final fmt = DateFormat('MMM d');
    return '${fmt.format(start)} – ${DateFormat('d').format(end)}';
  }

  static String periodLabelMonth(DateTime date) =>
      DateFormat('MMMM yyyy').format(date);

  // ── Wireframe v2 additions ──────────────────────────────────────────────────
  static const String appBarSubtitle = 'Jahnara Begum · SK ID 4521 · Manikganj Sadar';
  static const String heroScoreLabel = 'PERFORMANCE SCORE';
  static const String heroDesc = 'Blends visit completion, referral follow-through & SLA compliance';
  static const String slaLabel = 'SLA COMPLIANCE';
  static const String highRiskLabel = 'HIGH-RISK RESPONSE';
  static const String visitTrendLabel = 'VISIT TREND';
  static const String trendSteady = '↑ steady';
  static const String statVisitsCompleted = 'Visits Completed';
  static const String statReferralsMade = 'Referrals Made';
  static const String statReferralsCompleted = 'Referrals Completed';
  static const String statHouseholdsCovered = 'Households Covered';
  static const String statAvgVisitsDay = 'Avg Visits / Day';
  static const String statMissedOverdue = 'Missed / Overdue';
  static const String sectionServiceBreakdown = 'SERVICE-WISE BREAKDOWN';
  static const String insightBoldPhrase = 'more visits';
  static const List<String> weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const List<String> weekLabels = ['W1', 'W2', 'W3', 'W4'];
  static const String serviceAnc = 'ANC';
  static const String serviceNcd = 'NCD';
  static const String serviceChild = 'Child / Immunisation';
  static const String servicePnc = 'PNC';
  static const String serviceHousehold = 'Household enrolment';

  static String insightWeek(int pct) =>
      'You completed $pct% more visits than the Manikganj Sadar area average this week.';

  static String insightMonth(int pct) =>
      'You completed $pct% more visits than the Manikganj Sadar area average this month.';
}

/// Household enrollment flow strings.
abstract final class EnrollmentStrings {
  EnrollmentStrings._();

  // ── NID Scan Screen ──────────────────────────────────────────────────────
  static const String nidScanTitle = 'Scan Head\'s ID';
  static const String nidScanSubtitle = 'Position ID card in the frame';
  static const String nidScanOrCreate = 'Or create household manually';
  static const String nidScanCameraHint = 'Place ID card here';

  // ── Create Household Screen (Step 1) ──────────────────────────────────────
  static const String createHouseholdTitle = 'Household Information';
  static const String createHouseholdSubtitle = 'Step 1 of 2';

  static const String householdNumberLabel = 'Household Number';
  static const String householdNumberHint = 'Auto-generated';

  static const String healthWorkerLabel = 'Health Worker';
  static const String healthWorkerHint = 'Your name';

  static const String villageLabel = 'Village';
  static const String villageHint = 'Select village';
  static const String subVillageLabel = 'Sub-Village';
  static const String subVillageHint = 'Select sub-village';

  static const String householdTypeLabel = 'Household Type';
  static const List<String> householdTypes = [
    'Single-family',
    'Multi-family',
    'Institutional',
    'Other',
  ];

  static const String numberOfMembersLabel = 'Number of Members';
  static const String numberOfMembersHint = 'Estimated count';

  static const String houseNumberLabel = 'House Number';
  static const String houseNumberHint = 'e.g., 123 A/B';

  static const String occupationLabel = 'Primary Occupation';
  static const String occupationHint = 'Farmer, Labour, Business, etc.';

  static const String monthlyIncomeLabel = 'Monthly Income';
  static const List<String> incomeRanges = [
    '<10000',
    '10000-25000',
    '25000-50000',
    '>50000',
  ];

  static const String disabilityQuestionLabel =
      'Does any household member have a disability?';
  static const String disabilityDetailsLabel = 'Please specify';
  static const String disabilityDetailsHint = 'Type of disability';

  // ── Household Head Info Screen (Step 2) ──────────────────────────────────
  static const String householdHeadTitle = 'Household Head Information';
  static const String householdHeadSubtitle = 'Step 2 of 2';

  static const String headNameLabel = 'Full Name';
  static const String headNameHint = 'Head\'s full name';

  static const String fatherNameLabel = 'Father\'s Name';
  static const String fatherNameHint = 'As printed on the NID (Bangla)';
  static const String motherNameLabel = 'Mother\'s Name';
  static const String motherNameHint = 'As printed on the NID (Bangla)';

  static const String idTypeLabel = 'ID Type';
  static const List<String> idTypes = ['BRN', 'NID'];

  static const String idNumberLabel = 'ID Number';
  static const String idNumberHint = 'Birth Registration or NID number';

  static const String mobileNumberLabel = 'Mobile Number';
  static const String mobileNumberHint = '+880 1XXX XXXXXX';
  static const String mobileNotAvailableLabel = 'Not Available';

  static const String dateOfBirthLabel = 'Date of Birth';
  static const String dateOfBirthHint = 'DD/MM/YYYY';
  static const String approximateAgeLabel = 'Or Approximate Age';
  static const String approximateAgeHint = 'Years';

  static const String ageLabel = 'Age';
  static const String ageHint = 'Calculated from DOB';

  static const String genderLabel = 'Gender';
  static const List<String> genders = ['Male', 'Female', 'Other'];

  static const String maritalStatusLabel = 'Marital Status';
  static const List<String> maritalStatuses = [
    'Single',
    'Married',
    'Widowed',
    'Divorced',
  ];

  static const String disabilityStatusLabel = 'Disability Status';
  static const List<String> disabilityStatuses = [
    'None',
    'Physical',
    'Sensory',
    'Cognitive',
    'Multiple',
  ];

  // ── Add Member Screen ────────────────────────────────────────────────────
  static const String addMemberTitle = 'Add Household Member';
  static const String memberNameLabel = 'Full Name';
  static const String memberNameHint = 'Member\'s full name';

  static const String relationshipToHeadLabel = 'Relationship to Head';
  static const List<String> relationships = [
    'Spouse',
    'Child',
    'Parent',
    'Sibling',
    'Other',
  ];

  static const String memberVillageLabel = 'Village (if different)';
  static const String memberVillageHint = 'For external members';

  static const String nidScanCTA = 'Scan ID (Optional)';

  // ── Success Screen ───────────────────────────────────────────────────────
  static const String householdCreatedTitle = 'Household Enrolled!';
  static const String householdCreatedSubtitle =
      'Your household has been created successfully.';

  static const String householdDetailsTitle = 'Household Details';

  static const String membersAddedLabel = 'Members Added';
  static String membersAddedCount(int count) => '$count members';

  static const String addMoreMembers = 'Add Member';
  static const String saveHousehold = 'Save & Continue';

  // ── Shared validation messages ───────────────────────────────────────────
  static const String fieldRequired = 'This field is required';
  static const String invalidEmail = 'Please enter a valid email';
  static const String invalidPhone = 'Please enter a valid phone number';
  static const String invalidAge = 'Please enter a valid age';
  static const String invalidDate = 'Please enter a valid date';

  static const String enrollmentFailed = 'Enrollment failed';
  static const String enrollmentSuccess = 'Household enrolled successfully';

  // ── Common CTA buttons ───────────────────────────────────────────────────
  static const String next = 'Next';
  static const String previous = 'Previous';
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String submit = 'Submit';
  static const String createHousehold = 'Create Household';
  static const String scanAgain = 'Scan Again';

  // ── Redesign (v2) additions ───────────────────────────────────────────────
  static const String createHouseholdAppBarSubtitle =
      'Register a new household in your catchment area';

  static const String householdInfoSectionHeader = '🏠 Household Information';
  static const String householdHeadSectionHeader =
      '👤 Household Head Information';

  static const String autoGeneratedSuffix = '(auto-generated)';

  static const String householdTypeHint = 'Select type';
  static const String householdHeadOccupationLabel = 'Household Head Occupation';
  static const String monthlyIncomeInputLabel = 'Monthly Household Income (BDT)';
  static const String monthlyIncomeInputHint = 'e.g. 12000';
  static const String disabilityAnyPersonLabel =
      'Any person with disability?';
  static const String disabilityPersonCountLabel =
      'Number of persons with disability';
  static const String disabilityPersonCountHint = 'e.g. 1';

  static const String totalMembersLabel = 'Total Household Members';
  static const String totalMembersHint = 'e.g. 5';

  static const List<String> householdTypesV2 = ['BRAC VO', 'NVO'];
  static const List<String> gendersHead = ['Male', 'Female', 'Third Gender'];
  static const List<String> maritalStatusesV2 = [
    'Married',
    'Single',
    'Separated / Divorced',
    'Widowed',
    'Unmarried',
  ];
  static const List<String> disabilityStatusesV2 = ['Present', 'Absent'];
  static const List<String> disabilityYesNo = ['Yes', 'No'];
  static const List<String> gendersMember = ['Male', 'Female', 'Other'];
  static const List<String> idTypesV2 = ['BRN', 'National ID'];

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
  static const List<String> occupationOptions = [
    'Farmer',
    'Day labourer',
    'Rickshaw / transport',
    'Small business',
    'Garments worker',
    'Government service',
    'Private service',
    'Housewife',
    'Other',
  ];

  static const String continueArrow = 'Continue →';
  static const String createHouseholdCTA = '✓ Create Household';
  static const String saveMemberCTA = 'Save Member →';

  static const String mobileNotAvailableHint = 'Not Available';

  static const String nidScanButtonLabel = 'Scan NID card to read number';
  static const String nidScanNoBrnHint =
      'If member has no NID, enter Birth Registration ID instead.';
  static String nidNumberCaptured(String number) =>
      '✓ NID number captured: $number';
  static const String autoScanActive = 'Auto-scanning — hold card steady';
  static const String autoScanHint = 'Scanning every ~2 s · tap button to force capture';
  static const String nidScanNotFound =
      'Could not read the NID number. Try again or type it in below.';
  static const String nidScanError =
      'Camera unavailable. Please type the NID number below.';
  static const String headPrefilledFromScan =
      'Name, date of birth & NID read from the card — verify, then add '
      "father's & mother's names (Bangla) manually.";
  static String nidDetailsCaptured(String number) =>
      '✓ Read from NID · verify the details below';

  // ── Existing-patient lookup (POST /spice-service/patient/search) ───────────
  /// Shown in the Add Member form after a scanned NID matches an existing
  /// registration and the server demographics have been loaded in.
  static String existingPatientLoaded(String name) =>
      '✓ Already registered as $name — details loaded from server';

  /// Compact banner shown on the post-scan sheet when the scanned NID already
  /// belongs to a registered patient.
  static String existingPatientFound(String name) =>
      'Already registered as $name';

  static const String existingPatientHint =
      'This person is already in the system — link them to a household '
      'instead of registering again.';

  static const String dobHelperText =
      'If exact DOB is unknown, leave blank and enter approximate age below.';
  static const String villageHelperText =
      'Only if member lives outside this household\'s village';
  static const String villageMemberHint = 'Leave blank if same village';
  static const String otpHelperText = 'OTP verification required';

  static const String addMemberSubtitle = 'Adding to';

  static const String householdMembersSectionHeader = '👪 Household Members';

  static const String householdCreatedTitle2 = 'Household Created';

  // Detail card labels
  static const String detailLabelHouseholdNo = 'Household No.';
  static const String detailLabelHouseNo = 'House No.';
  static const String detailLabelVillage = 'Village';
  static const String detailLabelTotalMembers = 'Total Members';

  // ── Duplicate detection ───────────────────────────────────────────────
  static const String duplicateTitle = 'Patient already registered';
  static const String duplicateBody =
      'A member with this ID is already in your records. '
      'Registering again may create a duplicate.';
  static const String duplicateViewRecord = 'View record';
  static const String duplicateContinue = 'Continue anyway';
}

/// Visit landing screen — patient header, last-seen line, household co-flags,
/// and the "Start Visit" CTA. (`Start Visit` itself and the patient-name
/// fallback are shared with [PatientContextStrings].)
abstract final class VisitLandingStrings {
  VisitLandingStrings._();

  static const String startFailed = 'Failed to start visit';
  static const String firstVisit = 'First visit for this patient';
  static const String alsoInHousehold = 'Also in this household';
  static const String startingButton = 'Starting...';

  /// Patient age line, e.g. `42 years`.
  static String ageYears(int age) => '$age years';

  // ── Last-seen relative time ────────────────────────────────────────────────
  static const String seenToday = 'today';
  static const String seenYesterday = 'yesterday';

  /// e.g. `3 days ago`.
  static String seenDaysAgo(int days) => '$days days ago';

  /// e.g. `2 weeks ago`.
  static String seenWeeksAgo(int weeks) => '$weeks weeks ago';

  /// e.g. `Last seen yesterday — ANC`.
  static String lastSeen(String timeAgo, String programme) =>
      'Last seen $timeAgo — $programme';
}

/// Three-card pre-visit AI briefing screen shown between encounter creation
/// and triage. (Card 1 title is shared with
/// [SymptomPickerStrings.briefCard1Title]; `Next` is shared with
/// [ComposerStrings.nextButton].)
abstract final class VisitBriefingStrings {
  VisitBriefingStrings._();

  static const String fallbackTitle = 'Pre-Visit Briefing';

  // ── Card 1: Before You Knock ──────────────────────────────────────────────
  static const String card1Subtitle =
      'AI-generated briefing based on patient history';
  static const String briefingUnavailable =
      'AI briefing unavailable — check patient record manually.';

  // ── Card 2: Conversation Guide ────────────────────────────────────────────
  static const String card2Title = 'Conversation Guide';
  static const String card2Subtitle =
      'Personalised for this patient\'s programmes and history';
  static const String guideUnavailable = 'Conversation guide unavailable.';

  // ── Card 3: Transition ────────────────────────────────────────────────────
  static const String card3Title = 'Begin the Consultation';
  static const String card3Subtitle =
      'Ask the patient how they are feeling — the AI Scribe will start listening';
  static const String transitionFallback =
      'Ask the patient how she is feeling today and begin the consultation.';
  static const String scribeBadgeLabel = 'Ambient AI Scribe';
  static const String scribeBadgeDescription =
      'Automatically transcribes and structures clinical information as you speak.';
  static const String autofillBadgeLabel = 'Auto-fill Assessment';
  static const String autofillBadgeDescription =
      'Relevant fields in the assessment form are populated from the conversation.';
  static const String reviewBadgeLabel = 'You Review Everything';
  static const String reviewBadgeDescription =
      'All AI suggestions are proposals — you accept or edit before submitting.';

  // ── Bottom bar ────────────────────────────────────────────────────────────
  static const String beginAssessment = 'Begin Assessment';
  static const String skipBriefing = 'Skip briefing';
}

/// Visit details screen — per-encounter drill-down with section cards,
/// detail-row labels, and rawJson-derived additional details.
/// (`Diagnosis` is shared with [RealtimeAsrStrings.diagnosis].)
abstract final class VisitDetailsStrings {
  VisitDetailsStrings._();

  static const String fallbackTitle = 'Visit Details';
  static const String headerVisitFallback = 'Visit';

  // ── Visit Information section ─────────────────────────────────────────────
  static const String sectionVisitInformation = 'Visit Information';
  static const String labelService = 'Service';
  static const String generalVisitFallback = 'General Visit';
  static const String labelVisitDate = 'Visit Date';
  static const String labelReviewDate = 'Review Date';
  static const String labelVisitNumber = 'Visit Number';
  static const String labelStatus = 'Status';
  static const String labelVisitType = 'Visit Type';
  static const String labelPatientStatus = 'Patient Status';
  static const String labelEncounterId = 'Encounter ID';

  // ── Clinical section titles ───────────────────────────────────────────────
  static const String sectionPresentingComplaints = 'Presenting Complaints';
  static const String sectionSystemicExaminations = 'Systemic Examinations';
  static const String sectionObstetricExaminations = 'Obstetric Examinations';
  static const String sectionComplaints = 'Complaints';
  static const String sectionPhysicalExaminations = 'Physical Examinations';
  static const String sectionComorbidities = 'Comorbidities';
  static const String sectionComplications = 'Complications';
  static const String sectionInvestigations = 'Investigations';
  static const String sectionClinicalNotes = 'Clinical Notes';
  static const String notesLabel = 'Notes';

  // ── Visit history section ─────────────────────────────────────────────────
  static const String sectionVisitHistory = 'Visit History';
  static const String unknownVisitType = 'Unknown';

  /// e.g. `Encounter ID: enc-123`.
  static String encounterIdLine(String id) => '$labelEncounterId: $id';

  // ── Prescriptions section ─────────────────────────────────────────────────
  static const String sectionPrescriptions = 'Prescriptions';
  static const String unknownMedication = 'Unknown Medication';
  static const String labelDosage = 'Dosage';
  static const String labelFrequency = 'Frequency';
  static const String labelDuration = 'Duration';
  static const String labelInstructions = 'Instructions';

  // ── Provider section ──────────────────────────────────────────────────────
  static const String sectionProviderInformation = 'Provider Information';
  static const String labelProvider = 'Provider';
  static const String labelFacility = 'Facility';

  // ── Labour & Delivery section ─────────────────────────────────────────────
  static const String sectionLabourDelivery = 'Labour & Delivery';
  static const String labelDeliveryType = 'Delivery Type';
  static const String labelDeliveryAt = 'Delivery At';
  static const String labelDeliveryBy = 'Delivery By';
  static const String labelDeliveryStatus = 'Delivery Status';
  static const String labelDeliveryDateTime = 'Delivery Date/Time';
  static const String labelLabourOnset = 'Labour Onset';

  // ── Neonate / Baby section ────────────────────────────────────────────────
  static const String sectionNeonate = 'Neonate / Baby';
  static const String labelMotherAlive = 'Mother Alive';
  static const String yes = 'Yes';
  static const String no = 'No';
  static const String labelNeonateOutcome = 'Neonate Outcome';
  static const String labelStateOfBaby = 'State of Baby';
  static const String labelBirthWeight = 'Birth Weight';
  static const String labelBreastCondition = 'Breast Condition';
  static const String labelBreastNotes = 'Breast Notes';
  static const String labelInvolutionOfUterus = 'Involution of Uterus';
  static const String labelSigns = 'Signs';

  // ── Additional details section ────────────────────────────────────────────
  static const String sectionAdditionalDetails = 'Additional Details';

  /// Display labels for rawJson fields surfaced in the Additional Details
  /// section, keyed by the wire field name (keys are not user-facing).
  static Map<String, String> get additionalDetailLabels => {
    'referralStatus': 'Referral Status',
    'referralReason': 'Referral Reason',
    'nextFollowUpDate': 'Next Follow-up',
    'diagnosis': RealtimeAsrStrings.diagnosis,
    'prescription': 'Prescription',
    'labTests': 'Lab Tests',
    'symptoms': 'Symptoms',
    'riskLevel': 'Risk Level',
    'programType': 'Program Type',
    'encounterClass': 'Encounter Type',
    'reasonCode': 'Reason',
    'bloodPressureSystolic': 'BP Systolic',
    'bloodPressureDiastolic': 'BP Diastolic',
    'weight': 'Weight',
    'height': 'Height',
    'bmi': 'BMI',
    'temperature': 'Temperature',
    'pulseRate': 'Pulse Rate',
    'respiratoryRate': 'Respiratory Rate',
  };
}

/// Strings for [AssistantScreen] — conversational AI Q&A tab.
abstract final class AssistantStrings {
  AssistantStrings._();

  static const String title = 'AI Assistant';
  static const String subtitle = 'Apon Sushashthya';
  static const String inputHint = 'Ask a clinical question…';
  static const String errorMessage =
      'Could not reach the assistant. Check your connection.';
  static const String suggestedMuac = 'How do I measure MUAC?';
  static const String suggestedAncDanger = 'ANC danger signs?';
  static const String suggestedNcd = 'NCD medication adherence tips';
  static const String suggestedReferChild = 'When to refer a child?';
  static const String suggestedFindrisc = 'FINDRISC score interpretation';
  static const String emptyHeading = 'Ask me anything';
  static const String emptySubheading =
      'Clinical guidance, protocol reminders,\nand care tips — always at hand.';
  static const String retryLabel = 'Retry';
  static const String poweredBy =
      'Powered by Gemini · For clinical guidance only';
  static const String badgeLabel = 'AI';
  static const String tabAsk = 'Ask AI';
  static const String tabTraining = 'Training';
}

/// Strings for [HouseholdFollowUpScreen].
abstract final class HouseholdFollowUpStrings {
  HouseholdFollowUpStrings._();

  static const String title = 'Others in this household';
  static const String subtitle =
      'Check if any family members need care today.';
  static const String emptyState = 'No other household members need a visit.';
  static const String viewPatient = 'View patient';
  static const String doneButton = 'Done — go to home';
  static const String overdue = 'Overdue';
  static const String dueToday = 'Due today';
  static const String dueSoon = 'Due soon';
  static const String urgentLabel = 'Urgent';
}

// ─────────────────────────────────────────────────────────────────────────────
// Select Household screen (link member to existing household)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class SelectHouseholdStrings {
  static const String title = 'Select Household';
  static const String subtitle = 'Choose the household to link this member to';
  static const String searchHint = 'Search by name, house number, or village...';
  static const String catchmentCount = 'households in your catchment';
  static const String emptyState = 'No households found';
  static const String ctaPrefix = 'Link & Enrol';
  static const String unknownFamily = 'Unknown family';
  static const String membersLabel = 'members';
}

// ─────────────────────────────────────────────────────────────────────────────
// Link Member screen (member registration form for existing household)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class LinkMemberStrings {
  static const String title = 'Add Member';
  static const String selectedHouseholdLabel = 'Selected household';
  static const String ctaLabel = 'Link & Enrol Member';
  static const String submitting = 'Submitting…';
  static const String successMessage = 'Member linked successfully';
  static const String errorPrefix = 'Could not link member';
}

// ─────────────────────────────────────────────────────────────────────────────
// EPI / Immunisation timeline
// ─────────────────────────────────────────────────────────────────────────────
abstract final class EpiStrings {
  EpiStrings._();

  static const String screenTitle = 'Vaccination';
  static const String vaccinationCta = 'Vaccination';
  static const String noDobError =
      'Date of birth not available — cannot compute schedule.';

  static String overdueBanner(int count) =>
      '$count ${count == 1 ? 'vaccine' : 'vaccines'} overdue · Action needed today.';

  static const String statusCompleted = 'Given';
  static const String statusDueNow = 'Due now';
  static const String statusUpcoming = 'Upcoming';
  static const String statusNotYetDue = 'Not yet due';
  static const String statusLocked = 'Locked';

  static const String updateStatusCta = 'Update Status →';
  static const String vaccinesDueLabel = 'Vaccines due at this milestone';
  static const String dateAdministered = 'Date Administered';
  static const String notesOptional = 'Notes (Optional)';
  static const String notesHint = 'e.g. Child was well, no adverse reaction…';
  static const String markCompleted = 'Mark as Completed';
  static const String cancel = 'Cancel';
  static const String submitCta = 'Submit';
  static const String givenOn = 'Given';
  static const String doneVisitCta = 'Done → Continue Visit';
}

abstract final class ChildAssessmentStrings {
  ChildAssessmentStrings._();

  static const String sectionTitle = 'Child Assessment';
  static const String q6Label = 'Does the child have any congenital defect?';
  static const String q7Label = 'Weight';
  static const String q7Unit = 'kg';
  static const String q7Hint = 'e.g. 6.5';
  static const String q8Label = 'Is the child breastfeeding?';
  static const String q9Label =
      'In the past 24 hours, was the child given additional food?';
  static const String q10Label = 'Has the child received vaccines?';
  static const String q11Label = 'Has the child taken deworming medicine?';
  static const String q12Label = 'Any Illness/Complications?';
  static const String q13Label = 'If any complication, specify';
  static const String q13SelectAll = 'Select all that apply';
  static const String q14Label = 'Has referral been made?';
  static const String q15Label = 'Referral place';
  static const String yesOption = 'Yes';
  static const String noOption = 'No';
  static const String vaccinationCta = '💉  Vaccination  →';

  static const List<String> complicationOptions = [
    'Diarrhea',
    'Pneumonia',
    'Cannot stand or walk',
    'Cannot maintain body balance',
    'Cannot speak two meaningful words',
  ];

  static const List<String> referralPlaces = [
    'Medical College Hospital',
    'Government Hospital',
    'Upazila Health Complex',
    'Private Hospital/Clinic',
    'Health & Family Welfare Center',
    'Community Clinic',
  ];
}

/// Care Coordination Engine (CCE) — the referral SLA alert drawer.
/// All widget-facing copy for `lib/features/cce/`. Derivation-time strings
/// interpolated by the pure-Dart model live in `cce_alert.dart`.
abstract final class CceStrings {
  CceStrings._();

  // ── Drawer header ─────────────────────────────────────────────────────────
  static const String drawerTitle = 'Care Coordination Alerts';
  static const String poweredBy = 'Powered by CCE · Care Coordination Engine';
  static String actionsNeeded(int n) =>
      '$n action${n == 1 ? '' : 's'} needed';
  static const String done = 'Done';

  static const String explainer =
      'CCE tracks every patient after referral and triggers alerts when SLAs '
      'are breached — so no patient is lost between SK and facility.';

  // ── Bell entry point ──────────────────────────────────────────────────────
  static const String bellTooltip = 'Care Coordination Alerts';

  // ── Empty state ───────────────────────────────────────────────────────────
  static const String emptyTitle = 'All referrals on track';
  static const String emptyBody =
      'No SLA breaches. Every referred patient is accounted for between SK '
      'and facility.';

  // ── Card actions ──────────────────────────────────────────────────────────
  static const String actionCallFamily = 'Call family';
  static const String actionUpdateStatus = 'Update status';
  static const String actionLocate = 'Locate';
  static const String actionCheckIn = 'Check in';

  static const String noPhone = 'No phone number on file for this patient';
  static const String noLocation = 'No location on file for this patient';
  static const String dialFailed = 'Could not open the dialer';

  // ── Update-status sheet ───────────────────────────────────────────────────
  static String updateTitle(String patientName) => 'Update — $patientName';
  static const String updatePrompt = 'Where is the patient now?';
  static const String updateOptNotLeft = 'Not yet left home';
  static const String updateOptOnWay = 'On the way to facility';
  static const String updateOptArrived = 'Arrived at facility';
  static const String updateOptTreated = 'Seen by clinician / treated';
  static const String updateOptDischarged = 'Discharged (recovered)';

  static const String barrierPrompt = 'Add a barrier tag (optional)';
  static const String barrierTransport = 'Transport';
  static const String barrierCost = 'Cost';
  static const String barrierFamily = 'Family';
  static const String barrierDistance = 'Distance';

  static const String saveUpdate = 'Save update';
  static const String saveHint = 'Saves offline · syncs on next cycle';
  static const String updateSaved = 'Referral status updated';
  static const String selectStatus = 'Select the patient\'s current status';

  // ── Follow-up banner (completed cards) ───────────────────────────────────
  static String followUpDueBanner([String? date]) =>
      date != null ? 'Follow-up due · $date' : 'Follow-up due';

  // ── Update status sheet v2 (wireframe v14) ───────────────────────────────
  static const String updateSheetTitle = 'Update patient status';
  static const String updateSyncNote =
      'CCE will sync this update to the facility and supervisor';
  static const String updateOptReachedFacility = 'Patient reached facility';
  static const String updateOptTransportIssue =
      'Unable to travel — transport issue';
  static const String updateOptRefused = 'Patient refused referral';
  static const String updateOptRecoveredHome = 'Patient recovered at home';
  static const String updateOptOther = 'Other — add note';
  static const String updateConfirmSync = 'Confirm & sync to CCE';
  static const String updateCancel = 'Cancel';
  static const String updateOtherHint = 'Describe what happened…';
  static const String updateOtherRequired = 'Please add a note before saving';
}

/// Follow-up call logging — the device-side close/update flow.
abstract final class FollowUpCallStrings {
  FollowUpCallStrings._();

  static const String logCall = 'Log call';
  static const String sheetTitle = 'Log follow-up call';
  static const String outcomePrompt = 'How did the call go?';
  static const String outcomeSuccessful = 'Reached — successful';
  static const String outcomeUnsuccessful = 'Could not reach';
  static const String outcomeWrongNumber = 'Wrong number';
  static const String reasonLabel = 'Note (optional)';
  static const String reasonHint = 'e.g. no answer, will retry tomorrow';
  static const String save = 'Save call';
  static const String saved = 'Call logged — will sync on next cycle';
  static const String schedule = 'Schedule';
  static const String scheduled =
      'Follow-up scheduled — will sync on next cycle';
  static const String scheduleFailed = 'Could not schedule the follow-up';
  static const String selectOutcome = 'Select the call outcome';
  static const String closedNote =
      'Wrong number or exhausted attempts will close this follow-up.';
  static const String failed = 'Could not log the call';
}


abstract final class EnrollStrings {
  EnrollStrings._();

  static const String screenTitle = 'Add Services';
  static String selectFor(String name) => 'Select services for $name';
  static const String subtitle =
      'Add the health programmes this person needs. Tap a programme to select it.';
  static const String sectionPregnancy = 'PREGNANCY CARE';
  static const String sectionChronic = 'CHRONIC CONDITIONS';
  static const String sectionChild = 'CHILD HEALTH';
  static const String pregnantWomanLabel = 'Pregnant Woman';
  static const String pregnantWomanBengali = 'গর্ভবতী মা';
  static const String ancLabel = 'ANC Visit';
  static const String ancBengali = 'মাতৃস্বাস্থ্য সেবা';
  static const String pncLabel = 'PNC Visit';
  static const String pncBengali = 'প্রসবোত্তর সেবা';
  static const String ncdLabel = 'NCD Check';
  static const String ncdBengali = 'অসংক্রামক রোগ';
  static const String tbLabel = 'TB Check';
  static const String tbBengali = 'যক্ষ্মা';
  static const String imciLabel = 'Child Visit';
  static const String imciBengali = 'শিশু স্বাস্থ্য সেবা';
  static const String epiLabel = 'Vaccination';
  static const String epiBengali = 'টিকা';
  static const String lockedToastAnc =
      '⚠ Select "Pregnant Woman" first to unlock ANC';
  static const String lockedToastPnc =
      '⚠ Select "Pregnant Woman" first to unlock PNC';
  static const String noProgrammes =
      'No eligible programmes for this patient based on age and gender.';
  static String confirmCta(int n) =>
      n == 0 ? 'Select Programmes' : 'Confirm Enrollment ($n selected)';
  static const String savedToast = 'Programmes saved ✓';
  static const String addServicesCta = 'Add Services';
  static const String noServicesTitle = 'No services enrolled';
  static const String noServicesSubtitle =
      'Tap below to add health programmes for this patient.';
}

abstract final class PregnancyRegStrings {
  PregnancyRegStrings._();

  static const String sheetTitle = 'Register Pregnancy';
  static String forPatient(String name) => 'For $name';
  static const String sectionDates = 'PREGNANCY DATES';
  static const String lmpLabel = 'Last Menstrual Period (LMP)';
  static const String lmpRequired = '* Required';
  static const String lmpHint = 'Tap to select date';
  static const String eddLabel = 'Est. Due Date (EDD)';
  static const String gaLabel = 'Gestational Age';
  static const String tooEarlyWarning =
      '⚠ LMP is less than 6 weeks ago. Only basic details saved — full risk screening at next visit.';
  static const String sectionHistory = 'OBSTETRIC HISTORY';
  static const String gravidaLabel = 'Gravida (total pregnancies)';
  static const String parityLabel = 'Parity (live births)';
  static const String firstPregnancy = 'First pregnancy';
  static const String sectionRisk = 'RISK SCREENING';
  static String ageRiskNormal(int age) => 'Age $age · Normal age for pregnancy';
  static String ageRiskLow(int age) => '⚠ Age $age · Under 18 — high risk';
  static String ageRiskHigh(int age) => '⚠ Age $age · Over 35 — high risk';
  static const String conditionsLabel = 'Any existing conditions?';
  static const String conditionHtn = 'Hypertension / High BP';
  static const String conditionDiabetes = 'Diabetes';
  static const String conditionCsection = 'Previous C-section';
  static const String conditionComplicated = 'Previous complicated delivery';
  static const String registerCta = '🤰  Register Pregnancy';
  static const String skipCta = 'Skip for now';
  static const String savedToast = 'Pregnancy registered ✓';
  static const String lmpRequiredError = 'Please select the LMP date';
  static const String lmpFutureError = 'LMP cannot be in the future';
  static const String multiparaWarning = '⚠ Gravida > 4 — multipara risk';
}

abstract final class NewPatientVisitStrings {
  NewPatientVisitStrings._();

  static const String backTooltip = 'Back';
  static const String step1Label = '1. How are you?';
  static const String step3Label = '3. Summary';
  static const String howFeelFemale = 'How is she feeling today? 🎙';
  static const String howFeelMale = 'How is he feeling today? 🎙';
  static const String scribeTitle = 'AI Scribe';
  static const String scribeSubtitle = 'Tap and let her speak';
  static const String scribeStart = '🎙 Start';
  static const String searchHint = 'Search symptoms...';
  static const String noSymptomsFound = 'No symptoms found';
  static const String eligibleServicesHeader = '✦ Eligible services';
  static const String eligibleServicesTag = 'Age & gender based';
  static const String pwHint = "⚠ Select 'PW' first to unlock ANC";
  static const String startVisitCta = 'Start Visit →';
  static const String selectServiceCta = 'Select a service to continue';
}

/// Patient-scoped AI assistant (the floating "✦" sheet).
abstract final class PatientAiStrings {
  PatientAiStrings._();

  static String title(String name) => 'Ask about $name';
  static const String intro =
      "I have this patient's record. I'll answer only from their data — ask "
      'about their care, or tap an action below.';
  static const String inputHint = 'Ask about this patient...';
  static const String scopeNote = '🔒 Answers limited to this patient';
  static const String noPhone = 'No phone number on file for this patient';
  static const String dialFailed = 'Could not open the dialer';
  static const String fabTooltip = 'Ask AI about this patient';

  static const List<String> starters = [
    'Any danger signs to check?',
    'What should I do this visit?',
    'Is a referral needed?',
  ];
}

abstract final class ConsentStrings {
  ConsentStrings._();

  static const String title = 'Data Collection Consent';
  static const String subtitle = 'Apon Sushashthya Health Programme';
  static const String introText =
      'Before we register this household, we need your permission to collect and '
      'use health information for the purpose of providing community healthcare services.';
  static const String section1Title = 'What we collect';
  static const String section1Body =
      'We collect names, ages, health conditions, visit records, and contact details '
      'of household members enrolled in the UHIS Leapfrog programme.';
  static const String section2Title = 'How we use it';
  static const String section2Body =
      'Information is used by trained health workers to provide follow-up care, '
      'track programme outcomes, and improve community health services. '
      'It is never shared with third parties outside the programme.';
  static const String section3Title = 'Your rights';
  static const String section3Body =
      'You may withdraw consent at any time by contacting your village health worker. '
      'Data will be retained as required by national health regulations.';
  static const String checkboxLabel =
      'I have read and understood the above. I give consent for health data '
      'collection for members of this household.';
  static const String confirmButton = 'I Agree';
  static const String declineButton = 'Decline';
  static const String declineWarning =
      'Without consent, household registration cannot be completed.';
  static const String declineConfirm = 'Cancel registration';
  static const String declineCancel = 'Go back';
}

abstract final class CareThreadStrings {
  CareThreadStrings._();

  static const String anc = 'ANC / Pregnancy';
  static const String bp = 'Pre-eclampsia watch';
  static const String sugar = 'Blood sugar';
  static const String htn = 'Hypertension';
  static const String imm = 'Immunization';
  static const String growth = 'Growth monitoring';
  static const String pnc = 'Postnatal recovery';
  static const String newborn = 'Newborn care';
  static const String general = 'General enrollment';
  static const String illness = 'Past illness';
  static const String highrisk = 'High-risk pregnancy';
  static const String csection = 'Emergency C-section';
}
