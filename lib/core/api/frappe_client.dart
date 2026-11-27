import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

/// Why a Frappe call failed, so callers can react without parsing messages.
enum FrappeErrorKind {
  /// No token on the device, or the server rejected it (401/403).
  unauthorized,

  /// Unknown resource (404).
  notFound,

  /// Per-user rate limit hit (429).
  rateLimited,

  /// Server-side LLM / configuration unavailable or the model output was
  /// unusable (417, 5xx).
  unavailable,

  /// The request never got a response (offline, DNS, timeout).
  network,

  /// A response arrived but not in the expected shape.
  badResponse,
}

class FrappeException implements Exception {
  const FrappeException(this.kind, this.message, {this.statusCode, this.cause});

  final FrappeErrorKind kind;
  final String message;
  final int? statusCode;

  /// The transport error behind this one, if any — lets callers keep their
  /// existing user messages and analytics (offline vs timeout) unchanged.
  final Object? cause;

  @override
  String toString() =>
      'FrappeException(${kind.name}${statusCode != null ? ', $statusCode' : ''}): $message';
}

/// Result of [FrappeClient.getBytes]. [bytes] is null on a 304.
typedef FrappeBytesResponse = ({int status, Uint8List? bytes, String? etag});

/// Transport for whitelisted methods on the `frappe-uhis-next` site.
///
/// Every call carries `X-Auth-Token: Bearer <jwt>` and `tenantId` — the
/// server's `remote_auth` check rejects a request missing either — and JSON
/// results are unwrapped from Frappe's `{"message": ...}` envelope.
class FrappeClient {
  FrappeClient({
    required String baseUrl,
    required this.authTokenProvider,
    this.tenantIdProvider,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(minutes: 2),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: connectTimeout,
               receiveTimeout: receiveTimeout,
             ),
           );

  final Future<String?> Function() authTokenProvider;
  final Future<String?> Function()? tenantIdProvider;
  final Dio _dio;

  /// Base URL requests are resolved against (for debug logging).
  String get baseUrl => _dio.options.baseUrl;

  /// POSTs [body] as JSON and returns the unwrapped `message` object.
  ///
  /// [receiveTimeout] overrides the client default for this call only.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Duration? receiveTimeout,
  }) => _post(path, body, receiveTimeout: receiveTimeout);

  /// POSTs [form] as `multipart/form-data` (e.g. a photo upload) and returns
  /// the unwrapped `message` object. Frappe passes the plain form fields to
  /// the whitelisted method as arguments and the file parts via
  /// `frappe.request.files`.
  Future<Map<String, dynamic>> postMultipart(
    String path,
    FormData form, {
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) => _post(
    path,
    form,
    sendTimeout: sendTimeout,
    receiveTimeout: receiveTimeout,
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Object body, {
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) async {
    final headers = await _authHeaders();
    try {
      final response = await _dio.post<dynamic>(
        path,
        data: body,
        options: Options(
          headers: headers,
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
        ),
      );
      return _unwrapMessage(response.data);
    } on DioException catch (e) {
      throw _mapDioError(e, path);
    }
  }

  /// GETs raw bytes (e.g. an image). Sends `If-None-Match` when [ifNoneMatch]
  /// is given; a 304 returns `bytes: null`.
  Future<FrappeBytesResponse> getBytes(
    String path, {
    String? ifNoneMatch,
  }) async {
    final headers = await _authHeaders();
    if (ifNoneMatch != null) headers['If-None-Match'] = ifNoneMatch;
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          validateStatus: (s) =>
              s != null && ((s >= 200 && s < 300) || s == 304),
        ),
      );
      final status = response.statusCode ?? 0;
      final etag = response.headers.value('etag');
      if (status == 304) return (status: status, bytes: null, etag: etag);
      final data = response.data;
      if (data == null) {
        throw FrappeException(
          FrappeErrorKind.badResponse,
          'Empty body from $path',
          statusCode: status,
        );
      }
      return (status: status, bytes: Uint8List.fromList(data), etag: etag);
    } on DioException catch (e) {
      throw _mapDioError(e, path);
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await authTokenProvider();
    if (token == null || token.isEmpty) {
      throw const FrappeException(
        FrappeErrorKind.unauthorized,
        'No auth token available for the Frappe call.',
      );
    }
    final headers = <String, String>{'X-Auth-Token': 'Bearer $token'};
    final tenantId = await tenantIdProvider?.call();
    if (tenantId != null && tenantId.isNotEmpty) {
      headers['tenantId'] = tenantId;
    }
    return headers;
  }

  Map<String, dynamic> _unwrapMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is Map<String, dynamic>) return message;
    }
    throw FrappeException(
      FrappeErrorKind.badResponse,
      'Expected {"message": {...}}, got ${body.runtimeType}',
    );
  }

  static FrappeException _mapDioError(DioException e, String path) {
    final status = e.response?.statusCode;
    if (status == null) {
      return FrappeException(
        FrappeErrorKind.network,
        e.message ?? 'Network error calling $path',
        cause: e,
      );
    }
    final kind = switch (status) {
      401 || 403 => FrappeErrorKind.unauthorized,
      404 => FrappeErrorKind.notFound,
      429 => FrappeErrorKind.rateLimited,
      417 || >= 500 => FrappeErrorKind.unavailable,
      _ => FrappeErrorKind.badResponse,
    };
    return FrappeException(
      kind,
      '$path failed ($status)',
      statusCode: status,
      cause: e,
    );
  }
}

/// Builds a [FrappeClient] for `spice_next_ai` on this app's own session —
/// same token-stripping / tenantId convention as `buildShukheeConsentClient`.
FrappeClient buildFrappeAiClient(ApiClient api, {required String baseUrl}) {
  return FrappeClient(
    baseUrl: baseUrl,
    authTokenProvider: () async {
      final raw = api.exportAuthToken();
      if (raw == null) return null;
      const prefix = 'Bearer ';
      return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
    },
    tenantIdProvider: () async => api.tenantId,
  );
}
