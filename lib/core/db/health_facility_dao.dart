import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// One row from Android `HealthFacilityEntity` / user-data
/// `nearestHealthFacilities` + `userHealthFacilities`.
class HealthFacilityRow {
  const HealthFacilityRow({
    required this.id,
    required this.name,
    this.fhirId,
    this.phoneNumber,
    this.isDefault = false,
    this.isUserSite = false,
    this.tenantId,
    this.districtId,
    this.chiefdomId,
  });

  /// Server numeric facility id (stable PK).
  final String id;
  final String name;

  /// Spinner / `summary.referredSiteId` value (Android uses fhirId).
  final String? fhirId;
  final String? phoneNumber;
  final bool isDefault;
  final bool isUserSite;
  final String? tenantId;
  final String? districtId;
  final String? chiefdomId;

  Map<String, Object?> toDb() => {
        'id': id,
        'name': name,
        'fhir_id': fhirId,
        'phone_number': phoneNumber,
        'is_default': isDefault ? 1 : 0,
        'is_user_site': isUserSite ? 1 : 0,
        'tenant_id': tenantId,
        'district_id': districtId,
        'chiefdom_id': chiefdomId,
      };

  factory HealthFacilityRow.fromDb(Map<String, Object?> row) {
    return HealthFacilityRow(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      fhirId: row['fhir_id'] as String?,
      phoneNumber: row['phone_number'] as String?,
      isDefault: (row['is_default'] as int?) == 1,
      isUserSite: (row['is_user_site'] as int?) == 1,
      tenantId: row['tenant_id'] as String?,
      districtId: row['district_id'] as String?,
      chiefdomId: row['chiefdom_id'] as String?,
    );
  }
}

/// Offline cache of nearest / user health facilities (Android MetaRepository
/// → `HealthFacilityEntity` parity).
class HealthFacilityDao {
  HealthFacilityDao(this._db);

  final AppDatabase _db;

  /// Spinner list — default site first (Android `ORDER BY isDefault DESC`).
  Future<List<HealthFacilityRow>> nearestFacilities() async {
    final rows = await _db.db.query(
      AppDatabase.tableHealthFacilities,
      orderBy: 'is_default DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(HealthFacilityRow.fromDb).toList();
  }

  Future<HealthFacilityRow?> defaultFacility() async {
    final rows = await _db.db.query(
      AppDatabase.tableHealthFacilities,
      where: 'is_default = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HealthFacilityRow.fromDb(rows.first);
  }

  /// Replace-all upsert (Android deleteAll + insert).
  Future<void> replaceAll(List<HealthFacilityRow> facilities) async {
    await _db.db.transaction((tx) async {
      await tx.delete(AppDatabase.tableHealthFacilities);
      for (final f in facilities) {
        await tx.insert(
          AppDatabase.tableHealthFacilities,
          f.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Parse + filter + merge user-data facility lists (pure + persist).
  ///
  /// Mirrors Android `filterNearestHealthFacilitiesByLinkedVillages` +
  /// `saveHealthFacilityInDb`.
  Future<int> replaceFromUserDataEntity(Map<String, dynamic> entity) async {
    final rows = HealthFacilityIngest.fromUserDataEntity(entity);
    await replaceAll(rows);
    return rows.length;
  }
}

/// Pure ingest helpers — unit-tested without SQLite.
abstract final class HealthFacilityIngest {
  HealthFacilityIngest._();

  /// Build the offline facility list from a static-data `entity` map.
  static List<HealthFacilityRow> fromUserDataEntity(Map<String, dynamic> entity) {
    final villageIds = _villageIds(entity);
    final defaultId = _facilityId(
      entity['defaultHealthFacility'] ?? entity['defaultFacility'],
    );

    final nearestRaw = entity['nearestHealthFacilities'];
    final nearest = _parseList(nearestRaw);
    final filtered = villageIds.isEmpty
        ? nearest
        : nearest
            .where((f) => f.linkedVillageIds.any(villageIds.contains))
            .toList();

    final userRaw = entity['userHealthFacilities'];
    final userSites = _parseList(userRaw);
    final userSiteIds = userSites.map((f) => f.id).toSet();

    final byId = <String, _ParsedFacility>{};
    for (final f in filtered) {
      byId[f.id] = f;
    }
    // Android: append userHealthFacilities not already in the nearest list.
    for (final f in userSites) {
      byId.putIfAbsent(f.id, () => f);
    }

    return byId.values
        .map(
          (f) => HealthFacilityRow(
            id: f.id,
            name: f.name,
            fhirId: f.fhirId,
            phoneNumber: f.phoneNumber,
            isDefault: defaultId != null && f.id == defaultId,
            isUserSite: userSiteIds.contains(f.id),
            tenantId: f.tenantId,
            districtId: f.districtId,
            chiefdomId: f.chiefdomId,
          ),
        )
        .toList();
  }

  static Set<int> _villageIds(Map<String, dynamic> entity) {
    final raw = entity['villages'];
    if (raw is! List) return const {};
    final out = <int>{};
    for (final v in raw) {
      if (v is! Map) continue;
      final id = v['id'];
      if (id is int) {
        out.add(id);
      } else if (id is num) {
        out.add(id.toInt());
      } else if (id is String) {
        final parsed = int.tryParse(id);
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }

  static String? _facilityId(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id == null) return null;
    final s = id.toString().trim();
    return s.isEmpty ? null : s;
  }

  static List<_ParsedFacility> _parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <_ParsedFacility>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final parsed = _ParsedFacility.fromJson(Map<String, dynamic>.from(item));
      if (parsed != null) out.add(parsed);
    }
    return out;
  }
}

class _ParsedFacility {
  const _ParsedFacility({
    required this.id,
    required this.name,
    this.fhirId,
    this.phoneNumber,
    this.tenantId,
    this.districtId,
    this.chiefdomId,
    this.linkedVillageIds = const {},
  });

  final String id;
  final String name;
  final String? fhirId;
  final String? phoneNumber;
  final String? tenantId;
  final String? districtId;
  final String? chiefdomId;
  final Set<int> linkedVillageIds;

  static _ParsedFacility? fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    if (idRaw == null) return null;
    final id = idRaw.toString().trim();
    if (id.isEmpty) return null;

    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final linked = <int>{};
    final lvRaw = json['linkedVillages'];
    if (lvRaw is List) {
      for (final v in lvRaw) {
        if (v is! Map) continue;
        final vid = v['id'];
        if (vid is int) {
          linked.add(vid);
        } else if (vid is num) {
          linked.add(vid.toInt());
        } else if (vid is String) {
          final parsed = int.tryParse(vid);
          if (parsed != null) linked.add(parsed);
        }
      }
    }

    String? districtId;
    final district = json['district'];
    if (district is Map) {
      districtId = district['id']?.toString();
    } else {
      districtId = str('districtId');
    }

    String? chiefdomId;
    final chiefdom = json['chiefdom'];
    if (chiefdom is Map) {
      chiefdomId = chiefdom['id']?.toString();
    } else {
      chiefdomId = str('chiefdomId');
    }

    final phone = str('phuFocalPersonNumber') ?? str('phoneNumber');

    return _ParsedFacility(
      id: id,
      name: str('name') ?? str('facilityName') ?? id,
      fhirId: str('fhirId') ?? str('fhir_id'),
      phoneNumber: phone,
      tenantId: str('tenantId'),
      districtId: districtId,
      chiefdomId: chiefdomId,
      linkedVillageIds: linked,
    );
  }
}
