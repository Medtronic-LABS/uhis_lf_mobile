import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Local cache for NCD/ANC initial screening records.
///
/// Screening rows are created at the first visit, then pushed to
/// `spice-service/screening/create` on next sync.
class ScreeningDao {
  ScreeningDao(this._db);

  final AppDatabase _db;

  static const String _table = 'screenings';

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        programme TEXT NOT NULL,
        screening_date INTEGER NOT NULL,
        raw_json TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_screening_patient ON $_table(patient_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_screening_sync ON $_table(sync_status)');
  }

  Future<void> upsert(ScreeningEntity entity) async {
    await _db.db.insert(
      _table,
      entity.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ScreeningEntity>> getByPatientId(String patientId) async {
    final rows = await _db.db.query(
      _table,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'screening_date DESC',
    );
    return rows.map(ScreeningEntity.fromDb).toList();
  }

  Future<List<ScreeningEntity>> getPending() async {
    final rows = await _db.db.query(
      _table,
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
    );
    return rows.map(ScreeningEntity.fromDb).toList();
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

class ScreeningEntity {
  const ScreeningEntity({
    required this.id,
    required this.patientId,
    required this.programme,
    required this.screeningDate,
    required this.rawJson,
    this.syncStatus = 'pending',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final String programme;
  final int screeningDate;
  final String rawJson;
  final String syncStatus;
  final int? createdAt;
  final int? updatedAt;

  Map<String, dynamic> toDb() => {
        'id': id,
        'patient_id': patientId,
        'programme': programme,
        'screening_date': screeningDate,
        'raw_json': rawJson,
        'sync_status': syncStatus,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static ScreeningEntity fromDb(Map<String, dynamic> row) => ScreeningEntity(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        programme: row['programme'] as String,
        screeningDate: row['screening_date'] as int,
        rawJson: row['raw_json'] as String,
        syncStatus: row['sync_status'] as String? ?? 'pending',
        createdAt: row['created_at'] as int?,
        updatedAt: row['updated_at'] as int?,
      );
}
