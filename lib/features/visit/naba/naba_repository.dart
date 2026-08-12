/// Repository for the AI Next Best Action (NABA) endpoint.
///
/// Routing matches [ProgrammeRecommendationRepository] and [VisitBriefingRepository]:
/// when [AppConfig.aiServiceBaseUrl] (`AI_SERVICE_URL` dart-define) is set, calls
/// directly at `/naba/generate` on that base URL. Otherwise routes through the
/// nginx gateway at [Endpoints.nabaGenerate].
///
/// No caching — every call is unique (post-assessment context).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import 'naba_models.dart';

class NabaRepository {
  const NabaRepository(this._client);

  final ApiClient _client;

  static const _jsonPretty = JsonEncoder.withIndent('  ');

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
    final payload = request.toJson();
    if (kDebugMode) {
      final base = dio.options.baseUrl;
      debugPrint('[NABA] POST $base$path');
      debugPrint('[NABA] request payload:\n${_jsonPretty.convert(payload)}');
    }
    try {
      final response = await dio.post<dynamic>(
        path,
        data: payload,
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        if (kDebugMode) {
          debugPrint('[NABA] unexpected response type=${raw.runtimeType} '
              'status=${response.statusCode} body=$raw');
        }
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'Expected JSON object, got ${raw.runtimeType}',
        );
      }
      if (kDebugMode) {
        debugPrint('[NABA] response status=${response.statusCode}');
        debugPrint('[NABA] response body:\n${_jsonPretty.convert(raw)}');
        final referral = raw['referralRecommendation'] ?? raw['referral_recommendation'];
        final danger = raw['dangerSigns'] ?? raw['danger_signs'];
        debugPrint('[NABA] referralRecommendation=$referral');
        debugPrint('[NABA] dangerSigns=$danger');
      }
      return NabaResponse.fromJson(raw);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[NABA] generate failed: $e');
        debugPrint('$st');
      }
      rethrow;
    }
  }
}
