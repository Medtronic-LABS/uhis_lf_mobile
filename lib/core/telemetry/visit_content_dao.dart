import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../db/app_database.dart';
import 'visit_content_entry.dart';

/// Queue for visit-scoped AI content (transcript + Step 3 summary text).
///
/// One row per [visit_uuid], merged across capture points. Wiped on SK handover
/// like [ValueAuditDao].
class VisitContentDao {
  VisitContentDao(this._db);

  final AppDatabase _db;

  String get _table => AppDatabase.tableVisitContentTelemetry;

  Future<VisitContentEntry?> byVisitUuid(String visitUuid) async {
    final rows = await _db.db.query(
      _table,
      where: 'visit_uuid = ?',
      whereArgs: [visitUuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VisitContentEntry.fromDb(rows.first);
  }

  Future<void> upsert(VisitContentEntry entry) async {
    await _db.db.insert(
      _table,
      entry.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<VisitContentEntry>> pending({int limit = 100}) async {
    final rows = await _db.db.query(
      _table,
      where: 'upload_status = ?',
      whereArgs: [VisitContentUploadStatus.pending],
      orderBy: 'occurred_at ASC',
      limit: limit,
    );
    return rows.map(VisitContentEntry.fromDb).toList();
  }

  Future<int> markUploaded(List<String> ids, {DateTime? at}) async {
    if (ids.isEmpty) return 0;
    final placeholders = List.filled(ids.length, '?').join(',');
    return _db.db.update(
      _table,
      {
        'upload_status': VisitContentUploadStatus.uploaded,
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
      [VisitContentUploadStatus.pending],
    );
    return (
      total: (total.first['c'] as int?) ?? 0,
      pending: (pend.first['c'] as int?) ?? 0,
    );
  }
}
