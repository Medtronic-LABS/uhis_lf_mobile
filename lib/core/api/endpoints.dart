/// Single home for every UHIS backend path the mobile app touches.
///
/// Names mirror the entries in `postman/UHIS-Platform.postman_collection.json`
/// so a path change on the server can be traced here without a fan-out grep.
/// Engineering Design Standards (Config Management): widgets and repositories
/// MUST reference these constants — no inline string URLs anywhere.
class Endpoints {
  // ── Auth + identity ──────────────────────────────────────────────────────
  static const String login = '/auth-service/session';
  static const String logout = '/auth-service/logout';
  static const String profile = '/user-service/user/profile';

  /// Villages owned by a given user (SK). Worklist scope resolution.
  static String userVillages(String userId) =>
      '/user-service/user/user-villages/$userId';

  // ── Admin: village hierarchy ─────────────────────────────────────────────
  /// Returns sub-villages for a given village (union) ID.
  /// Response: { "entity": [ { "id": 18, "name": "Meherpur Sadar", ... }, ... ] }
  static String subVillagesByVillage(int villageId) =>
      '/admin-service/sub-villages/by-village/$villageId';

  /// Bulk sub-village fetch — preferred over the per-village loop.
  static const String subVillagesByVillageIds =
      '/admin-service/sub-villages-by-village-ids';

  static String shasthyaShebikaSubVillages(int id) =>
      '/admin-service/shasthya-shebika/$id/sub-villages';

  /// Fetch Shasthya Shebikas (and their sub-villages) for a given SK ID.
  /// POST with body: { "id": <skId> }
  /// Response: { "data": { "<skId>": [ { "subVillages": [...] }, ... ] } }
  static const String shasthyaShebikasBySkId =
      '/admin-service/shasthya-shebika/by-shasthya-kormi-id';

  // ── Spice: household + member ────────────────────────────────────────────
  static const String householdList = '/spice-service/household/list';
  static const String householdMemberList =
      '/spice-service/household/member/list';
  static const String householdMemberLinkList =
      '/spice-service/household-member-link/list';

  /// Get a single household by ID with embedded members.
  /// Response: { "entity": { "id": ..., "householdMembers": [...], ... } }
  static String householdById(String householdId) =>
      '/spice-service/household/$householdId';

  // ── FHIR Mapper: household member lookups ────────────────────────────────
  /// Get household member by patient ID.
  static const String fhirHouseholdMemberByPatientId =
      '/fhir-mapper-service/household/member/patient-id';

  /// Get household member by member ID.
  static const String fhirHouseholdMemberById =
      '/fhir-mapper-service/household/member/id';

  /// Get households by member IDs (bulk lookup).
  static const String fhirHouseholdByMemberIds =
      '/fhir-mapper-service/household/member/ids';

  // ── Spice: patient (worklist primary signals) ────────────────────────────
  static const String patientList = '/spice-service/patient/list';
  static const String patientSearch = '/spice-service/patient/search';
  static const String patientOfflineList =
      '/spice-service/patient/offline/list';
  static const String patientDetails = '/spice-service/patient/patientDetails';
  static const String patientDiagnosisDetails =
      '/spice-service/patient/diagnosis-details';
  static const String patientGetDiagnosisDetails =
      '/spice-service/patient/get-diagnosis-details';
  static const String patientMemberAssessmentHistory =
      '/spice-service/patient/member-assessment-history';
  static const String patientPregnancyInfo =
      '/spice-service/patient/pregnancy/info';
  static const String patientPregnancyDetails =
      '/spice-service/patient/pregnancy/details';

  /// Patient treatment history (prescriptions, medications).
  static const String patientTreatmentDetails =
      '/spice-service/patient/treatment-details';

  /// Patient vitals list (BP, glucose, weight history).
  static const String patientVitalsList = '/spice-service/patient/vitals/list';

  /// Patient status (enrolled, active, transferred, deceased).
  static const String patientStatus = '/spice-service/patient/patient-status';

  // ── Spice: vital logs (BP, Glucose) ──────────────────────────────────────
  /// Blood pressure logs for a patient.
  static const String bpLogList = '/spice-service/bplog/list';
  static const String bpLogCreate = '/spice-service/bplog/create';

  /// Glucose logs for a patient.
  static const String glucoseLogList = '/spice-service/glucoselog/list';
  static const String glucoseLogCreate = '/spice-service/glucoselog/create';

  // ── Spice: assessments ───────────────────────────────────────────────────
  /// Create a new assessment (screening, vitals capture).
  static const String assessmentCreate = '/spice-service/assessment/create';
  static const String assessmentBpLogCreate =
      '/spice-service/assessment/bp-log-create';
  static const String assessmentGlucoseLogCreate =
      '/spice-service/assessment/glucose-log-create';

  // ── Spice: medical review ────────────────────────────────────────────────
  /// Vital observations from medical review.
  static const String medicalReviewVitalDetails =
      '/spice-service/medical-review/vital-details';

  /// PNC (postnatal care) details.
  static const String medicalReviewPncDetails =
      '/spice-service/medical-review/pnc/details';
  static const String medicalReviewPncCreate =
      '/spice-service/medical-review/pnc/create';

  /// ANC (antenatal care) details.
  static const String medicalReviewAncDetails =
      '/spice-service/medical-review/anc-pregnancy/details';

  /// ANC (antenatal care) history.
  static const String medicalReviewAncHistory =
      '/spice-service/medical-review/anc-history';

  /// NCD medical review history summary (for viewing historical data).
  static const String medicalReviewNcdDetails =
      '/spice-service/medical-review/ncd/history-summary';

  /// Mental health / eye care details (includes CATARACT, EYE_CARE).
  static const String mentalHealthDetails =
      '/spice-service/mentalhealth/details';

  /// ICCM general details (above 5 years).
  static const String medicalReviewIccmDetails =
      '/spice-service/medical-review/iccm-general/details';

  /// ICCM under 2 months details.
  static const String medicalReviewIccmUnder2MonthsDetails =
      '/spice-service/medical-review/iccm-under-2months/details';

  /// ICCM under 5 years details.
  static const String medicalReviewIccmUnder5YearsDetails =
      '/spice-service/medical-review/iccm-under-5years/details';

  /// Labour/delivery/mother-neonate details.
  static const String medicalReviewLabourDetails =
      '/spice-service/medical-review/labour-mother-neonate/details';

  /// Weight tracking.
  static const String medicalReviewWeight =
      '/spice-service/medical-review/weight';
  static const String medicalReviewWeightCreate =
      '/spice-service/medical-review/weight/create';

  /// Height tracking.
  static const String medicalReviewHeightCreate =
      '/spice-service/medical-review/height/create';

  /// BMI tracking.
  static const String medicalReviewBmiCreate =
      '/spice-service/medical-review/bmi/create';

  /// BP via medical review.
  static const String medicalReviewBpCreate =
      '/spice-service/medical-review/bp/create';

  /// Medical review history (encounter-shaped history).
  static const String medicalReviewHistory =
      '/spice-service/medical-review/history';

  // ── Spice: patient visits ────────────────────────────────────────────────
  /// Create a new patient visit (returns visitId).
  static const String patientVisitCreate =
      '/spice-service/patientvisit/create';

  /// List patient visits.
  static const String patientVisitList = '/spice-service/patientvisit/list';

  /// Get patient visit details.
  static const String patientVisitDetails =
      '/spice-service/patientvisit/details';

  // ── Referral tickets (verified against postman + Java controllers) ───────
  /// List referral tickets for a patient. Postman: Spice Service →
  /// patient-controller → getReferralTicket. Controller:
  /// `spice-service/.../patient/controller/PatientController.java:226`.
  static const String referralTicketList =
      '/spice-service/patient/referral-tickets';

  /// Create a referral ticket (spice-side). Postman: Spice Service →
  /// patient-controller → createReferralTicket. Controller:
  /// `PatientController.java:243`.
  static const String referralTicketCreate =
      '/spice-service/patient/referral-tickets/create';

  /// List referral tickets via fhir-mapper. Postman: FHIR Mapper →
  /// patient-controller → getReferralTicket. Controller:
  /// `fhir-mapper/.../patient/controller/PatientController.java:217`.
  static const String fhirReferralTicketList =
      '/fhir-mapper/patient/referral-tickets';

  /// Create a referral ticket via fhir-mapper — produces a FHIR
  /// `ServiceRequest` server-side. Postman: FHIR Mapper →
  /// patient-controller → createReferralTicket. Controller:
  /// `fhir-mapper/.../patient/controller/PatientController.java:201`.
  static const String fhirReferralTicketCreate =
      '/fhir-mapper/patient/referral-tickets/create';

  /// Update a referral ticket via fhir-mapper — updates server-side
  /// `ServiceRequest.status`. Postman: FHIR Mapper → patient-controller →
  /// updateReferralTicketByMemberId. Controller:
  /// `fhir-mapper/.../patient/controller/PatientController.java:323`.
  static const String fhirReferralTicketUpdate =
      '/fhir-mapper/patient/referral-tickets/update';

  // ── Spice: follow-up (programme-aware overdue signals) ───────────────────
  static const String followUpList = '/spice-service/follow-up/list';
  static const String followUpNcdList = '/spice-service/follow-up/ncd/list';
  static const String followUpCreate = '/spice-service/follow-up/create';
  static const String followUpOfflineLost =
      '/spice-service/follow-up/offline/lost-to-followups';
  static const String followUpOfflineScreening =
      '/spice-service/follow-up/offline/screening-followups';
  static const String followUpOfflineMedicalReview =
      '/spice-service/follow-up/offline/medical-review-followups';
  static const String followUpOfflineAssessment =
      '/spice-service/follow-up/offline/assessment-followups';

  // ── Spice: clinical detail (programme classification + risk hints) ───────
  static const String immunisationList = '/spice-service/immunisation/list';
  static const String immunisationDetail = '/spice-service/immunisation/detail';
  static const String immunisationCreate = '/spice-service/immunisation/create';
  static const String medicalReviewTbDetails =
      '/spice-service/medical-review/tb/details';
  static const String mentalHealthCreate = '/spice-service/mentalhealth/create';
  static const String mentalHealthConditionDetails =
      '/spice-service/mentalhealth/condition-details';

  // ── CQL Service: risk scoring + clinical decision support ────────────────
  /// AI-powered clinical pathway suggestion. Returns candidate programmes with
  /// confidence scores and rationale for explainability.
  static const String clinicalPathwaySuggest =
      '/cql-service/clinical-pathway/suggest';

  /// Evaluate patient against CQL library rules.
  static const String cqlEvaluate = '/cql-service/cql/evaluate';

  /// Evaluate by encounter ID.
  static const String cqlEvaluateEncounter =
      '/cql-service/cql/evaluate-encounter';

  /// Evaluate patient by specific CQL library.
  static const String cqlLibrary = '/cql-service/cql/library';

  /// Evaluate specific CQL expressions.
  static const String cqlExpression = '/cql-service/cql/expression';

  /// ANC risk result by patient ID.
  static const String cqlAncResult = '/cql-service/cql/anc-result';

  /// ANC results by villages (dashboard aggregation).
  static const String cqlAncResultList = '/cql-service/cql/anc-result/list';

  /// Get CQL result by patient ID.
  static const String cqlResult = '/cql-service/cql/result';

  // ── FHIR Server: direct FHIR resource access ────────────────────────────
  /// Base path for FHIR server (via nginx gateway).
  static const String fhirServerBase = '/fhir-server/fhir';

  /// Get all resources for a patient (Patient/$everything).
  /// FHIR R4: Returns a Bundle with Patient, Observations, Conditions, etc.
  static String fhirPatientEverything(String patientId) =>
      '/fhir-server/fhir/Patient/$patientId/\$everything';

  /// Get patient by FHIR ID.
  static String fhirPatient(String patientId) =>
      '/fhir-server/fhir/Patient/$patientId';

  /// Get encounter with all related resources.
  static String fhirEncounterEverything(String encounterId) =>
      '/fhir-server/fhir/Encounter/$encounterId/\$everything';

  /// Search ServiceRequests (referrals) for a patient.
  /// Returns FHIR Bundle with ServiceRequest resources.
  static String fhirServiceRequestByPatient(String patientId) =>
      '/fhir-server/fhir/ServiceRequest?subject=Patient/$patientId&_count=100';

  /// Search ServiceRequests (referrals) by village identifier.
  static String fhirServiceRequestByVillage(String villageId) =>
      '/fhir-server/fhir/ServiceRequest?identifier=http://mdtlabs.com/village-id|$villageId&_count=100';

  // ── AI Scribe: voice → SOAP note ─────────────────────────────────────────
  static const String scribeTranscribe =
      '/ai-scribe-service/scribe/transcribe';
  static String scribeResult(String jobId) =>
      '/ai-scribe-service/scribe/results/$jobId';
  static String scribeNote(String noteId) =>
      '/ai-scribe-service/scribe/notes/$noteId';
  static String scribeAccept(String noteId) =>
      '/ai-scribe-service/scribe/notes/$noteId/accept';
  static String scribeReject(String noteId) =>
      '/ai-scribe-service/scribe/notes/$noteId/reject';

  // Chunked upload — for audio files ≥ 1 MB (rural 2G path)
  static const String scribeUploadInit = '/ai-scribe-service/upload/init';
  static String scribeUploadChunk(String uploadId, int chunk) =>
      '/ai-scribe-service/upload/$uploadId/chunk/$chunk';
  static String scribeUploadStatus(String uploadId) =>
      '/ai-scribe-service/upload/$uploadId/status';
  static String scribeUploadComplete(String uploadId) =>
      '/ai-scribe-service/upload/$uploadId/complete';

  // ── Offline-service: bulk delta sync ─────────────────────────────────────
  /// GZIP'd bundle of households + members + assessments + follow-ups +
  /// reference data, scoped to the SK's villages. Nginx routes
  /// `/offline-service/` to the offline-service Spring app on :8093; the
  /// app's own controller is rooted at `/offline-sync/`.
  static const String offlineSyncFetch =
      '/offline-service/offline-sync/fetch-synced-data';
  static const String offlineSyncMemberAssessmentHistory =
      '/offline-service/offline-sync/member-assessment-history';
  static const String offlineSyncHhDataByReferenceIds =
      '/offline-service/offline-sync/get-hh-data-by-referenceIds';
  static const String offlineSyncSave =
      '/offline-service/offline-sync/save';

  /// Upload member signatures for offline-collected data.
  static const String offlineSyncUploadSignatures =
      '/offline-service/offline-sync/upload-signatures';

  /// Get offline sync status (pending, synced, failed).
  static const String offlineSyncStatus =
      '/offline-service/offline-sync/status';

  /// User's offline sync log.
  static const String offlineSyncUserLog =
      '/offline-service/offline-sync/user-log';

  /// Generate response for offline sync.
  static const String offlineSyncGenerateResponse =
      '/offline-service/offline-sync/generate-response';

  /// Create offline sync entry.
  static const String offlineSyncCreate =
      '/offline-service/offline-sync/create';
}
