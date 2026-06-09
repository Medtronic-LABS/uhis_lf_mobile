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

import '../models/dashboard_tier.dart';

/// App-wide identity strings.
abstract final class AppStrings {
  AppStrings._();

  static const String appName = 'UHIS Next';
  static const String appTagline = 'MedtronicLabs · Frontline Health';
  static const String poweredBy = 'Powered by Medtronic Labs';
}

/// Shared, cross-screen labels reused in more than one feature.
abstract final class CommonStrings {
  CommonStrings._();

  static const String required = 'Required';
  static const String or = 'or';
  static const String retry = 'Retry';
  static const String usePassword = 'Use password';
  static const String unnamed = '(unnamed)';
  static const String remove = 'Remove';
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
  static const String unlockWithBiometrics = 'Unlock with device';
  /// @deprecated Use [unlockWithBiometrics] instead. Kept for migration.
  static const String unlockWithPhonePasswordOrBiometrics = unlockWithBiometrics;
  static const String profileLoading = 'Profile loading…';
  static const String offlinePasswordDisabled =
      'You are offline. Connect to the internet to sign in with password.';

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
  static const String communityAtAGlance = 'Serving your community';
  static const String refreshTooltip = 'Refresh';

  // Stat cards.
  static const String totalMembers = 'Total\nMembers';
  static const String totalHouseholds = 'Total\nHouseholds';
  static const String highRiskPatients = 'High-Risk\nPatients';
  static const String soonBadge = 'SOON';
  static const String lookUpMembers =
      'Use the search bar above to look up members';
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

  // Confirmation dialogs.
  static const String confirmDisableDeviceUnlock = 'Disable device unlock?';
  static const String confirmDisableDeviceUnlockBody =
      'You will need to use your password or PIN to sign in next time.';
  static const String confirmSignOut = 'Sign out?';
  static const String confirmSignOutBody =
      'You will need to sign in again with your password.';
  static const String cancel = 'Cancel';
  static const String disable = 'Disable';

  static String couldNotEnable(Object error) => 'Could not enable: $error';

  /// `Good Morning, Asha` style greeting.
  static String greetingNamed(String part, String name) => '$part, $name';

  // Last-refreshed relative-time labels.
  static const String updatedJustNow = 'updated just now';
  static String updatedSecondsAgo(int s) => 'updated ${s}s ago';
  static String updatedMinutesAgo(int m) => 'updated ${m}m ago';
  static String updatedHoursAgo(int h) => 'updated ${h}h ago';
}

/// Settings menu strings.
abstract final class SettingsStrings {
  SettingsStrings._();

  static const String darkMode = 'Dark Mode';
  static const String lightMode = 'Light Mode';
  static const String appearance = 'Appearance';
}

/// Global search bar, scopes, result sections, and detail snackbars.
abstract final class SearchStrings {
  SearchStrings._();

  static const String barHint = 'Search by name, phone, NID, household number or name';
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

  // Confirmation dialog.
  static const String confirmRemovePin = 'Remove PIN?';
  static const String confirmRemovePinBody =
      'You will need to use your password or biometrics to sign in next time.';
  static const String deleteKey = 'Delete';

  static String createTitle(int len) => 'Create a $len-digit PIN';
  static String enterTitle(int len) => 'Enter your $len-digit PIN';
  static String usePin(int len) => 'Use $len-digit PIN';
  static String attemptsRemaining(int n) => '$n attempts remaining';
}

/// First-login data sync: the guided "downloading your ward" gate and the
/// dashboard data-freshness badge.
abstract final class SyncStrings {
  SyncStrings._();

  static const String title = 'Setting up your ward';
  static const String subtitle =
      'Downloading your households and patients so you can work offline.';

  // Per-entity labels used in progress lines and the data-as-of badge.
  static const String households = 'households';
  static const String members = 'members';
  static const String patients = 'patients';

  static const String done = 'Ready to go';
  static const String syncFailed =
      'We couldn\'t finish downloading your data.';
  static const String continueOffline = 'Continue with what we have';
  static const String retry = CommonStrings.retry;

  static const String refreshing = 'Updating your data…';
  static const String upToDate = 'Data up to date';

  /// `Downloading households… 120 of 340`.
  static String progressNamed(String entity, int done, int total) =>
      total > 0
          ? 'Downloading $entity… $done of $total'
          : 'Downloading $entity… $done';

  /// `Households 340 · Patients 512` style summary line on completion.
  static String entityCount(String entity, int count) => '$entity $count';

  /// Relative-time data-freshness badge, e.g. `Data as of 2 days ago`.
  static String dataAsOf(String relative) => 'Data as of $relative';
  static const String dataAsOfJustNow = 'Data as of just now';
  static String dataAsOfMinutes(int m) => 'Data as of ${m}m ago';
  static String dataAsOfHours(int h) => 'Data as of ${h}h ago';
  static String dataAsOfDays(int d) => 'Data as of ${d}d ago';

  // Dashboard preparation phase (after sync, before navigation)
  static const String almostReady = 'Almost ready';
  static const String preparingVisits = 'Preparing today\'s visits…';
  static const String preparingDashboard = 'Setting up your dashboard…';
}

/// First-login onboarding: security setup prompt.
abstract final class OnboardingStrings {
  OnboardingStrings._();

  static const String title = 'Secure Your Account';
  static const String subtitle =
      'Set up quick, secure access to UHIS Next using your device\'s biometrics and a backup PIN.';

  static const String biometricFeatureTitle = 'Device Unlock';
  static const String biometricFeatureDesc =
      'Use fingerprint, face, or device PIN for fast sign-in.';
  static const String biometricNotAvailable =
      'Set up a screen lock in Android Settings to enable this feature.';

  static const String pinFeatureDesc =
      'A backup option when biometrics are unavailable.';

  static const String setupButton = 'Set Up Security';
  static const String skipButton = 'Skip for Now';
  static const String pinRequiredNote =
      'Note: You can set up security options later from the settings menu.';

  static const String skipConfirmTitle = 'Skip Security Setup?';
  static const String skipConfirmBody =
      'Without biometric or PIN authentication, you will need to enter your password each time you open the app. You can set these up later from settings.';
  static const String cancelButton = 'Cancel';
  static const String skipAnywayButton = 'Skip Anyway';

  static const String notAvailable = 'Not available';
  static const String biometricSetupFailed =
      'Could not enable device unlock. You can enable it later from the menu.';

  static String pinFeatureTitle(int len) => '$len-Digit Backup PIN';
}

/// Household / member list screens.
abstract final class HouseholdListStrings {
  HouseholdListStrings._();

  static const String allHouseholds = 'All Households';
  static const String allMembers = 'All Members';
  static const String loadError = 'Could not load data';
  static const String noHouseholds = 'No households found';
  static const String noMembers = 'No members found';
  static const String unnamedHousehold = '(Unnamed household)';
  static const String unnamedMember = '(Unnamed)';

  // Filter toggle labels
  static const String myPatients = 'My Patients';
  static const String allMembersFilter = 'All Members';
  static String myPatientsCount(int n) => 'My Patients ($n)';
  static String allMembersCount(int n) => 'All Members ($n)';

  static String householdsCount(int n) => '$n households';
  static String membersCount(int n) => '$n members';
  static String totalMembersCount(int n) => '$n total members';
  static String acrossHouseholds(int n) => 'across $n households';
}

/// Household detail screen strings.
abstract final class HouseholdDetailStrings {
  HouseholdDetailStrings._();

  static const String unnamedHousehold = '(Unnamed household)';
  static const String unnamed = '(Unnamed)';
  static const String members = 'Members';
  static const String location = 'Location';
  static const String coordinates = 'Coordinates';
  static const String householdHead = 'Household Head';
  static const String householdMembers = 'Household Members';
  static const String noHeadInfo = 'Head information not available';
  static const String noMembers = 'No members found';
  static const String head = 'HEAD';
  static const String personalInfo = 'Personal Information';
  static const String age = 'Age';
  static const String gender = 'Gender';
  static const String phone = 'Phone';
  static const String notAvailable = 'Not available';
  static const String householdInfo = 'Household Information';
  static const String householdName = 'Household';
  static const String householdNumber = 'Household No.';
  static const String totalMembers = 'Total Members';
  static const String viewHealthDetails = 'View Health Details';
  static const String pregnant = 'PREGNANT';
  static const String patientId = 'Patient ID';
  static const String showLess = 'Show less';
  static String showMore(int count) => 'Show $count more members';

  static String memberDataNotLoaded(int count) =>
      'This household has $count members.\nDetailed member information will be available once data is synced.';
}

/// AI Worklist (Screen 2): chip filter labels, programme tags, urgent banner,
/// last-synced strip, and the empty/error states. All literal copy for the
/// worklist surface lives here — widgets never inline strings.
abstract final class WorklistStrings {
  WorklistStrings._();

  // Programme labels.
  static const String programmeImci = 'IMCI';
  static const String programmeAnc = 'ANC';
  static const String programmePnc = 'PNC';
  static const String programmeNcd = 'NCD';
  static const String programmeTb = 'TB';
  static const String programmeUnknown = 'General';

  // Chip filters.
  static const String filterAll = 'All';
  static const String filterImci = 'IMCI';
  static const String filterAnc = 'ANC';
  static const String filterNcd = 'NCD';
  static const String filterTb = 'TB';

  // Urgent banner.
  static const String urgentBadge = 'URGENT';
  static String urgentBannerFmt(String name) =>
      'Highest risk: $name — review first.';

  // Risk band labels (also serve as accessibility hints).
  static const String bandUrgent = 'Urgent';
  static const String bandHigh = 'High';
  static const String bandModerate = 'Moderate';
  static const String bandLow = 'Low';

  // Empty / error / sync strip.
  static const String emptyTitle = 'No patients on your worklist yet';
  static const String emptyBody =
      'Sync with the server when you have a connection to pull your patients.';
  static const String loadFailed = 'Could not load worklist';
  static const String syncNow = 'Sync now';
  static const String syncing = 'Syncing…';
  static const String syncedJustNow = 'Synced just now';
  static const String offlineSuffix = 'Offline';
  static String syncedMinutes(int m) => 'Synced ${m}m ago';
  static String syncedHours(int h) => 'Synced ${h}h ago';
  static String syncedDays(int d) => 'Synced ${d}d ago';
  static String syncFailed(String reason) => 'Sync failed: $reason';
  static String syncSummary(int patients) =>
      patients == 0 ? 'No new updates' : 'Updated $patients patient(s)';

  // Card affordances.
  static String ageFmt(int age) => 'Age $age';
  static const String noAge = 'Age —';
  static const String tapForDetails = 'Tap for details';
  static const String rationaleHeader = 'Why this score';

  // Rationale bottom sheet.
  static const String whyThisScore = 'Why this score?';
  static String riskScoreLabel(int score) => 'Risk score: $score';
  static const String riskDriversHeader = 'Risk drivers';
  static const String modelVersionLabel = 'Model version';
  static const String computedAtLabel = 'Computed';
  static const String humanReviewRequired = 'Human review required';
  static const String closeSheet = 'Close';
}

/// Patient Context Screen (stub) strings. Full design lives in a later spec.
abstract final class PatientContextStrings {
  PatientContextStrings._();

  static const String fallbackTitle = 'Patient';
  static const String loading = 'Loading patient…';
  static const String notFound = 'Patient not in local cache';
  static const String idLabel = 'Patient ID';
  static const String householdLabel = 'Household';
  static const String villageLabel = 'Village';
  static const String programmesLabel = 'Programmes';
  static const String riskLabel = 'Risk';
  static const String sectionRecentVisits = 'Recent visits';
  static const String sectionVitals = 'Vitals';
  static const String sectionAiSuggestions = 'AI suggestions';
  static const String sectionActions = 'Actions';
  static const String comingSoon = 'Coming in a future release';
  static const String refresh = 'Refresh from server';
  static const String refreshing = 'Refreshing…';
  static const String refreshDone = 'Patient refreshed';
  static const String refreshFailed = 'Refresh failed';

  // ── HTML detail composition ──────────────────────────────────────────────
  static const String backToWorklist = 'Back to worklist';
  static const String sayHelloFirst = ' Say hello first';
  static const String greetingBangla =
      'আপনাদের কেমন আছেন? রোগী কেমন আছে?';
  static const String greetingEnglish =
      'How is everyone? How is the patient today?';
  static String aiSummaryLead(String name) =>
      '$name has the following risk drivers worth addressing today.';
}


/// Copy for the Referral SLA dashboard, cards, banners, and notifications.
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §11.
abstract final class ReferralStrings {
  ReferralStrings._();

  // ── Dashboard ────────────────────────────────────────────────────────────
  static const String dashboardTitle = 'Referrals';
  static const String emptyTitle = 'No active referrals';
  static const String emptyBody =
      'Your SLA dashboard populates after you create a referral or sync from the facility.';
  static const String loadFailed = 'Could not load referrals';

  // ── Filter chips (priority bands) ────────────────────────────────────────
  static const String filterAll = 'All';
  static const String filterCritical = 'Critical';
  static const String filterHigh = 'High';
  static const String filterMedium = 'Medium';
  static const String filterLow = 'Low';

  // ── SLA tier labels ──────────────────────────────────────────────────────
  static const String tierEmergency = 'EMERGENCY';
  static const String tierUrgent = 'URGENT';
  static const String tierRoutine = 'ROUTINE';

  // ── SLA strip / data-age badge ───────────────────────────────────────────
  static String syncedAgo(String relative) => 'Synced $relative';
  static String breachesCount(int n) => '$n SLA breach${n == 1 ? "" : "es"}';
  static String escalationsCount(int n) =>
      '$n escalation${n == 1 ? "" : "s"} pending';

  // ── Critical banner ──────────────────────────────────────────────────────
  static String criticalBannerFmt(String patientName, String tier, String detail) =>
      'BREACHED: $patientName · $tier · $detail';

  // ── Timeline node labels ─────────────────────────────────────────────────
  static const String stepCreated = 'Created';
  static const String stepAcknowledged = 'Acked';
  static const String stepInTransit = 'Travel';
  static const String stepArrived = 'Arrived';
  static const String stepTreatmentStarted = 'Treated';
  static const String stepClosedRecovered = 'Recovered';
  static const String stepClosedDeceased = 'Deceased';
  static const String stepBreached = 'BREACH';
  static const String stepPaused = 'Paused';
  static const String stepRefused = 'Refused';
  static const String stepTargetUnreachable = 'Target unreachable';
  static const String stepDuplicate = 'Duplicate';
  static const String stepTransportDeclined = 'Transport declined';
  static const String stepDiverted = 'Diverted';

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
        return value != null ? '$value missed follow-up(s)' : 'Missed follow-up';
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
  static const String tapToSeeWhy = 'Tap to see why';
  static const String rationaleSheetTitle = 'Why is this referral prioritized?';
  static const String modelVersionLabel = 'Model version';
  static String agedFmt(String relative) => 'referred $relative ago';
  static String overdueFmt(String relative) => 'overdue by $relative';

  // ── Dashboard chip on home screen ────────────────────────────────────────
  static String dashboardChipCritical(int n) => '$n critical referrals';
  static String dashboardChipActive(int n) => '$n active referrals';

  // ── Notification copy (Bangla-ready: titles only here) ───────────────────
  static const String notifCriticalTitle = '🔴 SLA BREACHED';
  static const String notifWarningTitle = '🟠 Referral warning';
  static const String notifCompletionTitle = '🟢 Treatment completed';
  static String notifCriticalBody(String patient, String reason) =>
      '$patient — $reason';
  static String notifWarningBody(String patient, String reason) =>
      '$patient — $reason';
  static String notifCompletionBody(String patient) =>
      '$patient discharged successfully.';

  // ── Permission rationale (in-app card before OS prompt) ─────────────────
  static const String permissionRationaleTitle = 'Enable referral alerts';
  static const String permissionRationaleBody =
      'Get notified when a referral is delayed or breaches its SLA — even when the app is closed.';
  static const String permissionRationaleAction = 'Enable';
  static const String permissionRationaleDismiss = 'Not now';

  // ── Triage Card — Priority Badges ────────────────────────────────────────
  static const String badgeCritical = '🔴 CRITICAL';
  static const String badgeHigh = '🟠 HIGH';
  static const String badgeMedium = '🟡 MEDIUM';
  static const String badgeLow = '🟢 LOW';
  static const String badgeCompleted = '🟢 COMPLETED';

  // ── Triage Card — SLA Status Layer ───────────────────────────────────────
  static String slaBreached(String overdue) => 'SLA BREACHED +$overdue';
  static String slaWarning(String remaining) => 'SLA: $remaining left';
  static const String slaCompleted = 'Completed ✓';
  static const String slaOnTrack = 'On Track';

  // ── Triage Card — Referral Metadata ──────────────────────────────────────
  static const String metaReferred = 'Referred:';
  static const String metaCondition = 'Condition:';
  static const String metaFacility = 'Facility:';
  static const String metaProgramme = 'Programme:';
  static const String metaAssigned = 'Assigned:';
  static const String metaReferralId = 'Ref ID:';

  // ── Triage Card — Operational Status ─────────────────────────────────────
  static const String statusLabel = 'Status:';
  static const String statusNotArrived = 'Not arrived at facility';
  static const String statusCheckedIn = 'Checked in';
  static const String statusAwaitingReview = 'Awaiting review';
  static const String statusDischarged = 'Discharged';
  static const String statusInTreatment = 'In treatment';
  static String overdueStatus(String days) => '$days overdue';
  static String slaWasStatus(String days) => 'SLA was $days';
  static String waitingStatus(String duration) => '$duration waiting';
  static String followUpDue(String date) => 'Follow-up due $date';
  static const String prescriptionShared = 'Prescription shared';

  // ── Triage Card — Operational Status Hints ───────────────────────────────
  static const String hintNotCheckedIn = '📍 Not checked in';
  static const String hintTransportBarrier = '🚌 Possible transport barrier';
  static const String hintAtFacility = '🏥 At facility';
  static String hintQueueWait(String department, String duration) =>
      '⏳ $department queue $duration';
  static const String hintCareCompleted = '✅ Care completed';
  static String hintFollowUp(String duration) => '📋 Follow-up in $duration';

  // ── Triage Card — Timeline Progress ──────────────────────────────────────
  static const String timelineSKVisit = 'SK Visit';
  static const String timelineReferred = 'Referred';
  static const String timelineArrived = 'Arrived';
  static const String timelineOBReview = 'OB Review';
  static const String timelineTreated = 'Treated';
  static const String timelineDischarged = 'Discharged';
  static const String timelineWaiting = 'Waiting';

  // ── Triage Card — Action Layer ───────────────────────────────────────────
  static const String actionCallFamily = 'Call Family';
  static const String actionUpdateStatus = 'Update Status';
  static const String actionLocate = 'Locate';
  static const String actionEscalate = 'Escalate';
  static const String actionCallFacility = 'Call Facility';
  static const String actionUpdateQueue = 'Update Queue';
  static const String actionOpenReferral = 'Open Referral';
  static const String actionViewPrescription = 'View Prescription';
  static const String actionScheduleFollowUp = 'Schedule Follow-up';
  static const String actionSendReminder = 'Send Reminder';
  static const String actionCloseCase = 'Close Case';

  // ── Contact Sheet ────────────────────────────────────────────────────────
  static String contactSheetTitle(String name) => 'Contact $name';
  static const String contactCall = 'Call';
  static const String contactCallSubtitle = 'Open phone dialer';
  static const String contactWhatsApp = 'WhatsApp';
  static const String contactWhatsAppSubtitle = 'Send message via WhatsApp';
  static const String contactSms = 'SMS';
  static const String contactSmsSubtitle = 'Send text message';

  // ── Contact Messages ─────────────────────────────────────────────────────
  static String msgGreeting(String name) => 'Hello $name, ';
  static const String msgIntro = 'this is UHIS Health Worker. ';
  static String msgReferralFor(String diagnosis) =>
      'Regarding your referral for $diagnosis, ';
  static const String msgReferralGeneric = 'Regarding your health referral, ';
  static const String msgOverdue =
      'we noticed your appointment is overdue. Please contact us or visit the health facility as soon as possible. ';
  static const String msgNewReferral =
      'please ensure you visit the referred health facility at your earliest convenience. ';
  static const String msgInTreatment =
      'we are following up on your treatment progress. Please let us know if you need any assistance. ';
  static const String msgCompleted =
      'we hope you are recovering well. Please attend your follow-up appointment as scheduled. ';
  static const String msgGenericOutreach =
      'we are reaching out regarding your health care. ';
  static const String msgClosing =
      'Reply to this message or call us for any queries. Thank you.';

  // ── Error Messages ───────────────────────────────────────────────────────
  static const String errorNoPhone = 'No phone number available';
  static const String errorPhoneDialer = 'Could not open phone dialer';
  static const String errorWhatsApp = 'Could not open WhatsApp. Is it installed?';
  static const String errorSms = 'Could not open SMS app';
  static const String errorMaps = 'Could not open Google Maps';
  static String errorOpening(String type, String error) =>
      'Error opening $type: $error';

  // ── Location Sheet ───────────────────────────────────────────────────────
  static String locateSheetTitle(String name) => 'Locate $name';
  static const String locateOpenMaps = 'Open in Google Maps';
  static const String locateOpenMapsSubtitle = 'View location on map';
  static const String locateGetDirections = 'Get Directions';
  static const String locateGetDirectionsSubtitle = 'Navigate to patient';
}

/// AI Mission Dashboard strings (Screen 2 redesign).
/// Spec: AI Mission Dashboard — action page answering "Who needs me next?"
abstract final class MissionDashboardStrings {
  MissionDashboardStrings._();

  // ── HTML Dashboard composition ───────────────────────────────────────────
  static String aiSortedVisits(int n) => 'AI sorted your $n visits overnight';
  static const String visitsToday = 'Visits today';
  /// Stat subline built from the SK's actual worklist. Returns `'No villages'`
  /// when the queue is empty (cold start, before sync), `'1 village'` or
  /// `'N villages'` once data lands. Distance estimate dropped — no source
  /// data yet; bring it back when geo is wired.
  static String visitsTodaySubline(int villageCount) {
    if (villageCount <= 0) return 'No villages assigned';
    if (villageCount == 1) return '1 village';
    return '$villageCount villages';
  }
  static const String referralAlertsLabel = 'Referral alerts';
  static const String tapToFollowUp = 'Tap to follow up →';
  static const String referralCceComingSoon = 'CCE integration coming soon';
  static const String visitStartFailed =
      'Could not start visit. Try again from the patient screen.';
  static const String visitMissingPatient =
      'No patient record — open the case to begin.';
  static String houseNumber(String no) => 'House #$no';
  static String moreVisits(int n) =>
      n == 1 ? '+ 1 more visit today' : '+ $n more visits today';
  static String todaysVisits(String date) => "Today's visits · $date";
  static const String upcomingWorkHeader = 'Upcoming work — earliest first';
  static const String aiSortedBadge = 'AI sorted';
  static const String actionVisitNow = 'Visit now';
  static const String actionVisitToday = 'Visit today';
  static const String actionThisWeek = 'This week';
  static const String actionRoutine = 'Routine';

  // ── AI Daily Brief Card ──────────────────────────────────────────────────
  static const String aiBriefTitle = "Today's AI Brief";
  static const String visitsRecommended = 'Visits Recommended';
  static const String childDangerCases = 'Child Danger Cases';
  static const String slaBreachedReferrals = 'SLA Breached Referrals';
  static const String ancFollowUps = 'ANC Follow-ups';
  static const String highRiskDiabeticPatients = 'High-Risk Diabetic Patients';
  static const String expectedWorkload = 'Expected Workload';
  static const String priorityLevel = 'Priority Level';
  static const String whyQuestion = 'Why?';
  static const String riskFactorsIdentified = 'Risk Factors Identified';
  static String workloadHours(double hours) =>
      '${hours.toStringAsFixed(1)} Hours';

  // ── Mission Progress Card ────────────────────────────────────────────────
  static const String todaysProgress = "Today's Progress";
  static const String visitsCompleted = 'Visits Completed';
  static const String visitsRemaining = 'Visits Remaining';
  static const String estimatedTime = 'Estimated Time';
  static String progressFraction(int done, int total) => '$done / $total';
  static String progressPercent(int percent) => '$percent%';
  static String remainingVisits(int n) => '$n Visits Remaining';
  static String estimatedDuration(String duration) => 'Estimated Time: $duration';
  static String completionPrediction(String time) =>
      'At current pace, all visits can be completed by $time';

  // ── Critical Alert Banner ────────────────────────────────────────────────
  static const String criticalAlert = '🔴 Critical Alert';
  static const String emergencyAncAlert = '🔴 Emergency ANC Alert';
  static const String immediateFollowUpRequired = 'Immediate follow-up required.';
  static String childReferralOverdue(int days) =>
      '$days Child Referral${days == 1 ? '' : 's'} Overdue';
  static String highRiskPregnancyWaiting(String name, String duration) =>
      '$name: High-risk pregnancy waiting $duration for OB review.';

  // ── Mission Queue Card ───────────────────────────────────────────────────
  static String priorityRank(int rank) => 'Priority #$rank';
  static String daysOverdue(int days) => '$days Days Overdue';
  static const String aiInsight = 'AI Insight';
  static const String aiPrioritisedBecause = 'AI Prioritised because:';
  static const String reason = 'Reason';

  // ── AI Insight Reasons (human-readable) ──────────────────────────────────
  static const String insightPatientNeverArrived =
      'Patient never arrived at facility.';
  static const String insightPossibleTransportBarrier =
      'Possible transport barrier.';
  static const String insightReferralOverdue = 'Referral overdue.';
  static const String insightChildUnder5 = 'Child under 5.';
  static const String insightHighRiskPregnancy = 'High-risk pregnancy.';
  static const String insightNoFacilityArrival = 'No facility arrival.';
  static const String insightMissedFollowUp = 'Missed follow-up.';
  static const String insightSlaBreached = 'SLA breached.';
  static const String insightEmergencyDiagnosis = 'Emergency diagnosis.';
  static const String insightDiabetesMissedFollowUp =
      'Diabetes patient missed follow-up.';

  // ── Action Buttons ───────────────────────────────────────────────────────
  static const String callFamily = 'Call Family';
  static const String locate = 'Locate';
  static const String openCase = 'Open Case';
  static const String callFacility = 'Call Facility';
  static const String openReferral = 'Open Referral';
  static const String scheduleVisit = 'Schedule Visit';
  static const String visitHousehold = 'Visit Household';
  static const String startRoute = 'Start Route';
  static const String continueTodaysWork = "Continue Today's Work";

  // ── Referral Operations Widget ───────────────────────────────────────────
  static const String referralStatus = 'Referral Status';
  static const String active = 'Active';
  static const String breached = 'Breached';
  static const String awaitingReview = 'Awaiting Review';
  static const String completed = 'Completed';
  static String referralCount(int count, String status) => '$count $status';

  // ── Follow-Ups Due Widget ────────────────────────────────────────────────
  static const String followUpsDue = 'Follow-Ups Due';
  static const String discharged = 'Discharged';
  static const String followUpDue = 'Follow-up Due';
  static const String tomorrow = 'Tomorrow';
  static const String today = 'Today';
  static String daysAway(int days) =>
      days == 0 ? today : (days == 1 ? tomorrow : 'In $days days');

  // ── Household Opportunities Widget ───────────────────────────────────────
  static const String householdOpportunities = 'Household Opportunities';
  static const String potentialServices = 'Potential Services';
  static const String mother = 'Mother';
  static const String child = 'Child';
  static const String father = 'Father';
  static const String ancFollowUpDue = 'ANC Follow-up Due';
  static const String epiVaccineDue = 'EPI Vaccine Due';
  static const String bpReviewPending = 'BP Review Pending';
  static String householdNumber(int number) => 'Household #$number';
  static String potentialServicesCount(int count) =>
      'Potential Services: $count';

  // ── Route Optimization Widget ────────────────────────────────────────────
  static const String optimalRoute = 'Optimal Route';
  static const String distance = 'Distance';
  static const String estimatedTravelTime = 'Estimated Time';
  static String distanceKm(double km) => '${km.toStringAsFixed(1)} km';
  static String travelDuration(String duration) => duration;

  // ── Learning Recommendations Widget ──────────────────────────────────────
  static const String todaysLearning = "Today's Learning";
  static String learningDuration(int minutes) => '$minutes Minutes';
  static const String triggeredByTodaysCases = 'Triggered by today\'s cases';

  // ── Floating AI Assistant ────────────────────────────────────────────────
  static const String aiAssistant = 'AI Assistant';
  static const String askAiAssistant = 'Ask AI Assistant';
  static const String aiAssistantHint =
      'Ask about patient care, guidelines, or procedures…';

  // ── Priority Levels ──────────────────────────────────────────────────────
  static const String priorityCritical = 'Critical';
  static const String priorityHigh = 'High';
  static const String priorityMedium = 'Medium';
  static const String priorityLow = 'Low';

  // ── Programme Badges ─────────────────────────────────────────────────────
  static const String badgeAnc = 'ANC';
  static const String badgeImci = 'IMCI';
  static const String badgeNcd = 'NCD';
  static const String badgeTb = 'TB';
  static const String badgeEpi = 'EPI';
  static const String badgeReferral = 'Referral';

  // ── Empty States ─────────────────────────────────────────────────────────
  static const String noMissionsToday = 'No missions for today';
  static const String allCaughtUp = 'All caught up! Great work.';
  static const String noCriticalAlerts = 'No critical alerts';
  static const String noFollowUpsDue = 'No follow-ups due';
  static const String noHouseholdOpportunities =
      'No household opportunities identified';

  // ── 5-Tier Dashboard Model ───────────────────────────────────────────────
  // Single source of UI copy for tier headers, CTAs, and driver rationales.
  // Widgets must call these helpers instead of inlining tier labels.

  static const String tierLabelCritical = 'Critical';
  static const String tierLabelOverdue = 'Overdue';
  static const String tierLabelDueToday = 'Due today';
  static const String tierLabelThisWeek = 'This week';
  static const String tierLabelUpcoming = 'Upcoming';

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
  static const String ctaVisitNow = 'Visit now';
  static const String ctaVisitToday = 'Visit today';
  static const String ctaPlanVisit = 'Plan visit';
  static const String ctaSchedule = 'Schedule';

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

  /// Human-readable rationale for a driver tag on `MissionQueueItem.drivers`.
  /// Unknown tags fall back to a generic phrase so the rationale sheet never
  /// shows a raw tag identifier to the SK.
  static String driverLabel(String tag) {
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
  static const String skAsksBangla =
      'রোগী কেমন আছে? কতদিন হলো অসুস্থ?';
  static const String skAsksEnglish =
      'How is the patient? How many days unwell?';

  static const String durationQuestion = 'কতদিন হলো? · How many days sick?';
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

  static const String reviewTitle = 'AI Draft Note';
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
}

/// AI Scribe inline banner strings (replaces FAB labels for the new single-form layout).
abstract final class ScribeBannerStrings {
  ScribeBannerStrings._();

  static const String idle = 'AI Scribe — Tap to start listening';
  static const String idleSub = 'SK talks to family — AI fills the form';
  static const String recording = 'Recording…';
  static const String uploading = 'Uploading…';
  static const String processing = 'AI processing note…';
  static const String ready = 'AI note ready — tap to review';
  static const String error = 'Upload failed — tap to retry';
}

/// Bottom-nav tab labels + the Map placeholder copy.
abstract final class BottomNavStrings {
  BottomNavStrings._();

  static const String home = 'Home';
  static const String patients = 'Patients';
  static const String tasks = 'Tasks';
  static const String map = 'Map';

  // Map placeholder screen
  static const String mapTitle = 'Map';
  static const String mapPlaceholderHeading = 'Map View';
  static const String mapPlaceholderSubheading = 'Coming soon';
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
  static const String symptomConvulsions = 'Convulsions / Fits';
  static const String symptomUnconscious = 'Unconscious / Unresponsive';
  static const String symptomLethargy = 'Unusually sleepy / Difficult to wake';
  static const String symptomNotEating = 'Not eating / drinking';
  static const String symptomChestIndrawing = 'Chest in-drawing';
  static const String symptomStridor = 'Stridor (noisy breathing)';
  static const String symptomVaginalBleeding = 'Vaginal bleeding';
  static const String symptomWaterBreak = 'Water break / Leaking';
  static const String symptomReducedFetalMovement = 'Reduced fetal movement';
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
  static const String symptomSwellingFaceHands = 'Swelling (face / hands)';
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

  /// Returns the localized label for a symptom code.
  static String symptomLabel(String code) {
    switch (code) {
      // Danger signs
      case 'convulsions': return symptomConvulsions;
      case 'unconscious': return symptomUnconscious;
      case 'lethargy': return symptomLethargy;
      case 'not_eating': return symptomNotEating;
      case 'chest_indrawing': return symptomChestIndrawing;
      case 'stridor': return symptomStridor;
      case 'vaginal_bleeding': return symptomVaginalBleeding;
      case 'water_break': return symptomWaterBreak;
      case 'reduced_fetal_movement': return symptomReducedFetalMovement;
      case 'chest_pain': return symptomChestPain;
      case 'hemoptysis': return symptomHemoptysis;
      // Fever & respiratory
      case 'fever': return symptomFever;
      case 'cough': return symptomCough;
      case 'cough_over_2_weeks': return symptomCoughOver2Weeks;
      case 'difficulty_breathing': return symptomDifficultyBreathing;
      case 'fast_breathing': return symptomFastBreathing;
      case 'shortness_breath': return symptomShortnessBreath;
      // GI & nutrition
      case 'diarrhea': return symptomDiarrhea;
      case 'bloody_diarrhea': return symptomBloodyDiarrhea;
      case 'vomiting': return symptomVomiting;
      case 'loss_appetite': return symptomLossAppetite;
      case 'muac_red': return symptomMuacRed;
      case 'visible_wasting': return symptomVisibleWasting;
      case 'edema_both_feet': return symptomEdemaBothFeet;
      case 'weight_loss': return symptomWeightLoss;
      // Maternal
      case 'pregnant': return symptomPregnant;
      case 'headache_severe': return symptomHeadacheSevere;
      case 'blurred_vision': return symptomBlurredVision;
      case 'abdominal_pain': return symptomAbdominalPain;
      case 'swelling_face_hands': return symptomSwellingFaceHands;
      case 'high_bp_known': return symptomHighBpKnown;
      case 'labor_signs': return symptomLaborSigns;
      // NCD / metabolic
      case 'dizziness': return symptomDizziness;
      case 'numbness': return symptomNumbness;
      case 'polyuria': return symptomPolyuria;
      case 'polydipsia': return symptomPolydipsia;
      case 'foot_pain': return symptomFootPain;
      case 'foot_wound': return symptomFootWound;
      // TB indicators
      case 'night_sweats': return symptomNightSweats;
      case 'fatigue': return symptomFatigue;
      case 'tb_contact': return symptomTbContact;
      // Mental health
      case 'feeling_sad': return symptomFeelingSad;
      case 'anxiety': return symptomAnxiety;
      case 'sleep_difficulty': return symptomSleepDifficulty;
      // Child health
      case 'ear_problem': return symptomEarProblem;
      case 'skin_rash': return symptomSkinRash;
      case 'eye_discharge': return symptomEyeDischarge;
      case 'umbilicus_red': return symptomUmbilicusRed;
      case 'jaundice': return symptomJaundice;
      default: return code;
    }
  }
}

/// Pathway review sheet + activation rationales.
/// Phase 1: Symptom-driven unified assessment flow.
abstract final class PathwayStrings {
  PathwayStrings._();

  // ── Review sheet ─────────────────────────────────────────────────────────
  static const String reviewTitle = "Today's Assessment Plan";
  static const String reviewSubtitle = 'Based on symptoms and patient history';
  static const String startAssessment = 'Start Assessment';
  static const String addProgramme = '+ Add section manually';
  static const String confirmRemoveTitle = 'Skip this assessment?';
  static String confirmRemoveBody(String programmeName, String trigger) =>
      '$programmeName was recommended because: $trigger.\n\n'
      'Skipping will create a follow-up task so it surfaces next visit.';
  static const String keepButton = 'Keep';
  static const String skipAnywayButton = 'Skip anyway';

  // ── Pathway rationales (localized explainability) ────────────────────────
  static const String pathwayNeonateRationale = 'Neonate assessment (age < 2 months)';
  static const String pathwayIccmRationale = 'Child illness assessment (WHO IMCI)';
  static const String pathwayAncRationale = 'Antenatal care — pregnancy confirmed';
  static const String pathwayPncRationale = 'Postnatal care — within 6 weeks of delivery';
  static const String pathwayTbScreenRationale = 'TB screening — WHO 4-symptom screen';
  static const String pathwayNcdHtnRationale = 'NCD — hypertension review';
  static const String pathwayNcdDmRationale = 'NCD — diabetes symptoms';
  static const String pathwayNutritionRationale = 'Nutrition assessment — malnutrition indicators';
  static const String pathwayEpiRationale = 'Immunization — vaccines overdue';
  static const String pathwayManualRationale = 'Manually added';

  // ── Programme display names ──────────────────────────────────────────────
  static const String programmeImci = 'ICCM / Child Illness';
  static const String programmeAnc = 'ANC';
  static const String programmePnc = 'PNC';
  static const String programmeNcd = 'NCD';
  static const String programmeTb = 'TB Screening';
  static const String programmeEpi = 'EPI / Immunization';
  static const String programmeNeonate = 'Neonate Assessment';
  static const String programmeNutrition = 'Nutrition Assessment';
  static const String programmeUnknown = 'Assessment';

  // ── Progress indicator ───────────────────────────────────────────────────
  static String assessmentProgress(int current, int total, String programme) =>
      'Assessment $current of $total — $programme';

  /// Returns the localized rationale for a pathway rationale key.
  static String rationale(String key) {
    switch (key) {
      case 'pathwayNeonateRationale': return pathwayNeonateRationale;
      case 'pathwayIccmRationale': return pathwayIccmRationale;
      case 'pathwayAncRationale': return pathwayAncRationale;
      case 'pathwayPncRationale': return pathwayPncRationale;
      case 'pathwayTbScreenRationale': return pathwayTbScreenRationale;
      case 'pathwayNcdHtnRationale': return pathwayNcdHtnRationale;
      case 'pathwayNcdDmRationale': return pathwayNcdDmRationale;
      case 'pathwayNutritionRationale': return pathwayNutritionRationale;
      case 'pathwayEpiRationale': return pathwayEpiRationale;
      case 'pathwayManualRationale': return pathwayManualRationale;
      default: return key;
    }
  }
}
