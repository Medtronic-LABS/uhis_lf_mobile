import '../db/household_dao.dart';
import '../db/member_dao.dart';

/// Local-first dashboard data access.
/// Following Android spice-2.0 pattern: all reads are from local SQLite,
/// network sync populates the local cache.
/// 
/// This provides INSTANT response for dashboard counts vs network-based
/// DashboardRepository which has latency on every request.
class LocalDashboardRepository {
  LocalDashboardRepository({
    required HouseholdDao households,
    required MemberDao members,
  })  : _households = households,
        _members = members;

  final HouseholdDao _households;
  final MemberDao _members;

  /// Returns household and member counts from LOCAL SQLite (instant).
  /// Returns (0, 0) if local cache is empty (sync not completed yet).
  Future<({int households, int members})> householdAndMemberCount() async {
    final households = await _households.count();
    final members = await _members.count();
    return (households: households, members: members);
  }

  /// Returns household count from LOCAL SQLite.
  Future<int> householdCount() async {
    return _households.count();
  }

  /// Returns member count from LOCAL SQLite.
  Future<int> memberCount() async {
    return _members.count();
  }

  /// Returns true if local cache has data (sync has completed).
  Future<bool> hasLocalData() async {
    final count = await _households.count();
    return count > 0;
  }

  /// Get all households from LOCAL SQLite (instant, no network).
  Future<List<HouseholdEntity>> getHouseholds({
    int limit = 100,
    int offset = 0,
    String? searchTerm,
  }) async {
    return _households.getAll(limit: limit, offset: offset);
  }

  /// Get members for a household from LOCAL SQLite (instant, no network).
  Future<List<HouseholdMemberEntity>> getMembersByHousehold(String householdId) async {
    return _members.getByHouseholdId(householdId);
  }

  /// Get member by ID from LOCAL SQLite (instant, no network).
  Future<HouseholdMemberEntity?> getMemberById(String memberId) async {
    return _members.getById(memberId);
  }

  /// Get member by patient ID from LOCAL SQLite (instant, no network).
  Future<HouseholdMemberEntity?> getMemberByPatientId(String patientId) async {
    return _members.getByPatientId(patientId);
  }

  /// Search households by name from LOCAL SQLite.
  Future<List<HouseholdEntity>> searchHouseholds(String query, {int limit = 50}) async {
    return _households.search(query, limit: limit);
  }

  /// Search members by name from LOCAL SQLite.
  Future<List<HouseholdMemberEntity>> searchMembers(String query, {int limit = 50}) async {
    return _members.searchByName(query, limit: limit);
  }
}
