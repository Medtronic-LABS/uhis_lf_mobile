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

  static String? _cellAsString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static AssessmentRow fromDb(Map<String, Object?> row) => AssessmentRow(
        id: _cellAsString(row['id'])!,
        patientId: _cellAsString(row['patient_id'])!,
        kind: _cellAsString(row['kind']),
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

  /// Returns completed visit count per patient, keyed by patient_id.
  /// Single SQL round-trip; used by WorklistRepository.load().
  Future<Map<String, int>> visitCountsByPatients(
    List<String> patientIds,
    List<String> kinds,
  ) async {
    if (patientIds.isEmpty || kinds.isEmpty) return const <String, int>{};
    final pp = List.filled(patientIds.length, '?').join(',');
    final kp = List.filled(kinds.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT patient_id, COUNT(*) AS cnt FROM ${AppDatabase.tableAssessments} '
      'WHERE patient_id IN ($pp) '
      'AND UPPER(kind) IN ($kp) '
      'GROUP BY patient_id',
      [...patientIds, ...kinds.map((k) => k.toUpperCase())],
    );
    final out = <String, int>{};
    for (final r in rows) {
      final pid = AssessmentRow._cellAsString(r['patient_id']);
      if (pid == null) continue;
      out[pid] = r['cnt'] as int;
    }
    return out;
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
      final pid = AssessmentRow._cellAsString(r['patient_id']);
      if (pid == null) continue;
      (out[pid] ??= <AssessmentRow>[]).add(AssessmentRow.fromDb(r));
    }
    return out;
  }
}
