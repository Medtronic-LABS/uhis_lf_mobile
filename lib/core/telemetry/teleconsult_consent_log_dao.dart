import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../db/app_database.dart';
import 'teleconsult_consent_log_entry.dart';

/// Queue for teleconsult patient-consent decisions -- one row per Agree/
/// Decline tap on `TeleconsultConsentScreen`.
///
/// Wiped on SK handover like [AssistantContentDao], since it holds a patient
/// id and date of birth.
class TeleconsultConsentLogDao {
  TeleconsultConsentLogDao(this._db);

  final AppDatabase _db;

  String get _table => AppDatabase.tableTeleconsultConsentLog;

  Future<void> upsert(TeleconsultConsentLogEntry entry) async {
    await _db.db.insert(
      _table,
      entry.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TeleconsultConsentLogEntry>> pending({int limit = 100}) async {
    final rows = await _db.db.query(
      _table,
      where: 'upload_status = ?',
      whereArgs: [TeleconsultConsentLogUploadStatus.pending],
      orderBy: 'occurred_at ASC',
      limit: limit,
    );
    return rows.map(TeleconsultConsentLogEntry.fromDb).toList();
  }

  Future<int> markUploaded(List<String> ids, {DateTime? at}) async {
    if (ids.isEmpty) return 0;
    final placeholders = List.filled(ids.length, '?').join(',');
    return _db.db.update(
      _table,
      {
        'upload_status': TeleconsultConsentLogUploadStatus.uploaded,
        'uploaded_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      },
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<({int total, int pending})> counts() async {
    final total = await _db.db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    final pend = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE upload_status = ?',
      [TeleconsultConsentLogUploadStatus.pending],
    );
    return (
      total: (total.first['c'] as int?) ?? 0,
      pending: (pend.first['c'] as int?) ?? 0,
    );
  }
}
