import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/debug/console_log.dart';
import '../../core/api/endpoints.dart' show Endpoints;
import '../../core/auth/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/pregnancy_episode_dao.dart';
import '../../core/models/json_read.dart';
import '../../core/models/provance_dto.dart';
import '../../core/sync/offline_push_service.dart';
import '../../core/sync/sync_activity.dart';
import '../patient/followup_call_service.dart';
import 'forms/pregnancy_outcome_side_effects.dart';
import 'forms/visit_summary_details.dart';
import 'forms/vitals_trend.dart';

/// Repository for offline-first assessment management matching Android pattern.
///
/// Follows Android spice-2.0 pattern:
/// 1. Save to local DB with sync_status = pending
/// 2. Attempt immediate sync if online
/// 3. Batch sync via offline-service when connectivity returns
///
/// Phase 1: Supports caller-supplied encounterId for unified assessments.
/// Multiple programme assessments from the same visit share one encounterId.
class AssessmentRepository extends ChangeNotifier {
  AssessmentRepository({
    required LocalAssessmentDao dao,
    required ApiClient api,
    required AuthRepository auth,
    AssessmentDao? historyDao,
    FollowUpCallService? followUpCalls,
    MemberDao? memberDao,
  })  : _dao = dao,
        _api = api,
        _auth = auth,
        _historyDao = historyDao,
        _followUpCalls = followUpCalls,
        _memberDao = memberDao;

  final LocalAssessmentDao _dao;
  final ApiClient _api;
  final AuthRepository _auth;
  // Server-synced visit history (assessments table). May be null when not
  // wired in (e.g., during unit tests where the full DB is not available).
  final AssessmentDao? _historyDao;
  // Pending follow-up call attempts ride the same offline-sync/create push.
  // Null in unit tests where the follow-up DB isn't wired.
  final FollowUpCallService? _followUpCalls;
  // New household members (e.g. live-birth babies) ride the same push.
  final MemberDao? _memberDao;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  /// Save assessment locally and attempt sync.
  ///
  /// Returns the local assessment ID for tracking.
  ///
  /// [encounterId] - Optional caller-supplied encounter ID (UUID v4).
  /// When provided, multiple assessments from the same unified visit
  /// can share this ID, enabling backend deduplication and linking.
  Future<String> saveAssessment({
    required String assessmentType,
    required Map<String, dynamic> assessmentDetails,
    required int householdMemberLocalId,
    String? memberId,
    String? householdId,
    String? patientId,
    String? villageId,
    String? encounterId,
    bool isReferred = false,
    String? referralStatus,
    List<String>? referredReasons,
    List<String>? customStatus,
    String? pregnancyEpisodeId,
    int? followUpId,
    double latitude = 0.0,
    double longitude = 0.0,
    Map<String, dynamic>? otherDetails,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final type = assessmentType.toUpperCase();
    // See kPregnancyEpisodeLinkedTypes — single source of truth matching
    // Android's OfflineSyncRepository.getPregnancyEpisodeId(). This fallback
    // UUID only fires if a caller didn't already resolve a real episode id
    // (UnifiedFormNotifier always does today via PregnancyEpisodeDao).
    final resolvedEpisodeId = pregnancyEpisodeId ??
        (kPregnancyEpisodeLinkedTypes.contains(type)
            ? const Uuid().v4()
            : null);

    final enrichedOtherDetails = <String, dynamic>{
      ...?otherDetails,
      'encounterId': ?encounterId,
    };

    // Screens hand us whatever id they had on hand, which since the local-PK
    // migration is usually the member's autoincrement id rather than its FHIR
    // id. Resolve against the member row here so the stored assessment carries
    // the same identity Android writes.
    final identity = await _resolveEncounterIdentity(
      householdMemberLocalId: householdMemberLocalId,
      memberId: memberId,
      householdId: householdId,
      patientId: patientId,
      villageId: villageId,
    );

    final entity = LocalAssessmentEntity(
      id: id,
      householdMemberLocalId: householdMemberLocalId,
      memberId: identity.memberId,
      householdId: identity.householdId,
      patientId: identity.patientId,
      villageId: identity.villageId,
      assessmentType: assessmentType.toUpperCase(),
      assessmentDetails: jsonEncode(assessmentDetails),
      otherDetails: enrichedOtherDetails.isNotEmpty
          ? jsonEncode(enrichedOtherDetails)
          : null,
      isReferred: isReferred,
      referralStatus: isReferred ? 'Referred' : (referralStatus ?? 'Recovered'),
      referredReasons:
          referredReasons != null ? jsonEncode(referredReasons) : null,
      customStatus: (customStatus != null && customStatus.isNotEmpty)
          ? jsonEncode(customStatus)
          : null,
      followUpId: followUpId,
      pregnancyEpisodeId: resolvedEpisodeId,
      latitude: latitude,
      longitude: longitude,
      syncStatus: AssessmentSyncStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    await _dao.insert(entity);
    await _refreshPendingCount();

    return id;
  }

  /// Spice `updateOtherAssessmentDetails` — merge Step 3 summary keys into
  /// each pending assessment for this visit and return how many rows were
  /// updated. Caller should then [syncPendingAssessments].
  Future<int> applyStep3Summary({
    required String encounterId,
    DateTime? nextVisitDate,
    required bool isReferred,
    String? referralFacilityType,
    String? referredSiteId,
  }) async {
    final updated = await _dao.mergeOtherDetailsForEncounter(
      encounterId: encounterId,
      patchFor: (row) => VisitSummaryDetails.patchFor(
        assessmentType: row.assessmentType,
        nextVisitDate: nextVisitDate,
        isReferred: isReferred || row.isReferred,
        referralFacilityType: referralFacilityType,
        referredSiteId: referredSiteId,
      ),
    );
    if (updated > 0) {
      debugPrint(
        '[AssessmentRepo] Step 3 summary applied to $updated assessment(s) '
        'encounter=$encounterId nextVisit=$nextVisitDate referred=$isReferred',
      );
      await _refreshPendingCount();
    }
    return updated;
  }

  /// Resolve the encounter identity from the member row, mirroring the join
  /// Android's `AssessmentDAO` does at sync time (`hhm.patient_id as patientId`).
  ///
  /// When the member row is found, [patientId] prefers `members.patient_id`
  /// and falls back to the visit-route id so local lookups still resolve for a
  /// member the server has not assigned a patient id to yet. Push re-derives
  /// the outgoing value from `hhm.patient_id`, matching Spice.
  Future<({
    String? memberId,
    String? householdId,
    String? patientId,
    String? villageId,
  })> _resolveEncounterIdentity({
    required int householdMemberLocalId,
    String? memberId,
    String? householdId,
    String? patientId,
    String? villageId,
  }) async {
    String? keep(String? value) => value?.isNotEmpty == true ? value : null;

    final dao = _memberDao;
    if (dao == null) {
      return (
        memberId: memberId,
        householdId: householdId,
        patientId: patientId,
        villageId: villageId,
      );
    }

    try {
      var member = householdMemberLocalId > 0
          ? await dao.getById('$householdMemberLocalId')
          : null;
      if (member == null && keep(patientId) != null) {
        member = await dao.getByPatientId(patientId!);
      }
      if (member == null) {
        debugPrint(
            '[Assessment] identity unresolved — localId=$householdMemberLocalId '
            'patientId=$patientId; storing caller-supplied ids');
        return (
          memberId: memberId,
          householdId: householdId,
          patientId: patientId,
          villageId: villageId,
        );
      }
      final resolved = (
        memberId: keep(member.fhirId) ?? keep(memberId),
        householdId: keep(member.householdFhirId) ?? keep(householdId),
        // Local reads (visit history, visit numbering, same-day ANC guard,
        // worklist scoring) all key on this column, so keep the local id when
        // the server has not assigned a patient id yet. The wire value is
        // re-derived from hhm.patient_id in getUnsyncedForPush, so a local PK
        // never reaches the server.
        patientId: keep(member.patientId) ?? keep(patientId),
        villageId: keep(villageId) ??
            keep(member.subVillageId) ??
            keep(member.villageId),
      );
      debugPrint(
          '[Assessment] identity resolved — member=${resolved.memberId} '
          'patient=${resolved.patientId} household=${resolved.householdId} '
          'village=${resolved.villageId}');
      return resolved;
    } catch (e) {
      debugPrint('[Assessment] identity lookup failed: $e');
      return (
        memberId: memberId,
        householdId: householdId,
        patientId: patientId,
        villageId: villageId,
      );
    }
  }

  /// Batch sync all pending assessments via `offline-sync/create` matching Android.
  ///
  /// [syncMode] mirrors Android's sync mode constants:
  ///   - `'AutomaticSync'` — triggered by connectivity-restored event
  ///   - `'ManualSync'` — triggered by the user tapping Sync
  ///   - `'InitialSync'` — first login sync (pass when bootstrapping)
  ///
  /// This is the only write path — no direct assessment/create call.
  Future<int> syncPendingAssessments({
    String syncMode = 'ManualSync',
  }) async {
    if (OfflinePushService.isPushInFlight) {
      debugPrint(
          '[AssessmentSync] Offline Sync push in flight — skip assessment sync');
      return 0;
    }
    if (_isSyncing) {
      debugPrint('[AssessmentSync] Already syncing — skip');
      return 0;
    }
    if (SyncActivity.pullInFlight) {
      debugPrint('[AssessmentSync] Pull in flight — skip assessment sync');
      return 0;
    }

    _isSyncing = true;
    SyncActivity.assessmentPushInFlight = true;
    notifyListeners();

    try {
      // Rows marked inProgress mid-flight (app killed / crash) never re-enter
      // getUnsynced otherwise — reclaim them before each push attempt.
      final recovered = await _dao.resetStuckInProgress();
      if (recovered > 0) {
        debugPrint(
            '[AssessmentSync] Recovered $recovered stuck inProgress → pending');
      }

      // Manual / Initial sync also retries prior HTTP failures; AutomaticSync
      // only retries pending + networkError (server rejections stay failed).
      final includeFailed =
          syncMode == 'ManualSync' || syncMode == 'InitialSync';
      final queue = await _dao.getUnsyncedForPush(includeFailed: includeFailed);
      final pending = queue.ready;
      if (queue.blocked.isNotEmpty) {
        debugPrint(
            '[AssessmentSync] Holding ${queue.blocked.length} assessment(s) — '
            'member or household not registered server-side yet');
      }
      debugPrint('[AssessmentSync] Pending count: ${pending.length} (syncMode=$syncMode)');
      if (pending.isEmpty) return 0;

      final synced = await _batchSync(pending, syncMode: syncMode);
      await _refreshPendingCount();
      debugPrint('[AssessmentSync] ✓ Synced $synced assessment(s). Pending now: $_pendingCount');
      return synced;
    } catch (e, st) {
      debugPrint('[AssessmentSync] ✗ Sync error: $e\n$st');
      rethrow;
    } finally {
      _isSyncing = false;
      SyncActivity.assessmentPushInFlight = false;
      notifyListeners();
    }
  }

  /// Batch sync via offline-service/offline-sync/create matching Android.
  ///
  /// Error classification mirrors Android `OfflineSyncRepository`:
  /// - [DioException] with no server response → [AssessmentSyncStatus.networkError]
  ///   (eligible for retry on next connectivity event)
  /// - HTTP 4xx/5xx server response → [AssessmentSyncStatus.failed]
  ///   (a server-side problem; not automatically retried)
  Future<int> _batchSync(
    List<LocalAssessmentEntity> assessments, {
    required String syncMode,
  }) async {
    final ids = assessments.map((e) => e.id).toList();
    debugPrint('[AssessmentSync] Marking ${ids.length} as in-progress: $ids');

    await _dao.updateSyncStatus(ids, AssessmentSyncStatus.inProgress);

    final userId = await _auth.userId();
    // userFhirId = FHIR Practitioner resource ID (e.g. stored from login data['fhirId']).
    // Android ProvanceDto.userId = getUserFhirId(), not the numeric userId.
    // Sending numeric userId here causes HAPI-1094: Practitioner/<numericId> not found.
    final userFhirId = await _auth.userFhirId();
    final orgId = await _auth.organizationFhirId();
    final deviceId = await _auth.deviceId();
    debugPrint('[AssessmentSync] Provenance — userId=$userId, userFhirId=$userFhirId, orgId=$orgId, deviceId=$deviceId');

    // Session identity only. Each assessment overwrites modifiedDate with its
    // own createdAt inside toApiRequest (Android ProvanceDto(modifiedDate =
    // entity.createdAt)). Follow-ups below still use this push-time stamp.
    final provenance = ProvanceDto.fromMap({
      'modifiedDate': DateTime.now().toUtc().toIso8601String(),
      'organizationId': orgId,
      'spiceUserId': userId,
      // Use FHIR ID as userId; fall back to numeric string only if FHIR ID not yet stored
      if (userFhirId != null && userFhirId.isNotEmpty)
        'userId': userFhirId
      else if (userId != null)
        'userId': userId.toString(),
    });

    final requestId = const Uuid().v4();
    final assessmentPayloads = assessments
        .map((e) => e.toApiRequest(
              provenance: provenance,
              peerSupervisorId: userId,
            ))
        .toList();

    void logChunked(String tag, String text) {
      const limit = 900;
      for (var start = 0; start < text.length; start += limit) {
        final end = (start + limit).clamp(0, text.length);
        // ignore: avoid_print
        print('$tag ${text.substring(start, end)}');
      }
    }

    debugPrint('[AssessmentSync] requestId: $requestId  appType: ${AppConfig.appType}  syncMode: $syncMode');
    debugPrint('[AssessmentSync] assessments[${assessmentPayloads.length}]:');
    for (var i = 0; i < assessmentPayloads.length; i++) {
      final a = assessmentPayloads[i];
      final assessType = a['assessmentType'] as String? ?? 'unknown';
      final enc = a['encounter'] as Map<String, dynamic>? ?? {};
      debugPrint('[AssessmentSync][$i] === $assessType ===');
      debugPrint('[AssessmentSync][$i] patient=${enc['patientId']} provenance=${enc['provenance']}');
      debugPrint('[AssessmentSync][$i] referral: encounter.referred=${enc['referred']}  patientStatus=${a['patientStatus']}  referredReasons=${a['referredReasons'] ?? "(none)"}  customStatus=${enc['customStatus']}');
      logChunked('[AssessmentSync][$i] details:', jsonEncode(a['assessmentDetails']));
    }

    // Serialize any pending follow-up call attempts so they ride this same
    // offline-sync/create push (Android bundles follow-ups alongside
    // assessments). Defensive: a follow-up serialization failure must never
    // block the assessment push.
    var followUpPayloads = <Map<String, dynamic>>[];
    var pushedFollowUpIds = <String>[];
    if (_followUpCalls != null) {
      try {
        final profile = await _auth.userProfileSummary();
        final callerFullName = [
          profile.firstName?.trim() ?? '',
          profile.lastName?.trim() ?? '',
        ].where((s) => s.isNotEmpty).join(' ');
        final followUpProvenance =
            Map<String, dynamic>.from(provenance.toJson())..remove('spiceRole');
        final result = await _followUpCalls.serializePendingForPush(
          provenance: followUpProvenance,
          calledByUserId: '${userId ?? ''}',
          calledByUserFullName: callerFullName.isNotEmpty
              ? callerFullName
              : 'SK ${userId ?? ''}',
          calledByUserRole: 'SHASTIYA_KORMI',
        );
        followUpPayloads = result.wire;
        pushedFollowUpIds = result.ids;
        if (followUpPayloads.isNotEmpty) {
          debugPrint(
              '[AssessmentSync] attaching ${followUpPayloads.length} pending follow-up(s)');
        }
      } catch (e) {
        debugPrint('[AssessmentSync] follow-up serialize skipped: $e');
      }
    }

    // householdMembers[] is for NEW member registrations only — the server calls
    // createHouseHoldMember on every entry and expects a full DTO. For existing
    // member assessments we send everything in the top-level assessments[] array;
    // the server builds MemberAssessmentFollowUpMap from encounter.memberId +
    // encounter.householdId + provenance on each assessment.
    // Live-birth babies registered after pregnancy outcome ride this array.
    var householdMemberPayloads = <Map<String, dynamic>>[];
    var pushedMemberIds = <String>[];
    if (_memberDao != null) {
      try {
        final includeFailedMembers =
            syncMode == 'ManualSync' || syncMode == 'InitialSync';
        final pendingMembers = await _memberDao.getUnsynced(
          includeFailed: includeFailedMembers,
        );
        if (pendingMembers.isNotEmpty) {
          householdMemberPayloads = pendingMembers
              .map(
                (m) => PregnancyOutcomeSideEffects.toHouseholdMemberWire(
                  entity: m,
                  provenance: provenance.toJson(),
                ),
              )
              .toList();
          pushedMemberIds = pendingMembers.map((m) => m.id).toList();
          debugPrint(
              '[AssessmentSync] attaching ${householdMemberPayloads.length} '
              'pending household member(s)');
        }
      } catch (e) {
        debugPrint('[AssessmentSync] household-member serialize skipped: $e');
      }
    }

    debugPrint('[AssessmentSync] assessments[${assessmentPayloads.length}]:');

    // Build create request matching Android's OfflineSyncRepository.getRequestObject().
    // communityProfiles and rxBuddies are included (empty arrays) so the server
    // receives the full contract shape Android sends.
    final request = {
      'requestId': requestId,
      'appVersionName': AppConfig.appVersionName,
      'appVersionCode': AppConfig.appVersionCode,
      'appType': AppConfig.appType,
      'syncMode': syncMode,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
      'households': <Map<String, dynamic>>[],
      'householdMembers': householdMemberPayloads,
      'assessments': assessmentPayloads,
      'followUps': followUpPayloads,
      'householdMemberLinks': <Map<String, dynamic>>[],
      'communityProfiles': <Map<String, dynamic>>[],
      'rxBuddies': <Map<String, dynamic>>[],
    };

    debugPrint(
        '********** OFFLINE-SYNC CREATE PAYLOAD START **********');
    ConsoleLog.json(
      '[PayloadDebug] sync-create → ${Endpoints.offlineSyncCreate} '
      '(requestId=$requestId, ${assessmentPayloads.length} assessment(s), '
      '${followUpPayloads.length} follow-up(s), '
      '${householdMemberPayloads.length} household member(s))',
      request,
    );
    debugPrint(
        '*********** OFFLINE-SYNC CREATE PAYLOAD END ***********');
    debugPrint('[AssessmentSync] POST ${Endpoints.offlineSyncCreate}');
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        Endpoints.offlineSyncCreate,
        data: request,
      );

      final status = response.statusCode ?? 0;
      debugPrint('[AssessmentSync] Response HTTP $status — body: ${response.data}');

      if (status >= 200 && status < 300) {
        // Android keeps local status InProgress on HTTP 201 and only flips to
        // Success/Failed after POST /offline-sync/status reports terminal
        // entity states. Premature Success hid Failed queue rows (e.g.
        // fhirmapper connection refused) from the SK.
        debugPrint(
            '[AssessmentSync] Queue accepted (HTTP $status) — polling status '
            'for requestId=$requestId');
        final poll = await _pollOfflineSyncStatus(
          requestId: requestId,
          deviceId: deviceId,
        );
        if (poll.overall == _OfflineSyncPollResult.inProgress) {
          // Leave rows inProgress (not pending) so the next sync does not
          // re-POST duplicates. Stuck reclaim is age-gated in
          // LocalAssessmentDao.resetStuckInProgress.
          debugPrint(
              '[AssessmentSync] Status still InProgress after polls — leaving '
              '${ids.length} as inProgress (requestId=$requestId)');
          return 0;
        }

        // Attribute each verdict to the assessment the server named. Anything
        // it did not name inherits the batch outcome.
        final succeededIds = <String>[];
        final failedIds = <String>[];
        for (final entity in assessments) {
          final reported = entity.referenceId == null
              ? null
              : poll.assessmentStatusByReference[entity.referenceId];
          final ok = reported == null
              ? poll.overall == _OfflineSyncPollResult.success
              : reported == 'Success';
          (ok ? succeededIds : failedIds).add(entity.id);
          final fhirId = entity.referenceId == null
              ? null
              : poll.assessmentFhirIdByReference[entity.referenceId];
          if (ok && fhirId != null && fhirId.isNotEmpty) {
            await _dao.applyFhirIdByReferenceId(entity.referenceId!, fhirId);
          }
        }

        if (failedIds.isNotEmpty) {
          await _dao.updateSyncStatus(failedIds, AssessmentSyncStatus.failed);
        }
        if (succeededIds.isNotEmpty) {
          await _dao.updateSyncStatus(
              succeededIds, AssessmentSyncStatus.success);
        }

        if (failedIds.isEmpty) {
          debugPrint('[AssessmentSync] Marked ${ids.length} as success');
          if (pushedFollowUpIds.isNotEmpty && _followUpCalls != null) {
            try {
              // Poll already confirmed Success — stamp FollowUp Success +
              // synced calls (do not leave tickets stuck at InProgress).
              await _followUpCalls.markPushSucceeded(pushedFollowUpIds);
            } catch (e) {
              debugPrint(
                  '[AssessmentSync] follow-up markPushSucceeded skipped: $e');
            }
          }
          if (pushedMemberIds.isNotEmpty && _memberDao != null) {
            try {
              await _memberDao.markSynced(pushedMemberIds);
              debugPrint(
                  '[AssessmentSync] Marked ${pushedMemberIds.length} '
                  'household member(s) as synced');
            } catch (e) {
              debugPrint(
                  '[AssessmentSync] household-member markSynced skipped: $e');
            }
          }
          return ids.length;
        }

        debugPrint(
            '[AssessmentSync] ✗ Status poll reported Failed — marked '
            '${failedIds.length} as failed, ${succeededIds.length} as success');
        throw StateError(
            'Batch sync Failed for requestId=$requestId (status poll): '
            '${failedIds.length} of ${ids.length} assessment(s) rejected');
      } else {
        // Server returned an error response — mark as failed (not network error).
        // Failed assessments are NOT automatically retried; require manual sync.
        await _dao.updateSyncStatus(ids, AssessmentSyncStatus.failed);
        debugPrint('[AssessmentSync] ✗ Marked ${ids.length} as failed (HTTP $status)');
        throw StateError('Batch sync failed: HTTP $status — ${response.data}');
      }
    } on DioException catch (e) {
      // Distinguish transport-level errors (no response) from server errors.
      final isNetworkError = e.response == null ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError;
      if (isNetworkError) {
        // Mark networkError — these are retried automatically when connectivity
        // is restored (matching Android's NotSynced | NetworkError query filter).
        await _dao.updateSyncStatus(ids, AssessmentSyncStatus.networkError);
        debugPrint('[AssessmentSync] ✗ Network error — marked ${ids.length} as networkError (will retry): ${e.type}');
      } else {
        await _dao.updateSyncStatus(ids, AssessmentSyncStatus.failed);
        debugPrint('[AssessmentSync] ✗ Server error — marked ${ids.length} as failed: HTTP ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  Future<void> _refreshPendingCount() async {
    _pendingCount = await _dao.getUnsyncedCount();
    notifyListeners();
  }

  Future<int> getPendingCount() async {
    await _refreshPendingCount();
    return _pendingCount;
  }

  Future<List<LocalAssessmentEntity>> getAssessmentsForPatient(
      String patientId) async {
    return _dao.getByPatientId(patientId);
  }

  Future<LocalAssessmentEntity?> getAssessmentById(String id) async {
    return _dao.getById(id);
  }

  /// True when the patient already has a prior NCD assessment (local or
  /// synced history). Used for BD first-visit vs follow-up referral paths.
  Future<bool> hasPriorNcdAssessment(String patientId) async {
    if (patientId.isEmpty) return false;
    final localRows = await _dao.getByPatientId(patientId);
    if (localRows.any((r) => r.assessmentType.toUpperCase() == 'NCD')) {
      return true;
    }
    if (_historyDao == null) return false;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = historyMap[patientId] ?? const [];
    return rows.any((r) => _isNcdKind(r.kind?.toUpperCase() ?? ''));
  }

  /// Number of childhood visits already recorded for [patientId], across this
  /// device's unsynced rows and synced history. Spice keeps the same counter in
  /// `PregnancyDetail.childVisitNo` and submits `childVisitNo + 1` as
  /// `pncChild.visitNo`.
  Future<int> priorChildhoodVisitCount(String patientId) async {
    if (patientId.isEmpty) return 0;
    final localRows = await _dao.getByPatientId(patientId);
    var count = localRows
        .where((r) => _isChildhoodVisitKind(r.assessmentType.toUpperCase()))
        .length;
    if (_historyDao == null) return count;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = historyMap[patientId] ?? const [];
    count += rows
        .where((r) => _isChildhoodVisitKind(r.kind?.toUpperCase() ?? ''))
        .length;
    return count;
  }

  /// The keys one patient's assessments can be filed under.
  ///
  /// A visit stamps `local_assessments` with whatever id its screen carried
  /// (usually `members.patient_id`), while sync files `assessments` under the
  /// local member PK — see [MemberDao.patientIdsByMemberIds]. Reading only one
  /// of them hides half the patient's ANC history.
  static List<String> _idsFor(
    String patientId,
    String? alsoId, {
    Iterable<String>? extraIds,
  }) =>
      <String>{
        patientId,
        if (alsoId != null) alsoId,
        ...?extraIds,
      }.where((id) => id.isNotEmpty).toList(growable: false);

  /// Local rows across [ids], newest-first and de-duplicated by row id.
  Future<List<LocalAssessmentEntity>> _localRows(List<String> ids) async {
    if (ids.length == 1) return _dao.getByPatientId(ids.first);
    final seen = <String>{};
    final out = <LocalAssessmentEntity>[];
    for (final id in ids) {
      for (final row in await _dao.getByPatientId(id)) {
        if (seen.add(row.id)) out.add(row);
      }
    }
    out.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
    return out;
  }

  /// Synced history rows across [ids], de-duplicated by row id.
  Future<List<AssessmentRow>> _historyRows(List<String> ids) async {
    if (_historyDao == null || ids.isEmpty) return const [];
    final map = await _historyDao.forMany(ids);
    final seen = <String>{};
    final out = <AssessmentRow>[];
    for (final id in ids) {
      for (final row in map[id] ?? const <AssessmentRow>[]) {
        if (seen.add(row.id)) out.add(row);
      }
    }
    return out;
  }

  /// Latest ANC visit date + scheduled next-visit date for Eligible Services /
  /// revisit lock. Prefers the chronologically newest ANC row across local
  /// assessments and synced history. [nextDueAt] comes from summary /
  /// `nextVisitDate` / `nextFollowUpDate` when present (null if not stamped).
  Future<({DateTime lastVisitAt, DateTime? nextDueAt})?> latestAncVisitSchedule(
    String patientId, {
    String? alsoId,
  }) async {
    final ids = _idsFor(patientId, alsoId);
    if (ids.isEmpty) return null;

    DateTime? bestVisit;
    DateTime? bestNextDue;

    void consider(DateTime visitAt, DateTime? nextDue) {
      if (bestVisit == null || visitAt.isAfter(bestVisit!)) {
        bestVisit = visitAt;
        bestNextDue = nextDue;
        return;
      }
      // Same visit moment: keep a stamped next-due if the earlier pick lacked one.
      if (bestVisit != null &&
          !visitAt.isBefore(bestVisit!) &&
          !visitAt.isAfter(bestVisit!) &&
          bestNextDue == null &&
          nextDue != null) {
        bestNextDue = nextDue;
      }
    }

    for (final row in await _localRows(ids)) {
      if (!_isAncVisitKind(row.assessmentType.toUpperCase())) continue;
      final visitAt = row.createdAt;
      if (visitAt == null) continue;
      consider(visitAt, _nextVisitFromOtherDetails(row.otherDetails));
    }

    for (final row in await _historyRows(ids)) {
      final kind = row.kind?.toUpperCase() ?? '';
      if (!_isAncVisitKind(kind)) continue;
      final occurred = row.occurredAt;
      if (occurred == null) continue;
      consider(
        DateTime.fromMillisecondsSinceEpoch(occurred),
        _nextVisitFromHistoryRaw(row.rawJson),
      );
    }

    final visit = bestVisit;
    if (visit == null) return null;
    return (lastVisitAt: visit, nextDueAt: bestNextDue);
  }

  static DateTime? _nextVisitFromOtherDetails(String? otherDetails) {
    if (otherDetails == null || otherDetails.isEmpty) return null;
    try {
      final decoded = jsonDecode(otherDetails);
      if (decoded is! Map) return null;
      return _nextVisitFromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static DateTime? _nextVisitFromHistoryRaw(String rawJson) {
    if (rawJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final top = _nextVisitFromMap(map);
      if (top != null) return top;
      final summary = map['summary'];
      if (summary is Map) {
        return _nextVisitFromMap(Map<String, dynamic>.from(summary));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _nextVisitFromMap(Map<String, dynamic> map) =>
      JsonRead.firstDateTime(map, const [
        'nextVisitDate',
        'nextFollowUpDate',
        'dueDate',
      ]);

  /// Number of ANC visits already recorded for [patientId], across this
  /// device's rows and synced history.
  ///
  /// Unlike [ancVitalsHistory] this counts every ANC assessment, including
  /// ones saved without vitals — a visit still happened, so it must advance
  /// the visit number.
  Future<int> priorAncVisitCount(String patientId, {String? alsoId}) async {
    final ids = _idsFor(patientId, alsoId);
    if (ids.isEmpty) return 0;
    final localRows = await _localRows(ids);
    var count = localRows
        .where((r) => r.assessmentType.toUpperCase() == 'ANC')
        .length;
    count += (await _historyRows(ids))
        .where((r) => _isAncVisitKind(r.kind?.toUpperCase() ?? ''))
        .length;
    return count;
  }

  /// True when this pregnancy has already been registered — a PW profile or
  /// any ANC visit exists locally or in synced history.
  ///
  /// Used to decide whether PW registration should be offered again. Reads
  /// both stores so a device that missed the local enrolment write (or was
  /// re-installed) still recognises a registered woman.
  Future<bool> hasPregnancyRegistration(String patientId) async {
    if (patientId.isEmpty) return false;
    final localRows = await _dao.getByPatientId(patientId);
    if (localRows.any((r) {
      final type = r.assessmentType.toUpperCase();
      return type == 'ANC' || _isPwProfileKind(type);
    })) {
      return true;
    }
    if (_historyDao == null) return false;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = historyMap[patientId] ?? const [];
    return rows.any((r) {
      final kind = r.kind?.toUpperCase() ?? '';
      return _isAncVisitKind(kind) || _isPwProfileKind(kind);
    });
  }

  /// Most-recent weight (kg) for [patientId] from any prior ANC, NCD, or
  /// Cataract assessment (local unsynced rows first, then synced history).
  ///
  /// Pass [alsoId] / [extraIds] when the caller's screen id, local member PK,
  /// and server `members.patient_id` differ — same multi-key rule as
  /// [ancVitalsHistory] / [priorAncVisitCount].
  Future<double?> lastRecordedWeight(
    String patientId, {
    String? alsoId,
    Iterable<String>? extraIds,
    String? memberId,
  }) async {
    return _lastRecordedBiometric(
      patientId,
      _BiometricKind.weight,
      alsoId: alsoId,
      extraIds: extraIds,
      memberId: memberId,
    );
  }

  /// Most-recent height (cm) for [patientId] from any prior ANC, NCD, or
  /// Cataract assessment. Used to prefill and lock height on later visits.
  Future<double?> lastRecordedHeight(
    String patientId, {
    String? alsoId,
    Iterable<String>? extraIds,
    String? memberId,
  }) async {
    return _lastRecordedBiometric(
      patientId,
      _BiometricKind.height,
      alsoId: alsoId,
      extraIds: extraIds,
      memberId: memberId,
    );
  }

  Future<double?> _lastRecordedBiometric(
    String patientId,
    _BiometricKind kind, {
    String? alsoId,
    Iterable<String>? extraIds,
    String? memberId,
  }) async {
    final ids = _idsFor(patientId, alsoId, extraIds: extraIds);
    if (ids.isEmpty && (memberId == null || memberId.isEmpty)) return null;

    // 1. Local rows (newest first) — includes unsynced visits not yet in
    //    history. Height and weight are resolved independently (most recent
    //    non-empty value for each field across ANC / NCD / Cataract).
    final seenLocal = <String>{};
    if (ids.isNotEmpty) {
      for (final row in await _localRows(ids)) {
        if (!seenLocal.add(row.id)) continue;
        if (!_isBiometricSourceLocalType(row.assessmentType)) continue;
        final v = _biometricFromLocalDetails(row.assessmentDetails, kind);
        if (v != null) return v;
      }
    }
    // Assessments are sometimes keyed only by member FHIR id when patient_id
    // was unresolved at save time.
    if (memberId != null && memberId.isNotEmpty) {
      for (final row in await _dao.getByMemberId(memberId)) {
        if (!seenLocal.add(row.id)) continue;
        if (!_isBiometricSourceLocalType(row.assessmentType)) continue;
        final v = _biometricFromLocalDetails(row.assessmentDetails, kind);
        if (v != null) return v;
      }
    }

    // 2. Synced history — same programme types, newest first.
    if (ids.isEmpty) return null;
    final historyRows = List<AssessmentRow>.from(await _historyRows(ids))
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    for (final row in historyRows) {
      final kindTag = row.kind?.toUpperCase() ?? '';
      if (!_isBiometricSourceHistoryKind(kindTag)) continue;
      final v = _biometricFromHistoryRaw(row.rawJson, kind);
      if (v != null) return v;
    }
    return null;
  }

  /// Local assessment types that may carry adult height/weight biometrics.
  static bool _isBiometricSourceLocalType(String assessmentType) {
    switch (assessmentType.toUpperCase()) {
      case 'ANC':
      case 'NCD':
      case 'CATARACT':
        return true;
      default:
        return false;
    }
  }

  /// Synced history kind tags that may carry adult height/weight biometrics.
  static bool _isBiometricSourceHistoryKind(String kind) {
    return _isAncVisitKind(kind) || _isNcdKind(kind) || _isCataractKind(kind);
  }

  /// Height/weight from a locally saved assessment_details blob.
  /// NCD stores them under `biometric` (legacy rows may still use `bpLog`).
  static double? _biometricFromLocalDetails(
    String detailsJson,
    _BiometricKind kind,
  ) {
    Map<String, dynamic> map;
    try {
      map = jsonDecode(detailsJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    return _biometricFromMap(map, kind);
  }

  /// Height/weight from a synced assessments.raw_json row (observations.*,
  /// ANC medicalHistoryPhysicalExamination, NCD biometric/bpLog, etc.).
  static double? _biometricFromHistoryRaw(
    String rawJson,
    _BiometricKind kind,
  ) {
    Map<String, dynamic> raw;
    try {
      raw = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    // Flat observations.height (Android MemberAssessmentObservations) first.
    final obs = raw['observations'];
    if (obs is Map) {
      final fromObs = _biometricFromMap(Map<String, dynamic>.from(obs), kind);
      if (fromObs != null) return fromObs;
    }
    final fromRoot = _biometricFromMap(raw, kind);
    if (fromRoot != null) return fromRoot;
    // Flutter NCD wire / history DTO nests biometric under assessmentDetails
    // (and often assessmentDetails.ncd.biometric) — previously missed here.
    final details = raw['assessmentDetails'];
    if (details is Map) {
      final fromDetails =
          _biometricFromMap(Map<String, dynamic>.from(details), kind);
      if (fromDetails != null) return fromDetails;
    }
    return null;
  }

  /// Shared height/weight extraction for local details and history JSON maps.
  @visibleForTesting
  static double? biometricFromMapForTest(
    Map<String, dynamic> map,
    String field, // 'height' | 'weight'
  ) {
    final kind =
        field == 'weight' ? _BiometricKind.weight : _BiometricKind.height;
    return _biometricFromMap(map, kind);
  }

  static double? _biometricFromMap(
    Map<String, dynamic> map,
    _BiometricKind kind,
  ) {
    final key = kind == _BiometricKind.height ? 'height' : 'weight';
    final anc = map['anc'];
    final ancMedHx = anc is Map ? anc['medicalHistoryPhysicalExamination'] : null;
    final details = map['assessmentDetails'];
    final candidates = <dynamic>[
      map[key],
      if (map['biometric'] is Map) (map['biometric'] as Map)[key],
      if (map['bpLog'] is Map) (map['bpLog'] as Map)[key],
      if (map['ncd'] is Map) ...[
        (map['ncd'] as Map)[key],
        if ((map['ncd'] as Map)['biometric'] is Map)
          ((map['ncd'] as Map)['biometric'] as Map)[key],
        if ((map['ncd'] as Map)['bpLog'] is Map)
          ((map['ncd'] as Map)['bpLog'] as Map)[key],
      ],
      if (map['medicalHistoryPhysicalExamination'] is Map)
        (map['medicalHistoryPhysicalExamination'] as Map)[key],
      if (ancMedHx is Map) ancMedHx[key],
      // Nested assessmentDetails (history DTO / wrapped wire).
      if (details is Map) ...[
        details[key],
        if (details['biometric'] is Map) (details['biometric'] as Map)[key],
        if (details['bpLog'] is Map) (details['bpLog'] as Map)[key],
        if (details['ncd'] is Map) ...[
          (details['ncd'] as Map)[key],
          if ((details['ncd'] as Map)['biometric'] is Map)
            ((details['ncd'] as Map)['biometric'] as Map)[key],
          if ((details['ncd'] as Map)['bpLog'] is Map)
            ((details['ncd'] as Map)['bpLog'] as Map)[key],
        ],
      ],
    ];
    for (final raw in candidates) {
      final v = _positiveDouble(raw);
      if (v != null) return v;
    }
    return null;
  }

  static double? _positiveDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final v = raw.toDouble();
      return v > 0 ? v : null;
    }
    var s = raw.toString().trim();
    if (s.isEmpty) return null;
    // History observations sometimes include units ("165 cm", "60.5 kg").
    s = s.replaceAll(RegExp(r'(cm|kg)$', caseSensitive: false), '').trim();
    final v = double.tryParse(s);
    if (v == null || v <= 0) return null;
    return v;
  }

  /// Prior ANC visit snapshots for the Step 2 AI vitals-trend card.
  ///
  /// Source of truth for synced history is the `assessments` table
  /// (`observations` + visit date). Local `local_assessments` rows are
  /// merged in by calendar day (local wins on the same day). Oldest-first.
  /// Today's in-progress form values are NOT included here.
  Future<List<VisitVitals>> ancVitalsHistory(
    String patientId, {
    String? alsoId,
  }) async {
    final ids = _idsFor(patientId, alsoId);
    if (ids.isEmpty) return const [];

    // 1. Synced history — assessments table (observations + visitDate).
    final fromAssessments = <VisitVitals>[];
    for (final row in await _historyRows(ids)) {
      final kind = row.kind?.toUpperCase() ?? '';
      if (!_isAncKind(kind)) continue;
      final visitAt = _visitDateFromAssessmentRaw(row.rawJson) ??
          (row.occurredAt != null
              ? DateTime.fromMillisecondsSinceEpoch(row.occurredAt!)
              : null);
      final snap = _snapshotFromServerRaw(
        row.rawJson,
        visitAt?.millisecondsSinceEpoch ?? row.occurredAt,
      );
      if (!snap.isEmpty) fromAssessments.add(snap);
    }

    // 2. Local submissions — merge by calendar day (local wins).
    final fromLocal = <VisitVitals>[];
    for (final row in await _localRows(ids)) {
      if (row.assessmentType.toUpperCase() != 'ANC') continue;
      final snap = _snapshotFromAnc(row.assessmentDetails, row.createdAt);
      if (!snap.isEmpty) fromLocal.add(snap);
    }

    return _mergeAncVitalsByVisitDay(
      fromAssessments: fromAssessments,
      fromLocal: fromLocal,
    );
  }

  /// Merge synced `assessments` + `local_assessments` by calendar day.
  /// Same-day collision: local wins (fresher device write).
  static List<VisitVitals> _mergeAncVitalsByVisitDay({
    required List<VisitVitals> fromAssessments,
    required List<VisitVitals> fromLocal,
  }) {
    final byDay = <String, VisitVitals>{};

    String? dayKey(DateTime? d) {
      if (d == null) return null;
      final local = d.toLocal();
      return '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
    }

    var undated = 0;
    for (final snap in fromAssessments) {
      final key = dayKey(snap.date) ?? 'assessments-undated-${undated++}';
      byDay[key] = snap;
    }
    undated = 0;
    for (final snap in fromLocal) {
      final key = dayKey(snap.date) ?? 'local-undated-${undated++}';
      byDay[key] = snap; // local overwrites assessments on same day
    }

    final merged = byDay.values.toList()
      ..sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return a.date!.compareTo(b.date!);
      });
    return merged;
  }

  /// Prefer `visitDate` / `assessmentDate` from assessments.raw_json, then
  /// `occurredAt` column.
  static DateTime? _visitDateFromAssessmentRaw(String rawJson) {
    try {
      final raw = jsonDecode(rawJson) as Map<String, dynamic>;
      final ms = JsonRead.epochMillis(
        raw,
        const ['visitDate', 'assessmentDate', 'completedAt', 'completedDate', 'date'],
      );
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}
    return null;
  }

  /// Returns `pregnantWomanExistingIllness` and `pregnantWomanOnTreatment`
  /// from the most recent prior ANC assessment. Checks local submissions first,
  /// then server-synced history. Returns null when no prior ANC data found.
  Future<Map<String, dynamic>?> lastAncIllnessData(
    String patientId, {
    String? alsoId,
  }) async {
    final ids = _idsFor(patientId, alsoId);
    if (ids.isEmpty) return null;

    // 1. Most-recent local ANC row (newest-first from DAO).
    // Local ANC details are nested: medicalHistoryPhysicalExamination holds
    // pregnantWomanExistingIllness — unwrap before reading.
    final localRows = await _localRows(ids);
    for (final row in localRows) {
      if (row.assessmentType.toUpperCase() != 'ANC') continue;
      try {
        final raw = jsonDecode(row.assessmentDetails) as Map<String, dynamic>;
        final flat = _flattenMap(raw, _ancSubObjects);
        final illness = flat['pregnantWomanExistingIllness'];
        final treatment = flat['pregnantWomanOnTreatment'];
        if (illness != null) {
          return {
            'pregnantWomanExistingIllness': illness,
            if (treatment != null) 'pregnantWomanOnTreatment': treatment,
          };
        }
      } catch (_) {}
    }

    // 2. Server-synced history rows (newest-first).
    final historyRows = List<AssessmentRow>.from(await _historyRows(ids))
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    for (final row in historyRows) {
      if (!_isAncKind(row.kind?.toUpperCase() ?? '')) continue;
      try {
        final raw = jsonDecode(row.rawJson) as Map<String, dynamic>;
        final flat = _flattenMap(raw, _ancSubObjects);
        final illness = flat['pregnantWomanExistingIllness'];
        final treatment = flat['pregnantWomanOnTreatment'];
        if (illness != null) {
          return {
            'pregnantWomanExistingIllness': illness,
            if (treatment != null) 'pregnantWomanOnTreatment': treatment,
          };
        }
      } catch (_) {}
    }
    return null;
  }

  /// Stable ANC obstetric history fields from the most recent prior ANC:
  /// `previousPregnancyComplications`, `ttTdCompleted`,
  /// `facilityIdentifiedForDelivery`. Returns null when no prior ANC found.
  Future<Map<String, dynamic>?> lastAncChronicData(
    String patientId, {
    String? alsoId,
  }) async {
    final ids = _idsFor(patientId, alsoId);
    if (ids.isEmpty) return null;
    const keys = [
      'previousPregnancyComplications',
      'ttTdCompleted',
      'facilityIdentifiedForDelivery',
    ];
    final localRows = await _localRows(ids);
    for (final row in localRows) {
      if (row.assessmentType.toUpperCase() != 'ANC') continue;
      final r = _extractKeys(row.assessmentDetails, keys, _ancSubObjects);
      if (r != null) return r;
    }
    final rows = List<AssessmentRow>.from(await _historyRows(ids))
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    for (final row in rows) {
      if (!_isAncKind(row.kind?.toUpperCase() ?? '')) continue;
      final r = _extractKeys(row.rawJson, keys, _ancSubObjects);
      if (r != null) return r;
    }
    return null;
  }

  /// Stable NCD diagnosis/medication/lifestyle fields from the most recent
  /// prior NCD assessment. Wire names are mapped back to form field IDs:
  ///   diagnosedBP           → isBeforeHtnDiagnosis
  ///   diagnosedBPMedication → medicationFrequencyBp
  ///   diagnosedGlucose      → isBeforeDiabetesDiagnosis
  ///   diagnosedGlucoseMedication → medicationFrequencyBg
  Future<Map<String, dynamic>?> lastNcdChronicData(String patientId) async {
    if (patientId.isEmpty) return null;
    const subObjects = ['bpLog', 'glucoseLog', 'symptomsLog', 'ncd', 'assessmentDetails'];

    Map<String, dynamic>? extract(String jsonStr) {
      try {
        final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
        final flat = _flattenMap(raw, subObjects);
        final result = <String, dynamic>{};
        final htn = flat['isBeforeHtnDiagnosis'] ?? flat['diagnosedBP'];
        if (htn != null) result['isBeforeHtnDiagnosis'] = htn;
        final htnMed = flat['medicationFrequencyBp'] ?? flat['diagnosedBPMedication'];
        if (htnMed != null) result['medicationFrequencyBp'] = htnMed;
        final dm = flat['isBeforeDiabetesDiagnosis'] ?? flat['diagnosedGlucose'];
        if (dm != null) result['isBeforeDiabetesDiagnosis'] = dm;
        final dmMed = flat['medicationFrequencyBg'] ?? flat['diagnosedGlucoseMedication'];
        if (dmMed != null) result['medicationFrequencyBg'] = dmMed;
        final smoker = flat['isRegularSmoker'];
        if (smoker != null) result['isRegularSmoker'] = smoker;
        return result.isEmpty ? null : result;
      } catch (_) {
        return null;
      }
    }

    final localRows = await _dao.getByPatientId(patientId);
    for (final row in localRows) {
      if (row.assessmentType.toUpperCase() != 'NCD') continue;
      final r = extract(row.assessmentDetails);
      if (r != null) return r;
    }
    if (_historyDao == null) return null;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = List<AssessmentRow>.from(historyMap[patientId] ?? const [])
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    for (final row in rows) {
      if (!_isNcdKind(row.kind?.toUpperCase() ?? '')) continue;
      final r = extract(row.rawJson);
      if (r != null) return r;
    }
    return null;
  }

  /// Prior `pncIllness` flags from the most recent PNC_MOTHER assessment
  /// (Android subsequent-visit Hb / glucose mandatory gates).
  ///
  /// Returns `{ anemia, bloodSugar, dmPatient, gdmPatient }` when found.
  Future<Map<String, dynamic>?> lastPncIllnessFlags(String patientId) async {
    if (patientId.isEmpty) return null;
    const subObjects = ['pncMother', 'pncIllness', 'assessmentDetails'];
    const keys = ['anemia', 'bloodSugar', 'dmPatient', 'gdmPatient', 'pncIllness'];

    Map<String, dynamic>? fromJson(String jsonStr) {
      try {
        final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
        // Prefer nested pncIllness object (Spice wire).
        final nested = raw['pncIllness'] ??
            (raw['pncMother'] is Map
                ? (raw['pncMother'] as Map)['pncIllness']
                : null) ??
            (raw['assessmentDetails'] is Map
                ? ((raw['assessmentDetails'] as Map)['pncMother'] is Map
                    ? ((raw['assessmentDetails'] as Map)['pncMother']
                        as Map)['pncIllness']
                    : (raw['assessmentDetails'] as Map)['pncIllness'])
                : null);
        if (nested is Map) {
          return {
            if (nested['anemia'] != null) 'anemia': nested['anemia'],
            if (nested['bloodSugar'] != null)
              'bloodSugar': nested['bloodSugar'],
            if (nested['dmPatient'] != null) 'dmPatient': nested['dmPatient'],
            if (nested['gdmPatient'] != null) 'gdmPatient': nested['gdmPatient'],
          };
        }
        final flat = _extractKeys(jsonStr, keys, subObjects);
        if (flat == null) return null;
        if (flat['pncIllness'] is Map) {
          final m = flat['pncIllness'] as Map;
          return {
            if (m['anemia'] != null) 'anemia': m['anemia'],
            if (m['bloodSugar'] != null) 'bloodSugar': m['bloodSugar'],
            if (m['dmPatient'] != null) 'dmPatient': m['dmPatient'],
            if (m['gdmPatient'] != null) 'gdmPatient': m['gdmPatient'],
          };
        }
        return {
          if (flat['anemia'] != null) 'anemia': flat['anemia'],
          if (flat['bloodSugar'] != null) 'bloodSugar': flat['bloodSugar'],
          if (flat['dmPatient'] != null) 'dmPatient': flat['dmPatient'],
          if (flat['gdmPatient'] != null) 'gdmPatient': flat['gdmPatient'],
        };
      } catch (_) {
        return null;
      }
    }

    final localRows = await _dao.getByPatientId(patientId);
    for (final row in localRows) {
      if (row.assessmentType.toUpperCase() != 'PNC_MOTHER') continue;
      final r = fromJson(row.assessmentDetails);
      if (r != null && r.isNotEmpty) return r;
    }
    if (_historyDao == null) return null;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = List<AssessmentRow>.from(historyMap[patientId] ?? const [])
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    for (final row in rows) {
      if (!_isPncMotherKind(row.kind?.toUpperCase() ?? '')) continue;
      final r = fromJson(row.rawJson);
      if (r != null && r.isNotEmpty) return r;
    }
    return null;
  }

  /// True when the latest ANC indicates anemia in pregnancy — Hb &lt; 11 or
  /// `highRiskPregnantWoman` text/structure contains "anemia"
  /// (Android `highRiskPregnantWoman.contains("Anemia")`).
  Future<bool> hadAnemiaDuringPregnancy(String patientId) async {
    if (patientId.isEmpty) return false;

    bool fromMap(Map<String, dynamic> flat) {
      final hb = flat['hemoglobin'];
      final hbNum = hb is num
          ? hb.toDouble()
          : (hb is String ? double.tryParse(hb) : null);
      if (hbNum != null && hbNum > 0 && hbNum < 11) return true;

      final risk = flat['highRiskPregnantWoman'];
      if (_textContainsAnemia(risk)) return true;
      final summary = flat['summary'];
      if (summary is Map &&
          _textContainsAnemia(summary['highRiskPregnantWoman'])) {
        return true;
      }
      return false;
    }

    final localRows = await _dao.getByPatientId(patientId);
    for (final row in localRows) {
      if (row.assessmentType.toUpperCase() != 'ANC') continue;
      try {
        final raw = jsonDecode(row.assessmentDetails) as Map<String, dynamic>;
        if (fromMap(_flattenMap(raw, [
          ..._ancSubObjects,
          'summary',
          'pointOfCareInvestigations',
        ]))) {
          return true;
        }
      } catch (_) {}
    }
    if (_historyDao == null) return false;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = List<AssessmentRow>.from(historyMap[patientId] ?? const [])
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    for (final row in rows) {
      if (!_isAncVisitKind(row.kind?.toUpperCase() ?? '')) continue;
      try {
        final raw = jsonDecode(row.rawJson) as Map<String, dynamic>;
        if (fromMap(_flattenMap(raw, [
          ..._ancSubObjects,
          'summary',
          'pointOfCareInvestigations',
        ]))) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static bool _textContainsAnemia(Object? value) {
    if (value == null) return false;
    if (value is String) {
      return value.toLowerCase().contains('anemia') ||
          value.toLowerCase().contains('anaemia');
    }
    if (value is List) {
      return value.any(_textContainsAnemia);
    }
    if (value is Map) {
      return value.values.any(_textContainsAnemia) ||
          value.keys.any((k) => _textContainsAnemia(k.toString()));
    }
    return value.toString().toLowerCase().contains('anemia') ||
        value.toString().toLowerCase().contains('anaemia');
  }

  /// Stable PNC Mother history fields from the most recent prior PNC_MOTHER
  /// assessment: gravida, parity, livingChildren, comorbidity flags.
  Future<Map<String, dynamic>?> lastPncMotherChronicData(
      String patientId) async {
    if (patientId.isEmpty) return null;
    const subObjects = [
      'maternalHealthAssessment',
      'pregnancyHistory',
      'pncMother',
      'assessmentDetails',
    ];
    const keys = [
      'gravida',
      'parity',
      'livingChildren',
      'htnPatient',
      'eclampsia',
      'dmPatient',
      'gdmPatient',
      'onTreatmentHtnEclampsia',
      'onTreatmentDmGdm',
    ];
    final localRows = await _dao.getByPatientId(patientId);
    for (final row in localRows) {
      if (row.assessmentType.toUpperCase() != 'PNC_MOTHER') continue;
      final r = _extractKeys(row.assessmentDetails, keys, subObjects);
      if (r != null) return r;
    }
    if (_historyDao == null) return null;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = List<AssessmentRow>.from(historyMap[patientId] ?? const [])
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    for (final row in rows) {
      if (!_isPncMotherKind(row.kind?.toUpperCase() ?? '')) continue;
      final r = _extractKeys(row.rawJson, keys, subObjects);
      if (r != null) return r;
    }
    return null;
  }

  /// Stable Family Planning fields from the most recent prior FP assessment:
  /// familyPlanningMethods, desireForChildrenInFuture, numberOfLivingChildren.
  Future<Map<String, dynamic>?> lastFpData(String patientId) async {
    if (patientId.isEmpty) return null;
    const subObjects = ['familyPlanning', 'family_planning', 'assessmentDetails'];

    Map<String, dynamic>? extract(String jsonStr) {
      try {
        final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
        final flat = _flattenMap(raw, subObjects);
        final result = <String, dynamic>{};
        // Methods are an array on the wire, but the form renders a
        // single-select Spinner — hand back the first option so the prefilled
        // value matches an option id rather than a stringified list.
        final methods = flat['familyPlanningMethods'];
        final method = methods is List
            ? (methods.isEmpty ? null : methods.first)
            : methods;
        if (method != null) result['familyPlanningMethods'] = method;
        // Wire name is desireForChildren; form field is desireForChildrenInFuture.
        final desire = flat['desireForChildrenInFuture'] ?? flat['desireForChildren'];
        if (desire != null) result['desireForChildrenInFuture'] = desire;
        final children = flat['numberOfLivingChildren'];
        if (children != null) result['numberOfLivingChildren'] = children;
        return result.isEmpty ? null : result;
      } catch (_) {
        return null;
      }
    }

    final localRows = await _dao.getByPatientId(patientId);
    for (final row in localRows) {
      if (row.assessmentType.toUpperCase() != 'FAMILY_PLANNING') continue;
      final r = extract(row.assessmentDetails);
      if (r != null) return r;
    }
    if (_historyDao == null) return null;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = List<AssessmentRow>.from(historyMap[patientId] ?? const [])
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    for (final row in rows) {
      if (!_isFpKind(row.kind?.toUpperCase() ?? '')) continue;
      final r = extract(row.rawJson);
      if (r != null) return r;
    }
    return null;
  }

  /// Reads the most-recent assessment row for [patientId] and returns the LMP
  /// date (or null when unavailable).  Scans ALL rows newest-first — LMP data
  /// only exists for maternal patients so no programme filter is needed.
  Future<DateTime?> lmpDateFromHistory(String patientId) async {
    if (patientId.isEmpty || _historyDao == null) return null;
    final historyMap = await _historyDao.forMany([patientId]);
    final rows = List<AssessmentRow>.from(historyMap[patientId] ?? const [])
      ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
    debugPrint('[AssessmentRepo] lmpFromHistory: ${rows.length} total rows '
        'for patient $patientId');
    for (final row in rows) {
      debugPrint('[AssessmentRepo] lmpFromHistory row kind="${row.kind}" id=${row.id}');
      // Print up to 400 chars of rawJson so we can see what keys the server sends.
      final preview = row.rawJson.length > 400
          ? '${row.rawJson.substring(0, 400)}…'
          : row.rawJson;
      debugPrint('[AssessmentRepo] lmpFromHistory row ${row.id} rawJson=$preview');
      final lmp = _extractLmpFromRaw(row.rawJson);
      debugPrint('[AssessmentRepo] lmpFromHistory row ${row.id}: lmp=$lmp');
      if (lmp != null) return lmp;
    }

    // Fallback: scan local assessments (may contain PWPROFILE or ANC submissions
    // with LMP / gestational-weeks data that the server history summary omits).
    // Try both patient_id and member_id columns since legacy rows may be stored
    // under the numeric server household-member ID instead of the FHIR patient ID.
    debugPrint('[AssessmentRepo] lmpFromHistory: no LMP in server history — '
        'scanning local assessments for $patientId');
    var localRows = await _dao.getByPatientId(patientId);
    debugPrint('[AssessmentRepo] lmpFromHistory: ${localRows.length} local rows by patientId');

    if (localRows.isEmpty) {
      // Extract unique member IDs from history rawJson rows.
      final memberIds = <String>{};
      for (final row in rows) {
        try {
          final raw = jsonDecode(row.rawJson) as Map<String, dynamic>;
          final mid = raw['householdMemberId']?.toString() ??
              raw['memberId']?.toString();
          if (mid != null && mid.isNotEmpty) memberIds.add(mid);
        } catch (_) {}
      }
      debugPrint('[AssessmentRepo] lmpFromHistory: trying memberIds=$memberIds');
      for (final mid in memberIds) {
        final byMember = await _dao.getByMemberId(mid);
        localRows = [...localRows, ...byMember];
      }
      debugPrint('[AssessmentRepo] lmpFromHistory: ${localRows.length} local rows by memberId');
    }

    for (final local in localRows) {
      debugPrint('[AssessmentRepo] lmpFromHistory local type=${local.assessmentType} memberId=${local.memberId}');
      final lmp = _extractLmpFromRaw(local.assessmentDetails);
      debugPrint('[AssessmentRepo] lmpFromHistory local ${local.id}: lmp=$lmp');
      if (lmp != null) return lmp;
    }
    return null;
  }

  // ANC sub-object keys used by _toAnc() in UnifiedPayloadMapper.
  static const _ancSubObjects = [
    'medicalHistoryPhysicalExamination',
    'vaccinationAndSupplements',
    'ancServicesBirthPreparedness',
    'pointOfCareInvestigations',
    'dangerSignsRiskIdentification',
    'anc',
    'assessmentDetails',
  ];

  /// Flatten [subObjects] from [raw] into a single map for key lookups.
  static Map<String, dynamic> _flattenMap(
    Map<String, dynamic> raw,
    List<String> subObjects,
  ) {
    final flat = <String, dynamic>{...raw};
    for (final sub in subObjects) {
      if (raw[sub] is Map) {
        flat.addAll((raw[sub] as Map).cast<String, dynamic>());
      }
    }
    return flat;
  }

  /// Extract [keys] from [jsonStr] after unwrapping [subObjects]. Returns null
  /// when the JSON is unparseable or none of the keys are present.
  static Map<String, dynamic>? _extractKeys(
    String jsonStr,
    List<String> keys,
    List<String> subObjects,
  ) {
    try {
      final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
      final flat = _flattenMap(raw, subObjects);
      final result = <String, dynamic>{};
      for (final key in keys) {
        final v = flat[key];
        if (v != null) result[key] = v;
      }
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  /// True when [kind] (already uppercased) looks like an ANC visit tag.
  /// Covers the many variants the backend may send:
  ///   "ANC", "ANTENATAL", "ANTENATAL_CARE", "ANTENATAL CARE",
  ///   "PRENATAL", "MATERNITY", "OBSTETRIC", "PREGNANCY"
  static bool _isAncKind(String kind) {
    if (kind.isEmpty) return false;
    return kind.contains('ANC') ||
        kind.contains('ANTENATAL') ||
        kind.contains('PRENATAL') ||
        kind.contains('MATERNITY') ||
        kind.contains('OBSTETRIC') ||
        kind.contains('PREGNANCY');
  }

  /// Stricter than [_isAncKind]: counts antenatal visits only, so a delivery
  /// record (`PREGNANCY_OUTCOME`) is never mistaken for an ANC visit.
  static bool _isAncVisitKind(String kind) {
    if (kind.isEmpty || kind.contains('OUTCOME')) return false;
    return kind.contains('ANC') ||
        kind.contains('ANTENATAL') ||
        kind.contains('PRENATAL');
  }

  /// Pregnant-woman registration record (Spice `PWPROFILE`).
  static bool _isPwProfileKind(String kind) =>
      kind.replaceAll('_', '').contains('PWPROFILE');

  static bool _isNcdKind(String kind) =>
      kind.contains('NCD') || kind.contains('HYPERTENSION') || kind.contains('DIABETES');

  static bool _isCataractKind(String kind) => kind.contains('CATARACT');

  /// Matches the local type (`CHILDHOOD_VISIT`) and the Spice wire /history
  /// spellings (`ChildHood_Visit`, `CHILD_MENU`).
  static bool _isChildhoodVisitKind(String kind) =>
      kind.contains('CHILDHOOD') || kind == 'CHILD_MENU';

  static bool _isPncMotherKind(String kind) =>
      kind.contains('PNC') && !kind.contains('CHILD') && !kind.contains('NEONAT');

  static bool _isFpKind(String kind) =>
      kind.contains('FAMILY_PLANNING') ||
      kind.contains('FAMILYPLANNING') ||
      kind == 'FP';

  /// Extracts LMP from a server assessment row's rawJson, trying several key
  /// locations the backend may use.  Returns null when nothing recognisable
  /// is found; falls back to deriving a synthetic LMP from gestational weeks.
  static DateTime? _extractLmpFromRaw(String rawJson) {
    try {
      final raw = jsonDecode(rawJson) as Map<String, dynamic>;
      // Flatten sub-objects that may carry the LMP key.
      // Server uses different wrappers for ANC vs PWPROFILE assessment types.
      const wrappers = [
        'observations',
        'assessmentDetails',
        'medicalHistoryPhysicalExamination',
        'pointOfCareInvestigations',
        'medicalHistory',
        'pregnancyDetails',
        'pwProfile',
        'pregnancyDetailsAndHistory',
        'clinicalDetails',
        'pregnancyProfile',
        'obstetricHistory',
      ];
      // PWPROFILE nests two levels deep
      // (assessmentDetails → pwProfile → pregnancyDetailsAndHistory), so lift
      // repeatedly until no wrapper is left.
      var flat = <String, dynamic>{...raw};
      for (var depth = 0; depth < 3; depth++) {
        final next = <String, dynamic>{...flat};
        for (final sub in wrappers) {
          final nested = flat[sub];
          if (nested is Map) {
            next.addAll(nested.cast<String, dynamic>());
          }
        }
        if (next.length == flat.length) break;
        flat = next;
      }

      // ISO strings or epoch millis (int / numeric string) under common keys.
      final lmp = JsonRead.firstDateTime(flat, const [
        'lmpDate',
        'lastMenstrualPeriod',
        'lastMenstrualPeriodDate',
        'lmp',
        'lmpValue',
        'menstrualDate',
        'lastPeriodDate',
      ]);
      if (lmp != null) return lmp;

      // Fallback: derive LMP from gestational weeks.
      for (final key in const [
        'gestationalAge',
        'gestationalWeeks',
        'gaWeeks',
        'weeksPregnant',
      ]) {
        final v = flat[key];
        int? weeks;
        if (v is int) weeks = v;
        if (v is num) weeks = v.toInt();
        if (v is String) weeks = int.tryParse(v);
        if (weeks != null && weeks > 0 && weeks < 45) {
          return DateTime.now().subtract(Duration(days: weeks * 7));
        }
      }
    } catch (_) {}
    return null;
  }

  /// Parses an ANC `assessment_details` JSON blob into a [VisitVitals],
  /// unwrapping the nested programme sub-objects the same way the DAO's
  /// clinical-vitals extractor does.
  static VisitVitals _snapshotFromAnc(String detailsJson, DateTime? date) {
    Map<String, dynamic> map;
    try {
      map = jsonDecode(detailsJson) as Map<String, dynamic>;
    } catch (_) {
      return const VisitVitals();
    }
    return _vitalsFromFlattened(map, date);
  }

  /// Parses a server-synced assessment's `raw_json` into a [VisitVitals].
  static VisitVitals _snapshotFromServerRaw(String rawJson, int? occurredAtMs) {
    Map<String, dynamic> raw;
    try {
      raw = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      return const VisitVitals();
    }
    final date = occurredAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(occurredAtMs)
        : null;
    return _vitalsFromFlattened(raw, date);
  }

  static VisitVitals _vitalsFromFlattened(
      Map<String, dynamic> map, DateTime? date) {
    final flat = <String, dynamic>{...map};
    for (final sub in const [
      'medicalHistoryPhysicalExamination',
      'pointOfCareInvestigations',
      'dangerSignsRiskIdentification',
      'observations',
      'assessmentDetails',
    ]) {
      if (map[sub] is Map) {
        flat.addAll((map[sub] as Map).cast<String, dynamic>());
      }
    }

    int? asInt(String key) {
      final v = flat[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    double? asDouble(String key) {
      final v = flat[key];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    int? sys = asInt('systolic') ?? asInt('bloodPressureSystolic');
    if (sys == null && flat['bpLogDetails'] is List) {
      final log = flat['bpLogDetails'] as List;
      if (log.isNotEmpty && log.first is Map) {
        final s = (log.first as Map)['systolic'];
        if (s is num) sys = s.toInt();
      }
    }
    int? dia = asInt('diastolic') ?? asInt('bloodPressureDiastolic');
    // Parse "130/85" slash-string from member-assessment-history observations.bp
    if (sys == null || dia == null) {
      final bpStr = flat['bp'] as String?;
      if (bpStr != null && bpStr.contains('/')) {
        final parts = bpStr.split('/');
        if (sys == null && parts.isNotEmpty) sys = int.tryParse(parts[0].trim());
        if (dia == null && parts.length > 1) dia = int.tryParse(parts[1].trim());
      }
    }
    final urine = flat['urinaryAlbumin'] ?? flat['urineProtein'];

    return VisitVitals(
      date: date,
      systolic: sys,
      diastolic: dia,
      weight: asDouble('weight'),
      urineProtein: urine is String ? urine : urine?.toString(),
    );
  }

  /// Poll `offline-sync/status` until every entity is terminal (Success/Failed)
  /// or [maxAttempts] is exhausted. Mirrors Android
  /// `ScheduledSyncWork.getSyncStatus` (4 × 10s) /
  /// `OfflineSyncRepository.getSyncStatusForOffline`.
  Future<_OfflineSyncPollOutcome> _pollOfflineSyncStatus({
    required String requestId,
    required String deviceId,
    int maxAttempts = 4,
    Duration delayBetween = const Duration(seconds: 10),
  }) async {
    final userId = await _auth.userId();
    var sawFailed = false;
    final statusByReference = <int, String>{};
    final fhirIdByReference = <int, String>{};

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        await Future<void>.delayed(delayBetween);
      }
      final body = <String, dynamic>{
        'requestId': requestId,
        'dataRequired': false,
        if (userId != null) 'userId': userId,
        'appVersionName': AppConfig.appVersionName,
        'appVersionCode': AppConfig.appVersionCode,
        if (deviceId.isNotEmpty) 'deviceId': deviceId,
      };
      ConsoleLog.banner('[PayloadDebug] sync-status\n${body.toString()}');
      try {
        final res = await _api.dio.post<Map<String, dynamic>>(
          Endpoints.offlineSyncStatus,
          data: body,
        );
        final data = res.data ?? const <String, dynamic>{};
        final entities = data['entityList'];
        debugPrint(
            '[AssessmentSync] status poll $attempt/$maxAttempts → '
            'HTTP ${res.statusCode} entities=${entities is List ? entities.length : 0}');

        if (entities is! List || entities.isEmpty) {
          // Empty list while queue is still spinning up — keep polling.
          continue;
        }

        var anyInProgress = false;
        for (final raw in entities) {
          if (raw is! Map) continue;
          final entityStatus = raw['status']?.toString() ?? '';
          final reference = int.tryParse(raw['referenceId']?.toString() ?? '');
          debugPrint(
              '[AssessmentSync] status entity type=${raw['type']} '
              'ref=${raw['referenceId']} status=$entityStatus '
              'err=${raw['errorMessage']}');
          if (raw['type']?.toString() == 'Assessment' && reference != null) {
            statusByReference[reference] = entityStatus;
            final fhirId = raw['fhirId']?.toString();
            if (fhirId != null && fhirId.isNotEmpty && fhirId != 'null') {
              fhirIdByReference[reference] = fhirId;
            }
          }
          if (entityStatus == 'InProgress') {
            anyInProgress = true;
          } else if (entityStatus == 'Failed') {
            sawFailed = true;
          }
        }
        if (anyInProgress) continue;
        return _OfflineSyncPollOutcome(
          overall: sawFailed
              ? _OfflineSyncPollResult.failed
              : _OfflineSyncPollResult.success,
          assessmentStatusByReference: statusByReference,
          assessmentFhirIdByReference: fhirIdByReference,
        );
      } on DioException catch (e) {
        debugPrint(
            '[AssessmentSync] status poll $attempt/$maxAttempts error: '
            '${e.type} HTTP ${e.response?.statusCode}');
        // Transport blip — keep trying; do not mark Failed yet.
      }
    }
    return _OfflineSyncPollOutcome(
      overall: sawFailed
          ? _OfflineSyncPollResult.failed
          : _OfflineSyncPollResult.inProgress,
      assessmentStatusByReference: statusByReference,
      assessmentFhirIdByReference: fhirIdByReference,
    );
  }
}

enum _OfflineSyncPollResult { success, failed, inProgress }

/// Terminal verdict for the batch plus the per-assessment breakdown, keyed by
/// the numeric `referenceId` the server echoes for each entity.
class _OfflineSyncPollOutcome {
  const _OfflineSyncPollOutcome({
    required this.overall,
    required this.assessmentStatusByReference,
    required this.assessmentFhirIdByReference,
  });

  final _OfflineSyncPollResult overall;
  final Map<int, String> assessmentStatusByReference;
  final Map<int, String> assessmentFhirIdByReference;
}

enum _BiometricKind { height, weight }

class SaveAssessmentResult {
  const SaveAssessmentResult({
    required this.localId,
    required this.syncedImmediately,
    this.fhirId,
    this.error,
  });

  final String localId;
  final bool syncedImmediately;
  final String? fhirId;
  final String? error;

  bool get isSuccess => error == null;
}
