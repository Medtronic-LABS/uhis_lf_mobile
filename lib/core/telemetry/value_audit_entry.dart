/// One before/after pair for a field the SK edited after AI filled it.
///
/// **This is the PHI half of telemetry.** [TelemetryEvent] holds field *ids*
/// and counts and is non-PHI by construction, which is what lets it survive
/// the local-data wipe. These rows hold what was actually measured — "AI heard
/// 160, the SK submitted 140" — so they are treated as clinical data
/// throughout: their table is listed in `AppDatabase._allTables` and is
/// cleared when a different SK signs into a shared device, capture is gated
/// behind `AppConfig.valueAuditEnabled`, and the server gates them again.
///
/// [visitUuid] is the same correlator the visit's [TelemetryEvent] carries, so
/// a report can join the two. It is still not a patient reference: it is
/// random, minted per visit, and never used to look anything up.
///
/// Values are stored as the strings the form held. No parsing, no unit
/// inference, no rounding — a report that shows a clinician what AI proposed
/// must show what it actually proposed.
library;

/// Upload lifecycle, reusing the same vocabulary as the telemetry queue.
abstract final class ValueAuditUploadStatus {
  ValueAuditUploadStatus._();

  static const String pending = 'pending';
  static const String uploaded = 'uploaded';
}

class ValueAuditEntry {
  const ValueAuditEntry({
    required this.id,
    required this.visitUuid,
    required this.fieldId,
    required this.occurredAt,
    this.aiFeature = 'scribe',
    this.aiValue,
    this.finalValue,
    this.uploadStatus = ValueAuditUploadStatus.pending,
    this.uploadedAt,
  });

  /// Client-generated UUID, and the server's dedup key — so a lost upload
  /// response cannot double-write the pair on retry.
  final String id;

  /// Ties this pair to the visit's telemetry row.
  final String visitUuid;

  /// Which AI feature proposed the value; matches the server's registry key.
  final String aiFeature;

  /// The form field, e.g. `systolic`.
  final String fieldId;

  /// What AI put in the field, as it was before the SK's first edit. Null when
  /// AI proposed nothing recordable.
  final String? aiValue;

  /// What was actually submitted, read at submit time rather than at edit
  /// time — the SK may edit the same field repeatedly, and only the last value
  /// is the one that reached the record.
  final String? finalValue;

  /// Epoch ms, UTC.
  final int occurredAt;

  final String uploadStatus;
  final int? uploadedAt;

  Map<String, Object?> toDb() => {
        'id': id,
        'visit_uuid': visitUuid,
        'ai_feature': aiFeature,
        'field_id': fieldId,
        'ai_value': aiValue,
        'final_value': finalValue,
        'occurred_at': occurredAt,
        'upload_status': uploadStatus,
        'uploaded_at': uploadedAt,
      };

  static ValueAuditEntry fromDb(Map<String, Object?> row) => ValueAuditEntry(
        id: row['id'] as String,
        visitUuid: row['visit_uuid'] as String,
        aiFeature: row['ai_feature'] as String? ?? 'scribe',
        fieldId: row['field_id'] as String,
        aiValue: row['ai_value'] as String?,
        finalValue: row['final_value'] as String?,
        occurredAt: row['occurred_at'] as int,
        uploadStatus: row['upload_status'] as String? ??
            ValueAuditUploadStatus.pending,
        uploadedAt: row['uploaded_at'] as int?,
      );

  Map<String, dynamic> toApiJson() => {
        'id': id,
        'visitUuid': visitUuid,
        'aiFeature': aiFeature,
        'fieldId': fieldId,
        'aiValue': aiValue,
        'finalValue': finalValue,
        'occurredAt':
            DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true)
                .toIso8601String(),
      };
}
