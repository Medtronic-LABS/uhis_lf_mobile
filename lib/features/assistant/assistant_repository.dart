/// HTTP client for the conversational AI assistant service.
///
/// Routes through the nginx gateway at [Endpoints.assistantAsk], or directly
/// to the local service when [AppConfig.aiServiceBaseUrl] is set (same dart-
/// define that routes Visit Briefing and AI Scribe to a local container).
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/debug/console_log.dart';
import '../../core/errors/domain_exceptions.dart';
import '../training/offline_llm_service.dart';
import 'assistant_models.dart';

class AssistantRepository {
  AssistantRepository(this._client);

  final ApiClient _client;

  final _offlineLlm = OfflineLlmService();

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
  /// Priority order:
  ///   1. On-device Gemma (offline) when the model is initialized and
  ///      [contextDocs] are provided for RAG context.
  ///   2. Coaching RAG backend when [AppConfig.coachingServiceUrl] is set and
  ///      no [patientContext] is provided.
  ///   3. UHIS AI-Scribe assistant endpoint (default / patient-scoped).
  Future<AssistantAnswer> ask(
    String question, {
    Map<String, dynamic>? patientContext,
    List<String> contextDocs = const [],
  }) async {
    // Use on-device Gemma only when offline and model is initialized.
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity.every((r) => r == ConnectivityResult.none);
      if (isOffline && await _offlineLlm.isReady()) {
        return _askOffline(question, contextDocs);
      }
    } on OfflineLlmException catch (e) {
      ConsoleLog.warn('[AssistantRepository] offline LLM check failed: $e');
    }

    final coachingUrl = AppConfig.coachingServiceUrl;
    if (coachingUrl.isNotEmpty && patientContext == null) {
      try {
        return await _askCoachingRag(question, coachingUrl);
      } on AssistantException catch (e) {
        ConsoleLog.warn(
            '[AssistantRepository] coaching RAG unavailable (${e.statusCode ?? "conn-refused"}), falling back to AI-scribe');
      }
    }
    return _askAiScribe(question, patientContext: patientContext);
  }

  static const _maxContextChars = 1800;

  Future<AssistantAnswer> _askOffline(
    String question,
    List<String> contextDocs,
  ) async {
    String contextSection = '';
    if (contextDocs.isNotEmpty) {
      final raw = contextDocs.join('\n');
      final truncated = raw.length > _maxContextChars
          ? raw.substring(0, _maxContextChars)
          : raw;
      contextSection = '\n\nContext:\n$truncated';
    }
    final prompt = 'You are a micro-coaching assistant for community health workers. Be concise and practical.$contextSection\n\nQuestion: $question\nAnswer:';

    ConsoleLog.banner('[PayloadDebug] offline-llm → q=$question');
    try {
      final answer = await _offlineLlm.ask(prompt);
      ConsoleLog.step('[PayloadDebug] offline-llm → ${answer.length}chars');
      return AssistantAnswer(text: answer);
    } on OfflineLlmException catch (e) {
      ConsoleLog.warn('[PayloadDebug] offline-llm failed: $e');
      throw AssistantException(e.message);
    }
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
      ConsoleLog.step('[PayloadDebug] coaching-rag → ${response.statusCode}');
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
      ConsoleLog.warn('[PayloadDebug] coaching-rag error: $e');
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
