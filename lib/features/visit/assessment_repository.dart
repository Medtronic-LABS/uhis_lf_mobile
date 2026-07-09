import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart' show Endpoints;
import '../../core/auth/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/models/provance_dto.dart';
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
  /// [syncMode] mirrors Android's sync mode constants:
  ///   - `'AutomaticSync'` — triggered by connectivity-restored event
  ///   - `'ManualSync'` — triggered by the user tapping Sync
  ///   - `'InitialSync'` — first login sync (pass when bootstrapping)
  ///
  /// This is the only write path — no direct assessment/create call.
  Future<int> syncPendingAssessments({
    String syncMode = 'ManualSync',
  }) async {
    if (_isSyncing) {
      debugPrint('[AssessmentSync] Already syncing — skip');
      return 0;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final pending = await _dao.getUnsynced();
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

    debugPrint('[AssessmentSync] requestId: $requestId  tenantId: ${_api.tenantIdAsNum}  appType: ${AppConfig.appType}  syncMode: $syncMode');
    debugPrint('[AssessmentSync] assessments[${assessmentPayloads.length}]:');
    for (var i = 0; i < assessmentPayloads.length; i++) {
      final a = assessmentPayloads[i];
      final assessType = a['assessmentType'] as String? ?? 'unknown';
      debugPrint('[AssessmentSync][$i] === $assessType ===');
      debugPrint('[AssessmentSync][$i] patient=${a['encounter']?['patientId']} provenance=${a['encounter']?['provenance']}');
      logChunked('[AssessmentSync][$i] details:', jsonEncode(a['assessmentDetails']));
    }

    // Build create request matching Android's OfflineSyncRepository.getRequestObject().
    // communityProfiles and rxBuddies are included (empty arrays) so the server
    // receives the full contract shape Android sends.
    final request = {
      'requestId': requestId,
      'tenantId': _api.tenantIdAsNum,
      'appVersionName': AppConfig.appVersionName,
      'appVersionCode': AppConfig.appVersionCode,
      'appType': AppConfig.appType,
      'syncMode': syncMode,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
      'households': <Map<String, dynamic>>[],
      'householdMembers': <Map<String, dynamic>>[],
      'assessments': assessmentPayloads,
      'followUps': <Map<String, dynamic>>[],
      'householdMemberLinks': <Map<String, dynamic>>[],
      'communityProfiles': <Map<String, dynamic>>[],
      'rxBuddies': <Map<String, dynamic>>[],
    };

    debugPrint('[AssessmentSync] POST ${Endpoints.offlineSyncCreate}');
    try {
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

  /// Prior locally-saved ANC visits for [patientId] as trend snapshots,
  /// oldest-first.
  ///
  /// Used by the Step 2 vitals-trend card to plot systolic/diastolic/weight/
  /// urine-protein movement across visits.  Reads only committed rows — the
  /// current visit's live values come from the form notifier and are not yet
  /// persisted here, so no explicit exclusion is required.
  Future<List<VisitVitals>> ancVitalsHistory(String patientId) async {
    if (patientId.isEmpty) return const [];
    final rows = await _dao.getByPatientId(patientId); // created_at DESC
    final snapshots = <VisitVitals>[];
    for (final row in rows) {
      if (row.assessmentType.toUpperCase() != 'ANC') continue;
      final snap = _snapshotFromAnc(row.assessmentDetails, row.createdAt);
      if (!snap.isEmpty) snapshots.add(snap);
    }
    // Rows are newest-first; the analyzer expects oldest-first.
    return snapshots.reversed.toList();
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
    final flat = <String, dynamic>{...map};
    for (final sub in const [
      'medicalHistoryPhysicalExamination',
      'pointOfCareInvestigations',
      'dangerSignsRiskIdentification',
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
    final dia = asInt('diastolic') ?? asInt('bloodPressureDiastolic');

    final urine = flat['urinaryAlbumin'] ?? flat['urineProtein'];

    return VisitVitals(
      date: date,
      systolic: sys,
      diastolic: dia,
      weight: asDouble('weight'),
      urineProtein: urine is String ? urine : urine?.toString(),
    );
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
