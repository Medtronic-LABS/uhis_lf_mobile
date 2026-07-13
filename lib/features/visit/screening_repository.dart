import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

/// Pushes initial NCD/ANC screening records to the spice-service.
///
/// Screening is a one-time record created at the first clinical encounter
/// for a programme. Subsequent visits use assessment/create instead.
class ScreeningRepository {
  ScreeningRepository(this._client);

  final ApiClient _client;

  /// Submits an initial screening record.
  ///
  /// [payload] must conform to the Android ScreeningRequest shape:
  /// `{ patientId, programme, screeningDate, nationalId, ... }`
  Future<void> createScreening(Map<String, dynamic> payload) async {
    await _client.dio.post<dynamic>(Endpoints.screeningCreate, data: payload);
  }
}
