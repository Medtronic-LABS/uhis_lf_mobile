import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class AssessmentRow {
  const AssessmentRow({
    required this.id,
    required this.patientId,
    this.kind,
    this.occurredAt,
    required this.rawJson,
  });

  final String id;
  final String patientId;
  final String? kind;
  final int? occurredAt;
  final String rawJson;

  Map<String, Object?> toDb() => {
        'id': id,
        'patient_id': patientId,
        'kind': kind,
        'occurred_at': occurredAt,
        'raw_json': rawJson,
      };

  static AssessmentRow fromDb(Map<String, Object?> row) => AssessmentRow(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        kind: row['kind'] as String?,
        occurredAt: row['occurred_at'] as int?,
        rawJson: row['raw_json'] as String? ?? '{}',
      );
}

class AssessmentDao {
  AssessmentDao(this._db);

  final AppDatabase _db;

  Future<void> upsertMany(List<AssessmentRow> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.db.batch();
    for (final r in rows) {
      batch.insert(
        AppDatabase.tableAssessments,
        r.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, List<AssessmentRow>>> forMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const <String, List<AssessmentRow>>{};
    final placeholders = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableAssessments,
      where: 'patient_id IN ($placeholders)',
      whereArgs: patientIds,
      orderBy: 'occurred_at DESC',
    );
    final out = <String, List<AssessmentRow>>{};
    for (final r in rows) {
      final pid = r['patient_id'] as String?;
      if (pid == null) continue;
      (out[pid] ??= <AssessmentRow>[]).add(AssessmentRow.fromDb(r));
    }
    return out;
  }
}
