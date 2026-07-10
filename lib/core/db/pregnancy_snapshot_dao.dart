import 'package:sqflite/sqflite.dart';

import '../mission/mission_pregnancy_facts.dart';
import 'app_database.dart';

/// Per-patient pregnancy snapshot persisted to `patient_pregnancy_snapshot`
/// (schema v8). Built at sync time from the bundle's `pregnancyInfos[]` array;
/// read by `MissionDashboardRepository` to feed
/// `MissionInputData.pregnancyByPatientId`.
///
/// One row per patient — re-syncing replaces the row in place.
class PregnancySnapshotRow {
  const PregnancySnapshotRow({
    required this.patientId,
    required this.facts,
    this.updatedAt,
    this.eddDate,
    this.lmpDate,
  });

  final String patientId;
  final PregnancyFacts facts;
  final int? updatedAt;

  /// EDD as epoch milliseconds — from `pregnancyInfos[].estimatedDeliveryDate`.
  final int? eddDate;

  /// LMP as epoch milliseconds — from `pregnancyInfos[].lmpDate` (or similar).
  /// Preferred over deriving from EDD; stored at sync time so Form 2 can show
  /// gestational age without requiring the server to echo it in assessment rows.
  final int? lmpDate;

  Map<String, Object?> toDb() => {
        'patient_id': patientId,
        'high_risk_pregnant_woman': facts.highRiskPregnantWoman ? 1 : 0,
        'has_gaps_in_anc': facts.hasGapsInAnc ? 1 : 0,
        'is_postpartum_window': facts.isPostpartumWindow ? 1 : 0,
        'is_near_term_anc': facts.isNearTermAnc ? 1 : 0,
        'had_delivery_complications': facts.hadDeliveryComplications ? 1 : 0,
        'has_pnc_illness': facts.hasPncIllness ? 1 : 0,
        'updated_at': updatedAt,
        'edd_date': eddDate,
        'lmp_date': lmpDate,
      };

  static PregnancySnapshotRow fromDb(Map<String, Object?> row) =>
      PregnancySnapshotRow(
        patientId: row['patient_id'] as String,
        facts: PregnancyFacts(
          highRiskPregnantWoman: row['high_risk_pregnant_woman'] == 1,
          hasGapsInAnc: row['has_gaps_in_anc'] == 1,
          isPostpartumWindow: row['is_postpartum_window'] == 1,
          isNearTermAnc: row['is_near_term_anc'] == 1,
          hadDeliveryComplications: row['had_delivery_complications'] == 1,
          hasPncIllness: row['has_pnc_illness'] == 1,
        ),
        updatedAt: row['updated_at'] as int?,
        eddDate: row['edd_date'] as int?,
        lmpDate: row['lmp_date'] as int?,
      );
}

class PregnancySnapshotDao {
  PregnancySnapshotDao(this._db);

  final AppDatabase _db;

  Future<void> upsertMany(List<PregnancySnapshotRow> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.db.batch();
    for (final r in rows) {
      batch.insert(
        AppDatabase.tablePregnancySnapshot,
        r.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Bulk read — returns `patientId → PregnancyFacts` for *every* patient
  /// that has a stored snapshot. Callers should treat missing keys as
  /// [PregnancyFacts.empty].
  Future<Map<String, PregnancyFacts>> getAll() async {
    final rows = await _db.db.query(AppDatabase.tablePregnancySnapshot);
    final out = <String, PregnancyFacts>{};
    for (final r in rows) {
      final row = PregnancySnapshotRow.fromDb(r);
      out[row.patientId] = row.facts;
    }
    return out;
  }

  Future<PregnancySnapshotRow?> byPatient(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tablePregnancySnapshot,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PregnancySnapshotRow.fromDb(rows.first);
  }

  Future<void> clearAll() async {
    await _db.db.delete(AppDatabase.tablePregnancySnapshot);
  }
}
