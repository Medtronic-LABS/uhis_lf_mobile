import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One scripted response (or thrown error) per call; the last one repeats.
/// Records every request so tests can assert on headers / paths.
class ScriptedDioAdapter implements HttpClientAdapter {
  ScriptedDioAdapter(this._responses);

  final List<Future<ResponseBody> Function(RequestOptions)> _responses;
  final List<RequestOptions> requests = [];

  int get callCount => requests.length;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final index = requests.length < _responses.length
        ? requests.length
        : _responses.length - 1;
    requests.add(options);
    return _responses[index](options);
  }
}

ResponseBody jsonResponseBody(Object body, {int statusCode = 200}) =>
    ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: {
        'content-type': ['application/json; charset=utf-8'],
      },
    );

ResponseBody bytesResponseBody(
  List<int> bytes, {
  int statusCode = 200,
  String contentType = 'image/svg+xml',
  String? etag,
}) => ResponseBody.fromBytes(
  Uint8List.fromList(bytes),
  statusCode,
  headers: {
    'content-type': [contentType],
    if (etag != null) 'etag': [etag],
  },
);
