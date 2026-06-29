import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import 'briefing_models.dart';

/// Calls the AI visit briefing service to generate pre-visit guidance cards.
///
/// When [AppConfig.aiServiceBaseUrl] is non-empty (set via --dart-define
/// AI_SERVICE_URL=http://10.0.2.2:8096), requests go directly to the local
/// service without the nginx prefix. Otherwise they route through the gateway.
class VisitBriefingRepository {
  const VisitBriefingRepository(this._client);

  final ApiClient _client;

  /// Returns the Dio instance and path pair to use for a given remote path.
  (Dio, String) _resolve(String gatewayPath, String directPath) {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 1),
      ));
      return (direct, directPath);
    }
    return (_client.dio, gatewayPath);
  }

  Future<VisitBriefingResponse> generate(Map<String, dynamic> patientContext) async {
    final (dio, path) = _resolve(
      Endpoints.visitBriefingGenerate,
      '/briefing/generate',
    );
    final response = await dio.post<Map<String, dynamic>>(path, data: patientContext);
    return VisitBriefingResponse.fromJson(response.data ?? {});
  }

  /// Short 2-3 sentence summary for the patient context screen header.
  Future<String> summary(Map<String, dynamic> patientContext) async {
    final (dio, path) = _resolve(
      Endpoints.visitBriefingSummary,
      '/briefing/summary',
    );
    final response = await dio.post<Map<String, dynamic>>(path, data: patientContext);
    return (response.data?['summary'] as String?) ?? '';
  }
}
