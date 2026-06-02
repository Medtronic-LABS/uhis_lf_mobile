import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Entity representing a household member stored locally.
/// Matches Android HouseholdMemberEntity from spice-2.0-android uhis-dev branch.
class HouseholdMemberEntity {
  const HouseholdMemberEntity({
    required this.id,
    this.fhirId,
    this.householdId,
    this.householdReferenceId,
    this.name,
    this.gender,
    this.dob,
    this.phone,
    this.phoneNumberCategory,
    this.nationalId,
    this.patientId,
    this.villageId,
    this.isActive = true,
    this.isHouseholdHead = false,
    this.isPregnant = false,
    this.relation,
    this.initial,
    this.signature,
    this.localSignatureFile,
    this.motherPatientId,
    this.motherReferenceId,
    this.version,
    this.lastUpdated,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'Success',
    this.rawJson,
  });

  final String id;
  final String? fhirId;
  final String? householdId;
  final String? householdReferenceId;
  final String? name;
  final String? gender;
  final String? dob;
  final String? phone;
  final String? phoneNumberCategory;
  final String? nationalId;
  final String? patientId;
  final String? villageId;
  final bool isActive;
  final bool isHouseholdHead;
  final bool isPregnant;
  final String? relation;
  final String? initial;
  final String? signature;
  final String? localSignatureFile;
  final String? motherPatientId;
  final String? motherReferenceId;
  final String? version;
  final String? lastUpdated;
  final int? createdAt;
  final int? updatedAt;
  final String syncStatus;
  final String? rawJson;

  Map<String, dynamic> toDb() => {
        'id': id,
        'fhir_id': fhirId,
        'household_id': householdId,
        'household_reference_id': householdReferenceId,
        'name': name,
        'gender': gender,
        'dob': dob,
        'phone': phone,
        'phone_number_category': phoneNumberCategory,
        'national_id': nationalId,
        'patient_id': patientId,
        'village_id': villageId,
        'is_active': isActive ? 1 : 0,
        'is_household_head': isHouseholdHead ? 1 : 0,
        'is_pregnant': isPregnant ? 1 : 0,
        'relation': relation,
        'initial': initial,
        'signature': signature,
        'local_signature_file': localSignatureFile,
        'mother_patient_id': motherPatientId,
        'mother_reference_id': motherReferenceId,
        'version': version,
        'last_updated': lastUpdated,
        'created_at': createdAt,
        'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        'sync_status': syncStatus,
        'raw_json': rawJson,
      };

  factory HouseholdMemberEntity.fromDb(Map<String, dynamic> row) {
    return HouseholdMemberEntity(
      id: row['id'] as String,
      fhirId: row['fhir_id'] as String?,
      householdId: row['household_id'] as String?,
      householdReferenceId: row['household_reference_id'] as String?,
      name: row['name'] as String?,
      gender: row['gender'] as String?,
      dob: row['dob'] as String?,
      phone: row['phone'] as String?,
      phoneNumberCategory: row['phone_number_category'] as String?,
      nationalId: row['national_id'] as String?,
      patientId: row['patient_id'] as String?,
      villageId: row['village_id'] as String?,
      isActive: (row['is_active'] as int?) == 1,
      isHouseholdHead: (row['is_household_head'] as int?) == 1,
      isPregnant: (row['is_pregnant'] as int?) == 1,
      relation: row['relation'] as String?,
      initial: row['initial'] as String?,
      signature: row['signature'] as String?,
      localSignatureFile: row['local_signature_file'] as String?,
      motherPatientId: row['mother_patient_id'] as String?,
      motherReferenceId: row['mother_reference_id'] as String?,
      version: row['version'] as String?,
      lastUpdated: row['last_updated'] as String?,
      createdAt: row['created_at'] as int?,
      updatedAt: row['updated_at'] as int?,
      syncStatus: row['sync_status'] as String? ?? 'Success',
      rawJson: row['raw_json'] as String?,
    );
  }

  /// Creates from API JSON (e.g., from /household/member/list or fetch-synced-data response).
  /// Matches Android HouseHoldMember.toHouseholdMemberEntity() conversion.
  factory HouseholdMemberEntity.fromApiJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is int) return v == 1;
      if (v is String) return v.toLowerCase() == 'true';
      return false;
    }

    // Parse timestamps - Android uses Long milliseconds
    int? createdAt;
    int? updatedAt;
    final createdAtVal = json['createdAt'] ?? json['created_at'];
    final updatedAtVal = json['updatedAt'] ?? json['updated_at'];
    if (createdAtVal is int) createdAt = createdAtVal;
    if (createdAtVal is num) createdAt = createdAtVal.toInt();
    if (updatedAtVal is int) updatedAt = updatedAtVal;
    if (updatedAtVal is num) updatedAt = updatedAtVal.toInt();

    // Parse householdHeadRelationship (API field name)
    final relation = str('householdHeadRelationship') ?? str('relation');
    // isHouseholdHead = true when relation is "HouseholdHead" or "Self"
    final isHead = relation?.toLowerCase() == 'householdhead' ||
        relation?.toLowerCase() == 'self';

    // Android HouseHoldMember JSON mapping:
    // - JSON 'id' → @ColumnInfo(name = "fhir_id") var id (the FHIR ID)
    // - JSON 'referenceId' → @ColumnInfo(name = "id") val referenceId (app-generated ID)
    // - JSON 'householdId' → @ColumnInfo("household_fhir_id") (the FHIR ID of the household)
    // We use FHIR ID as primary key and relationship key in Flutter for consistency.
    final fhirId = str('id');  // JSON 'id' field IS the FHIR ID
    final referenceId = str('referenceId') ?? str('memberId');

    return HouseholdMemberEntity(
      id: fhirId ?? referenceId ?? '',
      fhirId: fhirId,
      householdId: str('householdId') ?? str('household_id'),  // This is the FHIR ID of household
      householdReferenceId: str('householdReferenceId') ?? str('household_reference_id'),
      name: str('name'),
      gender: str('gender'),
      dob: str('dateOfBirth') ?? str('dob'),
      phone: str('phoneNumber') ?? str('phone'),
      phoneNumberCategory: str('phoneNumberCategory') ?? str('phone_number_category'),
      nationalId: str('nationalId') ?? str('national_id'),
      patientId: str('patientId') ?? str('patient_id'),
      villageId: str('villageId') ?? str('village_id'),
      isActive: json['isActive'] != false,
      isHouseholdHead: isHead,
      isPregnant: parseBool(json['isPregnant']),
      relation: relation,
      initial: str('initial'),
      signature: str('signature'),
      localSignatureFile: str('localSignatureFile') ?? str('local_signature_file'),
      motherPatientId: str('motherPatientId') ?? str('mother_patient_id') ?? str('parentId'),
      motherReferenceId: str('motherReferenceId') ?? str('mother_reference_id'),
      version: str('version'),
      lastUpdated: str('lastUpdated') ?? str('last_updated'),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      syncStatus: str('syncStatus') ?? str('sync_status') ?? 'Success',
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

  /// Get all members grouped by household ID (single query - much faster).
  /// Returns a Map where keys are household IDs and values are lists of members.
  Future<Map<String, List<HouseholdMemberEntity>>> getAllGroupedByHousehold() async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      orderBy: 'household_id, name ASC',
    );
    final grouped = <String, List<HouseholdMemberEntity>>{};
    for (final row in rows) {
      final member = HouseholdMemberEntity.fromDb(row);
      final hhId = member.householdId ?? '';
      grouped.putIfAbsent(hhId, () => []).add(member);
    }
    return grouped;
  }

  /// Get member counts per household (single query - for list view).
  Future<Map<String, int>> getMemberCountsByHousehold() async {
    final rows = await _db.db.rawQuery('''
      SELECT household_id, COUNT(*) as count 
      FROM ${AppDatabase.tableMembers} 
      GROUP BY household_id
    ''');
    final counts = <String, int>{};
    for (final row in rows) {
      final hhId = row['household_id'] as String?;
      final count = row['count'] as int? ?? 0;
      if (hhId != null) {
        counts[hhId] = count;
      }
    }
    return counts;
  }

  /// Get IDs of members that are in the patients table (assigned to the SK).
  /// Returns the set of patient IDs from the patients table.
  /// These are "My Patients" - patients owned by the logged-in SK.
  Future<Set<String>> getMyPatientIds() async {
    // Get all patient IDs from the patients table (these are the assigned patients)
    // Also include the patient_id column for matching
    final rows = await _db.db.rawQuery(
        'SELECT id, patient_id FROM ${AppDatabase.tablePatients}');
    // ignore: avoid_print
    print('[MemberDao] getMyPatientIds raw: ${rows.take(3).toList()}');
    
    // Collect both id and patient_id for matching
    final ids = <String>{};
    for (final row in rows) {
      final id = row['id'];
      final patientId = row['patient_id'];
      if (id != null) ids.add(id.toString());
      if (patientId != null) ids.add(patientId.toString());
    }
    // ignore: avoid_print
    print('[MemberDao] getMyPatientIds: ${ids.length} unique IDs');
    if (ids.isNotEmpty) {
      // ignore: avoid_print
      print('[MemberDao] Sample IDs: ${ids.take(5).toList()}');
    }
    return ids;
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
