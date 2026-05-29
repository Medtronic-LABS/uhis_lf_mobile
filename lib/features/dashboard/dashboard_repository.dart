import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_repository.dart';

class DashboardRepository extends ApiRepository {
  DashboardRepository(super.api, this._authRepo);

  final AuthRepository _authRepo;

  /// Cached sub-village IDs fetched from the auth repository.
  /// IMPORTANT: Must be cleared on logout via [clearCache] to avoid
  /// using stale data from previous login sessions.
  List<int>? _cachedSubVillageIds;

  /// Clears cached data. Call this on logout to ensure fresh data on next login.
  void clearCache() {
    _cachedSubVillageIds = null;
  }

  /// Build the request body for household/member list APIs.
  /// IMPORTANT: These APIs filter by SUB-VILLAGE IDs (stored in FHIR as
  /// `village-id` identifier), NOT the union (village) IDs from user profile.
  Future<Map<String, dynamic>> _listRequest(int skip, int limit) async {
    final req = <String, dynamic>{
      'skip': skip,
      'limit': limit,
      'tenantId': api.tenantIdAsNum,
    };
    // Fetch sub-village IDs from auth repository (cached after login)
    _cachedSubVillageIds ??= await _authRepo.subVillageIds();
    final subVillageIds = _cachedSubVillageIds!;
    // ignore: avoid_print
    print('[DashboardRepository] subVillageIds=$subVillageIds tenantId=${api.tenantIdAsNum}');
    if (subVillageIds.isNotEmpty) {
      req['villageIds'] = subVillageIds;
    }
    // ignore: avoid_print
    print('[DashboardRepository] request body=$req');
    return req;
  }

  /// Returns both household count and total member count in a single pass.
  /// Members are counted by summing `noOfPeople` from each household.
  Future<({int households, int members})> householdAndMemberCount({
    int pageSize = 100,
    int hardCapPages = 50,
  }) async {
    int totalHouseholds = 0;
    int totalMembers = 0;
    int skip = 0;
    int page = 0;
    while (page < hardCapPages) {
      final body = await postOk(
        Endpoints.householdList,
        data: await _listRequest(skip, pageSize),
        action: 'Household list',
      );
      final list = extractList(body);
      // ignore: avoid_print
      print('[DashboardRepository] page=$page skip=$skip got=${list.length} households');
      totalHouseholds += list.length;
      for (final hh in list) {
        final n = (hh is Map) ? hh['noOfPeople'] : null;
        if (n is int) {
          totalMembers += n;
        } else if (n is num) {
          totalMembers += n.toInt();
        }
      }
      // ignore: avoid_print
      print('[DashboardRepository] runningTotal: households=$totalHouseholds members=$totalMembers');
      if (list.length < pageSize) break;
      skip += pageSize;
      page++;
    }
    return (households: totalHouseholds, members: totalMembers);
  }

  /// Returns the count of enrolled patients (clinical patients who have
  /// received care). This is typically 0 for new SK assignments - most
  /// people are just household members until they receive clinical services.
  Future<int> patientCount() async {
    final data = await postOk(
      Endpoints.patientList,
      data: await _listRequest(0, 1),
      action: 'Patient count',
    );
    final total = (data is Map) ? data['totalCount'] : null;
    if (total is int) return total;
    if (total is num) return total.toInt();
    if (total is String) return int.tryParse(total) ?? 0;
    return 0;
  }

  Future<int> householdCount({int pageSize = 100, int hardCapPages = 50}) async {
    final result = await householdAndMemberCount(
      pageSize: pageSize,
      hardCapPages: hardCapPages,
    );
    return result.households;
  }

  /// Returns the sub-village IDs for the current user.
  /// Used by the household list screen to fetch all households.
  Future<List<int>> getSubVillageIds() async {
    _cachedSubVillageIds ??= await _authRepo.subVillageIds();
    return _cachedSubVillageIds!;
  }

  /// Returns all households for the current user's sub-villages.
  Future<List<Map<String, dynamic>>> getAllHouseholds({
    int pageSize = 100,
    int hardCapPages = 5,
  }) async {
    final results = <Map<String, dynamic>>[];
    int skip = 0;
    int page = 0;
    while (page < hardCapPages) {
      final body = await postOk(
        Endpoints.householdList,
        data: await _listRequest(skip, pageSize),
        action: 'Household list',
      );
      final list = extractList(body);
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          results.add(item);
        } else if (item is Map) {
          results.add(Map<String, dynamic>.from(item));
        }
      }
      if (list.length < pageSize) break;
      skip += pageSize;
      page++;
    }
    return results;
  }

  /// Returns all members for the current user's sub-villages.
  Future<List<Map<String, dynamic>>> getAllMembers({
    int pageSize = 100,
    int hardCapPages = 10,
  }) async {
    final results = <Map<String, dynamic>>[];
    int skip = 0;
    int page = 0;
    while (page < hardCapPages) {
      final body = await postOk(
        Endpoints.householdMemberList,
        data: await _listRequest(skip, pageSize),
        action: 'Member list',
      );
      final list = extractList(body);
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          results.add(item);
        } else if (item is Map) {
          results.add(Map<String, dynamic>.from(item));
        }
      }
      if (list.length < pageSize) break;
      skip += pageSize;
      page++;
    }
    return results;
  }

  /// Returns members grouped by household ID.
  Future<Map<String, List<Map<String, dynamic>>>> getMembersByHousehold() async {
    final members = await getAllMembers();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final m in members) {
      final hhId = m['householdId']?.toString();
      if (hhId != null && hhId.isNotEmpty) {
        grouped.putIfAbsent(hhId, () => []).add(m);
      }
    }
    return grouped;
  }

  /// Returns households with embedded member data.
  Future<List<Map<String, dynamic>>> getHouseholdsWithMembers({
    int pageSize = 100,
    int hardCapPages = 5,
  }) async {
    final households = await getAllHouseholds(
      pageSize: pageSize,
      hardCapPages: hardCapPages,
    );
    final membersByHh = await getMembersByHousehold();
    
    // Enrich households with their members
    for (final hh in households) {
      final hhId = hh['id']?.toString();
      if (hhId != null && membersByHh.containsKey(hhId)) {
        hh['householdMembers'] = membersByHh[hhId];
      }
    }
    return households;
  }

  /// Fetches a single household by ID with embedded member data.
  /// Uses the dedicated `/household/:householdId` endpoint.
  Future<Map<String, dynamic>?> getHouseholdById(String householdId) async {
    // ignore: avoid_print
    print('[DashboardRepository] fetching household by ID: $householdId');
    try {
      final body = await getOk(
        Endpoints.householdById(householdId),
        action: 'Household detail',
      );
      // ignore: avoid_print
      print('[DashboardRepository] household response: ${body.runtimeType}');
      
      if (body is Map) {
        // The API returns { "entity": { ... } } or { "data": { ... } }
        final entity = body['entity'] ?? body['data'] ?? body;
        if (entity is Map<String, dynamic>) {
          // ignore: avoid_print
          print('[DashboardRepository] household keys: ${entity.keys.toList()}');
          final members = entity['householdMembers'];
          // ignore: avoid_print
          print('[DashboardRepository] householdMembers: ${members?.runtimeType} length=${members is List ? members.length : 0}');
          return entity;
        }
        return Map<String, dynamic>.from(entity as Map);
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[DashboardRepository] error fetching household: $e');
      rethrow;
    }
  }
}
