import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

/// Pushes NCD medical review records to the spice-service.
///
/// A medical review is created at each NCD follow-up visit containing
/// BP, glucose, medication adherence, and comorbidity status.
class NcdMedicalReviewRepository {
  NcdMedicalReviewRepository(this._client);

  final ApiClient _client;

  /// Submits an NCD medical review record.
  ///
  /// [payload] must conform to the Android MedicalReviewRequest shape:
  /// `{ patientId, bpLog, glucoseLog, onMedication, comorbidities, ... }`
  Future<void> createReview(Map<String, dynamic> payload) async {
    await _client.dio.post<dynamic>(Endpoints.assessmentCreate, data: payload);
  }
}
