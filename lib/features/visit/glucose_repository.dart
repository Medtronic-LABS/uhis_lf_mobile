import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

/// Pushes blood glucose log entries to the spice-service.
///
/// A glucose log entry is created for FBS or RBS readings captured
/// during the NCD assessment form (Step 3 of the visit flow).
class GlucoseRepository {
  GlucoseRepository(this._client);

  final ApiClient _client;

  /// Submits a single glucose log entry.
  ///
  /// [payload] must conform to the Android GlucoseLogRequest shape:
  /// `{ patientId, glucoseValue, glucoseUnit, glucoseType ('fasting'|'rbs'), ... }`
  Future<void> createGlucoseLog(Map<String, dynamic> payload) async {
    await _client.dio.post<dynamic>(Endpoints.glucoseLogCreate, data: payload);
  }
}
