import '../../core/api/api_repository.dart';
import '../../core/db/member_dao.dart';

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

/// Searches household members by name — local SQLite only.
///
/// Search runs entirely against the member table populated by
/// offline-sync/fetch-synced-data. No remote search calls are made.
class MemberSearchRepository extends ApiRepository {
  MemberSearchRepository(super.api, this._members);

  final MemberDao _members;

  static const int displayCap = 50;

  Future<MemberSearchResult> search({
    required String query,
    void Function(MemberSearchProgress)? onProgress,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return MemberSearchResult(matches: const [], totalScanned: 0, truncated: false);
    }

    onProgress?.call(MemberSearchProgress(0, displayCap));

    final rows = await _members.searchByName(q, limit: displayCap);
    final matches = rows.map((m) => MemberHit(
          id: m.patientId ?? m.id,
          name: m.name,
          gender: m.gender,
          phone: m.phone,
          householdId: m.householdId,
        )).toList();

    onProgress?.call(MemberSearchProgress(matches.length, displayCap));

    return MemberSearchResult(
      matches: matches,
      totalScanned: matches.length,
      truncated: matches.length >= displayCap,
    );
  }
}
