import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';
import 'assistant_content_dao.dart';
import 'telemetry_upload_log.dart';

/// Uploads the assistant-content telemetry queue.
///
/// Separate from the other uploaders so this PHI stream can be switched off
/// independently. Never throws; a failed batch stays pending for the next sync.
class AssistantContentUploader {
  AssistantContentUploader(this._dao, this._client);

  final AssistantContentDao _dao;
  final ApiClient _client;

  static const int batchSize = 50;

  (Dio, String) _resolve() {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));
      _client.attachAiServiceAuth(direct);
      return (direct, '/telemetry/assistant-content');
    }
    return (_client.dio, Endpoints.telemetryAssistantContent);
  }

  Future<int> uploadPending() async {
    if (!AppConfig.assistantContentTelemetryEnabled) return 0;
    var accepted = 0;
    try {
      final before = await _dao.counts();
      if (before.pending > 0) {
        telemetryUploadLog(
            '[AssistantContent] flush starting — ${before.pending} pending');
      }
      while (true) {
        final batch = await _dao.pending(limit: batchSize);
        if (batch.isEmpty) break;

        final ids =
            await _postBatch(batch.map((e) => e.toApiJson()).toList());
        if (ids == null) break;
        await _dao.markUploaded(ids);
        accepted += ids.length;

        if (batch.length < batchSize) break;
      }
      final after = await _dao.counts();
      if (after.pending > 0) {
        telemetryUploadLog(
            '[AssistantContent] ${after.pending} row(s) STILL pending '
            '(accepted $accepted this pass)');
      } else if (accepted > 0) {
        telemetryUploadLog(
            '[AssistantContent] queue drained — $accepted row(s) accepted');
      }
    } on Object catch (e) {
      telemetryUploadLog('[AssistantContent] upload aborted: $e');
    }
    return accepted;
  }

  Future<List<String>?> _postBatch(List<Map<String, dynamic>> rows) async {
    final (dio, path) = _resolve();
    telemetryUploadLog(
      '[AssistantContent] POST $path — posting ${rows.length} record(s)',
    );
    try {
      final res = await dio.post<dynamic>(path, data: {'entries': rows});
      final body = res.data;
      if (body is Map && body['acceptedIds'] is List) {
        final ids =
            (body['acceptedIds'] as List).map((e) => e.toString()).toList();
        telemetryUploadLog(
          '[AssistantContent] POST $path — accepted ${ids.length}/${rows.length} '
          'record(s) (HTTP ${res.statusCode})',
        );
        return ids;
      }
      telemetryUploadLog('[AssistantContent] unexpected response shape: $body');
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        telemetryUploadLog(
            '[AssistantContent] POST $path — endpoint disabled (404), '
            '${rows.length} record(s) left pending');
      } else {
        telemetryUploadLog('[AssistantContent] POST $path failed '
            '(HTTP ${e.response?.statusCode}, ${e.type.name}) — '
            '${rows.length} record(s) left pending');
      }
      return null;
    }
  }
}
