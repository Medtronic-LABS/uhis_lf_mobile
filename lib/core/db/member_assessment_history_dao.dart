import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Local mirror of Spice [MemberAssessmentHistoryEntity] — single source for KPI
/// dashboard counts (not for the offline upload queue).
class MemberAssessmentHistoryRow {
  const MemberAssessmentHistoryRow({
    this.id,
    required this.memberId,
    this.memberFhirId,
    required this.visitDate,
    this.serviceProvided,
    this.encounterId,
    this.customStatus,
    this.latestVisit = false,
    this.referralStatus,
    this.referralReason,
    this.nextFollowUpDate,
    this.practitionerId,
    this.observationsJson,
    this.shasthyaShebikaId,
  });

  final int? id;
  final int? memberId;
  final String? memberFhirId;
  final String visitDate;
  final String? serviceProvided;
  final String? encounterId;
  final String? customStatus;
  final bool latestVisit;
  final String? referralStatus;
  final String? referralReason;
  final String? nextFollowUpDate;
  final String? practitionerId;
  final String? observationsJson;
  final String? shasthyaShebikaId;

  Map<String, Object?> toDb() => {
        if (id != null) 'id': id,
        'member_id': memberId,
        'member_fhir_id': memberFhirId,
        'visit_date': visitDate,
        'service_provided': serviceProvided,
        'encounter_id': encounterId,
        'custom_status': customStatus,
        'latest_visit': latestVisit ? 1 : 0,
        'referral_status': referralStatus,
        'referral_reason': referralReason,
        'next_follow_up_date': nextFollowUpDate,
        'practitioner_id': practitionerId,
        'observations_json': observationsJson,
        'shasthya_shebika_id': shasthyaShebikaId,
      };

  static MemberAssessmentHistoryRow fromDb(Map<String, Object?> row) {
    return MemberAssessmentHistoryRow(
      id: row['id'] as int?,
      memberId: row['member_id'] as int?,
      memberFhirId: row['member_fhir_id'] as String?,
      visitDate: row['visit_date'] as String? ?? '',
      serviceProvided: row['service_provided'] as String?,
      encounterId: row['encounter_id'] as String?,
      customStatus: row['custom_status'] as String?,
      latestVisit: (row['latest_visit'] as int? ?? 0) == 1,
      referralStatus: row['referral_status'] as String?,
      referralReason: row['referral_reason'] as String?,
      nextFollowUpDate: row['next_follow_up_date'] as String?,
      practitionerId: row['practitioner_id'] as String?,
      observationsJson: row['observations_json'] as String?,
      shasthyaShebikaId: row['shasthya_shebika_id'] as String?,
    );
  }
}

class MemberAssessmentHistoryDao {
  MemberAssessmentHistoryDao(this._db);

  final AppDatabase _db;

  static const String tableName = 'member_assessment_history';

  /// UHIS `deleteAllMemberAssessmentHistory()` on first full download.
  Future<void> deleteAll() async {
    await _db.db.delete(tableName);
  }

  /// Inserts [rows], replacing any row with the same encounter id + service.
  ///
  /// [fromServer]: the rows come from member-assessment-history. A visit saved
  /// on this device is first written under the app's own visit id, and the
  /// server returns it under its own encounter id, so the encounter match alone
  /// leaves both rows and the dashboard counts the visit twice (LEAP-128). For
  /// server rows we also drop the device's copy of the same visit, found the way
  /// Spice's AssessmentHistoryResolver does it: same member + service + visit
  /// time (to the second, the precision the visit is uploaded with), or the
  /// local assessment the server stamped with this encounter id.
  ///
  /// Only rows written under a device visit id are dropped this way. Two
  /// server encounters that share a member, service and second are both kept.
  Future<void> upsertMany(
    List<MemberAssessmentHistoryRow> rows, {
    bool fromServer = false,
  }) async {
    if (rows.isEmpty) return;
    await _db.db.transaction((tx) async {
      final device = fromServer ? await _DeviceVisitIds.load(tx) : null;
      for (final row in rows) {
        final encounterId = row.encounterId?.trim();
        final service = row.serviceProvided?.trim().toLowerCase();
        final dbRow = row.toDb()..remove('id');
        if (encounterId != null &&
            encounterId.isNotEmpty &&
            service != null &&
            service.isNotEmpty) {
          await tx.delete(
            tableName,
            where: 'encounter_id = ? AND LOWER(service_provided) = ?',
            whereArgs: [encounterId, service],
          );
          if (device != null && device.isNotEmpty) {
            await _deleteDeviceCopies(tx, row, encounterId, service, device);
          }
        }
        await tx.insert(tableName, dbRow);
      }
    });
  }

  /// The visit id this device stored in a local assessment's `other_details`.
  /// JSON that cannot be read gives null, never an error: callers run inside
  /// a batch transaction that must not roll back over one bad row.
  static String? deviceEncounterId(String? otherDetails) {
    if (otherDetails == null || otherDetails.isEmpty) return null;
    try {
      final decoded = jsonDecode(otherDetails);
      if (decoded is! Map) return null;
      final id = decoded['encounterId']?.toString().trim();
      return id == null || id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// The visit time a row is matched on: UTC ISO-8601 cut to whole seconds.
  ///
  /// A value with no zone is read as UTC, the way SQLite reads it in
  /// [_visitSecondSql], so both sides of the comparison agree.
  static String visitSecond(String visitDate) {
    final parsed = DateTime.tryParse(visitDate.trim());
    if (parsed == null) {
      return visitDate.length >= 19 ? visitDate.substring(0, 19) : visitDate;
    }
    final utc = parsed.isUtc
        ? parsed
        : DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
            parsed.minute, parsed.second);
    return utc.toIso8601String().substring(0, 19);
  }

  /// SQL for the stored `visit_date` as a UTC second, matching [visitSecond].
  /// `strftime` converts any offset to UTC; a value it cannot read falls back
  /// to its first 19 characters.
  static const String _visitSecondSql =
      "COALESCE(strftime('%Y-%m-%dT%H:%M:%S', visit_date), "
      'substr(visit_date, 1, 19))';

  /// "Same member, same second" as SQL with its arguments, or null when the
  /// row names no member. A member part is only added when its value is
  /// present: SQLCipher on Android rejects a null bind value ("the bind value
  /// at index N is null"), unlike the desktop SQLite the unit tests run on.
  static ({String sql, List<Object> args})? _sameMemberAndSecond({
    required String visitDate,
    required int? memberId,
    required String? memberFhirId,
  }) {
    final member = <String>[];
    final memberArgs = <Object>[];
    final fhir = memberFhirId?.trim();
    if (fhir != null && fhir.isNotEmpty) {
      member.add('member_fhir_id = ?');
      memberArgs.add(fhir);
    }
    if (memberId != null) {
      member.add('member_id = ?');
      memberArgs.add(memberId);
    }
    if (member.isEmpty) return null;
    return (
      sql: '($_visitSecondSql = ? AND (${member.join(' OR ')}))',
      args: [visitSecond(visitDate), ...memberArgs],
    );
  }

  Future<void> _deleteDeviceCopies(
    DatabaseExecutor tx,
    MemberAssessmentHistoryRow row,
    String encounterId,
    String service,
    _DeviceVisitIds device,
  ) async {
    // Device ids of the local assessments the server stamped with this
    // encounter id, plus device rows of the same member at the same second.
    final toDelete = <String>{...device.stampedWith(encounterId)};
    final match = _sameMemberAndSecond(
      visitDate: row.visitDate,
      memberId: row.memberId,
      memberFhirId: row.memberFhirId,
    );
    if (match != null) {
      final candidates = await tx.rawQuery(
        'SELECT DISTINCT encounter_id FROM $tableName '
        'WHERE LOWER(service_provided) = ? AND encounter_id != ? '
        'AND ${match.sql}',
        [service, encounterId, ...match.args],
      );
      for (final c in candidates) {
        final id = c['encounter_id'] as String?;
        if (id != null && device.contains(id)) toDelete.add(id);
      }
    }
    toDelete.remove(encounterId);
    for (final id in toDelete) {
      await tx.delete(
        tableName,
        where: 'encounter_id = ? AND LOWER(service_provided) = ?',
        whereArgs: [id, service],
      );
    }
  }

  /// True when a row for the same visit is already present under another
  /// encounter id than [deviceEncounterId] (normally the server's copy).
  Future<bool> hasOtherCopyOfVisit({
    required String deviceEncounterId,
    required String? serverEncounterId,
    required String service,
    required String visitDate,
    required int? memberId,
    required String? memberFhirId,
  }) async {
    final parts = <String>[];
    final args = <Object>[];
    final match = _sameMemberAndSecond(
      visitDate: visitDate,
      memberId: memberId,
      memberFhirId: memberFhirId,
    );
    if (match != null) {
      parts.add(match.sql);
      args.addAll(match.args);
    }
    final server = serverEncounterId?.trim();
    if (server != null && server.isNotEmpty) {
      parts.add('encounter_id = ?');
      args.add(server);
    }
    if (parts.isEmpty) return false;
    final rows = await _db.db.rawQuery(
      'SELECT 1 FROM $tableName '
      'WHERE LOWER(service_provided) = ? AND encounter_id != ? '
      'AND (${parts.join(' OR ')}) LIMIT 1',
      [service.toLowerCase(), deviceEncounterId, ...args],
    );
    return rows.isNotEmpty;
  }

  /// The practitioner already stored for a visit, if any.
  Future<String?> practitionerIdFor(String encounterId, String service) async {
    final rows = await _db.db.query(
      tableName,
      columns: ['practitioner_id'],
      where: 'encounter_id = ? AND LOWER(service_provided) = ? '
          'AND practitioner_id IS NOT NULL',
      whereArgs: [encounterId, service.toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['practitioner_id'] as String?;
  }

  /// Every encounter id currently in the table.
  Future<Set<String>> encounterIds() async {
    final rows = await _db.db.rawQuery(
      'SELECT DISTINCT encounter_id FROM $tableName '
      'WHERE encounter_id IS NOT NULL',
    );
    return {for (final r in rows) r['encounter_id'] as String};
  }

  /// Removes the row written under the device's own visit id.
  Future<void> deleteByEncounter(String encounterId, String service) async {
    await _db.db.delete(
      tableName,
      where: 'encounter_id = ? AND LOWER(service_provided) = ?',
      whereArgs: [encounterId, service.toLowerCase()],
    );
  }

  /// Services Spice leaves out of this table when it saves synced history
  /// (`AssessmentUtil.isMedicalReviewVisitService`).
  static const medicalReviewServices = ['medicalreviewvisit', 'medicalreview'];

  static bool isMedicalReviewService(String? service) =>
      service != null &&
      medicalReviewServices.contains(service.trim().toLowerCase());

  /// Drops medical-review rows written before they were filtered out on sync.
  Future<int> deleteMedicalReviewRows() => _db.db.delete(
        tableName,
        where: 'LOWER(service_provided) IN '
            '(${List.filled(medicalReviewServices.length, '?').join(',')})',
        whereArgs: medicalReviewServices,
      );

  /// Earliest visit date the duplicate clean-up touches. Same value Spice
  /// Android passes from `LandingActivity`:
  /// `deleteDuplicateRecords("2026-05-01")`. Older rows are left as they are,
  /// as in Spice.
  static const String duplicateCleanUpSince = '2026-05-01';

  /// Spice `deleteDuplicateRecords`, run on every app start: keeps the first
  /// row of each member + service + visit time + custom status on or after
  /// [since]. The member is the local id, or the FHIR id when there is none,
  /// so two different members with no local id are never merged; the visit
  /// time is compared to the second, as uploads carry no milliseconds.
  Future<int> deleteDuplicateRecords({String since = duplicateCleanUpSince}) =>
      _db.db.rawDelete('''
DELETE FROM $tableName
WHERE id NOT IN (
  SELECT MIN(id) FROM $tableName
  GROUP BY COALESCE(CAST(member_id AS TEXT), member_fhir_id),
    LOWER(service_provided), $_visitSecondSql, custom_status
)
AND date(datetime(visit_date, 'localtime')) >= ?
''', [since]);

  /// Backfill `referral_status` from MAH `custom_status` (Spice SQL uses the column only,
  /// but synced rows often carry referral in the custom-status list).
  Future<void> reconcileReferralFromCustomStatus() async {
    await _db.db.execute('''
UPDATE $tableName
SET referral_status = 'Referred'
WHERE (referral_status IS NULL OR TRIM(referral_status) = '' OR referral_status = 'Recovered')
AND custom_status IS NOT NULL
AND (
  INSTR(custom_status, '"Referred"') > 0
  OR INSTR(custom_status, 'Referred To') > 0
)
''');
  }

  /// Pull referral flags from synced [assessments].raw_json into MAH.
  Future<void> reconcileReferralFromAssessmentsTable() async {
    const assessments = AppDatabase.tableAssessments;
    await _db.db.execute('''
UPDATE $tableName
SET referral_status = (
  SELECT COALESCE(
    json_extract(a.raw_json, '\$.referralStatus'),
    json_extract(a.raw_json, '\$.patientStatus')
  )
  FROM $assessments AS a
  WHERE a.id = $tableName.encounter_id
  LIMIT 1
)
WHERE (referral_status IS NULL OR TRIM(referral_status) = '' OR referral_status = 'Recovered')
AND EXISTS (
  SELECT 1 FROM $assessments AS a
  WHERE a.id = $tableName.encounter_id
  AND COALESCE(
    json_extract(a.raw_json, '\$.referralStatus'),
    json_extract(a.raw_json, '\$.patientStatus')
  ) IS NOT NULL
  AND TRIM(COALESCE(
    json_extract(a.raw_json, '\$.referralStatus'),
    json_extract(a.raw_json, '\$.patientStatus')
  )) != ''
)
''');
  }

  /// Insert MAH rows for synced NCD [assessments] missing from MAH (date window).
  Future<int> supplementFromAssessmentsTable({
    required String startDate,
    required String endDate,
  }) async {
    const assessments = AppDatabase.tableAssessments;
    const members = AppDatabase.tableMembers;
    final legacy = await _db.db.rawQuery(
      '''
SELECT a.*, m.id AS local_member_id
FROM $assessments AS a
LEFT JOIN $members AS m ON m.patient_id = a.patient_id OR m.fhir_id = a.patient_id
WHERE LOWER(a.kind) IN ('ncd', 'bd_ncd')
  AND date(datetime(a.occurred_at / 1000, 'unixepoch', 'localtime')) >= ?
  AND date(datetime(a.occurred_at / 1000, 'unixepoch', 'localtime')) <= ?
''',
      [startDate, endDate],
    );
    if (legacy.isEmpty) return 0;
    var added = 0;
    final rows = <MemberAssessmentHistoryRow>[];
    for (final r in legacy) {
      final encounterId = r['id'] as String?;
      if (encounterId == null || encounterId.isEmpty) continue;
      final existing = await _db.db.rawQuery(
        'SELECT 1 FROM $tableName WHERE encounter_id = ? LIMIT 1',
        [encounterId],
      );
      if (existing.isNotEmpty) continue;

      final raw = r['raw_json'] as String? ?? '{}';
      Map<String, dynamic> map;
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        map = {};
      }
      final visitMs = r['occurred_at'] as int? ??
          _epochFromMap(map, const ['visitDate', 'assessmentDate']);
      if (visitMs == null) continue;
      final visitDate =
          DateTime.fromMillisecondsSinceEpoch(visitMs).toUtc().toIso8601String();
      final memberFhir = _stringFromMap(map, const [
        'householdMemberId',
        'memberId',
        'memberFhirId',
      ]) ??
          r['patient_id'] as String?;
      final localMemberId = int.tryParse('${r['local_member_id'] ?? ''}');
      rows.add(
        MemberAssessmentHistoryRow(
          memberId: localMemberId,
          memberFhirId: memberFhir,
          visitDate: visitDate,
          serviceProvided: 'ncd',
          encounterId: encounterId,
          customStatus: _encodeCustomStatus(map['customStatus']),
          referralStatus: _stringFromMap(map, const [
            'referralStatus',
            'patientStatus',
          ]),
          observationsJson: map['observations'] != null
              ? jsonEncode(map['observations'])
              : null,
        ),
      );
      added++;
    }
    if (rows.isNotEmpty) await upsertMany(rows, fromServer: true);
    return added;
  }

  /// Clears stale practitioner stamps so dashboard SQL matches Spice village-scoped MAH
  /// (`practitionerId IS NULL OR practitionerId IS :userId`).
  Future<void> clearNonMatchingPractitionerIds(String? userFhirId) async {
    if (userFhirId == null || userFhirId.isEmpty) return;
    await _db.db.rawUpdate(
      'UPDATE $tableName SET practitioner_id = NULL '
      'WHERE practitioner_id IS NOT NULL AND practitioner_id != ?',
      [userFhirId],
    );
  }

  /// Fills missing MAH referral flags from [local_assessments] (Spice stores these on MAH).
  Future<void> reconcileReferralStatusFromLocalAssessments() async {
    const la = AppDatabase.tableLocalAssessments;
    await _db.db.execute('''
UPDATE $tableName
SET referral_status = (
  SELECT COALESCE(NULLIF(TRIM(la.referral_status), ''), 'Referred')
  FROM $la AS la
  WHERE la.is_referred = 1
  AND (
    $tableName.encounter_id = la.id
    OR (
      la.other_details IS NOT NULL
      AND json_extract(la.other_details, '\$.encounterId') IS NOT NULL
      AND $tableName.encounter_id = json_extract(la.other_details, '\$.encounterId')
    )
  )
  LIMIT 1
)
WHERE (referral_status IS NULL OR TRIM(referral_status) = '' OR referral_status = 'Recovered')
AND EXISTS (
  SELECT 1 FROM $la AS la
  WHERE la.is_referred = 1
  AND (
    $tableName.encounter_id = la.id
    OR (
      la.other_details IS NOT NULL
      AND json_extract(la.other_details, '\$.encounterId') IS NOT NULL
      AND $tableName.encounter_id = json_extract(la.other_details, '\$.encounterId')
    )
  )
)
''');
  }

  Future<int> countAll() async {
    final v = Sqflite.firstIntValue(
      await _db.db.rawQuery('SELECT COUNT(*) FROM $tableName'),
    );
    return v ?? 0;
  }

  static const _motherServiceTypes = [
    'pwprofile',
    'anc',
    'pnc_mother',
    'pregnancyoutcome',
  ];

  /// Distinct local member ids with mother-side MAH (Spice dashboard rebuild input).
  Future<List<int>> distinctMemberLocalIdsWithMotherHistory() async {
    const types = _motherServiceTypes;
    final ph = List.filled(types.length, '?').join(',');
    final rows = await _db.db.rawQuery('''
SELECT DISTINCT member_id FROM $tableName
WHERE member_id IS NOT NULL
  AND LOWER(service_provided) IN ($ph)
''', types);
    return rows
        .map((r) => r['member_id'] as int?)
        .whereType<int>()
        .toList();
  }

  /// Spice [getMemberAssessmentHistoryByMemberLocalIdsAndTypes].
  Future<List<MemberAssessmentHistoryRow>> getByMemberLocalIdsAndServiceTypes(
    List<int> memberLocalIds,
    List<String> serviceTypesLower,
  ) async {
    if (memberLocalIds.isEmpty || serviceTypesLower.isEmpty) return [];
    final idPh = List.filled(memberLocalIds.length, '?').join(',');
    final svcPh = List.filled(serviceTypesLower.length, '?').join(',');
    final rows = await _db.db.rawQuery('''
SELECT * FROM $tableName
WHERE member_id IN ($idPh)
  AND LOWER(service_provided) IN ($svcPh)
ORDER BY member_id ASC, visit_date ASC, id ASC
''', [...memberLocalIds, ...serviceTypesLower]);
    return rows.map(MemberAssessmentHistoryRow.fromDb).toList();
  }

  /// One-time bootstrap from legacy [assessments] rows after MAH ships.
  Future<int> backfillFromLegacyAssessmentsTable() async {
    final legacy = await _db.db.query(AppDatabase.tableAssessments);
    if (legacy.isEmpty) return 0;
    final rows = <MemberAssessmentHistoryRow>[];
    for (final r in legacy) {
      final encounterId = r['id'] as String?;
      if (encounterId == null || encounterId.isEmpty) continue;
      final raw = r['raw_json'] as String? ?? '{}';
      Map<String, dynamic> map;
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        map = {};
      }
      final visitMs = r['occurred_at'] as int? ??
          _epochFromMap(map, const ['visitDate', 'assessmentDate']);
      if (visitMs == null) continue;
      final visitDate =
          DateTime.fromMillisecondsSinceEpoch(visitMs).toUtc().toIso8601String();
      final memberFhir = _stringFromMap(map, const [
        'householdMemberId',
        'memberId',
        'memberFhirId',
      ]);
      rows.add(
        MemberAssessmentHistoryRow(
          memberId: null,
          memberFhirId: memberFhir ?? r['patient_id'] as String?,
          visitDate: visitDate,
          serviceProvided: (r['kind'] as String?)?.toLowerCase(),
          encounterId: encounterId,
          customStatus: _encodeCustomStatus(map['customStatus']),
          observationsJson: map['observations'] != null
              ? jsonEncode(map['observations'])
              : null,
          referralStatus: _stringFromMap(map, const ['referralStatus']),
        ),
      );
    }
    await upsertMany(rows, fromServer: true);
    return rows.length;
  }

  static int? _epochFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
        final dt = DateTime.tryParse(v);
        if (dt != null) return dt.millisecondsSinceEpoch;
      }
    }
    return null;
  }

  static String? _stringFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static String? _encodeCustomStatus(Object? raw) {
    if (raw == null) return null;
    if (raw is List) {
      final parts = raw.map((e) => e.toString()).where((s) => s.isNotEmpty);
      final list = parts.toList();
      if (list.isEmpty) return null;
      return jsonEncode(list);
    }
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Visit ids this device gave its own saved assessments, read once per
/// server batch from `local_assessments.other_details`.
class _DeviceVisitIds {
  _DeviceVisitIds(this._all, this._byServerId);

  final Set<String> _all;
  final Map<String, Set<String>> _byServerId;

  bool get isNotEmpty => _all.isNotEmpty;

  bool contains(String encounterId) => _all.contains(encounterId);

  /// Device ids of the assessments the server stamped with [serverEncounterId].
  Set<String> stampedWith(String serverEncounterId) =>
      _byServerId[serverEncounterId] ?? const {};

  static Future<_DeviceVisitIds> load(DatabaseExecutor tx) async {
    final rows = await tx.query(
      AppDatabase.tableLocalAssessments,
      columns: ['fhir_id', 'other_details'],
      where: 'other_details IS NOT NULL',
    );
    final all = <String>{};
    final byServerId = <String, Set<String>>{};
    for (final r in rows) {
      final deviceId = MemberAssessmentHistoryDao.deviceEncounterId(
          r['other_details'] as String?);
      if (deviceId == null) continue;
      all.add(deviceId);
      final serverId = (r['fhir_id'] as String?)?.trim();
      if (serverId != null && serverId.isNotEmpty) {
        byServerId.putIfAbsent(serverId, () => {}).add(deviceId);
      }
    }
    return _DeviceVisitIds(all, byServerId);
  }
}
