import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Local cache for Rx-Buddy medication adherence check-ins.
///
/// Rows track daily medication intake confirmations; pushed to the server
/// as part of the NCD follow-up sync payload.
class RxBuddyDao {
  RxBuddyDao(this._db);

  final AppDatabase _db;

  static const String _table = 'rx_buddy_checkins';

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        check_date INTEGER NOT NULL,
        medications_taken INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        raw_json TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_rx_buddy_patient ON $_table(patient_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_rx_buddy_date ON $_table(check_date DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_rx_buddy_sync ON $_table(sync_status)');
  }

  Future<void> upsert(RxBuddyCheckinEntity entity) async {
    await _db.db.insert(
      _table,
      entity.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<RxBuddyCheckinEntity>> getByPatientId(String patientId,
      {int? limit}) async {
    final rows = await _db.db.query(
      _table,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'check_date DESC',
      limit: limit,
    );
    return rows.map(RxBuddyCheckinEntity.fromDb).toList();
  }

  Future<List<RxBuddyCheckinEntity>> getPending() async {
    final rows = await _db.db.query(
      _table,
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
    );
    return rows.map(RxBuddyCheckinEntity.fromDb).toList();
  }

  Future<void> markSynced(String id) async {
    await _db.db.update(
      _table,
      {'sync_status': 'success'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class RxBuddyCheckinEntity {
  const RxBuddyCheckinEntity({
    required this.id,
    required this.patientId,
    required this.checkDate,
    required this.medicationsTaken,
    this.notes,
    this.rawJson,
    this.syncStatus = 'pending',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final int checkDate;
  final bool medicationsTaken;
  final String? notes;
  final String? rawJson;
  final String syncStatus;
  final int? createdAt;
  final int? updatedAt;

  Map<String, dynamic> toDb() => {
        'id': id,
        'patient_id': patientId,
        'check_date': checkDate,
        'medications_taken': medicationsTaken ? 1 : 0,
        'notes': notes,
        'raw_json': rawJson,
        'sync_status': syncStatus,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static RxBuddyCheckinEntity fromDb(Map<String, dynamic> row) =>
      RxBuddyCheckinEntity(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        checkDate: row['check_date'] as int,
        medicationsTaken: (row['medications_taken'] as int?) == 1,
        notes: row['notes'] as String?,
        rawJson: row['raw_json'] as String?,
        syncStatus: row['sync_status'] as String? ?? 'pending',
        createdAt: row['created_at'] as int?,
        updatedAt: row['updated_at'] as int?,
      );
}
