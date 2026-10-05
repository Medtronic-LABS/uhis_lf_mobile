import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/debug/console_log.dart';

/// Builds a [ShukheeConsentClient] wired to this app's own authenticated
/// session ([ApiClient]) -- same token-stripping/tenantId convention as
/// `shukhee_client_factory.dart`'s `buildShukheeClient`, kept here (rather
/// than there) since that file's own doc comment scopes it to building "the
/// app's one real `ShukheeClient`" (the `shukhee_sdk` client specifically),
/// not every Shukhee-family client. Shared by both
/// `TeleconsultConsentScreen` (fetching consent copy) and `TeleconsultScreen`
/// (attaching the accepted version to the resulting call) so the header-
/// building logic isn't duplicated between them.
ShukheeConsentClient buildShukheeConsentClient(BuildContext context) {
  final apiClient = context.read<ApiClient>();
  return ShukheeConsentClient(
    baseUrl: AppConfig.shukheeApiBaseUrl,
    authTokenProvider: () async {
      final raw = apiClient.exportAuthToken();
      if (raw == null) return null;
      const prefix = 'Bearer ';
      return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
    },
    tenantIdProvider: () async => apiClient.tenantId,
  );
}

/// Consent HTML content fetched live from the Shukhee/Frappe backend for the
/// pre-teleconsult consent gate -- see [ShukheeConsentClient].
class ShukheeConsentContent {
  const ShukheeConsentContent({
    required this.lng,
    required this.html,
    this.version,
  });

  /// The language the backend actually served -- the server falls back to
  /// 'en' when the requested language isn't configured, so this may differ
  /// from the language [ShukheeConsentClient.fetchConsent] was asked for.
  final String lng;
  final String html;

  /// The consent copy's version, echoed back by `get_consent` -- logged
  /// alongside the SK's Agree/Decline decision (see
  /// `TeleconsultConsentLogEntry.consentVersion`) so the audit trail records
  /// exactly which copy the patient saw. Null against a backend that hasn't
  /// been updated to return it yet.
  final String? version;
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
    final responseVersion = data['version'];
    if (html is! String || html.isEmpty) {
      throw ShukheeConsentException('Consent response missing "consent" HTML.');
    }
    return ShukheeConsentContent(
      lng: responseLng is String && responseLng.isNotEmpty ? responseLng : lng,
      html: html,
      version: responseVersion is String && responseVersion.isNotEmpty
          ? responseVersion
          : null,
    );
  }

  static const String attachConsentPath =
      '/api/method/shukhee_integration.api.consent.attach_consent_to_call';

  /// Denormalizes the accepted consent version/language onto the `Call Logs`
  /// row a successful booking just created -- called once from
  /// `TeleconsultScreen._submitBooking` right after `startConsultation`
  /// returns, since the consent gate runs before that row exists. Returns
  /// true once the backend confirms the attach. Returns false, never throws,
  /// on any failure (unknown `call_log`, network error, etc.) -- this is
  /// always best-effort and must never block or fail the booking flow it's
  /// called from, mirroring `ShukheeEncounterLinkClient.attachFhirEncounterId`.
  Future<bool> attachConsentToCall({
    required String callLog,
    String? consentVersion,
    required String lng,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await _dio.post<Map<String, dynamic>>(
        attachConsentPath,
        data: {
          'call_log': callLog,
          'consent_version': consentVersion,
          'lng': lng,
        },
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      return data['attached'] == true;
    } catch (_) {
      return false;
    }
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
