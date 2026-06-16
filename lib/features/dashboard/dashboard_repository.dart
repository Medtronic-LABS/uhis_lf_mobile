import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/member_dao.dart';

class DashboardRepository extends ApiRepository {
  DashboardRepository(super.api, this._authRepo, this._households, this._members);

  final AuthRepository _authRepo;
  final HouseholdDao _households;
  final MemberDao _members;

  Future<List<int>> getSubVillageIds() => _authRepo.villageIds();

  /// Household and member counts from local SQLite — instant, no network.
  Future<({int households, int members})> householdAndMemberCount() async {
    final h = await _households.count();
    final m = await _members.count();
    return (households: h, members: m);
  }

  Future<int> householdCount() async => _households.count();

  /// Enrolled patient count from server (not in local DB).
  Future<int> patientCount() async {
    final villageIds = await _authRepo.villageIds();
    final data = await postOk(
      Endpoints.patientList,
      data: {
        'skip': 0,
        'limit': 1,
        'tenantId': api.tenantIdAsNum,
        if (villageIds.isNotEmpty) 'villageIds': villageIds,
      },
      action: 'Patient count',
    );
    final total = (data is Map) ? data['totalCount'] : null;
    if (total is int) return total;
    if (total is num) return total.toInt();
    if (total is String) return int.tryParse(total) ?? 0;
    return 0;
  }

  /// All households from local SQLite.
  Future<List<Map<String, dynamic>>> getAllHouseholds() async {
    final rows = await _households.getAll(limit: 1000);
    return rows.map((h) => h.toDb().cast<String, dynamic>()).toList();
  }

  /// Members grouped by household ID from local SQLite.
  Future<Map<String, List<Map<String, dynamic>>>> getMembersByHousehold() async {
    final grouped = await _members.getAllGroupedByHousehold();
    return grouped.map((hhId, members) => MapEntry(
          hhId,
          members.map((m) => m.toDb().cast<String, dynamic>()).toList(),
        ));
  }

  /// Members for a specific household from local SQLite.
  Future<List<Map<String, dynamic>>> getMembersForHousehold(String householdId) async {
    final rows = await _members.getByHouseholdId(householdId);
    return rows.map((m) => m.toDb().cast<String, dynamic>()).toList();
  }

  /// Household with embedded members from local SQLite.
  Future<Map<String, dynamic>?> getHouseholdById(String householdId) async {
    final hh = await _households.getById(householdId);
    if (hh == null) return null;
    final result = hh.toDb().cast<String, dynamic>();
    final memberRows = await _members.getByHouseholdId(householdId);
    result['householdMembers'] =
        memberRows.map((m) => m.toDb().cast<String, dynamic>()).toList();
    return result;
  }

  /// Households with embedded members from local SQLite.
  Future<List<Map<String, dynamic>>> getHouseholdsWithMembers() async {
    final households = await _households.getAll(limit: 1000);
    final grouped = await _members.getAllGroupedByHousehold();
    return households.map((hh) {
      final result = hh.toDb().cast<String, dynamic>();
      final memberRows = grouped[hh.id] ?? [];
      result['householdMembers'] =
          memberRows.map((m) => m.toDb().cast<String, dynamic>()).toList();
      return result;
    }).toList();
  }

  /// All members as flat list from local SQLite.
  Future<List<Map<String, dynamic>>> getAllMembers() async {
    final grouped = await _members.getAllGroupedByHousehold();
    return grouped.values
        .expand((list) => list)
        .map((m) => m.toDb().cast<String, dynamic>())
        .toList();
  }
}
