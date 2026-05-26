import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

enum HouseholdSearchField { name, householdNo }

class HouseholdHit {
  HouseholdHit({this.name, this.householdNo, this.village, this.memberCount});

  final String? name;
  final String? householdNo;
  final String? village;
  final int? memberCount;

  static HouseholdHit fromJson(Map json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? members;
    final members1 = json['noOfPeople'];
    if (members1 is int) members = members1;
    else if (members1 is num) members = members1.toInt();
    else if (members1 is String) members = int.tryParse(members1);
    if (members == null && json['householdMembers'] is List) {
      members = (json['householdMembers'] as List).length;
    }

    return HouseholdHit(
      name: str('name'),
      householdNo: str('householdNo'),
      village: str('village'),
      memberCount: members,
    );
  }
}

class HouseholdSearchProgress {
  HouseholdSearchProgress(this.loaded, this.cap);
  final int loaded;
  final int cap;
}

class HouseholdSearchResult {
  HouseholdSearchResult({
    required this.matches,
    required this.totalScanned,
    required this.truncated,
  });
  final List<HouseholdHit> matches;
  final int totalScanned;
  final bool truncated;
}

class HouseholdSearchRepository {
  HouseholdSearchRepository(this._api);

  final ApiClient _api;

  static const int pageSize = 100;
  static const int maxPages = 5;
  static const int displayCap = 50;

  Future<HouseholdSearchResult> search({
    required HouseholdSearchField field,
    required String query,
    void Function(HouseholdSearchProgress)? onProgress,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return HouseholdSearchResult(
        matches: const [],
        totalScanned: 0,
        truncated: false,
      );
    }
    final matches = <HouseholdHit>[];
    int scanned = 0;
    int skip = 0;
    bool ranOut = false;
    for (int page = 0; page < maxPages; page++) {
      onProgress?.call(HouseholdSearchProgress(scanned, pageSize * maxPages));
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
      final list = _extractList(resp.data);
      scanned += list.length;
      for (final raw in list) {
        if (raw is! Map) continue;
        final hit = HouseholdHit.fromJson(raw);
        final hay = (field == HouseholdSearchField.name)
            ? (hit.name ?? '')
            : (hit.householdNo ?? '');
        if (hay.toLowerCase().contains(q)) {
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
    onProgress?.call(HouseholdSearchProgress(scanned, pageSize * maxPages));
    return HouseholdSearchResult(
      matches: matches,
      totalScanned: scanned,
      truncated: ranOut,
    );
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
