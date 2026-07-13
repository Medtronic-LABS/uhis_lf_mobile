import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Local cache for NCD medical review records.
///
/// Review rows are pushed to `spice-service/assessment/create` on next sync.
class NcdMedicalReviewDao {
  NcdMedicalReviewDao(this._db);

  final AppDatabase _db;

  static const String _table = 'ncd_medical_reviews';

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        visit_date INTEGER NOT NULL,
        bp_systolic INTEGER,
        bp_diastolic INTEGER,
        glucose_value REAL,
        glucose_type TEXT,
        on_medication INTEGER DEFAULT 0,
        raw_json TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ncd_review_patient ON $_table(patient_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ncd_review_sync ON $_table(sync_status)');
  }

  Future<void> upsert(NcdMedicalReviewEntity entity) async {
    await _db.db.insert(
      _table,
      entity.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<NcdMedicalReviewEntity>> getByPatientId(String patientId) async {
    final rows = await _db.db.query(
      _table,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'visit_date DESC',
    );
    return rows.map(NcdMedicalReviewEntity.fromDb).toList();
  }

  Future<List<NcdMedicalReviewEntity>> getPending() async {
    final rows = await _db.db.query(
      _table,
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
    );
    return rows.map(NcdMedicalReviewEntity.fromDb).toList();
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

class NcdMedicalReviewEntity {
  const NcdMedicalReviewEntity({
    required this.id,
    required this.patientId,
    required this.visitDate,
    required this.rawJson,
    this.bpSystolic,
    this.bpDiastolic,
    this.glucoseValue,
    this.glucoseType,
    this.onMedication = false,
    this.syncStatus = 'pending',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final int visitDate;
  final String rawJson;
  final int? bpSystolic;
  final int? bpDiastolic;
  final double? glucoseValue;
  final String? glucoseType;
  final bool onMedication;
  final String syncStatus;
  final int? createdAt;
  final int? updatedAt;

  Map<String, dynamic> toDb() => {
        'id': id,
        'patient_id': patientId,
        'visit_date': visitDate,
        'bp_systolic': bpSystolic,
        'bp_diastolic': bpDiastolic,
        'glucose_value': glucoseValue,
        'glucose_type': glucoseType,
        'on_medication': onMedication ? 1 : 0,
        'raw_json': rawJson,
        'sync_status': syncStatus,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static NcdMedicalReviewEntity fromDb(Map<String, dynamic> row) =>
      NcdMedicalReviewEntity(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        visitDate: row['visit_date'] as int,
        rawJson: row['raw_json'] as String,
        bpSystolic: row['bp_systolic'] as int?,
        bpDiastolic: row['bp_diastolic'] as int?,
        glucoseValue: (row['glucose_value'] as num?)?.toDouble(),
        glucoseType: row['glucose_type'] as String?,
        onMedication: (row['on_medication'] as int?) == 1,
        syncStatus: row['sync_status'] as String? ?? 'pending',
        createdAt: row['created_at'] as int?,
        updatedAt: row['updated_at'] as int?,
      );
}
