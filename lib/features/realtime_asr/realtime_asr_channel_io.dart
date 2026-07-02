import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native (Android/iOS/desktop) implementation — `IOWebSocketChannel`
/// supports custom handshake headers, which is how auth is carried on
/// `/scribe/realtime/transcribe` (see RealtimeAsrService).
const bool realtimeAsrSupported = true;

WebSocketChannel connectRealtimeChannel(Uri uri, Map<String, String> headers) {
  return IOWebSocketChannel.connect(uri, headers: headers);
}
