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

  static const _inChunkSize = 400;

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
    final upperKinds = kinds.map((k) => k.toUpperCase()).toList();
    final out = <String, int>{};
    for (var i = 0; i < patientIds.length; i += _inChunkSize) {
      final chunk = patientIds.sublist(
        i,
        i + _inChunkSize > patientIds.length
            ? patientIds.length
            : i + _inChunkSize,
      );
      final pp = List.filled(chunk.length, '?').join(',');
      final kp = List.filled(upperKinds.length, '?').join(',');
      final rows = await _db.db.rawQuery(
        'SELECT patient_id, COUNT(*) AS cnt FROM ${AppDatabase.tableAssessments} '
        'WHERE patient_id IN ($pp) '
        'AND UPPER(kind) IN ($kp) '
        'GROUP BY patient_id',
        [...chunk, ...upperKinds],
      );
      for (final r in rows) {
        final pid = AssessmentRow._cellAsString(r['patient_id']);
        if (pid == null) continue;
        out[pid] = r['cnt'] as int;
      }
    }
    return out;
  }

  /// Latest synced assessment per patient — one row each (roster badges).
  Future<Map<String, AssessmentRow>> latestAssessmentForMany(
    List<String> patientIds,
  ) async {
    if (patientIds.isEmpty) return const <String, AssessmentRow>{};
    final out = <String, AssessmentRow>{};
    for (var i = 0; i < patientIds.length; i += _inChunkSize) {
      final chunk = patientIds.sublist(
        i,
        i + _inChunkSize > patientIds.length
            ? patientIds.length
            : i + _inChunkSize,
      );
      final pp = List.filled(chunk.length, '?').join(',');
      final rows = await _db.db.rawQuery(
        '''
SELECT a.id, a.patient_id, a.kind, a.occurred_at, a.raw_json
FROM ${AppDatabase.tableAssessments} AS a
INNER JOIN (
  SELECT patient_id, MAX(occurred_at) AS max_at
  FROM ${AppDatabase.tableAssessments}
  WHERE patient_id IN ($pp)
  GROUP BY patient_id
) AS t ON a.patient_id = t.patient_id AND a.occurred_at = t.max_at
''',
        chunk,
      );
      for (final r in rows) {
        final row = AssessmentRow.fromDb(r);
        out.putIfAbsent(row.patientId, () => row);
      }
    }
    return out;
  }

  Future<Map<String, List<AssessmentRow>>> forMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const <String, List<AssessmentRow>>{};
    final out = <String, List<AssessmentRow>>{};
    for (var i = 0; i < patientIds.length; i += _inChunkSize) {
      final chunk = patientIds.sublist(
        i,
        i + _inChunkSize > patientIds.length
            ? patientIds.length
            : i + _inChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await _db.db.query(
        AppDatabase.tableAssessments,
        where: 'patient_id IN ($placeholders)',
        whereArgs: chunk,
        orderBy: 'occurred_at DESC',
      );
      for (final r in rows) {
        final pid = AssessmentRow._cellAsString(r['patient_id']);
        if (pid == null) continue;
        (out[pid] ??= <AssessmentRow>[]).add(AssessmentRow.fromDb(r));
      }
    }
    return out;
  }
}
