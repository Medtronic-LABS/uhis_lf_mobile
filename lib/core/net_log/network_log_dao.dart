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
  static const String _table = AppDatabase.tableNetworkLog;

  /// Inserts [entries] and purges to [maxRows]. [isCurrent] is the first
  /// statement of the transaction: when it returns false (a wipe happened
  /// since the batch was snapshotted) nothing is written.
  Future<void> insertBatch(
    List<NetworkLogEntry> entries, {
    bool Function()? isCurrent,
  }) async {
    await _db.db.transaction((tx) async {
      if (isCurrent != null && !isCurrent()) return;
      for (final e in entries) {
        await tx.insert(_table, e.toDb());
      }
      await _purge(tx);
    });
  }

  /// Merges native SDK rows. Duplicates on `(native_id, started_at_ms)` are
  /// ignored; rows older than [floorMs] are skipped. Returns rows inserted.
  Future<int> mergeNative(
    List<NetworkLogEntry> entries, {
    required int floorMs,
  }) async {
    var inserted = 0;
    await _db.db.transaction((tx) async {
      for (final e in entries) {
        if (e.startedAtMs < floorMs) continue;
        final id = await tx.insert(
          _table,
          e.toDb(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id > 0) inserted++;
      }
      await _purge(tx);
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
      limit: limit,
      offset: offset,
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

  /// Native merge cursor and floor. A missing row means the floor is now.
  Future<({int cursor, int floorMs})> nativeState() async {
    final row = await _syncMeta.read(AppDatabase.networkLogNativeEntity);
    if (row == null) {
      return (cursor: 0, floorMs: DateTime.now().millisecondsSinceEpoch);
    }
    return (cursor: row.cursor ?? 0, floorMs: row.lastSyncTime ?? 0);
  }

  Future<void> setNativeCursor(int cursor) async {
    final existing = await _syncMeta.read(AppDatabase.networkLogNativeEntity);
    await _syncMeta.upsert(SyncMetaRow(
      entity: AppDatabase.networkLogNativeEntity,
      lastSyncTime: existing?.lastSyncTime ??
          DateTime.now().millisecondsSinceEpoch,
      cursor: cursor,
    ));
  }

  Future<void> _purge(Transaction tx) => tx.rawDelete(
        'DELETE FROM $_table WHERE id <= '
        '(SELECT MAX(id) FROM $_table) - $maxRows',
      );
}
