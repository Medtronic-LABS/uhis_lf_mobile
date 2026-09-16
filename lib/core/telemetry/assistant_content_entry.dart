/// One patient AI assistant ("Ask") turn's PHI text — the question the SK
/// typed and the answer the model gave.
///
/// **PHI, like [VisitContentEntry].** Holds free clinical text that can name
/// the patient, so its table is in [AppDatabase._allTables] and is wiped when a
/// different SK signs into a shared device. Capture and upload are gated by
/// [AppConfig.assistantContentTelemetryEnabled].
///
/// Joined to the `assistant_ask` telemetry event by [correlator] — the per-ask
/// id minted once and carried on both streams. The chatbot has no encounter,
/// so this correlator, not a visit id, is the join key.
library;

/// Upload lifecycle — same vocabulary as the other telemetry queues.
abstract final class AssistantContentUploadStatus {
  AssistantContentUploadStatus._();

  static const String pending = 'pending';
  static const String uploaded = 'uploaded';
}

class AssistantContentEntry {
  const AssistantContentEntry({
    required this.id,
    required this.correlator,
    required this.occurredAt,
    this.question,
    this.answer,
    this.appLanguage,
    this.skUserId,
    this.capturedTenantId,
    this.uploadStatus = AssistantContentUploadStatus.pending,
    this.uploadedAt,
  });

  /// Client-generated UUID — the server's dedup key on retry.
  final String id;

  /// Per-ask correlator, shared with the assistant_ask telemetry event.
  final String correlator;

  final String? question;
  final String? answer;

  /// `bn` | `en` — the app language the answer was produced in.
  final String? appLanguage;

  final String? skUserId;
  final int? capturedTenantId;

  /// Capture instant, epoch ms UTC.
  final int occurredAt;

  final String uploadStatus;
  final int? uploadedAt;

  Map<String, Object?> toDb() => {
        'id': id,
        'correlator': correlator,
        'question': question,
        'answer': answer,
        'app_language': appLanguage,
        'sk_user_id': skUserId,
        'captured_tenant_id': capturedTenantId,
        'occurred_at': occurredAt,
        'upload_status': uploadStatus,
        'uploaded_at': uploadedAt,
      };

  static AssistantContentEntry fromDb(Map<String, Object?> row) =>
      AssistantContentEntry(
        id: row['id'] as String,
        correlator: row['correlator'] as String,
        question: row['question'] as String?,
        answer: row['answer'] as String?,
        appLanguage: row['app_language'] as String?,
        skUserId: row['sk_user_id'] as String?,
        capturedTenantId: row['captured_tenant_id'] as int?,
        occurredAt: row['occurred_at'] as int,
        uploadStatus: row['upload_status'] as String? ??
            AssistantContentUploadStatus.pending,
        uploadedAt: row['uploaded_at'] as int?,
      );

  /// Wire shape the server's /telemetry/assistant-content ingest expects
  /// (camelCase, ISO timestamp) — see app/api/assistant_content.py.
  Map<String, dynamic> toApiJson() => {
        'id': id,
        'correlator': correlator,
        'question': question,
        'answer': answer,
        'appLanguage': appLanguage,
        'skUserId': skUserId,
        'capturedTenantId': capturedTenantId,
        'occurredAt': DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true)
            .toIso8601String(),
      };
}
