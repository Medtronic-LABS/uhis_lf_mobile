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
}
