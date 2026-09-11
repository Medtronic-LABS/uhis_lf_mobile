/// One row of visit-scoped AI content for product QA — transcript, WhatsApp
/// summary, and referral recommendation text.
///
/// **PHI, like [ValueAuditEntry].** Holds free text the SK saw or the scribe
/// heard, so the table is in [AppDatabase._allTables] and is wiped when a
/// different SK signs into a shared device. Capture and upload are gated by
/// [AppConfig.visitContentTelemetryEnabled].
library;

/// Upload lifecycle — same vocabulary as the telemetry and value-audit queues.
abstract final class VisitContentUploadStatus {
  VisitContentUploadStatus._();

  static const String pending = 'pending';
  static const String uploaded = 'uploaded';
}

class VisitContentEntry {
  const VisitContentEntry({
    required this.id,
    required this.visitUuid,
    required this.patientId,
    required this.occurredAt,
    this.transcript,
    this.transcriptCapturedAt,
    this.whatsappSummary,
    this.referralRecommendation,
    this.summaryStartedAt,
    this.summaryEndAt,
    this.skUserId,
    this.capturedTenantId,
    this.uploadStatus = VisitContentUploadStatus.pending,
    this.uploadedAt,
  });

  /// Client-generated UUID — server dedup key on retry.
  final String id;

  /// Encounter [visitId]; one row per visit.
  final String visitUuid;

  final String patientId;

  final String? transcript;
  final int? transcriptCapturedAt;

  final String? whatsappSummary;
  final String? referralRecommendation;
  final int? summaryStartedAt;
  final int? summaryEndAt;

  final String? skUserId;
  final int? capturedTenantId;

  /// Latest capture instant on the row, epoch ms UTC.
  final int occurredAt;

  final String uploadStatus;
  final int? uploadedAt;

  Map<String, Object?> toDb() => {
        'id': id,
        'visit_uuid': visitUuid,
        'patient_id': patientId,
        'transcript': transcript,
        'transcript_captured_at': transcriptCapturedAt,
        'whatsapp_summary': whatsappSummary,
        'referral_recommendation': referralRecommendation,
        'summary_started_at': summaryStartedAt,
        'summary_end_at': summaryEndAt,
        'sk_user_id': skUserId,
        'captured_tenant_id': capturedTenantId,
        'occurred_at': occurredAt,
        'upload_status': uploadStatus,
        'uploaded_at': uploadedAt,
      };

  static VisitContentEntry fromDb(Map<String, Object?> row) =>
      VisitContentEntry(
        id: row['id'] as String,
        visitUuid: row['visit_uuid'] as String,
        patientId: row['patient_id'] as String,
        transcript: row['transcript'] as String?,
        transcriptCapturedAt: row['transcript_captured_at'] as int?,
        whatsappSummary: row['whatsapp_summary'] as String?,
        referralRecommendation: row['referral_recommendation'] as String?,
        summaryStartedAt: row['summary_started_at'] as int?,
        summaryEndAt: row['summary_end_at'] as int?,
        skUserId: row['sk_user_id'] as String?,
        capturedTenantId: row['captured_tenant_id'] as int?,
        occurredAt: row['occurred_at'] as int,
        uploadStatus: row['upload_status'] as String? ??
            VisitContentUploadStatus.pending,
        uploadedAt: row['uploaded_at'] as int?,
      );

  Map<String, dynamic> toApiJson() => {
        'id': id,
        'visitUuid': visitUuid,
        'patientId': patientId,
        'transcript': transcript,
        'transcriptCapturedAt': _isoOrNull(transcriptCapturedAt),
        'whatsappSummary': whatsappSummary,
        'referralRecommendation': referralRecommendation,
        'summaryStartedAt': _isoOrNull(summaryStartedAt),
        'summaryEndAt': _isoOrNull(summaryEndAt),
        'skUserId': skUserId,
        'capturedTenantId': capturedTenantId,
        'occurredAt': DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true)
            .toIso8601String(),
      };

  static String? _isoOrNull(int? epochMs) {
    if (epochMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true)
        .toIso8601String();
  }
}
