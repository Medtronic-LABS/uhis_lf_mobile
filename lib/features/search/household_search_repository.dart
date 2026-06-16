import '../../core/db/household_dao.dart';

enum HouseholdSearchField { name, householdNo }

class HouseholdHit {
  HouseholdHit({
    this.id,
    this.name,
    this.householdNo,
    this.village,
    this.memberCount,
    this.rawJson,
  });

  final String? id;
  final String? name;
  final String? householdNo;
  final String? village;
  final int? memberCount;
  final Map<String, dynamic>? rawJson;

  static HouseholdHit fromEntity(HouseholdEntity h) => HouseholdHit(
        id: h.id,
        name: h.name,
        householdNo: h.householdNo,
        village: h.village,
        memberCount: h.memberCount,
        rawJson: h.toDb().cast<String, dynamic>(),
      );

  static HouseholdHit fromJson(Map json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? members;
    final m = json['noOfPeople'] ?? json['memberCount'];
    if (m is int) members = m;
    else if (m is num) members = m.toInt();
    if (members == null && json['householdMembers'] is List) {
      members = (json['householdMembers'] as List).length;
    }
    return HouseholdHit(
      id: str('id'),
      name: str('name'),
      householdNo: str('householdNo'),
      village: str('village'),
      memberCount: members,
      rawJson: json is Map<String, dynamic> ? json : Map<String, dynamic>.from(json),
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

/// Searches households from local SQLite — all data comes from offline sync.
class HouseholdSearchRepository {
  HouseholdSearchRepository(this._households);

  final HouseholdDao _households;
  static const int displayCap = 50;

  Future<HouseholdSearchResult> search({
    required HouseholdSearchField field,
    required String query,
    void Function(HouseholdSearchProgress)? onProgress,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return HouseholdSearchResult(matches: const [], totalScanned: 0, truncated: false);
    }

    onProgress?.call(HouseholdSearchProgress(0, displayCap));

    final rows = field == HouseholdSearchField.householdNo
        ? await _households.search(q, limit: displayCap + 1)
        : await _households.search(q, limit: displayCap + 1);

    final truncated = rows.length > displayCap;
    final hits = rows.take(displayCap).map(HouseholdHit.fromEntity).toList();

    onProgress?.call(HouseholdSearchProgress(hits.length, displayCap));
    return HouseholdSearchResult(
      matches: hits,
      totalScanned: rows.length,
      truncated: truncated,
    );
  }
}
