import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../auth/auth_repository.dart';
import '../db/assessment_dao.dart';
import '../db/follow_up_dao.dart';
import '../db/immunisation_dao.dart';
import '../db/patient_dao.dart';
import '../db/patient_programmes_dao.dart';
import '../db/sync_meta_dao.dart';
import '../models/json_read.dart';
import '../models/patient.dart';
import '../models/programme.dart';
import 'sync_report.dart';

/// Pulls worklist input data from the UHIS platform services into the local
/// SQLite cache. Risk *scoring* is a separate concern handled by
/// `RiskScoringService` / `WorklistRepository.recomputeAllAfterSync`.
///
/// Authoritative bulk path: `POST /offline-sync/fetch-synced-data` —
/// a GZIP'd JSON bundle keyed by entity. Per-endpoint spice calls remain
/// available via [refreshPatient] for gap-fills.
class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService({
    required ApiClient api,
    required AuthRepository auth,
    required PatientDao patients,
    required PatientProgrammesDao programmes,
    required FollowUpDao followUps,
    required ImmunisationDao immunisations,
    required AssessmentDao assessments,
    required SyncMetaDao syncMeta,
  })  : _api = api,
        _auth = auth,
        _patients = patients,
        _programmes = programmes,
        _followUps = followUps,
        _immunisations = immunisations,
        _assessments = assessments,
        _syncMeta = syncMeta;

  static const String _entityKey = 'worklist';

  final ApiClient _api;
  final AuthRepository _auth;
  final PatientDao _patients;
  final PatientProgrammesDao _programmes;
  final FollowUpDao _followUps;
  final ImmunisationDao _immunisations;
  final AssessmentDao _assessments;
  final SyncMetaDao _syncMeta;

  bool _running = false;

  /// True when a sync is currently in flight — `WorklistView` consumes this to
  /// disable manual refresh.
  bool get isRunning => _running;

  Future<DateTime?> lastSyncedAt() async {
    final row = await _syncMeta.read(_entityKey);
    final t = row?.lastSyncTime;
    return t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
  }

  /// First sync after login — full pull, no `lastSyncTime` filter.
  Future<SyncReport> coldSync() => _runSync(fullSync: true);

  /// Pull-to-refresh — delta filter using the cached `lastSyncTime`.
  Future<SyncReport> warmSync() => _runSync(fullSync: false);

  Future<SyncReport> _runSync({required bool fullSync}) async {
    if (_running) {
      return SyncReport.empty().copyWith(
        errors: const ['Sync already running'],
      );
    }
    _running = true;
    notifyListeners();
    final started = DateTime.now();
    var report = SyncReport(startedAt: started, finishedAt: started)
        .copyWith(wasFullSync: fullSync);
    try {
      final villageIds = await _auth.subVillageIds();
      if (villageIds.isEmpty) {
        return report.copyWith(
          finishedAt: DateTime.now(),
          errors: const [
            'No villages assigned to this SK — nothing to sync',
          ],
        );
      }

      DateTime? since;
      if (!fullSync) {
        final last = await _syncMeta.read(_entityKey);
        if (last?.lastSyncTime != null) {
          since = DateTime.fromMillisecondsSinceEpoch(last!.lastSyncTime!);
        }
      }

      Map<String, dynamic>? bundle;
      try {
        bundle = await _fetchBundle(villageIds: villageIds, since: since);
      } catch (e) {
        // Aggregate endpoint failed — fall back to granular spice calls so
        // the worklist still moves forward on a flaky cell connection.
        return await _fallbackGranularSync(
          villageIds: villageIds,
          fullSync: fullSync,
          started: started,
          aggregateError: e.toString(),
        );
      }

      final out = await _persistBundle(bundle);
      report = report.copyWith(
        finishedAt: DateTime.now(),
        patients: out.patients,
        followUps: out.followUps,
        immunisations: out.immunisations,
        assessments: out.assessments,
      );

      if (fullSync) {
        await _syncMeta.stampFull(_entityKey, report.finishedAt);
      } else {
        await _syncMeta.stampWarm(_entityKey, report.finishedAt);
      }
      return report;
    } catch (e) {
      return report.copyWith(
        finishedAt: DateTime.now(),
        errors: ['Sync failed: $e'],
      );
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _fetchBundle({
    required List<int> villageIds,
    DateTime? since,
  }) async {
    final body = <String, dynamic>{
      'villageIds': villageIds,
      'tenantId': _api.tenantIdAsNum,
      if (since != null)
        'lastSyncTime': since.millisecondsSinceEpoch,
      'currentSyncTime': DateTime.now().millisecondsSinceEpoch,
    };
    final resp = await _api.dio.post<List<int>>(
      Endpoints.offlineSyncFetch,
      data: body,
      options: Options(responseType: ResponseType.bytes),
    );
    final status = resp.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw StateError('offline-sync HTTP $status');
    }
    final bytes = resp.data;
    if (bytes == null || bytes.isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = _maybeDecompress(Uint8List.fromList(bytes));
    final text = utf8.decode(decoded);
    if (text.isEmpty) return const <String, dynamic>{};
    final parsed = jsonDecode(text);
    if (parsed is Map<String, dynamic>) return parsed;
    if (parsed is Map) return Map<String, dynamic>.from(parsed);
    return const <String, dynamic>{};
  }

  static Uint8List _maybeDecompress(Uint8List raw) {
    // GZIP magic bytes 1F 8B. Server may also return plain JSON when the
    // payload is small enough.
    if (raw.length >= 2 && raw[0] == 0x1F && raw[1] == 0x8B) {
      return Uint8List.fromList(GZipCodec().decode(raw));
    }
    return raw;
  }

  Future<_PersistTotals> _persistBundle(Map<String, dynamic> bundle) async {
    if (bundle.isEmpty) return const _PersistTotals();

    // Bundle key names vary across spice / offline-service versions. Accept a
    // small set of synonyms and treat any list-typed entry under those keys
    // as the entity list.
    final patientNodes = _listFromAny(bundle, const [
      'patients',
      'patientList',
      'patientDetails',
    ]);
    final followUpNodes = _listFromAny(bundle, const [
      'followUps',
      'follow_ups',
      'followUpList',
    ]);
    final immunisationNodes = _listFromAny(bundle, const [
      'immunisations',
      'immunizations',
      'immunisationList',
    ]);
    final assessmentNodes = _listFromAny(bundle, const [
      'assessments',
      'assessmentList',
      'assessmentHistory',
    ]);

    final patients = <Patient>[];
    final programmes = <String, Set<Programme>>{};
    for (final raw in patientNodes) {
      if (raw is! Map) continue;
      final p = Patient.fromApiJson(raw);
      if (p == null) continue;
      patients.add(p);
      programmes[p.id] = _extractProgrammes(raw);
    }

    final followUps = <FollowUpRow>[];
    for (final raw in followUpNodes) {
      if (raw is! Map) continue;
      final row = _followUpRowFrom(raw);
      if (row != null) followUps.add(row);
    }

    final immunisations = <ImmunisationRow>[];
    for (final raw in immunisationNodes) {
      if (raw is! Map) continue;
      final row = _immunisationRowFrom(raw);
      if (row != null) immunisations.add(row);
    }

    final assessments = <AssessmentRow>[];
    for (final raw in assessmentNodes) {
      if (raw is! Map) continue;
      final row = _assessmentRowFrom(raw);
      if (row != null) assessments.add(row);
    }

    await _patients.upsertMany(patients);
    for (final entry in programmes.entries) {
      await _programmes.replaceFor(entry.key, entry.value);
    }
    await _followUps.upsertMany(followUps);
    await _immunisations.upsertMany(immunisations);
    await _assessments.upsertMany(assessments);

    return _PersistTotals(
      patients: patients.length,
      followUps: followUps.length,
      immunisations: immunisations.length,
      assessments: assessments.length,
    );
  }

  static List _listFromAny(Map bundle, List<String> keys) {
    for (final k in keys) {
      final v = bundle[k];
      if (v is List) return v;
      if (v is Map) {
        if (v['entityList'] is List) return v['entityList'] as List;
        if (v['data'] is List) return v['data'] as List;
      }
    }
    return const [];
  }

  static Set<Programme> _extractProgrammes(Map raw) {
    final out = <Programme>{};
    final diag = raw['diagnosisType'];
    if (diag is List) {
      for (final d in diag) {
        final p = Programme.fromTag(d?.toString());
        if (p != null) out.add(p);
      }
    }
    // Common enrolment markers — server fields vary across versions.
    if (_truthy(raw['isPregnant']) || _truthy(raw['isAncEnrolled'])) {
      out.add(Programme.anc);
    }
    if (_truthy(raw['isNcdEnrolled']) || _truthy(raw['isDiabetic']) ||
        _truthy(raw['isHypertensive'])) {
      out.add(Programme.ncd);
    }
    if (_truthy(raw['isTbEnrolled']) ||
        _truthy(raw['presumptiveTb']) ||
        raw['presumptiveTbNo'] != null) {
      out.add(Programme.tb);
    }
    final age = JsonRead.firstInt(raw, const ['age']);
    if (age != null && age < 5) out.add(Programme.imci);
    return out;
  }

  static bool _truthy(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == 'yes' || s == 'y' || s == '1';
  }

  FollowUpRow? _followUpRowFrom(Map raw) {
    final id = JsonRead.firstString(raw, const ['id', 'fhirId', 'uuid']);
    if (id == null) return null;
    final patientId = JsonRead.firstString(raw, const [
      'patientId',
      'memberId',
      'householdMemberId',
      'patientReference',
    ]);
    if (patientId == null) return null;
    final kind = JsonRead.firstString(raw, const ['type', 'followUpType']);
    final dueAt = JsonRead.epochMillis(raw, const [
      'dueDate',
      'nextVisitDate',
      'visitDate',
    ]);
    final completedAt =
        JsonRead.epochMillis(raw, const ['completedAt', 'visitDate']);
    final attempts = JsonRead.firstInt(raw, const ['attempts', 'visits']);
    final isLost = _truthy(raw['isLostToFollowUp']) ||
        _truthy(raw['lostToFollowUp']) ||
        (kind != null && kind.toLowerCase().contains('lost'));
    return FollowUpRow(
      id: id,
      patientId: patientId,
      kind: _normaliseFollowUpKind(kind),
      dueAt: dueAt,
      completedAt: completedAt,
      attempts: attempts,
      isLost: isLost,
      rawJson: JsonRead.encode(raw),
    );
  }

  static String _normaliseFollowUpKind(String? wire) {
    if (wire == null) return FollowUpKind.generic;
    final w = wire.toLowerCase();
    if (w.contains('ncd')) return FollowUpKind.ncd;
    if (w.contains('screening')) return FollowUpKind.screening;
    if (w.contains('medical')) return FollowUpKind.medicalReview;
    if (w.contains('assessment')) return FollowUpKind.assessment;
    if (w.contains('lost')) return FollowUpKind.lost;
    return FollowUpKind.generic;
  }

  ImmunisationRow? _immunisationRowFrom(Map raw) {
    final id = JsonRead.firstString(raw, const ['id', 'uuid', 'fhirId']);
    if (id == null) return null;
    final patientId =
        JsonRead.firstString(raw, const ['patientId', 'memberId']);
    if (patientId == null) return null;
    return ImmunisationRow(
      id: id,
      patientId: patientId,
      vaccineCode: JsonRead.firstString(
          raw, const ['vaccineCode', 'vaccine', 'antigen']),
      dueAt: JsonRead.epochMillis(raw, const ['dueDate', 'scheduledAt']),
      givenAt: JsonRead.epochMillis(raw, const ['givenAt', 'administeredAt']),
      rawJson: JsonRead.encode(raw),
    );
  }

  AssessmentRow? _assessmentRowFrom(Map raw) {
    final id = JsonRead.firstString(raw, const ['id', 'uuid', 'fhirId']);
    if (id == null) return null;
    final patientId = JsonRead.firstString(raw, const [
      'patientId',
      'memberId',
      'householdMemberId',
    ]);
    if (patientId == null) return null;
    return AssessmentRow(
      id: id,
      patientId: patientId,
      kind: JsonRead.firstString(
          raw, const ['type', 'assessmentType', 'kind']),
      occurredAt: JsonRead.epochMillis(
          raw, const ['occurredAt', 'date', 'assessmentDate']),
      rawJson: JsonRead.encode(raw),
    );
  }

  Future<SyncReport> _fallbackGranularSync({
    required List<int> villageIds,
    required bool fullSync,
    required DateTime started,
    required String aggregateError,
  }) async {
    final patientNodes = await _fetchPatientList(villageIds);
    if (patientNodes.isEmpty) {
      return SyncReport(
        startedAt: started,
        finishedAt: DateTime.now(),
        wasFullSync: fullSync,
        errors: [
          'Aggregate sync failed ($aggregateError); patient list empty too',
        ],
      );
    }
    final patients = <Patient>[];
    final programmes = <String, Set<Programme>>{};
    for (final raw in patientNodes) {
      if (raw is! Map) continue;
      final p = Patient.fromApiJson(raw);
      if (p == null) continue;
      patients.add(p);
      programmes[p.id] = _extractProgrammes(raw);
    }
    await _patients.upsertMany(patients);
    for (final entry in programmes.entries) {
      await _programmes.replaceFor(entry.key, entry.value);
    }
    final report = SyncReport(
      startedAt: started,
      finishedAt: DateTime.now(),
      patients: patients.length,
      wasFullSync: fullSync,
      errors: [
        'Aggregate sync degraded — used per-patient fallback ($aggregateError)',
      ],
    );
    if (fullSync) {
      await _syncMeta.stampFull(_entityKey, report.finishedAt);
    } else {
      await _syncMeta.stampWarm(_entityKey, report.finishedAt);
    }
    return report;
  }

  Future<List> _fetchPatientList(List<int> villageIds) async {
    // fhir-mapper `getPatientDetailsByVillageIds` calls `setTime` on the
    // `currentSyncTime` field — the request fails with HTTP 500
    // "date must not be null" if we don't include it.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final body = <String, dynamic>{
      'villageIds': villageIds,
      'skip': 0,
      'limit': 1000,
      'tenantId': _api.tenantIdAsNum,
      'currentSyncTime': nowMs,
    };
    try {
      final resp =
          await _api.dio.post(Endpoints.patientOfflineList, data: body);
      return _extractList(resp.data);
    } catch (_) {
      // Try the non-offline endpoint as a second fallback.
      try {
        final resp = await _api.dio.post(Endpoints.patientList, data: body);
        return _extractList(resp.data);
      } catch (_) {
        return const [];
      }
    }
  }

  static List _extractList(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      if (body['entityList'] is List) return body['entityList'] as List;
      if (body['data'] is List) return body['data'] as List;
    }
    return const [];
  }

  /// Per-patient refresh — fan-out to the granular spice endpoints. Tolerates
  /// per-endpoint failures so partial refresh still wins over stale data.
  Future<void> refreshPatient(String patientId) async {
    final body = {
      'patientId': patientId,
      'tenantId': _api.tenantIdAsNum,
      'currentSyncTime': DateTime.now().millisecondsSinceEpoch,
    };
    Future<Map?> tryGet(String path) async {
      try {
        final resp = await _api.dio.post(path, data: body);
        final data = resp.data;
        if (data is Map) return data;
      } catch (_) {/* tolerate */}
      return null;
    }

    final detail = await tryGet(Endpoints.patientDetails);
    if (detail != null) {
      final p = Patient.fromApiJson(detail);
      if (p != null) {
        await _patients.upsertMany([p]);
        await _programmes.replaceFor(p.id, _extractProgrammes(detail));
      }
    }
    final immun = await tryGet(Endpoints.immunisationList);
    if (immun != null) {
      final list = _extractList(immun);
      final rows = <ImmunisationRow>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final row = _immunisationRowFrom(raw);
        if (row != null) rows.add(row);
      }
      await _immunisations.upsertMany(rows);
    }
    final follow = await tryGet(Endpoints.followUpList);
    if (follow != null) {
      final list = _extractList(follow);
      final rows = <FollowUpRow>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final row = _followUpRowFrom(raw);
        if (row != null) rows.add(row);
      }
      await _followUps.upsertMany(rows);
    }
  }
}

class _PersistTotals {
  const _PersistTotals({
    this.patients = 0,
    this.followUps = 0,
    this.immunisations = 0,
    this.assessments = 0,
  });

  final int patients;
  final int followUps;
  final int immunisations;
  final int assessments;
}

