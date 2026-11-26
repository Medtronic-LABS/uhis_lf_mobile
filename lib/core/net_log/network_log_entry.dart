import 'url_sanitizer.dart';

/// One recorded network request, as stored in the `network_log` table.
///
/// Holds only sanitised, non-PHI fields (see the URL rule in the network log
/// design). [epoch] is runtime-only bookkeeping for the wipe race and is never
/// persisted.
class NetworkLogEntry {
  const NetworkLogEntry({
    required this.startedAtMs,
    required this.source,
    this.nativeId,
    required this.service,
    required this.method,
    required this.url,
    this.finalUrl,
    this.statusCode,
    this.durationMs,
    this.timing = 'total',
    this.attempt = 1,
    this.errorType,
    this.epoch = 0,
  });

  /// `'dart'` or `'native'`.
  final String source;
  final int startedAtMs;
  final int? nativeId;
  final String service;
  final String method;
  final String url;
  final String? finalUrl;
  final int? statusCode;
  final int? durationMs;

  /// `'total'`, `'headers'` or `'handshake'`.
  final String timing;
  final int attempt;
  final String? errorType;

  /// Recorder epoch captured when the request started. Not a DB column.
  final int epoch;

  /// Row map with [source] forced and every text field normalised, so a
  /// recorder or merge bug cannot persist tokens, query strings or raw
  /// exception text. The DAO is the single choke point that calls this.
  Map<String, Object?> toSanitizedDb({required String forcedSource}) => {
    ...toDb(),
    'source': forcedSource,
    'method': _token(method, RegExp(r'^[A-Za-z]{1,16}$'), 'UNKNOWN'),
    'service': _token(service, RegExp(r'^[a-z0-9-]{1,32}$'), 'other'),
    'url': UrlSanitizer.sanitize(url),
    'final_url': finalUrl == null ? null : UrlSanitizer.sanitize(finalUrl!),
    'timing': _timings.contains(timing) ? timing : 'total',
    'error_type': errorType == null
        ? null
        : (allowedErrorTypes.contains(errorType) ? errorType : 'unknown'),
  };

  /// The only error types ever persisted: the Dio exception names, the
  /// realtime WebSocket output and the SDK vocabulary. Anything else (for
  /// example a raw exception class name) is stored as `unknown`.
  static const Set<String> allowedErrorTypes = {
    'connectionTimeout',
    'sendTimeout',
    'receiveTimeout',
    'badCertificate',
    'badResponse',
    'cancel',
    'connectionError',
    'wsError',
    'unknown',
  };

  static const Set<String> _timings = {'total', 'headers', 'handshake'};

  static String _token(String v, RegExp allowed, String fallback) =>
      allowed.hasMatch(v) ? v : fallback;

  Map<String, Object?> toDb() => {
    'started_at_ms': startedAtMs,
    'source': source,
    'native_id': nativeId,
    'service': service,
    'method': method,
    'url': url,
    'final_url': finalUrl,
    'status_code': statusCode,
    'duration_ms': durationMs,
    'timing': timing,
    'attempt': attempt,
    'error_type': errorType,
  };

  factory NetworkLogEntry.fromDb(Map<String, Object?> r) => NetworkLogEntry(
    startedAtMs: r['started_at_ms'] as int,
    source: r['source'] as String,
    nativeId: r['native_id'] as int?,
    service: r['service'] as String,
    method: r['method'] as String,
    url: r['url'] as String,
    finalUrl: r['final_url'] as String?,
    statusCode: r['status_code'] as int?,
    durationMs: r['duration_ms'] as int?,
    timing: r['timing'] as String,
    attempt: r['attempt'] as int,
    errorType: r['error_type'] as String?,
  );
}
