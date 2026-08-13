import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// CCE / SK referred-call retry limit (product override; tune later).
  static const int cceRetryAttempts = 3;

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
    bool? isWillingToVisitUhc,
    String? visitRejectReason,
    String? otherVisitRejectReason,
    String? callType,
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

    final callExtras = <String, dynamic>{
      'callType': callType ?? 'SCREENED',
      'wrongNumber': wrongNumber,
      if (isWillingToVisitUhc != null)
        'isWillingToVisitUHC': isWillingToVisitUhc,
      if (visitRejectReason != null) 'visitRejectReason': visitRejectReason,
      if (otherVisitRejectReason != null)
        'otherVisitRejectReason': otherVisitRejectReason,
    };

    await _dao.insertCall(FollowUpCallRow(
      id: _uuid.v4(),
      followUpId: followUpId,
      callDate: now,
      status: status,
      duration: durationMinutes,
      reason: reason ?? visitRejectReason,
      otherReason: otherReason ?? otherVisitRejectReason,
      patientStatus: patientStatus,
      attempts: newAttempts,
      latitude: latitude,
      longitude: longitude,
      rawJson: jsonEncode(callExtras),
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

  /// Distinct follow-ups with unsynced call logs — Offline Sync badge count.
  Future<int> pendingPushCount() => _dao.pendingPushCount();

  /// After create accepts: InProgress + mark call rows synced.
  Future<void> markPushed(List<String> ids) => _dao.markPushed(ids);

  /// After status poll Success: promote follow-ups to Success.
  Future<void> markPushSucceeded(List<String> ids) =>
      _dao.markPushSucceeded(ids);

  /// After a failed push: mark these follow-ups NetworkError for retry.
  Future<void> markPushFailed(List<String> ids) => _dao.markPushFailed(ids);

  /// Serialize every pending follow-up into the `followUps[]` array the
  /// offline-sync/create push expects.
  ///
  /// Matches Android Room `FollowUp` + nested `FollowUpCall` Gson wire
  /// (referenceId/syncStatus/caller fields on details). Slim DTO-only pushes
  /// were failing spice update while Android's fuller shape succeeds.
  ///
  /// [provenance] must carry an Android-style offset/Z `modifiedDate`.
  Future<({List<Map<String, dynamic>> wire, List<String> ids})>
      serializePendingForPush({
    required Map<String, dynamic> provenance,
    String calledByUserId = '',
    String calledByUserFullName = '',
    String calledByUserRole = 'SHASTIYA_KORMI',
  }) async {
    final pending = await _dao.pendingPush();
    final wire = <Map<String, dynamic>>[];
    final ids = <String>[];
    var skippedNoServerId = 0;

    for (final row in pending) {
      // Server requires a numeric follow-up id ("Call register id"). Skip rows
      // that arrived with id:null and have no backendId yet — they cannot be
      // updated until a subsequent pull returns a real server id.
      int? serverId = row.backendId;
      Map<String, dynamic> raw = const {};
      try {
        raw = Map<String, dynamic>.from(
            jsonDecode(row.rawJson) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('[FollowUpPush] rawJson decode failed row=${row.id}: $e');
      }
      serverId ??= (raw['id'] as num?)?.toInt();
      if (serverId == null) {
        skippedNoServerId++;
        debugPrint('[FollowUpPush] SKIP row=${row.id} — no backendId and no '
            'raw id; status=${row.syncStatus} patientId=${row.patientId} '
            'rawKeys=${raw.keys.toList()}');
        continue;
      }

      final calls = await _dao.callsFor(row.id, onlyUnsynced: true);
      final attempts = row.attempts ?? 0;
      final unsuccessful = row.unsuccessfulAttempts ?? 0;
      // Android Room local PK — not the call-register id. Stable hash of the
      // Flutter row id keeps retries idempotent enough for status tracking.
      final referenceId = row.id.hashCode & 0x7fffffff;

      // Match Android Room `FollowUp` + `@Ignore followUpDetails/provenance`.
      final parent = <String, dynamic>{
        'referenceId': referenceId == 0 ? serverId : referenceId,
        'id': serverId,
        'householdId': _asWireString(raw['householdId']),
        'memberId': _asWireString(raw['memberId']),
        'patientId': _asWireString(raw['patientId']) ?? row.patientId,
        'encounterId': _asWireString(raw['encounterId']),
        'encounterName': raw['encounterName'],
        'encounterType': raw['encounterType'],
        'patientStatus': raw['patientStatus'],
        'reason': raw['reason'],
        'attempts': attempts,
        'successfulAttempts': (attempts - unsuccessful).clamp(0, attempts),
        'unsuccessfulAttempts': unsuccessful,
        'type': raw['type'] ?? row.type,
        'encounterDate': raw['encounterDate'],
        'nextVisitDate': raw['nextVisitDate'],
        'referredSiteId':
            _asWireString(raw['referredSiteId'] ?? row.referredSiteId),
        'referralFacilityType': raw['referralFacilityType'],
        'villageId': _asWireString(raw['villageId']),
        'isCompleted': row.isCompleted,
        'isWrongNumber': row.isLost,
        // Android create samples omit calledAt and send updatedAt: 0.
        'updatedAt': 0,
        'syncStatus': FollowUpSyncStatus.notSynced,
        'provenance': provenance,
        'followUpDetails': calls
            .map(
              (c) => c.toWire(
                serverFollowUpId: serverId!,
                calledByUserId: calledByUserId,
                calledByUserFullName: calledByUserFullName,
                calledByUserRole: calledByUserRole,
              ),
            )
            .toList(),
      };
      if (raw['currentPatientStatus'] != null) {
        parent['currentPatientStatus'] = raw['currentPatientStatus'];
      }
      wire.add(parent);
      ids.add(row.id);
    }
    debugPrint('[FollowUpPush] pending=${pending.length} '
        'serialized=${wire.length} skippedNoServerId=$skippedNoServerId');
    return (wire: wire, ids: ids);
  }

  static String? _asWireString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }
}
