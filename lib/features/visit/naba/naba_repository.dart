/// Repository for the AI Next Best Action (NABA) endpoint.
///
/// Routing matches [ProgrammeRecommendationRepository] and [VisitBriefingRepository]:
/// when [AppConfig.aiServiceBaseUrl] (`AI_SERVICE_URL` dart-define) is set, calls
/// directly at `/naba/generate` on that base URL. Otherwise routes through the
/// nginx gateway at [Endpoints.nabaGenerate].
///
/// No caching — every call is unique (post-assessment context).
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import 'naba_models.dart';

class NabaRepository {
  const NabaRepository(this._client);

  final ApiClient _client;

  (Dio, String) _resolve() {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(minutes: 2),
      ));
      return (direct, '/naba/generate');
    }
    return (_client.dio, Endpoints.nabaGenerate);
  }

  Future<NabaResponse> generate(NabaRequest request) async {
    final (dio, path) = _resolve();
    final response = await dio.post<Map<String, dynamic>>(
      path,
      data: request.toJson(),
    );
    final data = response.data;
    if (data == null) throw Exception('NABA: empty response');
    return NabaResponse.fromJson(data);
  }
}
