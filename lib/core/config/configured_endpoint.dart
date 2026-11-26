/// One resolved base URL from `AppConfig`, with the config rule that produced it.
class ConfiguredEndpoint {
  const ConfiguredEndpoint({
    required this.service,
    required this.url,
    required this.rule,
  });

  /// Service label of the `API_BASE_URL` row; it supplies the gateway host.
  static const String gatewayService = 'api-gateway';

  final String service;
  final String url;
  final String rule;
}
