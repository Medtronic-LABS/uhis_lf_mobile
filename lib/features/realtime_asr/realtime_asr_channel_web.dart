import 'package:web_socket_channel/web_socket_channel.dart';

/// Web implementation — browsers do not allow a WebSocket client to set
/// custom handshake headers, so the Authorization/Cookie/tenantId auth this
/// API requires can't be carried on web. Real-time ASR is native-only.
const bool realtimeAsrSupported = false;

WebSocketChannel connectRealtimeChannel(Uri uri, Map<String, String> headers) {
  throw UnsupportedError(
    'Real-time ASR is not supported on Flutter web (no custom WebSocket '
    'handshake headers) — use the Android/iOS app.',
  );
}
