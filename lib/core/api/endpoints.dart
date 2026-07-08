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
