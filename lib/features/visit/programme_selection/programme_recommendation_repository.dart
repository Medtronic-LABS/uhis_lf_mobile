import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import 'programme_recommendation_models.dart';

/// Calls the unified leapfrog-ai-services Programme Recommendation endpoint.
///
/// Routing mirrors [VisitBriefingRepository]: when [AppConfig.aiServiceBaseUrl]
/// is set (dev `--dart-define=AI_SERVICE_URL=http://10.0.2.2:8095`), the call
/// goes direct to the local service. Otherwise it routes through the nginx
/// gateway at [Endpoints.programmeRecommendation].
///
/// The service is fail-soft on the server side — when Gemini is unavailable
/// it falls back to a deterministic heuristic — so this repository surfaces
/// errors as exceptions without retry. The screen renders a localized
/// "unable to load" empty-state when this throws.
class ProgrammeRecommendationRepository {
  const ProgrammeRecommendationRepository(this._client);

  final ApiClient _client;

  (Dio, String) _resolve() {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 1),
      ));
      return (direct, '/programme-recommendation/recommend');
    }
    return (_client.dio, Endpoints.programmeRecommendation);
  }

  Future<ProgrammeRecommendationResponse> recommend(
    Map<String, dynamic> request,
  ) async {
    final (dio, path) = _resolve();
    final response = await dio.post<Map<String, dynamic>>(path, data: request);
    return ProgrammeRecommendationResponse.fromJson(response.data ?? const {});
  }
}
