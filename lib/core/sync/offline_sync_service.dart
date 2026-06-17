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
import '../db/household_dao.dart';
import '../db/immunisation_dao.dart';
import '../db/member_dao.dart';
import '../db/patient_dao.dart';
import '../db/patient_programmes_dao.dart';
import '../db/pregnancy_snapshot_dao.dart';
import '../db/referral_dao.dart';
import '../db/sync_meta_dao.dart';
import '../db/treatment_presence_dao.dart';
import '../mission/mission_pregnancy_facts.dart';
import '../models/json_read.dart';
import '../models/patient.dart';
import '../models/programme.dart';
import '../models/referral.dart';
import '../models/sla.dart';
import 'sync_progress.dart';
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
    required ReferralDao referrals,
    required SyncMetaDao syncMeta,
    HouseholdDao? households,
    MemberDao? members,
    PregnancySnapshotDao? pregnancySnapshot,
    TreatmentPresenceDao? treatmentPresence,
  })  : _api = api,
        _auth = auth,
        _patients = patients,
        _programmes = programmes,
        _followUps = followUps,
        _immunisations = immunisations,
        _assessments = assessments,
        _referrals = referrals,
        _syncMeta = syncMeta,
        _households = households,
        _members = members,
        _pregnancySnapshot = pregnancySnapshot,
        _treatmentPresence = treatmentPresence;

  static const String _entityKey = 'worklist';

  final ApiClient _api;
  final AuthRepository _auth;
  final PatientDao _patients;
  final PatientProgrammesDao _programmes;
  final FollowUpDao _followUps;
  final HouseholdDao? _households;
  final MemberDao? _members;
  final ImmunisationDao _immunisations;
  final AssessmentDao _assessments;
  final ReferralDao _referrals;
  final SyncMetaDao _syncMeta;
  final PregnancySnapshotDao? _pregnancySnapshot;
  final TreatmentPresenceDao? _treatmentPresence;

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
    _emitProgress(const SyncProgress(currentStep: SyncStep.connecting));
    final started = DateTime.now();
    var report = SyncReport(startedAt: started, finishedAt: started)
        .copyWith(wasFullSync: fullSync);
    try {
      var villageIds = await _auth.villageIds();
      if (villageIds.isEmpty) {
        // Profile endpoint returned no villages (common for kakina_sk accounts
        // whose villages come from static-data, not /user-service/user/profile).
        // Fetch the authoritative list now and persist it so this sync — and
        // every subsequent one — succeeds without requiring a filter-sheet open.
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
        // Aggregate endpoint failed — fall back to granular spice calls so
        // the worklist still moves forward on a flaky cell connection.
        return await _fallbackGranularSync(
          villageIds: villageIds,
          fullSync: fullSync,
          started: started,
          aggregateError: e.toString(),
        );
      }

      // Step 2: Process and persist bundle (includes households/members if in bundle - Android pattern)
      _emitProgress(const SyncProgress(
        currentStep: SyncStep.processingData,
        entityName: 'patients',
      ));
      debugPrint(
        '[OfflineSyncService] Bundle top-level keys: ${bundle.keys.toList()}',
      );
      // Bundle is village-wide (every member in every assigned sub-village).
      // Each member row carries `shasthyaKormiId` — the SK who owns them.
      // Pass our user id so the bridge layer keeps only the SK's own patients
      // on the dashboard worklist while the household list still sees the
      // full village (the household screen reads from the members table,
      // which we keep unfiltered).
      final ownerUserId = await _auth.userId();
      debugPrint('[OfflineSyncService] Using ownerUserId=$ownerUserId for member-patient filtering');
      var out = await _persistBundle(bundle, ownerUserId: ownerUserId);
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
        await _members!.setVillageIdForAll(villageIds.first.toString());
      }

      // Step 2b: Bundle parsed zero patients — try the granular
      // /spice-service/patient/offline/list path (Android fallback shape)
      // before giving up. Aggregate sometimes returns metadata-only payloads
      // when the bundled endpoint disagrees on the wire schema.
      if (out.patients == 0) {
        debugPrint(
          '[OfflineSyncService] Bundle yielded zero patients — falling back '
          'to granular /spice-service/patient/offline/list',
        );
        final patientNodes = await _fetchPatientList(villageIds);
        if (patientNodes.isNotEmpty) {
          final patients = <Patient>[];
          final programmes = <String, Set<Programme>>{};
          for (final raw in patientNodes) {
            if (raw is! Map) continue;
            final p = Patient.fromApiJson(raw);
            if (p == null) continue;
            patients.add(p);
            programmes[p.id] = _extractProgrammes(raw);
          }
          if (patients.isNotEmpty) {
            await _patients.upsertMany(patients);
            for (final entry in programmes.entries) {
              await _programmes.replaceFor(entry.key, entry.value);
            }
            out = out.copyWith(patients: patients.length);
            debugPrint(
              '[OfflineSyncService] Granular fallback persisted '
              '${patients.length} patients',
            );
          }
        }
      }

      // Step 3: Sync households and members from the separate household-list
      // endpoint. This always runs on a cold sync because the bundle endpoint
      // strips villageId / subVillageId from its household JSON, leaving
      // members with null village_id that makes every filter return 0 rows.
      // On warm syncs we skip it when the bundle already returned households,
      // to avoid the extra 6-8 paginated API calls on every pull-to-refresh.
      int totalHouseholds = out.households;
      int totalMembers = out.members;
      if (out.households == 0 || fullSync) {
        _emitProgress(const SyncProgress(
          currentStep: SyncStep.fetchingPatients,
          entityName: 'households',
        ));
        final hhCount = await _syncHouseholdsAndMembers(villageIds: villageIds);
        if (hhCount.households > 0) totalHouseholds = hhCount.households;
        // Only update members count if we didn't get any from the bundle
        if (out.members == 0 && hhCount.members > 0) totalMembers = hhCount.members;
      }
      
      // Step 4: Sync referrals
      _emitProgress(SyncProgress(
        currentStep: SyncStep.fetchingReferrals,
        entityName: 'referrals',
        itemsDone: out.patients,
        itemsTotal: out.patients,
      ));
      final referralCount = await _syncReferrals(villageIds: villageIds);
      
      report = report.copyWith(
        finishedAt: DateTime.now(),
        patients: out.patients,
        followUps: out.followUps,
        immunisations: out.immunisations,
        assessments: out.assessments,
        referrals: referralCount,
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

  // App version constants (match pubspec.yaml)
  static const String _appVersionName = '1.0.0';
  static const int _appVersionCode = 1;
  static const String _appType = 'community'; // Matches Android CommonUtils.isCommunityOrNot()

  Future<Map<String, dynamic>> _fetchBundle({
    required List<int> villageIds,
    DateTime? since,
  }) async {
    // Match Android RequestAllEntities format: integer villageIds + metadata
    final userId = await _auth.userId();
    final deviceId = await _auth.deviceId();
    final body = <String, dynamic>{
      'villageIds': villageIds, // integers, not strings
      if (since != null)
        'lastSyncTime': since.toUtc().toIso8601String(),
      if (userId != null) 'userId': userId,
      'appVersionName': _appVersionName,
      'appVersionCode': _appVersionCode,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
      'appType': _appType,
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

  /// Syncs households and members from spice-service to local SQLite.
  ///
  /// Fetches per static-data village so API-internal village/sub-village IDs
  /// (which differ from the static-data IDs the filter UI uses) can be replaced
  /// with the correct static-data IDs at storage time. Sub-village IDs are
  /// translated via a name→static-data-ID map fetched from the same static-data
  /// endpoint, since the two systems share names but not numeric IDs.
  Future<({int households, int members})> _syncHouseholdsAndMembers({
    required List<int> villageIds,
  }) async {
    if (_households == null || _members == null) {
      debugPrint('[OfflineSyncService] HouseholdDao/MemberDao not provided, skipping household sync');
      return (households: 0, members: 0);
    }

    // Build sub-village translation tables. The household/member APIs return
    // their own internal sub-village IDs (e.g. 26) which differ from the
    // static-data IDs (e.g. 238) that UserHierarchyService exposes and the
    // filter UI queries against. Two strategies:
    //   byName — match on sub-village name (when API returns a name field)
    //   byCode — match on static-data `code`/`referenceId` vs API's numeric ID
    final svMapping = await _fetchSubVillageMapping();

    int totalHouseholds = 0;
    int totalMembers = 0;

    try {
      const pageSize = 200;

      for (final staticVillageId in villageIds) {
        final staticVillageIdStr = staticVillageId.toString();

        // ── Fetch households for this static-data village ─────────────────
        int skip = 0;
        final batchHouseholds = <HouseholdEntity>[];
        // household FHIR ID → translated static-data sub-village ID,
        // for enriching members that share the same household.
        final hhIdToStaticSvId = <String, String>{};

        while (true) {
          final body = <String, dynamic>{
            'skip': skip,
            'limit': pageSize,
            'tenantId': _api.tenantIdAsNum,
            'villageIds': [staticVillageId],
          };
          final resp = await _api.dio.post(Endpoints.householdList, data: body);
          final list = _extractList(resp.data);
          if (list.isEmpty) break;

          for (final raw in list) {
            if (raw is! Map) continue;
            final rawMap = Map<String, dynamic>.from(raw);

            // Translate sub-village: name match first, then code match.
            final svName = _firstNonEmpty(rawMap, const ['subVillage', 'subVillageName', 'sub_village_name'])
                ?.toLowerCase();
            final apiSvId = _firstNonEmpty(rawMap, const ['subVillageId', 'sub_village_id']);
            final staticSvId = (svName != null ? svMapping.byName[svName] : null)
                ?? (apiSvId != null ? svMapping.byCode[apiSvId] : null)
                ?? apiSvId;

            // Override API-internal village ID with the static-data ID we
            // used for the request — all returned rows belong to this village.
            rawMap['villageId'] = staticVillageIdStr;
            rawMap['village_id'] = staticVillageIdStr;

            final hh = HouseholdEntity.fromApiJson(rawMap);
            if (hh.id.isEmpty) continue;
            batchHouseholds.add(hh);
            if (staticSvId != null) hhIdToStaticSvId[hh.id] = staticSvId;

            if (batchHouseholds.length == 1) {
              debugPrint(
                '[OfflineSyncService] Sample household: id=${hh.id} '
                'villageId=$staticVillageIdStr apiSvId=$apiSvId svName=$svName '
                'staticSvId=$staticSvId allKeys=${rawMap.keys.toList()}',
              );
            }
          }

          _emitProgress(SyncProgress(
            currentStep: SyncStep.fetchingPatients,
            entityName: 'households',
            itemsDone: totalHouseholds + batchHouseholds.length,
          ));

          if (list.length < pageSize) break;
          if (list.length > pageSize) break;
          skip += pageSize;
        }

        await _households!.upsertMany(batchHouseholds);
        totalHouseholds += batchHouseholds.length;
        debugPrint('[OfflineSyncService] Synced ${batchHouseholds.length} households for village $staticVillageIdStr');

        // ── Fetch members for this static-data village ────────────────────
        skip = 0;
        final batchMembers = <HouseholdMemberEntity>[];

        _emitProgress(SyncProgress(
          currentStep: SyncStep.fetchingPatients,
          entityName: 'members',
          itemsDone: totalHouseholds,
        ));

        while (true) {
          final body = <String, dynamic>{
            'skip': skip,
            'limit': pageSize,
            'tenantId': _api.tenantIdAsNum,
            'villageIds': [staticVillageId],
          };
          final resp = await _api.dio.post(Endpoints.householdMemberList, data: body);
          final list = _extractList(resp.data);
          if (list.isEmpty) break;

          for (final raw in list) {
            if (raw is! Map) continue;
            final rawMap = Map<String, dynamic>.from(raw);

            // Translate sub-village: name match, then code match, then household map.
            final svName = _firstNonEmpty(rawMap, const ['subVillage', 'subVillageName', 'sub_village_name'])
                ?.toLowerCase();
            final apiSvId = _firstNonEmpty(rawMap, const ['subVillageId', 'sub_village_id']);
            final nameOrCodeSvId = (svName != null ? svMapping.byName[svName] : null)
                ?? (apiSvId != null ? svMapping.byCode[apiSvId] : null);

            // Override API-internal village ID.
            rawMap['villageId'] = staticVillageIdStr;
            rawMap['village_id'] = staticVillageIdStr;

            var m = HouseholdMemberEntity.fromApiJson(rawMap);
            if (m.id.isEmpty) continue;

            // Apply translated sub-village ID:
            //   1. name/code translation (most reliable)
            //   2. household-level translated ID (propagated from hhIdToStaticSvId)
            //   3. raw API sub-village ID (last resort — filter won't match but at least stored)
            final effectiveSvId = nameOrCodeSvId
                ?? (m.householdId != null ? hhIdToStaticSvId[m.householdId!] : null)
                ?? m.subVillageId;
            if (effectiveSvId != m.subVillageId) {
              m = m.copyWithVillage(subVillageId: effectiveSvId);
            }

            // Enrich shasthya_shebika_id when absent.
            if (m.shasthyaShebikaId == null) {
              final ssObj = raw['shasthyaShebika'];
              final ssRaw = raw['shasthyaShebikaId']
                  ?? (ssObj is Map ? ssObj['id'] : null)
                  ?? raw['ssId'];
              final ssId = ssRaw?.toString();
              if (ssId != null && ssId.isNotEmpty) {
                m = m.copyWithVillage(shasthyaShebikaId: ssId);
              }
            }

            if (batchMembers.isEmpty) {
              debugPrint(
                '[OfflineSyncService] Sample member: id=${m.id} '
                'villageId=${m.villageId} apiSvId=$apiSvId svName=$svName '
                'staticSvId=${m.subVillageId} allKeys=${rawMap.keys.toList()}',
              );
            }

            batchMembers.add(m);
          }

          _emitProgress(SyncProgress(
            currentStep: SyncStep.fetchingPatients,
            entityName: 'members',
            itemsDone: totalMembers + batchMembers.length,
          ));

          if (list.length < pageSize) break;
          if (list.length > pageSize) break;
          skip += pageSize;
        }

        await _members!.upsertMany(batchMembers);
        totalMembers += batchMembers.length;
        debugPrint(
          '[OfflineSyncService] Synced ${batchMembers.length} members for village $staticVillageIdStr '
          '(villageId populated: ${batchMembers.where((m) => m.villageId != null).length}, '
          'subVillageId populated: ${batchMembers.where((m) => m.subVillageId != null).length})',
        );

        // Push translated sub_village_id to ALL members in these households —
        // including bundle-synced rows whose primary keys differ from the
        // household/member list rows (so upsertMany alone can't reach them).
        if (hhIdToStaticSvId.isNotEmpty) {
          await _members!.propagateSubVillageFromMap(hhIdToStaticSvId);
        }
      }

      // SQL JOIN: overwrites bundle's API-internal village_id (e.g. 5) with
      // the static-data village_id (e.g. 26) now held by the households table.
      // No IS NULL guard — unconditional so bundle rows are always corrected.
      await _members!.propagateVillageFromHouseholdTable();

    } catch (e) {
      debugPrint('[OfflineSyncService] Household/member sync error: $e');
    }

    return (households: totalHouseholds, members: totalMembers);
  }

  /// Returns the first non-empty string value found under [keys] in [raw].
  static String? _firstNonEmpty(Map raw, List<String> keys) {
    for (final k in keys) {
      final v = raw[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  /// Fetches the static-data endpoint and builds two lookup tables for
  /// translating API-internal sub-village IDs to the static-data IDs that
  /// UserHierarchyService exposes and the filter UI queries against.
  ///
  /// Returns `({byName, byCode})`:
  ///  - `byName`: lowercased sub-village name → static-data ID
  ///  - `byCode`: `code` / `referenceId` / any string field that may hold the
  ///    API-internal ID → static-data ID (used when the API returns only the
  ///    internal ID and a name field is absent)
  Future<({Map<String, String> byName, Map<String, String> byCode})>
      _fetchSubVillageMapping() async {
    final byName = <String, String>{};
    final byCode = <String, String>{};
    try {
      final resp = await _api.dio.post(Endpoints.staticUserData);
      final data = resp.data;
      Map<String, dynamic> entity;
      if (data is Map && data['entity'] is Map) {
        entity = Map<String, dynamic>.from(data['entity'] as Map);
      } else if (data is Map) {
        entity = Map<String, dynamic>.from(data);
      } else {
        return (byName: byName, byCode: byCode);
      }
      final svRaw = entity['subVillages'];
      if (svRaw is! List) return (byName: byName, byCode: byCode);

      int loggedSample = 0;
      for (final sv in svRaw.whereType<Map>()) {
        final id = sv['id']?.toString();
        if (id == null || id.isEmpty) continue;

        // Name map — used when household/member API returns a sub-village name.
        final name = sv['name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          byName[name.toLowerCase()] = id;
        }

        // Code map — `code` often holds the API's internal numeric ID, which
        // is a different ID space from the static-data `id`. Also try
        // `referenceId` as an alternative cross-reference field.
        for (final field in const ['code', 'referenceId', 'fhirId']) {
          final v = sv[field]?.toString().trim();
          if (v != null && v.isNotEmpty) byCode[v] = id;
        }

        // Log first 3 samples — surface every cross-reference field available.
        if (loggedSample < 3) {
          loggedSample++;
          debugPrint(
            '[OfflineSyncService] Static-data SV sample #$loggedSample: '
            'id=$id name=$name code=${sv['code']} referenceId=${sv['referenceId']} '
            'fhirId=${sv['fhirId']} allFields=${Map.fromEntries(sv.entries.map((e) => MapEntry(e.key, e.value?.toString())))}',
          );
        }
      }
      debugPrint(
        '[OfflineSyncService] Sub-village maps: '
        'byName=${byName.length} byCode=${byCode.length}',
      );
    } catch (e) {
      debugPrint('[OfflineSyncService] Sub-village mapping fetch failed: $e');
    }
    return (byName: byName, byCode: byCode);
  }

  Future<_PersistTotals> _persistBundle(
    Map<String, dynamic> bundle, {
    int? ownerUserId,
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

    // ── Parse households from bundle (Android: ResponseInitialDownload) ────
    final households = <HouseholdEntity>[];

    // Build referenceId → {villageId, subVillageId} BEFORE fromApiJson discards
    // the referenceId field. Member.householdId references the household's
    // referenceId (small internal ID), not the FHIR ID stored as
    // HouseholdEntity.id. We use this map to propagate village data to members
    // whose village_id is absent from the bundle payload.
    final hhRefToVillage = <String, String>{};
    final hhRefToSubVillage = <String, String>{};

    for (final raw in householdNodes) {
      if (raw is! Map) continue;
      final rawMap = Map<String, dynamic>.from(raw);
      final hh = HouseholdEntity.fromApiJson(rawMap);
      if (hh.id.isNotEmpty) households.add(hh);

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
      '(${hhRefToVillage.length} with referenceId→village mapping)',
    );

    // ── Parse members from bundle (Android: ResponseInitialDownload) ────────
    // Members table stays village-wide so the household screen can render the
    // full roster; ownership filtering is applied separately when bridging
    // into the patients table below.
    final members = <HouseholdMemberEntity>[];
    final ownedMemberIds = <String>{};
    for (final raw in memberNodes) {
      if (raw is! Map) continue;
      var m = HouseholdMemberEntity.fromApiJson(Map<String, dynamic>.from(raw));
      if (m.id.isEmpty) continue;

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
    // When we know who the SK is, keep only members whose `shasthyaKormiId`
    // matches — every village member arrives in the bundle, but the
    // dashboard worklist must reflect the SK's own caseload.
    if (patients.isEmpty && members.isNotEmpty) {
      debugPrint(
        '[OfflineSyncService] Bridge filter: ownerUserId=$ownerUserId, '
        'ownedMemberIds=${ownedMemberIds.length}/${members.length}',
      );
      final bridgeSource = ownedMemberIds.isNotEmpty
          ? members.where((m) => ownedMemberIds.contains(m.id))
          : members;
      if (ownedMemberIds.isEmpty && ownerUserId != null) {
        debugPrint(
          '[OfflineSyncService] WARNING: No members matched shasthyaKormiId=$ownerUserId. '
          'Bridging all ${members.length} members to patients table.',
        );
      }
      for (final m in bridgeSource) {
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
      final facts = _pregnancyFactsFrom(raw, now: now);
      if (facts == null) continue;
      pregnancyRows.add(PregnancySnapshotRow(
        patientId: patientId,
        facts: facts,
        updatedAt: nowMs,
      ));
    }

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

    // Upsert patients instead of clear+insert to preserve patients fetched
    // via refreshPatient() (e.g., searched patients outside SK's caseload).
    // The upsert handles both new inserts and updates to existing rows.
    await _patients.upsertMany(patients);
    for (final entry in programmes.entries) {
      await _programmes.replaceFor(entry.key, entry.value);
    }
    await _followUps.upsertMany(followUps);
    await _immunisations.upsertMany(immunisations);
    await _assessments.upsertMany(assessments);

    // Persist households and members if found in bundle and DAOs are available
    if (households.isNotEmpty && _households != null) {
      await _households!.upsertMany(households);
    }
    if (members.isNotEmpty && _members != null) {
      await _members!.upsertMany(members);
    }

    // Back-propagate village data via in-memory map (handles rows saved by
    // earlier syncs without enrichment). Idempotent — already-set rows skipped.
    if (_members != null && hhRefToVillage.isNotEmpty) {
      await _members!.propagateVillageFromHouseholds(
        hhRefToVillage,
        hhRefToSubVillage: hhRefToSubVillage,
      );
    }

    // SQL JOIN fallback: use households.village_id (populated by the
    // _syncHouseholdsAndMembers call that runs after _persistBundle on cold
    // sync) to fill any remaining member rows with null village_id.
    if (_members != null) {
      await _members!.propagateVillageFromHouseholdTable();
    }

    // Mission Dashboard side tables (schema v8). Replace-then-write so a
    // re-sync drops stale per-patient flags.
    if (_pregnancySnapshot != null) {
      await _pregnancySnapshot!.clearAll();
      if (pregnancyRows.isNotEmpty) {
        await _pregnancySnapshot!.upsertMany(pregnancyRows);
      }
    }
    if (_treatmentPresence != null) {
      await _treatmentPresence!.clearAll();
      if (treatmentPatientIds.isNotEmpty) {
        await _treatmentPresence!
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
      villageId: m.villageId,
      isActive: m.isActive,
      updatedAt: m.updatedAt,
      rawJson: m.rawJson ?? '{}',
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

  /// Sync referrals from the backend. Tries fhir-mapper first,
  /// falls back to direct FHIR queries if mapper fails or returns empty.
  Future<int> _syncReferrals({required List<int> villageIds}) async {
    try {
      debugPrint('[OfflineSyncService] Syncing referrals for ${villageIds.length} villages...');
      
      // Try bulk fetch by villageIds first (via fhir-mapper)
      List referralNodes = [];
      try {
        final body = <String, dynamic>{
          'villageIds': villageIds,
          'tenantId': _api.tenantIdAsNum,
          'limit': 1000,
        };
        final resp = await _api.dio.post(
          Endpoints.fhirReferralTicketList,
          data: body,
        );
        referralNodes = _extractList(resp.data);
        debugPrint('[OfflineSyncService] Fetched ${referralNodes.length} referrals by villageIds');
      } catch (e) {
        debugPrint('[OfflineSyncService] Bulk referral fetch failed: $e');
      }
      
      if (referralNodes.isEmpty) {
        debugPrint('[OfflineSyncService] No referrals to sync');
        return 0;
      }
      
      // Parse and persist referrals
      final referrals = <Referral>[];
      for (final raw in referralNodes) {
        if (raw is! Map) continue;
        final referral = _referralFromPayload(Map<String, Object?>.from(raw));
        if (referral != null) {
          referrals.add(referral);
        }
      }
      
      if (referrals.isNotEmpty) {
        await _referrals.upsertMany(referrals);
        debugPrint('[OfflineSyncService] Persisted ${referrals.length} referrals');
      }
      
      return referrals.length;
    } catch (e) {
      debugPrint('[OfflineSyncService] Referral sync error: $e');
      return 0;
    }
  }

  /// Fetch referrals directly from FHIR server (bypasses fhir-mapper bugs).
  Future<List<Map<String, dynamic>>> _fetchReferralsFromFhir(List<int> villageIds) async {
    final allReferrals = <Map<String, dynamic>>[];
    
    try {
      // First try: query by village identifier (doesn't require local patient DB)
      debugPrint('[OfflineSyncService] Querying FHIR ServiceRequests for ${villageIds.length} villages...');
      
      // Query ServiceRequests by village identifier
      for (final villageId in villageIds.take(20)) { // Limit to first 20 villages
        try {
          final resp = await _api.dio.get(
            Endpoints.fhirServiceRequestByVillage(villageId.toString()),
          );
          final parsed = _parseFhirServiceRequests(resp.data, '');
          allReferrals.addAll(parsed);
        } catch (_) {
          // Continue with next village
        }
      }
      
      if (allReferrals.isNotEmpty) {
        debugPrint('[OfflineSyncService] Found ${allReferrals.length} ServiceRequests from FHIR villages');
        return allReferrals;
      }
      
      // Second try: if no results by village, try by patient IDs from local DB
      final patients = await _patients.allForVillages(const <String>[]);
      if (patients.isEmpty) {
        debugPrint('[OfflineSyncService] No patients in DB to query referrals for');
        return [];
      }
      
      debugPrint('[OfflineSyncService] Querying FHIR ServiceRequests for ${patients.length} patients...');
      
      // Query ServiceRequests for each patient (batched)
      const batchSize = 10;
      for (var i = 0; i < patients.length; i += batchSize) {
        final batch = patients.sublist(
          i,
          i + batchSize > patients.length ? patients.length : i + batchSize,
        );
        
        final futures = batch.map((p) async {
          try {
            final resp = await _api.dio.get(
              Endpoints.fhirServiceRequestByPatient(p.id),
            );
            return _parseFhirServiceRequests(resp.data, p.id);
          } catch (_) {
            return <Map<String, dynamic>>[];
          }
        });
        
        final results = await Future.wait(futures);
        for (final list in results) {
          allReferrals.addAll(list);
        }
      }
      
      debugPrint('[OfflineSyncService] Found ${allReferrals.length} ServiceRequests from FHIR');
    } catch (e) {
      debugPrint('[OfflineSyncService] Direct FHIR query failed: $e');
    }
    
    return allReferrals;
  }

  /// Parse FHIR Bundle of ServiceRequests into referral payload format.
  List<Map<String, dynamic>> _parseFhirServiceRequests(dynamic data, String patientId) {
    final referrals = <Map<String, dynamic>>[];
    
    if (data is! Map) return referrals;
    
    final entries = data['entry'] as List? ?? [];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final resource = entry['resource'] as Map?;
      if (resource == null || resource['resourceType'] != 'ServiceRequest') continue;
      
      // Extract patient ID from subject reference if not provided
      String effectivePatientId = patientId;
      if (effectivePatientId.isEmpty) {
        final subject = resource['subject'] as Map?;
        final ref = subject?['reference'] as String? ?? '';
        if (ref.contains('Patient/')) {
          effectivePatientId = ref.split('Patient/').last;
        }
      }
      
      // Extract identifiers
      String? villageId;
      String? patientStatus;
      final identifiers = resource['identifier'] as List? ?? [];
      for (final ident in identifiers) {
        if (ident is! Map) continue;
        final system = ident['system'] as String? ?? '';
        final value = ident['value'] as String?;
        if (system.contains('village-id')) villageId = value;
        if (system.contains('patient-status')) patientStatus = value;
      }
      
      // Skip if no patient ID
      if (effectivePatientId.isEmpty) continue;
      
      // Map FHIR ServiceRequest to referral payload format
      referrals.add({
        'id': resource['id']?.toString(),
        'fhirId': resource['id']?.toString(),
        'patientId': effectivePatientId,
        'memberId': effectivePatientId,
        'villageId': villageId,
        'patientStatus': patientStatus ?? resource['status']?.toString() ?? 'active',
        'referredReason': resource['code']?['text'] ?? 
            (resource['reasonCode'] as List?)?.firstOrNull?['text'] ?? 'Referral',
        'referredTo': 'District Hospital',
        'referredDate': resource['authoredOn']?.toString(),
        'status': resource['status']?.toString() ?? 'active',
      });
    }
    
    return referrals;
  }

  /// Fallback: fetch referrals for each patient in the local DB.
  Future<List> _fetchReferralsForAllPatients() async {
    try {
      // Get all patient IDs from local DB
      final patients = await _patients.allForVillages(const []);
      if (patients.isEmpty) return [];
      
      debugPrint('[OfflineSyncService] Fetching referrals for ${patients.length} patients...');
      
      final allReferrals = <dynamic>[];
      // Batch the requests to avoid overwhelming the server
      const batchSize = 20;
      for (var i = 0; i < patients.length; i += batchSize) {
        final batch = patients.sublist(
          i,
          i + batchSize > patients.length ? patients.length : i + batchSize,
        );
        
        // Fetch referrals for each patient in the batch in parallel
        final futures = batch.map((p) async {
          try {
            final body = <String, dynamic>{
              'patientId': p.id,
              'tenantId': _api.tenantIdAsNum,
            };
            final resp = await _api.dio.post(
              Endpoints.fhirReferralTicketList,
              data: body,
            );
            return _extractList(resp.data);
          } catch (_) {
            return <dynamic>[];
          }
        });
        
        final results = await Future.wait(futures);
        for (final list in results) {
          allReferrals.addAll(list);
        }
      }
      
      debugPrint('[OfflineSyncService] Fetched ${allReferrals.length} referrals from patients');
      return allReferrals;
    } catch (e) {
      debugPrint('[OfflineSyncService] Per-patient referral fetch error: $e');
      return [];
    }
  }

  /// Parse a referral from the fhir-mapper payload.
  Referral? _referralFromPayload(Map<String, Object?> p) {
    final id = JsonRead.firstString(p, const ['id', 'referralId', 'fhirId']);
    if (id == null || id.isEmpty) return null;
    
    final patientId = JsonRead.firstString(p, const ['memberId', 'patientId', 'householdMemberId']);
    if (patientId == null || patientId.isEmpty) return null;
    
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tier = _inferTier(p['referredReason'] as String?);
    // Derive initial priority level from SLA tier
    final priorityLevel = switch (tier) {
      SlaTier.emergency => SlaPriority.critical.wireTag,
      SlaTier.urgent => SlaPriority.high.wireTag,
      SlaTier.routine => SlaPriority.low.wireTag,
    };
    return Referral(
      id: id,
      patientId: patientId,
      slaTier: tier,
      diagnosisLabel: p['referredReason'] as String?,
      state: ReferralStatus.fromWireTag(p['patientStatus'] as String?),
      priorityLevel: priorityLevel,
      priorityScore: tier == SlaTier.emergency ? 100 : (tier == SlaTier.urgent ? 60 : 30),
      createdAt: _parseDateMs(p['referredDate']) ?? ts,
      updatedAt: ts,
      rawJson: jsonEncode(p),
    );
  }

  /// Infer SLA tier from referred reason (diagnosis).
  static SlaTier _inferTier(String? reason) {
    if (reason == null) return SlaTier.routine;
    final r = reason.toLowerCase();
    if (r.contains('emergency') || r.contains('critical') || r.contains('severe')) {
      return SlaTier.emergency;
    }
    if (r.contains('urgent') || r.contains('high') || r.contains('danger')) {
      return SlaTier.urgent;
    }
    return SlaTier.routine;
  }

  /// Parse date from various formats to epoch milliseconds.
  static int? _parseDateMs(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
      final ms = int.tryParse(raw);
      if (ms != null) return ms;
    }
    return null;
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
    
    // Also sync referrals in fallback mode
    final referralCount = await _syncReferrals(villageIds: villageIds);
    
    final report = SyncReport(
      startedAt: started,
      finishedAt: DateTime.now(),
      patients: patients.length,
      referrals: referralCount,
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
    // Use integer villageIds to match Android RequestAllEntities format
    final body = <String, dynamic>{
      'villageIds': villageIds,
      'skip': 0,
      'limit': 1000,
      'tenantId': _api.tenantIdAsNum,
      'currentSyncTime': DateTime.now().toUtc().toIso8601String(),
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

  @override
  /// Calls `POST /spice-service/static-data/user-data`, extracts village IDs,
  /// persists them via [AuthRepository.saveLinkedVillageIds], and returns the
  /// list. Returns an empty list if the endpoint fails or returns no villages.
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
      final villagesRaw = entity['villages'];
      if (villagesRaw is! List) return const [];
      final ids = villagesRaw
          .whereType<Map>()
          .map((m) {
            final id = m['id'];
            if (id is int) return id;
            if (id is num) return id.toInt();
            if (id is String) return int.tryParse(id);
            return null;
          })
          .whereType<int>()
          .toList();
      if (ids.isNotEmpty) {
        await _auth.saveLinkedVillageIds(ids);
        debugPrint('[OfflineSyncService] Fetched ${ids.length} village IDs from static-data fallback');
      }
      return ids;
    } catch (e) {
      debugPrint('[OfflineSyncService] static-data fallback failed: $e');
      return const [];
    }
  }

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

