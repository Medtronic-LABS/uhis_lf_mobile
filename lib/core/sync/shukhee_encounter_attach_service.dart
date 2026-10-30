import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../db/call_log_history_dao.dart';
import 'shukhee_encounter_link_client.dart';

/// Durably attaches a visit's server-assigned FHIR Encounter id onto its
/// local Shukhee Call Logs row ([CallLogHistoryDao.stampFhirEncounterId] +
/// [ShukheeEncounterLinkClient.attachFhirEncounterId]), so the call/
/// prescription link (see `TeleconsultHistorySection`/`EncounterDao.
/// idsForPatient`) survives a full local data wipe or a new device instead of
/// depending on any client-side reconciliation state.
///
/// Two callers feed this, in order of how soon each learns the FHIR id after
/// a Shukhee call:
/// - [attachForVisit] — called the moment `OfflinePushService`/
///   `AssessmentRepository`'s push+poll resolves a FHIR id for one pushed
///   assessment (`applyFhirIdByReferenceId`'s call site), typically within a
///   poll round-trip of the visit finishing. The client-minted visit id is
///   already known exactly (from that assessment's own `otherDetails.
///   encounterId`) -- no heuristic needed.
/// - [attachAll] — called from `OfflineSyncService`'s assessment-history
///   *pull* step, a redundant catch-up path for a call whose push/poll never
///   ran on this device (offline for a long stretch, or synced from a
///   different device). Its ids come from `EncounterDao.findPendingDraftId`,
///   a best-effort patient+programme+time-window match.
///
/// Both are safe to call repeatedly and out of order -- a row already
/// attached (`fhir_encounter_id` non-null in `getPendingFhirAttach()`'s
/// filter) is simply absent from the next pass, and a failed attach leaves
/// the local row untouched so the next call retries it.
class ShukheeEncounterAttachService {
  ShukheeEncounterAttachService({
    required CallLogHistoryDao callLogHistory,
    required ShukheeEncounterLinkClient linkClient,
  })  : _callLogHistory = callLogHistory,
        _linkClient = linkClient;

  final CallLogHistoryDao _callLogHistory;
  final ShukheeEncounterLinkClient _linkClient;

  /// Convenience wrapper for [attachForVisit] used directly from
  /// `OfflinePushService`/`AssessmentRepository`'s poll-apply loops: decodes
  /// a `LocalAssessmentEntity.otherDetails` JSON blob and, if it stashed a
  /// client-minted `encounterId` (see `AssessmentRepository.saveAssessment`'s
  /// `enrichedOtherDetails`), attaches [fhirEncounterId] for that visit.
  ///
  /// No-op -- never throws -- when [otherDetailsJson] is null, malformed, or
  /// has no `encounterId` key (e.g. a standalone BP/glucose log that never
  /// went through the visit flow, so there's nothing to attach). Callers that
  /// don't need to know when the attach finishes may call this without
  /// awaiting it (both current call sites do).
  Future<void> attachFromOtherDetails(
    String? otherDetailsJson,
    String fhirEncounterId,
  ) async {
    if (otherDetailsJson == null) return;
    try {
      final decoded = jsonDecode(otherDetailsJson);
      if (decoded is! Map) return;
      final encounterId = decoded['encounterId'];
      if (encounterId is String && encounterId.isNotEmpty) {
        await attachForVisit(encounterId, fhirEncounterId);
      }
    } catch (_) {/* otherDetails malformed -- nothing to attach */}
  }

  /// Single-visit variant. No-op if no local Call Logs row's `encounter_id`
  /// matches [clientVisitId], or if it's already attached.
  Future<void> attachForVisit(String clientVisitId, String fhirEncounterId) async {
    try {
      final pending = await _callLogHistory.getPendingFhirAttach();
      for (final row in pending) {
        if (row.encounterId != clientVisitId) continue;
        await _attach(row.id, fhirEncounterId);
      }
    } catch (e) {
      debugPrint('[ShukheeEncounterAttachService] attachForVisit failed: $e');
    }
  }

  /// Batch variant, keyed by client-minted visit id -> the server's own FHIR
  /// Encounter id for that same visit.
  Future<void> attachAll(Map<String, String> draftToServerEncounterId) async {
    if (draftToServerEncounterId.isEmpty) return;
    try {
      final pending = await _callLogHistory.getPendingFhirAttach();
      for (final row in pending) {
        final fhirEncounterId = draftToServerEncounterId[row.encounterId];
        if (fhirEncounterId == null) continue;
        await _attach(row.id, fhirEncounterId);
      }
    } catch (e) {
      debugPrint('[ShukheeEncounterAttachService] attachAll failed: $e');
    }
  }

  Future<void> _attach(String callLog, String fhirEncounterId) async {
    final attached = await _linkClient.attachFhirEncounterId(
      callLog: callLog,
      fhirEncounterId: fhirEncounterId,
    );
    if (attached) {
      await _callLogHistory.stampFhirEncounterId(callLog, fhirEncounterId);
      debugPrint(
        '[ShukheeEncounterAttachService] attached fhir_encounter_id=$fhirEncounterId '
        'to Call Logs callLog=$callLog',
      );
    }
  }
}
