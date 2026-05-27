import '../../core/api/api_repository.dart';
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

class HouseholdSearchRepository extends ApiRepository {
  HouseholdSearchRepository(super.api);

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
      final body = await postOk(
        Endpoints.householdList,
        data: {
          'skip': skip,
          'limit': pageSize,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'Household list',
      );
      final list = extractList(body);
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
}
