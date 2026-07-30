import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class ImmunisationRow {
  const ImmunisationRow({
    required this.id,
    required this.patientId,
    this.vaccineCode,
    this.dueAt,
    this.givenAt,
    this.status,
    this.missedReason,
    required this.rawJson,
  });

  final String id;
  final String patientId;
  final String? vaccineCode;
  final int? dueAt;
  final int? givenAt;

  /// 'Vaccinated' | 'Missed' | null (no explicit outcome recorded yet).
  final String? status;

  /// Reason text captured when [status] is 'Missed'.
  final String? missedReason;
  final String rawJson;

  Map<String, Object?> toDb() => {
        'id': id,
        'patient_id': patientId,
        'vaccine_code': vaccineCode,
        'due_at': dueAt,
        'given_at': givenAt,
        'status': status,
        'missed_reason': missedReason,
        'raw_json': rawJson,
      };

  static ImmunisationRow fromDb(Map<String, Object?> row) => ImmunisationRow(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        vaccineCode: row['vaccine_code'] as String?,
        dueAt: row['due_at'] as int?,
        givenAt: row['given_at'] as int?,
        status: row['status'] as String?,
        missedReason: row['missed_reason'] as String?,
        rawJson: row['raw_json'] as String? ?? '{}',
      );
}

class ImmunisationDao {
  ImmunisationDao(this._db);

  final AppDatabase _db;

  Future<void> upsertMany(List<ImmunisationRow> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.db.batch();
    for (final r in rows) {
      batch.insert(
        AppDatabase.tableImmunisations,
        r.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, List<ImmunisationRow>>> forMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) {
      return const <String, List<ImmunisationRow>>{};
    }
    final placeholders = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableImmunisations,
      where: 'patient_id IN ($placeholders)',
      whereArgs: patientIds,
    );
    final out = <String, List<ImmunisationRow>>{};
    for (final r in rows) {
      final pid = r['patient_id'] as String?;
      if (pid == null) continue;
      (out[pid] ??= <ImmunisationRow>[]).add(ImmunisationRow.fromDb(r));
    }
    return out;
  }
}
