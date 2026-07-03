import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/db/ai_response_cache_dao.dart';
import 'programme_recommendation_models.dart';

/// Calls the unified leapfrog-ai-services Programme Recommendation endpoint.
///
/// Routing mirrors [VisitBriefingRepository]: when [AppConfig.aiServiceBaseUrl]
/// is set (dev `--dart-define=AI_SERVICE_URL=http://10.0.2.2:8095`), the call
/// goes direct to the local service. Otherwise it routes through the nginx
/// gateway at [Endpoints.programmeRecommendation].
///
/// Results are cached in SQLite via [AiResponseCacheDao]. Cache key is
/// `programme-reco:{patientId}` and the content_hash covers every field in
/// the request payload — so the SK editing the symptom set, the gender, the
/// current programme list, etc. invalidates the entry and the next entry to
/// Step 2 re-hits the API. Cache TTL defaults to 24 hours.
///
/// The service is fail-soft on the server side — when Gemini is unavailable
/// it falls back to a deterministic heuristic — so this repository surfaces
/// errors as exceptions without retry. The screen renders a localized
/// "unable to load" empty-state when this throws.
class ProgrammeRecommendationRepository {
  const ProgrammeRecommendationRepository(this._client,
      {AiResponseCacheDao? cache})
      : _cache = cache;

  final ApiClient _client;
  final AiResponseCacheDao? _cache;

  static const String _kind = 'programme-reco';

  (Dio, String) _resolve() {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 45),
      ));
      return (direct, '/programme-recommendation/recommend');
    }
    return (_client.dio, Endpoints.programmeRecommendation);
  }

  String _hashOf(Map<String, dynamic> req) =>
      jsonEncode(req).hashCode.toRadixString(16);

  String _cacheKeyFor(Map<String, dynamic> req) {
    final pid = (req['patientId'] as String?)?.trim() ?? 'unknown';
    return '$_kind:$pid';
  }

  Future<ProgrammeRecommendationResponse> recommend(
    Map<String, dynamic> request,
  ) async {
    final cacheKey = _cacheKeyFor(request);
    final hash = _hashOf(request);

    final cache = _cache;
    if (cache != null) {
      final cached = await cache.get(cacheKey, contentHash: hash);
      if (cached != null) {
        final decoded = jsonDecode(cached.payload) as Map<String, dynamic>;
        return ProgrammeRecommendationResponse.fromJson(decoded);
      }
    }

    final (dio, path) = _resolve();
    final response = await dio.post<dynamic>(path, data: request);
    final raw = response.data;
    if (raw is! Map<String, dynamic>) {
      // Server returned non-JSON (404 page, plain-text error, etc.)
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Expected JSON object, got ${raw.runtimeType}',
      );
    }
    final data = raw;

    if (cache != null) {
      await cache.put(
        cacheKey: cacheKey,
        kind: _kind,
        contentHash: hash,
        payload: jsonEncode(data),
      );
    }
    return ProgrammeRecommendationResponse.fromJson(data);
  }
}
