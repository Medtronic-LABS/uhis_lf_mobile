import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';
import 'teleconsult_consent_log_dao.dart';
import 'telemetry_upload_log.dart';

/// Uploads the teleconsult-consent decision queue.
///
/// Unlike [AssistantContentUploader] (which posts to ai-scribe-service via
/// [ApiClient]'s own authenticated Dio), this posts to the Shukhee/Frappe
/// backend ([AppConfig.shukheeApiBaseUrl]) with that backend's own
/// `X-Auth-Token`/`tenantId` header convention -- the same one
/// `ShukheeConsentClient`/`ShukheeEncounterLinkClient` use -- since the
/// consent copy and the decision it audits both live on that side. Never
/// throws; a failed batch stays pending for the next flush.
class TeleconsultConsentLogUploader {
  /// [dio] is a test seam -- mirrors `ShukheeConsentClient`'s own optional
  /// `Dio?` constructor param -- so tests can fake the Shukhee HTTP
  /// boundary without a real network. Production always lets it default.
  TeleconsultConsentLogUploader(this._dao, this._client, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.shukheeApiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  final TeleconsultConsentLogDao _dao;
  final ApiClient _client;
  final Dio _dio;

  static const int batchSize = 50;

  Future<int> uploadPending() async {
    var accepted = 0;
    try {
      final before = await _dao.counts();
      if (before.pending > 0) {
        telemetryUploadLog('[TeleconsultConsentLog] flush starting — '
            '${before.pending} pending');
      }
      while (true) {
        final batch = await _dao.pending(limit: batchSize);
        if (batch.isEmpty) break;

        // record_consent_decision is a single-record endpoint (it inserts
        // exactly one Shukhee Consent Log row per call, per the plan/backend
        // implementation) -- unlike AssistantContentUploader's endpoint,
        // there is no `{"entries": [...]}` batch variant to post to, so each
        // pending row gets its own request. Stop at the first failure and
        // leave the rest pending for the next flush, same conservative
        // posture as the batch uploaders.
        var postedAny = false;
        for (final entry in batch) {
          final ok = await _postOne(entry.toApiJson());
          if (!ok) break;
          await _dao.markUploaded([entry.id]);
          accepted += 1;
          postedAny = true;
        }
        if (!postedAny || batch.length < batchSize) break;
      }
      final after = await _dao.counts();
      if (after.pending > 0) {
        telemetryUploadLog(
            '[TeleconsultConsentLog] ${after.pending} row(s) STILL pending '
            '(accepted $accepted this pass)');
      } else if (accepted > 0) {
        telemetryUploadLog(
            '[TeleconsultConsentLog] queue drained — $accepted row(s) accepted');
      }
    } on Object catch (e) {
      telemetryUploadLog('[TeleconsultConsentLog] upload aborted: $e');
    }
    return accepted;
  }

  /// Same header convention as `ShukheeConsentClient`/
  /// `ShukheeEncounterLinkClient`: [ApiClient.exportAuthToken] already stores
  /// the full `Bearer <token>` value, so it's stripped and re-prefixed onto
  /// `X-Auth-Token` rather than assumed bare.
  Map<String, String> _authHeaders() {
    final headers = <String, String>{};
    final raw = _client.exportAuthToken();
    if (raw != null && raw.isNotEmpty) {
      const prefix = 'Bearer ';
      final bare = raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
      headers['X-Auth-Token'] = 'Bearer $bare';
    }
    final tenantId = _client.tenantId;
    if (tenantId != null && tenantId.isNotEmpty) {
      headers['tenantId'] = tenantId;
    }
    return headers;
  }

  /// Posts one row to `record_consent_decision` -- a single-record endpoint
  /// (see [TeleconsultConsentLogEntry.toApiJson]'s doc comment), not a batch
  /// ingest. Returns whether the server accepted it.
  Future<bool> _postOne(Map<String, dynamic> row) async {
    const path = Endpoints.shukheeRecordConsentDecision;
    try {
      final res = await _dio.post<dynamic>(
        path,
        data: row,
        options: Options(headers: _authHeaders()),
      );
      // Frappe wraps a whitelisted method's return dict as
      // {"message": {...}} -- same unwrap ShukheeConsentClient applies to
      // get_consent's response.
      final body = res.data;
      final message = body is Map && body['message'] is Map
          ? body['message'] as Map
          : body;
      if (message is Map && message['logged'] == true) {
        telemetryUploadLog(
            '[TeleconsultConsentLog] POST $path — accepted (HTTP ${res.statusCode})');
        return true;
      }
      telemetryUploadLog(
          '[TeleconsultConsentLog] unexpected response shape: $body');
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        telemetryUploadLog(
            '[TeleconsultConsentLog] POST $path — endpoint disabled (404), '
            'record left pending');
      } else {
        telemetryUploadLog('[TeleconsultConsentLog] POST $path failed '
            '(HTTP ${e.response?.statusCode}, ${e.type.name}) — '
            'record left pending');
      }
      return false;
    }
  }
}
