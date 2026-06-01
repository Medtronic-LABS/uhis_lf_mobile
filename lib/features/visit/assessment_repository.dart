import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/db/local_assessment_dao.dart';

/// Repository for offline-first assessment management.
///
/// Follows Android spice-2.0 pattern:
/// 1. Save to local DB with sync_status = pending
/// 2. Attempt immediate sync if online
/// 3. Batch sync via offline-service when connectivity returns
class AssessmentRepository extends ChangeNotifier {
  AssessmentRepository({
    required LocalAssessmentDao dao,
    required ApiClient api,
  })  : _dao = dao,
        _api = api;

  final LocalAssessmentDao _dao;
  final ApiClient _api;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  /// Save assessment locally and attempt sync.
  ///
  /// Returns the local assessment ID for tracking.
  Future<String> saveAssessment({
    required String assessmentType,
    required Map<String, dynamic> assessmentDetails,
    required int householdMemberLocalId,
    String? memberId,
    String? householdId,
    String? patientId,
    String? villageId,
    bool isReferred = false,
    String? referralStatus,
    List<String>? referredReasons,
    int? followUpId,
    double latitude = 0.0,
    double longitude = 0.0,
    Map<String, dynamic>? otherDetails,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final entity = LocalAssessmentEntity(
      id: id,
      householdMemberLocalId: householdMemberLocalId,
      memberId: memberId,
      householdId: householdId,
      patientId: patientId,
      villageId: villageId,
      assessmentType: assessmentType.toUpperCase(),
      assessmentDetails: jsonEncode(assessmentDetails),
      otherDetails: otherDetails != null ? jsonEncode(otherDetails) : null,
      isReferred: isReferred,
      referralStatus: isReferred ? 'Referred' : (referralStatus ?? 'Recovered'),
      referredReasons:
          referredReasons != null ? jsonEncode(referredReasons) : null,
      followUpId: followUpId,
      latitude: latitude,
      longitude: longitude,
      syncStatus: AssessmentSyncStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    // Save locally first (offline-first)
    await _dao.insert(entity);
    await _refreshPendingCount();

    // Attempt immediate sync
    _attemptImmediateSync(entity);

    return id;
  }

  /// Attempt to sync a single assessment immediately.
  Future<void> _attemptImmediateSync(LocalAssessmentEntity entity) async {
    try {
      // Check connectivity by making a lightweight request
      final result = await _syncSingleAssessment(entity);
      if (result) {
        await _refreshPendingCount();
        notifyListeners();
      }
    } catch (e) {
      // Network error - assessment stays pending for batch sync
      debugPrint('Immediate sync failed, will batch sync: $e');
    }
  }

  /// Sync a single assessment to the API.
  ///
  /// Returns true if successful.
  Future<bool> _syncSingleAssessment(LocalAssessmentEntity entity) async {
    try {
      // Mark as in-progress
      await _dao.updateSyncStatus([entity.id], AssessmentSyncStatus.inProgress);

      final type = entity.assessmentType.toUpperCase();
      final details = jsonDecode(entity.assessmentDetails);

      // Route to appropriate endpoint based on assessment type
      String endpoint;
      Map<String, dynamic> requestBody;

      if (type == 'NCD') {
        // NCD uses /assessment/create or separate BP/Glucose endpoints
        endpoint = Endpoints.assessmentCreate;
        requestBody = _buildNcdRequest(entity, details);
      } else {
        // Other types (TB, ANC, ICCM) use the generic create endpoint
        endpoint = Endpoints.assessmentCreate;
        requestBody = entity.toApiRequest();
      }

      final response = await _api.dio.post<Map<String, dynamic>>(
        endpoint,
        data: requestBody,
      );

      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        // Extract FHIR ID from response
        final data = response.data;
        final fhirId = data?['id']?.toString() ??
            data?['fhirId']?.toString() ??
            data?['assessmentId']?.toString();

        if (fhirId != null) {
          await _dao.updateFhirId(entity.id, fhirId);
        } else {
          await _dao.updateSyncStatus(
              [entity.id], AssessmentSyncStatus.success);
        }
        return true;
      } else {
        await _dao.updateSyncStatus([entity.id], AssessmentSyncStatus.failed);
        return false;
      }
    } catch (e) {
      await _dao.updateSyncStatus(
          [entity.id], AssessmentSyncStatus.networkError);
      rethrow;
    }
  }

  /// Build NCD-specific request body.
  Map<String, dynamic> _buildNcdRequest(
    LocalAssessmentEntity entity,
    Map<String, dynamic> details,
  ) {
    return {
      'assessmentType': 'NCD',
      'patientId': entity.patientId,
      'memberId': entity.memberId,
      'villageId': entity.villageId,
      if (details['bpLog'] != null) 'bpLog': details['bpLog'],
      if (details['glucoseLog'] != null) 'glucoseLog': details['glucoseLog'],
      if (details['cvdRiskLevel'] != null)
        'cvdRiskLevel': details['cvdRiskLevel'],
      if (details['cvdRiskScore'] != null)
        'cvdRiskScore': details['cvdRiskScore'],
      if (details['riskLevel'] != null) 'riskLevel': details['riskLevel'],
      'encounter': {
        'householdId': entity.householdId,
        'memberId': entity.memberId,
        'patientId': entity.patientId,
        'referred': entity.isReferred,
        'latitude': entity.latitude,
        'longitude': entity.longitude,
        'startTime': entity.createdAt?.toUtc().toIso8601String(),
        'endTime': entity.updatedAt?.toUtc().toIso8601String(),
      },
      'assessmentTakenOn': entity.createdAt?.toUtc().toIso8601String(),
    };
  }

  /// Batch sync all pending assessments.
  ///
  /// Used by OfflineSyncService during scheduled sync.
  Future<int> syncPendingAssessments() async {
    if (_isSyncing) return 0;

    _isSyncing = true;
    notifyListeners();

    try {
      final pending = await _dao.getUnsynced();
      if (pending.isEmpty) return 0;

      int synced = 0;

      // Try batch sync via offline-service first
      try {
        synced = await _batchSync(pending);
      } catch (e) {
        // Fall back to individual sync
        debugPrint('Batch sync failed, trying individual: $e');
        for (final entity in pending) {
          try {
            if (await _syncSingleAssessment(entity)) {
              synced++;
            }
          } catch (_) {
            // Continue with next
          }
        }
      }

      await _refreshPendingCount();
      return synced;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Batch sync via offline-service/offline-sync/create.
  Future<int> _batchSync(List<LocalAssessmentEntity> assessments) async {
    final ids = assessments.map((e) => e.id).toList();

    // Mark as in-progress
    await _dao.updateSyncStatus(ids, AssessmentSyncStatus.inProgress);

    // Build batch request matching Android's format
    final requestId = const Uuid().v4();
    final request = {
      'requestId': requestId,
      'tenantId': _api.tenantIdAsNum,
      'households': <Map<String, dynamic>>[],
      'householdMembers': <Map<String, dynamic>>[],
      'assessments': assessments.map((e) => e.toApiRequest()).toList(),
      'followups': <Map<String, dynamic>>[],
      'householdMemberLink': <Map<String, dynamic>>[],
    };

    final response = await _api.dio.post<Map<String, dynamic>>(
      Endpoints.offlineSyncCreate,
      data: request,
    );

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      // Poll for sync status or mark as success
      await _dao.updateSyncStatus(ids, AssessmentSyncStatus.success);
      return ids.length;
    } else {
      await _dao.updateSyncStatus(ids, AssessmentSyncStatus.failed);
      throw StateError('Batch sync failed: HTTP $status');
    }
  }

  /// Refresh pending count.
  Future<void> _refreshPendingCount() async {
    _pendingCount = await _dao.getUnsyncedCount();
    notifyListeners();
  }

  /// Get pending count (call to refresh).
  Future<int> getPendingCount() async {
    await _refreshPendingCount();
    return _pendingCount;
  }

  /// Get all assessments for a patient.
  Future<List<LocalAssessmentEntity>> getAssessmentsForPatient(
      String patientId) async {
    return _dao.getByPatientId(patientId);
  }

  /// Get assessment by local ID.
  Future<LocalAssessmentEntity?> getAssessmentById(String id) async {
    return _dao.getById(id);
  }
}

/// Result of saving an assessment.
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
