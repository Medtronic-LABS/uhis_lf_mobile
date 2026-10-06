import 'package:dio/dio.dart';

/// Thin client for `shukhee_integration.api.consultation.attach_fhir_encounter_id` --
/// deliberately its own small class rather than a new method on `ShukheeClient`
/// (from the pinned `shukhee_sdk` git dependency, whose fixed API surface this
/// app doesn't own) or on `CallLogSyncClient` (documented as intentionally
/// scoped to `spice_next_core`, not `shukhee_integration`, even though both
/// currently resolve to the same Frappe site/gateway).
///
/// Called once `OfflineSyncService`'s own assessment-history sync learns a
/// visit's server-assigned FHIR Encounter id, for any local Call Logs row
/// still missing one (see `CallLogHistoryDao.getPendingFhirAttach`) -- durably
/// attaches it server-side so the link survives a full local data wipe or a
/// new device, instead of depending on any client-side reconciliation state.
class ShukheeEncounterLinkClient {
  ShukheeEncounterLinkClient({
    required String baseUrl,
    required this.authTokenProvider,
    this.tenantIdProvider,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 15),
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: connectTimeout,
                receiveTimeout: receiveTimeout,
              ),
            );

  static const String attachPath =
      '/api/method/shukhee_integration.api.consultation.attach_fhir_encounter_id';

  final Future<String?> Function() authTokenProvider;
  final Future<String?> Function()? tenantIdProvider;
  final Dio _dio;

  /// Returns true once the backend confirms the attach (including a
  /// same-value repeat call -- see the endpoint's own idempotency doc
  /// comment). Returns false, never throws, on any failure (unknown
  /// `call_log`, network error, etc.) -- this is always a best-effort
  /// enrichment retried on the next sync pass, never something that should
  /// interrupt the sync it's called from.
  Future<bool> attachFhirEncounterId({
    required String callLog,
    required String fhirEncounterId,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await _dio.post<Map<String, dynamic>>(
        attachPath,
        data: {'call_log': callLog, 'fhir_encounter_id': fhirEncounterId},
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      return data['attached'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await authTokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('No auth token available to call attach_fhir_encounter_id.');
    }
    final headers = {'X-Auth-Token': 'Bearer $token'};
    final tenantId = await tenantIdProvider?.call();
    if (tenantId != null && tenantId.isNotEmpty) {
      headers['tenantId'] = tenantId;
    }
    return headers;
  }

  /// Frappe whitelisted methods wrap a returned dict as `{"message": {...}}`.
  Map<String, dynamic> _unwrapMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is Map<String, dynamic>) return message;
      return body;
    }
    return const {};
  }
}
