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
///
/// Phase 1: Supports caller-supplied encounterId for unified assessments.
/// Multiple programme assessments from the same visit share one encounterId.
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
    int? followUpId,
    double latitude = 0.0,
    double longitude = 0.0,
    Map<String, dynamic>? otherDetails,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    // Include encounterId in otherDetails for persistence and API request
    final enrichedOtherDetails = <String, dynamic>{
      ...?otherDetails,
      if (encounterId != null) 'encounterId': encounterId,
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
    _attemptImmediateSync(entity, encounterId: encounterId);

    return id;
  }

  /// Attempt to sync a single assessment immediately.
  Future<void> _attemptImmediateSync(
    LocalAssessmentEntity entity, {
    String? encounterId,
  }) async {
    try {
      // Check connectivity by making a lightweight request
      final result = await _syncSingleAssessment(entity, encounterId: encounterId);
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
  Future<bool> _syncSingleAssessment(
    LocalAssessmentEntity entity, {
    String? encounterId,
  }) async {
    try {
      // Mark as in-progress
      await _dao.updateSyncStatus([entity.id], AssessmentSyncStatus.inProgress);

      final type = entity.assessmentType.toUpperCase();
      final details = jsonDecode(entity.assessmentDetails);

      // Extract encounterId from otherDetails if not provided
      String? effectiveEncounterId = encounterId;
      if (effectiveEncounterId == null && entity.otherDetails != null) {
        try {
          final other = jsonDecode(entity.otherDetails!);
          effectiveEncounterId = other['encounterId'] as String?;
        } catch (_) {}
      }

      // Route to appropriate endpoint based on assessment type
      String endpoint;
      Map<String, dynamic> requestBody;

      if (type == 'NCD') {
        // NCD uses /assessment/create or separate BP/Glucose endpoints
        endpoint = Endpoints.assessmentCreate;
        requestBody = _buildNcdRequest(entity, details, encounterId: effectiveEncounterId);
      } else {
        // Other types (TB, ANC, ICCM) use the generic create endpoint
        endpoint = Endpoints.assessmentCreate;
        requestBody = _buildApiRequest(entity, encounterId: effectiveEncounterId);
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
    Map<String, dynamic> details, {
    String? encounterId,
  }) {
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
        if (encounterId != null) 'encounterId': encounterId,
      },
      'assessmentTakenOn': entity.createdAt?.toUtc().toIso8601String(),
    };
  }

  /// Build generic API request body with optional encounterId.
  Map<String, dynamic> _buildApiRequest(
    LocalAssessmentEntity entity, {
    String? encounterId,
  }) {
    final details = jsonDecode(entity.assessmentDetails);
    return {
      'referenceId': entity.householdMemberLocalId,
      'assessmentType': entity.assessmentType.toUpperCase(),
      'assessmentDetails': details,
      'villageId': entity.villageId,
      'assessmentDate': entity.createdAt?.toUtc().toIso8601String(),
      'patientStatus': entity.referralStatus ?? 'Recovered',
      if (entity.referredReasons != null)
        'referredReasons': entity.referredReasons,
      if (entity.otherDetails != null)
        'summary': jsonDecode(entity.otherDetails!),
      'encounter': {
        'householdId': entity.householdId,
        'memberId': entity.memberId,
        'referred': entity.isReferred,
        'patientId': entity.patientId,
        'latitude': entity.latitude,
        'longitude': entity.longitude,
        'startTime': entity.createdAt?.toUtc().toIso8601String(),
        'endTime': entity.updatedAt?.toUtc().toIso8601String(),
        if (encounterId != null) 'encounterId': encounterId,
      },
      if (entity.followUpId != null) 'followUpId': entity.followUpId,
      'updatedAt': entity.updatedAt?.millisecondsSinceEpoch ?? 0,
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
