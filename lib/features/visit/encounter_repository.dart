import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/models/assessment_history_item.dart';
import '../../core/models/programme.dart';
import '../../core/sync/offline_sync_service.dart';

/// Summary of a past visit/encounter for display.
class VisitSummary {
  const VisitSummary({
    required this.id,
    required this.date,
    required this.programme,
    this.type,
    this.status,
    this.visitNumber,
    this.isLocal = false,
    this.rawJson = const {},
  });

  final String id;
  final DateTime date;
  final Programme programme;
  final String? type;
  final String? status;
  final int? visitNumber;
  final bool isLocal;
  final Map<String, dynamic> rawJson;

  /// Build a [VisitSummary] from an offline-sync assessment-history row.
  /// This is now the authoritative server-side source for past visits —
  /// the row already carries the encounter id, visit date, and programme
  /// hint, so no further fetch is needed to render the worklist row.
  static VisitSummary fromAssessmentHistory(AssessmentHistoryItem item) {
    final typeStr = item.serviceProvided ?? 'Assessment';
    return VisitSummary(
      id: item.encounterId,
      date: item.visitDate,
      programme: Programme.fromString(typeStr),
      type: typeStr,
      status: item.referralStatus,
      rawJson: item.rawJson,
    );
  }

  static VisitSummary fromEncounterRow(EncounterRow row) {
    return VisitSummary(
      id: row.id,
      date: DateTime.fromMillisecondsSinceEpoch(row.startedAt),
      programme: Programme.fromString(row.programme),
      type: row.programme,
      status: row.status.name,
      isLocal: true,
    );
  }
}

/// Repository for visit/encounter data.
///
/// Combines local offline drafts with server-side history. The server
/// history is sourced exclusively from the offline-sync
/// `member-assessment-history` endpoint via [OfflineSyncService] —
/// the legacy spice-service `patient/member-assessment-history` route is
/// no longer called here.
class EncounterRepository extends ApiRepository {
  EncounterRepository(super.api, this._dao, {OfflineSyncService? offlineSync})
      : _offlineSync = offlineSync;

  final EncounterDao _dao;
  final OfflineSyncService? _offlineSync;
  static final _random = Random.secure();

  /// Generate a simple unique ID.
  static String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = _random.nextInt(999999).toString().padLeft(6, '0');
    return 'enc_${now}_$rand';
  }

  /// Get recent visits for a patient.
  ///
  /// Merges local drafts with the offline-sync `member-assessment-history`
  /// rows, deduplicating by encounter id. When the offline-sync service
  /// has not been wired (legacy test setups) we fall back to local-only.
  Future<List<VisitSummary>> recentEncounters(
    String patientId, {
    int limit = 10,
    String? villageId,
  }) async {
    final visits = <String, VisitSummary>{};

    // 1. Local encounters first — includes drafts the device has captured
    //    but not yet synced.
    final local = await _dao.recentForPatient(patientId, limit: limit);
    for (final row in local) {
      visits[row.id] = VisitSummary.fromEncounterRow(row);
    }

    // 2. Server history from offline-sync. The endpoint is village-scoped;
    //    pass the caller's hint when available, else the user's full set.
    final sync = _offlineSync;
    if (sync != null) {
      final scope = villageId != null
          ? (int.tryParse(villageId) != null ? [int.parse(villageId)] : null)
          : null;
      final history = await sync.fetchAssessmentHistory(villageIds: scope);
      final wantedMember = _memberHint(patientId);
      for (final row in history) {
        if (wantedMember != null &&
            row.householdMemberId != wantedMember &&
            !row.householdMemberId.endsWith('/$wantedMember')) {
          continue;
        }
        if (visits.containsKey(row.encounterId)) continue;
        visits[row.encounterId] = VisitSummary.fromAssessmentHistory(row);
      }
    } else {
      debugPrint(
          '[EncounterRepository] No OfflineSyncService wired — local only');
    }

    final result = visits.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result.take(limit).toList();
  }

  /// Server-side history rows are keyed by `householdMemberId`. When the
  /// caller already passes a numeric or FHIR-referenced id we can filter
  /// down to that member; otherwise we leave the row set unfiltered.
  String? _memberHint(String patientId) {
    if (int.tryParse(patientId) != null) return patientId;
    if (patientId.contains('/')) {
      final last = patientId.split('/').last;
      if (int.tryParse(last) != null) return last;
    }
    return null;
  }

  /// Get the most recent visit summary for "Last seen X ago" display.
  Future<VisitSummary?> lastEncounterSummary(
    String patientId, {
    String? villageId,
  }) async {
    final visits = await recentEncounters(
      patientId,
      limit: 1,
      villageId: villageId,
    );
    return visits.isEmpty ? null : visits.first;
  }

  /// Create a new visit (local draft + server POST).
  /// 
  /// Returns the local encounter ID. Server visitId is stored separately.
  Future<String> createVisit(String patientId, Programme programme) async {
    final id = _generateId();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Create local draft
    final row = EncounterRow(
      id: id,
      patientId: patientId,
      programme: programme.name,
      startedAt: now,
      status: EncounterStatus.draft,
      syncStatus: SyncStatus.pending,
    );
    await _dao.upsert(row);

    // Optimistically POST to server
    try {
      final body = await postOk(
        Endpoints.patientVisitCreate,
        data: {
          'patientId': patientId,
          'programme': programme.name,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'Create visit',
      );
      final serverVisitId = body['entity']?['id']?.toString() ??
          body['id']?.toString() ??
          body['visitId']?.toString();
      if (serverVisitId != null) {
        await _dao.updateSyncStatus(id, SyncStatus.synced,
            serverVisitId: serverVisitId);
      }
    } catch (e) {
      // Offline — keep as pending, will sync later
      // ignore: avoid_print
      print('[EncounterRepository] Visit create failed, queued offline: $e');
    }

    return id;
  }

  /// Get a local encounter by ID.
  Future<EncounterRow?> byId(String id) => _dao.byId(id);

  /// Get all in-progress encounters.
  Future<List<EncounterRow>> inProgress() => _dao.inProgress();

  /// Get pending sync encounters.
  Future<List<EncounterRow>> pendingSync() => _dao.pendingSync();

  /// Save triage data for an encounter.
  Future<void> saveTriage(String encounterId, Map<String, dynamic> triage) =>
      _dao.updateTriage(encounterId, triage);

  /// Save vitals data for an encounter.
  Future<void> saveVitals(String encounterId, Map<String, dynamic> vitals) =>
      _dao.updateVitals(encounterId, vitals);

  /// Save assessment data and complete the encounter.
  Future<void> saveAssessment(
    String encounterId,
    Map<String, dynamic> assessment,
  ) =>
      _dao.updateAssessment(encounterId, assessment);
}
