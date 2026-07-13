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

  /// Ask the assistant a question. Pass [patientContext] to scope the answer
  /// to a single patient (the patient-context floating assistant); omit it for
  /// the general Ask-AI tab. Returns the prose answer plus any suggested
  /// actions the backend selected from the fixed allowlist.
  Future<AssistantAnswer> ask(
    String question, {
    Map<String, dynamic>? patientContext,
  }) async {
    final (dio, path) = _resolve();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        path,
        data: {
          'question': question,
          'locale': 'en',
          'context': patientContext == null
              ? 'community-health-worker'
              : 'patient-scoped',
          if (patientContext != null) 'patientContext': patientContext,
        },
      );
      final data = response.data;
      if (data == null) throw const AssistantException('Empty response');
      final answer = data['answer'] as String?;
      if (answer == null || answer.isEmpty) {
        throw const AssistantException('No answer in response');
      }
      final rawActions = data['actions'];
      final actions = <AssistantAction>[];
      if (rawActions is List) {
        for (final a in rawActions) {
          if (a is Map<String, dynamic>) {
            final parsed = AssistantAction.fromJson(a);
            if (parsed != null) actions.add(parsed);
          }
        }
      }
      return AssistantAnswer(text: answer, actions: actions);
    } on DioException catch (e) {
      throw AssistantException(
        e.message ?? 'Network error',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
