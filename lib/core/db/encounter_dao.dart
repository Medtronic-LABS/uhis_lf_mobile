import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import '../time/calendar_day.dart';
import 'app_database.dart';

/// Visit/encounter status lifecycle.
enum EncounterStatus {
  /// Initial draft, created when user taps "Start Visit".
  draft,
  /// Triage completed, vitals in progress.
  triageComplete,
  /// Vitals completed, assessment in progress.
  vitalsComplete,
  /// Full visit completed locally.
  completed,
  /// Synced to server successfully.
  synced,
}

/// Sync status for offline-first operations.
enum SyncStatus {
  /// Not yet attempted to sync.
  pending,
  /// Currently syncing.
  syncing,
  /// Successfully synced to server.
  synced,
  /// Sync failed, will retry.
  failed,
}

/// Represents a local visit/encounter record.
class EncounterRow {
  const EncounterRow({
    required this.id,
    required this.patientId,
    required this.programme,
    required this.startedAt,
    this.completedAt,
    required this.status,
    required this.syncStatus,
    this.serverVisitId,
    this.triageJson,
    this.vitalsJson,
    this.assessmentJson,
  });

  final String id;
  final String patientId;
  final String programme;
  final int startedAt;
  final int? completedAt;
  final EncounterStatus status;
  final SyncStatus syncStatus;
  final String? serverVisitId;
  final String? triageJson;
  final String? vitalsJson;
  final String? assessmentJson;

  Map<String, Object?> toDb() => {
        'id': id,
        'patient_id': patientId,
        'programme': programme,
        'started_at': startedAt,
        'completed_at': completedAt,
        'status': status.name,
        'sync_status': syncStatus.name,
        'server_visit_id': serverVisitId,
        'triage_json': triageJson,
        'vitals_json': vitalsJson,
        'assessment_json': assessmentJson,
      };

  static EncounterRow fromDb(Map<String, Object?> row) => EncounterRow(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        programme: row['programme'] as String,
        startedAt: row['started_at'] as int,
        completedAt: row['completed_at'] as int?,
        status: EncounterStatus.values.firstWhere(
          (e) => e.name == row['status'],
          orElse: () => EncounterStatus.draft,
        ),
        syncStatus: SyncStatus.values.firstWhere(
          (e) => e.name == row['sync_status'],
          orElse: () => SyncStatus.pending,
        ),
        serverVisitId: row['server_visit_id'] as String?,
        triageJson: row['triage_json'] as String?,
        vitalsJson: row['vitals_json'] as String?,
        assessmentJson: row['assessment_json'] as String?,
      );

  /// Parse triage data from JSON.
  Map<String, dynamic>? get triageData {
    if (triageJson == null || triageJson!.isEmpty) return null;
    try {
      return jsonDecode(triageJson!) as Map<String, dynamic>;
    } on FormatException catch (e) {
      debugPrint('[encounter_dao] corrupt triageJson for $id: $e');
      return null;
    }
  }

  /// Parse vitals data from JSON.
  Map<String, dynamic>? get vitalsData {
    if (vitalsJson == null || vitalsJson!.isEmpty) return null;
    try {
      return jsonDecode(vitalsJson!) as Map<String, dynamic>;
    } on FormatException catch (e) {
      debugPrint('[encounter_dao] corrupt vitalsJson for $id: $e');
      return null;
    }
  }

  /// Parse assessment data from JSON.
  Map<String, dynamic>? get assessmentData {
    if (assessmentJson == null || assessmentJson!.isEmpty) return null;
    try {
      return jsonDecode(assessmentJson!) as Map<String, dynamic>;
    } on FormatException catch (e) {
      debugPrint('[encounter_dao] corrupt assessmentJson for $id: $e');
      return null;
    }
  }

  /// Create a copy with updated fields.
  EncounterRow copyWith({
    String? id,
    String? patientId,
    String? programme,
    int? startedAt,
    int? completedAt,
    EncounterStatus? status,
    SyncStatus? syncStatus,
    String? serverVisitId,
    String? triageJson,
    String? vitalsJson,
    String? assessmentJson,
  }) =>
      EncounterRow(
        id: id ?? this.id,
        patientId: patientId ?? this.patientId,
        programme: programme ?? this.programme,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        status: status ?? this.status,
        syncStatus: syncStatus ?? this.syncStatus,
        serverVisitId: serverVisitId ?? this.serverVisitId,
        triageJson: triageJson ?? this.triageJson,
        vitalsJson: vitalsJson ?? this.vitalsJson,
        assessmentJson: assessmentJson ?? this.assessmentJson,
      );
}

/// DAO for local encounter/visit storage.
///
/// Supports offline-first visit capture with sync queue.
class EncounterDao {
  EncounterDao(this._db);

  final AppDatabase _db;

  /// Insert or update an encounter.
  Future<void> upsert(EncounterRow row) async {
    await _db.db.insert(
      AppDatabase.tableEncounters,
      row.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get an encounter by ID.
  Future<EncounterRow?> byId(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tableEncounters,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EncounterRow.fromDb(rows.first);
  }

  /// Get recent encounters for a patient, ordered by most recent first.
  Future<List<EncounterRow>> recentForPatient(
    String patientId, {
    int limit = 10,
  }) async {
    final rows = await _db.db.query(
      AppDatabase.tableEncounters,
      where: 'patient_id = ? AND status = ?',
      whereArgs: [patientId, EncounterStatus.completed.name],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(EncounterRow.fromDb).toList();
  }

  /// Get the most recent encounter for a patient.
  Future<EncounterRow?> lastForPatient(String patientId) async {
    final rows = await recentForPatient(patientId, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Get all pending encounters that need syncing.
  Future<List<EncounterRow>> pendingSync() async {
    final rows = await _db.db.query(
      AppDatabase.tableEncounters,
      where: 'sync_status IN (?, ?)',
      whereArgs: [SyncStatus.pending.name, SyncStatus.failed.name],
      orderBy: 'started_at ASC',
    );
    return rows.map(EncounterRow.fromDb).toList();
  }

  /// Get all in-progress encounters (draft or incomplete).
  Future<List<EncounterRow>> inProgress() async {
    final rows = await _db.db.query(
      AppDatabase.tableEncounters,
      where: 'status NOT IN (?, ?)',
      whereArgs: [EncounterStatus.completed.name, EncounterStatus.synced.name],
      orderBy: 'started_at DESC',
    );
    return rows.map(EncounterRow.fromDb).toList();
  }

  /// Update sync status for an encounter.
  Future<void> updateSyncStatus(String id, SyncStatus status,
      {String? serverVisitId}) async {
    final values = <String, Object?>{
      'sync_status': status.name,
    };
    if (serverVisitId != null) {
      values['server_visit_id'] = serverVisitId;
    }
    if (status == SyncStatus.synced) {
      values['status'] = EncounterStatus.synced.name;
    }
    await _db.db.update(
      AppDatabase.tableEncounters,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update triage data for an encounter.
  Future<void> updateTriage(
    String id,
    Map<String, dynamic> triageData,
  ) async {
    await _db.db.update(
      AppDatabase.tableEncounters,
      {
        'triage_json': jsonEncode(triageData),
        'status': EncounterStatus.triageComplete.name,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update vitals data for an encounter.
  Future<void> updateVitals(
    String id,
    Map<String, dynamic> vitalsData,
  ) async {
    await _db.db.update(
      AppDatabase.tableEncounters,
      {
        'vitals_json': jsonEncode(vitalsData),
        'status': EncounterStatus.vitalsComplete.name,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update assessment data and mark encounter as completed.
  Future<void> updateAssessment(
    String id,
    Map<String, dynamic> assessmentData,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      AppDatabase.tableEncounters,
      {
        'assessment_json': jsonEncode(assessmentData),
        'status': EncounterStatus.completed.name,
        'completed_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete an encounter by ID.
  Future<void> delete(String id) async {
    await _db.db.delete(
      AppDatabase.tableEncounters,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all synced encounters older than the given timestamp.
  Future<int> pruneSynced(int olderThan) async {
    return _db.db.delete(
      AppDatabase.tableEncounters,
      where: 'sync_status = ? AND completed_at < ?',
      whereArgs: [SyncStatus.synced.name, olderThan],
    );
  }

  /// Get patient IDs with completed visits on the current **calendar** day.
  ///
  /// Uses a half-open local-midnight window `[today, tomorrow)` so comparison
  /// is by date, not wall-clock time (and does not include future days).
  Future<Set<String>> completedTodayPatientIds() async {
    final todayStart = CalendarDay.todayStart();
    final tomorrowStart = CalendarDay.tomorrowStart(todayStart);
    final startMs = todayStart.millisecondsSinceEpoch;
    final endMs = tomorrowStart.millisecondsSinceEpoch;

    final rows = await _db.db.query(
      AppDatabase.tableEncounters,
      columns: ['patient_id'],
      where: 'status IN (?, ?) AND completed_at >= ? AND completed_at < ?',
      whereArgs: [
        EncounterStatus.completed.name,
        EncounterStatus.synced.name,
        startMs,
        endMs,
      ],
      distinct: true,
    );
    return rows.map((r) => r['patient_id'] as String).toSet();
  }
}
