/// Shadow-mode evaluation log entry for Phase 6 differential hints.
///
/// During Phase 4 pilot, the app computes what a differential model *would*
/// suggest but never surfaces it to the SK. These entries are stored locally
/// and uploaded to the FHIR encounter as a DocumentReference with tag
/// `system: "https://uhis.gov.bd/eval", code: "shadow-hint"`.
///
/// The clinical board queries these after sufficient volume to gate Phase 6.
library;

/// A single shadow-mode log entry captured at assessment completion.
class EvalLogEntry {
  const EvalLogEntry({
    required this.id,
    required this.encounterId,
    required this.patientId,
    required this.memberId,
    required this.capturedAt,
    required this.activatedProgrammes,
    required this.symptoms,
    required this.fieldValues,
    required this.cdsAlerts,
    required this.patientContextJson,
    this.uploadStatus = EvalUploadStatus.pending,
    this.uploadedAt,
    this.fhirDocRefId,
  });

  final String id;               // UUID
  final String encounterId;
  final String patientId;
  final String memberId;
  final DateTime capturedAt;

  /// JSON-encoded list of Programme codes: e.g. ["ICCM","TB_SCREEN"]
  final String activatedProgrammes;

  /// JSON-encoded list of symptom codes selected by SK (not scribe).
  final String symptoms;

  /// JSON-encoded map: fieldId → value (all values from submitted assessment).
  final String fieldValues;

  /// JSON-encoded list of CDS alert ids that fired during this assessment.
  final String cdsAlerts;

  /// JSON-encoded PatientContext snapshot (age, sex, conditions, flags).
  final String patientContextJson;

  final EvalUploadStatus uploadStatus;
  final DateTime? uploadedAt;
  final String? fhirDocRefId; // FHIR DocumentReference id after upload

  Map<String, Object?> toDb() => {
        'id': id,
        'encounter_id': encounterId,
        'patient_id': patientId,
        'member_id': memberId,
        'captured_at': capturedAt.millisecondsSinceEpoch,
        'activated_programmes': activatedProgrammes,
        'symptoms': symptoms,
        'field_values': fieldValues,
        'cds_alerts': cdsAlerts,
        'patient_context_json': patientContextJson,
        'upload_status': uploadStatus.name,
        'uploaded_at': uploadedAt?.millisecondsSinceEpoch,
        'fhir_doc_ref_id': fhirDocRefId,
      };

  factory EvalLogEntry.fromDb(Map<String, Object?> row) => EvalLogEntry(
        id: row['id'] as String,
        encounterId: row['encounter_id'] as String,
        patientId: row['patient_id'] as String,
        memberId: row['member_id'] as String,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
            row['captured_at'] as int),
        activatedProgrammes: row['activated_programmes'] as String,
        symptoms: row['symptoms'] as String,
        fieldValues: row['field_values'] as String,
        cdsAlerts: row['cds_alerts'] as String,
        patientContextJson: row['patient_context_json'] as String,
        uploadStatus: EvalUploadStatus.values.firstWhere(
          (e) => e.name == (row['upload_status'] as String?),
          orElse: () => EvalUploadStatus.pending,
        ),
        uploadedAt: row['uploaded_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['uploaded_at'] as int)
            : null,
        fhirDocRefId: row['fhir_doc_ref_id'] as String?,
      );
}

enum EvalUploadStatus { pending, uploading, uploaded, failed }

/// DDL for the eval_log table — referenced by AppDatabase v11 migration.
const String kEvalLogTableDdl = '''
  CREATE TABLE eval_log (
    id TEXT PRIMARY KEY,
    encounter_id TEXT NOT NULL,
    patient_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    captured_at INTEGER NOT NULL,
    activated_programmes TEXT NOT NULL,
    symptoms TEXT NOT NULL,
    field_values TEXT NOT NULL,
    cds_alerts TEXT NOT NULL,
    patient_context_json TEXT NOT NULL,
    upload_status TEXT NOT NULL DEFAULT 'pending',
    uploaded_at INTEGER,
    fhir_doc_ref_id TEXT
  )
''';

const String kEvalLogIndexDdl1 =
    'CREATE INDEX idx_eval_log_patient ON eval_log(patient_id)';
const String kEvalLogIndexDdl2 =
    'CREATE INDEX idx_eval_log_upload ON eval_log(upload_status)';
const String kEvalLogIndexDdl3 =
    'CREATE INDEX idx_eval_log_captured ON eval_log(captured_at DESC)';
