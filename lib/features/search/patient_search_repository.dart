import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';

enum PatientSearchField { name, phone, nid }

class PatientHit {
  PatientHit({this.name, this.age, this.phone, this.nid});

  final String? name;
  final String? age;
  final String? phone;
  final String? nid;

  static PatientHit fromJson(Map json) {
    String? firstNonEmpty(List<dynamic> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      return null;
    }

    final first = firstNonEmpty(['firstName', 'givenName']);
    final last = firstNonEmpty(['lastName', 'familyName']);
    final composed = [first, last].where((s) => s != null && s.isNotEmpty).join(' ').trim();
    return PatientHit(
      name: composed.isEmpty ? firstNonEmpty(['name', 'fullName']) : composed,
      age: firstNonEmpty(['age', 'ageInYears']),
      phone: firstNonEmpty(['phoneNumber', 'mobile', 'contactNumber']),
      nid: firstNonEmpty(['idCode', 'nationalId', 'nid', 'identifier']),
    );
  }
}

class PatientSearchRepository extends ApiRepository {
  PatientSearchRepository(super.api);

  Future<List<PatientHit>> search({
    required PatientSearchField field,
    required String query,
    int limit = 20,
  }) async {
    final body = <String, dynamic>{
      'skip': 0,
      'limit': limit,
      'tenantId': api.tenantIdAsNum,
    };
    switch (field) {
      case PatientSearchField.name:
        body['name'] = query;
        break;
      case PatientSearchField.phone:
        body['phoneNumber'] = query;
        break;
      case PatientSearchField.nid:
        body['idCode'] = query;
        break;
    }
    final data = await postOk(Endpoints.patientSearch, data: body, action: 'Search');
    return extractList(data)
        .whereType<Map>()
        .map((e) => PatientHit.fromJson(e))
        .toList(growable: false);
  }
}
