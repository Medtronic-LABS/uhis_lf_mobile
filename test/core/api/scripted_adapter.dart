import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Counts requests per path and replays a scripted outcome per attempt, so a
/// test can assert exactly how many times a request was issued. Replaces the
/// real adapter — no sockets, no mocking package needed.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.failuresBeforeSuccess);

  /// How many leading attempts fail, per path.
  final Map<String, int> failuresBeforeSuccess;

  /// Total attempts observed, per path.
  final Map<String, int> calls = <String, int>{};

  /// Status returned once a path stops failing.
  int successStatus = 200;

  /// Transport error thrown by a failing attempt, unless [failureStatus] is set.
  DioExceptionType failureType = DioExceptionType.receiveTimeout;

  /// When set, a failing attempt answers with this HTTP status instead of
  /// throwing [failureType].
  int? failureStatus;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final seen = (calls[path] ?? 0) + 1;
    calls[path] = seen;

    var status = successStatus;
    if (seen <= (failuresBeforeSuccess[path] ?? 0)) {
      final failing = failureStatus;
      if (failing == null) {
        throw DioException(requestOptions: options, type: failureType);
      }
      status = failing;
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
