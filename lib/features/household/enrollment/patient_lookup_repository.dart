import '../../../core/api/api_repository.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/patient.dart';

/// Looks up an already-registered patient on the spice-service by NID.
///
/// Best-effort enrichment layered on top of the on-device NID OCR: when the
/// device is online and a scanned NID matches an existing registration, the
/// caller can pull authoritative demographics instead of trusting OCR alone,
/// and warn the health worker before creating a duplicate. Offline or on any
/// transport error the caller degrades to OCR-only — this lookup never blocks
/// enrollment.
///
/// Wire: `POST /spice-service/patient/search` (Postman
/// `patient-controller/searchPatient`). Response mapped through the shared
/// [Patient.fromApiJson] so no bespoke DTO is introduced.
class PatientLookupRepository extends ApiRepository {
  PatientLookupRepository(super.api);

  /// Search patients whose identifier / demographics match [nid] and return the
  /// first hit, or null when nothing matches (or [nid] is blank). Throws
  /// [ApiException] on a non-2xx response and lets the underlying
  /// `DioException` propagate on a transport failure, so the caller decides how
  /// to degrade.
  Future<Patient?> lookupByNid(String nid) async {
    final trimmed = nid.trim();
    if (trimmed.isEmpty) return null;

    final body = <String, dynamic>{
      'searchText': trimmed,
      'skip': 0,
      'limit': _maxResults,
      'count': _maxResults,
    };

    final data = await postOk(
      Endpoints.patientSearch,
      data: body,
      action: 'Patient NID lookup',
    );
    return firstMatch(data);
  }

  /// Pull the first mappable [Patient] out of a `/patient/search` response body
  /// (a bare list, a `{ entityList: [...] }`, or a `{ data: [...] }` envelope).
  /// Pure and side-effect-free so the parsing is unit-testable without a live
  /// HTTP client.
  static Patient? firstMatch(dynamic body) {
    for (final entry in ApiRepository.extractListStatic(body)) {
      if (entry is Map) {
        final patient = Patient.fromApiJson(entry);
        if (patient != null) return patient;
      }
    }
    return null;
  }

  static const int _maxResults = 5;
}
