import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Wire-side kind tags for the `follow_ups.kind` column. Centralised so
/// `OfflineSyncService` and `RiskScoringService` agree on the spelling.
abstract final class FollowUpKind {
  FollowUpKind._();

  static const String generic = 'generic';
  static const String ncd = 'ncd';
  static const String screening = 'screening';
  static const String medicalReview = 'medical_review';
  static const String assessment = 'assessment';
  static const String lost = 'lost';
}

class FollowUpRow {
  const FollowUpRow({
    required this.id,
    required this.patientId,
    required this.kind,
    this.dueAt,
    this.completedAt,
    this.attempts,
    this.isLost = false,
    required this.rawJson,
  });

  final String id;
  final String patientId;
  final String kind;
  final int? dueAt;
  final int? completedAt;
  final int? attempts;
  final bool isLost;
  final String rawJson;

  Map<String, Object?> toDb() => {
        'id': id,
        'patient_id': patientId,
        'kind': kind,
        'due_at': dueAt,
        'completed_at': completedAt,
        'attempts': attempts,
        'is_lost': isLost ? 1 : 0,
        'raw_json': rawJson,
      };

  static FollowUpRow fromDb(Map<String, Object?> row) => FollowUpRow(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        kind: row['kind'] as String? ?? FollowUpKind.generic,
        dueAt: row['due_at'] as int?,
        completedAt: row['completed_at'] as int?,
        attempts: row['attempts'] as int?,
        isLost: row['is_lost'] == 1,
        rawJson: row['raw_json'] as String? ?? '{}',
      );
}

class FollowUpDao {
  FollowUpDao(this._db);

  final AppDatabase _db;

  Future<void> upsertMany(List<FollowUpRow> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.db.batch();
    for (final r in rows) {
      batch.insert(
        AppDatabase.tableFollowUps,
        r.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<FollowUpRow>> forPatient(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tableFollowUps,
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
    return rows.map(FollowUpRow.fromDb).toList(growable: false);
  }

  /// Bulk read for the worklist: returns a `patientId → rows` map for the
  /// given patient IDs. Single SQL round-trip.
  Future<Map<String, List<FollowUpRow>>> forMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const <String, List<FollowUpRow>>{};
    final placeholders = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableFollowUps,
      where: 'patient_id IN ($placeholders)',
      whereArgs: patientIds,
    );
    final out = <String, List<FollowUpRow>>{};
    for (final r in rows) {
      final pid = r['patient_id'] as String?;
      if (pid == null) continue;
      (out[pid] ??= <FollowUpRow>[]).add(FollowUpRow.fromDb(r));
    }
    return out;
  }
}
