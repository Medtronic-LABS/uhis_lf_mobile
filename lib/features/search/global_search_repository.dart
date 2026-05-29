import 'household_search_repository.dart';
import 'member_search_repository.dart';

enum SearchScope { all, patients, households }

class GlobalSearchHits {
  GlobalSearchHits({
    this.members = const [],
    this.households = const [],
    this.membersScanned = 0,
    this.membersTruncated = false,
    this.householdsScanned = 0,
    this.householdsTruncated = false,
    this.error,
  });

  final List<MemberHit> members;
  final List<HouseholdHit> households;
  final int membersScanned;
  final bool membersTruncated;
  final int householdsScanned;
  final bool householdsTruncated;
  final Object? error;

  bool get isEmpty => members.isEmpty && households.isEmpty;
}

class GlobalSearchRepository {
  GlobalSearchRepository(this._member, this._household);

  final MemberSearchRepository _member;
  final HouseholdSearchRepository _household;

  Future<GlobalSearchHits> search({
    required String query,
    SearchScope scope = SearchScope.all,
    void Function(MemberSearchProgress)? onMemberProgress,
    void Function(HouseholdSearchProgress)? onHouseholdProgress,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return GlobalSearchHits();

    // Each source degrades to an empty result on failure so one failing source
    // never blanks the other — but the error is captured (not swallowed) so the
    // UI can tell "no matches" apart from "search failed".
    Object? memberError;
    Object? householdError;

    Future<MemberSearchResult> runMembers() async {
      try {
        return await _member.search(
          query: q,
          onProgress: onMemberProgress,
        );
      } catch (e) {
        memberError = e;
        return MemberSearchResult(
          matches: const [],
          totalScanned: 0,
          truncated: false,
        );
      }
    }

    Future<HouseholdSearchResult> runHouseholds() async {
      try {
        final byName = await _household.search(
          field: HouseholdSearchField.name,
          query: q,
          onProgress: onHouseholdProgress,
        );
        if (byName.matches.isNotEmpty) return byName;
        return await _household.search(
          field: HouseholdSearchField.householdNo,
          query: q,
          onProgress: onHouseholdProgress,
        );
      } catch (e) {
        householdError = e;
        return HouseholdSearchResult(
          matches: const [],
          totalScanned: 0,
          truncated: false,
        );
      }
    }

    switch (scope) {
      case SearchScope.patients:
        // "Patients" scope searches all members (name, phone, NID, household)
        final m = await runMembers();
        return GlobalSearchHits(
          members: m.matches,
          membersScanned: m.totalScanned,
          membersTruncated: m.truncated,
          error: memberError,
        );
      case SearchScope.households:
        final h = await runHouseholds();
        return GlobalSearchHits(
          households: h.matches,
          householdsScanned: h.totalScanned,
          householdsTruncated: h.truncated,
          error: householdError,
        );
      case SearchScope.all:
        final results = await Future.wait([runMembers(), runHouseholds()]);
        final m = results[0] as MemberSearchResult;
        final h = results[1] as HouseholdSearchResult;
        // Surface an error only when both sources failed and nothing returned;
        // a partial result is shown without an error banner.
        final bothFailed = memberError != null && householdError != null;
        return GlobalSearchHits(
          members: m.matches,
          membersScanned: m.totalScanned,
          membersTruncated: m.truncated,
          households: h.matches,
          householdsScanned: h.totalScanned,
          householdsTruncated: h.truncated,
          error: bothFailed ? memberError : null,
        );
    }
  }
}
