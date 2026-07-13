import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

/// Pushes blood pressure log entries to the spice-service.
///
/// A BP log entry is created for each automated BP reading set captured
/// during the NCD assessment form (Step 3 of the visit flow).
class BloodPressureRepository {
  BloodPressureRepository(this._client);

  final ApiClient _client;

  /// Submits a single BP log entry.
  ///
  /// [payload] must conform to the Android BPLogRequest shape:
  /// `{ patientId, avgSystolic, avgDiastolic, weight, bmi, ... }`
  Future<void> createBpLog(Map<String, dynamic> payload) async {
    await _client.dio.post<dynamic>(Endpoints.bpLogCreate, data: payload);
  }
}
