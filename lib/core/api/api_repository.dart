import 'api_client.dart';

/// Base class for data repositories that talk to the UHIS gateway through
/// [ApiClient]. Holds the shared HTTP plumbing — a checked POST and the common
/// list-envelope extraction — so concrete repositories carry only their own
/// domain mapping. This is the single home for those behaviors (they were
/// previously copy-pasted across the dashboard and search repositories).
abstract class ApiRepository {
  ApiRepository(this.api);

  final ApiClient api;

  /// POST [endpoint] and return the decoded body. Throws [ApiException] on any
  /// non-2xx status. [action] is a short human label used in the error message
  /// (e.g. `'Patient count'` → `'Patient count failed (500)'`).
  Future<dynamic> postOk(
    String endpoint, {
    Object? data,
    String? action,
  }) async {
    final resp = await api.dio.post(endpoint, data: data);
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw ApiException(action ?? endpoint, code);
    }
    return resp.data;
  }

  /// GET [endpoint] and return the decoded body. Throws [ApiException] on any
  /// non-2xx status. [action] is a short human label used in the error message.
  Future<dynamic> getOk(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    String? action,
  }) async {
    final resp = await api.dio.get(endpoint, queryParameters: queryParameters);
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw ApiException(action ?? endpoint, code);
    }
    return resp.data;
  }

  /// Pull the list payload out of the response shapes the services return:
  /// a bare `List`, a `{ entityList: [...] }`, or a `{ data: [...] }` envelope.
  List extractList(dynamic body) => extractListStatic(body);

  /// Static version of [extractList] for use outside of repositories.
  static List extractListStatic(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      if (body['entityList'] is List) return body['entityList'] as List;
      if (body['data'] is List) return body['data'] as List;
    }
    return const [];
  }
}

/// Typed domain exception for a failed API call. Replaces the generic
/// `Exception('X failed (code)')` literals the repositories used to throw.
class ApiException implements Exception {
  ApiException(this.action, this.statusCode);

  final String action;
  final int statusCode;

  @override
  String toString() => '$action failed ($statusCode)';
}
