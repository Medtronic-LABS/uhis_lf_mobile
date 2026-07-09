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
  static const String unlockWithPhonePasswordOrBiometrics =
      unlockWithBiometrics;
  static const String profileLoading = 'Profile loading…';
  static const String offlinePasswordDisabled =
      'You are offline. Connect to the internet to sign in with password.';

  // Connectivity status row (bottom of the lock screen).
  static const String onlineStatus = 'Online';
  static const String offlineLoginAvailable = 'Offline login available';

  // Profile detail row labels.
  static const String skIdLabel = 'SK ID';
  static const String upazilaLabel = 'UPAZILA';
  static const String nidLabel = 'NID';
  static const String wardLabel = 'Ward';
  static const String households = 'households';

  static String welcomeBackNamed(String name) => 'Welcome back, $name';

  static const String signInToStartYourDay = 'Sign in to start your day';
  static const String shasthyaKormi = 'SHASTHYA KORMI';
  static const String verifyFingerprint = 'Verify fingerprint';
  static const String tapToPlaceFinger = 'Touch sensor to begin';
  static const String tapToPlaceFingerSubtitle =
      'Tap to place your finger and sign in';
  static const String aponSushashthya = 'Apon Sushashthya';
  static const String aponSushashthyaBn = 'আপন সুস্বাস্থ্য';
  static const String splashTagline =
      'AI-powered community health for every household in Bangladesh';
  static const String readingFingerprint = 'Reading fingerprint…';
  static const String fingerprintVerified = 'Verified!';
  static const String communityHealth = 'Community Health';
  static const String programName = 'Apon Sushashthya';
  static const String programSubtitle = 'আপন সুস্বাস্থ্য · Community Health';
  static String orUsePin(int len) => 'Use $len-digit PIN';
}

/// Android `BiometricPrompt` copy + biometric unlock messages.
abstract final class BiometricStrings {
  BiometricStrings._();

  static const String promptTitle = 'Fingerprint verification';
  static const String promptHint = 'Place your finger on the sensor';
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
  static const String systemMode = 'System Mode';
  static const String appearance = 'Appearance';
}

/// Real-Time ASR screen — live streaming transcription + live clinical
/// extraction against the ai-scribe-service, triggered from Settings.
/// Strings for Step 2 ambient listening / form-fill banner.
abstract final class Step2AsrStrings {
  Step2AsrStrings._();

  static const String bannerTitle = 'AI Form Fill';
  static const String bannerSubtitle =
      'Speak naturally — AI fills form fields as you talk.';
  static const String startListening = 'Start Listening';
  static const String stopListening = 'Stop';
  static const String connecting = 'Connecting…';
  static const String listening = 'Listening…';
  static const String stopping = 'Stopping…';
  static const String notListening = 'Tap to start ambient form-fill';
  static const String transcriptEmpty =
      'Speak — transcript will appear here.';
  static const String noFieldsYet = 'No fields extracted yet.';
  static const String extractNow = 'Fill Now';
  static const String extracting = 'Filling…';
  static const String notSupportedOnWeb =
      'Step 2 AI form-fill is not available in the web preview.';
  static const String micPermissionDenied =
      'Microphone permission is required.';
  static const String fieldsFilled = 'fields filled';
  static const String tapToEdit =
      'Review highlighted fields in the form below.';
  static const String unmappedLabel = 'Not matched:';

  static String filledCount(int n) => '$n $fieldsFilled';
}

abstract final class RealtimeAsrStrings {
  RealtimeAsrStrings._();

  static const String title = 'Real-Time ASR (Beta)';
  static const String subtitle =
      'Live transcript and detected symptoms while you talk. Not saved as a '
      'visit note — use AI Scribe during the visit for that.';
  static const String start = 'Start Listening';
  static const String stop = 'Stop';
  static const String connecting = 'Connecting…';
  static const String listening = 'Listening…';
  static const String stopping = 'Stopping…';
  static const String idle = 'Idle';
  static const String transcriptEmpty =
      'Tap Start Listening and speak — the live transcript appears here.';
  static const String extractNow = 'Extract Now';
  static const String extracting = 'Extracting…';
  static const String symptomsEmpty = 'No extraction yet.';
  static const String notSupportedOnWeb =
      'Real-time ASR is not available in the web preview — use the Android '
      'or iOS app.';
  static const String micPermissionDenied =
      'Microphone permission is required for real-time ASR.';
  static const String diagnosis = 'Diagnosis';
  static const String bloodPressure = 'Blood Pressure';
  static const String bloodGlucose = 'Blood Glucose';
  static const String clinicalNotes = 'Clinical Notes';
  static const String chiefComplaints = 'Chief Complaints';
  static const String comorbidities = 'Comorbidities';
  static const String complications = 'Complications';
}

/// Global search bar, scopes, result sections, and detail snackbars.
abstract final class SearchStrings {
  SearchStrings._();

  static const String barHint =
      'Search by name, phone, NID, household number or name';
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
  static const String scanNidTooltip = 'Scan NID card to find patient';
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
  static const String syncFailed = 'We couldn\'t finish downloading your data.';
  static const String continueOffline = 'Continue with what we have';
  static const String retry = CommonStrings.retry;

  static const String refreshing = 'Updating your data…';
  static const String upToDate = 'Data up to date';

  /// `Downloading households… 120 of 340`.
  static String progressNamed(String entity, int done, int total) => total > 0
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
  static const String noPatientsAssigned = 'No patients assigned to you';
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

  // Location / SS filter strings
  static const String filterTitle = 'Filter';
  static const String filterVillage = 'Village';
  static const String filterSubVillage = 'Sub-village';
  static const String filterSS = 'Shasthya Shebika (SS)';
  static const String filterAllVillages = 'All Villages';
  static const String filterAllSubVillages = 'All Sub-villages';
  static const String filterAllSS = 'All SS';
  static const String filterClearAll = 'Clear All';
  static const String filterApply = 'Apply';
  static String activeFilterCount(int n) =>
      '$n filter${n == 1 ? '' : 's'} active';
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
  static const String notAvailable = 'N/A';
  static const String householdInfo = 'Household Information';
  static const String householdName = 'Household';
  static const String householdNumber = 'Household No.';
  static const String totalMembers = 'Total Members';
  static const String viewHealthDetails = 'View Health Details';
  static const String pregnant = 'PREGNANT';
  static const String patientId = 'Patient ID';
  static const String showLess = 'Show less';
  static String showMore(int count) => 'Show $count more members';
  static const String village = 'Village';
  static const String ssName = 'Shasthya Shebika';
  static const String lastVisitDate = 'Last Visit';
  static const String recentService = 'Recent Service';
  static const String recentServiceDate = 'Service Date';
  static const String neverVisited = 'Never visited';
  static const String noSsAssigned = 'Not assigned';

  static String memberDataNotLoaded(int count) =>
      'This household has $count members.\nDetailed member information will be available once data is synced.';
}

/// AI Worklist (Screen 2): chip filter labels, programme tags, urgent banner,
/// last-synced strip, and the empty/error states. All literal copy for the
/// worklist surface lives here — widgets never inline strings.
abstract final class WorklistStrings {
  WorklistStrings._();

  // Programme labels — descriptive visit-type labels shown on patient cards.
  static const String programmeImci = 'Child Visit';
  static const String programmeAnc = 'ANC Visit';
  static const String programmePnc = 'PNC Visit';
  static const String programmeNcd = 'NCD Check';
  static const String programmeTb = 'TB Check';
  static const String programmeEpi = 'Vaccination';
  static const String programmeNutrition = 'Nutrition';
  static const String programmeFamilyPlanning = 'Family Planning';
  static const String programmeCataract = 'Cataract';
  static const String programmeEyeCare = 'Eye Care';
  static const String programmeUnknown = 'Scheduled Visit';
  static const String selectService = '📋  Select service';

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
  static const String urgencyNow = 'Now';
  static const String urgencyToday = 'Today';
  static const String urgencyThisWeek = 'This week';
  static const String urgencyRoutine = 'Routine';
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

  // ── Action buttons ───────────────────────────────────────────────────────
  static const String actionsTitle = 'Actions';
  static const String startVisit = 'Start Visit';
  static const String callHousehold = 'Call';
  static const String callComingSoon = 'Call household coming soon';

  // ── HTML detail composition ──────────────────────────────────────────────
  static const String backToWorklist = 'Back to worklist';
  static const String sayHelloFirst = ' Say hello first';
  static const String greetingBangla = 'আপনাদের কেমন আছেন? রোগী কেমন আছে?';
  static const String greetingEnglish =
      'How is everyone? How is the patient today?';
  static String aiSummaryLead(String name) =>
      '$name has the following risk drivers worth addressing today.';

  static const String allAssessmentsTitle = 'All assessments';
}

/// Copy for the patient profile card — collapsible demographic section
/// shown inside PatientContextScreen below the header.
abstract final class PatientProfileStrings {
  PatientProfileStrings._();

  static const String profileTitle = 'Patient Profile';
  static const String showMore = 'Show full profile';
  static const String hide = 'Hide profile';

  static const String sectionIdentity = 'Identity';
  static const String sectionLocation = 'Location';
  static const String sectionContact = 'Contact';
  static const String sectionCareTeam = 'Care Team';
  static const String sectionHousehold = 'Household Role';

  static const String labelNid = 'NID / BRN';
  static const String labelGender = 'Gender';
  static const String labelDob = 'Date of Birth';
  static const String labelIdType = 'ID Type';
  static const String labelMaritalStatus = 'Marital Status';
  static const String labelDisability = 'Disability';
  static const String labelVillage = 'Village';
  static const String labelPhone = 'Phone';
  static const String labelIsHouseholdHead = 'HH Head';
  static const String labelRelation = 'Relation to HH Head';
  static const String labelSk = 'Assigned SK';
  static const String labelGuardian = 'Guardian';
  static const String labelMother = 'Mother Ref';
  static const String labelGps = 'GPS';
  static const String labelIsPregnant = 'Pregnant';
  static const String yes = 'Yes';
  static const String no = 'No';
  static const String notAvailable = '—';
}

/// Copy for the Referral SLA dashboard, cards, banners, and notifications.
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §11.
abstract final class ReferralStrings {
  ReferralStrings._();

  // ── Create referral sheet ────────────────────────────────────────────────
  static const String createSheetTitle = 'Refer Patient';
  static const String createReasonLabel = 'Reason for referral';
  static const String createReasonHint = 'Select a reason';
  static const String createTierLabel = 'Urgency level';
  static const String createNotesLabel = 'Additional notes (optional)';
  static const String createNotesHint =
      'Enter any notes for the receiving facility';
  static const String createSubmit = 'Submit Referral';
  static const String createCancel = 'Cancel';
  static const String createSuccess = 'Referral created';
  static const String createFailed =
      'Failed to create referral — please try again';
  static const String createReasonRequired = 'Please select a reason';
  static const String tierEmergencyLabel = 'Emergency (6h SLA)';
  static const String tierUrgentLabel = 'Urgent (24h SLA)';
  static const String tierRoutineLabel = 'Routine (72h SLA)';
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
  static String criticalBannerFmt(
    String patientName,
    String tier,
    String detail,
  ) => 'BREACHED: $patientName · $tier · $detail';

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
  static const String errorWhatsApp =
      'Could not open WhatsApp. Is it installed?';
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

  static const String referralAlertsLabel = 'Referral alerts need follow-up';
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
  static const String filterByLocation = 'Village · SS · Area';
  static const String upcomingWorkHeader = 'Upcoming work — earliest first';
  static const String aiSortedBadge = '✦ AI sorted';
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
  static String estimatedDuration(String duration) =>
      'Estimated Time: $duration';
  static String completionPrediction(String time) =>
      'At current pace, all visits can be completed by $time';

  // ── Critical Alert Banner ────────────────────────────────────────────────
  static const String criticalAlert = '🔴 Critical Alert';
  static const String emergencyAncAlert = '🔴 Emergency ANC Alert';
  static const String immediateFollowUpRequired =
      'Immediate follow-up required.';
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

  // ── Household Enrollment CTA ─────────────────────────────────────────────
  static const String enrollHouseholdTitle = 'Enrol a new household';
  static const String enrollHouseholdSubtitle =
      'Register a family not yet in the programme';
  static const String enrollHouseholdAction = 'Enrol now';

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

  // ── Inline Village + Need filter ─────────────────────────────────────────
  static const String whichVillageVisiting = 'WHICH VILLAGE ARE YOU VISITING?';
  static const String allVillages = 'All villages';
  static const String filterByNeed = 'FILTER BY NEED';
  static const String filterByNeedOptional = 'optional';
  static const String needHighRisk = 'High-risk';
  static const String needAncMnch = 'ANC / MNCH';
  static const String needChildImmunisation = 'Child / Immunisation';
  static const String needNcd = 'NCD';
  static const String needEyeCare = 'Eye care';
  static const String needMissedFollowUp = 'Missed follow-up';
  static const String needPendingReferral = 'Pending referral';
  static const String needHomeVisit = 'Home visit';
  static const String needFacilityReferral = 'Facility referral';
  static const String clearNeedFilters = 'Clear';
  static const String filterByProgramme = 'Programme';
  static const String noNeedsInQueue = 'No priority needs in today\'s list';
  static const String noVisitsMatchFilters = 'No visits match these filters';
  static const String noVisitsMatchFiltersHint =
      'Try another village or clear the filters';
  static String completedVisitToast(String name) =>
      "$name's visit already done today ✓";

  // ── AI sorted info card tags ──────────────────────────────────────────────
  static const String aiSortedTagRisk = '✦Risk scoring';
  static const String aiSortedTagOverdue = '✦Overdue flags';
  static const String aiSortedTagCce = '✦CCE alerts';

  // ── "+ Enrol new" FAB ────────────────────────────────────────────────────
  static const String enrolNewCta = 'Enroll new';
  static const String enrolNewComingSoon =
      'QR enrolment flow coming soon. Use the Patients tab to view existing patients.';

  // ── Status pills (compact tier label shown in the card right-side pill) ───
  static String statusPillForTier(DashboardTier tier) {
    switch (tier) {
      case DashboardTier.critical:
        return 'Now';
      case DashboardTier.overdue:
        return 'Today';
      case DashboardTier.dueToday:
        return 'Today';
      case DashboardTier.thisWeek:
        return 'This week';
      case DashboardTier.upcoming:
        return 'Routine';
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
  static const String skAsksBangla = 'রোগী কেমন আছে? কতদিন হলো অসুস্থ?';
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
}

/// AI Scribe inline banner strings (replaces FAB labels for the new single-form layout).
abstract final class ScribeBannerStrings {
  ScribeBannerStrings._();

  static const String idle = 'AI Scribe';
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
abstract final class BottomNavStrings {
  BottomNavStrings._();

  static const String home = 'Home';
  static const String patients = 'Patients';
  static const String tasks = 'Tasks';
  static const String assistant = 'Assistant';

  // Assistant placeholder screen
  static const String assistantTitle = 'Assistant';
  static const String assistantPlaceholderHeading = 'AI Assistant';
  static const String assistantPlaceholderSubheading = 'Coming soon';

  static const String pressBackAgainToExit = 'Press back again to exit';
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
  static const String symptomLeakingFluidVagina = 'Leaking fluid from vagina';
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
  static const String nextButton = 'Next';
  static const String dismissOkButton = 'OK';

  // ── Extended field widget strings ───────────────────────────────────────────
  static const String selectDateHint = 'Select date';
  static const String bpSystolicHint = 'SYS';
  static const String bpDiastolicHint = 'DIA';
  static const String bpUnit = 'mmHg';
  static const String bpValidationError = 'Enter a valid reading';
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
  static const String programmeAnc = 'ANC';
  static const String programmePnc = 'PNC';
  static const String programmeNcd = 'NCD';
  static const String programmeTb = 'TB Screening';
  static const String programmeEpi = 'EPI / Immunization';
  static const String programmeNeonate = 'Neonate Assessment';
  static const String programmeNutrition = 'Nutrition Assessment';
  static const String programmeFamilyPlanning = 'Family Planning';
  static const String programmeCataract = 'Cataract / Eye Disease';
  static const String programmeEyeCare = 'Eye Care';
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
  static const String ctaWithPathways =
      'AI is checking — see what to do next →';
  static const String ctaRoutine = 'Continue (routine visit)';

  // ── Other symptoms free-text ─────────────────────────────────────────────
  static const String otherSymptomsLabel = 'Other symptoms / Notes';
  static const String otherSymptomsHint = 'Type symptom manually…';
  static const String otherSymptomsAddFromList = 'Add from list';

  // ── AI-driven symptom list (replaces the hardcoded cluster grid) ─────────
  static const String detectedSymptomsTitle = 'AI-Detected Symptoms';
  static const String detectedSymptomsSubtitleFilled =
      'Review each symptom. Tap × to remove anything incorrect, or add what is missing.';
  static const String addSymptomSearchHint = 'Search or type symptom…';
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
  static const String whatsAppNotInstalled =
      'WhatsApp is not installed on this device.';
  static const String smsNotAvailable =
      'SMS is not available on this device.';

  static const String acceptProposal = 'Accept & continue';
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
  static const String subtitle =
      'Clinical training modules for frontline health workers';
  static const String comingSoon = 'Coming soon';
  static const String certificatesTitle = 'Certificates';
  static const String certificatesSubtitle =
      'Complete modules to earn programme certificates';
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
  static const Map<String, String> additionalDetailLabels = {
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
