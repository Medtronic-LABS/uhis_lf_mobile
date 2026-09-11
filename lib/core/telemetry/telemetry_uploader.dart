/// Pushes queued telemetry to ai-scribe-service and enforces retention.
///
/// Server side: `POST /ai-scribe/telemetry/events` (`app/api/telemetry.py`).
/// The server stamps `tenant_id` from the authenticated caller and upserts on
/// each event's client-generated id, so this can retry a batch freely.
///
/// The ordering rule that matters: a row is only ever marked uploaded when the
/// server has confirmed it, and [purgeUploaded] only ever deletes *uploaded*
/// rows. Anything else risks deleting data that never left the device — while
/// there is no other copy, this table is the system of record.
library;

import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';
import 'telemetry_dao.dart';
import 'telemetry_event.dart';
import 'telemetry_upload_log.dart';

/// How long an uploaded row is kept on device before being purged.
///
/// A month, so a report can still be regenerated locally for the recent past
/// after the server has the data.
const Duration kTelemetryRetention = Duration(days: 30);

/// Events per request. The server rejects batches over 500; staying under it
/// also keeps a single failed POST cheap to retry on a rural link.
const int kTelemetryBatchSize = 200;

class TelemetryUploader {
  const TelemetryUploader(this._dao, this._client);

  final TelemetryDao _dao;
  final ApiClient _client;

  /// Same gateway-vs-direct split as [VisitBriefingRepository]: with
  /// `--dart-define=AI_SERVICE_URL=...` requests go straight to the service
  /// without nginx's `/ai-scribe` prefix; otherwise through the gateway.
  (Dio, String) _resolve() {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));
      return (direct, '/telemetry/events');
    }
    return (_client.dio, Endpoints.telemetryEvents);
  }

  /// Uploads pending events in batches. Returns how many the server accepted.
  ///
  /// Never throws: telemetry is not worth failing a sync over. A batch that
  /// fails is left `pending` and simply retried on the next reconnect, and
  /// the loop stops at the first failure rather than hammering a dead link.
  Future<int> uploadPending() async {
    var accepted = 0;
    try {
      final before = await _dao.counts();
      if (before.pending > 0) {
        telemetryUploadLog('[Telemetry] flush starting — ${before.pending} pending '
            '(${before.total} rows held)');
      }
      while (true) {
        final batch = await _dao.pending(limit: kTelemetryBatchSize);
        if (batch.isEmpty) break;

        final ids = await _postBatch(batch);
        if (ids == null) break; // failed — leave them pending, try next time
        await _dao.markUploaded(ids);
        accepted += ids.length;

        // A short batch means the queue is drained.
        if (batch.length < kTelemetryBatchSize) break;
      }
      if (accepted > 0) await purgeUploaded();
      final after = await _dao.counts();
      if (after.pending > 0) {
        telemetryUploadLog('[Telemetry] ${after.pending} event(s) STILL pending after '
            'flush (accepted $accepted this pass)');
      } else if (accepted > 0) {
        telemetryUploadLog('[Telemetry] queue drained — $accepted event(s) accepted');
      }
    } on Object catch (e) {
      telemetryUploadLog('[Telemetry] upload aborted: $e');
    }
    return accepted;
  }

  /// POSTs one batch. Returns the ids the server confirmed, or null on failure.
  ///
  /// Reads `acceptedIds` from the response rather than assuming the whole
  /// batch landed. Duplicates are included there by design — a replay after a
  /// lost response inserts nothing but must still be marked uploaded, or the
  /// device would resend those rows forever.
  Future<List<String>?> _postBatch(List<TelemetryEvent> batch) async {
    final (dio, path) = _resolve();
    telemetryUploadLog(
      '[Telemetry] POST $path — posting ${batch.length} event(s)',
    );
    try {
      final res = await dio.post<dynamic>(path, data: {
        'events': [
          for (final e in batch)
            {
              'id': e.id,
              'eventType': e.eventType,
              'occurredAt': DateTime.fromMillisecondsSinceEpoch(
                e.occurredAt,
                isUtc: true,
              ).toIso8601String(),
              if (e.visitUuid != null) 'visitUuid': e.visitUuid,
              if (e.skUserId != null) 'skUserId': e.skUserId,
              if (e.capturedTenantId != null)
                'capturedTenantId': e.capturedTenantId,
              // Which AI feature produced the row. Sent explicitly rather
              // than left to the server's default so a future feature needs
              // no server change to be attributed correctly.
              'aiFeature': kTelemetryAiFeatureScribe,
              'appVersion': e.appVersion,
              'appBuild': e.appBuild,
              'payloadVersion': e.payloadVersion,
              'payload': e.payload,
            },
        ],
      });

      final body = res.data;
      if (body is! Map<String, dynamic>) {
        telemetryUploadLog(
            '[Telemetry] unexpected response type ${body.runtimeType}');
        return null;
      }
      final raw = body['acceptedIds'];
      if (raw is! List) {
        telemetryUploadLog('[Telemetry] response carried no acceptedIds — keeping '
            '${batch.length} event(s) pending');
        return null;
      }
      final ids = raw.map((e) => e.toString()).toList();
      telemetryUploadLog(
        '[Telemetry] POST $path — accepted ${ids.length}/${batch.length} '
        'record(s) (HTTP ${res.statusCode}, '
        'inserted=${body['inserted']}, duplicates=${body['duplicates']})',
      );
      return ids;
    } on DioException catch (e) {
      telemetryUploadLog('[Telemetry] POST $path failed '
          '(HTTP ${e.response?.statusCode}, ${e.type.name}) — '
          '${batch.length} event(s) left pending');
      return null;
    }
  }

  /// Enforces retention. Only ever deletes rows the server has accepted, so
  /// it is safe to call unconditionally.
  Future<int> purgeUploaded({Duration retain = kTelemetryRetention}) async {
    final removed = await _dao.purgeUploadedOlderThan(retain);
    if (removed > 0) {
      telemetryUploadLog('[Telemetry] purged $removed uploaded event(s) older than '
          '${retain.inDays}d');
    }
    return removed;
  }
}
