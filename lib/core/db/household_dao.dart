import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Entity representing a household stored locally.
class HouseholdEntity {
  const HouseholdEntity({
    required this.id,
    this.householdNo,
    this.name,
    this.village,
    this.villageId,
    this.memberCount,
    this.updatedAt,
    this.rawJson,
  });

  final String id;
  final String? householdNo;
  final String? name;
  final String? village;
  final String? villageId;
  final int? memberCount;
  final int? updatedAt;
  final String? rawJson;

  Map<String, dynamic> toDb() => {
        'id': id,
        'household_no': householdNo,
        'name': name,
        'village': village,
        'village_id': villageId,
        'member_count': memberCount,
        'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        'raw_json': rawJson,
      };

  factory HouseholdEntity.fromDb(Map<String, dynamic> row) {
    return HouseholdEntity(
      id: row['id'] as String,
      householdNo: row['household_no'] as String?,
      name: row['name'] as String?,
      village: row['village'] as String?,
      villageId: row['village_id'] as String?,
      memberCount: row['member_count'] as int?,
      updatedAt: row['updated_at'] as int?,
      rawJson: row['raw_json'] as String?,
    );
  }

  /// Creates from API JSON (e.g., from /household/list response).
  factory HouseholdEntity.fromApiJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? memberCount;
    final nop = json['noOfPeople'] ?? json['memberCount'];
    if (nop is int) memberCount = nop;
    if (nop is num) memberCount = nop.toInt();

    return HouseholdEntity(
      id: str('fhirId') ?? str('id') ?? str('householdId') ?? '',
      householdNo: str('householdNo') ?? str('household_no'),
      name: str('name') ?? str('householdName'),
      village: str('villageName') ?? str('village'),
      villageId: str('villageId') ?? str('village_id'),
      memberCount: memberCount,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
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
