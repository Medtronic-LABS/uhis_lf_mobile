import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Local cache for patient diagnosis records (NCD, ANC comorbidities, TB).
class DiagnosisDao {
  DiagnosisDao(this._db);

  final AppDatabase _db;

  static const String _table = 'diagnoses';

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        diagnosis_code TEXT NOT NULL,
        diagnosis_label TEXT,
        programme TEXT,
        confirmed_at INTEGER,
        raw_json TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_diagnosis_patient ON $_table(patient_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_diagnosis_code ON $_table(diagnosis_code)');
  }

  Future<void> upsert(DiagnosisEntity entity) async {
    await _db.db.insert(
      _table,
      entity.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DiagnosisEntity>> getByPatientId(String patientId) async {
    final rows = await _db.db.query(
      _table,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'confirmed_at DESC',
    );
    return rows.map(DiagnosisEntity.fromDb).toList();
  }

  Future<List<DiagnosisEntity>> getPending() async {
    final rows = await _db.db.query(
      _table,
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
    );
    return rows.map(DiagnosisEntity.fromDb).toList();
  }
}

class DiagnosisEntity {
  const DiagnosisEntity({
    required this.id,
    required this.patientId,
    required this.diagnosisCode,
    required this.rawJson,
    this.diagnosisLabel,
    this.programme,
    this.confirmedAt,
    this.syncStatus = 'pending',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final String diagnosisCode;
  final String rawJson;
  final String? diagnosisLabel;
  final String? programme;
  final int? confirmedAt;
  final String syncStatus;
  final int? createdAt;
  final int? updatedAt;

  Map<String, dynamic> toDb() => {
        'id': id,
        'patient_id': patientId,
        'diagnosis_code': diagnosisCode,
        'diagnosis_label': diagnosisLabel,
        'programme': programme,
        'confirmed_at': confirmedAt,
        'raw_json': rawJson,
        'sync_status': syncStatus,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static DiagnosisEntity fromDb(Map<String, dynamic> row) => DiagnosisEntity(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        diagnosisCode: row['diagnosis_code'] as String,
        rawJson: row['raw_json'] as String,
        diagnosisLabel: row['diagnosis_label'] as String?,
        programme: row['programme'] as String?,
        confirmedAt: row['confirmed_at'] as int?,
        syncStatus: row['sync_status'] as String? ?? 'pending',
        createdAt: row['created_at'] as int?,
        updatedAt: row['updated_at'] as int?,
      );
}
