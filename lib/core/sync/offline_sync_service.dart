import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../debug/console_log.dart';
import '../api/endpoints.dart';
import '../auth/auth_repository.dart';
import '../auth/user_hierarchy_service.dart';
import '../config/app_config.dart';
import '../models/assessment_history_item.dart';
import '../db/app_database.dart';
import '../db/assessment_dao.dart';
import '../db/encounter_dao.dart';
import '../db/follow_up_dao.dart';
import '../db/household_dao.dart';
import '../db/immunisation_dao.dart';
import '../db/member_dao.dart';
import '../db/patient_dao.dart';
import '../db/patient_programmes_dao.dart';
import '../db/pregnancy_snapshot_dao.dart';
import '../db/sync_meta_dao.dart';
import '../db/treatment_presence_dao.dart';
import '../mission/mission_pregnancy_facts.dart';
import '../models/json_read.dart';
import '../models/patient.dart';
import '../models/programme.dart';
import 'sync_progress.dart';
import 'sync_report.dart';

/// Pulls worklist input data from the UHIS platform services into the local
/// SQLite cache. Risk *scoring* is a separate concern handled by
/// `RiskScoringService` / `WorklistRepository.recomputeAllAfterSync`.
///
/// Authoritative bulk path: `POST /offline-sync/fetch-synced-data` —
/// a GZIP'd JSON bundle keyed by entity.
class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService({
    required ApiClient api,
    required AuthRepository auth,
    required AppDatabase db,
    required PatientDao patients,
    required PatientProgrammesDao programmes,
    required FollowUpDao followUps,
    required ImmunisationDao immunisations,
    required AssessmentDao assessments,
    required SyncMetaDao syncMeta,
    HouseholdDao? households,
    MemberDao? members,
    PregnancySnapshotDao? pregnancySnapshot,
    TreatmentPresenceDao? treatmentPresence,
    EncounterDao? encounterDao,
    // P1: injected so OfflineSyncService can reuse already-fetched static-data
    // instead of making a second user-data HTTP call on every full sync.
    UserHierarchyService? hierarchy,
  })  : _api = api,
        _auth = auth,
        _db = db,
        _patients = patients,
        _programmes = programmes,
        _followUps = followUps,
        _immunisations = immunisations,
        _assessments = assessments,
        _syncMeta = syncMeta,
        _households = households,
        _members = members,
        _pregnancySnapshot = pregnancySnapshot,
        _treatmentPresence = treatmentPresence,
        _encounterDao = encounterDao,
        _hierarchy = hierarchy;

  static const String _entityKey = 'worklist';

  final ApiClient _api;
  final AuthRepository _auth;
  final AppDatabase _db;
  final PatientDao _patients;
  final PatientProgrammesDao _programmes;
  final FollowUpDao _followUps;
  final HouseholdDao? _households;
  final MemberDao? _members;
  final ImmunisationDao _immunisations;
  final AssessmentDao _assessments;
  final SyncMetaDao _syncMeta;
  final PregnancySnapshotDao? _pregnancySnapshot;
  final TreatmentPresenceDao? _treatmentPresence;
  final EncounterDao? _encounterDao;
  // P1: shared hierarchy service — avoids second user-data call on full sync
  final UserHierarchyService? _hierarchy;

  bool _running = false;

  /// Stream controller for sync progress updates.
  final _progressController = StreamController<SyncProgress>.broadcast();

  /// Stream of sync progress updates for UI consumption.
  Stream<SyncProgress> get progressStream => _progressController.stream;

  /// Current progress state.
  SyncProgress _progress = SyncProgress.initial;
  SyncProgress get progress => _progress;

  void _emitProgress(SyncProgress p) {
    _progress = p;
    _progressController.add(p);
    notifyListeners();
  }

  /// True when a sync is currently in flight — `WorklistView` consumes this to
  /// disable manual refresh.
  bool get isRunning => _running;

  Future<DateTime?> lastSyncedAt() async {
    final row = await _syncMeta.read(_entityKey);
    final t = row?.lastSyncTime;
    return t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
  }

  /// First sync after login — full pull, no `lastSyncTime` filter.
  ///
  /// [wipeBeforeSync] truncates every local table before the pull — set only
  /// by the online-login flow (`SyncProgressScreen`), never by
  /// `worklist_screen.dart`'s cold-sync safety net, so an already-signed-in
  /// user who simply hasn't synced yet never has their data wiped.
  Future<SyncReport> coldSync({bool wipeBeforeSync = false}) =>
      _runSync(fullSync: true, wipeBeforeSync: wipeBeforeSync);

  /// Pull-to-refresh — delta filter using the cached `lastSyncTime`. Never
  /// wipes local data.
  Future<SyncReport> warmSync() => _runSync(fullSync: false);

  Future<SyncReport> _runSync({
    required bool fullSync,
    bool wipeBeforeSync = false,
  }) async {
    if (_running) {
      return SyncReport.empty().copyWith(
        errors: const ['Sync already running'],
      );
    }
    _running = true;
    _emitProgress(const SyncProgress(currentStep: SyncStep.connecting));
    final started = DateTime.now();
    var report = SyncReport(startedAt: started, finishedAt: started)
        .copyWith(wasFullSync: fullSync);
    try {
      if (wipeBeforeSync) {
        await _db.wipeAllData();
      }

      // userId is required by the server — fail fast rather than sending a
      // request without it and getting an empty/rejected bundle silently.
      final syncUserId = await _auth.userId();
      if (syncUserId == null) {
        const msg = 'userId not available — re-login required before sync';
        _emitProgress(SyncProgress.failed(msg));
        return report.copyWith(
          finishedAt: DateTime.now(),
          errors: const [msg],
        );
      }

      // Resolve village IDs for the bundle fetch. On a full sync we need the
      // most authoritative scope (shasthyaShebikas[].subVillages) to avoid
      // over-broad bundles. Two paths:
      //
      // P1 fast-path: if UserHierarchyService has already fetched static-data
      // (e.g. it ran prefetch() during login), reuse the cached ids already
      // persisted to AuthRepository — no second HTTP call.
      //
      // Fallback: call _fetchAndSaveVillageIds() ourselves so that a cold
      // OfflineSyncService start (no UserHierarchyService, or hierarchy not
      // yet fetched) still gets the authoritative ids.
      var villageIds = <int>[];
      if (fullSync) {
        final hierarchyReady = _hierarchy?.ssWorkers != null;
        if (hierarchyReady) {
          villageIds = await _auth.villageIds();
          debugPrint(
            '[OfflineSyncService] P1: reusing hierarchy cache — '
            '${villageIds.length} village IDs, no 2nd user-data call',
          );
        } else {
          villageIds = await _fetchAndSaveVillageIds();
        }
      }
      if (villageIds.isEmpty) {
        villageIds = await _auth.villageIds();
      }
      if (villageIds.isEmpty) {
        villageIds = await _fetchAndSaveVillageIds();
      }
      if (villageIds.isEmpty) {
        _emitProgress(SyncProgress.failed('No villages assigned'));
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

      // Step 1: Fetch patients bundle
      _emitProgress(const SyncProgress(
        currentStep: SyncStep.fetchingPatients,
        entityName: 'patients',
      ));

      Map<String, dynamic>? bundle;
      try {
        bundle = await _fetchBundle(villageIds: villageIds, since: since);
      } catch (e) {
        throw StateError('fetch-synced-data failed: $e');
      }

      // Step 2: Process and persist bundle (includes households/members if in bundle - Android pattern)
      _emitProgress(const SyncProgress(
        currentStep: SyncStep.processingData,
        entityName: 'patients',
      ));
      debugPrint(
        '[OfflineSyncService] Bundle top-level keys: ${bundle.keys.toList()}',
      );
      // Filter the bundle to this SK's caseload using SS worker IDs.
      // The bundle is village-wide; households are scoped to the SK by
      // shasthyaShebikaId (the SS worker assigned to each household).
      // Android filters the same way — no `shasthyaKormiId` on members.
      final ownerUserId = await _auth.userId();
      final ssWorkerIds = await _auth.ssWorkerIds();
      debugPrint('[OfflineSyncService] Bundle filter: ownerUserId=$ownerUserId ssWorkerIds=$ssWorkerIds');
      var out = await _persistBundle(bundle, ownerUserId: ownerUserId, ssWorkerIds: ssWorkerIds);
      debugPrint(
        '[OfflineSyncService] Bundle persisted: patients=${out.patients} '
        'households=${out.households} members=${out.members} '
        'followUps=${out.followUps} immunisations=${out.immunisations} '
        'assessments=${out.assessments}',
      );

      // Bundle returns API-internal village IDs (e.g. 5) but the request used
      // static-data IDs (e.g. 26). When there is exactly one village, every
      // member row belongs to that village — stamp it unconditionally so filters
      // using static-data IDs find the rows.
      if (villageIds.length == 1 && _members != null) {
        await _members.setVillageIdForAll(villageIds.first.toString());
      }

      final int totalHouseholds = out.households;
      final int totalMembers = out.members;
      
      // Step 3c: Merge assessment history serviceProvided → patient_programmes.
      // Runs after the member sync so the member→patientId map is fully built.
      await _syncAssessmentHistoryProgrammes(villageIds);

      report = report.copyWith(
        finishedAt: DateTime.now(),
        patients: out.patients,
        followUps: out.followUps,
        immunisations: out.immunisations,
        assessments: out.assessments,
        households: totalHouseholds,
        members: totalMembers,
      );

      if (fullSync) {
        await _syncMeta.stampFull(_entityKey, report.finishedAt);
      } else {
        await _syncMeta.stampWarm(_entityKey, report.finishedAt);
      }

      // Done!
      _emitProgress(SyncProgress.completed());
      return report;
    } catch (e) {
      _emitProgress(SyncProgress.failed('Sync failed: $e'));
      return report.copyWith(
        finishedAt: DateTime.now(),
        errors: ['Sync failed: $e'],
      );
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  // App version + type are sourced from AppConfig so the Engineering Design
  // Standards "Configuration management" rule (no hardcoded build values) is
  // honoured and a single `--dart-define` bump propagates to both headers
  // (set in `ApiClient`) and request bodies.

  /// Formats [dt] as `"2024-01-15T10:30:00+00:00"` — matching Android's
  /// `DateTimeFormatter.ISO_OFFSET_DATE_TIME` output (no millis, explicit offset).
  static String _toOffsetDateTime(DateTime dt) {
    final s = dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');
    return s.endsWith('Z') ? '${s.substring(0, s.length - 1)}+00:00' : s;
  }

  Future<Map<String, dynamic>> _fetchBundle({
    required List<int> villageIds,
    DateTime? since,
  }) async {
    // Match Android RequestAllEntities format: integer villageIds + metadata
    final userId = await _auth.userId();
    if (userId == null) {
      debugPrint('[OfflineSyncService] WARNING: userId is null — sync may return empty bundle');
    }
    final deviceId = await _auth.deviceId();
    final body = <String, dynamic>{
      'villageIds': villageIds,
      if (since != null) 'lastSyncTime': _toOffsetDateTime(since),
      'userId': ?userId,
      'appVersionName': AppConfig.appVersionName,
      'appVersionCode': AppConfig.appVersionCode,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
      'appType': AppConfig.appType,
      'memberIds': <int>[],
    };
    ConsoleLog.banner('[PayloadDebug] sync-fetch\n${body.toString()}');
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

  Future<_PersistTotals> _persistBundle(
    Map<String, dynamic> bundle, {
    int? ownerUserId,
    List<int> ssWorkerIds = const [],
  }) async {
    if (bundle.isEmpty) return const _PersistTotals();

    // Log bundle keys for debugging
    debugPrint('[OfflineSyncService] Bundle keys: ${bundle.keys.toList()}');

    // ── Households (Android: ResponseInitialDownload.households) ──────────
    final householdNodes = _listFromAny(bundle, const [
      'households',
      'householdList',
    ]);
    
    // ── Members (Android: ResponseInitialDownload.members / householdMemberLinks) ─
    final memberNodes = _listFromAny(bundle, const [
      'members',
      'memberList',
      'householdMembers',
      'householdMemberLinks',
    ]);

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
    debugPrint('[OfflineSyncService] followUpNodes: ${followUpNodes.length} raw items in bundle');
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
    int followUpDropped = 0;
    for (final raw in followUpNodes) {
      if (raw is! Map) continue;
      final row = _followUpRowFrom(raw);
      if (row != null) {
        followUps.add(row);
      } else {
        followUpDropped++;
      }
    }
    if (followUpDropped > 0) {
      debugPrint('[OfflineSyncService] followUps: dropped $followUpDropped items (missing patientId)');
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

    // ── Parse households from bundle (Android: ResponseInitialDownload) ────
    final households = <HouseholdEntity>[];

    // Build referenceId → {villageId, subVillageId} BEFORE fromApiJson discards
    // the referenceId field. Member.householdId references the household's
    // referenceId (small internal ID), not the FHIR ID stored as
    // HouseholdEntity.id. We use this map to propagate village data to members
    // whose village_id is absent from the bundle payload.
    final hhRefToVillage = <String, String>{};
    final hhRefToSubVillage = <String, String>{};

    // SS worker IDs used to scope the bundle to this SK's caseload.
    // Android filters households by shasthyaShebikaId matching the SK's
    // assigned SS worker IDs. When no SS IDs are known, all households are kept.
    final ssIdSet = ssWorkerIds.toSet();
    final filteredHouseholdIds = <String>{};

    for (final raw in householdNodes) {
      if (raw is! Map) continue;
      final rawMap = Map<String, dynamic>.from(raw);

      // Apply SS worker filter: only include households whose shasthyaShebikaId
      // matches one of the SK's assigned SS workers. Households with a null or
      // missing shasthyaShebikaId are excluded when the filter is active —
      // those are unassigned/legacy records not part of this SK's caseload.
      // When no SS IDs are known (first-run before static-data completes) the
      // filter is skipped so the sync isn't left empty.
      if (ssIdSet.isNotEmpty) {
        final ssRaw = rawMap['shasthyaShebikaId'];
        final ssId = ssRaw is int
            ? ssRaw
            : (ssRaw is num
                ? ssRaw.toInt()
                : (ssRaw is String ? int.tryParse(ssRaw.trim()) : null));
        if (ssId == null || !ssIdSet.contains(ssId)) continue;
      }

      final hh = HouseholdEntity.fromApiJson(rawMap);
      if (hh.id.isNotEmpty) {
        households.add(hh);
        filteredHouseholdIds.add(hh.id);
      }

      final ref = raw['referenceId']?.toString();
      if (ref != null && ref.isNotEmpty) {
        final vid = (raw['villageId'] ?? raw['village_id'])?.toString();
        final svid = (raw['subVillageId'] ?? raw['sub_village_id'])?.toString();
        if (vid != null && vid.isNotEmpty) hhRefToVillage[ref] = vid;
        if (svid != null && svid.isNotEmpty) hhRefToSubVillage[ref] = svid;
      }
    }
    debugPrint(
      '[OfflineSyncService] Parsed ${households.length} households from bundle '
      '(${hhRefToVillage.length} with referenceId→village mapping, '
      'ssFilter=${ssIdSet.isEmpty ? "none" : ssIdSet.toString()})',
    );

    // ── Parse members from bundle (Android: ResponseInitialDownload) ────────
    // Keep only members that belong to the SK's filtered households.
    // When no household filter is active (filteredHouseholdIds empty and
    // ssIdSet empty) all members pass through for backward compatibility.
    final members = <HouseholdMemberEntity>[];
    final ownedMemberIds = <String>{};
    for (final raw in memberNodes) {
      if (raw is! Map) continue;
      var m = HouseholdMemberEntity.fromApiJson(Map<String, dynamic>.from(raw));
      if (m.id.isEmpty) continue;

      // Scope members to the SK's filtered households. When a household filter
      // is active, exclude members with a null householdId (orphaned records)
      // and members whose householdId isn't in the filtered set.
      // Mirrors the household-level rule: null → exclude when filter is active.
      if (filteredHouseholdIds.isNotEmpty) {
        if (m.householdId == null || !filteredHouseholdIds.contains(m.householdId)) continue;
      }

      // Enrich village/sub-village from household if missing.
      // Member.householdId = household.referenceId (the small internal ID).
      if (m.householdId != null) {
        final vid = m.villageId ?? hhRefToVillage[m.householdId!];
        final svid = m.subVillageId ?? hhRefToSubVillage[m.householdId!];
        if (vid != m.villageId || svid != m.subVillageId) {
          m = m.copyWithVillage(villageId: vid, subVillageId: svid);
        }
      }

      // Also try to capture shasthyaShebikaId from alternate raw key shapes.
      if (m.shasthyaShebikaId == null) {
        final ssRaw = raw['shasthyaShebikaId']
            ?? raw['shasthyaShebika']?['id']
            ?? raw['ssId'];
        final ssId = ssRaw?.toString();
        if (ssId != null && ssId.isNotEmpty) {
          m = m.copyWithVillage(shasthyaShebikaId: ssId);
        }
      }

      members.add(m);
      if (ownerUserId != null) {
        final skRaw = raw['shasthyaKormiId'];
        final sk = skRaw is int
            ? skRaw
            : (skRaw is num
                ? skRaw.toInt()
                : (skRaw is String ? int.tryParse(skRaw.trim()) : null));
        if (sk == ownerUserId) ownedMemberIds.add(m.id);
      }
    }
    debugPrint(
      '[OfflineSyncService] Parsed ${members.length} members from bundle '
      '(${ownedMemberIds.length} owned by user $ownerUserId)',
    );
    // Verify household-member linking
    if (households.isNotEmpty && members.isNotEmpty) {
      final householdIds = households.map((h) => h.id).toSet();
      final linkedMembers = members.where((m) => m.householdId != null && householdIds.contains(m.householdId)).length;
      final unassignedMembers = members.where((m) => m.householdId == null).length;
      debugPrint('[OfflineSyncService] Member-household linking: $linkedMembers linked, $unassignedMembers unassigned');
    }

    // uhis-dev backend ships `members` as the canonical patient list — the
    // offline-sync bundle has no `patients` key. Bridge each member into the
    // patients table so the worklist and mission dashboard can see them.
    // Programme membership remains driven by the dedicated `pregnancyInfos` /
    // `treatmentDetails` arrays parsed elsewhere; here we only need the
    // identity columns the worklist query selects.
    //
    // Household-level filtering by shasthyaShebikaId already scoped members
    // to this SK's caseload in the parsing loop above. Bridge all parsed
    // members directly; no secondary ownership filter is needed.
    if (patients.isEmpty && members.isNotEmpty) {
      debugPrint(
        '[OfflineSyncService] Bridging ${members.length} members → patients '
        '(households filtered by ssIds=${ssIdSet.isEmpty ? "none" : ssIdSet.toString()})',
      );
      for (final m in members) {
        final p = _memberToPatient(m);
        if (p != null) patients.add(p);
      }
      debugPrint(
        '[OfflineSyncService] Derived ${patients.length} patients from members',
      );
    }

    // ── Programme inference from bundle side-tables ──────────────────────────
    // The aggregate bundle ships member identity in `members` but programme
    // membership in `pregnancyInfos` (ANC) and `followUps.encounterType`
    // (NCD / TB / ICCM…). Build a memberId → patientId resolver from the
    // members we just parsed, then merge any programme hits into the
    // existing `programmes` map so the dashboard surfaces the right pills.
    final memberIdToPatientId = <String, String>{};
    for (final m in members) {
      final pid = (m.patientId != null && m.patientId!.isNotEmpty)
          ? m.patientId!
          : m.id;
      memberIdToPatientId[m.id] = pid;
      if (m.patientId != null && m.patientId!.isNotEmpty) {
        memberIdToPatientId[m.patientId!] = pid;
      }
    }
    void mergeProgramme(String? patientKey, Programme? programme) {
      if (patientKey == null || patientKey.isEmpty || programme == null) {
        return;
      }
      final patientId = memberIdToPatientId[patientKey] ?? patientKey;
      programmes.putIfAbsent(patientId, () => <Programme>{}).add(programme);
    }

    final pregnancyNodes = _listFromAny(bundle, const [
      'pregnancyInfos',
      'pregnancyInfoList',
      'pregnancies',
    ]);
    final pregnancyRows = <PregnancySnapshotRow>[];
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    for (final raw in pregnancyNodes) {
      if (raw is! Map) continue;
      final memberKey = JsonRead.firstString(raw, const [
        'householdMemberId',
        'memberId',
        'patientId',
      ]);
      mergeProgramme(memberKey, Programme.anc);

      final patientId =
          memberKey == null ? null : memberIdToPatientId[memberKey] ?? memberKey;
      if (patientId == null || patientId.isEmpty) continue;
      // Always persist a row when we have a member key — LMP/EDD must not be
      // dropped just because clinical fact flags failed to parse.
      final facts = _pregnancyFactsFrom(raw, now: now) ?? PregnancyFacts.empty;
      final flat = _flattenPregnancyInfo(raw);
      final eddMs = JsonRead.epochMillis(flat, const [
        'estimatedDeliveryDate',
        'edd',
        'eddDate',
      ]);
      // Android spice entity field is `lastMenstrualPeriod` (ISO string).
      final lmpMs = JsonRead.epochMillis(flat, const [
        'lastMenstrualPeriod',
        'lastMenstrualPeriodDate',
        'lmpDate',
        'lmp',
        'lmpValue',
        'menstrualDate',
        'lastPeriodDate',
      ]);
      if (lmpMs == null) {
        final wire = flat['lastMenstrualPeriod'] ?? flat['lmpDate'];
        // Key present with null is normal for multi-episode rows — not a parse error.
        if (wire != null && '$wire'.trim().isNotEmpty && '$wire' != 'null') {
          debugPrint(
            '[LMP] sync parse FAIL patient=$patientId raw=$wire',
          );
        }
      } else {
        debugPrint(
          '[LMP] sync parse OK patient=$patientId member=$memberKey '
          'lmpMs=$lmpMs eddMs=$eddMs '
          'wire=${flat['lastMenstrualPeriod']}',
        );
      }
      pregnancyRows.add(PregnancySnapshotRow(
        patientId: patientId,
        facts: facts,
        updatedAt: nowMs,
        eddDate: eddMs,
        lmpDate: lmpMs,
      ));
    }
    final withLmp =
        pregnancyRows.where((r) => r.lmpDate != null).map((r) => r.patientId);
    debugPrint(
      '[LMP] sync pregnancyInfos n=${pregnancyRows.length} '
      'withLmp=${withLmp.length} ids=${withLmp.toSet().take(8).toList()}',
    );

    // Bundle `treatmentDetails[]` → presence-only set (clinical specifics
    // live elsewhere). Drives the `ncd-drift` OVERDUE-min driver and the
    // on-treatment composite-score bonus.
    final treatmentNodes = _listFromAny(bundle, const [
      'treatmentDetails',
      'treatmentDetailsList',
      'treatments',
    ]);
    final treatmentPatientIds = <String>{};
    for (final raw in treatmentNodes) {
      if (raw is! Map) continue;
      final memberKey = JsonRead.firstString(raw, const [
        'patientId',
        'memberId',
        'householdMemberId',
      ]);
      if (memberKey == null || memberKey.isEmpty) continue;
      final patientId = memberIdToPatientId[memberKey] ?? memberKey;
      if (patientId.isEmpty) continue;
      treatmentPatientIds.add(patientId);
    }

    for (final raw in followUpNodes) {
      if (raw is! Map) continue;
      final memberKey = JsonRead.firstString(raw, const [
        'patientId',
        'memberId',
        'householdMemberId',
      ]);
      final encounter = JsonRead.firstString(raw, const [
        'encounterType',
        'encounterName',
      ]);
      mergeProgramme(memberKey, Programme.fromTag(encounter));
    }

    // Upsert patients instead of clear+insert to preserve any existing rows.
    // The upsert handles both new inserts and updates to existing rows.
    await _patients.upsertMany(patients);
    for (final entry in programmes.entries) {
      await _programmes.replaceFor(entry.key, entry.value);
    }
    // Remap follow-up patientIds through the member→BRN translation built above
    // so they match the IDs stored in the patients table.
    final remappedFollowUps = followUps.map((row) {
      final mapped = memberIdToPatientId[row.patientId];
      return (mapped != null && mapped != row.patientId)
          ? row.copyWith(patientId: mapped)
          : row;
    }).toList();
    await _followUps.upsertMany(remappedFollowUps);
    await _immunisations.upsertMany(immunisations);
    await _assessments.upsertMany(assessments);

    // Persist households and members if found in bundle and DAOs are available
    if (households.isNotEmpty && _households != null) {
      await _households.upsertMany(households);
    }
    if (members.isNotEmpty && _members != null) {
      await _members.upsertMany(members);
    }

    // Back-propagate village data via in-memory map (handles rows saved by
    // earlier syncs without enrichment). Idempotent — already-set rows skipped.
    if (_members != null && hhRefToVillage.isNotEmpty) {
      await _members.propagateVillageFromHouseholds(
        hhRefToVillage,
        hhRefToSubVillage: hhRefToSubVillage,
      );
    }

    // SQL JOIN fallback: use households.village_id to fill any remaining
    // member rows with null village_id.
    if (_members != null) {
      await _members.propagateVillageFromHouseholdTable();
    }

    // Mission Dashboard side tables (schema v8). Replace-then-write so a
    // re-sync drops stale per-patient flags — but preserve LMP/EDD (and
    // local-only enroll rows) when the server omits dates or drops a row.
    if (_pregnancySnapshot != null) {
      final prior = await _pregnancySnapshot.getAllRows();
      final merged = PregnancySnapshotDao.mergePreservingDates(
        incoming: pregnancyRows,
        prior: prior,
      );
      final mergedWithLmp =
          merged.where((r) => r.lmpDate != null).length;
      debugPrint(
        '[LMP] snapshot merge prior=${prior.length} '
        'incoming=${pregnancyRows.length} merged=${merged.length} '
        'mergedWithLmp=$mergedWithLmp',
      );
      await _pregnancySnapshot.clearAll();
      if (merged.isNotEmpty) {
        await _pregnancySnapshot.upsertMany(merged);
      }
    }
    if (_treatmentPresence != null) {
      await _treatmentPresence.clearAll();
      if (treatmentPatientIds.isNotEmpty) {
        await _treatmentPresence
            .upsertAll(treatmentPatientIds, updatedAt: nowMs);
      }
    }

    return _PersistTotals(
      patients: patients.length,
      followUps: followUps.length,
      immunisations: immunisations.length,
      assessments: assessments.length,
      households: households.length,
      members: members.length,
    );
  }

  /// Map a household member row into the minimum Patient shape the worklist
  /// query selects. The uhis-dev backend treats every household member as a
  /// candidate patient — there is no separate `patients` array in the bundle.
  /// Returns null if the member lacks a usable identifier.
  static Patient? _memberToPatient(HouseholdMemberEntity m) {
    if (m.id.isEmpty) return null;
    // Derive age in years from DOB when available — the JSON bundle never carries
    // a pre-computed `age` field for household members, so without this the
    // patient.age stays null and all age-gated sections show for every member.
    int? ageYears;
    if (m.dob != null) {
      final dob = DateTime.tryParse(m.dob!);
      if (dob != null) {
        final now = DateTime.now();
        ageYears = now.year - dob.year;
        if (now.month < dob.month ||
            (now.month == dob.month && now.day < dob.day)) {
          ageYears--;
        }
        if (ageYears < 0) ageYears = 0;
      }
    }
    return Patient(
      // Prefer the explicit patientId when the backend has minted one, else
      // fall back to the member's own UUID so every member shows up exactly
      // once in the patients table.
      id: (m.patientId != null && m.patientId!.isNotEmpty) ? m.patientId! : m.id,
      patientId: m.patientId,
      name: m.name,
      gender: m.gender,
      dob: m.dob,
      phone: m.phone,
      nationalId: m.nationalId,
      householdId: m.householdId,
      // Mirror Android AssessmentEntity: use the sub-village ID as the canonical
      // villageId so that assessment payloads scope to the same granularity that
      // the Android SK's pull request uses (getAllSubVillageIds → [203, 204, 206]).
      // Without this, Flutter tags assessments with the parent village (34) and
      // Android's member-assessment-history pull (scoped to sub-villages) never
      // finds them.
      villageId: m.subVillageId ?? m.villageId,
      villageName: m.subVillageName ?? m.villageName,
      isActive: m.isActive,
      updatedAt: m.updatedAt,
      rawJson: m.rawJson ?? '{}',
      age: ageYears,
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
    // PILOT-SCOPE v1: TB enrolment signal disabled — TB not in pilot.
    // To restore: un-comment the block below and add Programme.tb to kPilotProgrammes.
    // if (_truthy(raw['isTbEnrolled']) ||
    //     _truthy(raw['presumptiveTb']) ||
    //     raw['presumptiveTbNo'] != null) {
    //   out.add(Programme.tb);
    // }
    final age = JsonRead.firstInt(raw, const ['age']);
    if (age != null && age < 5) out.add(Programme.imci);
    return out;
  }

  /// Infer programme from `observations.confirmDiagnosis` in an assessment
  /// history row. The field is a comma-separated string of SNOMED display
  /// terms sent by the UHIS backend when serviceProvided="enrollment".
  static Programme? _inferProgrammeFromObservations(Map<String, dynamic> raw) {
    final obs = raw['observations'];
    if (obs is! Map) return null;
    final diag = obs['confirmDiagnosis']?.toString().toLowerCase() ?? '';
    if (diag.isEmpty) return null;
    if (diag.contains('hypertension') ||
        diag.contains('diabetes') ||
        diag.contains('cardiovascular') ||
        diag.contains('heart disease') ||
        diag.contains('copd') ||
        diag.contains('chronic kidney')) {
      return Programme.ncd;
    }
    if (diag.contains('pregnan') || diag.contains('antenatal') || diag.contains('anc')) {
      return Programme.anc;
    }
    if (diag.contains('tuberculosis') || diag.contains(' tb')) {
      return Programme.tb;
    }
    return null;
  }

  static bool _truthy(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == 'yes' || s == 'y' || s == '1';
  }

  FollowUpRow? _followUpRowFrom(Map raw) {
    // Android FollowUp.id is Long? — server may return null for newly-created
    // records not yet server-committed. Generate a deterministic synthetic ID
    // so those records are not silently dropped (P3 fix).
    String? id = JsonRead.firstString(raw, const ['id', 'fhirId', 'uuid']);
    final patientId = JsonRead.firstString(raw, const [
      'patientId',
      'memberId',
      'householdMemberId',
      'patientReference',
    ]);
    if (patientId == null) return null;
    if (id == null) {
      // Derive a stable key from (patientId, type, dueDate) so a re-sync
      // produces the same row rather than inserting duplicates.
      final kind = JsonRead.firstString(raw, const ['type', 'followUpType', 'encounterType']);
      final due = JsonRead.firstString(raw, const ['nextFollowUpDate', 'dueDate', 'nextVisitDate']);
      id = 'fu-$patientId-${kind ?? "generic"}-${due ?? "0"}';
    }
    final kind = JsonRead.firstString(raw, const ['type', 'followUpType']);
    final dueAt = JsonRead.epochMillis(raw, const [
      'nextFollowUpDate',
      'dueDate',
      'nextVisitDate',
      'visitDate',
    ]);
    final completedAt = JsonRead.epochMillis(
        raw, const ['completedAt', 'completedDate', 'visitDate']);
    final attempts = JsonRead.firstInt(raw, const ['attempts', 'visits']);
    final unsuccessful = JsonRead.firstInt(raw, const [
      'unsuccessfulAttempts',
      'failedAttempts',
    ]);
    final referredSiteId = JsonRead.firstString(raw, const [
      'referredSiteId',
      'referralSiteId',
    ]);
    // Server `type` enum stored verbatim (`REFERRED` / `SCREENED` /
    // `LOST_TO_FOLLOW_UP` / `MEDICAL_REVIEW`). Orthogonal to [kind] which
    // is the risk-scoring bucket.
    final wireType = JsonRead.firstString(raw, const [
      'type',
      'followUpType',
    ])?.toUpperCase();
    final isLost = _truthy(raw['isLostToFollowUp']) ||
        _truthy(raw['lostToFollowUp']) ||
        (kind != null && kind.toLowerCase().contains('lost')) ||
        wireType == 'LOST_TO_FOLLOW_UP';
    final backendId = (raw['id'] as num?)?.toInt();
    return FollowUpRow(
      id: id,
      patientId: patientId,
      kind: _normaliseFollowUpKind(kind),
      dueAt: dueAt,
      completedAt: completedAt,
      attempts: attempts,
      unsuccessfulAttempts: unsuccessful,
      type: wireType,
      referredSiteId: referredSiteId,
      isLost: isLost,
      backendId: backendId,
      rawJson: JsonRead.encode(raw),
    );
  }

  /// True when `value` carries meaningful content — non-null, non-empty
  /// string (rejecting `"null"`, `"[]"`, `"{}"` as sentinels), non-empty
  /// collection, non-zero number, or truthy bool. Used by
  /// [_pregnancyFactsFrom] because the bundle returns several "high-risk"
  /// fields as JSON-encoded arrays of conditions (e.g.
  /// `"[\"High Fever\",\"Abnormal Pulse\"]"`) rather than booleans — the
  /// presence of the array itself is the signal.
  static bool _hasContent(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    final s = value.toString().trim();
    if (s.isEmpty) return false;
    final lower = s.toLowerCase();
    if (lower == 'null' || lower == 'false') return false;
    if (s == '[]' || s == '{}') return false;
    return true;
  }

  /// Flatten nested pregnancy DTOs so LMP/EDD keys are readable at the top
  /// level. Spice `pregnancyInfos[]` is usually flat (`lastMenstrualPeriod`),
  /// but assessment-shaped nests still show up on some builds.
  static Map<String, dynamic> _flattenPregnancyInfo(Map raw) {
    final flat = <String, dynamic>{
      for (final e in raw.entries) e.key.toString(): e.value,
    };
    for (final sub in const [
      'pregnancyDetails',
      'pregnancyDetail',
      'pwProfile',
      'pregnancyProfile',
      'obstetricHistory',
      'observations',
      'assessmentDetails',
    ]) {
      final nested = raw[sub];
      if (nested is Map) {
        for (final e in nested.entries) {
          flat.putIfAbsent(e.key.toString(), () => e.value);
        }
      }
    }
    return flat;
  }

  /// Build a [PregnancyFacts] snapshot from one `pregnancyInfos[]` row.
  /// Per-row narrow-catch — one malformed entry should not kill the rest.
  static PregnancyFacts? _pregnancyFactsFrom(Map raw, {required DateTime now}) {
    try {
      final highRisk = _hasContent(raw['highRiskPregnantWoman']) ||
          _hasContent(raw['highRiskMother']);
      final gapsAnc = _hasContent(raw['gapsInAnc']);

      bool withinDays(Object? value, int windowDays, {bool future = false}) {
        final ts = JsonRead.epochMillis({'_': value}, const ['_']);
        if (ts == null) return false;
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        final diff = future ? dt.difference(now) : now.difference(dt);
        return diff.inDays >= 0 && diff.inDays <= windowDays;
      }

      final dod = raw['dateOfDelivery'] ?? raw['deliveryDate'];
      final edd = raw['estimatedDeliveryDate'] ?? raw['edd'];
      final isPostpartum = withinDays(dod, 42);
      final isNearTerm = withinDays(edd, 14, future: true);

      final hadComplications =
          _hasContent(raw['complicationsDuringDelivery']) ||
              _truthy(raw['isDeliveryAtHome']);

      final hasPncIll = _hasContent(raw['pncIllness']);

      return PregnancyFacts(
        highRiskPregnantWoman: highRisk,
        hasGapsInAnc: gapsAnc,
        isPostpartumWindow: isPostpartum,
        isNearTermAnc: isNearTerm,
        hadDeliveryComplications: hadComplications,
        hasPncIllness: hasPncIll,
      );
    } on Object catch (e) {
      debugPrint('[OfflineSyncService] pregnancyInfos parse failed: $e');
      return null;
    }
  }

  /// Extracts a normalised vitals map from an assessment-history raw JSON row.
  /// The server places clinical values in `observations` (e.g. weight, height,
  /// bp "110/80", bg) which are merged with the top-level row and normalised to
  /// the keys [VitalsRepository.latestFromLocal] reads (`systolic`, `diastolic`,
  /// `weight`, `height`, `bmi`, `temperature`, `glucoseValue`, `spO2`,
  /// `respiratoryRate`). Returns null when no recognisable vital is found.
  static Map<String, dynamic>? _vitalsFromAssessmentRaw(
      Map<String, dynamic> raw) {
    final src = <String, dynamic>{};
    // Primary key used by the assessment-history endpoint.
    for (final key in const ['observations', 'assessmentDetails']) {
      final details = raw[key];
      if (details is Map) {
        for (final e in details.entries) {
          src.putIfAbsent(e.key.toString(), () => e.value);
        }
      }
    }
    // Merge top-level fields as fallback (some backends inline vitals directly).
    for (final e in raw.entries) {
      src.putIfAbsent(e.key, () => e.value);
    }

    double? num_(String key) {
      final v = src[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final vitals = <String, dynamic>{};

    // BP — `bp` arrives as "110/80" slash-string; also handle avgSystolic/avgDiastolic forms.
    final bpStr = src['bp'];
    if (bpStr is String && bpStr.contains('/')) {
      final parts = bpStr.split('/');
      if (parts.length == 2) {
        final s = double.tryParse(parts[0].trim());
        final d = double.tryParse(parts[1].trim());
        if (s != null) src.putIfAbsent('systolic', () => s);
        if (d != null) src.putIfAbsent('diastolic', () => d);
      }
    }
    final sys = num_('avgSystolic') ?? num_('systolicBp') ?? num_('systolic');
    final dia = num_('avgDiastolic') ?? num_('diastolicBp') ?? num_('diastolic');
    if (sys != null) vitals['systolic'] = sys;
    if (dia != null) vitals['diastolic'] = dia;

    // Direct-key matches for VitalsRepository field names.
    for (final key in const [
      'weight', 'height', 'bmi', 'temperature', 'spO2', 'respiratoryRate', 'muac',
    ]) {
      final v = num_(key);
      if (v != null) vitals[key] = v;
    }

    // Haemoglobin — drives ANC anaemia bands in RiskScoringService.
    final hb = num_('hemoglobin') ?? num_('hb');
    if (hb != null) vitals['hemoglobin'] = hb;

    // Glucose — `bg` is the observations field; also handle longer names.
    final glucose =
        num_('bg') ?? num_('glucoseValue') ?? num_('glucose') ?? num_('bloodGlucose');
    if (glucose != null) vitals['glucoseValue'] = glucose;

    return vitals.isEmpty ? null : vitals;
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

  /// Fetches assessment history and merges `serviceProvided` values into the
  /// local `patient_programmes` table. Called after `_persistBundle` so that
  /// the member→patient ID map is fully built before we do the lookup.
  ///
  /// This supplements the programme extraction done in `_persistBundle` (which
  /// uses `pregnancyInfos`, `treatmentDetails`, and `followUps.encounterType`).
  /// Assessment history provides the most up-to-date service type per member.
  Future<void> _syncAssessmentHistoryProgrammes(List<int> villageIds) async {
    if (_members == null) return;
    try {
      final items = await fetchAssessmentHistory(villageIds: villageIds);
      if (items.isEmpty) return;

      // Collect unique member IDs and bulk-resolve to patient IDs.
      final memberIds = items
          .map((i) => i.householdMemberId)
          .toSet()
          .toList(growable: false);
      final memberToPatient =
          await _members.patientIdsByMemberIds(memberIds);

      // Group programmes, latest visitDate, and nextFollowUpDate per patientId.
      final newProgrammes = <String, Set<Programme>>{};
      final latestVisitMs = <String, int>{};   // patientId → ms of last visit
      final nextFollowUpMs = <String, int>{};  // patientId → ms of next appt

      for (final item in items) {
        final patientId = memberToPatient[item.householdMemberId];
        if (patientId == null || patientId.isEmpty) continue;

        // Primary: map serviceProvided tag directly.
        var programme = Programme.fromTag(item.serviceProvided);

        // Fallback: when serviceProvided is "enrollment" or otherwise unmapped,
        // infer the programme from observations.confirmDiagnosis. The UHIS
        // backend sends confirmDiagnosis as a comma-separated string of SNOMED
        // display terms (e.g. "Hypertension, Diabetes mellitus type 2 (disorder)").
        if (programme == null || programme == Programme.unknown) {
          programme = _inferProgrammeFromObservations(item.rawJson);
        }

        if (programme != null && programme != Programme.unknown) {
          newProgrammes
              .putIfAbsent(patientId, () => <Programme>{})
              .add(programme);
        }

        // Track latest visit per patient (assessment history rows are not
        // guaranteed to be in order — take the maximum visitDate).
        final visitMs = item.visitDate.millisecondsSinceEpoch;
        final prev = latestVisitMs[patientId];
        if (prev == null || visitMs > prev) latestVisitMs[patientId] = visitMs;

        // nextFollowUpDate wins over inferred interval — only overwrite if the
        // new value is more recent than one we've already seen for this patient.
        final nfd = item.nextFollowUpDate;
        if (nfd != null) {
          final nfdMs = nfd.millisecondsSinceEpoch;
          final prevNfd = nextFollowUpMs[patientId];
          if (prevNfd == null || nfdMs > prevNfd) {
            nextFollowUpMs[patientId] = nfdMs;
          }
        }
      }

      // Merge programmes into patient_programmes — add, never remove.
      int progUpdated = 0;
      for (final entry in newProgrammes.entries) {
        final existing = await _programmes.programmesFor(entry.key);
        final merged = {...existing, ...entry.value};
        if (merged.length > existing.length) {
          await _programmes.replaceFor(entry.key, merged);
          progUpdated++;
        }
      }

      // Seed last_visit_at (and next_due_at when available) from assessment
      // history so _inferDueAt can compute overdue/dueToday tiers for patients
      // whose bundle follow-up records have no nextVisitDate. Uses patchVisitTiming
      // so only non-null values are written — the subsequent recomputeAllAfterSync
      // pass will not erase these because updateRisk also guards with null-checks.
      int schedUpdated = 0;
      for (final pid in latestVisitMs.keys) {
        await _patients.patchVisitTiming(
          patientId: pid,
          lastVisitAt: latestVisitMs[pid],
          nextDueAt: nextFollowUpMs[pid], // null for most NCD patients
        );
        schedUpdated++;
      }

      // P3: Synthesise FollowUpRow entries from assessment-history nextFollowUpDate
      // so the follow_ups table is populated even when the bulk-sync bundle
      // contains no followUps (e.g. for NCD patients whose open follow-up was not
      // yet included in the bundle). Mirrors Android's behaviour: every assessment
      // with a scheduled nextVisitDate creates/updates a follow-up record.
      // Uses a deterministic id keyed on (patientId, programme, dueDate) so
      // re-syncing is idempotent.
      final historyFollowUps = <FollowUpRow>[];
      for (final pid in nextFollowUpMs.keys) {
        final dueAt = nextFollowUpMs[pid]!;
        final programme = newProgrammes[pid]?.firstOrNull?.name ?? 'generic';
        historyFollowUps.add(FollowUpRow(
          id: 'hist-fu-$pid-$programme',
          patientId: pid,
          kind: _normaliseFollowUpKind(programme),
          dueAt: dueAt,
          rawJson: '{"source":"assessment-history"}',
        ));
      }
      if (historyFollowUps.isNotEmpty) {
        await _followUps.upsertMany(historyFollowUps);
        debugPrint(
          '[OfflineSyncService] P3: seeded ${historyFollowUps.length} follow-up rows from assessment history',
        );
      }

      // Write encounter rows with extracted vitals so VitalsRepository can
      // render Recent Vitals without a new network call. Only rows that carry
      // clinical assessmentDetails (NCD/ANC/PNC have BP/weight etc.) get an
      // encounter row; rows with no vitals content are skipped.
      int vitalsWritten = 0;
      if (_encounterDao != null) {
        for (final item in items) {
          final patientId = memberToPatient[item.householdMemberId];
          if (patientId == null || patientId.isEmpty) continue;
          final vitals = _vitalsFromAssessmentRaw(item.rawJson);
          if (vitals == null) continue;
          final enc = EncounterRow(
            id: item.encounterId,
            patientId: patientId,
            programme: (item.serviceProvided ?? 'assessment').toLowerCase(),
            startedAt: item.visitDate.millisecondsSinceEpoch,
            completedAt: item.visitDate.millisecondsSinceEpoch,
            status: EncounterStatus.synced,
            syncStatus: SyncStatus.synced,
            vitalsJson: jsonEncode(vitals),
          );
          await _encounterDao.upsert(enc);
          vitalsWritten++;
        }
      }

      // Write assessment rows keyed by FHIR patient ID so AssessmentDao queries
      // by patientId resolve correctly (assessment history uses numeric
      // householdMemberId; the bulk-sync bundle may use a different field).
      final assessmentRows = <AssessmentRow>[];
      for (final item in items) {
        final patientId = memberToPatient[item.householdMemberId];
        if (patientId == null || patientId.isEmpty) continue;
        assessmentRows.add(AssessmentRow(
          id: item.encounterId,
          patientId: patientId,
          kind: item.serviceProvided,
          occurredAt: item.visitDate.millisecondsSinceEpoch,
          rawJson: jsonEncode(item.rawJson),
        ));
      }
      if (assessmentRows.isNotEmpty) {
        await _assessments.upsertMany(assessmentRows);
      }

      debugPrint(
        '[OfflineSyncService] assessment-history sync: '
        '${items.length} rows → $progUpdated programme updates, '
        '$schedUpdated visit-schedule updates, $vitalsWritten encounter rows with vitals, '
        '${assessmentRows.length} assessment rows',
      );
    } catch (e) {
      debugPrint(
        '[OfflineSyncService] assessment-history programme sync failed: $e',
      );
    }
  }

  /// Calls `POST /spice-service/static-data/user-data`, extracts village IDs
  /// and the user's FHIR Practitioner ID, persists both, and returns the list.
  /// Returns an empty list if the endpoint fails or returns no villages.
  ///
  /// Android MetaDataResponse.userProfile.fhirId mirrors ProvanceDto.userId —
  /// storing it here prevents HAPI-1094 Practitioner/numericId not found.
  Future<List<int>> _fetchAndSaveVillageIds() async {
    try {
      final resp = await _api.dio.post(Endpoints.staticUserData);
      final data = resp.data;
      Map<String, dynamic> entity;
      if (data is Map && data['entity'] is Map) {
        entity = Map<String, dynamic>.from(data['entity'] as Map);
      } else if (data is Map) {
        entity = Map<String, dynamic>.from(data);
      } else {
        return const [];
      }

      // Log entity top-level keys so we can identify org FHIR ID field name.
      debugPrint('[OfflineSyncService] entity keys: ${entity.keys.toList()}');

      // Persist FHIR Practitioner ID from userProfile so provenance.userId
      // references a real Practitioner resource (mirrors Android saveFhirId()).
      final userProfile = entity['userProfile'];
      if (userProfile is Map) {
        debugPrint('[OfflineSyncService] userProfile keys: ${userProfile.keys.toList()}');
        final fhirId = userProfile['fhirId'] as String?;
        if (fhirId != null && fhirId.isNotEmpty) {
          await _auth.saveUserFhirId(fhirId);
          debugPrint('[OfflineSyncService] Saved userFhirId: $fhirId');
        }
      }

      // Persist FHIR Organization ID (mirrors Android healthFacility.fhirId →
      // SecuredPreference.ORGANIZATION_FHIR_ID). Try common response key names.
      String? orgFhirId;
      for (final key in const [
        'defaultHealthFacility',
        'healthFacility',
        'organization',
        'facility',
      ]) {
        final fac = entity[key];
        if (fac is Map) {
          debugPrint('[OfflineSyncService] $key keys: ${fac.keys.toList()}');
          final fid = fac['fhirId'] as String? ?? fac['fhir_id'] as String?;
          if (fid != null && fid.isNotEmpty) {
            orgFhirId = fid;
            debugPrint('[OfflineSyncService] orgFhirId from $key.fhirId: $fid');
            break;
          }
        }
      }
      // Fallback: iterate healthFacilities list for isDefault=true.
      if (orgFhirId == null) {
        final facilities = entity['healthFacilities'];
        if (facilities is List) {
          debugPrint('[OfflineSyncService] healthFacilities count: ${facilities.length}');
          for (final fac in facilities) {
            if (fac is! Map) continue;
            final isDefault = fac['isDefault'] == true || fac['isDefault'] == 1;
            debugPrint('[OfflineSyncService] facility id=${fac['id']} fhirId=${fac['fhirId']} isDefault=$isDefault');
            if (isDefault) {
              final fid = fac['fhirId'] as String?;
              if (fid != null && fid.isNotEmpty) {
                orgFhirId = fid;
                debugPrint('[OfflineSyncService] orgFhirId from healthFacilities[default].fhirId: $fid');
                break;
              }
            }
          }
          if (orgFhirId == null && facilities.isNotEmpty) {
            final first = facilities.first;
            if (first is Map) {
              final fid = first['fhirId'] as String?;
              if (fid != null && fid.isNotEmpty) {
                orgFhirId = fid;
                debugPrint('[OfflineSyncService] orgFhirId from healthFacilities[0].fhirId: $fid');
              }
            }
          }
        }
      }
      if (orgFhirId != null) {
        await _auth.saveOrganizationFhirId(orgFhirId);
      } else {
        debugPrint('[OfflineSyncService] WARNING: orgFhirId not found — entity keys: ${entity.keys.toList()}');
      }

      // Mirror Android MetaRepository: use sub-villages nested within
      // shasthyaShebikas (most specific scope) before falling back to the
      // top-level subVillages list or village IDs.
      List<int> extractSubVillageIds(dynamic raw) => (raw is List)
          ? raw
              .whereType<Map>()
              .map((m) {
                final id = m['id'];
                if (id is int) return id;
                if (id is num) return id.toInt();
                if (id is String) return int.tryParse(id);
                return null;
              })
              .whereType<int>()
              .toList()
          : const <int>[];

      // 1. shasthyaShebikas[].subVillages — SK's specific area
      final ssRaw = entity['shasthyaShebikas'];
      final ssSubIds = (ssRaw is List)
          ? ssRaw
              .whereType<Map>()
              .expand((ss) => extractSubVillageIds(ss['subVillages']))
              .toList()
          : const <int>[];

      // 2. Top-level subVillages
      final topSubIds = extractSubVillageIds(entity['subVillages']);

      // 3. Top-level villages (broadest, last resort)
      final villageIds = extractSubVillageIds(entity['villages']);

      final ids = ssSubIds.isNotEmpty
          ? ssSubIds
          : (topSubIds.isNotEmpty ? topSubIds : villageIds);

      debugPrint(
          '[OfflineSyncService] static-data village candidates: '
          'ssSubIds=${ssSubIds.length} topSubIds=${topSubIds.length} '
          'villageIds=${villageIds.length} → using ${ids.length}');

      if (ids.isNotEmpty) {
        await _auth.saveLinkedVillageIds(ids);
        debugPrint('[OfflineSyncService] Fetched ${ids.length} sub-village IDs from static-data fallback');
      }

      // Extract SS worker IDs (shasthyaShebikas[].id) — used to filter bundle
      // households by shasthyaShebikaId so only the SK's caseload is stored.
      final ssWorkerIds = (ssRaw is List)
          ? ssRaw
              .whereType<Map>()
              .map((ss) {
                final id = ss['id'];
                if (id is int) return id;
                if (id is num) return id.toInt();
                if (id is String) return int.tryParse(id);
                return null;
              })
              .whereType<int>()
              .toList()
          : const <int>[];
      if (ssWorkerIds.isNotEmpty) {
        await _auth.saveSsWorkerIds(ssWorkerIds);
        debugPrint('[OfflineSyncService] Saved ${ssWorkerIds.length} SS worker IDs: $ssWorkerIds');
      }

      return ids;
    } catch (e) {
      debugPrint('[OfflineSyncService] static-data fallback failed: $e');
      return const [];
    }
  }

  /// Fetches the offline-sync member-assessment-history list.
  ///
  /// Wraps `POST /offline-service/offline-sync/member-assessment-history`.
  /// Mirrors the Android reference contract (`OfflineSyncRepository
  /// .fetchMemberAssessmentHistory`): the request scopes by [villageIds] for
  /// CHW users and falls back to the logged-in user's assigned villages so
  /// the call site does not have to remember to thread them through.
  ///
  /// Returns an empty list (rather than throwing) on transport failure so a
  /// flaky cell connection cannot blank the Service-History tab while the
  /// local SQLite cache still holds usable data.
  Future<List<AssessmentHistoryItem>> fetchAssessmentHistory({
    List<int>? villageIds,
    String? memberId,
    DateTime? since,
  }) async {
    var villages = villageIds;
    if (villages == null || villages.isEmpty) {
      villages = await _auth.villageIds();
    }
    if (villages.isEmpty) return const [];
    // Dedupe — `villageIds()` can return duplicates when sub-village + village
    // IDs collapse to the same numeric scope. Backend treats `[26, 26]` and
    // `[26]` the same but the duplicate is noise on the wire.
    final scope = villages.toSet().toList();

    final userId = await _auth.userId();
    final deviceId = await _auth.deviceId();

    // NOTE: `memberId` is intentionally omitted from the request body even when
    // the caller passes one. Spice-side member-history filter keys on the
    // numeric internal id, not the FHIR id we hold on the client, so a
    // memberId in the body silently excludes every row. The endpoint already
    // scopes by `villageIds`; we filter to the requested member client-side
    // via [_filterHistoryForMember] in the calling repository.
    if (userId == null) {
      debugPrint('[OfflineSyncService] WARNING: userId is null for assessment-history request');
    }
    final body = <String, dynamic>{
      'appType': AppConfig.appType,
      'villageIds': scope,
      if (since != null) 'lastSyncTime': _toOffsetDateTime(since),
      'userId': ?userId,
      'appVersionName': AppConfig.appVersionName,
      'appVersionCode': AppConfig.appVersionCode,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
      'memberIds': <int>[],
    };
    ConsoleLog.banner('[PayloadDebug] assessment-history\n${body.toString()}');

    try {
      final resp = await _api.dio.post(
        Endpoints.offlineSyncMemberAssessmentHistory,
        data: body,
      );
      final status = resp.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        debugPrint(
          '[OfflineSyncService] member-assessment-history HTTP $status',
        );
        return const [];
      }
      final data = resp.data;
      debugPrint('[OfflineSyncService] member-assessment-history raw response keys=${data is Map ? data.keys.toList() : "list"} totalCount=${data is Map ? data["totalCount"] : "n/a"}');
      final raw = _extractHistoryList(data);
      final items = <AssessmentHistoryItem>[];
      for (final row in raw) {
        if (row is! Map) continue;
        final item =
            AssessmentHistoryItem.fromJson(Map<String, dynamic>.from(row));
        if (item != null) items.add(item);
      }
      items.sort((a, b) => b.visitDate.compareTo(a.visitDate));
      debugPrint(
        '[OfflineSyncService] member-assessment-history villages=$scope rawRows=${raw.length} parsed=${items.length}',
      );
      return items;
    } catch (e) {
      debugPrint('[OfflineSyncService] member-assessment-history failed: $e');
      return const [];
    }
  }

  /// The endpoint sometimes returns a bare list, sometimes wraps it in
  /// `{ entity: [...] }` / `{ entityList: [...] }` / `{ data: [...] }` — the
  /// spice envelope conventions leak through. Tolerate all three.
  static List<dynamic> _extractHistoryList(Object? body) {
    if (body is List) return body;
    if (body is Map) {
      for (final key in const ['entity', 'entityList', 'data']) {
        final v = body[key];
        if (v is List) return v;
      }
    }
    return const [];
  }

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }
}

class _PersistTotals {
  const _PersistTotals({
    this.patients = 0,
    this.followUps = 0,
    this.immunisations = 0,
    this.assessments = 0,
    this.households = 0,
    this.members = 0,
  });

  final int patients;
  final int followUps;
  final int immunisations;
  final int assessments;
  final int households;
  final int members;

  _PersistTotals copyWith({
    int? patients,
    int? followUps,
    int? immunisations,
    int? assessments,
    int? households,
    int? members,
  }) =>
      _PersistTotals(
        patients: patients ?? this.patients,
        followUps: followUps ?? this.followUps,
        immunisations: immunisations ?? this.immunisations,
        assessments: assessments ?? this.assessments,
        households: households ?? this.households,
        members: members ?? this.members,
      );
}

