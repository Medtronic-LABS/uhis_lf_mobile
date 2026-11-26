import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/debug/console_log.dart';
import '../../core/net_log/network_log_entry.dart';
import '../../core/net_log/network_request_recorder.dart';
import '../../core/net_log/service_classifier.dart';
import '../../core/net_log/url_sanitizer.dart';

/// Native (Android/iOS/desktop) implementation — `IOWebSocketChannel`
/// supports custom handshake headers, which is how auth is carried on
/// `/scribe/realtime/transcribe` (see RealtimeAsrService).
const bool realtimeAsrSupported = true;

WebSocketChannel connectRealtimeChannel(
  Uri uri,
  Map<String, String> headers, {
  NetworkRequestRecorder? recorder,
  @visibleForTesting
  WebSocketChannel Function(Uri uri, Map<String, String> headers)? connect,
  @visibleForTesting ServiceClassifier? classifier,
}) {
  // Android ≤ 7.1 doesn't trust ISRG Root X1 (Let's Encrypt post-2021 chain).
  // In debug builds, bypass cert verification so engineers can test on older
  // hardware. Release builds always enforce full certificate verification.
  final HttpClient? client = kDebugMode
      ? (HttpClient()
          ..badCertificateCallback = (cert, host, port) => true)
      : null;
  final channel = connect != null
      ? connect(uri, headers)
      : IOWebSocketChannel.connect(uri, headers: headers, customClient: client);
  if (recorder != null) _observeHandshake(channel, uri, recorder, classifier);
  return channel;
}

/// Records one row when the handshake settles. Only observes `ready`: both
/// branches are handled here so no error escapes, while the channel's own
/// `ready` future still delivers the original error to its other listeners.
void _observeHandshake(
  WebSocketChannel channel,
  Uri uri,
  NetworkRequestRecorder recorder,
  ServiceClassifier? classifier,
) {
  // Deliberately broad catches: logging must never affect the connection.
  final int epoch;
  final int startedAtMs;
  final Stopwatch stopwatch;
  try {
    epoch = recorder.epoch;
    startedAtMs = DateTime.now().millisecondsSinceEpoch;
    stopwatch = Stopwatch()..start();
  } on Object catch (e) {
    ConsoleLog.warn('[NetworkLog] ws start failed: ${e.runtimeType}');
    return;
  }

  void record({int? statusCode, String? errorType}) {
    try {
      final url = UrlSanitizer.sanitize(uri.toString());
      recorder.record(NetworkLogEntry(
        startedAtMs: startedAtMs,
        source: 'dart',
        service: (classifier ?? ServiceClassifier.fromConfig()).classify(url),
        method: 'WS',
        url: url,
        statusCode: statusCode,
        durationMs: stopwatch.elapsedMilliseconds,
        timing: 'handshake',
        attempt: 1,
        errorType: errorType,
        epoch: epoch,
      ));
    } on Object catch (e) {
      ConsoleLog.warn('[NetworkLog] ws record failed: ${e.runtimeType}');
    }
  }

  channel.ready.then(
    (_) => record(statusCode: 101),
    onError: (Object e) => record(errorType: _errorType(e)),
  );
}

String _errorType(Object e) {
  if (e is WebSocketChannelException) return 'wsError';
  if (e is SocketException) return 'connectionError';
  if (e is HandshakeException) return 'badCertificate';
  if (e is TimeoutException) return 'connectionTimeout';
  return 'unknown';
}
