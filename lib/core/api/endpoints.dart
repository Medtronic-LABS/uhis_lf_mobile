/// Single home for every UHIS backend path the mobile app touches.
///
/// APPROVED API SET — only the 7 Postman-approved endpoints plus scribe and
/// logout are declared here. Any path not listed is not called by this app.
class Endpoints {
  // ── Auth ─────────────────────────────────────────────────────────────────
  static const String login = '/auth-service/session';
  static const String logout = '/auth-service/logout';

  // ── Spice: static data ────────────────────────────────────────────────────
  /// Returns user hierarchy: villages, subVillages, workflowIds, facilities.
  static const String staticUserData = '/spice-service/static-data/user-data';

  /// Patient search by identifier / free text. Used to look up an existing
  /// registration from a scanned NID before enrolling a duplicate.
  /// Postman: `patient-controller/searchPatient` → `{{spice_url}}/patient/search`.
  static const String patientSearch = '/spice-service/patient/search';

  // ── Spice: immunisation / EPI ─────────────────────────────────────────────
  /// Fetch immunisation schedule for a patient. Matches Android POST immunisation/list.
  static const String immunisationList = '/spice-service/immunisation/list';

  /// Push updated vaccine statuses for a visit encounter. Matches Android POST immunisation/create.
  static const String immunisationCreate = '/spice-service/immunisation/create';

  /// Post immunisation visit summary (vaccinated count, next visit date). Matches Android POST immunisation/summary-create.
  static const String immunisationSummaryCreate =
      '/spice-service/immunisation/summary-create';

  // ── Spice: assessments & clinical logs ───────────────────────────────────
  /// Create or update a visit assessment record.
  static const String assessmentCreate = '/spice-service/assessment/create';

  /// Create a screening record (initial NCD/ANC screening visit).
  static const String screeningCreate = '/spice-service/screening/create';

  /// Push a blood pressure log entry for a patient.
  static const String bpLogCreate = '/spice-service/bp-log/create';

  /// Push a blood glucose log entry for a patient.
  static const String glucoseLogCreate = '/spice-service/glucose-log/create';

  /// Create a CHW assessment-level BP log (multi-reading average within one visit).
  static const String assessmentBpLogCreate =
      '/spice-service/assessment/bplog-create';

  /// Create a CHW assessment-level glucose log.
  static const String assessmentGlucoseLogCreate =
      '/spice-service/assessment/glucoselog-create';

  /// Create a nurse/facility BP log (different path from CHW).
  static const String nurseBpLogCreate =
      '/spice-service/assessment/bp-log-create';

  /// Create a nurse/facility glucose log.
  static const String nurseGlucoseLogCreate =
      '/spice-service/assessment/glucose-log-create';

  // ── Spice: referrals ──────────────────────────────────────────────────────
  /// Create a referral ticket for a patient.
  static const String referralTicketCreate =
      '/spice-service/patient-transfer/create';

  /// Fetch existing referral tickets for a patient.
  static const String referralTicketFetch =
      '/spice-service/patient-transfer/list';

  // ── Spice: pregnancy details ──────────────────────────────────────────────
  /// Create ANC pregnancy episode record for a new pregnancy.
  static const String pregnancyDetailsCreate =
      '/spice-service/patient/pregnancy-details/create';

  /// Update an existing ANC pregnancy episode.
  static const String pregnancyDetailsUpdate =
      '/spice-service/patient/pregnancy-details/update';

  /// Fetch ANC pregnancy episode info for a patient.
  static const String pregnancyDetailsInfo =
      '/spice-service/patient/pregnancy-details/info';

  /// Update ANC risk flags on a pregnancy episode.
  static const String pregnancyAncRiskUpdate =
      '/spice-service/patient/pregnancy-anc-risk/update';

  // ── Spice: NCD medical reviews ────────────────────────────────────────────
  /// Create an NCD medical review for a patient.
  static const String ncdMedicalReviewCreate =
      '/spice-service/medical-review/ncd/create';

  /// Fetch NCD medical review details.
  static const String ncdMedicalReviewDetails =
      '/spice-service/medical-review/ncd/details';

  /// Create an NCD medical review summary record.
  static const String ncdMedicalReviewSummaryCreate =
      '/spice-service/medical-review/ncd/summary-create';

  /// Update confirmed NCD diagnosis.
  static const String confirmDiagnosisUpdate =
      '/spice-service/medical-review/confirm-diagnosis/update';

  /// Update patient NCD treatment plan.
  static const String patientTreatmentPlanUpdate =
      '/spice-service/patient-treatment-plan/update';

  // ── Spice: NCD follow-ups ─────────────────────────────────────────────────
  /// List NCD follow-up records for a patient.
  static const String followUpNcdList = '/spice-service/follow-up/ncd/list';

  /// Update an NCD follow-up record.
  static const String followUpNcdUpdate = '/spice-service/follow-up/ncd/update';

  // ── Spice: ANC medical reviews ────────────────────────────────────────────
  /// Create an ANC pregnancy medical review.
  static const String ancMedicalReviewCreate =
      '/spice-service/medical-review/anc-pregnancy/create';

  /// Fetch ANC pregnancy medical review details.
  static const String ancMedicalReviewDetails =
      '/spice-service/medical-review/anc-pregnancy/details';

  // ── Spice: PNC medical reviews ────────────────────────────────────────────
  /// Create a PNC mother medical review.
  static const String pncMedicalReviewCreate =
      '/spice-service/medical-review/pnc-mother/create';

  /// Fetch PNC medical review details.
  static const String pncMedicalReviewDetails =
      '/spice-service/medical-review/pnc/details';

  /// Fetch PNC history for a patient.
  static const String pncHistory = '/spice-service/medical-review/pnc-history';

  // ── Spice: Labour medical reviews ─────────────────────────────────────────
  /// Create a labour/delivery record (mother + neonate).
  static const String labourMotherNeonateCreate =
      '/spice-service/medical-review/labour-mother-neonate/create';

  /// Fetch labour/delivery details.
  static const String labourMotherNeonateDetails =
      '/spice-service/medical-review/labour-mother-neonate/details';

  // ── Spice: static data for medical reviews ────────────────────────────────
  /// Fetch NCD medical review metadata (diagnoses, conditions lookup).
  static const String staticNcdMedicalReview =
      '/spice-service/static-data/ncd-medical-review';

  /// Fetch ANC mother-neonate metadata.
  static const String staticMetaMotherNeonateAnc =
      '/spice-service/static-data/meta-data/mother-neonate-anc';

  /// Fetch PNC mother metadata.
  static const String staticMetaPncMother =
      '/spice-service/static-data/meta-data/mother-neonate-pnc-mother';

  /// Fetch PNC neonate/baby metadata.
  static const String staticMetaPncBaby =
      '/spice-service/static-data/meta-data/mother-neonate-pnc-baby';

  // ── Offline-service: bulk sync ────────────────────────────────────────────
  /// Bulk pull — households, members, followUps, householdMemberLinks.
  static const String offlineSyncFetch =
      '/offline-service/offline-sync/fetch-synced-data';

  /// Assessment timeline per village.
  static const String offlineSyncMemberAssessmentHistory =
      '/offline-service/offline-sync/member-assessment-history';

  /// Bulk push — households, householdMembers, assessments, followUps, links.
  static const String offlineSyncCreate =
      '/offline-service/offline-sync/create';

  // ── FHIR Server: observations ─────────────────────────────────────────────
  /// FHIR Observation search by encounter — returns a Bundle.
  static String fhirObservationByEncounter(String encounterId,
          {int count = 200}) =>
      '/fhir-server/fhir/Observation?encounter=Encounter/$encounterId&_count=$count';

  // ── AI Scribe: voice → SOAP note ─────────────────────────────────────────
  // nginx prefix on prod backend: /ai-scribe/ (not /ai-scribe-service/)
  static const String scribeTranscribe =
      '/ai-scribe/scribe/transcribe';
  static String scribeResult(String jobId) =>
      '/ai-scribe/scribe/results/$jobId';
  static String scribeNote(String noteId) =>
      '/ai-scribe/scribe/notes/$noteId';
  static String scribeAccept(String noteId) =>
      '/ai-scribe/scribe/notes/$noteId/accept';
  static String scribeReject(String noteId) =>
      '/ai-scribe/scribe/notes/$noteId/reject';

  /// Live streaming ASR + on-demand clinical extraction (WebSocket).
  static const String scribeRealtimeTranscribe =
      '/ai-scribe-service/scribe/realtime/transcribe';

  // ── AI Visit Briefing: pre-visit guidance cards ───────────────────────────
  static const String visitBriefingGenerate =
      '/ai-scribe/briefing/generate';
  static const String visitBriefingSummary =
      '/ai-scribe/briefing/summary';

  // ── AI Programme Recommendation: Step-2 programme picker ─────────────────
  static const String programmeRecommendation =
      '/ai-scribe/programme-recommendation/recommend';

  // ── AI Next Best Action: post-assessment care plan proposal ──────────────
  static const String nabaGenerate = '/ai-scribe/naba/generate';

  // ── AI Assistant: conversational Q&A ────────────────────────────────────
  static const String assistantAsk = '/ai-scribe/assistant/ask';

  // Chunked upload — for audio files ≥ 1 MB (rural 2G path)
  static const String scribeUploadInit = '/ai-scribe/upload/init';
  static String scribeUploadChunk(String uploadId, int chunk) =>
      '/ai-scribe/upload/$uploadId/chunk/$chunk';
  static String scribeUploadStatus(String uploadId) =>
      '/ai-scribe/upload/$uploadId/status';
  static String scribeUploadComplete(String uploadId) =>
      '/ai-scribe/upload/$uploadId/complete';
}
