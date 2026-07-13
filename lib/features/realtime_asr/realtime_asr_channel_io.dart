import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native (Android/iOS/desktop) implementation — `IOWebSocketChannel`
/// supports custom handshake headers, which is how auth is carried on
/// `/scribe/realtime/transcribe` (see RealtimeAsrService).
const bool realtimeAsrSupported = true;

WebSocketChannel connectRealtimeChannel(Uri uri, Map<String, String> headers) {
  // Android ≤ 7.1 doesn't trust ISRG Root X1 (Let's Encrypt post-2021 chain).
  // In debug builds, bypass cert verification so engineers can test on older
  // hardware. Release builds always enforce full certificate verification.
  final HttpClient? client = kDebugMode
      ? (HttpClient()
          ..badCertificateCallback = (cert, host, port) => true)
      : null;
  return IOWebSocketChannel.connect(uri, headers: headers, customClient: client);
}
