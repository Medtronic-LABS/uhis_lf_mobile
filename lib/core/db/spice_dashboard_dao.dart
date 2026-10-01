import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'member_assessment_history_dao.dart';

/// KPI counts aligned with Spice [DashboardCountsRow] / [DashboardLocalRepository].
class SpiceDashboardCounts {
  const SpiceDashboardCounts({
    this.pregnantWomenRegistrationCount = 0,
    this.ancCount = 0,
    this.pwIdentifiedFirst4MonthsWithAncCount = 0,
    this.anc3PlusCount = 0,
    this.pregnancyOutcomeCount = 0,
    this.pncCount = 0,
    this.highRiskPregnantWomenCount = 0,
    this.childVisitCount = 0,
    this.householdRegisteredCount = 0,
    this.familyPlanningCount = 0,
    this.otherServicesCount = 0,
    this.ncdScreeningFirstServiceCount = 0,
    this.ncdFollowUpReferralCount = 0,
    this.ncdFollowUpAssessmentCount = 0,
    this.totalNcdServicesCount = 0,
    this.linkedToCareCount = 0,
    this.eyeCareCount = 0,
    this.glassesSoldCustomStatusCount = 0,
    this.cataractCount = 0,
    this.ncdServicesInCataractCampCount = 0,
    this.patientsReferredForOperationCount = 0,
    this.memberRegisteredCount = 0,
    this.tbAssessmentCount = 0,
    this.tbContactTracingCount = 0,
  });

  final int pregnantWomenRegistrationCount;
  final int ancCount;
  final int pwIdentifiedFirst4MonthsWithAncCount;
  final int anc3PlusCount;
  final int pregnancyOutcomeCount;
  final int pncCount;
  final int highRiskPregnantWomenCount;
  final int childVisitCount;
  final int householdRegisteredCount;
  final int familyPlanningCount;
  final int otherServicesCount;
  final int ncdScreeningFirstServiceCount;
  final int ncdFollowUpReferralCount;
  final int ncdFollowUpAssessmentCount;
  final int totalNcdServicesCount;
  final int linkedToCareCount;
  final int eyeCareCount;
  final int glassesSoldCustomStatusCount;
  final int cataractCount;
  final int ncdServicesInCataractCampCount;
  final int patientsReferredForOperationCount;
  final int memberRegisteredCount;
  final int tbAssessmentCount;
  final int tbContactTracingCount;

  static SpiceDashboardCounts fromRow(Map<String, Object?> row) {
    int i(String k) => (row[k] as int?) ?? 0;
    return SpiceDashboardCounts(
      pregnantWomenRegistrationCount: i('pregnantWomenRegistrationCount'),
      ancCount: i('ancCount'),
      pwIdentifiedFirst4MonthsWithAncCount: i('pwIdentifiedFirst4MonthsWithAncCount'),
      anc3PlusCount: i('anc3PlusCount'),
      pregnancyOutcomeCount: i('pregnancyOutcomeCount'),
      pncCount: i('pncCount'),
      highRiskPregnantWomenCount: i('highRiskPregnantWomenCount'),
      childVisitCount: i('childVisitCount'),
      householdRegisteredCount: i('householdRegisteredCount'),
      familyPlanningCount: i('familyPlanningCount'),
      otherServicesCount: i('otherServicesCount'),
      ncdScreeningFirstServiceCount: i('ncdScreeningFirstServiceCount'),
      ncdFollowUpReferralCount: i('ncdFollowUpReferralCount'),
      ncdFollowUpAssessmentCount: i('ncdFollowUpAssessmentCount'),
      totalNcdServicesCount: i('totalNcdServicesCount'),
      linkedToCareCount: i('linkedToCareCount'),
      eyeCareCount: i('eyeCareCount'),
      glassesSoldCustomStatusCount: i('glassesSoldCustomStatusCount'),
      cataractCount: i('cataractCount'),
      ncdServicesInCataractCampCount: i('ncdServicesInCataractCampCount'),
      patientsReferredForOperationCount: i('patientsReferredForOperationCount'),
      memberRegisteredCount: i('memberRegisteredCount'),
      tbAssessmentCount: i('tbAssessmentCount'),
      tbContactTracingCount: i('tbContactTracingCount'),
    );
  }
}

class SpiceDashboardDao {
  SpiceDashboardDao(this._db);

  final AppDatabase _db;

  static const _mah = MemberAssessmentHistoryDao.tableName;
  static const _members = AppDatabase.tableMembers;
  static const _households = AppDatabase.tableHouseholds;
  static const _sslv = 'shasthya_shebika_linked_villages';
  static const _episodes = AppDatabase.tablePregnancyEpisodes;
  static const _snapshot = AppDatabase.tablePregnancySnapshot;

  Future<SpiceDashboardCounts> loadCounts({
    String? startDate,
    String? endDate,
    List<String> ssIds = const [],
    List<String> subVillageIds = const [],
    String? userFhirId,
  }) async {
    final base = await _mainMahCounts(
      startDate: startDate,
      endDate: endDate,
      ssIds: ssIds,
      subVillageIds: subVillageIds,
      userFhirId: userFhirId,
    );
    final hh = await _householdRegisteredCount(
      startDate: startDate,
      endDate: endDate,
      ssIds: ssIds,
      subVillageIds: subVillageIds,
    );
    final members = await _memberRegisteredCount(
      startDate: startDate,
      endDate: endDate,
      ssIds: ssIds,
      subVillageIds: subVillageIds,
    );
    ({int pwIdentifiedFirst4MonthsWithAncCount, int anc3PlusCount}) maternal;
    try {
      maternal = await _maternalCounts(
        startDate: startDate,
        endDate: endDate,
        ssIds: ssIds,
        subVillageIds: subVillageIds,
        userFhirId: userFhirId,
      );
    } catch (_) {
      maternal = (
        pwIdentifiedFirst4MonthsWithAncCount: 0,
        anc3PlusCount: 0,
      );
    }

    return SpiceDashboardCounts(
      pregnantWomenRegistrationCount: base.pregnantWomenRegistrationCount,
      ancCount: base.ancCount,
      pwIdentifiedFirst4MonthsWithAncCount:
          maternal.pwIdentifiedFirst4MonthsWithAncCount,
      anc3PlusCount: maternal.anc3PlusCount,
      pregnancyOutcomeCount: base.pregnancyOutcomeCount,
      pncCount: base.pncCount,
      highRiskPregnantWomenCount: base.highRiskPregnantWomenCount,
      childVisitCount: base.childVisitCount,
      householdRegisteredCount: hh,
      familyPlanningCount: base.familyPlanningCount,
      otherServicesCount: base.otherServicesCount,
      ncdScreeningFirstServiceCount: base.ncdScreeningFirstServiceCount,
      ncdFollowUpReferralCount: base.ncdFollowUpReferralCount,
      ncdFollowUpAssessmentCount: base.ncdFollowUpAssessmentCount,
      totalNcdServicesCount: base.totalNcdServicesCount,
      linkedToCareCount: base.linkedToCareCount,
      eyeCareCount: base.eyeCareCount,
      glassesSoldCustomStatusCount: base.glassesSoldCustomStatusCount,
      cataractCount: base.cataractCount,
      ncdServicesInCataractCampCount: base.ncdServicesInCataractCampCount,
      patientsReferredForOperationCount: base.patientsReferredForOperationCount,
      memberRegisteredCount: members,
      tbAssessmentCount: base.tbAssessmentCount,
      tbContactTracingCount: base.tbContactTracingCount,
    );
  }

  Future<SpiceDashboardCounts> _mainMahCounts({
    required String? startDate,
    required String? endDate,
    required List<String> ssIds,
    required List<String> subVillageIds,
    required String? userFhirId,
  }) async {
    final geo = _geoSql('hm', ssIds, subVillageIds);
    final geoLinked =
        _geoSql('ehm', ssIds, subVillageIds).replaceAll('hh.', 'ehh.');
    final geoArgs = _geoArgs(ssIds, subVillageIds);
    final args = <Object?>[
      startDate,
      startDate,
      endDate,
      endDate,
      ...geoArgs,
      userFhirId,
      startDate,
      startDate,
      endDate,
      endDate,
      ...geoArgs,
      userFhirId,
    ];

    final sql = '''
SELECT
  SUM(CASE WHEN LOWER(h.service_provided) IN ('pwprofile') THEN 1 ELSE 0 END) AS pregnantWomenRegistrationCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('anc') THEN 1 ELSE 0 END) AS ancCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('pregnancyoutcome') THEN 1 ELSE 0 END) AS pregnancyOutcomeCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('pnc_mother') THEN 1 ELSE 0 END) AS pncCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('childhood_visit') THEN 1 ELSE 0 END) AS childVisitCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('family_planning','familyplanning') THEN 1 ELSE 0 END) AS familyPlanningCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('other_services') THEN 1 ELSE 0 END) AS otherServicesCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('tb') THEN 1 ELSE 0 END) AS tbAssessmentCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('tbcontacttracing') THEN 1 ELSE 0 END) AS tbContactTracingCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('eye_care') THEN 1 ELSE 0 END) AS eyeCareCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('cataract') THEN 1 ELSE 0 END) AS cataractCount,
  0 AS householdRegisteredCount,
  0 AS pwIdentifiedFirst4MonthsWithAncCount,
  0 AS anc3PlusCount,
  0 AS memberRegisteredCount,
  SUM(CASE WHEN LOWER(h.service_provided) IN ('anc') AND h.custom_status IS NOT NULL
      AND INSTR(h.custom_status, 'HIGH_RISK_PW') > 0 THEN 1 ELSE 0 END) AS highRiskPregnantWomenCount,
  SUM(CASE WHEN LOWER(h.service_provided) = 'ncd' THEN 1
      WHEN LOWER(h.service_provided) = 'cataract' AND h.custom_status IS NOT NULL
      AND INSTR(h.custom_status, 'NCD_SERVICE_IN_CATARACT_CAMP') > 0 THEN 1 ELSE 0 END) AS totalNcdServicesCount,
  SUM(CASE WHEN LOWER(h.service_provided) = 'ncd' AND NOT EXISTS (
      SELECT 1 FROM $_mah p WHERE ${_sameMemberSql('h', 'p')}
      AND LOWER(p.service_provided) = 'ncd'
      AND (p.visit_date < h.visit_date OR (p.visit_date = h.visit_date AND p.id < h.id))
    ) THEN 1 ELSE 0 END) AS ncdScreeningFirstServiceCount,
  SUM(CASE WHEN LOWER(h.service_provided) = 'ncd' AND EXISTS (
      SELECT 1 FROM $_mah p WHERE ${_sameMemberSql('h', 'p')}
      AND LOWER(p.service_provided) = 'ncd'
      AND (p.visit_date < h.visit_date OR (p.visit_date = h.visit_date AND p.id < h.id))
    ) THEN 1 ELSE 0 END) AS ncdFollowUpAssessmentCount,
  SUM(CASE WHEN ${_spiceReferralStatus('h.referral_status')} AND (
      LOWER(h.service_provided) = 'ncd' OR (LOWER(h.service_provided) = 'cataract'
      AND h.custom_status IS NOT NULL AND INSTR(h.custom_status, 'NCD_SERVICE_IN_CATARACT_CAMP') > 0))
      AND (h.member_id IS NOT NULL OR NULLIF(h.member_fhir_id, '') IS NOT NULL)
      AND NOT EXISTS (SELECT 1 FROM $_mah previous WHERE ${_sameMemberSpiceSql('h', 'previous')}
      AND ${_spiceReferralStatus('previous.referral_status')}
      AND (LOWER(previous.service_provided) = 'ncd' OR (LOWER(previous.service_provided) = 'cataract'
      AND previous.custom_status IS NOT NULL AND INSTR(previous.custom_status, 'NCD_SERVICE_IN_CATARACT_CAMP') > 0))
      AND (previous.visit_date < h.visit_date OR (previous.visit_date = h.visit_date AND previous.id < h.id))
    ) THEN 1 ELSE 0 END) AS ncdFollowUpReferralCount,
  SUM(CASE WHEN h.custom_status IS NOT NULL AND INSTR(h.custom_status, 'GLASSES_SOLD') > 0
    THEN 1 ELSE 0 END) AS glassesSoldCustomStatusCount,
  SUM(CASE WHEN LOWER(h.service_provided) = 'cataract' AND h.custom_status IS NOT NULL
    AND INSTR(h.custom_status, 'NCD_SERVICE_IN_CATARACT_CAMP') > 0 THEN 1 ELSE 0 END) AS ncdServicesInCataractCampCount,
  SUM(CASE WHEN LOWER(h.service_provided) = 'cataract' AND h.custom_status IS NOT NULL
    AND INSTR(h.custom_status, 'REFERRED_FOR_OPERATION') > 0 THEN 1 ELSE 0 END) AS patientsReferredForOperationCount,
  (SELECT COUNT(DISTINCT COALESCE(CAST(e.member_id AS TEXT), e.member_fhir_id))
    FROM $_mah AS e
    LEFT JOIN $_members AS ehm ON (
      (e.member_id IS NOT NULL AND ehm.id = e.member_id)
      OR (NULLIF(e.member_fhir_id, '') IS NOT NULL AND ehm.fhir_id = e.member_fhir_id)
    )
    LEFT JOIN $_households AS ehh ON ehh.id = ehm.household_id
    WHERE LOWER(e.service_provided) = 'enrollment'
      AND (? IS NULL OR date(datetime(e.visit_date, 'localtime')) >= ?)
      AND (? IS NULL OR date(datetime(e.visit_date, 'localtime')) <= ?)
      AND ($geoLinked)
      AND EXISTS (SELECT 1 FROM $_mah AS n WHERE ${_sameMemberSql('e', 'n')}
        AND (LOWER(n.service_provided) = 'ncd' OR (LOWER(n.service_provided) = 'cataract'
        AND n.custom_status IS NOT NULL AND INSTR(n.custom_status, 'NCD_SERVICE_IN_CATARACT_CAMP') > 0))
        AND n.visit_date <= e.visit_date AND n.practitioner_id IS ?
    )
  ) AS linkedToCareCount
FROM $_mah AS h
LEFT JOIN $_members AS hm ON (
  (h.member_id IS NOT NULL AND hm.id = h.member_id)
  OR (NULLIF(h.member_fhir_id, '') IS NOT NULL AND hm.fhir_id = h.member_fhir_id)
)
LEFT JOIN $_households AS hh ON hh.id = hm.household_id
WHERE (? IS NULL OR date(datetime(h.visit_date, 'localtime')) >= ?)
  AND (? IS NULL OR date(datetime(h.visit_date, 'localtime')) <= ?)
  AND ($geo)
  AND (h.practitioner_id IS NULL OR h.practitioner_id IS ?)
''';

    final rows = await _db.db.rawQuery(sql, args);
    if (rows.isEmpty) return const SpiceDashboardCounts();
    return SpiceDashboardCounts.fromRow(rows.first);
  }

  Future<int> _householdRegisteredCount({
    required String? startDate,
    required String? endDate,
    required List<String> ssIds,
    required List<String> subVillageIds,
  }) async {
    final geo = _geoSqlHousehold(ssIds, subVillageIds);
    final args = <Object?>[
      startDate,
      startDate,
      endDate,
      endDate,
      ..._geoArgs(ssIds, subVillageIds),
    ];
    final sql = '''
SELECT COUNT(hh.id) AS c FROM $_households AS hh
WHERE (? IS NULL OR date(datetime(hh.created_at / 1000, 'unixepoch', 'localtime')) >= ?)
  AND (? IS NULL OR date(datetime(hh.created_at / 1000, 'unixepoch', 'localtime')) <= ?)
  AND ($geo)
''';
    final v = Sqflite.firstIntValue(await _db.db.rawQuery(sql, args));
    return v ?? 0;
  }

  Future<int> _memberRegisteredCount({
    required String? startDate,
    required String? endDate,
    required List<String> ssIds,
    required List<String> subVillageIds,
  }) async {
    final geo = _geoSql('hm', ssIds, subVillageIds);
    final args = <Object?>[
      startDate,
      startDate,
      endDate,
      endDate,
      ..._geoArgs(ssIds, subVillageIds),
    ];
    final sql = '''
SELECT COUNT(hm.id) AS c FROM $_members AS hm
LEFT JOIN $_households AS hh ON hh.id = hm.household_id
WHERE (? IS NULL OR date(datetime(hm.created_at / 1000, 'unixepoch', 'localtime')) >= ?)
  AND (? IS NULL OR date(datetime(hm.created_at / 1000, 'unixepoch', 'localtime')) <= ?)
  AND (
    hm.raw_json IS NULL
    OR json_extract(hm.raw_json, '\$.createdByRoleName') IS NULL
    OR TRIM(json_extract(hm.raw_json, '\$.createdByRoleName')) = ''
    OR LOWER(json_extract(hm.raw_json, '\$.createdByRoleName')) = 'shasthya_kormi'
  )
  AND ($geo)
''';
    final v = Sqflite.firstIntValue(await _db.db.rawQuery(sql, args));
    return v ?? 0;
  }

  Future<({int pwIdentifiedFirst4MonthsWithAncCount, int anc3PlusCount})>
      _maternalCounts({
    required String? startDate,
    required String? endDate,
    required List<String> ssIds,
    required List<String> subVillageIds,
    required String? userFhirId,
  }) async {
    // `fm` subquery only — no outer `hh` join; geography uses member/household
    // sub_village only (`households` has no shasthya_shebika_id in Flutter).
    final geo = _geoSql('fm', ssIds, subVillageIds, householdAlias: null);
    final geoArgs = _geoArgs(ssIds, subVillageIds);

    final anc3Sql = '''
SELECT COUNT(DISTINCT h.member_fhir_id) AS c FROM $_mah AS h
INNER JOIN (
  SELECT m.id AS memberId, m.fhir_id AS memberFhirId,
    COALESCE(m.sub_village_id, hh.sub_village_id) AS sub_village_id
  FROM $_members AS m
  LEFT JOIN $_households AS hh ON hh.id = m.household_id
) AS fm ON fm.memberFhirId = h.member_fhir_id OR CAST(fm.memberId AS TEXT) = h.member_fhir_id
WHERE LOWER(h.service_provided) = 'anc'
  AND h.member_fhir_id IS NOT NULL AND h.member_fhir_id != ''
  AND (h.practitioner_id IS NULL OR h.practitioner_id IS ?)
  AND CAST(json_extract(h.observations_json, '\$.ancVisitNumber') AS INTEGER) = 3
  AND (? IS NULL OR date(datetime(h.visit_date, 'localtime')) >= ?)
  AND (? IS NULL OR date(datetime(h.visit_date, 'localtime')) <= ?)
  AND ($geo)
''';
    final anc3Args = <Object?>[
      userFhirId,
      startDate,
      startDate,
      endDate,
      endDate,
      ...geoArgs,
    ];
    final anc3 = Sqflite.firstIntValue(
          await _db.db.rawQuery(anc3Sql, anc3Args),
        ) ??
        0;

    final pwGeo = _geoSqlPw(ssIds, subVillageIds);
    // Spice `getMaternalDashboardCounts`: latest pregnancy per member + MAH ANC in LMP window.
    final pwSql = '''
SELECT COALESCE(SUM(CASE WHEN EXISTS (
  SELECT 1 FROM $_mah AS hist
  WHERE ${_sameMemberLp('lp', 'hist')}
    AND LOWER(hist.service_provided) = 'anc'
    AND (? IS NULL OR date(datetime(hist.visit_date, 'localtime')) >= ?)
    AND (? IS NULL OR date(datetime(hist.visit_date, 'localtime')) <= ?)
    AND (hist.practitioner_id IS NULL OR hist.practitioner_id IS ?)
    AND lp.lmp_date IS NOT NULL
    AND date(datetime(hist.visit_date, 'localtime')) >= date(lp.lmp_date / 1000, 'unixepoch', 'localtime')
    AND date(datetime(hist.visit_date, 'localtime')) <= date(lp.lmp_date / 1000, 'unixepoch', 'localtime', '+4 months')
) THEN 1 ELSE 0 END), 0) AS c
FROM (
  SELECT le.lmp_date, le.member_local_id, le.member_fhir_id, le.sub_village_id
  FROM (
    SELECT pe.lmp_date, m.id AS member_local_id, m.fhir_id AS member_fhir_id,
      COALESCE(m.sub_village_id, hh.sub_village_id) AS sub_village_id,
      pe.patient_id, pe.started_at
    FROM $_episodes pe
    INNER JOIN $_members m ON m.patient_id = pe.patient_id
    LEFT JOIN $_households hh ON hh.id = m.household_id
    WHERE pe.lmp_date IS NOT NULL
      AND (pe.delivery_date_millis IS NULL OR pe.delivery_date_millis = 0)
      AND (pe.edd_date IS NULL OR date(pe.edd_date / 1000, 'unixepoch', 'localtime') > date('now', '-45 days'))
  ) AS le
  INNER JOIN (
    SELECT patient_id, MAX(started_at) AS max_started
    FROM $_episodes
    WHERE lmp_date IS NOT NULL
      AND (delivery_date_millis IS NULL OR delivery_date_millis = 0)
    GROUP BY patient_id
  ) AS latest ON latest.patient_id = le.patient_id AND latest.max_started = le.started_at
  UNION ALL
  SELECT ps.lmp_date, m.id AS member_local_id, m.fhir_id AS member_fhir_id,
    COALESCE(m.sub_village_id, hh.sub_village_id) AS sub_village_id
  FROM $_snapshot ps
  INNER JOIN $_members m ON m.patient_id = ps.patient_id
  LEFT JOIN $_households hh ON hh.id = m.household_id
  WHERE ps.lmp_date IS NOT NULL
    AND (ps.delivery_date_millis IS NULL OR ps.delivery_date_millis = 0)
    AND (ps.edd_date IS NULL OR date(ps.edd_date / 1000, 'unixepoch', 'localtime') > date('now', '-45 days'))
    AND NOT EXISTS (
      SELECT 1 FROM $_episodes pe
      WHERE pe.patient_id = ps.patient_id AND pe.lmp_date IS NOT NULL
        AND (pe.delivery_date_millis IS NULL OR pe.delivery_date_millis = 0)
    )
) AS lp
WHERE ($pwGeo)
''';
    final pwArgs = <Object?>[
      startDate,
      startDate,
      endDate,
      endDate,
      userFhirId,
      ...geoArgs,
    ];
    final pw4 = Sqflite.firstIntValue(
          await _db.db.rawQuery(pwSql, pwArgs),
        ) ??
        0;

    return (
      pwIdentifiedFirst4MonthsWithAncCount: pw4,
      anc3PlusCount: anc3,
    );
  }

  List<Object?> _geoArgs(List<String> ssIds, List<String> subVillageIds) {
    if (subVillageIds.isNotEmpty) return subVillageIds;
    if (ssIds.isNotEmpty) return ssIds;
    return const [];
  }

  String _geoSql(
    String alias,
    List<String> ssIds,
    List<String> subVillageIds, {
    String? householdAlias = 'hh',
  }) {
    final subVillageExpr = householdAlias != null
        ? 'COALESCE($alias.sub_village_id, $householdAlias.sub_village_id)'
        : '$alias.sub_village_id';
    if (subVillageIds.isNotEmpty) {
      final ph = List.filled(subVillageIds.length, '?').join(',');
      return '$subVillageExpr IN ($ph)';
    }
    if (ssIds.isNotEmpty) {
      final ph = List.filled(ssIds.length, '?').join(',');
      return '''$subVillageExpr IN (
        SELECT DISTINCT sslv.sub_village_id FROM $_sslv AS sslv
        WHERE sslv.shasthya_shebika_id IN ($ph))''';
    }
    return '1';
  }

  String _geoSqlPw(List<String> ssIds, List<String> subVillageIds) {
    if (subVillageIds.isNotEmpty) {
      final ph = List.filled(subVillageIds.length, '?').join(',');
      return 'lp.sub_village_id IN ($ph)';
    }
    if (ssIds.isNotEmpty) {
      final ph = List.filled(ssIds.length, '?').join(',');
      return '''lp.sub_village_id IN (
        SELECT DISTINCT sslv.sub_village_id FROM $_sslv AS sslv
        WHERE sslv.shasthya_shebika_id IN ($ph))''';
    }
    return '1';
  }

  /// Spice dashboard referral de-dupe (`memberId` OR `memberFhirId` only).
  static String _sameMemberSpiceSql(String hAlias, String pAlias) => '''
(
  ($hAlias.member_id IS NOT NULL AND $pAlias.member_id = $hAlias.member_id)
  OR (
    NULLIF($hAlias.member_fhir_id, '') IS NOT NULL
    AND $pAlias.member_fhir_id = $hAlias.member_fhir_id
  )
)''';

  /// Exact Spice `ncdFollowUpReferralCount` referral-status match.
  static String _spiceReferralStatus(String col) =>
      "($col IS NOT NULL AND ($col = 'Referred' OR $col LIKE 'Referred To%'))";

  static String _sameMemberLp(String lpAlias, String histAlias) => '''
(
  ($lpAlias.member_local_id IS NOT NULL AND $histAlias.member_id = $lpAlias.member_local_id)
  OR (
    NULLIF($lpAlias.member_fhir_id, '') IS NOT NULL
    AND $histAlias.member_fhir_id = $lpAlias.member_fhir_id
  )
  OR (
    $lpAlias.member_local_id IS NOT NULL
    AND NULLIF($histAlias.member_fhir_id, '') IS NOT NULL
    AND CAST($lpAlias.member_local_id AS TEXT) = $histAlias.member_fhir_id
  )
  OR (
    $histAlias.member_id IS NOT NULL
    AND NULLIF($lpAlias.member_fhir_id, '') IS NOT NULL
    AND CAST($histAlias.member_id AS TEXT) = $lpAlias.member_fhir_id
  )
)''';

  /// Same member as Spice linked-to-care (local id and/or FHIR id).
  static String _sameMemberSql(String hAlias, String pAlias) => '''
(
  ($hAlias.member_id IS NOT NULL AND $pAlias.member_id = $hAlias.member_id)
  OR (
    NULLIF($hAlias.member_fhir_id, '') IS NOT NULL
    AND $pAlias.member_fhir_id = $hAlias.member_fhir_id
  )
  OR (
    $hAlias.member_id IS NOT NULL
    AND NULLIF($pAlias.member_fhir_id, '') IS NOT NULL
    AND CAST($hAlias.member_id AS TEXT) = $pAlias.member_fhir_id
  )
  OR (
    $pAlias.member_id IS NOT NULL
    AND NULLIF($hAlias.member_fhir_id, '') IS NOT NULL
    AND CAST($pAlias.member_id AS TEXT) = $hAlias.member_fhir_id
  )
)''';

  String _geoSqlHousehold(List<String> ssIds, List<String> subVillageIds) {
    if (subVillageIds.isNotEmpty) {
      final ph = List.filled(subVillageIds.length, '?').join(',');
      return 'hh.sub_village_id IN ($ph)';
    }
    if (ssIds.isNotEmpty) {
      final ph = List.filled(ssIds.length, '?').join(',');
      return '''hh.sub_village_id IN (
        SELECT DISTINCT sslv.sub_village_id FROM $_sslv AS sslv
        WHERE sslv.shasthya_shebika_id IN ($ph))''';
    }
    return '1';
  }
}
