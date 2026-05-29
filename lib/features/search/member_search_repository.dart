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

  /// Searches members by name using server-side search.
  /// Falls back to client-side filtering for household-specific searches.
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
    print('[MemberSearch] query="$q" - using server-side search');

    try {
      // Use server-side patient search for name queries
      onProgress?.call(MemberSearchProgress(0, displayCap));
      
      final reqData = <String, dynamic>{
        'skip': 0,
        'limit': displayCap,
        'tenantId': api.tenantIdAsNum,
        'name': q,  // Server-side name search
      };

      final body = await postOk(
        Endpoints.patientSearch,
        data: reqData,
        action: 'Patient search',
      );
      
      final list = extractList(body);
      // ignore: avoid_print
      print('[MemberSearch] server search returned ${list.length} results');
      
      if (list.isNotEmpty) {
        // ignore: avoid_print
        print('[MemberSearch] sample keys: ${(list.first as Map).keys.toList()}');
      }

      final matches = <MemberHit>[];
      final seenIds = <String>{};
      
      for (final raw in list) {
        if (raw is! Map) continue;
        final hit = MemberHit.fromJson(raw);
        
        // Skip duplicates
        if (hit.id != null && seenIds.contains(hit.id)) continue;
        if (hit.id != null) seenIds.add(hit.id!);
        
        matches.add(hit);
        if (matches.length >= displayCap) break;
      }

      // ignore: avoid_print
      print('[MemberSearch] found ${matches.length} matches from server');
      onProgress?.call(MemberSearchProgress(matches.length, displayCap));
      
      return MemberSearchResult(
        matches: matches,
        totalScanned: list.length,
        truncated: matches.length >= displayCap,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[MemberSearch] server search failed: $e, falling back to client-side');
      return _clientSideSearch(query: q, onProgress: onProgress);
    }
  }

  /// Fallback client-side search for when server-side fails or for
  /// searches that need household info matching.
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
