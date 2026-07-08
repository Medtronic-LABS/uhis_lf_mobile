import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart' show Endpoints;
import '../../core/auth/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/models/provance_dto.dart';

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
  })  : _dao = dao,
        _api = api,
        _auth = auth;

  final LocalAssessmentDao _dao;
  final ApiClient _api;
  final AuthRepository _auth;

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
    String? pregnancyEpisodeId,
    int? followUpId,
    double latitude = 0.0,
    double longitude = 0.0,
    Map<String, dynamic>? otherDetails,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final resolvedEpisodeId = pregnancyEpisodeId ??
        (assessmentType.toUpperCase() == 'ANC' ||
                assessmentType.toUpperCase() == 'PNC'
            ? const Uuid().v4()
            : null);

    final enrichedOtherDetails = <String, dynamic>{
      ...?otherDetails,
      'encounterId': ?encounterId,
    };

    final entity = LocalAssessmentEntity(
      id: id,
      householdMemberLocalId: householdMemberLocalId,
      memberId: memberId,
      householdId: householdId,
      patientId: patientId,
      villageId: villageId,
      assessmentType: assessmentType.toUpperCase(),
      assessmentDetails: jsonEncode(assessmentDetails),
      otherDetails: enrichedOtherDetails.isNotEmpty
          ? jsonEncode(enrichedOtherDetails)
          : null,
      isReferred: isReferred,
      referralStatus: isReferred ? 'Referred' : (referralStatus ?? 'Recovered'),
      referredReasons:
          referredReasons != null ? jsonEncode(referredReasons) : null,
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

  /// Batch sync all pending assessments via `offline-sync/create` matching Android.
  ///
  /// This is the only write path — no direct assessment/create call.
  Future<int> syncPendingAssessments() async {
    if (_isSyncing) {
      debugPrint('[AssessmentSync] Already syncing — skip');
      return 0;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final pending = await _dao.getUnsynced();
      debugPrint('[AssessmentSync] Pending count: ${pending.length}');
      if (pending.isEmpty) return 0;

      final synced = await _batchSync(pending);
      await _refreshPendingCount();
      debugPrint('[AssessmentSync] ✓ Synced $synced assessment(s). Pending now: $_pendingCount');
      return synced;
    } catch (e, st) {
      debugPrint('[AssessmentSync] ✗ Sync error: $e\n$st');
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Batch sync via offline-service/offline-sync/create matching Android.
  Future<int> _batchSync(List<LocalAssessmentEntity> assessments) async {
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

    debugPrint('[AssessmentSync] requestId: $requestId  tenantId: ${_api.tenantIdAsNum}  appType: ${AppConfig.appType}');
    debugPrint('[AssessmentSync] assessments[${assessmentPayloads.length}]:');
    for (var i = 0; i < assessmentPayloads.length; i++) {
      final a = assessmentPayloads[i];
      final assessType = a['assessmentType'] as String? ?? 'unknown';
      debugPrint('[AssessmentSync][$i] === $assessType ===');
      debugPrint('[AssessmentSync][$i] patient=${a['encounter']?['patientId']} provenance=${a['encounter']?['provenance']}');
      logChunked('[AssessmentSync][$i] details:', jsonEncode(a['assessmentDetails']));
    }

    final request = {
      'requestId': requestId,
      'tenantId': _api.tenantIdAsNum,
      'appVersionName': AppConfig.appVersionName,
      'appVersionCode': AppConfig.appVersionCode,
      'appType': AppConfig.appType,
      'syncMode': 'ManualSync',
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
      'households': <Map<String, dynamic>>[],
      'householdMembers': <Map<String, dynamic>>[],
      'assessments': assessmentPayloads,
      'followUps': <Map<String, dynamic>>[],
      'householdMemberLinks': <Map<String, dynamic>>[],
    };

    debugPrint('[AssessmentSync] POST ${Endpoints.offlineSyncCreate}');
    final response = await _api.dio.post<Map<String, dynamic>>(
      Endpoints.offlineSyncCreate,
      data: request,
    );

    final status = response.statusCode ?? 0;
    debugPrint('[AssessmentSync] Response HTTP $status — body: ${response.data}');

    if (status >= 200 && status < 300) {
      await _dao.updateSyncStatus(ids, AssessmentSyncStatus.success);
      debugPrint('[AssessmentSync] Marked ${ids.length} as success');
      return ids.length;
    } else {
      await _dao.updateSyncStatus(ids, AssessmentSyncStatus.failed);
      debugPrint('[AssessmentSync] ✗ Marked ${ids.length} as failed');
      throw StateError('Batch sync failed: HTTP $status — ${response.data}');
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
}

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
