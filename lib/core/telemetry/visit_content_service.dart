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
        uploadStatus: existing?.uploadStatus ?? VisitContentUploadStatus.pending,
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
        uploadStatus: existing?.uploadStatus ?? VisitContentUploadStatus.pending,
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
        whatsappSummary: whatsappSummary?.trim().isEmpty == true
            ? null
            : whatsappSummary?.trim(),
        referralRecommendation: referralRecommendation?.trim().isEmpty == true
            ? null
            : referralRecommendation?.trim(),
        summaryEndAt: at,
        uploadStatus: existing?.uploadStatus ?? VisitContentUploadStatus.pending,
        uploadedAt: existing?.uploadedAt,
      ),
    );
  }

  Future<void> _upsert({
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
