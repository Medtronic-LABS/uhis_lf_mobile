import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

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
/// Read-through cache: first call hits the network; subsequent calls within
/// the same session return cached data. Call [invalidate] after logout.
///
/// [prefetch] is the preferred entry-point — call it once after login so all
/// downstream getters are guaranteed to return without a network round-trip.
class UserHierarchyService extends ChangeNotifier {
  UserHierarchyService(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  List<SsWorker>? _ssWorkers;
  List<VillageRef>? _villages;
  List<SubVillageRef>? _subVillages;
  SkProfile? _skProfile;
  List<int> _workflowIds = const [];
  HealthFacilityRef? _defaultFacility;
  bool _loading = false;
  String? _error;

  // Inflight future — prevents duplicate HTTP calls when multiple callers
  // await the service concurrently before the first fetch completes.
  Future<void>? _inflightFetch;

  bool get _fetched => _ssWorkers != null;

  List<SsWorker>? get ssWorkers => _ssWorkers;
  List<VillageRef>? get villages => _villages;
  List<SubVillageRef>? get subVillages => _subVillages;
  SkProfile? get skProfile => _skProfile;
  List<int> get workflowIds => _workflowIds;
  HealthFacilityRef? get defaultFacility => _defaultFacility;
  bool get loading => _loading;
  String? get error => _error;

  /// Ensures data is loaded. Safe to call multiple times — only one HTTP
  /// request fires per session regardless of concurrent callers.
  Future<void> prefetch({bool forceRefresh = false}) async {
    if (!forceRefresh && _fetched) return;
    _inflightFetch ??= _doFetch().whenComplete(() => _inflightFetch = null);
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

  Future<void> _doFetch() async {
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

      // ── SS workers ───────────────────────────────────────────────────────
      final ssRaw = entity['shasthyaShebikas'];
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
      final profileRaw = entity['userProfile'];
      if (profileRaw is Map) {
        _skProfile =
            SkProfile.fromJson(Map<String, dynamic>.from(profileRaw));
      }

      // ── Workflow IDs ─────────────────────────────────────────────────────
      final wfRaw = entity['workflowIds'];
      _workflowIds = (wfRaw is List)
          ? wfRaw.whereType<num>().map((n) => n.toInt()).toList()
          : const [];

      // ── Default health facility ──────────────────────────────────────────
      final facRaw = entity['defaultHealthFacility'];
      if (facRaw is Map) {
        _defaultFacility =
            HealthFacilityRef.fromJson(Map<String, dynamic>.from(facRaw));
      }

      // ── Persist LINKED_VILLAGE_IDS for offline sync ──────────────────────
      // These override the profile-derived village IDs so subsequent syncs
      // use exactly the villages from this endpoint (matches Android behaviour).
      final linkedIds = _villages!
          .map((v) => v.idAsInt)
          .whereType<int>()
          .toList();
      if (linkedIds.isNotEmpty) {
        await _auth.saveLinkedVillageIds(linkedIds);
      }

      debugPrint(
          '[UserHierarchyService] Loaded: ${_ssWorkers!.length} SS, '
          '${_villages!.length} villages, ${_subVillages!.length} sub-villages, '
          '${_workflowIds.length} workflows');
    } catch (e) {
      _error = e.toString();
      _ssWorkers ??= const [];
      _villages ??= const [];
      _subVillages ??= const [];
      debugPrint('[UserHierarchyService] Fetch failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void invalidate() {
    _ssWorkers = null;
    _villages = null;
    _subVillages = null;
    _skProfile = null;
    _workflowIds = const [];
    _defaultFacility = null;
    _error = null;
    _inflightFetch = null;
    notifyListeners();
  }
}
