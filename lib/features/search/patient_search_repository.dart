import '../../core/api/api_client.dart';
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

class PatientSearchRepository {
  PatientSearchRepository(this._api);

  final ApiClient _api;

  Future<List<PatientHit>> search({
    required PatientSearchField field,
    required String query,
    int limit = 20,
  }) async {
    final body = <String, dynamic>{
      'skip': 0,
      'limit': limit,
      'tenantId': _tenantIdAsNum(),
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
    final resp = await _api.dio.post(Endpoints.patientSearch, data: body);
    if (resp.statusCode != 200) {
      throw Exception('Search failed (${resp.statusCode})');
    }
    final data = resp.data;
    final list = (data is Map && data['entityList'] is List)
        ? data['entityList'] as List
        : (data is List ? data : const []);
    return list
        .whereType<Map>()
        .map((e) => PatientHit.fromJson(e))
        .toList(growable: false);
  }

  Object? _tenantIdAsNum() {
    final t = _api.tenantId;
    if (t == null) return null;
    return int.tryParse(t) ?? t;
  }
}
