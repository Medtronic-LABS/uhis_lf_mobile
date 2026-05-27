import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';

class DashboardRepository extends ApiRepository {
  DashboardRepository(super.api);

  Future<int> patientCount() async {
    final data = await postOk(
      Endpoints.patientList,
      data: {'skip': 0, 'limit': 1, 'tenantId': api.tenantIdAsNum},
      action: 'Patient count',
    );
    final total = (data is Map) ? data['totalCount'] : null;
    if (total is int) return total;
    if (total is num) return total.toInt();
    if (total is String) return int.tryParse(total) ?? 0;
    return 0;
  }

  Future<int> householdCount({int pageSize = 100, int hardCapPages = 50}) async {
    int total = 0;
    int skip = 0;
    int page = 0;
    while (page < hardCapPages) {
      final body = await postOk(
        Endpoints.householdList,
        data: {'skip': skip, 'limit': pageSize, 'tenantId': api.tenantIdAsNum},
        action: 'Household list',
      );
      final list = extractList(body);
      total += list.length;
      if (list.length < pageSize) break;
      skip += pageSize;
      page++;
    }
    return total;
  }
}
