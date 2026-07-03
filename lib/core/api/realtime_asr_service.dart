import '../config/app_config.dart';
import 'api_client.dart';
import 'endpoints.dart';

/// Auth + connection details for `WS /scribe/realtime/transcribe`, resolved
/// from the shared [ApiClient] session the same way [ScribeApiService] does
/// for HTTP calls — see that class's `_scribeUrl` for the nginx-prefix /
/// [AppConfig.scribeBaseUrl] handling this mirrors.
class RealtimeAsrConnectionInfo {
  const RealtimeAsrConnectionInfo({
    required this.uri,
    required this.headers,
  });

  final Uri uri;
  final Map<String, String> headers;
}

/// Builds the WebSocket URI + auth headers for the live streaming ASR API.
///
/// Native platforms only (`IOWebSocketChannel` supports custom handshake
/// headers; browsers do not allow a WS client to set arbitrary headers, so
/// this is not usable on Flutter web — see RealtimeAsrController).
class RealtimeAsrService {
  RealtimeAsrService(this.api);

  final ApiClient api;

  static const String _nginxPrefix = '/ai-scribe';

  Future<RealtimeAsrConnectionInfo> connectionInfo({
    required String language,
    String model = 'saarika:v2.5',
  }) async {
    // Strip /ai-scribe prefix only when AI_SERVICE_URL targets the local
    // service directly. Through nginx the full path is required.
    final endpoint = Endpoints.scribeRealtimeTranscribe;
    final path = AppConfig.aiServiceBaseUrl.isNotEmpty &&
            endpoint.startsWith(_nginxPrefix)
        ? endpoint.substring(_nginxPrefix.length)
        : endpoint;

    final base = Uri.parse(AppConfig.scribeBaseUrl);
    final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';
    final uri = Uri(
      scheme: wsScheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: _joinPaths(base.path, path),
      queryParameters: {
        'language': language,
        'model': model,
        // Fallback for WS clients that can't set headers (kept for parity
        // with the server's authenticate_websocket, not used on native).
        if (api.tenantId != null) 'tenantId': api.tenantId!,
      },
    );

    final headers = <String, String>{};
    final token = api.exportAuthToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = token;
    }
    final cookies = await api.exportAuthCookies();
    final cookiePairs = <String>[
      if (cookies.jsession != null) 'JSESSIONID=${cookies.jsession}',
      if (cookies.authCookie != null) 'AuthCookie=${cookies.authCookie}',
    ];
    if (cookiePairs.isNotEmpty) {
      headers['Cookie'] = cookiePairs.join('; ');
    }
    if (api.tenantId != null) {
      headers['tenantId'] = api.tenantId!;
    }

    return RealtimeAsrConnectionInfo(uri: uri, headers: headers);
  }

  static String _joinPaths(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }
}
