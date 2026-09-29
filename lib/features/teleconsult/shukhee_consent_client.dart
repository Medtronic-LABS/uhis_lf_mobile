import 'package:dio/dio.dart';

import '../../core/debug/console_log.dart';

/// Consent HTML content fetched live from the Shukhee/Frappe backend for the
/// pre-teleconsult consent gate -- see [ShukheeConsentClient].
class ShukheeConsentContent {
  const ShukheeConsentContent({required this.lng, required this.html});

  /// The language the backend actually served -- the server falls back to
  /// 'en' when the requested language isn't configured, so this may differ
  /// from the language [ShukheeConsentClient.fetchConsent] was asked for.
  final String lng;
  final String html;
}

/// Raised by [ShukheeConsentClient.fetchConsent] on any failure. Deliberately
/// never swallowed/returned as null -- the teleconsult consent gate is
/// compliance-sensitive: a fetch failure must block the call entirely and
/// show a retry action, never a cached/hardcoded fallback consent text (see
/// `TeleconsultConsentScreen`'s error state).
class ShukheeConsentException implements Exception {
  ShukheeConsentException(this.message);

  final String message;

  @override
  String toString() => 'ShukheeConsentException: $message';
}

/// Thin client for `shukhee_integration.api.consent.get_consent` --
/// deliberately its own small class rather than a new method on
/// `ShukheeClient` (from the pinned `shukhee_sdk` git dependency, whose fixed
/// API surface this app doesn't own) or on `ShukheeEncounterLinkClient`
/// (scoped to the encounter-attach endpoint, a different concern). Mirrors
/// `ShukheeEncounterLinkClient`'s constructor/header/unwrap shape.
///
/// Unlike `ShukheeEncounterLinkClient.attachFhirEncounterId` (best-effort,
/// swallows errors and returns `false`), [fetchConsent] always throws on
/// failure -- there is no safe fallback for compliance-sensitive consent
/// text, and the caller is expected to surface a retry action instead.
class ShukheeConsentClient {
  ShukheeConsentClient({
    required String baseUrl,
    required this.authTokenProvider,
    this.tenantIdProvider,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 15),
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: connectTimeout,
                receiveTimeout: receiveTimeout,
              ),
            );

  static const String consentPath =
      '/api/method/shukhee_integration.api.consent.get_consent';

  final Future<String?> Function() authTokenProvider;
  final Future<String?> Function()? tenantIdProvider;
  final Dio _dio;

  /// Fetches the consent HTML for [lng] ('en'/'bn'). Never caches -- callers
  /// (the online-gated "Call a doctor now" button) already guarantee
  /// connectivity at call time. Throws [ShukheeConsentException] on any
  /// failure -- do NOT catch and return a fallback here.
  Future<ShukheeConsentContent> fetchConsent({required String lng}) async {
    final headers = await _authHeaders();
    final body = {'lng': lng};
    ConsoleLog.banner('[PayloadDebug] teleconsult-consent\n$body');
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        consentPath,
        data: body,
        options: Options(headers: headers),
      );
    } catch (e) {
      ConsoleLog.warn('[PayloadDebug] teleconsult-consent error: $e');
      if (e is ShukheeConsentException) rethrow;
      throw ShukheeConsentException('Failed to fetch consent: $e');
    }
    ConsoleLog.step(
      '[PayloadDebug] teleconsult-consent -> ${response.statusCode}',
    );
    final data = _unwrapMessage(response.data);
    final html = data['consent'];
    final responseLng = data['lng'];
    if (html is! String || html.isEmpty) {
      throw ShukheeConsentException('Consent response missing "consent" HTML.');
    }
    return ShukheeConsentContent(
      lng: responseLng is String && responseLng.isNotEmpty ? responseLng : lng,
      html: html,
    );
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await authTokenProvider();
    if (token == null || token.isEmpty) {
      throw ShukheeConsentException('No auth token available to fetch consent.');
    }
    final headers = {'X-Auth-Token': 'Bearer $token'};
    final tenantId = await tenantIdProvider?.call();
    if (tenantId != null && tenantId.isNotEmpty) {
      headers['tenantId'] = tenantId;
    }
    return headers;
  }

  /// Frappe whitelisted methods wrap a returned dict as `{"message": {...}}`.
  Map<String, dynamic> _unwrapMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is Map<String, dynamic>) return message;
      return body;
    }
    return const {};
  }
}
