/// One resolved base URL from `AppConfig`, with the config rule that produced it.
class ConfiguredEndpoint {
  const ConfiguredEndpoint({
    required this.service,
    required this.url,
    required this.rule,
  });

  final String service;
  final String url;
  final String rule;
}

/// Labels a request URL with the backend service it targets.
///
/// [gatewayService] is the extra label of the configured-endpoints row for
/// `API_BASE_URL` itself. It supplies the gateway host for first-path-segment
/// matching and is never returned by [classify]; the page lists it as a normal
/// row. An `API_BASE_URL` carrying its own path prefix is not stripped before
/// first-segment matching, so such requests fall to `other`.
class ServiceClassifier {
  const ServiceClassifier(this.endpoints);

  /// Service label of the `API_BASE_URL` row; it supplies the gateway host.
  static const String gatewayService = 'api-gateway';
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

  String classify(String url) {
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
    final uri = Uri.tryParse(e.url);
    return uri != null && uri.hasAuthority ? uri : null;
  }

  String? _longestPrefixService(String url) {
    final gatewayEndpoint = _gatewayEndpoint();
    final gatewayUrl =
        gatewayEndpoint == null ? null : _trimSlash(gatewayEndpoint.url);
    String? service;
    var bestLength = -1;
    for (final e in endpoints) {
      final base = _trimSlash(e.url);
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

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}
