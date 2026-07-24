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
    this.deliveryDateMillis,
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

  /// Delivery date as epoch milliseconds — written locally after
  /// PREGNANCY_OUTCOME submission so `isPostpartum` is available immediately
  /// without waiting for a server re-sync (mirrors Android PregnancyCohortRules).
  final int? deliveryDateMillis;

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
        'delivery_date_millis': deliveryDateMillis,
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
        deliveryDateMillis: row['delivery_date_millis'] as int?,
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
    final rows = await getAllRows();
    return {for (final e in rows.entries) e.key: e.value.facts};
  }

  /// Full snapshot rows keyed by patient ID (includes `lmp_date` / `edd_date`).
  /// Used by sync to preserve dates the server omits on re-write.
  Future<Map<String, PregnancySnapshotRow>> getAllRows() async {
    final rows = await _db.db.query(AppDatabase.tablePregnancySnapshot);
    final out = <String, PregnancySnapshotRow>{};
    for (final r in rows) {
      final row = PregnancySnapshotRow.fromDb(r);
      out[row.patientId] = row;
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

  /// Insert or replace a single row — used by the pregnancy registration sheet
  /// to persist LMP/EDD/risk flags captured offline before the first ANC visit.
  Future<void> upsertOne(PregnancySnapshotRow row) async {
    await _db.db.insert(
      AppDatabase.tablePregnancySnapshot,
      row.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearAll() async {
    await _db.db.delete(AppDatabase.tablePregnancySnapshot);
  }

  /// Collapse multiple server episodes for the same patient into one row.
  ///
  /// `pregnancyInfos[]` often has several episodes per member; later rows
  /// frequently omit `lastMenstrualPeriod` / EDD even when an earlier episode
  /// has them. Prefer any non-null LMP/EDD so a null later row cannot wipe a
  /// good date before [upsertMany] (last-write-wins on `patient_id`).
  static List<PregnancySnapshotRow> coalesceByPatient(
    List<PregnancySnapshotRow> rows,
  ) {
    final byId = <String, PregnancySnapshotRow>{};
    for (final row in rows) {
      final prev = byId[row.patientId];
      if (prev == null) {
        byId[row.patientId] = row;
        continue;
      }
      final rowAt = row.updatedAt ?? 0;
      final prevAt = prev.updatedAt ?? 0;
      byId[row.patientId] = PregnancySnapshotRow(
        patientId: row.patientId,
        // Later episode facts tend to reflect current state (PNC window etc.).
        facts: row.facts,
        updatedAt: rowAt >= prevAt ? row.updatedAt : prev.updatedAt,
        eddDate: row.eddDate ?? prev.eddDate,
        lmpDate: row.lmpDate ?? prev.lmpDate,
        deliveryDateMillis: row.deliveryDateMillis ?? prev.deliveryDateMillis,
      );
    }
    return byId.values.toList(growable: false);
  }

  /// Merge server [incoming] rows with [prior] local snapshots.
  ///
  /// - Incoming is first coalesced per patient (see [coalesceByPatient]).
  /// - Incoming facts always win.
  /// - Null `lmpDate` / `eddDate` on incoming keeps the prior value.
  /// - Prior rows for patients absent from [incoming] are kept (local enroll).
  static List<PregnancySnapshotRow> mergePreservingDates({
    required List<PregnancySnapshotRow> incoming,
    required Map<String, PregnancySnapshotRow> prior,
  }) {
    final coalesced = coalesceByPatient(incoming);
    final incomingIds = <String>{};
    final merged = <PregnancySnapshotRow>[];
    for (final row in coalesced) {
      incomingIds.add(row.patientId);
      final prev = prior[row.patientId];
      merged.add(prev == null
          ? row
          : PregnancySnapshotRow(
              patientId: row.patientId,
              facts: row.facts,
              updatedAt: row.updatedAt,
              eddDate: row.eddDate ?? prev.eddDate,
              lmpDate: row.lmpDate ?? prev.lmpDate,
              deliveryDateMillis: row.deliveryDateMillis ?? prev.deliveryDateMillis,
            ));
    }
    for (final entry in prior.entries) {
      if (!incomingIds.contains(entry.key)) {
        merged.add(entry.value);
      }
    }
    return merged;
  }
}
