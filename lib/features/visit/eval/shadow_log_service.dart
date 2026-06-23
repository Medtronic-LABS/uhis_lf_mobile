/// Shadow-mode logging service for Phase 6 differential-hint eval dataset.
///
/// Called at assessment completion (after the SK submits). Captures the
/// structured inputs that would feed a differential model — but NEVER
/// surfaces hints to the SK during pilot. The data feeds the retrospective
/// eval dataset reviewed by the clinical board before Phase 6 goes live.
///
/// Lifecycle:
///   1. `ShadowLogService.capture(...)` is called by the submission orchestrator
///      after a successful fan-out submission.
///   2. Entry stored locally in `eval_log` table (sync-safe, additive).
///   3. `ShadowLogService.uploadPending()` is called by the offline sync
///      worker on reconnect — posts each pending entry as a FHIR
///      DocumentReference to the encounter's fhir-server record.
///   4. Clinical board runs FHIR queries monthly to extract the dataset.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import 'eval_log_entry.dart';

/// Payload passed by the submission orchestrator after a visit completes.
class EvalCapturePayload {
  const EvalCapturePayload({
    required this.encounterId,
    required this.patientId,
    required this.memberId,
    required this.activatedProgrammes,
    required this.symptoms,
    required this.fieldValues,
    required this.cdsAlertIds,
    required this.patientContextJson,
  });

  final String encounterId;
  final String patientId;
  final String memberId;
  final List<String> activatedProgrammes;
  final List<String> symptoms;
  final Map<String, dynamic> fieldValues;
  final List<String> cdsAlertIds;
  final Map<String, dynamic> patientContextJson;
}

class ShadowLogService {
  ShadowLogService(this._db);

  final AppDatabase _db;

  static const String _table = 'eval_log';

  /// Capture an assessment for the eval dataset.
  /// Fire-and-forget safe — does not throw; logs errors to diagnostics.
  Future<void> capture(EvalCapturePayload payload) async {
    final entry = EvalLogEntry(
      id: const Uuid().v4(),
      encounterId: payload.encounterId,
      patientId: payload.patientId,
      memberId: payload.memberId,
      capturedAt: DateTime.now(),
      activatedProgrammes: jsonEncode(payload.activatedProgrammes),
      symptoms: jsonEncode(payload.symptoms),
      fieldValues: jsonEncode(payload.fieldValues),
      cdsAlerts: jsonEncode(payload.cdsAlertIds),
      patientContextJson: jsonEncode(payload.patientContextJson),
    );
    try {
      await _db.db.insert(
        _table,
        entry.toDb(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } on DatabaseException catch (e, st) {
      // Non-fatal: eval logging must never break the assessment flow.
      // ignore: avoid_print
      print('[ShadowLog] capture failed — $e\n$st');
    }
  }

  /// Returns all entries pending upload, ordered oldest-first.
  Future<List<EvalLogEntry>> getPending() async {
    final rows = await _db.db.query(
      _table,
      where: 'upload_status = ?',
      whereArgs: [EvalUploadStatus.pending.name],
      orderBy: 'captured_at ASC',
      limit: 50,
    );
    return rows.map(EvalLogEntry.fromDb).toList();
  }

  /// Marks an entry as successfully uploaded with the FHIR DocumentReference id.
  Future<void> markUploaded(String id, String fhirDocRefId) async {
    await _db.db.update(
      _table,
      {
        'upload_status': EvalUploadStatus.uploaded.name,
        'uploaded_at': DateTime.now().millisecondsSinceEpoch,
        'fhir_doc_ref_id': fhirDocRefId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks an entry as failed so it can be retried later.
  Future<void> markFailed(String id) async {
    await _db.db.update(
      _table,
      {'upload_status': EvalUploadStatus.failed.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Re-queues failed entries for retry.
  Future<void> requeueFailed() async {
    await _db.db.update(
      _table,
      {'upload_status': EvalUploadStatus.pending.name},
      where: 'upload_status = ?',
      whereArgs: [EvalUploadStatus.failed.name],
    );
  }

  /// Pending count — used by sync status surface.
  Future<int> pendingCount() async {
    final result = await _db.db.rawQuery(
      "SELECT COUNT(*) as c FROM $_table WHERE upload_status = ?",
      [EvalUploadStatus.pending.name],
    );
    return result.first['c'] as int? ?? 0;
  }
}
