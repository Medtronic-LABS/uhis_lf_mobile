import 'package:sqflite/sqflite.dart';

import '../models/programme.dart';
import 'app_database.dart';

/// Data-access for the normalised `patient_programmes` table — the indexed
/// home for chip-filter queries.
class PatientProgrammesDao {
  PatientProgrammesDao(this._db);

  final AppDatabase _db;

  /// Replace the programme set for [patientId] in a single statement.
  /// Idempotent — safe to call after every patient sync.
  Future<void> replaceFor(
      String patientId, Set<Programme> programmes) async {
    await _db.db.transaction((tx) async {
      await tx.delete(
        AppDatabase.tablePatientProgrammes,
        where: 'patient_id = ?',
        whereArgs: [patientId],
      );
      if (programmes.isEmpty) return;
      final batch = tx.batch();
      for (final p in programmes) {
        batch.insert(
          AppDatabase.tablePatientProgrammes,
          {'patient_id': patientId, 'programme': p.wireTag},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Set<Programme>> programmesFor(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tablePatientProgrammes,
      columns: const ['programme'],
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
    final out = <Programme>{};
    for (final r in rows) {
      final tag = r['programme'] as String?;
      final p = Programme.fromWireTag(tag);
      if (p != null) out.add(p);
    }
    return out;
  }

  /// Bulk read — returns a `patientId → Set<Programme>` map for the IDs given.
  /// Single SQL round-trip; used by the worklist repo to attach programme
  /// sets to a page of patient rows.
  Future<Map<String, Set<Programme>>> programmesForMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const <String, Set<Programme>>{};
    final placeholders = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT patient_id, programme FROM ${AppDatabase.tablePatientProgrammes} '
      'WHERE patient_id IN ($placeholders)',
      patientIds,
    );
    final out = <String, Set<Programme>>{};
    for (final r in rows) {
      final pid = r['patient_id'] as String?;
      final tag = r['programme'] as String?;
      final p = Programme.fromWireTag(tag);
      if (pid == null || p == null) continue;
      (out[pid] ??= <Programme>{}).add(p);
    }
    return out;
  }
}
