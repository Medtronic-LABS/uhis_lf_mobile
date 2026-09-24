import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../db/app_database.dart';
import 'value_audit_entry.dart';

/// Queue for the PHI value-audit stream.
///
/// Mirrors [TelemetryDao] deliberately — same insert/pending/markUploaded
/// shape — but over a table that IS wiped when a different SK signs in. There
/// is therefore no purge method: the wipe is the retention policy on device,
/// and anything not yet uploaded at handover is meant to be lost rather than
/// carried into another SK's session.
class ValueAuditDao {
  ValueAuditDao(this._db);

  final AppDatabase _db;

  String get _table => AppDatabase.tableAiValueAudit;

  /// Inserts [entries], ignoring any id already stored.
  ///
  /// Batched in one transaction: a visit writes every pair at submit, and a
  /// partial write would leave a visit's audit trail half-recorded.
  Future<int> insertAll(List<ValueAuditEntry> entries) async {
    if (entries.isEmpty) return 0;
    var written = 0;
    await _db.db.transaction((tx) async {
      for (final entry in entries) {
        final rows = await tx.insert(
          _table,
          entry.toDb(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (rows > 0) written++;
      }
    });
    return written;
  }

  Future<List<ValueAuditEntry>> pending({int limit = 500}) async {
    final rows = await _db.db.query(
      _table,
      where: 'upload_status = ?',
      whereArgs: [ValueAuditUploadStatus.pending],
      orderBy: 'occurred_at ASC',
      limit: limit,
    );
    return rows.map(ValueAuditEntry.fromDb).toList();
  }

  Future<int> markUploaded(List<String> ids, {DateTime? at}) async {
    if (ids.isEmpty) return 0;
    final placeholders = List.filled(ids.length, '?').join(',');
    return _db.db.update(
      _table,
      {
        'upload_status': ValueAuditUploadStatus.uploaded,
        'uploaded_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      },
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<({int total, int pending})> counts() async {
    final total = await _db.db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    final pend = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE upload_status = ?',
      [ValueAuditUploadStatus.pending],
    );
    return (
      total: (total.first['c'] as int?) ?? 0,
      pending: (pend.first['c'] as int?) ?? 0,
    );
  }
}
