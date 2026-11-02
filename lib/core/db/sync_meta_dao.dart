import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class SyncMetaRow {
  const SyncMetaRow({
    required this.entity,
    this.lastSyncTime,
    this.lastFullSyncAt,
    this.cursor,
  });

  final String entity;
  final int? lastSyncTime;
  final int? lastFullSyncAt;

  /// Global `sync_seq` cursor from `spice_next_core.api.sync.pull` -- an
  /// opaque sequence integer, semantically distinct from [lastSyncTime]/
  /// [lastFullSyncAt] (epoch-ms timestamps), which is why it's its own
  /// column rather than overloading one of those. See `CallLogSyncService`.
  final int? cursor;
}

/// Data-access for the `sync_meta` table. First real consumer is the worklist
/// (`entity = 'worklist'`); other entities can adopt it as they migrate.
class SyncMetaDao {
  SyncMetaDao(this._db);

  final AppDatabase _db;

  Future<SyncMetaRow?> read(String entity) async {
    final rows = await _db.db.query(
      AppDatabase.tableSyncMeta,
      where: 'entity = ?',
      whereArgs: [entity],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SyncMetaRow(
      entity: r['entity'] as String,
      lastSyncTime: r['last_sync_time'] as int?,
      lastFullSyncAt: r['last_full_sync_at'] as int?,
      cursor: r['cursor'] as int?,
    );
  }

  Future<void> upsert(SyncMetaRow row) async {
    await _db.db.insert(
      AppDatabase.tableSyncMeta,
      {
        'entity': row.entity,
        'last_sync_time': row.lastSyncTime,
        'last_full_sync_at': row.lastFullSyncAt,
        'cursor': row.cursor,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> stampWarm(String entity, DateTime when) async {
    final existing = await read(entity);
    await upsert(SyncMetaRow(
      entity: entity,
      lastSyncTime: when.millisecondsSinceEpoch,
      lastFullSyncAt: existing?.lastFullSyncAt,
      cursor: existing?.cursor,
    ));
  }

  Future<void> stampFull(String entity, DateTime when) async {
    final ts = when.millisecondsSinceEpoch;
    final existing = await read(entity);
    await upsert(SyncMetaRow(
      entity: entity,
      lastSyncTime: ts,
      lastFullSyncAt: ts,
      cursor: existing?.cursor,
    ));
  }

  /// Advances [entity]'s `sync_seq` cursor -- see `CallLogSyncService`.
  /// Preserves [SyncMetaRow.lastSyncTime]/[SyncMetaRow.lastFullSyncAt] the
  /// same read-modify-write way [stampWarm]/[stampFull] preserve [cursor].
  Future<void> stampCursor(String entity, int cursor) async {
    final existing = await read(entity);
    await upsert(SyncMetaRow(
      entity: entity,
      lastSyncTime: existing?.lastSyncTime,
      lastFullSyncAt: existing?.lastFullSyncAt,
      cursor: cursor,
    ));
  }
}
