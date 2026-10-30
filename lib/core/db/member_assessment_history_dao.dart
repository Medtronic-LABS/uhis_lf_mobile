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

  Future<void> upsertMany(List<MemberAssessmentHistoryRow> rows) async {
    if (rows.isEmpty) return;
    await _db.db.transaction((tx) async {
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
        }
        await tx.insert(tableName, dbRow);
      }
    });
  }

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
    if (rows.isNotEmpty) await upsertMany(rows);
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
    await upsertMany(rows);
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
