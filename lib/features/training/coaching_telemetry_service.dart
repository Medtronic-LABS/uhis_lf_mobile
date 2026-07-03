import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';

class CoachingTelemetryService {
  const CoachingTelemetryService(this._api);

  final ApiClient _api;

  void fireCardViewed(int userId, String moduleId, int cardIndex) {
    _post({
      'event_type': 'module_card_viewed',
      'user_id': userId,
      'module_id': moduleId,
      'card_index': cardIndex,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void fireQuizAttempted(
      int userId, String moduleId, double score, bool passed) {
    _post({
      'event_type': 'module_quiz_attempted',
      'user_id': userId,
      'module_id': moduleId,
      'score': score,
      'passed': passed,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void _post(Map<String, dynamic> payload) {
    final url =
        '${AppConfig.coachingServiceUrl}/medtronics-api/telemetry/events';
    _api.dio.post<void>(url, data: payload).catchError((Object e) {
      debugPrint('[CoachingTelemetry] fire failed: $e');
      return Response<void>(requestOptions: RequestOptions(path: url));
    });
  }
}
