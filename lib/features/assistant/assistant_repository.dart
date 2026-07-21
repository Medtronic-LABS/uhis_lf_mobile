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
import '../../core/debug/console_log.dart';
import '../../core/errors/domain_exceptions.dart';
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

  /// Ask the assistant a question.
  ///
  /// Routes to the coaching RAG backend (`/medtronics-api/coaching/rag-query`)
  /// when [AppConfig.coachingServiceUrl] is set and no [patientContext] is
  /// provided. Falls back to the UHIS AI-Scribe assistant endpoint otherwise.
  Future<AssistantAnswer> ask(
    String question, {
    Map<String, dynamic>? patientContext,
  }) async {
    final coachingUrl = AppConfig.coachingServiceUrl;
    if (coachingUrl.isNotEmpty && patientContext == null) {
      return _askCoachingRag(question, coachingUrl);
    }
    return _askAiScribe(question, patientContext: patientContext);
  }

  Future<AssistantAnswer> _askCoachingRag(
      String question, String baseUrl) async {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 45),
    ));
    ConsoleLog.banner(
        '[PayloadDebug] coaching-rag → $baseUrl${Endpoints.coachingRagQuery}\nq=$question');
    try {
      final response = await dio.post<Map<String, dynamic>>(
        Endpoints.coachingRagQuery,
        data: {'question': question, 'response_language': 'en'},
      );
      ConsoleLog.d('[PayloadDebug] coaching-rag → ${response.statusCode}');
      final data = response.data;
      if (data == null) throw const AssistantException('Empty response');
      final answer = data['answer'] as String?;
      if (answer == null || answer.isEmpty) {
        throw const AssistantException('No answer in response');
      }
      final suggestedQuestions =
          (data['suggested_questions'] as List<dynamic>? ?? [])
              .whereType<String>()
              .toList();
      final rawModules = data['retrieved_modules'] as List<dynamic>? ?? [];
      final modules = <RagModuleHit>[];
      for (final m in rawModules) {
        if (m is! Map) continue;
        final titleRaw = m['title'];
        final title = (titleRaw is Map
                ? (titleRaw['en'] ?? titleRaw.values.firstOrNull)
                : titleRaw)
            ?.toString() ??
            '';
        modules.add(RagModuleHit(
          moduleId: (m['module_id'] ?? '').toString(),
          title: title,
          domain: (m['domain'] ?? '').toString(),
        ));
      }
      final rawDocs = data['source_documents'] as List<dynamic>? ?? [];
      final docs = <RagSourceAttribution>[];
      for (final d in rawDocs) {
        if (d is! Map) continue;
        docs.add(RagSourceAttribution(
          title: (d['title'] ?? '').toString(),
          sourceType: (d['source_type'] ?? 'pdf').toString(),
          presignedUrl: d['presigned_url'] as String?,
        ));
      }
      return AssistantAnswer(
        text: answer,
        suggestedQuestions: suggestedQuestions,
        retrievedModules: modules,
        sourceDocuments: docs,
      );
    } on DioException catch (e) {
      ConsoleLog.error('[PayloadDebug] coaching-rag error', e);
      throw AssistantException(NetworkErrorMapper.friendly(e),
          statusCode: e.response?.statusCode);
    }
  }

  Future<AssistantAnswer> _askAiScribe(
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
      throw AssistantException(NetworkErrorMapper.friendly(e),
          statusCode: e.response?.statusCode);
    }
  }
}
