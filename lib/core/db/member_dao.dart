import 'package:flutter/foundation.dart';

import 'app_database.dart';

/// Entity representing a household member stored locally.
/// Matches Android HouseholdMemberEntity from spice-2.0-android uhis-dev branch.
class HouseholdMemberEntity {
  const HouseholdMemberEntity({
    required this.id,
    this.fhirId,
    this.householdId,
    this.householdFhirId,
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

  /// Local autoincrement PK as string (Spice `Long id`).
  final String id;
  final String? fhirId;
  /// Local [HouseholdEntity.id] FK (Spice `household_id` Long).
  final String? householdId;
  /// Server household FHIR id (Spice `household_fhir_id`).
  final String? householdFhirId;
  final String? householdReferenceId;
  /// Wire correlation — equals [id] for rows we enrolled.
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

  Map<String, dynamic> toDb({bool includeId = true}) {
    final map = <String, dynamic>{
      'fhir_id': fhirId,
      'household_id':
          householdId == null ? null : (int.tryParse(householdId!) ?? householdId),
      'household_fhir_id': householdFhirId,
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
    if (includeId && id.isNotEmpty && id != '0') {
      map['id'] = int.tryParse(id) ?? id;
    }
    return map;
  }

  HouseholdMemberEntity copyWith({
    String? id,
    String? fhirId,
    String? householdId,
    String? householdFhirId,
    String? householdReferenceId,
    String? referenceId,
    String? name,
    String? gender,
    String? dob,
    String? phone,
    String? phoneNumberCategory,
    String? nationalId,
    String? patientId,
    String? villageId,
    String? villageName,
    String? subVillageId,
    String? subVillageName,
    String? shasthyaShebikaId,
    bool? isActive,
    bool? isHouseholdHead,
    bool? isPregnant,
    String? relation,
    String? initial,
    String? signature,
    String? localSignatureFile,
    String? motherPatientId,
    String? motherReferenceId,
    String? maritalStatus,
    String? disability,
    String? guardianId,
    String? guardianFhirId,
    double? latitude,
    double? longitude,
    String? idType,
    String? version,
    String? lastUpdated,
    int? createdAt,
    int? updatedAt,
    String? syncStatus,
    String? rawJson,
  }) {
    return HouseholdMemberEntity(
      id: id ?? this.id,
      fhirId: fhirId ?? this.fhirId,
      householdId: householdId ?? this.householdId,
      householdFhirId: householdFhirId ?? this.householdFhirId,
      householdReferenceId: householdReferenceId ?? this.householdReferenceId,
      referenceId: referenceId ?? this.referenceId,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      phone: phone ?? this.phone,
      phoneNumberCategory: phoneNumberCategory ?? this.phoneNumberCategory,
      nationalId: nationalId ?? this.nationalId,
      patientId: patientId ?? this.patientId,
      villageId: villageId ?? this.villageId,
      villageName: villageName ?? this.villageName,
      subVillageId: subVillageId ?? this.subVillageId,
      subVillageName: subVillageName ?? this.subVillageName,
      shasthyaShebikaId: shasthyaShebikaId ?? this.shasthyaShebikaId,
      isActive: isActive ?? this.isActive,
      isHouseholdHead: isHouseholdHead ?? this.isHouseholdHead,
      isPregnant: isPregnant ?? this.isPregnant,
      relation: relation ?? this.relation,
      initial: initial ?? this.initial,
      signature: signature ?? this.signature,
      localSignatureFile: localSignatureFile ?? this.localSignatureFile,
      motherPatientId: motherPatientId ?? this.motherPatientId,
      motherReferenceId: motherReferenceId ?? this.motherReferenceId,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      disability: disability ?? this.disability,
      guardianId: guardianId ?? this.guardianId,
      guardianFhirId: guardianFhirId ?? this.guardianFhirId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      idType: idType ?? this.idType,
      version: version ?? this.version,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rawJson: rawJson ?? this.rawJson,
    );
  }

  /// Returns a copy with location fields overridden (null means keep existing).
  HouseholdMemberEntity copyWithVillage({
    String? villageId,
    String? subVillageId,
    String? shasthyaShebikaId,
  }) {
    return copyWith(
      villageId: villageId ?? this.villageId,
      subVillageId: subVillageId ?? this.subVillageId,
      shasthyaShebikaId: shasthyaShebikaId ?? this.shasthyaShebikaId,
    );
  }

  factory HouseholdMemberEntity.fromDb(Map<String, dynamic> row) {
    return HouseholdMemberEntity(
      id: row['id']?.toString() ?? '',
      fhirId: row['fhir_id'] as String?,
      householdId: row['household_id']?.toString(),
      householdFhirId: row['household_fhir_id'] as String?,
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
    final isHead = relation?.toLowerCase() == 'householdhead' ||
        relation?.toLowerCase() == 'self' ||
        parseBool(json['isHouseholdHead']);

    // Spice HouseHoldMember JSON mapping:
    // - JSON 'id' → fhir_id
    // - JSON 'referenceId' → local correlation (may equal local PK after status)
    // - JSON 'householdId' → household_fhir_id
    // Local PK is assigned by insertOrUpdateFromBE, not here.
    final fhirId = str('id');
    final referenceId = str('referenceId') ?? str('memberId');
    final householdFhirId = str('householdId') ?? str('household_id');

    return HouseholdMemberEntity(
      id: referenceId ?? '0',
      fhirId: fhirId,
      householdId: null, // resolved to local HH id during sync persist
      householdFhirId: householdFhirId,
      householdReferenceId:
          str('householdReferenceId') ?? str('household_reference_id'),
      referenceId: referenceId,
      name: str('name'),
      gender: str('gender'),
      dob: str('dateOfBirth') ?? str('dob'),
      phone: str('phoneNumber') ?? str('phone'),
      phoneNumberCategory:
          str('phoneNumberCategory') ?? str('phone_number_category'),
      nationalId: str('nationalId') ?? str('national_id'),
      patientId: str('patientId') ?? str('patient_id'),
      villageId: str('villageId') ?? str('village_id'),
      villageName: str('village') ?? str('villageName') ?? str('village_name'),
      subVillageId: str('subVillageId') ?? str('sub_village_id'),
      subVillageName:
          str('subVillage') ?? str('subVillageName') ?? str('sub_village_name'),
      shasthyaShebikaId:
          str('shasthyaShebikaId') ?? str('shasthya_shebika_id'),
      isActive: json['isActive'] != false,
      isHouseholdHead: isHead,
      isPregnant: parseBool(json['isPregnant']),
      relation: relation,
      initial: str('initial'),
      signature: str('signature'),
      localSignatureFile:
          str('localSignatureFile') ?? str('local_signature_file'),
      motherPatientId: str('motherPatientId') ??
          str('mother_patient_id') ??
          str('parentId'),
      motherReferenceId:
          str('motherReferenceId') ?? str('mother_reference_id'),
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
      rawJson: null,
    );
  }
}

/// Data-access for the `members` table — the local cache of household members.
/// Following spice-2.0-android pattern: all reads are from local SQLite,
/// network sync populates the local cache.
class MemberDao {
  MemberDao(this._db);

  final AppDatabase _db;

  /// Insert a new local member (autoincrement). Returns the local id string.
  Future<String> insertLocal(HouseholdMemberEntity member) async {
    final id = await _db.db.insert(
      AppDatabase.tableMembers,
      member.toDb(includeId: false),
    );
    return id.toString();
  }

  Future<HouseholdMemberEntity?> getByFhirId(String fhirId) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'fhir_id = ?',
      whereArgs: [fhirId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HouseholdMemberEntity.fromDb(rows.first);
  }

  /// Local row still awaiting its server id, matched on the reference we sent.
  ///
  /// Deliberately not a primary-key lookup: `referenceId` is only ours while
  /// the row is unstamped. Every device numbers its rows from 1, so treating an
  /// incoming referenceId as a local PK would let another device's member
  /// overwrite an unrelated row of ours that happens to share that number.
  Future<HouseholdMemberEntity?> getUnstampedByReferenceId(
      String referenceId) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: "reference_id = ? AND (fhir_id IS NULL OR fhir_id = '')",
      whereArgs: [referenceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HouseholdMemberEntity.fromDb(rows.first);
  }

  /// Spice `MemberDAO.insertOrUpdateFromBE`: merge by [fhirId], keep local PK.
  /// Also matches [referenceId] → local id to avoid duplicates when pull races
  /// the status stamp.
  Future<String> insertOrUpdateFromBE(HouseholdMemberEntity entity) async {
    final fhir = entity.fhirId;
    HouseholdMemberEntity? existing = (fhir != null && fhir.isNotEmpty)
        ? await getByFhirId(fhir)
        : null;

    if (existing == null &&
        entity.referenceId != null &&
        entity.referenceId!.isNotEmpty) {
      existing = await getUnstampedByReferenceId(entity.referenceId!);
    }

    // A row we created and haven't had confirmed yet: stamp it, never let the
    // server echo overwrite the form data the health worker just entered.
    final existingUnstamped =
        existing != null && (existing.fhirId == null || existing.fhirId!.isEmpty);
    if (existing?.syncStatus == 'NotSynced' || existingUnstamped) {
      if (fhir != null && fhir.isNotEmpty) {
        await updateFhirId(
          localId: existing!.id,
          fhirId: fhir,
          syncStatus: 'Success',
        );
      }
      return existing!.id;
    }

    if (existing != null) {
      final merged = entity.copyWith(
        id: existing.id,
        syncStatus: entity.syncStatus.isNotEmpty ? entity.syncStatus : 'Success',
        fhirId: fhir ?? existing.fhirId,
        householdId: entity.householdId ?? existing.householdId,
        householdFhirId: entity.householdFhirId ?? existing.householdFhirId,
        referenceId: entity.referenceId ?? existing.referenceId,
        isHouseholdHead: entity.isHouseholdHead || existing.isHouseholdHead,
      );
      await _db.db.update(
        AppDatabase.tableMembers,
        merged.toDb(includeId: false),
        where: 'id = ?',
        whereArgs: [int.tryParse(existing.id) ?? existing.id],
      );
      return existing.id;
    }

    final id = await _db.db.insert(
      AppDatabase.tableMembers,
      entity.copyWith(syncStatus: 'Success').toDb(includeId: false),
    );
    return id.toString();
  }

  /// Stamp FHIR id after offline-sync/status Success.
  Future<void> updateFhirId({
    required String localId,
    required String? fhirId,
    required String syncStatus,
  }) async {
    await _db.db.rawUpdate(
      '''
      UPDATE ${AppDatabase.tableMembers}
      SET fhir_id = ?,
          sync_status = CASE
            WHEN sync_status IN ('InProgress', 'NetworkError', 'NotSynced', 'Pending')
            THEN ?
            ELSE sync_status
          END,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        fhirId,
        syncStatus,
        DateTime.now().millisecondsSinceEpoch,
        int.tryParse(localId) ?? localId,
      ],
    );
  }

  /// Points `reference_id` (what the push echoes) at the local PK after insert.
  ///
  /// Does **not** set `patient_id` — Spice leaves `HouseholdMember.patient_id`
  /// null for newly created members until the server assigns one on sync pull.
  /// Writing the local PK here made Flutter assessments send `"279"`-style ids.
  Future<void> setReferenceId(String localId) async {
    await _db.db.update(
      AppDatabase.tableMembers,
      {'reference_id': localId},
      where: 'id = ?',
      whereArgs: [int.tryParse(localId) ?? localId],
    );
  }

  /// Bulk merge from sync pull.
  Future<void> upsertManyFromBE(List<HouseholdMemberEntity> members) async {
    for (final m in members) {
      await insertOrUpdateFromBE(m);
    }
  }

  /// Prefer [upsertManyFromBE] for sync; kept for call-site compatibility.
  Future<void> upsertMany(List<HouseholdMemberEntity> members) async {
    await upsertManyFromBE(members);
  }

  /// No-op under Spice identity — merge keeps the local row.
  @Deprecated('Placeholders are no longer deleted; merge by fhir_id instead')
  Future<void> removeLocalPlaceholders(
      List<HouseholdMemberEntity> incoming) async {
    // Intentionally empty — Option A never deletes the local PK row.
  }

  /// Mark a member active/inactive (Android updateMemberDeceasedStatus).
  Future<void> updateActiveStatus(
    String id, {
    required bool isActive,
    String syncStatus = 'NotSynced',
  }) async {
    await _db.db.update(
      AppDatabase.tableMembers,
      {
        'is_active': isActive ? 1 : 0,
        'sync_status': syncStatus,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [int.tryParse(id) ?? id],
    );
  }

  static const _pendingStatuses = ['NotSynced', 'NetworkError', 'Pending'];

  /// Members waiting to push via offline-sync/create (new babies, etc.).
  ///
  /// Only rows that were locally created for createHouseHoldMember — mothers
  /// marked inactive keep their prior sync_status and are excluded.
  Future<List<HouseholdMemberEntity>> getUnsynced() async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where:
          "(sync_status = 'NotSynced' OR sync_status = 'Pending') "
          "AND mother_reference_id IS NOT NULL "
          "AND mother_reference_id != ''",
      orderBy: 'created_at ASC',
    );
    return rows.map(HouseholdMemberEntity.fromDb).toList();
  }

  /// Count of all members waiting for offline-sync/create (Spice parity).
  Future<int> getUnsyncedCount() async {
    final ph = List.filled(_pendingStatuses.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableMembers} '
      'WHERE sync_status IN ($ph)',
      _pendingStatuses,
    );
    final c = rows.first['c'];
    return c is num ? c.toInt() : 0;
  }

  /// NotSynced members belonging to a NotSynced household (nested under
  /// `households[].householdMembers` — Spice `getAllUnSyncedHouseHoldMembers`).
  Future<List<HouseholdMemberEntity>> getUnsyncedForHousehold(
    String householdLocalId, {
    List<String> excludeIds = const [],
  }) async {
    final statusPh = List.filled(_pendingStatuses.length, '?').join(',');
    final args = <Object?>[
      int.tryParse(householdLocalId) ?? householdLocalId,
      ..._pendingStatuses,
    ];
    var excludeClause = '';
    if (excludeIds.isNotEmpty) {
      final ePh = List.filled(excludeIds.length, '?').join(',');
      excludeClause = ' AND id NOT IN ($ePh)';
      args.addAll(excludeIds.map((id) => int.tryParse(id) ?? id));
    }
    final rows = await _db.db.rawQuery(
      'SELECT * FROM ${AppDatabase.tableMembers} '
      'WHERE household_id = ? AND sync_status IN ($statusPh) '
      "AND (fhir_id IS NULL OR fhir_id = '')"
      '$excludeClause '
      'ORDER BY created_at ASC',
      args,
    );
    return rows.map(HouseholdMemberEntity.fromDb).toList();
  }

  /// Standalone NotSynced members whose household is already stamped (or has
  /// no household) — Spice `getOtherHouseholdMembers`. Excludes [excludeIds]
  /// already nested under a household payload in the same push.
  Future<List<HouseholdMemberEntity>> getOtherUnsyncedMembers({
    List<String> excludeIds = const [],
  }) async {
    final statusPh = List.filled(_pendingStatuses.length, '?').join(',');
    final args = <Object?>[..._pendingStatuses];
    var excludeClause = '';
    if (excludeIds.isNotEmpty) {
      final ePh = List.filled(excludeIds.length, '?').join(',');
      excludeClause = ' AND m.id NOT IN ($ePh)';
      args.addAll(excludeIds.map((id) => int.tryParse(id) ?? id));
    }
    final rows = await _db.db.rawQuery(
      'SELECT m.* FROM ${AppDatabase.tableMembers} m '
      'LEFT JOIN ${AppDatabase.tableHouseholds} h ON h.id = m.household_id '
      'WHERE m.sync_status IN ($statusPh) '
      'AND (m.household_id IS NULL OR (h.fhir_id IS NOT NULL AND h.fhir_id != \'\')) '
      '$excludeClause '
      'ORDER BY m.created_at ASC',
      args,
    );
    return rows.map(HouseholdMemberEntity.fromDb).toList();
  }

  /// Flip sync_status for a batch of local member PKs.
  Future<void> updateSyncStatus(List<String> ids, String syncStatus) async {
    if (ids.isEmpty) return;
    final ph = List.filled(ids.length, '?').join(',');
    await _db.db.rawUpdate(
      'UPDATE ${AppDatabase.tableMembers} '
      'SET sync_status = ?, updated_at = ? '
      'WHERE id IN ($ph)',
      [
        syncStatus,
        DateTime.now().millisecondsSinceEpoch,
        ...ids.map((id) => int.tryParse(id) ?? id),
      ],
    );
  }

  /// Reclaim rows left InProgress after a killed push (age-gated).
  Future<int> resetStuckInProgress({
    Duration olderThan = const Duration(minutes: 15),
  }) async {
    final cutoff =
        DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    return _db.db.rawUpdate(
      'UPDATE ${AppDatabase.tableMembers} '
      "SET sync_status = 'NotSynced', updated_at = ? "
      "WHERE sync_status = 'InProgress' AND updated_at < ?",
      [DateTime.now().millisecondsSinceEpoch, cutoff],
    );
  }

  /// Mark members as successfully synced.
  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    await updateSyncStatus(ids, 'Success');
  }

  /// Get all members for a household (LOCAL query, no network).
  /// [householdId] is the local households.id (numeric string).
  Future<List<HouseholdMemberEntity>> getByHouseholdId(String householdId) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'household_id = ?',
      whereArgs: [int.tryParse(householdId) ?? householdId],
      orderBy: 'name ASC',
    );
    return rows.map(HouseholdMemberEntity.fromDb).toList();
  }

  /// Also resolve by household FHIR id (for screens that still pass server ids).
  Future<List<HouseholdMemberEntity>> getByHouseholdFhirId(
      String householdFhirId) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'household_fhir_id = ?',
      whereArgs: [householdFhirId],
      orderBy: 'name ASC',
    );
    return rows.map(HouseholdMemberEntity.fromDb).toList();
  }

  /// Get member by local ID, falling back to fhir_id for legacy callers.
  Future<HouseholdMemberEntity?> getById(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'id = ?',
      whereArgs: [int.tryParse(id) ?? id],
      limit: 1,
    );
    if (rows.isNotEmpty) return HouseholdMemberEntity.fromDb(rows.first);
    return getByFhirId(id);
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

  /// Get member by national ID (LOCAL query, no network).
  Future<HouseholdMemberEntity?> getByNationalId(String nid) async {
    if (nid.trim().isEmpty) return null;
    final rows = await _db.db.query(
      AppDatabase.tableMembers,
      where: 'national_id = ?',
      whereArgs: [nid.trim()],
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

    // Group by stable local household_id (Spice FK). No UUID/FHIR dual-key
    // normalization needed under Option A.
    final grouped = <String, List<HouseholdMemberEntity>>{};
    for (final row in rows) {
      final member = HouseholdMemberEntity.fromDb(row);
      final key = member.householdId ?? '';
      grouped.putIfAbsent(key, () => []).add(member);
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
  ///
  /// Grouped by village_id (not `DISTINCT village_id, village_name`) so a
  /// village_id that was synced with more than one village_name spelling
  /// still yields exactly one row. Two rows sharing a `value` would make the
  /// filter-tab UI mark both tabs active for a single selection, since tab
  /// selection is compared by that value alone.
  Future<List<({String id, String name})>> getDistinctVillages() async {
    final rows = await _db.db.rawQuery('''
      SELECT village_id, MIN(NULLIF(TRIM(village_name), '')) AS village_name
      FROM ${AppDatabase.tableMembers}
      WHERE village_id IS NOT NULL AND village_id != ''
      GROUP BY village_id
      ORDER BY COALESCE(MIN(NULLIF(TRIM(village_name), '')), village_id) ASC
    ''');
    return rows.map((r) {
      final id = r['village_id'].toString();
      final name = (r['village_name'] as String?)?.trim();
      return (id: id, name: (name != null && name.isNotEmpty) ? name : id);
    }).toList();
  }

  /// Returns distinct (subVillageId, subVillageName) pairs for filter UI.
  ///
  /// Grouped by sub_village_id (not `DISTINCT sub_village_id,
  /// sub_village_name`) for the same reason as [getDistinctVillages]: a
  /// sub_village_id synced with more than one name spelling must still
  /// yield exactly one row, or filter-tab selection (compared by value)
  /// would mark two tabs active for a single tap.
  Future<List<({String id, String name})>> getDistinctSubVillages({
    String? villageId,
  }) async {
    final where = villageId != null
        ? 'sub_village_id IS NOT NULL AND sub_village_id != \'\' AND village_id = ?'
        : 'sub_village_id IS NOT NULL AND sub_village_id != \'\'';
    final rows = await _db.db.rawQuery(
      '''
      SELECT sub_village_id, MIN(NULLIF(TRIM(sub_village_name), '')) AS sub_village_name
      FROM ${AppDatabase.tableMembers}
      WHERE $where
      GROUP BY sub_village_id
      ORDER BY COALESCE(MIN(NULLIF(TRIM(sub_village_name), '')), sub_village_id) ASC
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
      final hhId = row['household_id']?.toString();
      final count = row['count'] as int? ?? 0;
      if (hhId != null) {
        counts[hhId] = count;
      }
    }
    return counts;
  }

  /// Bulk-lookup: any known member identifier → the local patient key.
  ///
  /// Servers refer to a member by whichever id they hold: the backend PK
  /// (`fhir_id` under the Spice identity model — this is what assessment
  /// history's `householdMemberId` carries), the `reference_id` we echoed on
  /// push, or a separate `patient_id`. All of them resolve to `members.id`,
  /// because that is the value `_memberToPatient` writes as `patients.id` and
  /// therefore the key every side table (programmes, follow-ups, assessments,
  /// encounters, referrals) must use for the worklist join to find them.
  Future<Map<String, String>> patientIdsByMemberIds(List<String> memberIds) async {
    if (memberIds.isEmpty) return const {};
    final ph = List.filled(memberIds.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT id, fhir_id, reference_id, patient_id '
      'FROM ${AppDatabase.tableMembers} '
      'WHERE id IN ($ph) OR fhir_id IN ($ph) OR reference_id IN ($ph) '
      'OR patient_id IN ($ph)',
      [...memberIds, ...memberIds, ...memberIds, ...memberIds],
    );
    final result = <String, String>{};
    for (final row in rows) {
      final localId = row['id']?.toString();
      if (localId == null || localId.isEmpty) continue;
      for (final alias in [
        localId,
        row['fhir_id'],
        row['reference_id'],
        row['patient_id'],
      ]) {
        final key = alias?.toString();
        if (key != null && key.isNotEmpty) result[key] = localId;
      }
    }
    return result;
  }

  /// No-op — kept for call-site compatibility.
  ///
  /// Previously filled blank `patient_id` with the local member PK. That diverged
  /// from Spice (`HouseholdMember.patient_id` stays null until the server
  /// assigns it) and caused assessment sync to emit local ids like `"279"`.
  /// Household / patient joins already fall back to `members.id` when
  /// `patient_id` is empty.
  Future<int> backfillPatientIds() async => 0;

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
