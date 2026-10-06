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
    this.fhirEncounterId,
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

  /// Server-assigned FHIR Encounter id for the visit this call was booked
  /// from -- attached after the fact server-side (see
  /// shukhee_integration.api.consultation.attach_fhir_encounter_id), unlike
  /// [encounterId] which is the app's own client-minted visit id sent at
  /// booking time. Survives a full local data wipe or a new device, since
  /// it rides along in the ordinary Call Logs pull once the backend has it.
  final String? fhirEncounterId;

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
      fhirEncounterId: row['fhir_encounter_id'] as String?,
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
        'fhir_encounter_id': fhirEncounterId,
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

  /// Looks up by [encounterId] OR [CallLogHistoryRow.fhirEncounterId] --
  /// matched against local `encounters.id` via `EncounterDao.idsForPatient`
  /// -- rather than [CallLogHistoryRow.patientId], which mirrors Call Logs'
  /// `patient` Link, still unpopulated at booking time today (no bridge
  /// exists yet between this app's own patient identity and the Frappe
  /// backend's cross-system `Patient` doctype), so it is null on every
  /// synced-in row.
  ///
  /// `encounter_id` (the app's own client-minted visit id, sent at booking
  /// time) is the only join key for a call made before
  /// `attach_fhir_encounter_id` shipped, or one this device never learned
  /// the FHIR id for. `fhir_encounter_id` (server-attached after the fact,
  /// once the visit's own assessment-history sync resolves it) is the
  /// durable one -- it matches `encounters.id` even after a full local data
  /// wipe or on a different device, since it rides along in the ordinary
  /// Call Logs pull. Checking both keeps every call matchable regardless of
  /// which id happened to land in `encounters.id` for a given visit -- see
  /// `TeleconsultHistorySection`.
  Future<List<CallLogHistoryRow>> getForEncounters(List<String> encounterIds) async {
    if (encounterIds.isEmpty) return const [];
    final placeholders = List.filled(encounterIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableCallLogHistory,
      where: 'encounter_id IN ($placeholders) OR fhir_encounter_id IN ($placeholders)',
      whereArgs: [...encounterIds, ...encounterIds],
      orderBy: 'call_date DESC',
    );
    return rows.map(CallLogHistoryRow.fromDb).toList();
  }

  /// Rows that have a Shukhee `encounter_id` (a call was actually booked
  /// from this visit) but no [CallLogHistoryRow.fhirEncounterId] yet -- the
  /// candidates `OfflineSyncService`'s assessment-history persist step
  /// should attempt to attach a FHIR id to on this sync pass. Cheap to call
  /// on every sync since it only ever returns a handful of rows in
  /// practice (one per Shukhee call this device has made that hasn't been
  /// durably attached server-side yet).
  Future<List<CallLogHistoryRow>> getPendingFhirAttach() async {
    final rows = await _db.db.query(
      AppDatabase.tableCallLogHistory,
      where: "encounter_id IS NOT NULL AND encounter_id != '' "
          'AND fhir_encounter_id IS NULL',
    );
    return rows.map(CallLogHistoryRow.fromDb).toList();
  }

  /// Stamps [fhirEncounterId] onto the row keyed by [id] (the Call Logs
  /// docname) once `attach_fhir_encounter_id` confirms the backend has it --
  /// stops `getPendingFhirAttach` from retrying an already-succeeded
  /// attach on the next sync pass. A later regular Call Logs pull would
  /// eventually write the same value anyway (see `upsertMany`); this just
  /// avoids the redundant network call in the meantime.
  Future<void> stampFhirEncounterId(String id, String fhirEncounterId) async {
    await _db.db.update(
      AppDatabase.tableCallLogHistory,
      {'fhir_encounter_id': fhirEncounterId},
      where: 'id = ?',
      whereArgs: [id],
    );
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
