import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import 'briefing_models.dart';

/// Calls the AI visit briefing service to generate pre-visit guidance cards.
class VisitBriefingRepository {
  const VisitBriefingRepository(this._client);

  final ApiClient _client;

  Future<VisitBriefingResponse> generate(Map<String, dynamic> patientContext) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      Endpoints.visitBriefingGenerate,
      data: patientContext,
    );
    return VisitBriefingResponse.fromJson(response.data ?? {});
  }

  /// Short 2-3 sentence summary for the patient context screen header.
  Future<String> summary(Map<String, dynamic> patientContext) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      Endpoints.visitBriefingSummary,
      data: patientContext,
    );
    return (response.data?['summary'] as String?) ?? '';
  }
}
