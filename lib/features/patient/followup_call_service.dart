import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/db/follow_up_dao.dart';

/// Device-side follow-up call/close lifecycle — the one thing the CHW client
/// is actually responsible for (follow-ups themselves are minted by the
/// backend and arrive on the pull; see the SPICE Android reference
/// `FollowUpRepository.addCallHistory`).
///
/// Logging a call: records a [FollowUpCallRow], increments attempt counters,
/// auto-closes the ticket on a wrong number or once retries are exhausted, and
/// flips the follow-up to [FollowUpSyncStatus.notSynced] so it rides the next
/// offline-sync/create push (serialized by [serializePendingForPush]).
class FollowUpCallService {
  FollowUpCallService(this._dao, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final FollowUpDao _dao;
  final DateTime Function() _clock;
  final _uuid = const Uuid();

  /// Max attempts before a ticket auto-completes (Android
  /// `FollowUpCriteria.screeningRetryAttempts`, default 5).
  static const int defaultRetryAttempts = 5;

  /// Log one call attempt against [followUpId]. Returns the updated row, or
  /// null if the follow-up no longer exists.
  Future<FollowUpRow?> logCall({
    required String followUpId,
    required String status, // FollowUpCallStatus.*
    String? reason,
    String? otherReason,
    String? patientStatus,
    double? durationMinutes,
    String? latitude,
    String? longitude,
    int retryAttempts = defaultRetryAttempts,
  }) async {
    final row = await _dao.byId(followUpId);
    if (row == null) return null;

    final now = _clock().millisecondsSinceEpoch;
    final newAttempts = (row.attempts ?? 0) + 1;
    final successful = status == FollowUpCallStatus.successful;
    final wrongNumber = status == FollowUpCallStatus.wrongNumber;
    final newUnsuccessful =
        (row.unsuccessfulAttempts ?? 0) + (successful ? 0 : 1);

    // Close the ticket on a wrong number, or once retries are exhausted
    // (mirrors Android addCallHistory).
    final shouldComplete =
        row.isCompleted || wrongNumber || newAttempts >= retryAttempts;
    final completedAt =
        shouldComplete ? (row.completedAt ?? now) : row.completedAt;

    await _dao.insertCall(FollowUpCallRow(
      id: _uuid.v4(),
      followUpId: followUpId,
      callDate: now,
      status: status,
      duration: durationMinutes,
      reason: reason,
      otherReason: otherReason,
      patientStatus: patientStatus,
      attempts: newAttempts,
      latitude: latitude,
      longitude: longitude,
    ));

    final updated = row.copyWith(
      attempts: newAttempts,
      unsuccessfulAttempts: newUnsuccessful,
      completedAt: completedAt,
      isLost: wrongNumber ? true : row.isLost,
      syncStatus: FollowUpSyncStatus.notSynced,
      updatedAt: now,
    );
    await _dao.update(updated);
    return updated;
  }

  /// Create a device-initiated follow-up (e.g. an SK scheduling a check on a
  /// referral). The backend accepts a follow-up with a null `id` as a create,
  /// so the row is stored NotSynced and pushed on the next offline-sync
  /// cycle, and shows in the patient's Open Follow-ups immediately. Returns
  /// the new local id.
  Future<String> scheduleLocal({
    required String patientId,
    required DateTime dueDate,
    String type = 'MEDICAL_REVIEW',
    String? reason,
    String? referredSiteId,
  }) async {
    final now = _clock().millisecondsSinceEpoch;
    final id = _uuid.v4();
    final raw = <String, dynamic>{
      'patientId': patientId,
      'type': type,
      if (reason != null) 'reason': reason,
      if (referredSiteId != null) 'referredSiteId': referredSiteId,
      'nextVisitDate': dueDate.toUtc().toIso8601String(),
      'dueDate': dueDate.toUtc().toIso8601String(),
    };
    await _dao.update(FollowUpRow(
      id: id,
      patientId: patientId,
      kind: FollowUpKind.medicalReview,
      dueAt: dueDate.millisecondsSinceEpoch,
      attempts: 0,
      unsuccessfulAttempts: 0,
      type: type,
      referredSiteId: referredSiteId,
      syncStatus: FollowUpSyncStatus.notSynced,
      updatedAt: now,
      rawJson: jsonEncode(raw),
    ));
    return id;
  }

  /// How many follow-ups are waiting to be pushed. Drives sync scheduling.
  Future<int> pendingPushCount() => _dao.pendingPushCount();

  /// After a successful push: flip these follow-ups to InProgress + mark their
  /// calls synced.
  Future<void> markPushed(List<String> ids) => _dao.markPushed(ids);

  /// After a failed push: mark these follow-ups NetworkError for retry.
  Future<void> markPushFailed(List<String> ids) => _dao.markPushFailed(ids);

  /// Serialize every pending follow-up into the `followUps[]` array the
  /// offline-sync/create push expects. Overlays the device edits onto the
  /// original server payload ([FollowUpRow.rawJson]) so all server routing
  /// fields (memberId, encounterId, villageId, …) survive the round-trip.
  ///
  /// [provenance] is the caller's audit block (must carry an ISO-8601
  /// `modifiedDate`, which the backend `Instant.parse`s). Returns the wire
  /// array plus the follow-up ids it covers, so the caller can mark them
  /// pushed on a 2xx.
  Future<({List<Map<String, dynamic>> wire, List<String> ids})>
      serializePendingForPush({
    required Map<String, dynamic> provenance,
  }) async {
    final pending = await _dao.pendingPush();
    final wire = <Map<String, dynamic>>[];
    final ids = <String>[];

    for (final row in pending) {
      final calls = await _dao.callsFor(row.id, onlyUnsynced: true);

      Map<String, dynamic> base;
      try {
        base = Map<String, dynamic>.from(
            jsonDecode(row.rawJson) as Map<String, dynamic>);
      } catch (_) {
        base = <String, dynamic>{};
      }

      // Overlay device state onto the server payload. `id` stays the server's
      // Long (null → create, non-null → update); numeric `updatedAt` is what
      // the backend sorts on.
      base['id'] = base['id'] ?? row.backendId;
      base['patientId'] = base['patientId'] ?? row.patientId;
      base['type'] = base['type'] ?? row.type;
      base['referredSiteId'] = base['referredSiteId'] ?? row.referredSiteId;
      base['attempts'] = row.attempts ?? 0;
      base['unsuccessfulAttempts'] = row.unsuccessfulAttempts ?? 0;
      base['isCompleted'] = row.isCompleted;
      base['isWrongNumber'] = row.isLost;
      base['updatedAt'] = row.updatedAt ?? DateTime.now().millisecondsSinceEpoch;
      base['calledAt'] = row.updatedAt;
      base['provenance'] = provenance;
      base['followUpDetails'] = calls.map((c) => c.toWire()).toList();

      wire.add(base);
      ids.add(row.id);
    }
    return (wire: wire, ids: ids);
  }
}
