import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  Future<int> patientCount() async {
    final resp = await _api.dio.post(
      Endpoints.patientList,
      data: {'skip': 0, 'limit': 1, 'tenantId': _tenantIdAsNum()},
    );
    if (resp.statusCode != 200) {
      throw Exception('Patient count failed (${resp.statusCode})');
    }
    final data = resp.data;
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
      final resp = await _api.dio.post(
        Endpoints.householdList,
        data: {
          'skip': skip,
          'limit': pageSize,
          'tenantId': _tenantIdAsNum(),
        },
      );
      if (resp.statusCode != 200) {
        throw Exception('Household list failed (${resp.statusCode})');
      }
      final body = resp.data;
      final list = _extractList(body);
      total += list.length;
      if (list.length < pageSize) break;
      skip += pageSize;
      page++;
    }
    return total;
  }

  Object? _tenantIdAsNum() {
    final t = _api.tenantId;
    if (t == null) return null;
    return int.tryParse(t) ?? t;
  }

  static List _extractList(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      if (body['entityList'] is List) return body['entityList'] as List;
      if (body['data'] is List) return body['data'] as List;
    }
    return const [];
  }
}
