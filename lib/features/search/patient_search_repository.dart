import '../../core/api/api_repository.dart';
import '../../core/db/member_dao.dart';

enum PatientSearchField { name, phone, nid }

class PatientHit {
  PatientHit({
    this.id,
    this.memberReference,
    this.patientReference,
    this.name,
    this.age,
    this.phone,
    this.nid,
    this.gender,
    this.householdId,
    this.villageId,
  });

  final String? id;
  final String? memberReference;
  final String? patientReference;
  final String? name;
  final String? age;
  final String? phone;
  final String? nid;
  final String? gender;
  final String? householdId;
  final String? villageId;
}

/// Patient/member search repository — local SQLite only.
///
/// All search is performed against the locally-synced member table populated
/// by offline-sync/fetch-synced-data. No remote search calls are made.
class PatientSearchRepository extends ApiRepository {
  PatientSearchRepository(super.api, {this._memberDao});

  final MemberDao? _memberDao;

  Future<List<PatientHit>> search({
    required PatientSearchField field,
    required String query,
    int limit = 50,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final dao = _memberDao;
    if (dao == null) return const [];

    final rows = await dao.searchByName(q, limit: limit);
    return rows.map((m) => PatientHit(
          id: m.patientId ?? m.id,
          name: m.name,
          gender: m.gender,
          phone: m.phone,
          householdId: m.householdId,
        )).toList();
  }
}
