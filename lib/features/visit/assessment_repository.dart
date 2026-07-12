import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart' show Endpoints;
import '../../core/auth/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/models/provance_dto.dart';
import '../patient/followup_call_service.dart';
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
  })  : _dao = dao,
        _api = api,
        _auth = auth,
        _historyDao = historyDao,
        _followUpCalls = followUpCalls;

  final LocalAssessmentDao _dao;
  final ApiClient _api;
  final AuthRepository _auth;
  // Server-synced visit history (assessments table). May be null when not
  // wired in (e.g., during unit tests where the full DB is not available).
  final AssessmentDao? _historyDao;
  // Pending follow-up call attempts ride the same offline-sync/create push.
  // Null in unit tests where the follow-up DB isn't wired.
  final FollowUpCallService? _followUpCalls;

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

    // Serialize any pending follow-up call attempts so they ride this same
    // offline-sync/create push (Android bundles follow-ups alongside
    // assessments). Defensive: a follow-up serialization failure must never
    // block the assessment push.
    var followUpPayloads = <Map<String, dynamic>>[];
    var pushedFollowUpIds = <String>[];
    if (_followUpCalls != null) {
      try {
        final result = await _followUpCalls.serializePendingForPush(
          provenance: provenance.toJson(),
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
      'followUps': followUpPayloads,
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
        // Follow-ups accepted in the same envelope → flip to InProgress
        // (awaiting server confirmation on the next pull) and mark their
        // calls synced so they are not re-pushed.
        if (pushedFollowUpIds.isNotEmpty && _followUpCalls != null) {
          try {
            await _followUpCalls.markPushed(pushedFollowUpIds);
          } catch (e) {
            debugPrint('[AssessmentSync] follow-up markPushed skipped: $e');
          }
        }
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

  /// Most-recent locally-saved weight reading for [patientId] from ANY visit
  /// type.  Returns `null` when no prior visit has a weight value.
  ///
  /// Used by the Step 2 weight-delta badge to show "Last: X kg" regardless of
  /// whether the patient's most recent visit was ANC, NCD, PNC, or any other
  /// programme.  Rows are read newest-first; the first non-null weight wins.
  Future<double?> lastRecordedWeight(String patientId) async {
    if (patientId.isEmpty) return null;
    final rows = await _dao.getByPatientId(patientId); // newest-first
    for (final row in rows) {
      final snap = _snapshotFromAnc(row.assessmentDetails, row.createdAt);
      if (snap.weight != null) return snap.weight;
    }
    return null;
  }

  /// Prior locally-saved ANC visits for [patientId] as trend snapshots,
  /// oldest-first.
  ///
  /// Used by the Step 2 vitals-trend card to plot systolic/diastolic/weight/
  /// urine-protein movement across visits.  Reads only committed rows — the
  /// current visit's live values come from the form notifier and are not yet
  /// persisted here, so no explicit exclusion is required.
  /// Returns ANC vital snapshots oldest-first from BOTH local submissions and
  /// server-synced history.  The trend card needs ≥2 data points.
  Future<List<VisitVitals>> ancVitalsHistory(String patientId) async {
    if (patientId.isEmpty) return const [];
    final snapshots = <VisitVitals>[];

    // 1. Locally-submitted assessments (pending or synced by this app).
    final localRows = await _dao.getByPatientId(patientId);
    for (final row in localRows) {
      if (row.assessmentType.toUpperCase() != 'ANC') continue;
      final snap = _snapshotFromAnc(row.assessmentDetails, row.createdAt);
      if (!snap.isEmpty) snapshots.add(snap);
    }

    // 2. Server-synced assessment history stored during offline sync.
    if (_historyDao != null) {
      final historyMap = await _historyDao.forMany([patientId]);
      final historyRows = historyMap[patientId] ?? const [];
      debugPrint('[AssessmentRepo] ANC history lookup: ${historyRows.length} rows '
          'for patient $patientId');
      for (final row in historyRows) {
        final kind = row.kind?.toUpperCase() ?? '';
        debugPrint('[AssessmentRepo] history row kind="$kind" id=${row.id}');
        if (!_isAncKind(kind)) continue;
        final snap = _snapshotFromServerRaw(row.rawJson, row.occurredAt);
        debugPrint('[AssessmentRepo] history snap: sys=${snap.systolic} dia=${snap.diastolic} '
            'wt=${snap.weight} urine=${snap.urineProtein}');
        if (!snap.isEmpty) snapshots.add(snap);
      }
    }

    // Sort oldest-first so VitalsTrendAnalyzer sees the correct sequence.
    snapshots.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return a.date!.compareTo(b.date!);
    });
    debugPrint('[AssessmentRepo] ancVitalsHistory: ${snapshots.length} snapshots '
        'for patient $patientId');
    return snapshots;
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

  /// Extracts LMP from a server assessment row's rawJson, trying several key
  /// locations the backend may use.  Returns null when nothing recognisable
  /// is found; falls back to deriving a synthetic LMP from gestational weeks.
  static DateTime? _extractLmpFromRaw(String rawJson) {
    try {
      final raw = jsonDecode(rawJson) as Map<String, dynamic>;
      // Flatten sub-objects that may carry the LMP key.
      // Server uses different wrappers for ANC vs PWPROFILE assessment types.
      final flat = <String, dynamic>{...raw};
      for (final sub in const [
        'observations',
        'assessmentDetails',
        'medicalHistoryPhysicalExamination',
        'pointOfCareInvestigations',
        'medicalHistory',
        'pregnancyDetails',
        'pwProfile',
        'clinicalDetails',
        'pregnancyProfile',
        'obstetricHistory',
      ]) {
        if (raw[sub] is Map) {
          flat.addAll((raw[sub] as Map).cast<String, dynamic>());
        }
      }

      // Try ISO date strings under common LMP field names.
      for (final key in const [
        'lmpDate',
        'lastMenstrualPeriod',
        'lastMenstrualPeriodDate',
        'lmp',
        'lmpValue',
        'menstrualDate',
        'lastPeriodDate',
      ]) {
        final v = flat[key];
        if (v is String && v.isNotEmpty) {
          final d = DateTime.tryParse(v);
          if (d != null) return d;
        }
        // Some backends send epoch millis.
        if (v is num && v > 1_000_000_000) {
          return DateTime.fromMillisecondsSinceEpoch(v.toInt());
        }
      }

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
