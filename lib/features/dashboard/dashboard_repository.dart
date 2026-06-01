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
  
  /// Cached members grouped by household ID for fast lookup.
  Map<String, List<Map<String, dynamic>>>? _cachedMembersByHousehold;

  /// Clears cached data. Call this on logout to ensure fresh data on next login.
  void clearCache() {
    _cachedSubVillageIds = null;
    _cachedMembersByHousehold = null;
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
      // API may ignore pagination and return all data - stop if we get more than requested
      if (list.length > pageSize) break;
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
      // API may ignore pagination and return all data - stop if we get more than requested
      if (list.length > pageSize) break;
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
      // API may ignore pagination and return all data - stop if we get more than requested
      if (list.length > pageSize) break;
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
  /// For large datasets (>500 households), skips member enrichment to avoid timeouts.
  Future<List<Map<String, dynamic>>> getHouseholdsWithMembers({
    int pageSize = 100,
    int hardCapPages = 5,
  }) async {
    final households = await getAllHouseholds(
      pageSize: pageSize,
      hardCapPages: hardCapPages,
    );
    
    // Skip member enrichment for large datasets - member API times out
    if (households.length > 500) {
      // ignore: avoid_print
      print('[DashboardRepository] Skipping member enrichment for ${households.length} households');
      return households;
    }
    
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

  /// Fetches members for a specific household.
  /// Tries multiple API approaches since spice-service doesn't reliably support
  /// household filtering.
  Future<List<Map<String, dynamic>>> getMembersForHousehold(String householdId) async {
    // ignore: avoid_print
    print('[DashboardRepository] fetching members for household: $householdId');
    
    // Check cache first
    if (_cachedMembersByHousehold != null) {
      final cached = _cachedMembersByHousehold![householdId];
      if (cached != null) {
        // ignore: avoid_print
        print('[DashboardRepository] returning ${cached.length} cached members');
        return cached;
      }
    }
    
    // Approach 1: Try household-member-link/list with householdId
    try {
      final req = <String, dynamic>{
        'skip': 0,
        'limit': 100,
        'tenantId': api.tenantIdAsNum,
        'householdId': int.tryParse(householdId) ?? householdId,
      };
      // ignore: avoid_print
      print('[DashboardRepository] trying household-member-link with: $req');
      final body = await postOk(
        Endpoints.householdMemberLinkList,
        data: req,
        action: 'Household member links',
      );
      final list = extractList(body);
      if (list.isNotEmpty) {
        final results = <Map<String, dynamic>>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            results.add(item);
          } else if (item is Map) {
            results.add(Map<String, dynamic>.from(item));
          }
        }
        // ignore: avoid_print
        print('[DashboardRepository] got ${results.length} members from household-member-link');
        return results;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[DashboardRepository] household-member-link failed: $e');
    }
    
    // Approach 2: Fall back to member/list with householdIds array
    try {
      final req2 = <String, dynamic>{
        'skip': 0,
        'limit': 100,
        'tenantId': api.tenantIdAsNum,
        'householdIds': [int.tryParse(householdId) ?? householdId],
      };
      // ignore: avoid_print
      print('[DashboardRepository] trying member/list with householdIds: $req2');
      final body = await postOk(
        Endpoints.householdMemberList,
        data: req2,
        action: 'Household members',
      );
      final list = extractList(body);
      final results = <Map<String, dynamic>>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          results.add(item);
        } else if (item is Map) {
          results.add(Map<String, dynamic>.from(item));
        }
      }
      // ignore: avoid_print
      print('[DashboardRepository] got ${results.length} members from member/list');
      if (results.isNotEmpty) return results;
    } catch (e) {
      // ignore: avoid_print
      print('[DashboardRepository] member/list failed: $e');
    }
    
    // Approach 3: Fetch ALL members and filter client-side
    // This is expensive but necessary when API doesn't support filtering
    try {
      // ignore: avoid_print
      print('[DashboardRepository] falling back to fetch-all + client filter');
      final allMembers = await getAllMembers(pageSize: 500, hardCapPages: 3);
      // ignore: avoid_print
      print('[DashboardRepository] fetched ${allMembers.length} total members');
      
      // Cache all members grouped by household for future lookups
      _cachedMembersByHousehold = <String, List<Map<String, dynamic>>>{};
      for (final m in allMembers) {
        final hhId = m['householdId']?.toString();
        if (hhId != null && hhId.isNotEmpty) {
          _cachedMembersByHousehold!.putIfAbsent(hhId, () => []).add(m);
        }
      }
      // ignore: avoid_print
      print('[DashboardRepository] cached members for ${_cachedMembersByHousehold!.length} households');
      
      final filtered = _cachedMembersByHousehold![householdId] ?? [];
      // ignore: avoid_print
      print('[DashboardRepository] returning ${filtered.length} members for household $householdId');
      return filtered;
    } catch (e) {
      // ignore: avoid_print
      print('[DashboardRepository] fetch-all failed: $e');
      return [];
    }
  }

  /// Fetches a single household by ID with embedded member data.
  /// Uses the dedicated `/household/:householdId` endpoint + separate member fetch.
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
        Map<String, dynamic> result;
        if (entity is Map<String, dynamic>) {
          result = entity;
        } else {
          result = Map<String, dynamic>.from(entity as Map);
        }
        
        // ignore: avoid_print
        print('[DashboardRepository] household keys: ${result.keys.toList()}');
        
        // If householdMembers is null/empty, fetch them separately
        final existingMembers = result['householdMembers'];
        if (existingMembers == null || (existingMembers is List && existingMembers.isEmpty)) {
          // ignore: avoid_print
          print('[DashboardRepository] householdMembers empty, fetching separately');
          final members = await getMembersForHousehold(householdId);
          result['householdMembers'] = members;
        }
        
        final members = result['householdMembers'];
        // ignore: avoid_print
        print('[DashboardRepository] final householdMembers: ${members?.runtimeType} length=${members is List ? members.length : 0}');
        return result;
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[DashboardRepository] error fetching household: $e');
      rethrow;
    }
  }
}
