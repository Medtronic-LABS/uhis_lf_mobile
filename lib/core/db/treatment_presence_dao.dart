import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Records that a patient has at least one `treatmentDetails[]` row in the
/// bundle (schema v8 — `patient_treatment_presence`). Persisted at sync time;
/// read by `MissionDashboardRepository` to feed
/// `MissionInputData.patientsOnTreatment`.
///
/// Boolean presence only — clinical specifics live elsewhere (and are out
/// of scope for the Mission Dashboard tier classifier).
class TreatmentPresenceDao {
  TreatmentPresenceDao(this._db);

  final AppDatabase _db;

  Future<void> upsertAll(Set<String> patientIds, {int? updatedAt}) async {
    if (patientIds.isEmpty) return;
    final batch = _db.db.batch();
    for (final pid in patientIds) {
      batch.insert(
        AppDatabase.tableTreatmentPresence,
        <String, Object?>{
          'patient_id': pid,
          'updated_at': updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Set<String>> getAll() async {
    final rows = await _db.db.query(
      AppDatabase.tableTreatmentPresence,
      columns: ['patient_id'],
    );
    return rows
        .map((r) => r['patient_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  Future<void> clearAll() async {
    await _db.db.delete(AppDatabase.tableTreatmentPresence);
  }
}
