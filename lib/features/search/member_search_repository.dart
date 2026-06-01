import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_repository.dart';

/// A match from member search.
class MemberHit {
  MemberHit({
    this.id,
    this.name,
    this.age,
    this.gender,
    this.phone,
    this.nid,
    this.householdId,
    this.householdName,
    this.householdNo,
  });

  final String? id;
  final String? name;
  final String? age;
  final String? gender;
  final String? phone;
  final String? nid;
  final String? householdId;
  final String? householdName;
  final String? householdNo;

  static MemberHit fromJson(Map json) {
    String? str(dynamic keys) {
      if (keys is String) {
        final v = json[keys];
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }
      if (keys is List) {
        for (final k in keys) {
          final v = json[k];
          if (v != null && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
      }
      return null;
    }

    final first = str(['firstName', 'givenName']);
    final last = str(['lastName', 'familyName']);
    final composed =
        [first, last].where((s) => s != null && s.isNotEmpty).join(' ').trim();

    return MemberHit(
      id: str(['id', 'memberId', 'patientId']),
      name: composed.isEmpty ? str(['name', 'fullName']) : composed,
      age: str(['age', 'ageInYears']),
      gender: str(['gender', 'sex']),
      phone: str(['phoneNumber', 'mobile', 'contactNumber']),
      nid: str(['idCode', 'nationalId', 'nid', 'identifier']),
      householdId: str(['householdId']),
      householdName: str(['householdName']),
      householdNo: str(['householdNo']),
    );
  }
}

class MemberSearchProgress {
  MemberSearchProgress(this.loaded, this.cap);
  final int loaded;
  final int cap;
}

class MemberSearchResult {
  MemberSearchResult({
    required this.matches,
    required this.totalScanned,
    required this.truncated,
  });
  final List<MemberHit> matches;
  final int totalScanned;
  final bool truncated;
}

/// Searches household members by name, phone, NID, or household info.
/// Uses server-side search via `/spice-service/patient/search` for efficiency.
class MemberSearchRepository extends ApiRepository {
  MemberSearchRepository(super.api, this._authRepo);

  final AuthRepository _authRepo;

  static const int displayCap = 50;

  /// Searches members by name using multiple strategies:
  /// 1. /patient/list with searchText (enrolled patients)
  /// 2. FHIR RelatedPerson search (all household members)
  Future<MemberSearchResult> search({
    required String query,
    void Function(MemberSearchProgress)? onProgress,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return MemberSearchResult(
        matches: const [],
        totalScanned: 0,
        truncated: false,
      );
    }

    // ignore: avoid_print
    print('[MemberSearch] query="$q" - using multi-strategy search');

    final matches = <MemberHit>[];
    final seenIds = <String>{};
    int totalScanned = 0;
    
    // Get user's accessible villageIds
    final villageIds = await _authRepo.subVillageIds();
    // ignore: avoid_print
    print('[MemberSearch] villageIds=$villageIds');

    onProgress?.call(MemberSearchProgress(0, displayCap));

    // Strategy 1: Try /patient/list with searchText
    try {
      final reqData = <String, dynamic>{
        'skip': 0,
        'limit': displayCap,
        'tenantId': api.tenantIdAsNum,
        'searchText': q,
        if (villageIds.isNotEmpty) 'villageIds': villageIds,
      };
      
      // ignore: avoid_print
      print('[MemberSearch] /patient/list request: $reqData');

      final body = await postOk(
        Endpoints.patientList,
        data: reqData,
        action: 'Patient list',
      );
      
      final list = extractList(body);
      // ignore: avoid_print
      print('[MemberSearch] /patient/list returned ${list.length} results');
      totalScanned += list.length;
      
      for (final raw in list) {
        if (raw is! Map) continue;
        final hit = MemberHit.fromJson(raw);
        final key = hit.id ?? hit.name;
        if (key != null && !seenIds.contains(key)) {
          seenIds.add(key);
          matches.add(hit);
        }
        if (matches.length >= displayCap) break;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[MemberSearch] /patient/list failed: $e');
    }

    onProgress?.call(MemberSearchProgress(matches.length, displayCap));

    // Strategy 2: Search FHIR RelatedPerson directly if we need more results
    if (matches.length < displayCap) {
      try {
        final fhirResults = await _searchFhirRelatedPerson(q, villageIds, displayCap - matches.length);
        // ignore: avoid_print
        print('[MemberSearch] FHIR RelatedPerson returned ${fhirResults.length} results');
        totalScanned += fhirResults.length;
        
        for (final hit in fhirResults) {
          final key = hit.id ?? hit.name;
          if (key != null && !seenIds.contains(key)) {
            seenIds.add(key);
            matches.add(hit);
          }
          if (matches.length >= displayCap) break;
        }
      } catch (e) {
        // ignore: avoid_print
        print('[MemberSearch] FHIR RelatedPerson search failed: $e');
      }
    }

    // ignore: avoid_print
    print('[MemberSearch] Total matches: ${matches.length}, scanned: $totalScanned');
    onProgress?.call(MemberSearchProgress(matches.length, displayCap));

    return MemberSearchResult(
      matches: matches,
      totalScanned: totalScanned,
      truncated: matches.length >= displayCap,
    );
  }

  /// Search FHIR RelatedPerson directly for household members
  Future<List<MemberHit>> _searchFhirRelatedPerson(
    String query,
    List<int> villageIds,
    int limit,
  ) async {
    // Build FHIR search URL
    final params = <String, String>{
      'name': query,
      '_count': limit.toString(),
    };

    // Add village filter if available
    if (villageIds.isNotEmpty) {
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
    print('[MemberSearch] FHIR request: $url');

    final resp = await api.dio.get(url);
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw Exception('FHIR search failed ($code)');
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

  /// Convert FHIR RelatedPerson to MemberHit
  MemberHit _relatedPersonToHit(Map resource) {
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
        } else if (system.contains('national-id')) {
          nid = value;
        } else if (system.contains('household-id')) {
          householdId = value;
        }
      }
    }

    String? gender = resource['gender']?.toString();
    
    String? age;
    final birthDate = resource['birthDate']?.toString();
    if (birthDate != null) {
      final bd = DateTime.tryParse(birthDate);
      if (bd != null) {
        age = (DateTime.now().year - bd.year).toString();
      }
    }

    return MemberHit(
      id: id ?? resource['id']?.toString(),
      name: name,
      age: age,
      gender: gender,
      phone: phone,
      nid: nid,
      householdId: householdId,
    );
  }

  /// Fallback client-side search (kept for offline mode)
  Future<MemberSearchResult> _clientSideSearch({
    required String query,
    void Function(MemberSearchProgress)? onProgress,
  }) async {
    final q = query.toLowerCase();
    
    final matches = <MemberHit>[];
    final seenIds = <String>{};
    int scanned = 0;
    int skip = 0;
    bool ranOut = false;

    final subVillageIds = await _authRepo.subVillageIds();
    // ignore: avoid_print
    print('[MemberSearch] client-side fallback, villageIds=$subVillageIds');

    const int pageSize = 100;
    const int maxPages = 10;

    for (int page = 0; page < maxPages; page++) {
      onProgress?.call(MemberSearchProgress(scanned, pageSize * maxPages));

      final reqData = <String, dynamic>{
        'skip': skip,
        'limit': pageSize,
        'tenantId': api.tenantIdAsNum,
      };
      if (subVillageIds.isNotEmpty) {
        reqData['villageIds'] = subVillageIds;
      }

      final body = await postOk(
        Endpoints.householdMemberList,
        data: reqData,
        action: 'Member list',
      );
      final list = extractList(body);
      // ignore: avoid_print
      print('[MemberSearch] page=$page got=${list.length} members');
      scanned += list.length;

      for (final raw in list) {
        if (raw is! Map) continue;
        final hit = MemberHit.fromJson(raw);

        // Skip duplicates
        if (hit.id != null && seenIds.contains(hit.id)) continue;
        if (hit.id != null) seenIds.add(hit.id!);

        // Check if query matches any searchable field
        final searchableFields = [
          hit.name,
          hit.phone,
          hit.nid,
          hit.householdName,
          hit.householdNo,
        ];

        final matched = searchableFields.any((field) {
          if (field == null) return false;
          return field.toLowerCase().contains(q);
        });

        if (matched) {
          matches.add(hit);
          if (matches.length >= displayCap) {
            ranOut = true;
            break;
          }
        }
      }

      if (ranOut) break;
      if (list.length < pageSize) break;
      skip += pageSize;
    }

    // ignore: avoid_print
    print('[MemberSearch] client-side found ${matches.length} matches, scanned=$scanned');
    onProgress?.call(MemberSearchProgress(scanned, pageSize * maxPages));
    return MemberSearchResult(
      matches: matches,
      totalScanned: scanned,
      truncated: ranOut,
    );
  }
}
