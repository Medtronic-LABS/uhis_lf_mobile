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

/// A single checkbox item shown below the consent body -- `get_consent` returns these
/// as a structured list so the app renders real checkboxes instead of embedding
/// "[ ] ..." text inside the consent HTML itself. [mandatory] items must all be ticked
/// before the SK/patient can proceed (Agree); optional ones never block proceeding.
class ConsentItem {
  const ConsentItem({required this.description, required this.mandatory});

  factory ConsentItem.fromJson(Map<String, dynamic> json) => ConsentItem(
        description: json['description'] as String? ?? '',
        mandatory: json['mandatory'] == true,
      );

  final String description;
  final bool mandatory;
}

/// Consent HTML content fetched live from the Shukhee/Frappe backend for the
/// pre-teleconsult consent gate -- see [ShukheeConsentClient].
class ShukheeConsentContent {
  const ShukheeConsentContent({
    required this.lng,
    required this.html,
    this.version,
    this.versionId,
    this.items = const [],
  });

  /// The language the backend actually served -- the server falls back to
  /// 'en' when the requested language isn't configured, so this may differ
  /// from the language [ShukheeConsentClient.fetchConsent] was asked for.
  final String lng;
  final String html;

  /// The consent copy's version label, echoed back by `get_consent` -- logged
  /// alongside the SK's Agree/Decline decision (see
  /// `TeleconsultConsentLogEntry.consentVersion`) so the audit trail is
  /// human-readable without following a link. Null against a backend that
  /// hasn't been updated to return it yet.
  final String? version;

  /// The `Shukhee Consent Version` snapshot row backing this exact response --
  /// must be carried forward unchanged (never re-derived later) and echoed back
  /// via `start_consultation` (Agree -- see `TeleconsultScreen._submitBooking`)
  /// or `record_consent_decline` (Decline), since the live `Shukhee Consent`
  /// row this was fetched from may be edited again before either of those
  /// calls happens. Null against a backend that hasn't been updated to return
  /// it yet.
  final String? versionId;

  /// The structured checkbox list rendered below the consent body (see [ConsentItem]).
  /// Which ones get ticked is echoed back positionally via `start_consultation`'s
  /// `items_checked` on Agree -- empty against a backend that hasn't been updated to
  /// return this yet, in which case no checkboxes render at all (matches the gate's own
  /// fail-closed posture: nothing to tick, nothing blocks Agree).
  final List<ConsentItem> items;
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
    final responseVersionId = data['version_id'];
    final responseItems = data['items'];
    if (html is! String || html.isEmpty) {
      throw ShukheeConsentException('Consent response missing "consent" HTML.');
    }
    return ShukheeConsentContent(
      lng: responseLng is String && responseLng.isNotEmpty ? responseLng : lng,
      html: html,
      version: responseVersion is String && responseVersion.isNotEmpty
          ? responseVersion
          : null,
      versionId: _asNonEmptyString(responseVersionId),
      items: responseItems is List
          ? responseItems
              .whereType<Map<String, dynamic>>()
              .map(ConsentItem.fromJson)
              .toList(growable: false)
          : const [],
    );
  }

  /// Shukhee Consent Version's name is an autoincrement doctype id -- Frappe's JSON
  /// layer normally serializes that as a string like every other Link value, but this
  /// accepts a bare number too rather than silently dropping a valid id over a type
  /// quirk.
  static String? _asNonEmptyString(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is num) return value.toString();
    return null;
  }

  static const String declinePath =
      '/api/method/shukhee_integration.api.consent.record_consent_decline';

  /// Records a Decline of the teleconsult consent gate -- the only server-side
  /// record a decline gets, since declining never leads to booking (no Call
  /// Logs row for an Agreed decision to be embedded on instead -- see
  /// `api.consultation.start_consultation`'s own doc comment on that side).
  /// Called once, immediately, from `TeleconsultConsentScreen._decide` when
  /// the SK taps Decline -- fire-and-forget, with no local queue/retry behind
  /// it (an offline decline is simply lost, an accepted gap -- declining
  /// itself has no connectivity requirement, so there's nothing else to
  /// gate it on). Never throws; returns true once the backend confirms the
  /// row was logged, false on any failure.
  Future<bool> recordDecline({
    required String patientId,
    String? visitId,
    required String lng,
    String? versionId,
    String? patientDob,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await _dio.post<Map<String, dynamic>>(
        declinePath,
        data: {
          'patient_id': patientId,
          'visit_id': visitId,
          'lng': lng,
          'version_id': versionId,
          'patient_dob': patientDob,
        },
        options: Options(headers: headers),
      );
      final data = _unwrapMessage(response.data);
      return data['logged'] == true;
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
