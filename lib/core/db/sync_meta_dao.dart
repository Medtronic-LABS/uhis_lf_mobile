import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class SyncMetaRow {
  const SyncMetaRow({
    required this.entity,
    this.lastSyncTime,
    this.lastFullSyncAt,
  });

  final String entity;
  final int? lastSyncTime;
  final int? lastFullSyncAt;
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
    );
  }

  Future<void> upsert(SyncMetaRow row) async {
    await _db.db.insert(
      AppDatabase.tableSyncMeta,
      {
        'entity': row.entity,
        'last_sync_time': row.lastSyncTime,
        'last_full_sync_at': row.lastFullSyncAt,
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
    ));
  }

  Future<void> stampFull(String entity, DateTime when) async {
    final ts = when.millisecondsSinceEpoch;
    await upsert(SyncMetaRow(
      entity: entity,
      lastSyncTime: ts,
      lastFullSyncAt: ts,
    ));
  }
}
