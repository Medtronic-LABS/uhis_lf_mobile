import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/db/ai_response_cache_dao.dart';
import 'briefing_models.dart';

/// Calls the AI visit briefing service to generate pre-visit guidance cards.
///
/// When [AppConfig.aiServiceBaseUrl] is non-empty (set via --dart-define
/// AI_SERVICE_URL=http://10.0.2.2:8096), requests go directly to the local
/// service without the nginx prefix. Otherwise they route through the gateway.
///
/// Results are cached in SQLite via [AiResponseCacheDao] when available so
/// re-opening the same visit / patient on the same day does not re-hit the
/// API. Cache TTL defaults to 24 hours; content_hash bumps when the input
/// payload changes so a stale entry is never served against a different
/// patient snapshot.
class VisitBriefingRepository {
  const VisitBriefingRepository(this._client, {AiResponseCacheDao? cache})
      : _cache = cache;

  final ApiClient _client;
  final AiResponseCacheDao? _cache;

  // Cache namespace — bump when the API response shape changes so rows
  // written by the old client are ignored. Last bump: invalidate DEV_SKIP_AUTH
  // mock responses cached while the backend ignored client-supplied context.
  static const String _kindBriefing = 'visit-briefing.v4';
  static const String _kindSummary = 'patient-summary.v3';

  /// Returns the Dio instance and path pair to use for a given remote path.
  (Dio, String) _resolve(String gatewayPath, String directPath) {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(minutes: 1),
      ));
      return (direct, directPath);
    }
    return (_client.dio, gatewayPath);
  }

  String _hashOf(Map<String, dynamic> ctx) =>
      jsonEncode(ctx).hashCode.toRadixString(16);

  String _cacheKeyFor(String kind, Map<String, dynamic> ctx) {
    final pid = (ctx['patientId'] as String?)?.trim() ?? 'unknown';
    return '$kind:$pid';
  }

  Future<VisitBriefingResponse> generate(Map<String, dynamic> patientContext) async {
    final cacheKey = _cacheKeyFor(_kindBriefing, patientContext);
    final hash = _hashOf(patientContext);

    // Cache hit short-circuits the API call. Mismatched hash → API; the DAO
    // drops the stale row automatically.
    final cache = _cache;
    if (cache != null) {
      final cached = await cache.get(cacheKey, contentHash: hash);
      if (cached != null) {
        final decoded = jsonDecode(cached.payload) as Map<String, dynamic>;
        return VisitBriefingResponse.fromJson(decoded);
      }
    }

    final (dio, path) = _resolve(
      Endpoints.visitBriefingGenerate,
      '/briefing/generate',
    );
    final response = await dio.post<Map<String, dynamic>>(path, data: patientContext);
    final data = response.data ?? const <String, dynamic>{};

    if (cache != null) {
      await cache.put(
        cacheKey: cacheKey,
        kind: _kindBriefing,
        contentHash: hash,
        payload: jsonEncode(data),
      );
    }
    return VisitBriefingResponse.fromJson(data);
  }

  /// Short 2-3 sentence summary for the patient context screen header.
  Future<String> summary(Map<String, dynamic> patientContext) async {
    final cacheKey = _cacheKeyFor(_kindSummary, patientContext);
    final hash = _hashOf(patientContext);

    final cache = _cache;
    if (cache != null) {
      final cached = await cache.get(cacheKey, contentHash: hash);
      if (cached != null) {
        final decoded = jsonDecode(cached.payload) as Map<String, dynamic>;
        return (decoded['summary'] as String?) ?? '';
      }
    }

    final (dio, path) = _resolve(
      Endpoints.visitBriefingSummary,
      '/briefing/summary',
    );
    final response = await dio.post<Map<String, dynamic>>(path, data: patientContext);
    final data = response.data ?? const <String, dynamic>{};

    if (cache != null) {
      await cache.put(
        cacheKey: cacheKey,
        kind: _kindSummary,
        contentHash: hash,
        payload: jsonEncode(data),
      );
    }
    return (data['summary'] as String?) ?? '';
  }
}
