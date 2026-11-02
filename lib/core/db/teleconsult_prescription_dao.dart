import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// A completed teleconsult's prescription/invoice, persisted against the
/// visit ([visitId] = `encounters.id`, the same UUID threaded through
/// `TeleconsultScreen.visitId` as Shukhee's `encounter_id`) that requested
/// the call. Lets the patient timeline show a "view prescription" icon and
/// reopen the PDF without a network re-fetch.
class TeleconsultPrescriptionRow {
  const TeleconsultPrescriptionRow({
    required this.visitId,
    required this.callLog,
    this.doctorName,
    this.prescriptionBytes,
    this.invoiceBytes,
    required this.createdAt,
  });

  final String visitId;
  final String callLog;
  final String? doctorName;
  final Uint8List? prescriptionBytes;
  final Uint8List? invoiceBytes;
  final DateTime createdAt;

  bool get hasAnyDocument => prescriptionBytes != null || invoiceBytes != null;

  static TeleconsultPrescriptionRow fromDb(Map<String, Object?> row) {
    return TeleconsultPrescriptionRow(
      visitId: row['visit_id'] as String,
      callLog: row['call_log'] as String,
      doctorName: row['doctor_name'] as String?,
      prescriptionBytes: row['prescription_bytes'] as Uint8List?,
      invoiceBytes: row['invoice_bytes'] as Uint8List?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  Map<String, Object?> toDb() => {
        'visit_id': visitId,
        'call_log': callLog,
        'doctor_name': doctorName,
        'prescription_bytes': prescriptionBytes,
        'invoice_bytes': invoiceBytes,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

class TeleconsultPrescriptionDao {
  TeleconsultPrescriptionDao(this._db);

  final AppDatabase _db;

  Future<void> upsert(TeleconsultPrescriptionRow row) async {
    await _db.db.insert(
      AppDatabase.tableTeleconsultPrescriptions,
      row.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TeleconsultPrescriptionRow?> getForVisit(String visitId) async {
    final rows = await _db.db.query(
      AppDatabase.tableTeleconsultPrescriptions,
      where: 'visit_id = ?',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TeleconsultPrescriptionRow.fromDb(rows.first);
  }

  /// Batched lookup for a screen rendering many timeline rows at once —
  /// follows this codebase's established `...ForMany` convention (see e.g.
  /// `LocalAssessmentDao.latestDraftCreatedAtForMany`) rather than one query
  /// per row.
  Future<Map<String, TeleconsultPrescriptionRow>> getForVisits(List<String> visitIds) async {
    if (visitIds.isEmpty) return const {};
    final placeholders = List.filled(visitIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableTeleconsultPrescriptions,
      where: 'visit_id IN ($placeholders)',
      whereArgs: visitIds,
    );
    return {
      for (final row in rows) row['visit_id'] as String: TeleconsultPrescriptionRow.fromDb(row),
    };
  }
}
