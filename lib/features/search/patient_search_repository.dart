import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_repository.dart';

enum PatientSearchField { name, phone, nid }

class PatientHit {
  PatientHit({
    this.id,
    this.memberReference,
    this.patientReference,
    this.name,
    this.age,
    this.phone,
    this.nid,
    this.gender,
    this.householdId,
    this.villageId,
  });

  final String? id;
  final String? memberReference;
  final String? patientReference;
  final String? name;
  final String? age;
  final String? phone;
  final String? nid;
  final String? gender;
  final String? householdId;
  final String? villageId;

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
      id: firstNonEmpty(['id', 'memberId']),
      memberReference: firstNonEmpty(['memberReference', 'relatedPersonId']),
      patientReference: firstNonEmpty(['patientReference', 'patientId']),
      name: composed.isEmpty ? firstNonEmpty(['name', 'fullName']) : composed,
      age: firstNonEmpty(['age', 'ageInYears']),
      phone: firstNonEmpty(['phoneNumber', 'mobile', 'contactNumber']),
      nid: firstNonEmpty(['idCode', 'nationalId', 'nid', 'identifier']),
      gender: firstNonEmpty(['gender', 'sex']),
      householdId: firstNonEmpty(['householdId', 'groupId']),
      villageId: firstNonEmpty(['villageId', 'unionId']),
    );
  }
}

/// Patient/member search repository.
/// Uses multiple strategies to find patients:
/// 1. `/patient/list` - for enrolled NCD patients (supports searchText)
/// 2. FHIR RelatedPerson search - for household members by name
class PatientSearchRepository extends ApiRepository {
  PatientSearchRepository(super.api, this._authRepo);

  final AuthRepository _authRepo;

  /// Search patients using the Spice 2.0 pattern.
  /// Uses `/patient/list` which supports searchText filtering.
  Future<List<PatientHit>> search({
    required PatientSearchField field,
    required String query,
    int limit = 50,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    // Get user's accessible villageIds
    final villageIds = await _authRepo.subVillageIds();
    
    // ignore: avoid_print
    print('[PatientSearch] query="$q" field=$field villageIds=$villageIds');

    // Try multiple search strategies
    final results = <PatientHit>[];
    final seenIds = <String>{};

    // Strategy 1: Use /patient/list with searchText (like Spice 2.0 Android)
    try {
      final listResults = await _searchPatientList(q, villageIds, limit);
      for (final hit in listResults) {
        final key = hit.id ?? hit.memberReference ?? hit.name;
        if (key != null && !seenIds.contains(key)) {
          seenIds.add(key);
          results.add(hit);
        }
      }
      // ignore: avoid_print
      print('[PatientSearch] /patient/list returned ${listResults.length} results');
    } catch (e) {
      // ignore: avoid_print
      print('[PatientSearch] /patient/list failed: $e');
    }

    // Strategy 2: Search FHIR RelatedPerson directly (household members)
    if (results.length < limit) {
      try {
        final fhirResults = await _searchFhirRelatedPerson(q, villageIds, limit - results.length);
        for (final hit in fhirResults) {
          final key = hit.id ?? hit.memberReference ?? hit.name;
          if (key != null && !seenIds.contains(key)) {
            seenIds.add(key);
            results.add(hit);
          }
        }
        // ignore: avoid_print
        print('[PatientSearch] FHIR RelatedPerson returned ${fhirResults.length} results');
      } catch (e) {
        // ignore: avoid_print
        print('[PatientSearch] FHIR RelatedPerson search failed: $e');
      }
    }

    // ignore: avoid_print
    print('[PatientSearch] Total results: ${results.length}');
    return results;
  }

  /// Search using /patient/list endpoint (Spice 2.0 pattern)
  Future<List<PatientHit>> _searchPatientList(
    String query, 
    List<int> villageIds, 
    int limit,
  ) async {
    final body = <String, dynamic>{
      'skip': 0,
      'limit': limit,
      'tenantId': api.tenantIdAsNum,
      'searchText': query,
      if (villageIds.isNotEmpty) 'villageIds': villageIds,
    };

    // ignore: avoid_print
    print('[PatientSearch] /patient/list request: $body');

    final data = await postOk(Endpoints.patientList, data: body, action: 'Patient list');
    final list = extractList(data);

    return list
        .whereType<Map>()
        .map((e) => PatientHit.fromJson(e))
        .toList(growable: false);
  }

  /// Search FHIR RelatedPerson directly for household members
  Future<List<PatientHit>> _searchFhirRelatedPerson(
    String query,
    List<int> villageIds,
    int limit,
  ) async {
    // Build FHIR search URL
    // Search by name with village filter
    final params = <String, String>{
      'name': query,
      '_count': limit.toString(),
    };

    // Add village filter if available
    if (villageIds.isNotEmpty) {
      // Use the first few villages to avoid URL length issues
      final villageFilter = villageIds.take(10).map(
        (id) => 'http://mdtlabs.com/village-id|$id'
      ).join(',');
      params['identifier'] = villageFilter;
    }

    final queryString = params.entries.map(
      (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}'
    ).join('&');

    final url = '/fhir-server/fhir/RelatedPerson?$queryString';
    
    // ignore: avoid_print
    print('[PatientSearch] FHIR request: $url');

    final resp = await api.dio.get(url);
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw ApiException('FHIR search', code);
    }

    final data = resp.data;
    if (data is! Map) return [];
    
    final entries = data['entry'] as List? ?? [];
    return entries
        .whereType<Map>()
        .map((entry) {
          final resource = entry['resource'] as Map? ?? {};
          return _relatedPersonToHit(resource);
        })
        .where((h) => h.name != null)
        .toList();
  }

  /// Convert FHIR RelatedPerson to PatientHit
  PatientHit _relatedPersonToHit(Map resource) {
    String? name;
    final names = resource['name'] as List?;
    if (names != null && names.isNotEmpty) {
      final nameObj = names.first as Map?;
      if (nameObj != null) {
        name = nameObj['text']?.toString();
        if (name == null) {
          final given = (nameObj['given'] as List?)?.join(' ') ?? '';
          final family = nameObj['family']?.toString() ?? '';
          name = '$given $family'.trim();
        }
      }
    }

    String? phone;
    final telecoms = resource['telecom'] as List?;
    if (telecoms != null) {
      for (final t in telecoms) {
        if (t is Map && t['system'] == 'phone') {
          phone = t['value']?.toString();
          break;
        }
      }
    }

    String? id;
    String? villageId;
    String? nid;
    String? householdId;
    final identifiers = resource['identifier'] as List?;
    if (identifiers != null) {
      for (final ident in identifiers) {
        if (ident is! Map) continue;
        final system = ident['system']?.toString() ?? '';
        final value = ident['value']?.toString();
        if (system.contains('patient-id')) {
          id = value;
        } else if (system.contains('village-id')) {
          villageId = value;
        } else if (system.contains('national-id')) {
          nid = value;
        } else if (system.contains('household-id')) {
          householdId = value;
        }
      }
    }

    String? gender = resource['gender']?.toString();
    
    // Calculate age from birthDate
    String? age;
    final birthDate = resource['birthDate']?.toString();
    if (birthDate != null) {
      final bd = DateTime.tryParse(birthDate);
      if (bd != null) {
        final now = DateTime.now();
        age = (now.year - bd.year).toString();
      }
    }

    return PatientHit(
      id: id ?? resource['id']?.toString(),
      memberReference: 'RelatedPerson/${resource['id']}',
      name: name,
      age: age,
      phone: phone,
      nid: nid,
      gender: gender,
      householdId: householdId,
      villageId: villageId,
    );
  }
}
