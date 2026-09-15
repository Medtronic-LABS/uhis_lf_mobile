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
    final hasTranscript = trimmed != null && trimmed.isNotEmpty;
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
        // Preserve rather than blank: this used to write `null` whenever it
        // was handed an empty string, wiping a transcript already captured.
        transcript: hasTranscript ? trimmed : existing?.transcript,
        transcriptCapturedAt:
            hasTranscript ? at : existing?.transcriptCapturedAt,
        whatsappSummary: existing?.whatsappSummary,
        referralRecommendation: existing?.referralRecommendation,
        summaryStartedAt: existing?.summaryStartedAt,
        summaryEndAt: existing?.summaryEndAt,
        // Always pending: an upsert only happens because new content arrived,
        // and content captured after a flush would otherwise stay on the
        // device forever. Re-sending is safe — the server merges by visit.
        uploadStatus: VisitContentUploadStatus.pending,
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
        // Always pending: an upsert only happens because new content arrived,
        // and content captured after a flush would otherwise stay on the
        // device forever. Re-sending is safe — the server merges by visit.
        uploadStatus: VisitContentUploadStatus.pending,
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
        whatsappSummary: _prefer(whatsappSummary, existing?.whatsappSummary),
        referralRecommendation: _prefer(
            referralRecommendation, existing?.referralRecommendation),
        summaryEndAt: at,
        // Always pending: an upsert only happens because new content arrived,
        // and content captured after a flush would otherwise stay on the
        // device forever. Re-sending is safe — the server merges by visit.
        uploadStatus: VisitContentUploadStatus.pending,
        uploadedAt: existing?.uploadedAt,
      ),
    );
  }

  /// Serializes every read-modify-write below.
  ///
  /// [_upsert] reads the row, merges, and writes it back, and its callers are
  /// concurrent — `recordTranscript` is fired with `unawaited` at form submit
  /// while Step 3 records its summary timings. Interleaved, the later writer
  /// re-reads a row the earlier one had not yet written and restores the field
  /// it had just set. That is how a captured 162-character transcript reached
  /// the device and was never uploaded: Step 3 wrote the row back with the
  /// `null` transcript it had read a moment earlier.
  Future<void> _writes = Future<void>.value();

  /// Keeps [incoming] when it carries text, otherwise [existing].
  ///
  /// A capture point that has nothing to say for a field must leave what is
  /// already stored alone — every merge below only ever adds.
  static String? _prefer(String? incoming, String? existing) {
    final trimmed = incoming?.trim();
    return (trimmed == null || trimmed.isEmpty) ? existing : trimmed;
  }

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
        skUserId: userId,
        capturedTenantId: tenantId,
        uploadStatus: entry.uploadStatus,
        uploadedAt: entry.uploadedAt,
      );
      await _dao.upsert(entry);
    } on Object catch (e, st) {
      debugPrint('[VisitContent] capture dropped: $e');
      debugPrint('[VisitContent] $st');
    }
  }

  static int _maxInt(int a, int b) => a > b ? a : b;
}
