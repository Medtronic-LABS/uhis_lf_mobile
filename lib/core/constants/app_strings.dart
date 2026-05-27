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

/// App-wide identity strings.
abstract final class AppStrings {
  AppStrings._();

  static const String appName = 'UHIS Next';
  static const String appTagline = 'MedtronicLabs · Frontline Health';
}

/// Shared, cross-screen labels reused in more than one feature.
abstract final class CommonStrings {
  CommonStrings._();

  static const String required = 'Required';
  static const String or = 'or';
  static const String retry = 'Retry';
  static const String usePassword = 'Use password';
  static const String unnamed = '(unnamed)';
}

/// Login screen + login-flow feedback.
abstract final class LoginStrings {
  LoginStrings._();

  static const String usernameLabel = 'Username';
  static const String passwordLabel = 'Password';
  static const String signIn = 'Sign in';
  static const String loginFailed = 'Login failed';
  static const String useDeviceUnlock = 'Use device unlock';
  static const String fromLockBanner =
      'Biometric cancelled — sign in with password.';
}

/// Lock / unlock screen + mid-session lock barrier.
abstract final class LockStrings {
  LockStrings._();

  static const String welcomeBack = 'Welcome back';
  static const String verifyToAccess =
      'Verify your identity to access your ward dashboard.';
  static const String biometricCancelled = 'Biometric cancelled';
  static const String unlockWithPhonePasswordOrBiometrics = 'Unlock with Phone password or biometrics';
  static const String profileLoading = 'Profile loading…';

  // Profile detail row labels.
  static const String skIdLabel = 'SK ID';
  static const String upazilaLabel = 'Upazila';
  static const String nidLabel = 'NID';
  static const String wardLabel = 'Ward';
  static const String households = 'households';

  static String welcomeBackNamed(String name) => 'Welcome back, $name';
}

/// Android `BiometricPrompt` copy + biometric unlock messages.
abstract final class BiometricStrings {
  BiometricStrings._();

  static const String promptTitle = AppStrings.appName;
  static const String promptHint = 'Verify your identity';
  static const String cancelButton = CommonStrings.usePassword;
}

/// Auth/session error messages surfaced to the user.
abstract final class AuthStrings {
  AuthStrings._();

  static const String savedSessionExpired =
      'Saved session expired — sign in again';
  static const String sessionExpired = 'Session expired';
}

/// Dashboard screen: greeting, stat cards, biometric-offer dialog, menu.
abstract final class DashboardStrings {
  DashboardStrings._();

  // Greeting parts.
  static const String goodMorning = 'Good Morning';
  static const String goodAfternoon = 'Good Afternoon';
  static const String goodEvening = 'Good Evening';
  static const String communityAtAGlance = 'Your community at a glance';
  static const String refreshTooltip = 'Refresh';

  // Stat cards.
  static const String totalPatients = 'Total\nPatients';
  static const String totalHouseholds = 'Total\nHouseholds';
  static const String highRiskPatients = 'High-Risk\nPatients';
  static const String soonBadge = 'SOON';
  static const String lookUpPatients =
      'Use the search bar above to look up patients';
  static const String lookUpHouseholds =
      'Use the search bar above to look up households';
  static const String aiTriageComingSoon =
      'AI triage coming soon — not wired yet';

  // Biometric-offer dialog.
  static const String useDeviceUnlockTitle = 'Use device unlock?';
  static const String biometricOfferSupported =
      'Sign in next time with your fingerprint, face, or device PIN — no password needed.';
  static const String biometricOfferUnsupported =
      'Sign in next time with your fingerprint, face, or device PIN. You may need to set up a screen lock in Android Settings first.';
  static const String notNow = 'Not now';
  static const String enable = 'Enable';
  static const String setUpScreenLock =
      'Set up a screen lock (PIN, pattern, or fingerprint) in Android Settings, then try again.';
  static const String deviceUnlockEnabled = 'Device unlock enabled';
  static const String deviceUnlockDisabled = 'Device unlock disabled';

  // Overflow menu.
  static const String enableDeviceUnlock = 'Enable device unlock';
  static const String disableDeviceUnlock = 'Disable device unlock';
  static const String signOut = 'Sign out';

  static String couldNotEnable(Object error) => 'Could not enable: $error';

  /// `Good Morning, Asha` style greeting.
  static String greetingNamed(String part, String name) => '$part, $name';

  // Last-refreshed relative-time labels.
  static const String updatedJustNow = 'updated just now';
  static String updatedSecondsAgo(int s) => 'updated ${s}s ago';
  static String updatedMinutesAgo(int m) => 'updated ${m}m ago';
  static String updatedHoursAgo(int h) => 'updated ${h}h ago';
}

/// Global search bar, scopes, result sections, and detail snackbars.
abstract final class SearchStrings {
  SearchStrings._();

  static const String barHint = 'Search patients or households';
  static const String scopeAll = 'All';
  static const String scopePatients = 'Patients';
  static const String scopeHouseholds = 'Households';
  static const String searchFailed = 'Search failed — try again.';
  static const String emptyPrompt =
      'Type a name, phone, NID, or household number';
  static const String noMatches = 'No matches.';
  static const String noPatientMatches = 'No patient matches.';
  static const String noHouseholdMatches = 'No household matches.';
  static const String resultsCapped = 'Result list capped — refine your query';
  static const String patientDetailNotImplemented =
      'Patient detail not implemented';
  static const String householdDetailNotImplemented =
      'Household detail not implemented';

  static String scanningHouseholds(int loaded, int cap) =>
      'Scanning households $loaded/$cap…';
  static String age(Object age) => 'Age $age';
  static String nid(Object nid) => 'NID $nid';
  static String householdNo(Object no) => 'No $no';
  static String memberCount(Object count) => '$count members';
}

/// App-specific fallback PIN: setup (create + confirm), unlock, and management.
/// Length-aware copy so the same strings serve a 4- or 6-digit PIN.
abstract final class PinStrings {
  PinStrings._();

  static const String confirmTitle = 'Confirm your PIN';
  static const String createSubtitle =
      'Use this PIN when fingerprint is unavailable.';
  static const String mismatch = 'PINs do not match — try again';
  static const String wrong = 'Incorrect PIN';
  static const String tooManyAttempts =
      'Too many attempts — sign in with password';
  static const String enabledSnack = 'PIN enabled';
  static const String disabledSnack = 'PIN disabled';
  static const String enablePin = 'Set up PIN';
  static const String disablePin = 'Remove PIN';
  static const String deleteKey = 'Delete';

  static String createTitle(int len) => 'Create a $len-digit PIN';
  static String enterTitle(int len) => 'Enter your $len-digit PIN';
  static String usePin(int len) => 'Use $len-digit PIN';
  static String attemptsRemaining(int n) => '$n attempts remaining';
}
