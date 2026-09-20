/// Persistence for [TelemetryEvent] rows.
///
/// Deliberately dumb: insert, read a date range, hand pending rows to the
/// uploader, mark them uploaded, purge old uploaded ones. All aggregation
/// lives in `telemetry_report.dart` so it stays pure and testable without a
/// database.
library;

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../db/app_database.dart';
import 'telemetry_event.dart';

class TelemetryDao {
  const TelemetryDao(this._db);

  final AppDatabase _db;

  static const String _table = AppDatabase.tableTelemetryEvents;

  /// Inserts one event. `ignore` on conflict because [TelemetryEvent.id] is a
  /// client-generated UUID that also serves as the server's dedup key — a
  /// re-emit of the same id is a no-op rather than a crash.
  Future<void> insert(TelemetryEvent event) async {
    await _db.db.insert(
      _table,
      event.toDb(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Events whose [TelemetryEvent.occurredAt] falls within [from]..[to].
  ///
  /// **Inclusive of both endpoints, to whole-day resolution**: [from] is
  /// floored to 00:00:00.000 and [to] is raised to 23:59:59.999 in the local
  /// timezone. The report screen hands over two dates the SK picked, and
  /// "1 Sep to 7 Sep" has to include everything that happened on the 7th —
  /// a naive `<= to` would cut the last day off at midnight and silently
  /// under-report it.
  Future<List<TelemetryEvent>> inRange(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
    final rows = await _db.db.query(
      _table,
      where: 'occurred_at >= ? AND occurred_at <= ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'occurred_at DESC',
    );
    return rows.map(TelemetryEvent.fromDb).toList();
  }

  /// Rows not yet accepted by the server, oldest first so the backlog drains
  /// in the order it happened.
  Future<List<TelemetryEvent>> pending({int limit = 500}) async {
    final rows = await _db.db.query(
      _table,
      where: 'upload_status = ?',
      whereArgs: [TelemetryUploadStatus.pending],
      orderBy: 'occurred_at ASC',
      limit: limit,
    );
    return rows.map(TelemetryEvent.fromDb).toList();
  }

  /// Flags [ids] as accepted by the server, stamping the time so
  /// [purgeUploadedOlderThan] has a retention clock to measure from.
  Future<int> markUploaded(List<String> ids, {DateTime? at}) async {
    if (ids.isEmpty) return 0;
    final placeholders = List.filled(ids.length, '?').join(',');
    return _db.db.update(
      _table,
      {
        'upload_status': TelemetryUploadStatus.uploaded,
        'uploaded_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      },
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Deletes rows uploaded longer ago than [retain] (default 30 days).
  ///
  /// Only ever touches rows already accepted by the server — a `pending` row
  /// is never deleted no matter how old, because until the upload path exists
  /// this table is the only copy of the data. Returns the number removed.
  Future<int> purgeUploadedOlderThan(
    Duration retain, {
    DateTime? now,
  }) async {
    final cutoff = (now ?? DateTime.now()).subtract(retain);
    return _db.db.delete(
      _table,
      where: 'upload_status = ? AND uploaded_at IS NOT NULL AND uploaded_at < ?',
      whereArgs: [
        TelemetryUploadStatus.uploaded,
        cutoff.millisecondsSinceEpoch,
      ],
    );
  }

  /// Diagnostics for the debug screen — total rows and how many still pending.
  Future<({int total, int pending})> counts() async {
    final total = await _db.db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    final pend = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE upload_status = ?',
      [TelemetryUploadStatus.pending],
    );
    return (
      total: (total.first['c'] as int?) ?? 0,
      pending: (pend.first['c'] as int?) ?? 0,
    );
  }
}
