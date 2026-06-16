import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/db/member_dao.dart';

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
  MemberSearchRepository(super.api, this._authRepo, this._members);

  final AuthRepository _authRepo;
  final MemberDao _members;

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

    // Strategy 2: Search local SQLite (synced household members) for non-enrolled
    if (matches.length < displayCap) {
      try {
        final localRows = await _members.searchByName(q, limit: displayCap - matches.length + 1);
        // ignore: avoid_print
        print('[MemberSearch] local DB returned ${localRows.length} results');
        totalScanned += localRows.length;
        for (final m in localRows) {
          final key = m.patientId ?? m.id;
          if (!seenIds.contains(key)) {
            seenIds.add(key);
            matches.add(MemberHit(
              id: m.patientId ?? m.id,
              name: m.name,
              gender: m.gender,
              phone: m.phone,
              householdId: m.householdId,
            ));
          }
          if (matches.length >= displayCap) break;
        }
      } catch (e) {
        // ignore: avoid_print
        print('[MemberSearch] local DB search failed: $e');
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

}
