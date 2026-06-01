import 'dart:math';

import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/models/programme.dart';

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

  static VisitSummary? fromAssessmentJson(Map<String, dynamic> json) {
    final id = json['encounterId']?.toString() ?? json['id']?.toString();
    if (id == null) return null;

    DateTime? date;
    final dateStr = json['visitDate'] ??
        json['createdAt'] ??
        json['startTime'] ??
        json['date'];
    if (dateStr is String) {
      date = DateTime.tryParse(dateStr);
    } else if (dateStr is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateStr);
    }
    date ??= DateTime.now();

    final typeStr = json['serviceProvided']?.toString() ??
        json['assessmentName']?.toString() ??
        json['type']?.toString() ??
        'Assessment';
    
    final programme = Programme.fromString(typeStr);

    return VisitSummary(
      id: id,
      date: date,
      programme: programme,
      type: typeStr,
      status: json['referralStatus']?.toString() ?? json['status']?.toString(),
      visitNumber: json['visitNumber'] is int ? json['visitNumber'] : null,
      rawJson: json,
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
/// Combines local offline storage with server API calls.
class EncounterRepository extends ApiRepository {
  EncounterRepository(super.api, this._dao);

  final EncounterDao _dao;
  static final _random = Random.secure();

  /// Generate a simple unique ID.
  static String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = _random.nextInt(999999).toString().padLeft(6, '0');
    return 'enc_${now}_$rand';
  }

  /// Get recent visits for a patient.
  /// 
  /// Merges local drafts with server history, deduplicating by ID.
  Future<List<VisitSummary>> recentEncounters(
    String patientId, {
    int limit = 10,
    String? villageId,
  }) async {
    final visits = <String, VisitSummary>{};

    // 1. Get local encounters first (includes drafts)
    final local = await _dao.recentForPatient(patientId, limit: limit);
    for (final row in local) {
      visits[row.id] = VisitSummary.fromEncounterRow(row);
    }

    // 2. Fetch from server (assessment history)
    try {
      final body = await postOk(
        Endpoints.patientMemberAssessmentHistory,
        data: {
          'patientId': patientId,
          if (villageId != null) 'villageIds': [int.tryParse(villageId)],
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        },
        action: 'Recent encounters',
      );
      final list = extractList(body);
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final summary = VisitSummary.fromAssessmentJson(item);
          if (summary != null && !visits.containsKey(summary.id)) {
            visits[summary.id] = summary;
          }
        }
      }
    } catch (e) {
      // Offline or error — local data only
      // ignore: avoid_print
      print('[EncounterRepository] Server fetch failed: $e');
    }

    // 3. Sort by date descending and limit
    final result = visits.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result.take(limit).toList();
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
