/// Emit API for AI assistant ("Ask") PHI content telemetry.
///
/// Same contract as [TelemetryService]: never throws, never blocks the chat.
/// One row per chatbot turn, written once when the answer arrives (unlike the
/// multi-stage visit-content capture, an assistant turn is complete in one go).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import 'assistant_content_dao.dart';
import 'assistant_content_entry.dart';

class AssistantContentService {
  AssistantContentService({
    required AssistantContentDao dao,
    required Future<int?> Function() userIdResolver,
    Future<int?> Function()? tenantIdResolver,
    Uuid uuid = const Uuid(),
  })  : _dao = dao,
        _userIdResolver = userIdResolver,
        _tenantIdResolver = tenantIdResolver,
        _uuid = uuid;

  final AssistantContentDao _dao;
  final Future<int?> Function() _userIdResolver;
  final Future<int?> Function()? _tenantIdResolver;
  final Uuid _uuid;

  /// Records one chatbot turn's question + answer text, keyed by [correlator]
  /// (the same id carried on the assistant_ask telemetry event).
  Future<void> recordAsk({
    required String correlator,
    required String question,
    required String answer,
    String? patientId,
    String? appLanguage,
    DateTime? occurredAt,
  }) async {
    if (!AppConfig.assistantContentTelemetryEnabled) return;
    try {
      final at = (occurredAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
      final userId = (await _userIdResolver())?.toString();
      final tenantId = await _tenantIdResolver?.call();
      await _dao.upsert(AssistantContentEntry(
        id: _uuid.v4(),
        correlator: correlator,
        patientId: patientId,
        question: question.trim().isEmpty ? null : question.trim(),
        answer: answer.trim().isEmpty ? null : answer.trim(),
        appLanguage: appLanguage,
        skUserId: userId,
        capturedTenantId: tenantId,
        occurredAt: at,
      ));
    } on Object catch (e, st) {
      debugPrint('[AssistantContent] capture dropped: $e');
      debugPrint('[AssistantContent] $st');
    }
  }
}
