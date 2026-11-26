import '../config/app_config.dart';
import '../config/configured_endpoint.dart';

export '../config/configured_endpoint.dart';

/// Labels a request URL with the backend service it targets.
///
/// [gatewayService] is the extra label of the configured-endpoints row for
/// `API_BASE_URL` itself. It supplies the gateway host for first-path-segment
/// matching and is never returned by [classify]; the page lists it as a normal
/// row. An `API_BASE_URL` carrying its own path prefix is not stripped before
/// first-segment matching, so such requests fall to `other`.
class ServiceClassifier {
  const ServiceClassifier(this.endpoints);

  /// Classifier over the endpoints resolved from `AppConfig`.
  factory ServiceClassifier.fromConfig() =>
      ServiceClassifier(AppConfig.configuredEndpoints);

  /// Service label of the `API_BASE_URL` row; it supplies the gateway host.
  static const String gatewayService = ConfiguredEndpoint.gatewayService;
  static const String otherHost = 'other-host';
  static const String other = 'other';

  static const Map<String, String> _segmentServices = {
    'auth-service': 'auth-service',
    'user-service': 'user-service',
    'spice-service': 'spice-service',
    'offline-service': 'offline-service',
    'fhir-server': 'fhir-server',
    'ai-scribe': 'ai-scribe',
    'ai-scribe-service': 'ai-scribe',
    'micro-coaching': 'micro-coaching',
    'admin-api': 'admin-api',
  };

  final List<ConfiguredEndpoint> endpoints;

  String classify(String rawUrl) {
    final url = _asHttp(rawUrl);
    final gateway = _gatewayUri();
    final prefixMatch = _longestPrefixService(url);
    if (prefixMatch != null) return prefixMatch;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority || gateway == null) return other;
    if (!_sameOrigin(uri, gateway)) return otherHost;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return other;
    return _segmentServices[segments.first] ?? other;
  }

  ConfiguredEndpoint? _gatewayEndpoint() {
    for (final e in endpoints) {
      if (e.service == gatewayService) return e;
    }
    return null;
  }

  Uri? _gatewayUri() {
    final e = _gatewayEndpoint();
    if (e == null) return null;
    final uri = Uri.tryParse(_asHttp(e.url));
    return uri != null && uri.hasAuthority ? uri : null;
  }

  String? _longestPrefixService(String url) {
    final gatewayEndpoint = _gatewayEndpoint();
    final gatewayUrl = gatewayEndpoint == null
        ? null
        : _trimSlash(_asHttp(gatewayEndpoint.url));
    String? service;
    var bestLength = -1;
    for (final e in endpoints) {
      final base = _trimSlash(_asHttp(e.url));
      if (e.service == gatewayService || base.isEmpty || base == gatewayUrl) {
        continue;
      }
      if (base.length > bestLength && _hasPrefix(url, base)) {
        service = e.service;
        bestLength = base.length;
      }
    }
    return service;
  }

  static bool _hasPrefix(String url, String base) {
    if (!url.startsWith(base)) return false;
    if (url.length == base.length) return true;
    final next = url[base.length];
    return next == '/' || next == '?' || next == '#';
  }

  /// A WebSocket handshake targets the same host as the HTTP API behind it
  /// (`wss` for `https`, `ws` for `http`), so compare them as one origin.
  static String _asHttp(String url) {
    if (url.startsWith('wss://')) return 'https://${url.substring(6)}';
    if (url.startsWith('ws://')) return 'http://${url.substring(5)}';
    return url;
  }

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}
