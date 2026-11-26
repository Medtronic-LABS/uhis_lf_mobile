/// Persistence for [NetworkLogEntry] rows (the hidden Network page).
///
/// Every write path purges to the newest [maxRows] inside the same
/// transaction, so the table is bounded without a separate sweeper.
library;

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/sync_meta_dao.dart';
import 'network_log_entry.dart';

class NetworkLogDao {
  NetworkLogDao(this._db) : _syncMeta = SyncMetaDao(_db);

  final AppDatabase _db;
  final SyncMetaDao _syncMeta;

  static const int maxRows = 2000;
  static const int insertChunk = 50;
  static const int mergeCap = 200;
  static const int maxFutureSkewMs = 5 * 60 * 1000;
  static const int maxPageLimit = 1000;
  static const String _table = AppDatabase.tableNetworkLog;

  /// Inserts Dart-side [entries] (source forced to `dart`, text normalised)
  /// in chunks of [insertChunk] and purges to [maxRows]. [isCurrent] is the
  /// first statement of the transaction: when it returns false (a wipe
  /// happened since the batch was snapshotted) nothing is written.
  Future<void> insertBatch(
    List<NetworkLogEntry> entries, {
    bool Function()? isCurrent,
  }) async {
    await _db.db.transaction((tx) async {
      if (isCurrent != null && !isCurrent()) return;
      for (var i = 0; i < entries.length; i += insertChunk) {
        final end = i + insertChunk < entries.length
            ? i + insertChunk
            : entries.length;
        for (final e in entries.sublist(i, end)) {
          await tx.insert(
            _table,
            e.toSanitizedDb(forcedSource: 'dart'),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      await _purge(tx);
    });
  }

  /// Merges native SDK rows and optionally moves the cursor, all in one
  /// transaction so the floor read cannot be stale against a concurrent
  /// [AppDatabase.wipeAllData]. Rows are forced to `native`, capped at
  /// [mergeCap], and skipped if older than the stored floor or more than
  /// [maxFutureSkewMs] in the future. [cursorTo] updates only the cursor
  /// column (it may be 0 or lower than the current value). Returns rows
  /// inserted.
  Future<int> mergeNative(
    List<NetworkLogEntry> entries, {
    int? cursorTo,
  }) async {
    var inserted = 0;
    await _db.db.transaction((tx) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final meta = await tx.query(
        AppDatabase.tableSyncMeta,
        columns: ['last_sync_time'],
        where: 'entity = ?',
        whereArgs: [AppDatabase.networkLogNativeEntity],
        limit: 1,
      );
      final floor =
          meta.isEmpty ? now : (meta.first['last_sync_time'] as int? ?? 0);
      for (final e in entries.take(mergeCap)) {
        if (e.startedAtMs < floor || e.startedAtMs > now + maxFutureSkewMs) {
          continue;
        }
        final id = await tx.insert(
          _table,
          e.toSanitizedDb(forcedSource: 'native'),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id > 0) inserted++;
      }
      await _purge(tx);
      if (cursorTo != null) {
        await tx.update(
          AppDatabase.tableSyncMeta,
          {'cursor': cursorTo},
          where: 'entity = ?',
          whereArgs: [AppDatabase.networkLogNativeEntity],
        );
      }
    });
    return inserted;
  }

  Future<List<NetworkLogEntry>> page({
    required int limit,
    required int offset,
    String? service,
  }) async {
    final rows = await _db.db.query(
      _table,
      where: service == null ? null : 'service = ?',
      whereArgs: service == null ? null : [service],
      orderBy: 'started_at_ms DESC, id DESC',
      limit: limit.clamp(0, maxPageLimit),
      offset: offset < 0 ? 0 : offset,
    );
    return rows.map(NetworkLogEntry.fromDb).toList();
  }

  Future<List<NetworkLogEntry>> newest(int limit, {String? service}) =>
      page(limit: limit, offset: 0, service: service);

  Future<Map<String, int>> countsByService() async {
    final rows = await _db.db.rawQuery(
      'SELECT service, COUNT(*) AS c FROM $_table GROUP BY service',
    );
    return {for (final r in rows) r['service'] as String: r['c'] as int};
  }

  /// Deletes every row and moves the native floor to now, atomically, so the
  /// native SDK's older rows are not re-imported.
  Future<void> clear() async {
    await _db.db.transaction((tx) async {
      await tx.delete(_table);
      await tx.update(
        AppDatabase.tableSyncMeta,
        {'last_sync_time': DateTime.now().millisecondsSinceEpoch},
        where: 'entity = ?',
        whereArgs: [AppDatabase.networkLogNativeEntity],
      );
    });
  }

  /// Native merge cursor and floor (read-only; [mergeNative] owns writes). A missing row means the floor is now.
  Future<({int cursor, int floorMs})> nativeState() async {
    final row = await _syncMeta.read(AppDatabase.networkLogNativeEntity);
    if (row == null) {
      return (cursor: 0, floorMs: DateTime.now().millisecondsSinceEpoch);
    }
    return (cursor: row.cursor ?? 0, floorMs: row.lastSyncTime ?? 0);
  }

  Future<void> _purge(Transaction tx) => tx.rawDelete(
        'DELETE FROM $_table WHERE id <= '
        '(SELECT MAX(id) FROM $_table) - $maxRows',
      );
}
