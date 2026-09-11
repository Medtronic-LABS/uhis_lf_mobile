import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';
import 'telemetry_upload_log.dart';
import 'value_audit_dao.dart';

/// Uploads the PHI value-audit queue.
///
/// A separate class from [TelemetryUploader], not a second method on it, so
/// the clinical-value path can be reasoned about — and switched off — on its
/// own. It has no purge: the table is wiped when a different SK signs in, and
/// that wipe is the device-side retention policy.
///
/// Same failure stance as telemetry: never throws, and a failed batch is left
/// pending for the next sync rather than dropped.
class ValueAuditUploader {
  ValueAuditUploader(this._dao, this._client);

  final ValueAuditDao _dao;
  final ApiClient _client;

  /// Rows per request. Smaller than the telemetry batch: each row carries two
  /// clinical values, so a request holds materially more than a counts-only
  /// telemetry event.
  static const int batchSize = 100;

  (Dio, String) _resolve() {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));
      return (direct, '/telemetry/value-audit');
    }
    return (_client.dio, Endpoints.telemetryValueAudit);
  }

  /// Uploads pending pairs in batches. Returns how many the server accepted.
  Future<int> uploadPending() async {
    if (!AppConfig.valueAuditEnabled) return 0;
    var accepted = 0;
    try {
      final before = await _dao.counts();
      if (before.pending > 0) {
        telemetryUploadLog(
            '[ValueAudit] flush starting — ${before.pending} pending');
      }
      while (true) {
        final batch = await _dao.pending(limit: batchSize);
        if (batch.isEmpty) break;

        final ids = await _postBatch(batch.map((e) => e.toApiJson()).toList());
        if (ids == null) break; // left pending, retried next sync
        await _dao.markUploaded(ids);
        accepted += ids.length;

        if (batch.length < batchSize) break;
      }
      final after = await _dao.counts();
      if (after.pending > 0) {
        telemetryUploadLog('[ValueAudit] ${after.pending} pair(s) STILL pending '
            '(accepted $accepted this pass)');
      } else if (accepted > 0) {
        telemetryUploadLog(
            '[ValueAudit] queue drained — $accepted pair(s) accepted');
      }
    } on Object catch (e) {
      telemetryUploadLog('[ValueAudit] upload aborted: $e');
    }
    return accepted;
  }

  /// POSTs one batch. Returns the ids the server confirmed, or null on failure.
  ///
  /// A 404 means the deployment has value audit switched off. That is a
  /// configuration answer, not an error to retry forever — the rows stay
  /// pending and are cleared by the next SK-handover wipe.
  Future<List<String>?> _postBatch(List<Map<String, dynamic>> rows) async {
    final (dio, path) = _resolve();
    telemetryUploadLog(
      '[ValueAudit] POST $path — posting ${rows.length} record(s)',
    );
    try {
      final res = await dio.post<dynamic>(path, data: {'entries': rows});
      final body = res.data;
      if (body is Map && body['acceptedIds'] is List) {
        final ids =
            (body['acceptedIds'] as List).map((e) => e.toString()).toList();
        telemetryUploadLog(
          '[ValueAudit] POST $path — accepted ${ids.length}/${rows.length} '
          'record(s) (HTTP ${res.statusCode})',
        );
        return ids;
      }
      telemetryUploadLog('[ValueAudit] unexpected response shape: $body');
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        telemetryUploadLog(
            '[ValueAudit] POST $path — endpoint disabled (404), '
            '${rows.length} record(s) left pending');
      } else {
        telemetryUploadLog('[ValueAudit] POST $path failed '
            '(HTTP ${e.response?.statusCode}, ${e.type.name}) — '
            '${rows.length} record(s) left pending');
      }
      return null;
    }
  }
}
