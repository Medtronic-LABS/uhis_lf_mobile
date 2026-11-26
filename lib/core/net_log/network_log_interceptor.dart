import 'package:dio/dio.dart';

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

  static const String _stopwatchKey = 'netLogSw';
  static const String _epochKey = 'netLogEpoch';

  final NetworkRequestRecorder _recorder;
  final ServiceClassifier _classifier;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_stopwatchKey] = Stopwatch()..start();
    options.extra[_epochKey] = _recorder.epoch;
    options.extra[_startedKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  static const String _startedKey = 'netLogStartedMs';

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
    final sw = options.extra[_stopwatchKey];
    if (sw is! Stopwatch) return;
    try {
      final url = UrlSanitizer.sanitize(options.uri.toString());
      _recorder.record(NetworkLogEntry(
        startedAtMs: options.extra[_startedKey] as int,
        source: 'dart',
        service: _classifier.classify(url),
        method: options.method,
        url: url,
        finalUrl:
            finalUri == null ? null : UrlSanitizer.sanitize(finalUri.toString()),
        statusCode: statusCode,
        durationMs: sw.elapsedMilliseconds,
        timing: options.responseType == ResponseType.stream ? 'headers' : 'total',
        attempt: (options.extra[kAttemptKey] as int?) ?? 1,
        errorType: errorType,
        epoch: options.extra[_epochKey] as int? ?? 0,
      ));
    } on Exception catch (e) {
      ConsoleLog.warn('[NetworkLog] record failed: ${e.runtimeType}');
    }
  }
}
