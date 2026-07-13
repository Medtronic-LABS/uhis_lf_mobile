import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Local cache for patient treatment detail records (prescriptions, regimens).
class TreatmentDetailsDao {
  TreatmentDetailsDao(this._db);

  final AppDatabase _db;

  static const String _table = 'treatment_details';

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        programme TEXT,
        medication_name TEXT,
        dosage TEXT,
        frequency TEXT,
        start_date INTEGER,
        end_date INTEGER,
        raw_json TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_treatment_patient ON $_table(patient_id)');
  }

  Future<void> upsert(TreatmentDetailsEntity entity) async {
    await _db.db.insert(
      _table,
      entity.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TreatmentDetailsEntity>> getByPatientId(String patientId) async {
    final rows = await _db.db.query(
      _table,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'start_date DESC',
    );
    return rows.map(TreatmentDetailsEntity.fromDb).toList();
  }

  Future<List<TreatmentDetailsEntity>> getPending() async {
    final rows = await _db.db.query(
      _table,
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
    );
    return rows.map(TreatmentDetailsEntity.fromDb).toList();
  }
}

class TreatmentDetailsEntity {
  const TreatmentDetailsEntity({
    required this.id,
    required this.patientId,
    required this.rawJson,
    this.programme,
    this.medicationName,
    this.dosage,
    this.frequency,
    this.startDate,
    this.endDate,
    this.syncStatus = 'pending',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final String rawJson;
  final String? programme;
  final String? medicationName;
  final String? dosage;
  final String? frequency;
  final int? startDate;
  final int? endDate;
  final String syncStatus;
  final int? createdAt;
  final int? updatedAt;

  Map<String, dynamic> toDb() => {
        'id': id,
        'patient_id': patientId,
        'programme': programme,
        'medication_name': medicationName,
        'dosage': dosage,
        'frequency': frequency,
        'start_date': startDate,
        'end_date': endDate,
        'raw_json': rawJson,
        'sync_status': syncStatus,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static TreatmentDetailsEntity fromDb(Map<String, dynamic> row) =>
      TreatmentDetailsEntity(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        rawJson: row['raw_json'] as String,
        programme: row['programme'] as String?,
        medicationName: row['medication_name'] as String?,
        dosage: row['dosage'] as String?,
        frequency: row['frequency'] as String?,
        startDate: row['start_date'] as int?,
        endDate: row['end_date'] as int?,
        syncStatus: row['sync_status'] as String? ?? 'pending',
        createdAt: row['created_at'] as int?,
        updatedAt: row['updated_at'] as int?,
      );
}
