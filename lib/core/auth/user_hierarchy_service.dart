import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';
import '../db/health_facility_dao.dart';
import 'auth_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models — all fields nullable-safe; fromJson handles missing/wrong types.
// ─────────────────────────────────────────────────────────────────────────────

/// SS worker (Shasthya Shebika) assigned under the logged-in SK.
class SsWorker {
  const SsWorker({
    required this.id,
    required this.name,
    this.phoneNumber,
    this.ssId,
    this.subVillages = const [],
  });

  final String id;
  final String name;
  final String? phoneNumber;
  final String? ssId;

  /// Sub-villages explicitly assigned to this SS (from nested `subVillages`).
  final List<SubVillageRef> subVillages;

  factory SsWorker.fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final svRaw = json['subVillages'];
    final subVillages = (svRaw is List)
        ? svRaw
            .whereType<Map>()
            .map((m) => SubVillageRef.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <SubVillageRef>[];

    return SsWorker(
      id: (json['id'] ?? '').toString(),
      name: str('name') ?? str('firstName') ?? 'SS ${json['id']}',
      phoneNumber: str('phoneNumber'),
      ssId: str('ssId'),
      subVillages: subVillages,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (ssId != null) 'ssId': ssId,
        'subVillages': subVillages.map((sv) => sv.toJson()).toList(),
      };
}

/// Sub-village reference — used both as a nested SS assignment and in the
/// top-level `subVillages` list from the static-data response.
class SubVillageRef {
  const SubVillageRef({
    required this.id,
    required this.name,
    this.villageId,
    this.code,
  });

  final String id;
  final String name;

  /// Parent village ID — used for village → sub-village cascade filtering.
  final String? villageId;
  final String? code;

  factory SubVillageRef.fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return SubVillageRef(
      id: (json['id'] ?? '').toString(),
      name: str('name') ?? (json['id'] ?? '').toString(),
      villageId: str('villageId'),
      code: str('code'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (villageId != null) 'villageId': villageId,
        if (code != null) 'code': code,
      };
}

/// Village assigned to the SK — top-level entry from `villages[]` in the
/// static-data response. `id` maps to LINKED_VILLAGE_IDS for offline sync.
class VillageRef {
  const VillageRef({
    required this.id,
    required this.name,
    this.code,
  });

  final String id;
  final String name;
  final String? code;

  int? get idAsInt => int.tryParse(id);

  factory VillageRef.fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return VillageRef(
      id: (json['id'] ?? '').toString(),
      name: str('name') ?? str('villageName') ?? (json['id'] ?? '').toString(),
      code: str('code'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (code != null) 'code': code,
      };
}

/// SK profile snapshot from `userProfile` in the static-data response.
class SkProfile {
  const SkProfile({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.fhirId,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? fhirId;

  factory SkProfile.fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final first = str('firstName') ?? '';
    final last = str('lastName') ?? '';
    final fullName = [first, last].where((s) => s.isNotEmpty).join(' ');

    return SkProfile(
      id: (json['id'] ?? '').toString(),
      name: str('name') ?? (fullName.isNotEmpty ? fullName : 'SK ${json['id']}'),
      phone: str('phoneNumber'),
      email: str('email') ?? str('username'),
      fhirId: str('fhirId'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (phone != null) 'phoneNumber': phone,
        if (email != null) 'email': email,
        if (fhirId != null) 'fhirId': fhirId,
      };
}

/// Health facility reference from `defaultHealthFacility` /
/// `userHealthFacilities[]` in the static-data response.
class HealthFacilityRef {
  const HealthFacilityRef({
    required this.id,
    required this.name,
    this.fhirId,
    this.tenantId,
  });

  final String id;
  final String name;
  final String? fhirId;
  final String? tenantId;

  factory HealthFacilityRef.fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return HealthFacilityRef(
      id: (json['id'] ?? '').toString(),
      name: str('name') ?? str('facilityName') ?? (json['id'] ?? '').toString(),
      fhirId: str('fhirId'),
      tenantId: str('tenantId'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (fhirId != null) 'fhirId': fhirId,
        if (tenantId != null) 'tenantId': tenantId,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

/// Server-side feature flags fetched from `GET /ai-scribe/config` after login.
///
/// All flags default to the safe/off position so an unreachable server never
/// enables a half-baked feature on-device.
class FeatureFlags {
  const FeatureFlags({this.voiceSampleCollectionEnabled = false});

  factory FeatureFlags.fromJson(Map<String, dynamic> json) => FeatureFlags(
        voiceSampleCollectionEnabled:
            json['voice_sample_collection_enabled'] as bool? ?? false,
      );

  /// Whether raw audio should be staged for backend training analysis.
  final bool voiceSampleCollectionEnabled;

  static const FeatureFlags defaults = FeatureFlags();
}

/// Fetches and caches the full static-data hierarchy from
/// `POST /spice-service/static-data/user-data`.
///
/// One HTTP call returns:
///   - SK profile (`userProfile`)
///   - Assigned villages (`villages[]`) → persisted as LINKED_VILLAGE_IDS
///   - Assigned sub-villages (`subVillages[]`) — top-level flat list
///   - SS workers (`shasthyaShebikas[]`) — each with nested `subVillages`
///   - Assigned workflow IDs (`workflowIds[]`)
///   - Default health facility (`defaultHealthFacility`)
///
/// Session memory is the fast path; a durable snapshot is also written to
/// secure storage so cold start / offline PIN unlock can still populate
/// enrollment SS and Village dropdowns. Call [invalidate] after logout
/// (disk cache is cleared with logout).
///
/// [prefetch] is the preferred entry-point — call it once after login so all
/// downstream getters are guaranteed to return without a network round-trip.
class UserHierarchyService extends ChangeNotifier {
  UserHierarchyService(
    this._api,
    this._auth, {
    HealthFacilityDao? healthFacilities,
  }) : _healthFacilities = healthFacilities;

  final ApiClient _api;
  final AuthRepository _auth;
  final HealthFacilityDao? _healthFacilities;

  List<SsWorker>? _ssWorkers;
  List<VillageRef>? _villages;
  List<SubVillageRef>? _subVillages;
  SkProfile? _skProfile;
  List<int> _workflowIds = const [];
  HealthFacilityRef? _defaultFacility;
  FeatureFlags _featureFlags = FeatureFlags.defaults;
  bool _loading = false;
  String? _error;

  /// True after a successful network parse or a successful disk hydrate.
  /// Failed network with no disk cache leaves this false so prefetch retries.
  bool _ready = false;

  // Inflight future — prevents duplicate HTTP calls when multiple callers
  // await the service concurrently before the first fetch completes.
  Future<void>? _inflightFetch;

  List<SsWorker>? get ssWorkers => _ssWorkers;
  List<VillageRef>? get villages => _villages;
  List<SubVillageRef>? get subVillages => _subVillages;
  SkProfile? get skProfile => _skProfile;
  List<int> get workflowIds => _workflowIds;
  HealthFacilityRef? get defaultFacility => _defaultFacility;
  FeatureFlags get featureFlags => _featureFlags;
  bool get loading => _loading;
  String? get error => _error;

  /// Ensures data is loaded. Safe to call multiple times — only one attempt
  /// (network, with disk fallback) runs until [invalidate] or [forceRefresh].
  Future<void> prefetch({bool forceRefresh = false}) async {
    if (!forceRefresh && _ready) return;
    _inflightFetch ??= _doFetch(forceRefresh: forceRefresh)
        .whenComplete(() => _inflightFetch = null);
    await _inflightFetch;
  }

  /// Returns the SS list, fetching if not yet loaded.
  Future<List<SsWorker>> getSsWorkers({bool forceRefresh = false}) async {
    await prefetch(forceRefresh: forceRefresh);
    return _ssWorkers ?? const [];
  }

  /// Returns top-level village list assigned to the SK.
  Future<List<VillageRef>> getVillages({bool forceRefresh = false}) async {
    await prefetch(forceRefresh: forceRefresh);
    return _villages ?? const [];
  }

  /// Returns top-level sub-village list assigned to the SK.
  Future<List<SubVillageRef>> getSubVillages({bool forceRefresh = false}) async {
    await prefetch(forceRefresh: forceRefresh);
    return _subVillages ?? const [];
  }

  Future<void> _doFetch({bool forceRefresh = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final resp = await _api.dio.post(Endpoints.staticUserData);
      final data = resp.data;

      // Response shape: { "entity": { ... } } or flat { ... }
      Map<String, dynamic> entity;
      if (data is Map && data['entity'] is Map) {
        entity = Map<String, dynamic>.from(data['entity'] as Map);
      } else if (data is Map) {
        entity = Map<String, dynamic>.from(data);
      } else {
        entity = const {};
      }

      _applyEntity(entity);
      await _persistSideEffectsFromNetwork(entity);
      await _persistHierarchyCache();
      _ready = true;
      // Fire-and-forget: flags failure must never fail the hierarchy load.
      unawaited(_fetchFeatureFlags());

      debugPrint(
          '[UserHierarchyService] Loaded: ${_ssWorkers!.length} SS, '
          '${_villages!.length} villages, ${_subVillages!.length} sub-villages, '
          '${_workflowIds.length} workflows');
    } catch (e) {
      _error = e.toString();
      debugPrint('[UserHierarchyService] Fetch failed: $e');
      final hydrated = await _hydrateFromDisk();
      if (hydrated) {
        _ready = true;
        _error = null;
        debugPrint(
            '[UserHierarchyService] Hydrated from disk cache: '
            '${_ssWorkers?.length ?? 0} SS, '
            '${_villages?.length ?? 0} villages, '
            '${_subVillages?.length ?? 0} sub-villages');
      } else if (forceRefresh) {
        // Explicit refresh failed and no disk — keep prior memory if any.
        _ready = _ssWorkers != null;
      } else {
        // Leave lists null and _ready false so a later prefetch can retry
        // (e.g. network returns after a cold offline open).
        _ready = false;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _applyEntity(Map<String, dynamic> entity) {
    // ── SS workers ───────────────────────────────────────────────────────
    final ssRaw = entity['shasthyaShebikas'] ?? entity['ssWorkers'];
    _ssWorkers = (ssRaw is List)
        ? ssRaw
            .whereType<Map>()
            .map((m) => SsWorker.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : const [];

    // ── Top-level villages ───────────────────────────────────────────────
    final villagesRaw = entity['villages'];
    _villages = (villagesRaw is List)
        ? villagesRaw
            .whereType<Map>()
            .map((m) => VillageRef.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : const [];

    // ── Top-level sub-villages ───────────────────────────────────────────
    final svRaw = entity['subVillages'];
    _subVillages = (svRaw is List)
        ? svRaw
            .whereType<Map>()
            .map((m) => SubVillageRef.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : const [];

    // ── SK profile ───────────────────────────────────────────────────────
    final profileRaw = entity['userProfile'] ?? entity['skProfile'];
    if (profileRaw is Map) {
      _skProfile = SkProfile.fromJson(Map<String, dynamic>.from(profileRaw));
    }

    // ── Workflow IDs ─────────────────────────────────────────────────────
    final wfRaw = entity['workflowIds'];
    _workflowIds = (wfRaw is List)
        ? wfRaw.whereType<num>().map((n) => n.toInt()).toList()
        : const [];

    // ── Default health facility ──────────────────────────────────────────
    final facRaw = entity['defaultHealthFacility'] ?? entity['defaultFacility'];
    if (facRaw is Map) {
      _defaultFacility =
          HealthFacilityRef.fromJson(Map<String, dynamic>.from(facRaw));
    }
  }

  /// Network-only side effects that must run after a live user-data parse.
  Future<void> _persistSideEffectsFromNetwork(Map<String, dynamic> entity) async {
    String? upazilaName;
    final chiefsRaw = entity['chiefdoms'];
    debugPrint('[UserHierarchyService] chiefdoms raw: $chiefsRaw');
    if (chiefsRaw is List && chiefsRaw.isNotEmpty) {
      final first = chiefsRaw.first;
      if (first is Map) {
        final v = first['name'];
        if (v != null) upazilaName = v.toString().trim();
      }
    }
    debugPrint('[UserHierarchyService] upazila → $upazilaName');
    await _auth.saveUpazila(upazilaName);

    // ── Persist LINKED_VILLAGE_IDS for offline sync ──────────────────────
    // Mirror Android MetaRepository: use sub-villages nested within each
    // SS worker (shasthyaShebikas[].subVillages) as the primary scope —
    // these are the most specific IDs and match exactly what the server
    // used when it assigned data to this SK's caseload. Fall back to the
    // top-level `subVillages` list, then to `villages` only as a last
    // resort (village-level IDs return the entire village, not just this
    // SK's area, and produce oversized bundles).
    final ssSubIds = _ssWorkers!
        .expand((ss) => ss.subVillages)
        .map((sv) => int.tryParse(sv.id))
        .whereType<int>()
        .toList();
    final topSubIds = _subVillages!
        .map((sv) => int.tryParse(sv.id))
        .whereType<int>()
        .toList();
    final villageOnlyIds = _villages!
        .map((v) => v.idAsInt)
        .whereType<int>()
        .toList();
    final linkedIds = ssSubIds.isNotEmpty
        ? ssSubIds
        : (topSubIds.isNotEmpty ? topSubIds : villageOnlyIds);
    debugPrint(
        '[UserHierarchyService] villageId candidates: '
        'ssSubIds=${ssSubIds.length} topSubIds=${topSubIds.length} '
        'villageIds=${villageOnlyIds.length} → using ${linkedIds.length}');
    if (linkedIds.isNotEmpty) {
      await _auth.saveLinkedVillageIds(linkedIds);
    }

    // Persist SS worker IDs so OfflineSyncService can filter bundle
    // households by shasthyaShebikaId (mirrors Android caseload scoping).
    final ssIds = _ssWorkers!
        .map((ss) => int.tryParse(ss.id))
        .whereType<int>()
        .toList();
    if (ssIds.isNotEmpty) {
      await _auth.saveSsWorkerIds(ssIds);
    }
    debugPrint(
        '[UserHierarchyService] Saved ${ssIds.length} SS worker IDs: $ssIds');

    // Persist FHIR Practitioner ID and org FHIR ID so OfflineSyncService can
    // read them from AuthRepository without a second user-data call (P1).
    final userFhirId = _skProfile?.fhirId;
    if (userFhirId != null && userFhirId.isNotEmpty) {
      await _auth.saveUserFhirId(userFhirId);
      debugPrint('[UserHierarchyService] Saved userFhirId: $userFhirId');
    }
    final orgFhirId = _defaultFacility?.fhirId;
    if (orgFhirId != null && orgFhirId.isNotEmpty) {
      await _auth.saveOrganizationFhirId(orgFhirId);
      debugPrint('[UserHierarchyService] Saved orgFhirId: $orgFhirId');
    }

    // Android MetaRepository.saveHealthFacilityInDb — nearest + user sites
    // filtered by villages[].linkedVillages intersection, into SQLite.
    final facilitiesDao = _healthFacilities;
    if (facilitiesDao != null) {
      try {
        final n = await facilitiesDao.replaceFromUserDataEntity(entity);
        debugPrint(
          '[UserHierarchyService] Saved $n health facilities for referral spinner',
        );
      } on Object catch (e) {
        debugPrint('[UserHierarchyService] health facilities persist failed: $e');
      }
    }
  }

  Future<void> _persistHierarchyCache() async {
    final cache = <String, dynamic>{
      'ssWorkers': _ssWorkers!.map((s) => s.toJson()).toList(),
      'villages': _villages!.map((v) => v.toJson()).toList(),
      'subVillages': _subVillages!.map((sv) => sv.toJson()).toList(),
      'workflowIds': _workflowIds,
      if (_skProfile != null) 'skProfile': _skProfile!.toJson(),
      if (_defaultFacility != null)
        'defaultFacility': _defaultFacility!.toJson(),
    };
    await _auth.saveUserHierarchyCache(cache);
  }

  /// Returns true when disk cache populated in-memory lists.
  Future<bool> _hydrateFromDisk() async {
    final cache = await _auth.loadUserHierarchyCache();
    if (cache == null) return false;

    final ssRaw = cache['ssWorkers'];
    final villagesRaw = cache['villages'];
    final svRaw = cache['subVillages'];
    final hasSs = ssRaw is List && ssRaw.isNotEmpty;
    final hasVillages = villagesRaw is List && villagesRaw.isNotEmpty;
    final hasSubVillages = svRaw is List && svRaw.isNotEmpty;
    if (!hasSs && !hasVillages && !hasSubVillages) return false;

    _applyEntity(cache);
    // Disk hydrate must not wipe a soft network error used for diagnostics,
    // but enrollment only needs the lists.
    return true;
  }

  /// Fetches server-side feature flags from [Endpoints.aiScribeConfig].
  ///
  /// Non-fatal — any error is logged and the defaults (all flags off) remain.
  Future<void> _fetchFeatureFlags() async {
    try {
      // Use AI service base URL (not UHIS backend) — config lives on leapfrog-ai-services.
      final aiBase = AppConfig.scribeBaseUrl.replaceAll(RegExp(r'/+$'), '');
      // Strip /ai-scribe prefix when hitting the service directly (AI_SERVICE_URL set).
      const rawPath = Endpoints.aiScribeConfig;
      final configPath = AppConfig.aiServiceBaseUrl.isNotEmpty &&
              rawPath.startsWith('/ai-scribe')
          ? rawPath.substring('/ai-scribe'.length)
          : rawPath;
      debugPrint('[AudioSample] fetching feature flags from $aiBase$configPath');
      final tempDio = Dio(BaseOptions(
        baseUrl: aiBase,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final resp = await tempDio.get(configPath);
      final data = resp.data;
      if (data is Map) {
        _featureFlags = FeatureFlags.fromJson(Map<String, dynamic>.from(data));
        notifyListeners();
        debugPrint('[UserHierarchyService] FeatureFlags: '
            'voiceSampleCollection=${_featureFlags.voiceSampleCollectionEnabled}');
      }
    } catch (e) {
      debugPrint('[UserHierarchyService] _fetchFeatureFlags failed (non-fatal): $e');
    }
  }

  void invalidate() {
    _ssWorkers = null;
    _villages = null;
    _subVillages = null;
    _skProfile = null;
    _workflowIds = const [];
    _defaultFacility = null;
    _featureFlags = FeatureFlags.defaults;
    _error = null;
    _ready = false;
    _inflightFetch = null;
    // Disk clear is awaited in AuthRepository.logout(); this is a safety net
    // if invalidate is called without a full logout.
    _auth.clearUserHierarchyCache().ignore();
    notifyListeners();
  }
}
