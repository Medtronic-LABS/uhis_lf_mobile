import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Entity representing a household member stored locally.
class HouseholdMemberEntity {
  const HouseholdMemberEntity({
    required this.id,
    this.householdId,
    this.name,
    this.gender,
    this.dob,
    this.phone,
    this.nationalId,
    this.patientId,
    this.villageId,
    this.isActive = true,
    this.updatedAt,
    this.rawJson,
  });

  final String id;
  final String? householdId;
  final String? name;
  final String? gender;
  final String? dob;
  final String? phone;
  final String? nationalId;
  final String? patientId;
  final String? villageId;
  final bool isActive;
  final int? updatedAt;
  final String? rawJson;

  Map<String, dynamic> toDb() => {
        'id': id,
        'household_id': householdId,
        'name': name,
        'gender': gender,
        'dob': dob,
        'phone': phone,
        'national_id': nationalId,
        'patient_id': patientId,
        'village_id': villageId,
        'is_active': isActive ? 1 : 0,
        'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        'raw_json': rawJson,
      };

  factory HouseholdMemberEntity.fromDb(Map<String, dynamic> row) {
    return HouseholdMemberEntity(
      id: row['id'] as String,
      householdId: row['household_id'] as String?,
      name: row['name'] as String?,
      gender: row['gender'] as String?,
      dob: row['dob'] as String?,
      phone: row['phone'] as String?,
      nationalId: row['national_id'] as String?,
      patientId: row['patient_id'] as String?,
      villageId: row['village_id'] as String?,
      isActive: (row['is_active'] as int?) == 1,
      updatedAt: row['updated_at'] as int?,
      rawJson: row['raw_json'] as String?,
    );
  }

  /// Creates from API JSON (e.g., from /household/member/list response).
  factory HouseholdMemberEntity.fromApiJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return HouseholdMemberEntity(
      id: str('fhirId') ?? str('id') ?? str('memberId') ?? '',
      householdId: str('householdId') ?? str('household_id'),
      name: str('name'),
      gender: str('gender'),
      dob: str('dateOfBirth') ?? str('dob'),
      phone: str('phoneNumber') ?? str('phone'),
      nationalId: str('nationalId') ?? str('national_id'),
      patientId: str('patientId') ?? str('patient_id'),
      villageId: str('villageId') ?? str('village_id'),
      isActive: json['isActive'] != false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      rawJson: null, // Can serialize full json if needed
    );
  }
}

/// Data-access for the `members` table — the local cache of household members.
/// Following spice-2.0-android pattern: all reads are from local SQLite,
/// network sync populates the local cache.
class MemberDao {
  MemberDao(this._db);

  final AppDatabase _db;

  /// Bulk upsert members from sync response.
  Future<void> upsertMany(List<HouseholdMemberEntity> members) async {
    if (members.isEmpty) return;
    final batch = _db.db.batch();
    for (final m in members) {
      batch.insert(
        AppDatabase.tableMembers,
        m.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get all members for a household (LOCAL query, no network).
  Future<List<HouseholdMemberEntity>> getByHouseholdId(String householdId) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'household_id = ?',
      whereArgs: [householdId],
      orderBy: 'name ASC',
    );
    return rows.map(HouseholdMemberEntity.fromDb).toList();
  }

  /// Get member by ID (LOCAL query, no network).
  Future<HouseholdMemberEntity?> getById(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HouseholdMemberEntity.fromDb(rows.first);
  }

  /// Get member by patient ID (LOCAL query, no network).
  Future<HouseholdMemberEntity?> getByPatientId(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HouseholdMemberEntity.fromDb(rows.first);
  }

  /// Search members by name (LOCAL query, no network).
  Future<List<HouseholdMemberEntity>> searchByName(String query, {int limit = 50}) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
      limit: limit,
    );
    return rows.map(HouseholdMemberEntity.fromDb).toList();
  }

  /// Get all members for villages (LOCAL query).
  Future<List<HouseholdMemberEntity>> getByVillageIds(List<String> villageIds) async {
    if (villageIds.isEmpty) {
      final rows = await _db.db.query(AppDatabase.tableMembers, orderBy: 'name ASC');
      return rows.map(HouseholdMemberEntity.fromDb).toList();
    }
    final placeholders = List.filled(villageIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'village_id IN ($placeholders)',
      whereArgs: villageIds,
      orderBy: 'name ASC',
    );
    return rows.map(HouseholdMemberEntity.fromDb).toList();
  }

  /// Count members in local DB.
  Future<int> count() async {
    final rows = await _db.db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${AppDatabase.tableMembers}');
    final c = rows.first['c'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return 0;
  }

  /// Count members for a specific household.
  Future<int> countByHousehold(String householdId) async {
    final rows = await _db.db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${AppDatabase.tableMembers} WHERE household_id = ?',
        [householdId]);
    final c = rows.first['c'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return 0;
  }

  /// Delete all members (used before full sync).
  Future<void> deleteAll() async {
    await _db.db.delete(AppDatabase.tableMembers);
  }
}
