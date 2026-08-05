import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Entity representing a household stored locally.
///
/// Spice-parity identity:
/// * [id] — local autoincrement PK (stable forever; Dart string form of Long)
/// * [fhirId] — server id, stamped by status API / pull merge
/// * [referenceId] — wire correlation (equals [id] for rows we enrolled)
class HouseholdEntity {
  const HouseholdEntity({
    required this.id,
    this.fhirId,
    this.referenceId,
    this.householdNo,
    this.name,
    this.village,
    this.villageId,
    this.subVillageId,
    this.subVillageName,
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

  /// Local autoincrement PK as string (Spice `Long id`).
  final String id;
  final String? fhirId;
  final String? referenceId;
  final String? householdNo;
  final String? name;

  /// Parent village name / id — never the sub-village (see [subVillageId]).
  final String? village;
  final String? villageId;
  final String? subVillageId;
  final String? subVillageName;
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

  /// Row map for insert/update. Omits [id] when empty/`0` so SQLite can
  /// autoincrement (mirrors Room `@PrimaryKey(autoGenerate = true)`).
  Map<String, dynamic> toDb({bool includeId = true}) {
    final map = <String, dynamic>{
      'fhir_id': fhirId,
      'reference_id': referenceId,
      'household_no': householdNo,
      'name': name,
      'village': village,
      'village_id': villageId,
      'sub_village_id': subVillageId,
      'sub_village_name': subVillageName,
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
    if (includeId && id.isNotEmpty && id != '0') {
      map['id'] = int.tryParse(id) ?? id;
    }
    return map;
  }

  HouseholdEntity copyWith({
    String? id,
    String? fhirId,
    String? referenceId,
    String? householdNo,
    String? name,
    String? village,
    String? villageId,
    String? subVillageId,
    String? subVillageName,
    int? memberCount,
    String? landmark,
    String? headPhoneNumber,
    String? headPhoneNumberCategory,
    double? latitude,
    double? longitude,
    bool? isOwnedAnImprovedLatrine,
    bool? isOwnedHandWashingFacilityWithSoap,
    bool? isOwnedATreatedBedNet,
    int? bedNetCount,
    String? version,
    String? lastUpdated,
    int? createdAt,
    int? updatedAt,
    String? syncStatus,
    String? rawJson,
  }) {
    return HouseholdEntity(
      id: id ?? this.id,
      fhirId: fhirId ?? this.fhirId,
      referenceId: referenceId ?? this.referenceId,
      householdNo: householdNo ?? this.householdNo,
      name: name ?? this.name,
      village: village ?? this.village,
      villageId: villageId ?? this.villageId,
      subVillageId: subVillageId ?? this.subVillageId,
      subVillageName: subVillageName ?? this.subVillageName,
      memberCount: memberCount ?? this.memberCount,
      landmark: landmark ?? this.landmark,
      headPhoneNumber: headPhoneNumber ?? this.headPhoneNumber,
      headPhoneNumberCategory:
          headPhoneNumberCategory ?? this.headPhoneNumberCategory,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isOwnedAnImprovedLatrine:
          isOwnedAnImprovedLatrine ?? this.isOwnedAnImprovedLatrine,
      isOwnedHandWashingFacilityWithSoap: isOwnedHandWashingFacilityWithSoap ??
          this.isOwnedHandWashingFacilityWithSoap,
      isOwnedATreatedBedNet:
          isOwnedATreatedBedNet ?? this.isOwnedATreatedBedNet,
      bedNetCount: bedNetCount ?? this.bedNetCount,
      version: version ?? this.version,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rawJson: rawJson ?? this.rawJson,
    );
  }

  factory HouseholdEntity.fromDb(Map<String, dynamic> row) {
    return HouseholdEntity(
      id: row['id']?.toString() ?? '',
      fhirId: row['fhir_id'] as String?,
      referenceId: row['reference_id'] as String?,
      householdNo: row['household_no'] as String?,
      name: row['name'] as String?,
      village: row['village'] as String?,
      villageId: row['village_id'] as String?,
      subVillageId: row['sub_village_id'] as String?,
      subVillageName: row['sub_village_name'] as String?,
      memberCount: row['member_count'] as int?,
      landmark: row['landmark'] as String?,
      headPhoneNumber: row['head_phone_number'] as String?,
      headPhoneNumberCategory: row['head_phone_number_category'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      isOwnedAnImprovedLatrine:
          (row['is_owned_an_improved_latrine'] as int?) == 1,
      isOwnedHandWashingFacilityWithSoap:
          (row['is_owned_hand_washing_facility'] as int?) == 1,
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

  /// Parse a fetch-synced-data / create-status household JSON.
  ///
  /// Spice mapping: JSON `id` → [fhirId], JSON `referenceId` → correlation.
  /// Local [id] is assigned by [HouseholdDao.insertOrUpdateFromBE], not here.
  factory HouseholdEntity.fromApiJson(Map<String, dynamic> json) {
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

    int? parseInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    double? parseDouble(dynamic v) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim());
      return null;
    }

    int? createdAt;
    int? updatedAt;
    final createdAtVal = json['createdAt'] ?? json['created_at'];
    final updatedAtVal = json['updatedAt'] ?? json['updated_at'];
    if (createdAtVal is int) createdAt = createdAtVal;
    if (createdAtVal is num) createdAt = createdAtVal.toInt();
    if (updatedAtVal is int) updatedAt = updatedAtVal;
    if (updatedAtVal is num) updatedAt = updatedAtVal.toInt();

    final memberCount = parseInt(json['noOfPeople'] ??
        json['memberCount'] ??
        json['member_count'] ??
        json['numberOfMembers']);

    final fhirId = str('id');
    final referenceId = str('referenceId');

    return HouseholdEntity(
      // Placeholder — insertOrUpdateFromBE assigns/keeps the local PK.
      id: referenceId ?? '0',
      fhirId: fhirId,
      referenceId: referenceId,
      householdNo: str('householdNo') ?? str('household_no'),
      name: str('name') ?? str('householdName'),
      village: str('villageName') ?? str('village'),
      villageId: str('villageId') ?? str('village_id'),
      subVillageId: str('subVillageId') ?? str('sub_village_id'),
      subVillageName: str('subVillageName') ?? str('sub_village_name'),
      memberCount: memberCount,
      landmark: str('landmark'),
      headPhoneNumber: str('headPhoneNumber') ?? str('head_phone_number'),
      headPhoneNumberCategory:
          str('headPhoneNumberCategory') ?? str('head_phone_number_category'),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      isOwnedAnImprovedLatrine: parseBool(json['ownedAnImprovedLatrine'] ??
          json['isOwnedAnImprovedLatrine'] ??
          json['is_owned_an_improved_latrine']),
      isOwnedHandWashingFacilityWithSoap: parseBool(
          json['ownedHandWashingFacilityWithSoap'] ??
              json['isOwnedHandWashingFacilityWithSoap'] ??
              json['is_owned_hand_washing_facility_with_soap']),
      isOwnedATreatedBedNet: parseBool(json['ownedTreatedBedNet'] ??
          json['isOwnedATreatedBedNet'] ??
          json['is_owned_a_treated_bed_net']),
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

/// Data-access for the `households` table — Spice-parity local cache.
class HouseholdDao {
  HouseholdDao(this._db);

  final AppDatabase _db;

  /// Insert a new local household (autoincrement). Returns the local id string.
  Future<String> insertLocal(HouseholdEntity household) async {
    final id = await _db.db.insert(
      AppDatabase.tableHouseholds,
      household.toDb(includeId: false),
    );
    return id.toString();
  }

  /// Lookup by server FHIR id (unique index).
  Future<HouseholdEntity?> getByFhirId(String fhirId) async {
    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      where: 'fhir_id = ?',
      whereArgs: [fhirId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HouseholdEntity.fromDb(rows.first);
  }

  /// Local row still awaiting its server id, matched on the reference we sent.
  ///
  /// Deliberately not a primary-key lookup: `referenceId` is only ours while
  /// the row is unstamped. Every device numbers its rows from 1, so treating an
  /// incoming referenceId as a local PK would let another device's household
  /// overwrite an unrelated row of ours that happens to share that number.
  Future<HouseholdEntity?> getUnstampedByReferenceId(String referenceId) async {
    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      where: "reference_id = ? AND (fhir_id IS NULL OR fhir_id = '')",
      whereArgs: [referenceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HouseholdEntity.fromDb(rows.first);
  }

  /// Spice `HouseholdDAO.insertOrUpdateFromBE`: merge by [fhirId], keep local PK.
  /// Also matches [referenceId] → local id so a pull that races status stamp
  /// cannot insert a second row for the same enrollment.
  Future<String> insertOrUpdateFromBE(HouseholdEntity entity) async {
    final fhir = entity.fhirId;
    HouseholdEntity? existing = (fhir != null && fhir.isNotEmpty)
        ? await getByFhirId(fhir)
        : null;

    // Race-safe: status may not have stamped fhir_id yet; bundle still echoes
    // our local PK as referenceId.
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
        referenceId: entity.referenceId ?? existing.referenceId,
      );
      await _db.db.update(
        AppDatabase.tableHouseholds,
        merged.toDb(includeId: false),
        where: 'id = ?',
        whereArgs: [int.tryParse(existing.id) ?? existing.id],
      );
      return existing.id;
    }

    final id = await _db.db.insert(
      AppDatabase.tableHouseholds,
      entity.copyWith(syncStatus: 'Success').toDb(includeId: false),
    );
    return id.toString();
  }

  /// Stamp FHIR id after offline-sync/status Success (Spice `updateFhirId`).
  Future<void> updateFhirId({
    required String localId,
    required String? fhirId,
    required String syncStatus,
  }) async {
    await _db.db.rawUpdate(
      '''
      UPDATE ${AppDatabase.tableHouseholds}
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

  /// Set wire [reference_id] to equal the local PK after insert.
  Future<void> setReferenceId(String localId) async {
    await _db.db.update(
      AppDatabase.tableHouseholds,
      {'reference_id': localId},
      where: 'id = ?',
      whereArgs: [int.tryParse(localId) ?? localId],
    );
  }

  /// Keep [member_count] in sync with the local members table after link /
  /// enroll (Android bumps `noOfPeople` when actual headcount grows).
  Future<void> setMemberCount(String householdId, int count) async {
    await _db.db.update(
      AppDatabase.tableHouseholds,
      {
        'member_count': count,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [int.tryParse(householdId) ?? householdId],
    );
  }

  /// Bulk merge from sync pull — each row goes through [insertOrUpdateFromBE].
  /// Returns map of fhirId → localId for member FK resolution.
  Future<Map<String, String>> upsertManyFromBE(
      List<HouseholdEntity> households) async {
    final fhirToLocal = <String, String>{};
    for (final h in households) {
      final localId = await insertOrUpdateFromBE(h);
      final fhir = h.fhirId;
      if (fhir != null && fhir.isNotEmpty) {
        fhirToLocal[fhir] = localId;
      }
    }
    return fhirToLocal;
  }

  /// Legacy bulk upsert — prefer [upsertManyFromBE] for sync.
  Future<void> upsertMany(List<HouseholdEntity> households) async {
    await upsertManyFromBE(households);
  }

  Future<HouseholdEntity?> getById(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      where: 'id = ?',
      whereArgs: [int.tryParse(id) ?? id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HouseholdEntity.fromDb(rows.first);
  }

  Future<List<HouseholdEntity>> getByVillageIds(
    List<String> villageIds, {
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

  Future<List<HouseholdEntity>> getAll(
      {int limit = 100, int offset = 0}) async {
    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(HouseholdEntity.fromDb).toList();
  }

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

  Future<int> count() async {
    final result = await _db.db
        .rawQuery('SELECT COUNT(*) AS c FROM ${AppDatabase.tableHouseholds}');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static const _pendingStatuses = ['NotSynced', 'NetworkError', 'Pending'];

  /// [includeFailed] mirrors `LocalAssessmentDao`'s Manual/Initial-sync
  /// retry: without it, a household the server rejected (`'Failed'`) has no
  /// way back into `getUnsynced`/`getUnsyncedCount` at all and silently
  /// drops out of the pending count forever.
  static List<String> _statusesFor({required bool includeFailed}) =>
      includeFailed ? [..._pendingStatuses, 'Failed'] : _pendingStatuses;

  /// Count of households waiting for offline-sync/create (Spice parity).
  Future<int> getUnsyncedCount({bool includeFailed = false}) async {
    final statuses = _statusesFor(includeFailed: includeFailed);
    final ph = List.filled(statuses.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableHouseholds} '
      'WHERE sync_status IN ($ph)',
      statuses,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Count of households the server rejected on the last attempt — surfaced
  /// separately so a permanently-stuck enrollment is visible, not silently
  /// dropped from the pending count.
  Future<int> getFailedCount() async {
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableHouseholds} '
      "WHERE sync_status = 'Failed'",
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Households eligible for Manual Offline Sync push.
  Future<List<HouseholdEntity>> getUnsynced({bool includeFailed = false}) async {
    final statuses = _statusesFor(includeFailed: includeFailed);
    final ph = List.filled(statuses.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableHouseholds,
      where: 'sync_status IN ($ph)',
      whereArgs: statuses,
      orderBy: 'created_at ASC',
    );
    return rows.map(HouseholdEntity.fromDb).toList();
  }

  /// Flip sync_status for a batch of local household PKs.
  Future<void> updateSyncStatus(List<String> ids, String syncStatus) async {
    if (ids.isEmpty) return;
    final ph = List.filled(ids.length, '?').join(',');
    await _db.db.rawUpdate(
      'UPDATE ${AppDatabase.tableHouseholds} '
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
      'UPDATE ${AppDatabase.tableHouseholds} '
      "SET sync_status = 'NotSynced', updated_at = ? "
      "WHERE sync_status = 'InProgress' AND updated_at < ?",
      [DateTime.now().millisecondsSinceEpoch, cutoff],
    );
  }
}
