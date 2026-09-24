import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// A single completed Shukhee teleconsult call, synced in from Frappe's
/// `Call Logs` doctype via `CallLogSyncService` -- distinct from
/// `TeleconsultPrescriptionRow`, which is single-row-per-visit and only ever
/// populated by this device's own live call. [id] is the backend's stable
/// Call Logs docname, not a visit id -- a patient can have many historical
/// calls, including ones made from a different device.
///
/// [clinicalDataJson] is stored as a canonical JSON string (never bytes/a
/// bare map) -- see [normalizeClinicalData]. [prescriptionLink]/
/// [invoiceLink] are presence flags only, never document bytes: documents
/// for a historical call are always fetched live, on demand, when the user
/// taps to view them (see `TeleconsultCallDetailScreen`).
class CallLogHistoryRow {
  const CallLogHistoryRow({
    required this.id,
    required this.syncSeq,
    this.patientId,
    this.encounterId,
    this.status,
    this.appointmentStatus,
    this.doctorName,
    this.doctorSpeciality,
    this.doctorFacility,
    this.reason,
    this.clinicalDataJson,
    this.prescriptionLink,
    this.invoiceLink,
    this.callDate,
    required this.updatedAt,
    required this.rawJson,
  });

  final String id;
  final int syncSeq;
  final String? patientId;
  final String? encounterId;
  final String? status;
  final String? appointmentStatus;
  final String? doctorName;
  final String? doctorSpeciality;
  final String? doctorFacility;
  final String? reason;
  final String? clinicalDataJson;
  final String? prescriptionLink;
  final String? invoiceLink;
  final DateTime? callDate;
  final DateTime updatedAt;
  final String rawJson;

  bool get hasPrescription => prescriptionLink != null && prescriptionLink!.isNotEmpty;
  bool get hasInvoice => invoiceLink != null && invoiceLink!.isNotEmpty;

  static CallLogHistoryRow fromDb(Map<String, Object?> row) {
    final callDateMs = row['call_date'] as int?;
    return CallLogHistoryRow(
      id: row['id'] as String,
      syncSeq: row['sync_seq'] as int,
      patientId: row['patient_id'] as String?,
      encounterId: row['encounter_id'] as String?,
      status: row['status'] as String?,
      appointmentStatus: row['appointment_status'] as String?,
      doctorName: row['doctor_name'] as String?,
      doctorSpeciality: row['doctor_speciality'] as String?,
      doctorFacility: row['doctor_facility'] as String?,
      reason: row['reason'] as String?,
      clinicalDataJson: row['clinical_data'] as String?,
      prescriptionLink: row['prescription_link'] as String?,
      invoiceLink: row['invoice_link'] as String?,
      callDate: callDateMs == null ? null : DateTime.fromMillisecondsSinceEpoch(callDateMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      rawJson: row['raw_json'] as String,
    );
  }

  Map<String, Object?> toDb() => {
        'id': id,
        'sync_seq': syncSeq,
        'patient_id': patientId,
        'encounter_id': encounterId,
        'status': status,
        'appointment_status': appointmentStatus,
        'doctor_name': doctorName,
        'doctor_speciality': doctorSpeciality,
        'doctor_facility': doctorFacility,
        'reason': reason,
        'clinical_data': clinicalDataJson,
        'prescription_link': prescriptionLink,
        'invoice_link': invoiceLink,
        'call_date': callDate?.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'raw_json': rawJson,
      };
}

/// Normalizes whatever shape `clinical_data` arrives in off the wire into a
/// canonical JSON string, written exactly once here so every later read only
/// ever has to `jsonDecode` once. Confirmed server-side (see
/// `shukhee_integration`'s `test_call_logs_sync.py`) that Frappe's own
/// `as_dict()` always re-encodes a JSON-fieldtype value back into a string
/// before it reaches `sync.pull`'s response, regardless of the backend DB's
/// own auto-deserialize behavior -- so in practice this always receives a
/// string. Still tolerates an already-parsed map defensively, as cheap
/// insurance against a future Frappe/backend change, rather than trusting
/// that contract to hold forever.
String? normalizeClinicalData(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) return raw.isEmpty ? null : raw;
  if (raw is Map<String, dynamic>) return raw.isEmpty ? null : jsonEncode(raw);
  return null;
}

class CallLogHistoryDao {
  CallLogHistoryDao(this._db);

  final AppDatabase _db;

  /// Bulk upsert (the sync-pull persist step) -- caller decides transaction
  /// scope, same contract as `PatientDao.upsertMany`.
  Future<void> upsertMany(List<CallLogHistoryRow> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.db.batch();
    for (final row in rows) {
      batch.insert(
        AppDatabase.tableCallLogHistory,
        row.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CallLogHistoryRow>> getForPatient(String patientId, {int limit = 50}) async {
    final rows = await _db.db.query(
      AppDatabase.tableCallLogHistory,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'call_date DESC',
      limit: limit,
    );
    return rows.map(CallLogHistoryRow.fromDb).toList();
  }

  /// Batched lookup for a screen rendering many patients at once -- follows
  /// this codebase's established `...ForMany`/`...ForVisits` convention (see
  /// e.g. `TeleconsultPrescriptionDao.getForVisits`) rather than one query
  /// per patient.
  Future<Map<String, List<CallLogHistoryRow>>> getForPatients(List<String> patientIds) async {
    if (patientIds.isEmpty) return const {};
    final placeholders = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableCallLogHistory,
      where: 'patient_id IN ($placeholders)',
      whereArgs: patientIds,
      orderBy: 'call_date DESC',
    );
    final result = <String, List<CallLogHistoryRow>>{};
    for (final row in rows) {
      final parsed = CallLogHistoryRow.fromDb(row);
      final patientId = parsed.patientId;
      if (patientId == null) continue;
      (result[patientId] ??= []).add(parsed);
    }
    return result;
  }

  Future<CallLogHistoryRow?> getById(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tableCallLogHistory,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CallLogHistoryRow.fromDb(rows.first);
  }
}
