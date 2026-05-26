import 'household_search_repository.dart';
import 'patient_search_repository.dart';

enum SearchScope { all, patients, households }

class GlobalSearchHits {
  GlobalSearchHits({
    this.patients = const [],
    this.households = const [],
    this.householdsScanned = 0,
    this.householdsTruncated = false,
    this.error,
  });

  final List<PatientHit> patients;
  final List<HouseholdHit> households;
  final int householdsScanned;
  final bool householdsTruncated;
  final Object? error;

  bool get isEmpty => patients.isEmpty && households.isEmpty;
}

class GlobalSearchRepository {
  GlobalSearchRepository(this._patient, this._household);

  final PatientSearchRepository _patient;
  final HouseholdSearchRepository _household;

  static const _digitsOnly = r'^\d+$';

  Future<GlobalSearchHits> search({
    required String query,
    SearchScope scope = SearchScope.all,
    void Function(HouseholdSearchProgress)? onHouseholdProgress,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return GlobalSearchHits();

    Future<List<PatientHit>> runPatients() async {
      final field = _detectPatientField(q);
      try {
        return await _patient.search(field: field, query: q);
      } catch (_) {
        return const [];
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
      } catch (_) {
        return HouseholdSearchResult(
          matches: const [],
          totalScanned: 0,
          truncated: false,
        );
      }
    }

    switch (scope) {
      case SearchScope.patients:
        final p = await runPatients();
        return GlobalSearchHits(patients: p);
      case SearchScope.households:
        final h = await runHouseholds();
        return GlobalSearchHits(
          households: h.matches,
          householdsScanned: h.totalScanned,
          householdsTruncated: h.truncated,
        );
      case SearchScope.all:
        final results = await Future.wait([runPatients(), runHouseholds()]);
        final p = results[0] as List<PatientHit>;
        final h = results[1] as HouseholdSearchResult;
        return GlobalSearchHits(
          patients: p,
          households: h.matches,
          householdsScanned: h.totalScanned,
          householdsTruncated: h.truncated,
        );
    }
  }

  PatientSearchField _detectPatientField(String q) {
    if (RegExp(_digitsOnly).hasMatch(q) && q.length >= 6) {
      return PatientSearchField.phone;
    }
    if (q.length >= 4 && RegExp(r'^[A-Za-z0-9-]+$').hasMatch(q) &&
        RegExp(r'\d').hasMatch(q) && RegExp(r'[A-Za-z]').hasMatch(q)) {
      return PatientSearchField.nid;
    }
    return PatientSearchField.name;
  }
}
