import 'package:dio/dio.dart';

/// One row of `spice_next_core.api.sync.pull`'s response -- deliberately not
/// scoped to Call Logs alone: a single page legitimately interleaves rows
/// from every doctype in `_SYNCABLE_DOCTYPES` (Patient/Household/Case/
/// Encounter/Observation/Condition/Referral/Task/Call Logs), sorted together
/// by the shared global `sync_seq` cursor. Callers filter to the doctype(s)
/// they own.
class SyncChange {
  const SyncChange({
    required this.doctype,
    required this.name,
    required this.syncSeq,
    required this.deleted,
    required this.doc,
  });

  final String doctype;
  final String name;
  final int syncSeq;
  final bool deleted;
  final Map<String, dynamic> doc;

  static SyncChange fromJson(Map<String, dynamic> json) => SyncChange(
        doctype: json['doctype'] as String,
        name: json['name'].toString(),
        syncSeq: json['sync_seq'] as int,
        deleted: json['deleted'] as bool? ?? false,
        doc: (json['doc'] as Map<String, dynamic>?) ?? const {},
      );
}

class SyncPullPage {
  const SyncPullPage({
    required this.contractVersion,
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  final int contractVersion;
  final List<SyncChange> changes;
  final int nextCursor;
  final bool hasMore;

  static SyncPullPage fromJson(Map<String, dynamic> json) => SyncPullPage(
        contractVersion: json['contract_version'] as int? ?? 1,
        changes: (json['changes'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SyncChange.fromJson)
            .toList(),
        nextCursor: json['next_cursor'] as int? ?? 0,
        hasMore: json['has_more'] as bool? ?? false,
      );
}

class CallLogSyncException implements Exception {
  const CallLogSyncException(this.message);
  final String message;

  @override
  String toString() => 'CallLogSyncException: $message';
}

/// HTTP client for `spice_next_core.api.sync.pull` -- the platform's generic,
/// cursor-based, catchment-scoped sync mechanism (the same one Patient/
/// Household/Case/Encounter/etc. already use), consumed here for the first
/// time from this app to pull a patient's Shukhee call/prescription/
/// clinicalData history (`Call Logs`, added to the doctype allowlist
/// server-side -- pull-only, no push support). Mirrors `shukhee_sdk`'s
/// `ShukheeClient` shape (self-contained internal [Dio], same auth header
/// convention) but is deliberately independent of it -- this hits a
/// different Frappe app (`spice_next_core`, not `shukhee_integration`) and
/// has nothing Shukhee-specific about its own transport layer.
class CallLogSyncClient {
  CallLogSyncClient({
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

  static const String pullPath = '/api/method/spice_next_core.api.sync.pull';

  final Future<String?> Function() authTokenProvider;
  final Future<String?> Function()? tenantIdProvider;
  final Dio _dio;

  Future<SyncPullPage> pull({required int cursor, int limit = 200}) async {
    final headers = await _authHeaders();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        pullPath,
        data: {'contract_version': 1, 'cursor': cursor, 'limit': limit},
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      return SyncPullPage.fromJson(data);
    } on DioException catch (e) {
      throw CallLogSyncException(
        e.response != null
            ? 'sync.pull failed (${e.response!.statusCode}): ${e.message}'
            : e.message ?? 'Network error contacting spice_next_core.api.sync.pull.',
      );
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await authTokenProvider();
    if (token == null || token.isEmpty) {
      throw const CallLogSyncException('No auth token available to call sync.pull.');
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
    throw const CallLogSyncException('Unexpected response shape from sync.pull.');
  }
}
