import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import '../constants/app_strings.dart';
import '../db/follow_up_dao.dart';
import '../db/household_dao.dart';
import '../db/local_assessment_dao.dart';
import '../db/member_dao.dart';
import '../debug/console_log.dart';
import '../models/provance_dto.dart';
import 'sync_activity.dart';
import '../../features/patient/followup_call_service.dart';
import '../../features/visit/forms/pregnancy_outcome_side_effects.dart';

/// Pending-row counts shown on the Offline Sync screen (Spice parity).
///
/// [followUps] is distinct follow-ups that still have unsynced call logs
/// (`follow_up_calls.is_synced = 0`), not ticket `sync_status` alone.
class OfflinePushCounts {
  const OfflinePushCounts({
    this.households = 0,
    this.members = 0,
    this.assessments = 0,
    this.followUps = 0,
    this.failed = 0,
  });

  final int households;
  final int members;
  final int assessments;
  final int followUps;

  /// Households + members + assessments the server rejected on a prior
  /// attempt (`sync_status == 'Failed'`) — excluded from [total] since a
  /// Manual/Initial sync is the only thing that will retry them (see
  /// `includeFailed` on the various DAOs' unsynced queries), and the SK
  /// should see this as a distinct "stuck, needs a manual retry" signal
  /// rather than it silently vanishing from the ordinary pending count.
  final int failed;

  int get total => households + members + assessments + followUps;

  bool get isEmpty => total == 0 && failed == 0;
}

/// Outcome of [OfflinePushService.pushAll].
class OfflinePushResult {
  const OfflinePushResult({
    required this.success,
    this.message,
    this.requestId,
    this.hadWork = false,
  });

  final bool success;
  final String? message;
  final String? requestId;

  /// False when there was nothing to post (caller may still warm-pull).
  final bool hadWork;
}

enum _PushPollResult { success, failed, inProgress }

/// Batch verdict plus the per-assessment breakdown, keyed by the numeric
/// `referenceId` the server echoes for each entity.
class _PushPollOutcome {
  const _PushPollOutcome({
    required this.overall,
    required this.assessmentStatus,
    this.followUpFailed = false,
  });

  final _PushPollResult overall;
  final Map<int, String> assessmentStatus;

  /// True when any `FollowUp` entity in this request finished as Failed.
  final bool followUpFailed;
}

/// Spice-style Manual Offline Sync: one `offline-sync/create` for all pending
/// households, standalone members, assessments and follow-ups, then status
/// poll to stamp `fhir_id` / Success without duplicating local rows.
class OfflinePushService extends ChangeNotifier {
  OfflinePushService({
    required ApiClient api,
    required AuthRepository auth,
    required HouseholdDao households,
    required MemberDao members,
    required LocalAssessmentDao assessments,
    FollowUpCallService? followUpCalls,
  })  : _api = api,
        _auth = auth,
        _households = households,
        _members = members,
        _assessments = assessments,
        _followUpCalls = followUpCalls;

  final ApiClient _api;
  final AuthRepository _auth;
  final HouseholdDao _households;
  final MemberDao _members;
  final LocalAssessmentDao _assessments;
  final FollowUpCallService? _followUpCalls;

  /// Cross-caller lock so assessment auto-sync and enrollment do not race.
  static bool isPushInFlight = false;

  bool _running = false;
  bool get isRunning => _running;

  double _progress = 0;
  double get progress => _progress;

  OfflinePushCounts _counts = const OfflinePushCounts();
  OfflinePushCounts get counts => _counts;

  Future<OfflinePushCounts> refreshCounts() async {
    final hh = await _households.getUnsyncedCount();
    final mem = await _members.getUnsyncedCount();
    final assess = await _assessments.getUnsyncedCount();
    var follow = 0;
    try {
      follow = await _followUpCalls?.pendingPushCount() ?? 0;
    } catch (_) {}
    final failedHh = await _households.getFailedCount();
    final failedMem = await _members.getFailedCount();
    final failedAssess = await _assessments.getFailedCount();
    _counts = OfflinePushCounts(
      households: hh,
      members: mem,
      assessments: assess,
      followUps: follow,
      failed: failedHh + failedMem + failedAssess,
    );
    notifyListeners();
    return _counts;
  }

  /// Push every pending entity in one create request (Spice ManualSync).
  Future<OfflinePushResult> pushAll({
    String syncMode = 'ManualSync',
  }) async {
    if (!_auth.hasSessionCredentials) {
      debugPrint('[OfflinePush] blocked — no auth token/session credentials');
      return OfflinePushResult(
        success: false,
        message: OfflineSyncStrings.notAuthenticated,
      );
    }
    if (_running ||
        isPushInFlight ||
        SyncActivity.householdMemberPushInFlight ||
        SyncActivity.assessmentPushInFlight ||
        SyncActivity.pullInFlight) {
      return OfflinePushResult(
        success: false,
        message: OfflineSyncStrings.syncAlreadyInProgress,
      );
    }

    _running = true;
    isPushInFlight = true;
    SyncActivity.householdMemberPushInFlight = true;
    _progress = 0;
    notifyListeners();

    try {
      await _households.resetStuckInProgress();
      await _members.resetStuckInProgress();
      await _assessments.resetStuckInProgress();

      // Manual / Initial sync also retries prior HTTP failures (a household
      // or member the server rejected doesn't otherwise have any way back
      // into these queries — see LocalAssessmentDao's identical convention).
      final includeFailed =
          syncMode == 'ManualSync' || syncMode == 'InitialSync';

      final unsyncedHouseholds =
          await _households.getUnsynced(includeFailed: includeFailed);
      final nestedMemberIds = <String>[];
      final householdPayloads = <Map<String, dynamic>>[];

      final userId = await _auth.userId() ?? 0;
      final userFhirId = await _auth.userFhirId() ?? '';
      final orgId = await _auth.organizationFhirId() ?? '';
      final deviceId = await _auth.deviceId();
      final profile = await _auth.userProfileSummary();
      final callerFullName = [
        profile.firstName?.trim() ?? '',
        profile.lastName?.trim() ?? '',
      ].where((s) => s.isNotEmpty).join(' ');

      final provenance = ProvanceDto.fromMap({
        // Match Android ProvanceDto / Instant.parse-friendly offset datetime.
        'modifiedDate': toOfflineOffsetDateTime(DateTime.now()),
        'organizationId': orgId,
        'spiceUserId': userId,
        if (userFhirId.isNotEmpty) 'userId': userFhirId else 'userId': '$userId',
        'spiceRole': 'SHASTIYA_KORMI',
      });
      final provenanceJson = provenance.toJson();
      // Android FollowUp provenance omits spiceRole on create; keep assessments
      // on the richer provenance, slim the follow-up copy.
      final followUpProvenance = Map<String, dynamic>.from(provenanceJson)
        ..remove('spiceRole');

      for (final hh in unsyncedHouseholds) {
        final nested = await _members.getUnsyncedForHousehold(
          hh.id,
          excludeIds: nestedMemberIds,
          includeFailed: includeFailed,
        );
        for (final m in nested) {
          nestedMemberIds.add(m.id);
        }
        householdPayloads.add(
          _householdWire(
            hh: hh,
            members: nested
                .map(
                  (m) => _memberWire(
                    m,
                    provenance: provenanceJson,
                    nestedUnderHousehold: true,
                    householdFhirId: null,
                  ),
                )
                .toList(),
            provenance: provenanceJson,
            userId: userId,
          ),
        );
      }

      final otherMembers = await _members.getOtherUnsyncedMembers(
        excludeIds: nestedMemberIds,
        includeFailed: includeFailed,
      );
      final standaloneMemberIds = otherMembers.map((m) => m.id).toList();

      // Resolve household FHIR for wire `householdId` when missing on the row.
      final standalonePayloads = <Map<String, dynamic>>[];
      for (final m in otherMembers) {
        var hhFhir = m.householdFhirId;
        if ((hhFhir == null || hhFhir.isEmpty) &&
            m.householdId != null &&
            m.householdId!.isNotEmpty) {
          final hh = await _households.getById(m.householdId!);
          hhFhir = hh?.fhirId;
        }
        standalonePayloads.add(
          _memberWire(
            m,
            provenance: provenanceJson,
            nestedUnderHousehold: false,
            householdFhirId: hhFhir,
          ),
        );
      }

      final assessmentQueue =
          await _assessments.getUnsyncedForPush(includeFailed: includeFailed);
      if (assessmentQueue.blocked.isNotEmpty) {
        debugPrint(
          '[OfflinePush] holding ${assessmentQueue.blocked.length} '
          'assessment(s) — member or household not registered server-side yet',
        );
      }
      final pendingAssessments = assessmentQueue.ready;
      final assessmentIds = pendingAssessments.map((e) => e.id).toList();
      // Session provenance is shared for households/members/follow-ups.
      // toApiRequest restamps each assessment's modifiedDate from createdAt
      // (Android convertEntityToRequest).
      final assessmentPayloads = pendingAssessments
          .map(
            (e) => e.toApiRequest(
              provenance: provenance,
              peerSupervisorId: userId,
            ),
          )
          .toList();

      var followUpPayloads = <Map<String, dynamic>>[];
      var pushedFollowUpIds = <String>[];
      if (_followUpCalls != null) {
        try {
          final result = await _followUpCalls.serializePendingForPush(
            provenance: followUpProvenance,
            calledByUserId: '$userId',
            calledByUserFullName:
                callerFullName.isNotEmpty ? callerFullName : 'SK $userId',
            calledByUserRole: 'SHASTIYA_KORMI',
          );
          followUpPayloads = result.wire;
          pushedFollowUpIds = result.ids;
        } catch (e) {
          debugPrint('[OfflinePush] follow-up serialize skipped: $e');
        }
      }

      if (householdPayloads.isEmpty &&
          standalonePayloads.isEmpty &&
          assessmentPayloads.isEmpty &&
          followUpPayloads.isEmpty) {
        _progress = 1;
        notifyListeners();
        return OfflinePushResult(
          success: true,
          hadWork: false,
          message: OfflineSyncStrings.nothingPendingToSync,
        );
      }

      final requestId = const Uuid().v4();
      final request = {
        'requestId': requestId,
        'appVersionName': AppConfig.appVersionName,
        'appVersionCode': AppConfig.appVersionCode,
        'appType': AppConfig.appType,
        'syncMode': syncMode,
        if (deviceId.isNotEmpty) 'deviceId': deviceId,
        'households': householdPayloads,
        'householdMembers': standalonePayloads,
        'assessments': assessmentPayloads,
        'followUps': followUpPayloads,
        'householdMemberLinks': <Map<String, dynamic>>[],
        'communityProfiles': <Map<String, dynamic>>[],
        'rxBuddies': <Map<String, dynamic>>[],
      };

      _progress = 0.15;
      notifyListeners();

      debugPrint(
        '[OfflinePush] create requestId=$requestId '
        'hh=${householdPayloads.length} members=${standalonePayloads.length} '
        'assessments=${assessmentPayloads.length} '
        'followUps=${followUpPayloads.length}',
      );
      ConsoleLog.json(
        '[OfflinePush] offline-sync/create payload '
        '(requestId=$requestId)',
        request,
      );

      try {
        final response = await _api.dio.post<Map<String, dynamic>>(
          Endpoints.offlineSyncCreate,
          data: request,
        );
        final status = response.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          // The server's validation detail lives in the body; without this the
          // failure surfaces as a bare status code and the cause is invisible.
          // Chunked via ConsoleLog.json because logcat drops very long lines.
          ConsoleLog.json(
            '[OfflinePush] create REJECTED status=$status '
            '(requestId=$requestId) body',
            response.data,
          );
          await _markNetworkOrFailed(
            householdIds: unsyncedHouseholds.map((e) => e.id).toList(),
            memberIds: [...nestedMemberIds, ...standaloneMemberIds],
            assessmentIds: assessmentIds,
            followUpIds: pushedFollowUpIds,
            network: false,
          );
          return OfflinePushResult(
            success: false,
            hadWork: true,
            requestId: requestId,
            message: OfflineSyncStrings.syncFailedHttp('$status'),
          );
        }
      } on DioException catch (e) {
        ConsoleLog.json(
          '[OfflinePush] create DioException type=${e.type} '
          'status=${e.response?.statusCode} (requestId=$requestId) body',
          e.response?.data ?? e.message,
        );
        final isNetwork = e.response == null ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError;
        await _markNetworkOrFailed(
          householdIds: unsyncedHouseholds.map((e) => e.id).toList(),
          memberIds: [...nestedMemberIds, ...standaloneMemberIds],
          assessmentIds: assessmentIds,
          followUpIds: pushedFollowUpIds,
          network: isNetwork,
        );
        return OfflinePushResult(
          success: false,
          hadWork: true,
          requestId: requestId,
          message: isNetwork
              ? OfflineSyncStrings.noNetworkChangesKept
              : OfflineSyncStrings.syncFailedHttp('${e.response?.statusCode}'),
        );
      }

      // Accepted — mark InProgress so a concurrent Start cannot re-POST.
      final hhIds = unsyncedHouseholds.map((e) => e.id).toList();
      final allMemberIds = [...nestedMemberIds, ...standaloneMemberIds];
      await _households.updateSyncStatus(hhIds, 'InProgress');
      await _members.updateSyncStatus(allMemberIds, 'InProgress');
      if (assessmentIds.isNotEmpty) {
        await _assessments.updateSyncStatus(
          assessmentIds,
          AssessmentSyncStatus.inProgress,
        );
      }
      if (pushedFollowUpIds.isNotEmpty && _followUpCalls != null) {
        try {
          await _followUpCalls.markPushed(pushedFollowUpIds);
        } catch (e) {
          debugPrint('[OfflinePush] follow-up markPushed skipped: $e');
        }
      }

      _progress = 0.4;
      notifyListeners();

      final outcome = await _pollAndApply(
        requestId: requestId,
        deviceId: deviceId,
        userId: userId,
      );
      final poll = outcome.overall;

      // inProgress → leave every row InProgress (no duplicate re-POST).
      if (pendingAssessments.isNotEmpty && poll != _PushPollResult.inProgress) {
        final succeeded = <String>[];
        final failed = <String>[];
        for (final entity in pendingAssessments) {
          final reported = entity.referenceId == null
              ? null
              : outcome.assessmentStatus[entity.referenceId];
          // Anything the server did not name inherits the batch verdict.
          final ok = reported == null
              ? poll == _PushPollResult.success
              : reported == 'Success';
          (ok ? succeeded : failed).add(entity.id);
        }
        if (failed.isNotEmpty) {
          await _assessments.updateSyncStatus(
              failed, AssessmentSyncStatus.failed);
        }
        if (succeeded.isNotEmpty) {
          await _assessments.updateSyncStatus(
              succeeded, AssessmentSyncStatus.success);
        }
      }

      // FollowUp Failed leaves referenceId null — reopen the batch we marked
      // InProgress on create-accept so Manual Sync can retry.
      if (outcome.followUpFailed &&
          pushedFollowUpIds.isNotEmpty &&
          _followUpCalls != null) {
        try {
          await _followUpCalls.markPushFailed(pushedFollowUpIds);
        } catch (e) {
          debugPrint('[OfflinePush] follow-up markPushFailed skipped: $e');
        }
      } else if (poll == _PushPollResult.success &&
          pushedFollowUpIds.isNotEmpty &&
          _followUpCalls != null) {
        // Status poll never stamps FollowUp → Success in entityList handling;
        // promote locally so tickets do not stick at InProgress after calls
        // were already marked synced on create-accept.
        try {
          await _followUpCalls.markPushSucceeded(pushedFollowUpIds);
        } catch (e) {
          debugPrint('[OfflinePush] follow-up markPushSucceeded skipped: $e');
        }
      }

      _progress = 1;
      await refreshCounts();

      if (poll == _PushPollResult.failed) {
        return OfflinePushResult(
          success: false,
          hadWork: true,
          requestId: requestId,
          message: outcome.followUpFailed
              ? OfflineSyncStrings.followUpSyncFailedRetry
              : OfflineSyncStrings.reportedFailedForSomeRecords,
        );
      }
      if (poll == _PushPollResult.inProgress) {
        return OfflinePushResult(
          success: true,
          hadWork: true,
          requestId: requestId,
          message: OfflineSyncStrings.acceptedStillProcessing,
        );
      }
      return OfflinePushResult(
        success: true,
        hadWork: true,
        requestId: requestId,
        message: OfflineSyncStrings.offlineSyncCompleted,
      );
    } catch (e, st) {
      debugPrint('[OfflinePush] ✗ $e\n$st');
      return OfflinePushResult(
        success: false,
        hadWork: true,
        message: 'Sync failed: $e',
      );
    } finally {
      _running = false;
      isPushInFlight = false;
      SyncActivity.householdMemberPushInFlight = false;
      notifyListeners();
    }
  }

  Future<_PushPollOutcome> _pollAndApply({
    required String requestId,
    required String deviceId,
    required int userId,
    int maxAttempts = 4,
    Duration delayBetween = const Duration(seconds: 8),
  }) async {
    var sawFailed = false;
    var followUpFailed = false;
    final assessmentStatus = <int, String>{};
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) await Future<void>.delayed(delayBetween);
      _progress = 0.4 + (0.5 * attempt / maxAttempts);
      notifyListeners();

      try {
        final res = await _api.dio.post<Map<String, dynamic>>(
          Endpoints.offlineSyncStatus,
          data: {
            'requestId': requestId,
            'dataRequired': false,
            'userId': userId,
            'appVersionName': AppConfig.appVersionName,
            'appVersionCode': AppConfig.appVersionCode,
            if (deviceId.isNotEmpty) 'deviceId': deviceId,
          },
        );
        final entities = res.data?['entityList'];
        debugPrint(
          '[OfflinePush] status poll $attempt/$maxAttempts '
          'entities=${entities is List ? entities.length : 0}',
        );
        if (entities is! List || entities.isEmpty) continue;

        var anyInProgress = false;
        for (final raw in entities) {
          if (raw is! Map) continue;
          final type = raw['type']?.toString() ?? '';
          final status = raw['status']?.toString() ?? '';
          final refId = raw['referenceId']?.toString();
          final fhirId = raw['fhirId']?.toString();

          if (status == 'InProgress') {
            anyInProgress = true;
            continue;
          }
          if (status == 'Failed') {
            sawFailed = true;
            // FollowUp rows often have referenceId:null on failure — still
            // need to reopen them for retry (create already marked InProgress).
            if (type == 'FollowUp') followUpFailed = true;
          }
          if (refId == null || refId.isEmpty) continue;
          if (status != 'Success' && status != 'Failed') continue;

          // Match the entity type exactly. Substring matching folded
          // "MemberAssessmentFollowUpMap" — a server-side join whose
          // referenceId is the member id — into the member branch, which then
          // stamped an unrelated status onto that member row.
          switch (type) {
            case 'Household':
              await _households.updateFhirId(
                localId: refId,
                fhirId: status == 'Success' ? fhirId : null,
                syncStatus: status,
              );
            case 'HouseholdMember':
              await _members.updateFhirId(
                localId: refId,
                fhirId: status == 'Success' ? fhirId : null,
                syncStatus: status,
              );
            case 'Assessment':
              final reference = int.tryParse(refId);
              if (reference == null) break;
              assessmentStatus[reference] = status;
              if (status == 'Success' &&
                  fhirId != null &&
                  fhirId.isNotEmpty &&
                  fhirId != 'null') {
                await _assessments.applyFhirIdByReferenceId(reference, fhirId);
              }
          }
        }

        if (!anyInProgress) {
          return _PushPollOutcome(
            overall:
                sawFailed ? _PushPollResult.failed : _PushPollResult.success,
            assessmentStatus: assessmentStatus,
            followUpFailed: followUpFailed,
          );
        }
      } on DioException catch (e) {
        debugPrint('[OfflinePush] status poll error: ${e.type}');
      }
    }
    return _PushPollOutcome(
      overall: sawFailed ? _PushPollResult.failed : _PushPollResult.inProgress,
      assessmentStatus: assessmentStatus,
      followUpFailed: followUpFailed,
    );
  }

  Future<void> _markNetworkOrFailed({
    required List<String> householdIds,
    required List<String> memberIds,
    required List<String> assessmentIds,
    required List<String> followUpIds,
    required bool network,
  }) async {
    final hhStatus = network ? 'NetworkError' : 'NotSynced';
    final memStatus = network ? 'NetworkError' : 'NotSynced';
    await _households.updateSyncStatus(householdIds, hhStatus);
    await _members.updateSyncStatus(memberIds, memStatus);
    if (assessmentIds.isNotEmpty) {
      await _assessments.updateSyncStatus(
        assessmentIds,
        network
            ? AssessmentSyncStatus.networkError
            : AssessmentSyncStatus.failed,
      );
    }
    if (followUpIds.isNotEmpty && _followUpCalls != null) {
      try {
        await _followUpCalls.markPushFailed(followUpIds);
      } catch (_) {}
    }
  }

  Map<String, dynamic> _householdWire({
    required HouseholdEntity hh,
    required List<Map<String, dynamic>> members,
    required Map<String, dynamic> provenance,
    required int userId,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final villageId = int.tryParse(hh.villageId ?? '') ?? 0;
    final subVillageId = int.tryParse(hh.subVillageId ?? '') ?? 0;
    final householdNo =
        int.tryParse(hh.householdNo ?? '') ?? hh.createdAt ?? nowMs;
    return {
      'referenceId': hh.referenceId ?? hh.id,
      'name': hh.name ?? '',
      'householdNo': householdNo,
      'householdType': 'Permanent',
      'villageId': villageId,
      if (subVillageId > 0) 'subVillageId': subVillageId,
      'village': hh.village ?? '',
      'shasthyaShebikaId': userId,
      'noOfPeople': hh.memberCount ?? members.length,
      'latitude': hh.latitude ?? 0.0,
      'longitude': hh.longitude ?? 0.0,
      'provenance': provenance,
      'householdMembers': members,
      'createdAt': hh.createdAt ?? nowMs,
      'updatedAt': hh.updatedAt ?? nowMs,
    };
  }

  /// Wire DTO for create — enrollment fields when present, baby-safe defaults
  /// otherwise. [nestedUnderHousehold] omits server `householdId` so the
  /// member is created under the parent household reference only.
  Map<String, dynamic> _memberWire(
    HouseholdMemberEntity m, {
    required Map<String, dynamic> provenance,
    required bool nestedUnderHousehold,
    required String? householdFhirId,
  }) {
    final base = PregnancyOutcomeSideEffects.toHouseholdMemberWire(
      entity: m,
      provenance: provenance,
    );
    // Enrich with enrollment fields the baby helper leaves blank.
    base['nationalId'] = m.nationalId ?? '';
    base['idType'] = _normalizeIdType(m.idType);
    base['isHouseholdHead'] = m.isHouseholdHead;
    base['maritalStatus'] = (m.maritalStatus ?? '').toLowerCase();
    base['disability'] = _disabilityValue(m.disability);
    base['phoneNumber'] = m.phone ?? '';
    base['phoneNumberCategory'] = m.phoneNumberCategory ?? '';
    base['isChild'] = _isChild(m.dob);
    base['householdReferenceId'] =
        m.householdReferenceId ?? m.householdId ?? '';

    if (nestedUnderHousehold) {
      base.remove('householdId');
    } else if (householdFhirId != null && householdFhirId.isNotEmpty) {
      base['householdId'] = householdFhirId;
    } else {
      // Prefer server id; never send a bare local PK as householdId.
      base.remove('householdId');
      if (m.householdFhirId != null && m.householdFhirId!.isNotEmpty) {
        base['householdId'] = m.householdFhirId;
      }
    }
    return base;
  }

  static String _normalizeIdType(String? raw) {
    if (raw == null || raw.isEmpty) return 'na';
    final s = raw.toLowerCase().replaceAll(' ', '');
    return switch (s) {
      'nationalid' => 'nid',
      'notavailable' => 'na',
      _ => s,
    };
  }

  static String _disabilityValue(String? status) {
    final s = (status ?? '').toLowerCase();
    return (s == 'none' || s == 'absent' || s == 'no' || s.isEmpty)
        ? 'absent'
        : 'present';
  }

  static bool _isChild(String? dob) {
    if (dob == null || dob.isEmpty) return false;
    final parsed = DateTime.tryParse(dob);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inDays < 18 * 365;
  }
}
