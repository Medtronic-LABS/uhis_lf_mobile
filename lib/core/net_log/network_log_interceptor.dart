import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../api/request_extras.dart';
import '../config/app_config.dart';
import '../debug/console_log.dart';
import 'network_log_entry.dart';
import 'network_request_recorder.dart';
import 'service_classifier.dart';
import 'url_sanitizer.dart';

/// Records one [NetworkLogEntry] per Dio attempt.
///
/// Reads only the method, URL, status, redirect list, response type and error
/// type. It never touches headers, bodies, cookies or error messages, so
/// nothing sensitive can reach the recorder, and URLs are sanitised before
/// they leave this class.
class NetworkLogInterceptor extends Interceptor {
  NetworkLogInterceptor._(this._recorder, this._classifier);

  /// Adds the interceptor to [dio] unless it already has one.
  static void attach(
    Dio dio,
    NetworkRequestRecorder recorder, {
    ServiceClassifier? classifier,
  }) {
    if (dio.interceptors.any((i) => i is NetworkLogInterceptor)) return;
    dio.interceptors.add(NetworkLogInterceptor._(
      recorder,
      classifier ?? ServiceClassifier(AppConfig.configuredEndpoints),
    ));
  }

  /// `RequestOptions.extra` key holding the per-attempt [_Start].
  @visibleForTesting
  static const String startKey = 'netLogStart';

  final NetworkRequestRecorder _recorder;
  final ServiceClassifier _classifier;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Deliberately broad catch (here and in _record): the log is a
    // non-critical side effect on the live auth path, so no failure inside it,
    // Error or Exception, may fail or delay a request. Only the type is logged.
    try {
      options.extra[startKey] = _Start(
        stopwatch: Stopwatch()..start(),
        epoch: _recorder.epoch,
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } on Object catch (e) {
      options.extra.remove(startKey);
      ConsoleLog.warn('[NetworkLog] start failed: ${e.runtimeType}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _record(
      response.requestOptions,
      statusCode: response.statusCode,
      finalUri: response.redirects.isEmpty ? null : response.realUri,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final badResponse =
        err.type == DioExceptionType.badResponse && err.response != null;
    _record(
      err.requestOptions,
      statusCode: err.response?.statusCode,
      errorType: badResponse ? null : err.type.name,
    );
    handler.next(err);
  }

  void _record(
    RequestOptions options, {
    int? statusCode,
    Uri? finalUri,
    String? errorType,
  }) {
    try {
      final start = options.extra[startKey];
      if (start is! _Start) return;
      final url = UrlSanitizer.sanitize(options.uri.toString());
      _recorder.record(NetworkLogEntry(
        startedAtMs: start.startedAtMs,
        source: 'dart',
        service: _classifier.classify(url),
        method: options.method,
        url: url,
        finalUrl:
            finalUri == null ? null : UrlSanitizer.sanitize(finalUri.toString()),
        statusCode: statusCode,
        durationMs: start.stopwatch.elapsedMilliseconds,
        timing: options.responseType == ResponseType.stream ? 'headers' : 'total',
        attempt: (options.extra[kAttemptKey] as int?) ?? 1,
        errorType: errorType,
        epoch: start.epoch,
      ));
    } on Object catch (e) {
      ConsoleLog.warn('[NetworkLog] record failed: ${e.runtimeType}');
    }
  }
}

/// Per-attempt state captured in onRequest; one lookup, one type check.
class _Start {
  const _Start({
    required this.stopwatch,
    required this.epoch,
    required this.startedAtMs,
  });

  final Stopwatch stopwatch;
  final int epoch;
  final int startedAtMs;
}
