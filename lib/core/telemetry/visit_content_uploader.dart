import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';
import 'telemetry_upload_log.dart';
import 'visit_content_dao.dart';

/// Uploads the visit-content telemetry queue.
///
/// Separate from [TelemetryUploader] and [ValueAuditUploader] so product QA
/// content can be switched off independently. Never throws; failed batches stay
/// pending for the next sync.
class VisitContentUploader {
  VisitContentUploader(this._dao, this._client);

  final VisitContentDao _dao;
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
      return (direct, '/telemetry/visit-content');
    }
    return (_client.dio, Endpoints.telemetryVisitContent);
  }

  Future<int> uploadPending() async {
    if (!AppConfig.visitContentTelemetryEnabled) return 0;
    var accepted = 0;
    try {
      final before = await _dao.counts();
      if (before.pending > 0) {
        telemetryUploadLog(
            '[VisitContent] flush starting — ${before.pending} pending');
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
        telemetryUploadLog('[VisitContent] ${after.pending} row(s) STILL pending '
            '(accepted $accepted this pass)');
      } else if (accepted > 0) {
        telemetryUploadLog(
            '[VisitContent] queue drained — $accepted row(s) accepted');
      }
    } on Object catch (e) {
      telemetryUploadLog('[VisitContent] upload aborted: $e');
    }
    return accepted;
  }

  Future<List<String>?> _postBatch(List<Map<String, dynamic>> rows) async {
    final (dio, path) = _resolve();
    telemetryUploadLog(
      '[VisitContent] POST $path — posting ${rows.length} record(s)',
    );
    try {
      final res = await dio.post<dynamic>(path, data: {'entries': rows});
      final body = res.data;
      if (body is Map && body['acceptedIds'] is List) {
        final ids =
            (body['acceptedIds'] as List).map((e) => e.toString()).toList();
        telemetryUploadLog(
          '[VisitContent] POST $path — accepted ${ids.length}/${rows.length} '
          'record(s) (HTTP ${res.statusCode})',
        );
        return ids;
      }
      telemetryUploadLog('[VisitContent] unexpected response shape: $body');
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        telemetryUploadLog(
            '[VisitContent] POST $path — endpoint disabled (404), '
            '${rows.length} record(s) left pending');
      } else {
        telemetryUploadLog('[VisitContent] POST $path failed '
            '(HTTP ${e.response?.statusCode}, ${e.type.name}) — '
            '${rows.length} record(s) left pending');
      }
      return null;
    }
  }
}
