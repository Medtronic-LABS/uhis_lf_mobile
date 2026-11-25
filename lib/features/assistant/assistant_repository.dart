/// HTTP client for the conversational AI assistant.
///
/// Patient-scoped and general questions go to the Frappe `spice_next_ai` app
/// ([Endpoints.assistantAsk]) via [FrappeClient]; base URL:
/// [AppConfig.spiceNextAiApiBaseUrl]. General questions go to the coaching
/// RAG backend instead when [AppConfig.coachingServiceUrl] is set.
library;

import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/frappe_client.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/debug/console_log.dart';
import '../../core/errors/domain_exceptions.dart';
import '../../core/i18n/app_locale.dart';
import 'assistant_models.dart';

class AssistantRepository {
  const AssistantRepository(this._client);

  final FrappeClient _client;

  /// Same answer budget the assistant had on the legacy ai-scribe route.
  static const _askTimeout = Duration(seconds: 30);

  /// Ask the assistant a question.
  ///
  /// Routes to the coaching RAG backend (`/medtronics-api/coaching/rag-query`)
  /// when [AppConfig.coachingServiceUrl] is set and no [patientContext] is
  /// provided. Falls back to the `spice_next_ai` assistant endpoint otherwise.
  Future<AssistantAnswer> ask(
    String question, {
    Map<String, dynamic>? patientContext,
    List<Map<String, String>>? history,
  }) async {
    final coachingUrl = AppConfig.coachingServiceUrl;
    if (coachingUrl.isNotEmpty && patientContext == null) {
      if (question.trim().length < 3) {
        return AssistantAnswer(text: AssistantStrings.enterAtLeast3Chars);
      }
      return _askCoachingRag(question, coachingUrl);
    }
    return _askSpiceNextAi(question, patientContext: patientContext, history: history);
  }

  Future<AssistantAnswer> _askCoachingRag(
      String question, String baseUrl) async {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 45),
      validateStatus: (s) => s != null && s < 500,
    ));
    ConsoleLog.banner(
        '[PayloadDebug] coaching-rag → $baseUrl${Endpoints.coachingRagQuery}\nq=$question');
    try {
      final response = await dio.post<Map<String, dynamic>>(
        Endpoints.coachingRagQuery,
        data: {'question': question, 'response_language': 'bn'},
      );
      ConsoleLog.step('[PayloadDebug] coaching-rag → ${response.statusCode}');
      final statusCode = response.statusCode ?? 0;
      if (statusCode == 404) {
        throw AssistantException(
          AssistantStrings.settingUpRetryLater,
          statusCode: 404,
        );
      }
      if (statusCode >= 400) {
        throw AssistantException(
          NetworkErrorMapper.friendly(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
            ),
          ),
          statusCode: statusCode,
        );
      }
      final data = response.data;
      if (data == null) throw AssistantException(AssistantStrings.emptyResponse);
      final answer = data['answer'] as String?;
      if (answer == null || answer.isEmpty) {
        throw AssistantException(AssistantStrings.noAnswerInResponse);
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
          statusCode: e.response?.statusCode, cause: e);
    }
  }

  Future<AssistantAnswer> _askSpiceNextAi(
    String question, {
    Map<String, dynamic>? patientContext,
    List<Map<String, String>>? history,
  }) async {
    const path = Endpoints.assistantAsk;
    final appLanguage = AppLocale.isBangla ? 'bn' : 'en';
    ConsoleLog.step('[AssistantAsk] appLanguage=$appLanguage context=${patientContext == null ? 'community-health-worker' : 'patient-scoped'}');
    final body = {
      'question': question,
      'appLanguage': appLanguage,
      'context':
          patientContext == null ? 'community-health-worker' : 'patient-scoped',
      if (patientContext != null) 'patientContext': patientContext,
      if (history != null && history.isNotEmpty) 'history': history,
    };
    ConsoleLog.json('[PayloadDebug] assistant-ask ${_client.baseUrl}$path', body);
    final Map<String, dynamic> data;
    try {
      data = await _client.postJson(path, body, receiveTimeout: _askTimeout);
    } on FrappeException catch (e) {
      ConsoleLog.warn('[PayloadDebug] assistant-ask error: $e');
      throw _toAssistantException(e);
    }
    ConsoleLog.json('[PayloadDebug] assistant-ask response', data);
    final answer = data['answer'] as String?;
    if (answer == null || answer.isEmpty) {
      throw AssistantException(AssistantStrings.noAnswerInResponse);
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
  }

  /// Keeps the user message and analytics cause the legacy route produced:
  /// the underlying [DioException] drives both when there is one.
  static AssistantException _toAssistantException(FrappeException e) {
    final cause = e.cause;
    if (cause == null && e.kind == FrappeErrorKind.badResponse) {
      return AssistantException(AssistantStrings.emptyResponse, cause: e);
    }
    return AssistantException(
      NetworkErrorMapper.friendly(cause ?? e),
      statusCode: e.statusCode,
      cause: cause ?? e,
    );
  }
}
