import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/patient.dart';
import '../models/programme.dart';
import 'app_database.dart';

/// Data-access for the `patients` table and the joined
/// `patient_programmes` row. The single home for worklist SQL — callers
/// never compose raw queries against patient storage.
class PatientDao {
  PatientDao(this._db);

  final AppDatabase _db;

  /// Bulk upsert. Caller is responsible for being inside a transaction when
  /// upserting alongside other entities.
  Future<void> upsertMany(List<Patient> patients) async {
    if (patients.isEmpty) return;
    final batch = _db.db.batch();
    for (final p in patients) {
      batch.insert(
        AppDatabase.tablePatients,
        p.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Update only the risk + scheduling fields on an existing patient row.
  /// Used by the worklist recompute pass — leaves the demographic columns
  /// untouched so they aren't accidentally wiped if a stale Patient instance
  /// is passed in.
  Future<void> updateRisk({
    required String patientId,
    required int score,
    required String bandWireTag,
    required String reasonsJson,
    int? nextDueAt,
    int? lastVisitAt,
    int? missedVisitCount,
    bool? redFlag,
  }) async {
    await _db.db.update(
      AppDatabase.tablePatients,
      {
        'risk_score': score,
        'risk_band': bandWireTag,
        'risk_reasons': reasonsJson,
        'next_due_at': ?nextDueAt,
        'last_visit_at': ?lastVisitAt,
        'missed_visit_count': ?missedVisitCount,
        if (redFlag != null) 'red_flag': redFlag ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [patientId],
    );
  }

  /// Update only visit scheduling fields after an assessment is completed.
  /// This is lighter than [updateRisk] — only touches the scheduling columns.
  Future<void> updateVisitSchedule({
    required String patientId,
    required int lastVisitAt,
    required int nextDueAt,
    int? missedVisitCount,
  }) async {
    await _db.db.update(
      AppDatabase.tablePatients,
      {
        'last_visit_at': lastVisitAt,
        'next_due_at': nextDueAt,
        'missed_visit_count': ?missedVisitCount,
      },
      where: 'id = ?',
      whereArgs: [patientId],
    );
  }

  Future<Patient?> byId(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tablePatients,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Patient.fromDb(rows.first);
  }

  Future<List<Patient>> allForVillages(List<String> villageIds) async {
    if (villageIds.isEmpty) {
      final rows = await _db.db.query(AppDatabase.tablePatients);
      return rows.map(Patient.fromDb).toList(growable: false);
    }
    final placeholders = List.filled(villageIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tablePatients,
      where: 'village_id IN ($placeholders)',
      whereArgs: villageIds,
    );
    return rows.map(Patient.fromDb).toList(growable: false);
  }

  /// Worklist query — ordered by `risk_score DESC, next_due_at ASC` and
  /// optionally chip-filtered by an indexed join on `patient_programmes`.
  ///
  /// Returns the raw joined rows; the worklist repository maps them to
  /// [WorklistEntry] (with [Programme] sets resolved separately to avoid
  /// row explosion from the JOIN).
  Future<List<Map<String, Object?>>> queryWorklist({
    Set<Programme> programmeFilter = const <Programme>{},
    int limit = 500,
    int offset = 0,
  }) async {
    if (programmeFilter.isEmpty) {
      return _db.db.query(
        AppDatabase.tablePatients,
        orderBy:
            'risk_score DESC NULLS LAST, next_due_at ASC NULLS LAST, name ASC',
        limit: limit,
        offset: offset,
      );
    }
    final placeholders =
        List.filled(programmeFilter.length, '?').join(',');
    final wireTags = programmeFilter.map((p) => p.wireTag).toList();
    return _db.db.rawQuery(
      'SELECT DISTINCT p.* FROM ${AppDatabase.tablePatients} p '
      'INNER JOIN ${AppDatabase.tablePatientProgrammes} pp '
      '  ON pp.patient_id = p.id '
      'WHERE pp.programme IN ($placeholders) '
      'ORDER BY p.risk_score DESC, p.next_due_at ASC, p.name ASC '
      'LIMIT ? OFFSET ?',
      [...wireTags, limit, offset],
    );
  }

  Future<int> count() async {
    final rows = await _db.db
        .rawQuery('SELECT COUNT(*) AS c FROM ${AppDatabase.tablePatients}');
    final c = rows.first['c'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return 0;
  }

  /// Copies sub_village_name from the members table into patients.village_name
  /// for every patient whose current village_name is null or looks like a raw
  /// numeric ID (i.e., no alphabetic chars). Called after _syncHouseholdsAndMembers
  /// so that the granular-sync sub-village text wins over the bundle's API-internal
  /// numeric village_id that may have landed in village_name.
  Future<int> propagateVillageNamesFromMembers() async {
    final updated = await _db.db.rawUpdate('''
      UPDATE ${AppDatabase.tablePatients}
      SET village_name = (
        SELECT m.sub_village_name
        FROM ${AppDatabase.tableMembers} m
        WHERE m.patient_id = ${AppDatabase.tablePatients}.id
          AND m.sub_village_name IS NOT NULL
          AND m.sub_village_name != ''
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM ${AppDatabase.tableMembers} m2
        WHERE m2.patient_id = ${AppDatabase.tablePatients}.id
          AND m2.sub_village_name IS NOT NULL
          AND m2.sub_village_name != ''
      )
      AND (
        village_name IS NULL
        OR village_name = ''
        OR village_name GLOB '[0-9]*'
      )
    ''');
    if (updated > 0) {
      debugPrint('[PatientDao] propagateVillageNamesFromMembers: $updated patients updated');
    }
    return updated;
  }

  /// Update visit timing columns without touching risk or demographic columns.
  /// Only non-null arguments are written; null arguments leave the column
  /// unchanged. Used after assessment-history sync to seed last_visit_at /
  /// next_due_at before the worklist recompute pass.
  Future<void> patchVisitTiming({
    required String patientId,
    int? lastVisitAt,
    int? nextDueAt,
  }) async {
    final values = <String, dynamic>{
      'last_visit_at': ?lastVisitAt,
      'next_due_at': ?nextDueAt,
    };
    if (values.isEmpty) return;
    await _db.db.update(
      AppDatabase.tablePatients,
      values,
      where: 'id = ?',
      whereArgs: [patientId],
    );
  }

  /// Clear all patients from the local database.
  /// Used before a fresh sync to remove stale data.
  Future<void> clearAll() async {
    await _db.db.delete(AppDatabase.tablePatients);
  }

  /// Query patients by household ID from local database.
  Future<List<Map<String, dynamic>>> getByHouseholdId(String householdId) async {
    return _db.db.query(
      AppDatabase.tablePatients,
      where: 'household_id = ?',
      whereArgs: [householdId],
      orderBy: 'name ASC',
    );
  }

  /// Returns a map of patientId → last_visit_at (ms) for the given IDs.
  Future<Map<String, int>> lastVisitAtForPatients(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const {};
    final ph = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT id, last_visit_at FROM ${AppDatabase.tablePatients} '
      'WHERE id IN ($ph) AND last_visit_at IS NOT NULL',
      patientIds,
    );
    return {
      for (final r in rows)
        if (r['id'] != null && r['last_visit_at'] != null)
          r['id'] as String: (r['last_visit_at'] as num).toInt(),
    };
  }
}
