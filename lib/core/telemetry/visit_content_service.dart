/// Emit API for visit-scoped AI content telemetry.
///
/// Same contract as [TelemetryService]: never throws, never blocks a visit.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import 'visit_content_dao.dart';
import 'visit_content_entry.dart';

class VisitContentService {
  VisitContentService({
    required VisitContentDao dao,
    required Future<int?> Function() userIdResolver,
    Future<int?> Function()? tenantIdResolver,
    Uuid uuid = const Uuid(),
  })  : _dao = dao,
        _userIdResolver = userIdResolver,
        _tenantIdResolver = tenantIdResolver,
        _uuid = uuid;

  final VisitContentDao _dao;
  final Future<int?> Function() _userIdResolver;
  final Future<int?> Function()? _tenantIdResolver;
  final Uuid _uuid;

  /// ASR transcript at form submit.
  Future<void> recordTranscript({
    required String visitUuid,
    required String patientId,
    String? transcript,
    DateTime? capturedAt,
  }) async {
    if (!AppConfig.visitContentTelemetryEnabled) return;
    final trimmed = transcript?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      debugPrint('[VisitContent] transcript empty at submit — not stored');
      return;
    }
    final at = (capturedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _upsert(
      visitUuid: visitUuid,
      patientId: patientId,
      occurredAt: at,
      merge: (existing) => VisitContentEntry(
        id: existing?.id ?? _uuid.v4(),
        visitUuid: visitUuid,
        patientId: patientId,
        occurredAt: existing == null ? at : _maxInt(existing.occurredAt, at),
        skUserId: existing?.skUserId,
        capturedTenantId: existing?.capturedTenantId,
        transcript: trimmed?.isEmpty == true ? null : trimmed,
        transcriptCapturedAt: trimmed?.isEmpty == true ? null : at,
        whatsappSummary: existing?.whatsappSummary,
        referralRecommendation: existing?.referralRecommendation,
        summaryStartedAt: existing?.summaryStartedAt,
        summaryEndAt: existing?.summaryEndAt,
        helpfulnessVote: existing?.helpfulnessVote,
        uploadStatus: _uploadStatus(existing, existing?.uploadStatus),
        uploadedAt: existing?.uploadedAt,
      ),
    );
  }

  /// Step 3 summary screen opened.
  Future<void> recordSummaryStarted({
    required String visitUuid,
    required String patientId,
    DateTime? startedAt,
  }) async {
    if (!AppConfig.visitContentTelemetryEnabled) return;
    final at = (startedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _upsert(
      visitUuid: visitUuid,
      patientId: patientId,
      occurredAt: at,
      merge: (existing) => VisitContentEntry(
        id: existing?.id ?? _uuid.v4(),
        visitUuid: visitUuid,
        patientId: patientId,
        occurredAt: existing == null ? at : _maxInt(existing.occurredAt, at),
        skUserId: existing?.skUserId,
        capturedTenantId: existing?.capturedTenantId,
        transcript: existing?.transcript,
        transcriptCapturedAt: existing?.transcriptCapturedAt,
        summaryStartedAt: existing?.summaryStartedAt ?? at,
        whatsappSummary: existing?.whatsappSummary,
        referralRecommendation: existing?.referralRecommendation,
        summaryEndAt: existing?.summaryEndAt,
        helpfulnessVote: existing?.helpfulnessVote,
        uploadStatus: _uploadStatus(existing, existing?.uploadStatus),
        uploadedAt: existing?.uploadedAt,
      ),
    );
  }

  /// Step 3 Done / Accept tapped.
  Future<void> recordSummaryCompleted({
    required String visitUuid,
    required String patientId,
    String? whatsappSummary,
    String? referralRecommendation,
    DateTime? endedAt,
  }) async {
    if (!AppConfig.visitContentTelemetryEnabled) return;
    final at = (endedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _upsert(
      visitUuid: visitUuid,
      patientId: patientId,
      occurredAt: at,
      merge: (existing) => VisitContentEntry(
        id: existing?.id ?? _uuid.v4(),
        visitUuid: visitUuid,
        patientId: patientId,
        occurredAt: existing == null ? at : _maxInt(existing.occurredAt, at),
        skUserId: existing?.skUserId,
        capturedTenantId: existing?.capturedTenantId,
        transcript: existing?.transcript,
        transcriptCapturedAt: existing?.transcriptCapturedAt,
        summaryStartedAt: existing?.summaryStartedAt,
        // Preserve, don't blank. Every other field here falls back to
        // `existing`; these two did not, so a second call carrying only one
        // of them wiped the other — a WhatsApp summary captured correctly
        // and then lost to a re-render.
        whatsappSummary: _prefer(whatsappSummary, existing?.whatsappSummary),
        referralRecommendation: _prefer(
            referralRecommendation, existing?.referralRecommendation),
        summaryEndAt: at,
        helpfulnessVote: existing?.helpfulnessVote,
        uploadStatus: _uploadStatus(existing, existing?.uploadStatus),
        uploadedAt: existing?.uploadedAt,
      ),
    );
  }

  /// Thumbs up/down on the Step 3 AI counselling message (LEAP-68).
  Future<void> recordHelpfulnessVote({
    required String visitUuid,
    required String patientId,
    required String vote,
  }) async {
    if (!AppConfig.visitContentTelemetryEnabled) return;
    final normalized = vote == VisitContentHelpfulnessVote.down
        ? VisitContentHelpfulnessVote.down
        : VisitContentHelpfulnessVote.up;
    final at = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _upsert(
      visitUuid: visitUuid,
      patientId: patientId,
      occurredAt: at,
      merge: (existing) => VisitContentEntry(
        id: existing?.id ?? _uuid.v4(),
        visitUuid: visitUuid,
        patientId: patientId,
        occurredAt: existing == null ? at : _maxInt(existing.occurredAt, at),
        skUserId: existing?.skUserId,
        capturedTenantId: existing?.capturedTenantId,
        transcript: existing?.transcript,
        transcriptCapturedAt: existing?.transcriptCapturedAt,
        whatsappSummary: existing?.whatsappSummary,
        referralRecommendation: existing?.referralRecommendation,
        summaryStartedAt: existing?.summaryStartedAt,
        summaryEndAt: existing?.summaryEndAt,
        helpfulnessVote: normalized,
        uploadStatus: _uploadStatus(existing, existing?.uploadStatus),
        uploadedAt: existing?.uploadedAt,
      ),
    );
  }

  /// Whether [after] carries new upload payload compared to [before].
  ///
  /// Used to re-queue a row that was already uploaded when a later capture
  /// point (transcript after summary, or the reverse) adds fields.
  static bool _payloadChanged(
    VisitContentEntry? before,
    VisitContentEntry after,
  ) {
    if (before == null) return true;
    return before.transcript != after.transcript ||
        before.transcriptCapturedAt != after.transcriptCapturedAt ||
        before.whatsappSummary != after.whatsappSummary ||
        before.referralRecommendation != after.referralRecommendation ||
        before.summaryStartedAt != after.summaryStartedAt ||
        before.summaryEndAt != after.summaryEndAt ||
        before.helpfulnessVote != after.helpfulnessVote;
  }

  /// Keeps pending rows pending; re-queues uploaded rows when payload grows.
  static String _uploadStatus(VisitContentEntry? before, String? prior) {
    if (before == null) return VisitContentUploadStatus.pending;
    if (prior != VisitContentUploadStatus.uploaded) {
      return VisitContentUploadStatus.pending;
    }
    return VisitContentUploadStatus.uploaded;
  }

  /// Keeps [incoming] when it carries text, otherwise [existing].
  ///
  /// A capture point with nothing to say for a field must leave what is
  /// already stored alone — these merges only ever add.
  static String? _prefer(String? incoming, String? existing) {
    final trimmed = incoming?.trim();
    return (trimmed == null || trimmed.isEmpty) ? existing : trimmed;
  }

  /// Serializes every read-modify-write below.
  ///
  /// [_upsert] reads the row, merges, and writes it back, and its callers are
  /// concurrent: `_recordSummaryStarted` and `_recordSummaryCompleted` are
  /// both fired with `unawaited` from the Step 3 screen. Interleaved, the
  /// later writer re-reads a row the earlier one has not yet written and
  /// stores back the field it had just set — silently dropping a transcript
  /// or a WhatsApp summary that was captured correctly.
  Future<void> _writes = Future<void>.value();

  Future<void> _upsert({
    required String visitUuid,
    required String patientId,
    required int occurredAt,
    required VisitContentEntry Function(VisitContentEntry? existing) merge,
  }) {
    final next = _writes.then((_) => _upsertNow(
          visitUuid: visitUuid,
          patientId: patientId,
          occurredAt: occurredAt,
          merge: merge,
        ));
    // A failed link must not break the chain for every later write.
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _upsertNow({
    required String visitUuid,
    required String patientId,
    required int occurredAt,
    required VisitContentEntry Function(VisitContentEntry? existing) merge,
  }) async {
    try {
      final existing = await _dao.byVisitUuid(visitUuid);
      final userId = existing?.skUserId ?? (await _userIdResolver())?.toString();
      final tenantId =
          existing?.capturedTenantId ?? await _tenantIdResolver?.call();
      var entry = merge(existing);
      var uploadStatus = entry.uploadStatus;
      if (existing?.uploadStatus == VisitContentUploadStatus.uploaded &&
          _payloadChanged(existing, entry)) {
        uploadStatus = VisitContentUploadStatus.pending;
      }
      entry = VisitContentEntry(
        id: entry.id,
        visitUuid: entry.visitUuid,
        patientId: entry.patientId,
        occurredAt: entry.occurredAt,
        transcript: entry.transcript,
        transcriptCapturedAt: entry.transcriptCapturedAt,
        whatsappSummary: entry.whatsappSummary,
        referralRecommendation: entry.referralRecommendation,
        summaryStartedAt: entry.summaryStartedAt,
        summaryEndAt: entry.summaryEndAt,
        helpfulnessVote: entry.helpfulnessVote,
        skUserId: userId,
        capturedTenantId: tenantId,
        uploadStatus: uploadStatus,
        uploadedAt: uploadStatus == VisitContentUploadStatus.pending
            ? null
            : entry.uploadedAt,
      );
      await _dao.upsert(entry);
    } on Object catch (e, st) {
      debugPrint('[VisitContent] capture dropped: $e');
      debugPrint('[VisitContent] $st');
    }
  }

  static int _maxInt(int a, int b) => a > b ? a : b;
}
