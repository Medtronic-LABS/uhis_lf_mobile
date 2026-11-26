/// Google Analytics event, parameter and screen names (LEAP-152).
///
/// Every name sent to GA lives here so the tracking plan and the code can't
/// drift apart. GA4 rules: snake_case, event names ≤ 40 chars, ≤ 25 params
/// per event, string values ≤ 100 chars.
///
/// PRIVACY: values are fixed choices, counts, durations or true/false only.
/// Never pass patient/household ids, names, phone/NID numbers, clinical values
/// or any free text (search queries, messages, transcripts).
library;

/// Event names.
abstract final class AnalyticsEvent {
  static const tabSelected = 'tab_selected';
  static const login = 'login';
  static const pinUnlock = 'pin_unlock';
  static const logout = 'logout';
  static const sessionExpired = 'session_expired';
  static const syncStarted = 'sync_started';
  static const syncCompleted = 'sync_completed';
  static const languageChanged = 'language_changed';
  static const appUpdatePrompt = 'app_update_prompt';
  static const appUpdateAction = 'app_update_action';
  static const permissionResult = 'permission_result';

  // Home (dashboard) interactions
  static const filterApplied = 'filter_applied';
  static const addHouseholdTapped = 'add_household_tapped';

  // Registration (households + members)
  /// One per NID scanner session, sent when the scanner closes.
  static const nidScanResult = 'nid_scan_result';
  /// What the SK chose in the home NID sheet (FAB / search QR).
  static const enrollmentPathChosen = 'enrollment_path_chosen';
  static const householdCreated = 'household_created';
  static const memberAdded = 'member_added';

  // Micro coaching. Only the launch is a Flutter event; everything inside
  // coaching is sent by the coaching SDK itself (coaching_* events).
  static const coachingOpened = 'coaching_opened';

  // Shukhee teleconsult (Call doctor), after `call_doctor_tapped` /
  // `teleconsult_consent`. visit_id = the parent visit's GA id.
  static const teleconsultSpecialitiesLoaded = 'teleconsult_specialities_loaded';
  static const teleconsultBookingSubmitted = 'teleconsult_booking_submitted';
  static const teleconsultBookingResult = 'teleconsult_booking_result';
  static const teleconsultDoctorAssigned = 'teleconsult_doctor_assigned';
  static const teleconsultCallEnded = 'teleconsult_call_ended';
  static const teleconsultPrescriptionViewed = 'teleconsult_prescription_viewed';
  static const teleconsultContinueWithoutCall = 'teleconsult_continue_without_call';
  /// Patient opened from a list — `source` says which page.
  static const patientTapped = 'patient_tapped';
  static const referralAlertsOpened = 'referral_alerts_opened';

  // Members page
  static const searchUsed = 'search_used';
  static const householdExpanded = 'household_expanded';
  static const addMemberTapped = 'add_member_tapped';
  static const memberDeceased = 'member_deceased';

  // Settings / performance
  static const settingsMenuOpened = 'settings_menu_opened';
  static const settingsOptionSelected = 'settings_option_selected';

  // Patient profile (timeline) page
  static const aiInsightOpened = 'ai_insight_opened';
  static const aiAssistantOpened = 'ai_assistant_opened';
  static const visitDetailsViewed = 'visit_details_viewed';
  static const startVisitTapped = 'start_visit_tapped';

  // Visit flow
  static const scribeStarted = 'scribe_started';
  static const cardScanTapped = 'card_scan_tapped';
  static const symptomSelected = 'symptom_selected';
  static const followUpDateChanged = 'followup_date_changed';
  /// Step 3 referral facility dropdown changed (facility never sent).
  static const referralFacilityChanged = 'referral_facility_changed';
  static const helpfulVote = 'helpful_vote';
  static const messageShared = 'message_shared';
  static const callDoctorTapped = 'call_doctor_tapped';
  static const teleconsultConsent = 'teleconsult_consent';

  // Visit lifecycle and AI accuracy (catalog names)
  static const visitStarted = 'visit_started';
  static const visitStepCompleted = 'visit_step_completed';
  static const visitStepBack = 'visit_step_back';
  static const visitCompleted = 'visit_completed';
  static const visitAbandoned = 'visit_abandoned';
  static const symptomOutcome = 'symptom_outcome';
  static const formSubmitted = 'form_submitted';
  static const aiFieldOutcome = 'ai_field_outcome';
  static const scribeResult = 'scribe_result';
  static const scribeStopped = 'scribe_stopped';
  static const fieldSource = 'field_source';
  static const epiScanAttempt = 'epi_scan_attempt';
  static const cardScanResult = 'card_scan_result';
  static const aiSummaryGenerated = 'ai_summary_generated';

  // AI assistant
  static const assistantAsked = 'assistant_asked';
  static const assistantAnswered = 'assistant_answered';
  static const assistantClosed = 'assistant_closed';
}

/// Parameter names.
abstract final class AnalyticsParam {
  static const tab = 'tab';
  static const fromTab = 'from_tab';
  static const method = 'method';
  static const result = 'result';
  static const failureReason = 'failure_reason';
  static const durationMs = 'duration_ms';
  static const isOnline = 'is_online';
  /// NID already registered: 'true' / 'false' / 'unknown' (offline).
  static const existingPatient = 'existing_patient';
  /// The SK cleared NID-scanned details and typed them instead.
  static const scanCleared = 'scan_cleared';
  /// The choice equals what the app pre-selected.
  static const isDefault = 'is_default';
  // Teleconsult
  /// Speciality title as Shukhee names it (e.g. General Physician).
  static const speciality = 'speciality';
  /// 1 for the first booking try, 2+ for Retry / Try again.
  static const attempt = 'attempt';
  static const waitMs = 'wait_ms';
  static const callMs = 'call_ms';
  static const documentType = 'document_type';
  static const photosPrescription = 'photos_prescription';
  static const photosLabReport = 'photos_lab_report';
  /// The contact number sent is the patient's number on file.
  static const contactFromRecord = 'contact_from_record';
  /// Which screen the SK left from (continue without call).
  static const after = 'after';
  static const trigger = 'trigger';
  static const households = 'households';
  static const members = 'members';
  static const from = 'from';
  static const to = 'to';
  static const type = 'type';
  static const action = 'action';
  static const permission = 'permission';
  static const granted = 'granted';
  static const source = 'source';
  static const filter = 'filter';
  static const filterValue = 'filter_value';
  static const activeFilters = 'active_filters';
  static const target = 'target';
  static const position = 'position';
  static const programme = 'programme';
  static const completed = 'completed';
  static const count = 'count';
  static const resultCount = 'result_count';
  static const queryLength = 'query_length';
  static const queryType = 'query_type';
  static const listMode = 'list_mode';
  static const otherMembers = 'other_members';
  static const row = 'row';
  static const searching = 'searching';
  static const list = 'list';
  static const isHead = 'is_head';
  static const nidScan = 'nid_scan';
  static const option = 'option';
  static const rangeDays = 'range_days';
  static const hasSummary = 'has_summary';
  static const button = 'button';
  static const step = 'step';
  static const mode = 'mode';
  static const daysAhead = 'days_ahead';
  static const daysChanged = 'days_changed';
  static const visitId = 'visit_id';
  static const fromStep = 'from_step';
  static const toStep = 'to_step';
  static const lastStep = 'last_step';
  static const activeMs = 'active_ms';
  static const inputMode = 'input_mode';
  /// First mic start to last mic stop — includes time the mic was off.
  static const scribeSpanMs = 'scribe_span_ms';
  /// Seconds the mic was actually on in one session / summed for a step.
  static const micSec = 'mic_sec';
  static const micSecTotal = 'mic_sec_total';
  static const micSessions = 'mic_sessions';
  static const stoppedBy = 'stopped_by';
  static const attempts = 'attempts';
  static const photosRead = 'photos_read';
  static const vaccinesDue = 'vaccines_due';
  static const vaccinesFound = 'vaccines_found';
  static const attemptIndex = 'attempt_index';
  static const engine = 'engine';
  static const captureQuality = 'capture_quality';
  static const matchedVaccines = 'matched_vaccines';
  static const revisit = 'revisit';
  static const programmes = 'programmes';
  static const scribeUsed = 'scribe_used';
  static const scanUsed = 'scan_used';
  static const teleconsultUsed = 'teleconsult_used';
  static const teleconsultMs = 'teleconsult_ms';
  static const referred = 'referred';
  static const feature = 'feature';
  static const field = 'field';
  static const outcome = 'outcome';
  static const filledBy = 'filled_by';
  static const symptomKey = 'symptom_key';
  static const addedBy = 'added_by';
  static const fieldsTotal = 'fields_total';
  static const fieldsShown = 'fields_shown';
  static const fieldsExtractable = 'fields_extractable';
  static const fieldsAi = 'fields_ai';
  static const fieldsScan = 'fields_scan';
  static const fieldsManual = 'fields_manual';
  static const fieldsPrefilled = 'fields_prefilled';
  static const fieldsDerived = 'fields_derived';
  static const fieldsEmpty = 'fields_empty';
  static const formMs = 'form_ms';
  static const manualEditMs = 'manual_edit_ms';
  static const card = 'card';
  static const fieldsFilled = 'fields_filled';
  static const scanMs = 'scan_ms';
  static const generationMs = 'generation_ms';
  static const responseMs = 'response_ms';
  static const askedAgain = 'asked_again';
  static const questions = 'questions';
  static const answered = 'answered';
  static const failed = 'failed';
  static const totalResponseMs = 'total_response_ms';
  static const context = 'context';
  static const vote = 'vote';
  static const channel = 'channel';
  static const launched = 'launched';
}

/// User property names (set at sign-in).
abstract final class AnalyticsUserProperty {
  static const tenantId = 'tenant_id';
  static const upazila = 'upazila';
  static const unionArea = 'union_area';
  static const appLanguage = 'app_language';
  static const appFlavor = 'app_flavor';
}

/// Common parameter values.
abstract final class AnalyticsValue {
  // Period filter and bottom-nav tab values.
  static const month = 'month';
  static const week = 'week';
  static const patients = 'patients';
  static const training = 'training';

  static const success = 'success';
  static const failed = 'failed';
  static const cancelled = 'cancelled';

  // login / unlock methods
  static const online = 'online';
  static const offline = 'offline';
  static const pin = 'pin';
  static const biometric = 'biometric';

  // failure reasons
  static const wrongCredentials = 'wrong_credentials';
  static const wrongPin = 'wrong_pin';
  static const sessionExpired = 'session_expired';
  static const updateRequired = 'update_required';
  static const versionCheckFailed = 'version_check_failed';
  static const timeout = 'timeout';
  static const serverError = 'server_error';
  static const other = 'other';

  // sync triggers
  static const firstLogin = 'first_login';
  static const fullSync = 'full';
  static const relogin = 'relogin';
  static const manual = 'manual';
  static const pullRefresh = 'pull_refresh';
  static const auto = 'auto';

  // app update
  static const force = 'force';
  static const optional = 'optional';
  static const update = 'update';
  static const later = 'later';

  // filter_applied
  static const village = 'village';
  static const programme = 'programme';
  static const select = 'select';
  static const clear = 'clear';
  static const add = 'add';
  static const remove = 'remove';
  static const all = 'all';

  // sources / targets on the home screen
  static const fab = 'fab';
  static const searchScan = 'search_scan';
  // Registration: scanner, capture method, sheet choices
  static const addMember = 'add_member';
  static const camera = 'camera';
  static const gallery = 'gallery';
  static const notFound = 'not_found';
  static const unknown = 'unknown';
  static const scanCreate = 'scan_create';
  static const scanLink = 'scan_link';
  static const manualCreate = 'manual_create';
  static const manualRegister = 'manual_register';
  static const closed = 'closed';
  // Coaching launch failures
  static const notInitialized = 'not_initialized';
  static const noActivity = 'no_activity';
  // Teleconsult outcomes / failure reasons / sources
  static const teleconsult = 'teleconsult';
  static const wrapUp = 'wrap_up';
  static const notCompleted = 'not_completed';
  static const invalidMobile = 'invalid_mobile';
  static const accountInactive = 'account_inactive';
  static const notProvisioned = 'not_provisioned';
  static const unauthorized = 'unauthorized';
  static const vendorUnreachable = 'vendor_unreachable';
  static const patientNotResolved = 'patient_not_resolved';
  static const bookingFailed = 'booking_failed';
  static const validation = 'validation';
  static const cameraMicDenied = 'camera_mic_denied';
  static const queue = 'queue';
  static const search = 'search';
  static const card = 'card';
  static const visitButton = 'visit_button';
  static const banner = 'banner';
  static const bell = 'bell';

  // filter / search sources
  static const home = 'home';
  static const members = 'members';
  static const service = 'service';
  static const households = 'households';
  static const expand = 'expand';
  static const collapse = 'collapse';
  static const head = 'head';
  static const otherMember = 'other_member';
  static const serviceList = 'service_list';
  static const householdDetail = 'household_detail';
  static const selectHousehold = 'select_household';
  static const addGuardian = 'add_guardian';
  static const saved = 'saved';

  // tab_selected / filter sources and values (performance, settings)
  static const bottomNav = 'bottom_nav';
  static const performance = 'performance';
  static const kpiDashboard = 'kpi_dashboard';
  static const period = 'period';
  static const dateFrom = 'date_from';
  static const dateTo = 'date_to';
  static const ssSubVillage = 'ss_sub_village';
  static const menu = 'menu';
  static const settingsScreen = 'settings_screen';

  // patient profile
  static const patientProfile = 'patient_profile';
  static const timeline = 'timeline';
  static const history = 'history';
  static const actionsRow = 'actions_row';
  static const noServicesCard = 'no_services_card';

  // visit flow
  static const visit = 'visit';
  static const symptoms = 'symptoms';
  static const live = 'live';
  static const record = 'record';
  static const grid = 'grid';
  static const otherText = 'other_text';
  static const sms = 'sms';
  static const whatsapp = 'whatsapp';
  static const visitStep3 = 'visit_step3';
  static const agreed = 'agreed';
  static const declined = 'declined';

  // input_mode / scribe / summary / assistant
  static const voice = 'voice';
  static const scan = 'scan';
  static const partial = 'partial';
  static const offlineTemplate = 'offline_template';
  static const typed = 'typed';
  static const suggested = 'suggested';
  static const retry = 'retry';
  static const emptyAnswer = 'empty_answer';
  static const answered = 'answered';

  // scribe_stopped.stopped_by
  static const user = 'user';
  static const left = 'left';
  static const error = 'error';
  static const counselling = 'counselling';
  static const contact = 'contact';
  static const alerts = 'alerts';

  // search_used.query_type (shape of the query, never the text)
  static const digits = 'digits';
  static const text = 'text';
  static const mixed = 'mixed';
}

/// Screen names for `screen_view`. GoRoutes are logged by their route
/// `name`; these cover pages and steps that are not GoRoutes.
abstract final class AnalyticsScreen {
  // Router / route-observer page names.
  static const splash = 'splash';
  static const login = 'login';
  static const lock = 'lock';
  static const forgotPassword = 'forgot_password';
  static const onboarding = 'onboarding';
  static const syncProgress = 'sync_progress';
  static const offlineSync = 'offline_sync';
  static const networkDiagnostics = 'network_diagnostics';
  static const pinSetup = 'pin_setup';
  static const pinUnlock = 'pin_unlock';
  static const dashboard = 'dashboard';
  static const patientsList = 'patients_list';
  static const householdDetail = 'household_detail';
  static const patientProfile = 'patient_profile';
  static const immunisationTimeline = 'immunisation_timeline';
  static const programmeEnroll = 'programme_enroll';
  static const assistant = 'assistant';
  static const householdCreate = 'household_create';
  static const memberAdd = 'member_add';
  static const memberLink = 'member_link';
  static const enrollmentConsent = 'enrollment_consent';
  static const householdSelect = 'household_select';
  static const teleconsultConsent = 'teleconsult_consent';
  static const teleconsult = 'teleconsult';
  static const counselling = 'counselling';

  static const visitStep1 = 'visit_step1_symptoms';
  static const visitStep2Programmes = 'visit_step2_programmes';
  static const visitStep2Vaccination = 'visit_step2_vaccination';
  static String visitStep2Form(String formType) =>
      'visit_step2_${formType.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}';
  static const visitStep3 = 'visit_step3_recommendation';
  static const settings = 'settings';
  static const skPerformance = 'sk_performance';
  static const aiAssistant = 'ai_assistant';
  static const alertsDrawer = 'alerts_drawer';
  static const microCoaching = 'micro_coaching';

  // Pages pushed without a GoRoute, sheets and dialogs (LEAP-152)
  static const pdfViewer = 'pdf_viewer';
  static const teleconsultCallDetail = 'teleconsult_call_detail';
  static const cardScanAnc = 'card_scan_anc';
  static const cardScanNcd = 'card_scan_ncd';
  static const cardScanEpi = 'card_scan_epi';
  static const addHouseholdScan = 'add_household_scan';
  static const nidScanMember = 'nid_scan_member';
  static const scribeReview = 'scribe_review';
  static const memberDeceased = 'member_deceased';
  static const visitDetails = 'visit_details';
  static const skMyPatients = 'sk_my_patients';
  static const skKpiDashboard = 'sk_kpi_dashboard';
  static const debugDbViewer = 'debug_db_viewer';
  static const debugDbTable = 'debug_db_table';
  static const telemetryViewer = 'telemetry_viewer';
}
