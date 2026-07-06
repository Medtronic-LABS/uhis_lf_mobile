/// HTTP client for the conversational AI assistant service.
///
/// Routes through the nginx gateway at [Endpoints.assistantAsk], or directly
/// to the local service when [AppConfig.aiServiceBaseUrl] is set (same dart-
/// define that routes Visit Briefing and AI Scribe to a local container).
library;

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/config/app_config.dart';
import 'assistant_models.dart';

class AssistantRepository {
  const AssistantRepository(this._client);

  final ApiClient _client;

  (Dio, String) _resolve() {
    final aiUrl = AppConfig.assistantBaseUrl;
    // When aiServiceBaseUrl is the gateway itself, use the gateway path.
    // When it points to a local service, strip the nginx prefix.
    if (AppConfig.aiServiceBaseUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));
      return (direct, '/assistant/ask');
    }
    return (_client.dio, Endpoints.assistantAsk);
  }

  Future<String> ask(String question) async {
    final (dio, path) = _resolve();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        path,
        data: {
          'question': question,
          'locale': 'en',
          'context': 'community-health-worker',
        },
      );
      final data = response.data;
      if (data == null) throw const AssistantException('Empty response');
      final answer = data['answer'] as String?;
      if (answer == null || answer.isEmpty) {
        throw const AssistantException('No answer in response');
      }
      return answer;
    } on DioException catch (e) {
      throw AssistantException(
        e.message ?? 'Network error',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
