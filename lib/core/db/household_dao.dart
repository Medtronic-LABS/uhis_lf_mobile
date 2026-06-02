import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Entity representing a household stored locally.
/// Matches Android HouseholdEntity from spice-2.0-android uhis-dev branch.
class HouseholdEntity {
  const HouseholdEntity({
    required this.id,
    this.fhirId,
    this.householdNo,
    this.name,
    this.village,
    this.villageId,
    this.memberCount,
    this.landmark,
    this.headPhoneNumber,
    this.headPhoneNumberCategory,
    this.latitude,
    this.longitude,
    this.isOwnedAnImprovedLatrine = false,
    this.isOwnedHandWashingFacilityWithSoap = false,
    this.isOwnedATreatedBedNet = false,
    this.bedNetCount,
    this.version,
    this.lastUpdated,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'Success',
    this.rawJson,
  });

  final String id;
  final String? fhirId;
  final String? householdNo;
  final String? name;
  final String? village;
  final String? villageId;
  final int? memberCount;
  final String? landmark;
  final String? headPhoneNumber;
  final String? headPhoneNumberCategory;
  final double? latitude;
  final double? longitude;
  final bool isOwnedAnImprovedLatrine;
  final bool isOwnedHandWashingFacilityWithSoap;
  final bool isOwnedATreatedBedNet;
  final int? bedNetCount;
  final String? version;
  final String? lastUpdated;
  final int? createdAt;
  final int? updatedAt;
  final String syncStatus;
  final String? rawJson;

  Map<String, dynamic> toDb() => {
        'id': id,
        'fhir_id': fhirId,
        'household_no': householdNo,
        'name': name,
        'village': village,
        'village_id': villageId,
        'member_count': memberCount,
        'landmark': landmark,
        'head_phone_number': headPhoneNumber,
        'head_phone_number_category': headPhoneNumberCategory,
        'latitude': latitude,
        'longitude': longitude,
        'is_owned_an_improved_latrine': isOwnedAnImprovedLatrine ? 1 : 0,
        'is_owned_hand_washing_facility': isOwnedHandWashingFacilityWithSoap ? 1 : 0,
        'is_owned_a_treated_bed_net': isOwnedATreatedBedNet ? 1 : 0,
        'bed_net_count': bedNetCount,
        'version': version,
        'last_updated': lastUpdated,
        'created_at': createdAt,
        'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        'sync_status': syncStatus,
        'raw_json': rawJson,
      };

  factory HouseholdEntity.fromDb(Map<String, dynamic> row) {
    return HouseholdEntity(
      id: row['id'] as String,
      fhirId: row['fhir_id'] as String?,
      householdNo: row['household_no'] as String?,
      name: row['name'] as String?,
      village: row['village'] as String?,
      villageId: row['village_id'] as String?,
      memberCount: row['member_count'] as int?,
      landmark: row['landmark'] as String?,
      headPhoneNumber: row['head_phone_number'] as String?,
      headPhoneNumberCategory: row['head_phone_number_category'] as String?,
      latitude: row['latitude'] as double?,
      longitude: row['longitude'] as double?,
      isOwnedAnImprovedLatrine: (row['is_owned_an_improved_latrine'] as int?) == 1,
      isOwnedHandWashingFacilityWithSoap: (row['is_owned_hand_washing_facility'] as int?) == 1,
      isOwnedATreatedBedNet: (row['is_owned_a_treated_bed_net'] as int?) == 1,
      bedNetCount: row['bed_net_count'] as int?,
      version: row['version'] as String?,
      lastUpdated: row['last_updated'] as String?,
      createdAt: row['created_at'] as int?,
      updatedAt: row['updated_at'] as int?,
      syncStatus: row['sync_status'] as String? ?? 'Success',
      rawJson: row['raw_json'] as String?,
    );
  }

  /// Creates from API JSON (e.g., from /household/list or fetch-synced-data response).
  /// Matches Android HouseHold.toHouseholdEntity() conversion.
  factory HouseholdEntity.fromApiJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? parseInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    double? parseDouble(dynamic v) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is int) return v == 1;
      if (v is String) return v.toLowerCase() == 'true';
      return false;
    }

    final memberCount = parseInt(json['noOfPeople'] ?? json['memberCount'] ?? json['no_of_people']);

    // Parse timestamps - Android uses Long milliseconds
    int? createdAt;
    int? updatedAt;
    final createdAtVal = json['createdAt'] ?? json['created_at'];
    final updatedAtVal = json['updatedAt'] ?? json['updated_at'];
    if (createdAtVal is int) createdAt = createdAtVal;
    if (createdAtVal is num) createdAt = createdAtVal.toInt();
    if (updatedAtVal is int) updatedAt = updatedAtVal;
    if (updatedAtVal is num) updatedAt = updatedAtVal.toInt();

    // Android HouseHold JSON mapping:
    // - JSON 'id' → @ColumnInfo(name = "fhir_id") var id (the FHIR ID)
    // - JSON 'referenceId' → @ColumnInfo(name = "id") var referenceId (app-generated ID)
    // We use FHIR ID as primary key in Flutter for consistency.
    final fhirId = str('id');  // JSON 'id' field IS the FHIR ID
    final referenceId = str('referenceId');
    
    return HouseholdEntity(
      id: fhirId ?? referenceId ?? '',
      fhirId: fhirId,
      householdNo: str('householdNo') ?? str('household_no'),
      name: str('name') ?? str('householdName'),
      village: str('villageName') ?? str('village'),
      villageId: str('villageId') ?? str('village_id'),
      memberCount: memberCount,
      landmark: str('landmark'),
      headPhoneNumber: str('headPhoneNumber') ?? str('head_phone_number'),
      headPhoneNumberCategory: str('headPhoneNumberCategory') ?? str('head_phone_number_category'),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      isOwnedAnImprovedLatrine: parseBool(json['ownedAnImprovedLatrine'] ?? json['isOwnedAnImprovedLatrine'] ?? json['is_owned_an_improved_latrine']),
      isOwnedHandWashingFacilityWithSoap: parseBool(json['ownedHandWashingFacilityWithSoap'] ?? json['isOwnedHandWashingFacilityWithSoap'] ?? json['is_owned_hand_washing_facility_with_soap']),
      isOwnedATreatedBedNet: parseBool(json['ownedTreatedBedNet'] ?? json['isOwnedATreatedBedNet'] ?? json['is_owned_a_treated_bed_net']),
      bedNetCount: parseInt(json['bedNetCount'] ?? json['bed_net_count']),
      version: str('version'),
      lastUpdated: str('lastUpdated') ?? str('last_updated'),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      syncStatus: str('syncStatus') ?? str('sync_status') ?? 'Success',
      rawJson: null,
    );
  }
}

/// Data-access for the `households` table — the local cache of households.
/// Following spice-2.0-android pattern: all reads are from local SQLite,
/// network sync populates the local cache.
class HouseholdDao {
  HouseholdDao(this._db);

  final AppDatabase _db;

  /// Bulk upsert households from sync response.
  Future<void> upsertMany(List<HouseholdEntity> households) async {
    if (households.isEmpty) return;
    final batch = _db.db.batch();
    for (final h in households) {
      batch.insert(
        AppDatabase.tableHouseholds,
        h.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get household by ID (LOCAL query, no network).
  Future<HouseholdEntity?> getById(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HouseholdEntity.fromDb(rows.first);
  }

  /// Get all households for villages (LOCAL query).
  Future<List<HouseholdEntity>> getByVillageIds(List<String> villageIds, {
    int limit = 100,
    int offset = 0,
    String? searchTerm,
  }) async {
    String where = '';
    List<Object?> args = [];

    if (villageIds.isNotEmpty) {
      final placeholders = List.filled(villageIds.length, '?').join(',');
      where = 'village_id IN ($placeholders)';
      args = [...villageIds];
    }

    if (searchTerm != null && searchTerm.isNotEmpty) {
      if (where.isNotEmpty) where += ' AND ';
      where += '(name LIKE ? OR household_no LIKE ?)';
      args.addAll(['%$searchTerm%', '%$searchTerm%']);
    }

    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      where: where.isEmpty ? null : where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(HouseholdEntity.fromDb).toList();
  }

  /// Get all households (LOCAL query).
  Future<List<HouseholdEntity>> getAll({int limit = 100, int offset = 0}) async {
    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(HouseholdEntity.fromDb).toList();
  }

  /// Search households by name or number (LOCAL query, no network).
  Future<List<HouseholdEntity>> search(String query, {int limit = 50}) async {
    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      where: 'name LIKE ? OR household_no LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name ASC',
      limit: limit,
    );
    return rows.map(HouseholdEntity.fromDb).toList();
  }

  /// Count households in local DB.
  Future<int> count() async {
    final rows = await _db.db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${AppDatabase.tableHouseholds}');
    final c = rows.first['c'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return 0;
  }

  /// Count households for specific villages.
  Future<int> countByVillageIds(List<String> villageIds) async {
    if (villageIds.isEmpty) return count();
    final placeholders = List.filled(villageIds.length, '?').join(',');
    final rows = await _db.db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${AppDatabase.tableHouseholds} WHERE village_id IN ($placeholders)',
        villageIds);
    final c = rows.first['c'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return 0;
  }

  /// Get total member count (sum of member_count column).
  Future<int> totalMemberCount() async {
    final rows = await _db.db.rawQuery(
        'SELECT COALESCE(SUM(member_count), 0) AS c FROM ${AppDatabase.tableHouseholds}');
    final c = rows.first['c'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return 0;
  }

  /// Delete all households (used before full sync).
  Future<void> deleteAll() async {
    await _db.db.delete(AppDatabase.tableHouseholds);
  }
}
