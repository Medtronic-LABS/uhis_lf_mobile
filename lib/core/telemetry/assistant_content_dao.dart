import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../db/app_database.dart';
import 'assistant_content_entry.dart';

/// Queue for AI assistant ("Ask") PHI content — one row per chatbot turn.
///
/// Keyed by [correlator] (UNIQUE), which also ties the row to its telemetry
/// event. Wiped on SK handover like [ValueAuditDao], since it holds free text.
class AssistantContentDao {
  AssistantContentDao(this._db);

  final AppDatabase _db;

  String get _table => AppDatabase.tableAssistantContentTelemetry;

  Future<void> upsert(AssistantContentEntry entry) async {
    await _db.db.insert(
      _table,
      entry.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AssistantContentEntry>> pending({int limit = 100}) async {
    final rows = await _db.db.query(
      _table,
      where: 'upload_status = ?',
      whereArgs: [AssistantContentUploadStatus.pending],
      orderBy: 'occurred_at ASC',
      limit: limit,
    );
    return rows.map(AssistantContentEntry.fromDb).toList();
  }

  Future<int> markUploaded(List<String> ids, {DateTime? at}) async {
    if (ids.isEmpty) return 0;
    final placeholders = List.filled(ids.length, '?').join(',');
    return _db.db.update(
      _table,
      {
        'upload_status': AssistantContentUploadStatus.uploaded,
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
      [AssistantContentUploadStatus.pending],
    );
    return (
      total: (total.first['c'] as int?) ?? 0,
      pending: (pend.first['c'] as int?) ?? 0,
    );
  }
}
