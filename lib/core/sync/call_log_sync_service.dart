import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../db/call_log_history_dao.dart';
import '../db/sync_meta_dao.dart';
import 'call_log_sync_client.dart';

/// Orchestrates pulling Call Logs history from `spice_next_core.api.sync.pull`
/// into the local `call_log_history` table: pull page(s) -> filter to this
/// doctype's completed rows -> persist -> advance the cursor. Structurally
/// parallel to `OfflineSyncService` but far smaller in scope -- this owns
/// exactly one doctype's worth of read-only, pull-only sync.
class CallLogSyncService {
  CallLogSyncService({
    required CallLogSyncClient client,
    required CallLogHistoryDao dao,
    required SyncMetaDao syncMeta,
  })  : _client = client,
        _dao = dao,
        _syncMeta = syncMeta;

  static const String _entityKey = 'callLogs';

  /// Defensive bound on how many pages a single `pull()` call will walk --
  /// mirrors this codebase's other bounded-retry constants. A legitimately
  /// huge backlog just gets picked up across multiple trigger events instead
  /// of blocking one indefinitely.
  static const int _maxPagesPerRun = 50;

  final CallLogSyncClient _client;
  final CallLogHistoryDao _dao;
  final SyncMetaDao _syncMeta;

  Future<void> pull() async {
    final cursorRow = await _syncMeta.read(_entityKey);
    var cursor = cursorRow?.cursor ?? 0;
    var pages = 0;

    while (true) {
      final page = await _client.pull(cursor: cursor);

      // Only sync calls whose outer `status` has reached "completed" --
      // clinical_data/prescription_link/invoice_link only ever populate at
      // that point (confirmed server-side), and a pending/rejected/cancelled
      // call has nothing useful to show as history. A call still pending
      // when first seen is simply skipped here (not persisted); once its
      // status later flips to completed, the same record's bumped sync_seq
      // (via the server's on_update hook) makes it reappear in a later
      // pull, where it then passes this filter and gets persisted -- no
      // special re-fetch logic needed.
      final rows = page.changes
          .where((c) => c.doctype == 'Call Logs' && !c.deleted && c.doc['status'] == 'completed')
          .map(_toRow)
          .toList();
      if (rows.isNotEmpty) {
        try {
          await _dao.upsertMany(rows);
        } catch (e) {
          debugPrint('[CallLogSyncService] persisting rows failed: $e');
        }
      }

      // Cursor advances from next_cursor regardless of whether this page
      // contained any Call Logs rows at all -- a page legitimately mixes in
      // Patient/Household/etc. changes via the shared global sync_seq
      // cursor; those are this app's other sync path's job, not this
      // service's, and must not block this cursor from advancing.
      cursor = page.nextCursor;
      await _syncMeta.stampCursor(_entityKey, cursor);

      pages++;
      if (!page.hasMore || pages >= _maxPagesPerRun) break;
    }
  }

  CallLogHistoryRow _toRow(SyncChange change) {
    final doc = change.doc;
    final callDateRaw = doc['creation'];
    return CallLogHistoryRow(
      id: change.name,
      syncSeq: change.syncSeq,
      patientId: doc['patient'] as String?,
      encounterId: doc['encounter_id'] as String?,
      status: doc['status'] as String?,
      appointmentStatus: doc['appointment_status'] as String?,
      doctorName: doc['doctor_name'] as String?,
      doctorSpeciality: doc['doctor_speciality'] as String?,
      doctorFacility: doc['doctor_facility'] as String?,
      reason: doc['reason'] as String?,
      clinicalDataJson: normalizeClinicalData(doc['clinical_data']),
      prescriptionLink: doc['prescription_link'] as String?,
      invoiceLink: doc['invoice_link'] as String?,
      callDate: _parseServerDatetime(callDateRaw),
      updatedAt: DateTime.now(),
      rawJson: jsonEncode(doc),
    );
  }

  /// Frappe's own datetime string shape (`"YYYY-MM-DD HH:MM:SS.ffffff"`,
  /// server-local time, no timezone suffix) -- `DateTime.parse` accepts it
  /// directly (space instead of `T` is the one deviation from ISO-8601 it
  /// tolerates). Any other/missing shape degrades to null rather than
  /// throwing -- callDate is display/sort-only, never load-bearing.
  DateTime? _parseServerDatetime(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
