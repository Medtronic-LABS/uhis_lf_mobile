import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Upload status constants for [AudioSampleModel].
abstract final class AudioSampleStatus {
  AudioSampleStatus._();

  static const pending = 'pending';
  static const uploaded = 'uploaded';
  static const abandoned = 'abandoned';
}

class AudioSampleModel {
  const AudioSampleModel({
    required this.id,
    required this.encounterId,
    this.fhirEncounterId,
    required this.localFilePath,
    this.scribeMode = 'formPrefill',
    this.language = 'bn',
    this.uploadStatus = AudioSampleStatus.pending,
    this.retryCount = 0,
    this.nextRetryAt,
    required this.createdAt,
  });

  final String id;
  final String encounterId;
  final String? fhirEncounterId;
  final String localFilePath;
  final String scribeMode;
  final String language;
  final String uploadStatus;
  final int retryCount;
  final int? nextRetryAt;
  final int createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'encounter_id': encounterId,
        'fhir_encounter_id': fhirEncounterId,
        'local_file_path': localFilePath,
        'scribe_mode': scribeMode,
        'language': language,
        'upload_status': uploadStatus,
        'retry_count': retryCount,
        'next_retry_at': nextRetryAt,
        'created_at': createdAt,
      };

  factory AudioSampleModel.fromMap(Map<String, dynamic> m) => AudioSampleModel(
        id: m['id'] as String,
        encounterId: m['encounter_id'] as String,
        fhirEncounterId: m['fhir_encounter_id'] as String?,
        localFilePath: m['local_file_path'] as String,
        scribeMode: m['scribe_mode'] as String? ?? 'formPrefill',
        language: m['language'] as String? ?? 'bn',
        uploadStatus:
            m['upload_status'] as String? ?? AudioSampleStatus.pending,
        retryCount: m['retry_count'] as int? ?? 0,
        nextRetryAt: m['next_retry_at'] as int?,
        createdAt: m['created_at'] as int,
      );
}

class AudioSampleDao {
  const AudioSampleDao(this._db);

  final AppDatabase _db;

  Database get _d => _db.db;
  static final _rng = Random();

  Future<void> insertSample(AudioSampleModel sample) async {
    await _d.insert(
      AppDatabase.tableAudioSamples,
      sample.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Returns pending rows whose retry time has arrived (or is null).
  Future<List<AudioSampleModel>> getDueSamples() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _d.query(
      AppDatabase.tableAudioSamples,
      where:
          "upload_status = ? AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [AudioSampleStatus.pending, now],
    );
    return rows.map(AudioSampleModel.fromMap).toList();
  }

  Future<void> markUploaded(String id) async {
    await _d.update(
      AppDatabase.tableAudioSamples,
      {'upload_status': AudioSampleStatus.uploaded},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAbandoned(String id) async {
    await _d.update(
      AppDatabase.tableAudioSamples,
      {'upload_status': AudioSampleStatus.abandoned},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Exponential backoff: min(30 * 2^n, 86400) seconds + jitter (0–30s).
  Future<void> scheduleRetry(String id, int currentRetryCount) async {
    final delaySecs =
        min(30 * pow(2, currentRetryCount), 86400).toInt();
    final jitterSecs = _rng.nextInt(30);
    final nextRetryAt = DateTime.now().millisecondsSinceEpoch +
        (delaySecs + jitterSecs) * 1000;
    await _d.update(
      AppDatabase.tableAudioSamples,
      {
        'retry_count': currentRetryCount + 1,
        'next_retry_at': nextRetryAt,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Updates fhir_encounter_id for all pending rows with matching encounter_id.
  Future<void> updateFhirEncounterId(
      String encounterId, String fhirId) async {
    await _d.update(
      AppDatabase.tableAudioSamples,
      {'fhir_encounter_id': fhirId},
      where: 'encounter_id = ? AND upload_status = ?',
      whereArgs: [encounterId, AudioSampleStatus.pending],
    );
  }

  Future<List<String>> getAbandonedLocalPaths() async {
    final rows = await _d.query(
      AppDatabase.tableAudioSamples,
      columns: ['local_file_path'],
      where: 'upload_status = ?',
      whereArgs: [AudioSampleStatus.abandoned],
    );
    return rows.map((r) => r['local_file_path'] as String).toList();
  }
}
