import 'package:flutter/foundation.dart';
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
    this.referenceId,
    this.name,
    this.gender,
    this.dob,
    this.phone,
    this.phoneNumberCategory,
    this.nationalId,
    this.patientId,
    this.villageId,
    this.villageName,
    this.subVillageId,
    this.subVillageName,
    this.shasthyaShebikaId,
    this.isActive = true,
    this.isHouseholdHead = false,
    this.isPregnant = false,
    this.relation,
    this.initial,
    this.signature,
    this.localSignatureFile,
    this.motherPatientId,
    this.motherReferenceId,
    this.maritalStatus,
    this.disability,
    this.guardianId,
    this.guardianFhirId,
    this.latitude,
    this.longitude,
    this.idType,
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
  /// Backend integer referenceId (the PK used as referenceId in offline-sync/create).
  final String? referenceId;
  final String? name;
  final String? gender;
  final String? dob;
  final String? phone;
  final String? phoneNumberCategory;
  final String? nationalId;
  final String? patientId;
  final String? villageId;
  final String? villageName;
  final String? subVillageId;
  final String? subVillageName;
  final String? shasthyaShebikaId;
  final bool isActive;
  final bool isHouseholdHead;
  final bool isPregnant;
  final String? relation;
  final String? initial;
  final String? signature;
  final String? localSignatureFile;
  final String? motherPatientId;
  final String? motherReferenceId;
  final String? maritalStatus;
  final String? disability;
  final String? guardianId;
  final String? guardianFhirId;
  final double? latitude;
  final double? longitude;
  final String? idType;
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
        'reference_id': referenceId,
        'name': name,
        'gender': gender,
        'dob': dob,
        'phone': phone,
        'phone_number_category': phoneNumberCategory,
        'national_id': nationalId,
        'patient_id': patientId,
        'village_id': villageId,
        'village_name': villageName,
        'sub_village_id': subVillageId,
        'sub_village_name': subVillageName,
        'shasthya_shebika_id': shasthyaShebikaId,
        'is_active': isActive ? 1 : 0,
        'is_household_head': isHouseholdHead ? 1 : 0,
        'is_pregnant': isPregnant ? 1 : 0,
        'relation': relation,
        'initial': initial,
        'signature': signature,
        'local_signature_file': localSignatureFile,
        'mother_patient_id': motherPatientId,
        'mother_reference_id': motherReferenceId,
        'marital_status': maritalStatus,
        'disability': disability,
        'guardian_id': guardianId,
        'guardian_fhir_id': guardianFhirId,
        'latitude': latitude,
        'longitude': longitude,
        'id_type': idType,
        'version': version,
        'last_updated': lastUpdated,
        'created_at': createdAt,
        'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        'sync_status': syncStatus,
        'raw_json': rawJson,
      };

  /// Returns a copy with location fields overridden (null means keep existing).
  HouseholdMemberEntity copyWithVillage({
    String? villageId,
    String? subVillageId,
    String? shasthyaShebikaId,
  }) {
    return HouseholdMemberEntity(
      id: id,
      fhirId: fhirId,
      householdId: householdId,
      householdReferenceId: householdReferenceId,
      referenceId: referenceId,
      name: name,
      gender: gender,
      dob: dob,
      phone: phone,
      phoneNumberCategory: phoneNumberCategory,
      nationalId: nationalId,
      patientId: patientId,
      villageId: villageId ?? this.villageId,
      villageName: villageName,
      subVillageId: subVillageId ?? this.subVillageId,
      subVillageName: subVillageName,
      shasthyaShebikaId: shasthyaShebikaId ?? this.shasthyaShebikaId,
      isActive: isActive,
      isHouseholdHead: isHouseholdHead,
      isPregnant: isPregnant,
      relation: relation,
      initial: initial,
      signature: signature,
      localSignatureFile: localSignatureFile,
      motherPatientId: motherPatientId,
      motherReferenceId: motherReferenceId,
      maritalStatus: maritalStatus,
      disability: disability,
      guardianId: guardianId,
      guardianFhirId: guardianFhirId,
      latitude: latitude,
      longitude: longitude,
      idType: idType,
      version: version,
      lastUpdated: lastUpdated,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: syncStatus,
      rawJson: rawJson,
    );
  }

  factory HouseholdMemberEntity.fromDb(Map<String, dynamic> row) {
    return HouseholdMemberEntity(
      id: row['id'] as String,
      fhirId: row['fhir_id'] as String?,
      householdId: row['household_id'] as String?,
      householdReferenceId: row['household_reference_id'] as String?,
      referenceId: row['reference_id'] as String?,
      name: row['name'] as String?,
      gender: row['gender'] as String?,
      dob: row['dob'] as String?,
      phone: row['phone'] as String?,
      phoneNumberCategory: row['phone_number_category'] as String?,
      nationalId: row['national_id'] as String?,
      patientId: row['patient_id'] as String?,
      villageId: row['village_id'] as String?,
      villageName: row['village_name'] as String?,
      subVillageId: row['sub_village_id'] as String?,
      subVillageName: row['sub_village_name'] as String?,
      shasthyaShebikaId: row['shasthya_shebika_id'] as String?,
      isActive: (row['is_active'] as int?) == 1,
      isHouseholdHead: (row['is_household_head'] as int?) == 1,
      isPregnant: (row['is_pregnant'] as int?) == 1,
      relation: row['relation'] as String?,
      initial: row['initial'] as String?,
      signature: row['signature'] as String?,
      localSignatureFile: row['local_signature_file'] as String?,
      motherPatientId: row['mother_patient_id'] as String?,
      motherReferenceId: row['mother_reference_id'] as String?,
      maritalStatus: row['marital_status'] as String?,
      disability: row['disability'] as String?,
      guardianId: row['guardian_id'] as String?,
      guardianFhirId: row['guardian_fhir_id'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      idType: row['id_type'] as String?,
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
      referenceId: referenceId,
      name: str('name'),
      gender: str('gender'),
      dob: str('dateOfBirth') ?? str('dob'),
      phone: str('phoneNumber') ?? str('phone'),
      phoneNumberCategory: str('phoneNumberCategory') ?? str('phone_number_category'),
      nationalId: str('nationalId') ?? str('national_id'),
      patientId: str('patientId') ?? str('patient_id'),
      villageId: str('villageId') ?? str('village_id'),
      villageName: str('village') ?? str('villageName') ?? str('village_name'),
      subVillageId: str('subVillageId') ?? str('sub_village_id'),
      subVillageName: str('subVillage') ?? str('subVillageName') ?? str('sub_village_name'),
      shasthyaShebikaId: str('shasthyaShebikaId') ?? str('shasthya_shebika_id'),
      isActive: json['isActive'] != false,
      isHouseholdHead: isHead,
      isPregnant: parseBool(json['isPregnant']),
      relation: relation,
      initial: str('initial'),
      signature: str('signature'),
      localSignatureFile: str('localSignatureFile') ?? str('local_signature_file'),
      motherPatientId: str('motherPatientId') ?? str('mother_patient_id') ?? str('parentId'),
      motherReferenceId: str('motherReferenceId') ?? str('mother_reference_id'),
      maritalStatus: str('maritalStatus') ?? str('marital_status'),
      disability: str('disability'),
      guardianId: str('guardianId') ?? str('guardian_id'),
      guardianFhirId: str('guardianFhirId') ?? str('guardian_fhir_id'),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      idType: str('idType') ?? str('id_type'),
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
    debugPrint('[MemberDao] searchByName q="$query" hits=${rows.length}');
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

  /// Get all members grouped by household ID with optional SS/village/sub-village filters.
  /// Returns members grouped by household_id, with optional location filters.
  ///
  /// village_id / sub_village_id / shasthya_shebika_id are populated by the
  /// sync enrichment step (offline_sync_service propagates them from household
  /// referenceId → villageId maps). Filters work correctly after the first sync
  /// that ran with the enrichment code in place.
  Future<Map<String, List<HouseholdMemberEntity>>> getAllGroupedByHousehold({
    String? villageId,
    String? subVillageId,
    String? shasthyaShebikaId,
    List<String>? subVillageIds, // IN clause — used for SS filter
  }) async {
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (villageId != null) {
      whereClauses.add('village_id = ?');
      whereArgs.add(villageId);
    }
    if (subVillageId != null) {
      whereClauses.add('sub_village_id = ?');
      whereArgs.add(subVillageId);
    }
    final effectiveSvIds =
        subVillageIds?.isNotEmpty == true ? subVillageIds : null;
    if (effectiveSvIds != null) {
      final ph = List.filled(effectiveSvIds.length, '?').join(',');
      whereClauses.add('sub_village_id IN ($ph)');
      whereArgs.addAll(effectiveSvIds);
    } else if (shasthyaShebikaId != null) {
      whereClauses.add('shasthya_shebika_id = ?');
      whereArgs.add(shasthyaShebikaId);
    }

    if (whereClauses.isNotEmpty) {
      final sample = await _db.db.rawQuery('''
        SELECT DISTINCT village_id, sub_village_id, shasthya_shebika_id
        FROM ${AppDatabase.tableMembers}
        WHERE village_id IS NOT NULL OR sub_village_id IS NOT NULL OR shasthya_shebika_id IS NOT NULL
        LIMIT 5
      ''');
      debugPrint('[MemberDao] Filter args: villageId=$villageId subVillageId=$subVillageId '
          'shebikaId=$shasthyaShebikaId subVillageIds=$subVillageIds');
      debugPrint('[MemberDao] DB sample (village/subVillage/shebika): $sample');
    }

    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
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

  /// Back-propagates village/sub-village to member rows that still have NULL
  /// village_id after a previous sync that ran without the enrichment step.
  /// [hhRefToVillage] maps household.referenceId → villageId.
  /// [hhRefToSubVillage] maps household.referenceId → subVillageId (optional).
  Future<void> propagateVillageFromHouseholds(
    Map<String, String> hhRefToVillage, {
    Map<String, String> hhRefToSubVillage = const {},
  }) async {
    if (hhRefToVillage.isEmpty) return;
    final rows = await _db.db.rawQuery(
      'SELECT id, household_id FROM ${AppDatabase.tableMembers} '
      'WHERE village_id IS NULL AND household_id IS NOT NULL',
    );
    if (rows.isEmpty) return;
    final batch = _db.db.batch();
    int count = 0;
    for (final row in rows) {
      final memberId = row['id']?.toString();
      final householdId = row['household_id']?.toString();
      if (memberId == null || householdId == null) continue;
      final villageId = hhRefToVillage[householdId];
      if (villageId == null) continue;
      final updates = <String, dynamic>{'village_id': villageId};
      final svId = hhRefToSubVillage[householdId];
      if (svId != null) updates['sub_village_id'] = svId;
      batch.update(
        AppDatabase.tableMembers,
        updates,
        where: 'id = ?',
        whereArgs: [memberId],
      );
      count++;
    }
    if (count > 0) {
      await batch.commit(noResult: true);
      debugPrint('[MemberDao] Propagated village_id to $count member records');
    }
  }

  /// SQL JOIN-based village propagation — derives village/sub-village directly
  /// from the households table instead of an in-memory map.
  /// Requires households to have village_id populated first (e.g. after
  /// _syncHouseholdsAndMembers upserts them from the household-list API).
  /// Works correctly because members.household_id = households.id (1152/1155
  /// members link via this join in practice).
  Future<void> propagateVillageFromHouseholdTable() async {
    final db = _db.db;
    // No village_id IS NULL guard — bundle sets API-internal IDs (e.g. 5);
    // household table has static-data IDs (e.g. 26) after _syncHouseholdsAndMembers.
    // Unconditional overwrite ensures filter-correct IDs win.
    final villageResult = await db.rawUpdate('''
      UPDATE ${AppDatabase.tableMembers}
      SET village_id = (
        SELECT village_id FROM ${AppDatabase.tableHouseholds}
        WHERE id = ${AppDatabase.tableMembers}.household_id
        AND village_id IS NOT NULL
      )
      WHERE household_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM ${AppDatabase.tableHouseholds}
        WHERE id = ${AppDatabase.tableMembers}.household_id
        AND village_id IS NOT NULL
      )
    ''');
    if (villageResult > 0) {
      debugPrint('[MemberDao] JOIN propagation: village_id→$villageResult rows');
    }
  }

  /// Propagates static-data sub_village_id to ALL member rows in each
  /// household (including bundle-synced rows whose IDs differ from the
  /// household/member list rows). Call after upsertMany in _syncHouseholdsAndMembers.
  Future<void> propagateSubVillageFromMap(Map<String, String> hhIdToSvId) async {
    if (hhIdToSvId.isEmpty) return;
    final batch = _db.db.batch();
    for (final entry in hhIdToSvId.entries) {
      batch.rawUpdate(
        'UPDATE ${AppDatabase.tableMembers} SET sub_village_id = ? WHERE household_id = ?',
        [entry.value, entry.key],
      );
    }
    await batch.commit(noResult: true);
    debugPrint('[MemberDao] propagateSubVillageFromMap: ${hhIdToSvId.length} household groups updated');
  }

  /// Returns distinct (villageId, villageName) pairs for filter UI.
  Future<List<({String id, String name})>> getDistinctVillages() async {
    final rows = await _db.db.rawQuery('''
      SELECT DISTINCT village_id, village_name
      FROM ${AppDatabase.tableMembers}
      WHERE village_id IS NOT NULL AND village_id != ''
      ORDER BY COALESCE(village_name, village_id) ASC
    ''');
    return rows.map((r) {
      final id = r['village_id'].toString();
      final name = (r['village_name'] as String?)?.trim();
      return (id: id, name: (name != null && name.isNotEmpty) ? name : id);
    }).toList();
  }

  /// Returns distinct (subVillageId, subVillageName) pairs for filter UI.
  Future<List<({String id, String name})>> getDistinctSubVillages({
    String? villageId,
  }) async {
    final where = villageId != null
        ? 'sub_village_id IS NOT NULL AND sub_village_id != \'\' AND village_id = ?'
        : 'sub_village_id IS NOT NULL AND sub_village_id != \'\'';
    final rows = await _db.db.rawQuery(
      '''
      SELECT DISTINCT sub_village_id, sub_village_name
      FROM ${AppDatabase.tableMembers}
      WHERE $where
      ORDER BY COALESCE(sub_village_name, sub_village_id) ASC
      ''',
      villageId != null ? [villageId] : null,
    );
    return rows.map((r) {
      final id = r['sub_village_id'].toString();
      final name = (r['sub_village_name'] as String?)?.trim();
      return (id: id, name: (name != null && name.isNotEmpty) ? name : id);
    }).toList();
  }

  /// Returns distinct shasthyaShebikaId values (with label) for filter UI.
  Future<List<({String id, String name})>> getDistinctShebikas({
    String? villageId,
    String? subVillageId,
  }) async {
    final whereClauses = [
      'shasthya_shebika_id IS NOT NULL',
      "shasthya_shebika_id != ''",
    ];
    final args = <dynamic>[];
    if (villageId != null) {
      whereClauses.add('village_id = ?');
      args.add(villageId);
    }
    if (subVillageId != null) {
      whereClauses.add('sub_village_id = ?');
      args.add(subVillageId);
    }
    final rows = await _db.db.rawQuery(
      '''
      SELECT DISTINCT shasthya_shebika_id
      FROM ${AppDatabase.tableMembers}
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY shasthya_shebika_id ASC
      ''',
      args.isEmpty ? null : args,
    );
    return rows.map((r) {
      final id = r['shasthya_shebika_id'].toString();
      return (id: id, name: 'SS $id');
    }).toList();
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

  /// Bulk-lookup: returns memberId → patientId for the given member IDs.
  ///
  /// `householdMemberId` in the assessment-history API is the numeric
  /// `referenceId` (backend PK), NOT the FHIR `id` column. Both are checked
  /// so callers don't need to know which ID system the server used.
  Future<Map<String, String>> patientIdsByMemberIds(List<String> memberIds) async {
    if (memberIds.isEmpty) return const {};
    final ph = List.filled(memberIds.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT id, reference_id, patient_id FROM ${AppDatabase.tableMembers} '
      'WHERE id IN ($ph) OR reference_id IN ($ph)',
      [...memberIds, ...memberIds],
    );
    final result = <String, String>{};
    for (final row in rows) {
      final fhirId = row['id']?.toString();
      final refId = row['reference_id']?.toString();
      final patientId = row['patient_id']?.toString();
      final resolved =
          (patientId != null && patientId.isNotEmpty) ? patientId : fhirId;
      if (resolved == null || resolved.isEmpty) continue;
      if (fhirId != null && fhirId.isNotEmpty) result[fhirId] = resolved;
      if (refId != null && refId.isNotEmpty) result[refId] = resolved;
    }
    return result;
  }

  /// Returns all member/patient IDs whose sub_village_id is in [subVillageIds].
  Future<Set<String>> getPatientIdsBySubVillages(List<String> subVillageIds) async {
    if (subVillageIds.isEmpty) return const {};
    final ph = List.filled(subVillageIds.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT id, patient_id FROM ${AppDatabase.tableMembers} WHERE sub_village_id IN ($ph)',
      subVillageIds,
    );
    final ids = <String>{};
    for (final row in rows) {
      final id = row['id'];
      final patientId = row['patient_id'];
      if (id != null) ids.add(id.toString());
      if (patientId != null) ids.add(patientId.toString());
    }
    return ids;
  }

  /// IDs assigned to this SK — from the patients table, plus member entity IDs
  /// only when that member is linked to an assigned patient (id or patient_id match).
  Future<Set<String>> getMyPatientIds() async {
    final ids = <String>{};

    final patientRows = await _db.db.rawQuery(
        'SELECT id, patient_id FROM ${AppDatabase.tablePatients}');
    for (final row in patientRows) {
      final id = row['id'];
      final patientId = row['patient_id'];
      if (id != null) ids.add(id.toString());
      if (patientId != null) ids.add(patientId.toString());
    }

    if (ids.isEmpty) return ids;

    // Bridge member IDs only for rows tied to an assigned patient — not every member.
    final placeholders = List.filled(ids.length, '?').join(',');
    final memberRows = await _db.db.rawQuery(
      'SELECT id, patient_id FROM ${AppDatabase.tableMembers} '
      'WHERE id IN ($placeholders) OR patient_id IN ($placeholders)',
      [...ids, ...ids],
    );
    for (final row in memberRows) {
      final memberId = row['id'];
      final memberPatientId = row['patient_id'];
      if (memberId != null) ids.add(memberId.toString());
      if (memberPatientId != null) ids.add(memberPatientId.toString());
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

  /// Sets village_id on ALL member rows. Called after bundle persist when the
  /// bundle returns API-internal village IDs (e.g. 5) but the sync was
  /// triggered with the static-data village ID (e.g. 26). Single-village syncs
  /// guarantee every member row belongs to that village.
  Future<void> setVillageIdForAll(String villageId) async {
    final count = await _db.db.rawUpdate(
      'UPDATE ${AppDatabase.tableMembers} SET village_id = ?',
      [villageId],
    );
    debugPrint('[MemberDao] setVillageIdForAll: $count rows → village_id=$villageId');
  }

  /// Delete all members (used before full sync).
  Future<void> deleteAll() async {
    await _db.db.delete(AppDatabase.tableMembers);
  }
}
