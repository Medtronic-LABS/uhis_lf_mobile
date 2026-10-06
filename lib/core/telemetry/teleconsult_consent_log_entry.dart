/// One patient's Agree/Decline decision on the teleconsult patient-consent
/// gate -- see `TeleconsultConsentScreen`.
///
/// **PHI, like [AssistantContentEntry]** -- carries a patient id and, per the
/// BRAC consent record's own audit shape, the patient's raw date of birth so
/// age is visible in the audit trail (no derived "is minor" flag -- see this
/// feature's plan doc for that decision). Its table is in
/// [AppDatabase._allTables] and is wiped when a different SK signs into a
/// shared device.
///
/// Unlike [AssistantContentEntry] (gated by
/// [AppConfig.assistantContentTelemetryEnabled]), capture here is never
/// feature-flagged -- this is the compliance audit record for a consent
/// decision, not optional usage telemetry, so it always fires.
library;

/// The decision vocabulary the backend's `Shukhee Consent Log.decision`
/// Select field expects.
abstract final class TeleconsultConsentDecision {
  TeleconsultConsentDecision._();

  static const String agreed = 'Agreed';
  static const String declined = 'Declined';
}

/// Upload lifecycle -- same vocabulary as the other telemetry queues.
abstract final class TeleconsultConsentLogUploadStatus {
  TeleconsultConsentLogUploadStatus._();

  static const String pending = 'pending';
  static const String uploaded = 'uploaded';
}

class TeleconsultConsentLogEntry {
  const TeleconsultConsentLogEntry({
    required this.id,
    required this.patientId,
    required this.decision,
    required this.lng,
    required this.occurredAt,
    this.visitId,
    this.consentVersion,
    this.versionId,
    this.patientDob,
    this.skUserId,
    this.capturedTenantId,
    this.uploadStatus = TeleconsultConsentLogUploadStatus.pending,
    this.uploadedAt,
  });

  /// Client-generated UUID -- the server's dedup key on retry.
  final String id;

  /// Which patient the consent decision was about.
  final String patientId;

  /// The visit/encounter the consent was captured during, if any.
  final String? visitId;

  /// [TeleconsultConsentDecision.agreed] or
  /// [TeleconsultConsentDecision.declined].
  final String decision;

  /// `bn` | `en` -- the language the SK actually saw the consent copy in.
  final String lng;

  /// Echoed back from the `version` the client fetched via
  /// `shukhee_integration.api.consent.get_consent`.
  final String? consentVersion;

  /// The exact Shukhee Consent Version snapshot the patient saw -- what the
  /// backend actually links `Shukhee Consent Log.consent_version` to;
  /// [consentVersion] is kept only as a human-readable label. See
  /// `ShukheeConsentContent.versionId`'s own doc comment for why this must be
  /// carried forward unchanged, not re-derived later.
  final String? versionId;

  /// Raw ISO date, for age-visibility in the audit trail -- no derived
  /// "is minor" flag, just the raw fact.
  final String? patientDob;

  final String? skUserId;
  final int? capturedTenantId;

  /// Capture instant, epoch ms UTC.
  final int occurredAt;

  final String uploadStatus;
  final int? uploadedAt;

  Map<String, Object?> toDb() => {
        'id': id,
        'patient_id': patientId,
        'visit_id': visitId,
        'decision': decision,
        'lng': lng,
        'consent_version': consentVersion,
        'version_id': versionId,
        'patient_dob': patientDob,
        'sk_user_id': skUserId,
        'captured_tenant_id': capturedTenantId,
        'occurred_at': occurredAt,
        'upload_status': uploadStatus,
        'uploaded_at': uploadedAt,
      };

  static TeleconsultConsentLogEntry fromDb(Map<String, Object?> row) =>
      TeleconsultConsentLogEntry(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        visitId: row['visit_id'] as String?,
        decision: row['decision'] as String,
        lng: row['lng'] as String,
        consentVersion: row['consent_version'] as String?,
        versionId: row['version_id'] as String?,
        patientDob: row['patient_dob'] as String?,
        skUserId: row['sk_user_id'] as String?,
        capturedTenantId: row['captured_tenant_id'] as int?,
        occurredAt: row['occurred_at'] as int,
        uploadStatus: row['upload_status'] as String? ??
            TeleconsultConsentLogUploadStatus.pending,
        uploadedAt: row['uploaded_at'] as int?,
      );

  /// Wire shape `shukhee_integration.api.consent.record_consent_decision`
  /// actually reads -- snake_case, one record per call (that endpoint
  /// inserts exactly one `Shukhee Consent Log` row; there is no batch
  /// variant). `occurred_at` is deliberately NOT sent -- the server stamps
  /// its own `frappe.utils.now_datetime()` rather than trusting a
  /// client-supplied capture time, and `id`/`sk_user_id`/`captured_tenant_id`
  /// are local-only bookkeeping the server doesn't read (identity is
  /// resolved server-side from the auth token instead -- see
  /// `record_consent_decision`'s own doc comment).
  Map<String, dynamic> toApiJson() => {
        'patient_id': patientId,
        'visit_id': visitId,
        'decision': decision,
        'lng': lng,
        'consent_version': consentVersion,
        'version_id': versionId,
        'patient_dob': patientDob,
      };
}
