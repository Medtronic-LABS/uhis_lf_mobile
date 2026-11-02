import 'app_database.dart';
import 'member_dao.dart';
import '../../features/household/service_static_filter.dart';

/// One row from the service-member list query (flat list, UHIS Services parity).
class ServiceMemberListRow {
  const ServiceMemberListRow({
    required this.member,
    this.recentServiceKind,
    this.recentServiceDateMs,
  });

  final HouseholdMemberEntity member;
  final String? recentServiceKind;
  final int? recentServiceDateMs;
}

/// SQL filters + list/count queries ported from Spice
/// [ServiceFilterConditions] / [ServiceMemberQueryBuilder].
class ServiceMemberDao {
  ServiceMemberDao(this._db);

  final AppDatabase _db;

  static const _members = AppDatabase.tableMembers;
  static const _households = AppDatabase.tableHouseholds;
  static const _mah = AppDatabase.tableMemberAssessmentHistory;
  static const _pregnancyDetail = AppDatabase.tablePregnancyDetail;

  static const _recentServiceDateExpr = '''
(SELECT MAX(CAST(strftime('%s', visit_date) AS INTEGER) * 1000)
 FROM $_mah AS mah
 WHERE mah.member_id = hhm.id)''';

  static const _latestServiceKindExpr = '''
(SELECT mah.service_provided
 FROM $_mah AS mah
 WHERE mah.member_id = hhm.id
 ORDER BY mah.visit_date DESC, mah.id DESC
 LIMIT 1)''';

  static const _latestPregnancyJoin = '''
LEFT JOIN (
  SELECT
    pd.household_member_local_id,
    pd.date_of_delivery,
    pd.last_menstrual_period,
    pd.estimated_delivery_date,
    pd.high_risk_pregnant_woman,
    pd.type_of_abortion,
    ROW_NUMBER() OVER (
      PARTITION BY pd.household_member_local_id
      ORDER BY pd.end_at DESC, pd.id DESC
    ) AS rn
  FROM $_pregnancyDetail AS pd
) AS lp ON lp.household_member_local_id = hhm.id AND lp.rn = 1
''';

  /// Spice [ServiceFilterConditions.ACTIVE_PREGNANCY].
  static const _activePregnancy = '''
lp.last_menstrual_period IS NOT NULL AND lp.last_menstrual_period != ''
AND (lp.date_of_delivery IS NULL OR lp.date_of_delivery = '')
AND (lp.estimated_delivery_date IS NULL OR substr(lp.estimated_delivery_date, 1, 10) > date('now', '-45 days'))
AND (lp.type_of_abortion IS NULL OR lp.type_of_abortion = '')
''';

  static const _highRiskPregnant = '''
$_activePregnancy
AND lp.high_risk_pregnant_woman IS NOT NULL AND lp.high_risk_pregnant_woman != ''
''';

  static const _postnatal = '''
lp.date_of_delivery IS NOT NULL AND lp.date_of_delivery != ''
AND substr(lp.date_of_delivery, 1, 10) >= date('now', '-42 days')
''';

  static const _awaitingDelivery = '''
(lp.date_of_delivery IS NULL OR lp.date_of_delivery = '')
AND (lp.type_of_abortion IS NULL OR lp.type_of_abortion = '')
AND lp.estimated_delivery_date IS NOT NULL AND lp.estimated_delivery_date != ''
''';

  static const _expectedDelivery = '''
$_awaitingDelivery
AND substr(lp.estimated_delivery_date, 1, 10) BETWEEN date('now') AND date('now', '+30 days')
''';

  static const _pendingDelivery = '''
$_awaitingDelivery
AND substr(lp.estimated_delivery_date, 1, 10) < date('now')
AND substr(lp.estimated_delivery_date, 1, 10) > date('now', '-45 days')
''';

  static const _childrenUnderTwo =
      "substr(hhm.dob, 1, 10) > date('now', '-2 years')";

  static const _externalMember = 'hhm.household_id IS NULL';

  static const _skScopedExternalCreator = '''
(json_extract(hhm.raw_json, '\$.createdByRoleName') IS NULL
 OR TRIM(json_extract(hhm.raw_json, '\$.createdByRoleName')) = ''
 OR LOWER(json_extract(hhm.raw_json, '\$.createdByRoleName')) = 'shasthya_kormi')
''';

  static const _isActive = 'hhm.is_active = 1';
  static const _hasHousehold = 'hhm.household_id IS NOT NULL';

  static const _familyPlanningEligible = '''
(hhm.gender = 'Female' OR LOWER(hhm.gender) IN ('female', 'f'))
AND LOWER(hhm.marital_status) = 'married'
AND substr(hhm.dob, 1, 10) <= date('now', '-14 years')
AND substr(hhm.dob, 1, 10) >= date('now', '-50 years')
AND NOT ($_activePregnancy)
''';

  static const _hasNcdHistory = '''
EXISTS (
  SELECT 1 FROM $_mah AS mah
  WHERE (mah.member_id = hhm.id OR (mah.member_fhir_id IS NOT NULL AND mah.member_fhir_id = hhm.fhir_id))
  AND LOWER(mah.service_provided) IN ('ncd', 'bd_ncd')
)
''';

  static const _hasCataractHistory = '''
EXISTS (
  SELECT 1 FROM $_mah AS mah
  WHERE (mah.member_id = hhm.id OR (mah.member_fhir_id IS NOT NULL AND mah.member_fhir_id = hhm.fhir_id))
  AND LOWER(mah.service_provided) = 'cataract'
)
''';

  static const _hasEyeHistory = '''
EXISTS (
  SELECT 1 FROM $_mah AS mah
  WHERE (mah.member_id = hhm.id OR (mah.member_fhir_id IS NOT NULL AND mah.member_fhir_id = hhm.fhir_id))
  AND LOWER(mah.service_provided) = 'eye_care'
)
''';

  static const _hasOtherServicesHistory = '''
EXISTS (
  SELECT 1 FROM $_mah AS mah
  WHERE (mah.member_id = hhm.id OR (mah.member_fhir_id IS NOT NULL AND mah.member_fhir_id = hhm.fhir_id))
  AND LOWER(mah.service_provided) = 'other_services'
)
''';

  Future<Map<ServiceStaticFilter, int>> countForFilters({
    required List<ServiceStaticFilter> filters,
    String searchInput = '',
    String? subVillageId,
    bool restrictExternalToSkCreator = true,
  }) async {
    if (filters.isEmpty) return {};
    final args = <Object?>[];
    final area = _buildAreaFilter(subVillageId: subVillageId, args: args);
    final selectColumns = <String>[];
    for (var i = 0; i < filters.length; i++) {
      final predicate = _filterPredicate(
        filters[i],
        area: area,
        restrictExternalToSkCreator: restrictExternalToSkCreator,
      );
      selectColumns.add(
        'SUM(CASE WHEN $predicate THEN 1 ELSE 0 END) AS cnt_$i',
      );
    }
    final whereConditions = <String>[];
    _appendSearch(whereConditions, args, searchInput);
    final whereClause = whereConditions.isEmpty
        ? ''
        : 'WHERE ${whereConditions.join(' AND ')}';
    final withPrefix =
        area.withClause.isNotEmpty ? '${area.withClause}\n' : '';
    final sql = '''
$withPrefix
SELECT
  ${selectColumns.join(',\n  ')}
FROM $_members AS hhm
LEFT JOIN $_households AS hh ON hh.id = hhm.household_id
$_latestPregnancyJoin
$whereClause
''';
    final row = await _db.db.rawQuery(sql, args);
    if (row.isEmpty) {
      return {for (final f in filters) f: 0};
    }
    final data = row.first;
    return {
      for (var i = 0; i < filters.length; i++)
        filters[i]: (data['cnt_$i'] as int?) ?? 0,
    };
  }

  Future<List<ServiceMemberListRow>> getMembers({
    required ServiceStaticFilter filter,
    String searchInput = '',
    String? subVillageId,
    bool restrictExternalToSkCreator = true,
  }) async {
    final args = <Object?>[];
    final conditions = <String>[];
    final isExternal = filter == ServiceStaticFilter.externalMembers ||
        filter == ServiceStaticFilter.externalPregnantWomen;
    final useOptionalHouseholdJoins = isExternal;
    final area = _buildAreaFilter(subVillageId: subVillageId, args: args);
    final areaMatch =
        useOptionalHouseholdJoins ? area.memberMatch : area.householdMatch;
    if (areaMatch != null) conditions.add(areaMatch);

    if (!_skipsActiveCheck(filter)) {
      conditions.add(_isActive);
    }
    _appendSearch(conditions, args, searchInput);
    _appendStaticFilterConditions(
      conditions,
      filter,
      restrictExternalToSkCreator: restrictExternalToSkCreator,
    );

    final whereClause =
        conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final householdJoin = useOptionalHouseholdJoins
        ? 'LEFT JOIN $_households AS hh ON hh.id = hhm.household_id'
        : 'INNER JOIN $_households AS hh ON hh.id = hhm.household_id';

    final orderBy = switch (filter) {
      ServiceStaticFilter.expectedDeliveries =>
        'ORDER BY substr(lp.estimated_delivery_date, 1, 10) ASC, hhm.id DESC',
      ServiceStaticFilter.pendingDeliveries =>
        'ORDER BY substr(lp.estimated_delivery_date, 1, 10) DESC, hhm.id DESC',
      _ =>
        'ORDER BY COALESCE($_recentServiceDateExpr, hhm.created_at) DESC, hhm.id DESC',
    };

    final withPrefix =
        area.withClause.isNotEmpty ? '${area.withClause}\n' : '';
    final sql = '''
$withPrefix
SELECT
  hhm.*,
  $_recentServiceDateExpr AS recent_service_date,
  $_latestServiceKindExpr AS latest_service_kind
FROM $_members AS hhm
$householdJoin
$_latestPregnancyJoin
$whereClause
$orderBy
''';
    final rows = await _db.db.rawQuery(sql, args);
    return rows.map((row) {
      final memberMap = Map<String, Object?>.from(row);
      final recentMs = memberMap.remove('recent_service_date');
      final kind = memberMap.remove('latest_service_kind');
      return ServiceMemberListRow(
        member: HouseholdMemberEntity.fromDb(
          Map<String, dynamic>.from(memberMap),
        ),
        recentServiceDateMs: recentMs is int ? recentMs : int.tryParse('$recentMs'),
        recentServiceKind: kind as String?,
      );
    }).toList();
  }

  void _appendSearch(
    List<String> conditions,
    List<Object?> args,
    String searchInput,
  ) {
    if (searchInput.trim().isEmpty) return;
    conditions.add(
      '(hhm.name LIKE ? OR hhm.phone LIKE ? OR hhm.national_id LIKE ?)',
    );
    final pattern = '%${searchInput.trim()}%';
    args.addAll([pattern, pattern, pattern]);
  }

  void _appendStaticFilterConditions(
    List<String> conditions,
    ServiceStaticFilter filter, {
    required bool restrictExternalToSkCreator,
  }) {
    switch (filter) {
      case ServiceStaticFilter.externalMembers:
        conditions.add(_externalMember);
        if (restrictExternalToSkCreator) {
          conditions.add(_skScopedExternalCreator);
        }
      case ServiceStaticFilter.externalPregnantWomen:
        conditions.add(_externalMember);
        if (restrictExternalToSkCreator) {
          conditions.add(_skScopedExternalCreator);
        }
        conditions.add(_activePregnancy);
      case ServiceStaticFilter.childrenUnderTwo:
        conditions.add(_childrenUnderTwo);
      case ServiceStaticFilter.ncdServices:
        conditions.add(_hasNcdHistory);
      case ServiceStaticFilter.cataractScreening:
        conditions.add(_hasCataractHistory);
      case ServiceStaticFilter.eyeScreening:
        conditions.add(_hasEyeHistory);
      case ServiceStaticFilter.otherServices:
        conditions.add(_hasOtherServicesHistory);
      case ServiceStaticFilter.pregnantWomen:
        conditions.add(_activePregnancy);
      case ServiceStaticFilter.highRiskPregnantWomen:
        conditions.add(_highRiskPregnant);
      case ServiceStaticFilter.familyPlanningCounselling:
        conditions.add(_familyPlanningEligible);
      case ServiceStaticFilter.postnatalCareMothers:
        conditions.add(_postnatal);
      case ServiceStaticFilter.expectedDeliveries:
        conditions.add(_expectedDelivery);
      case ServiceStaticFilter.pendingDeliveries:
        conditions.add(_pendingDelivery);
      case ServiceStaticFilter.allMembers:
        break;
    }
  }

  bool _skipsActiveCheck(ServiceStaticFilter filter) =>
      filter == ServiceStaticFilter.externalMembers ||
      filter == ServiceStaticFilter.allMembers ||
      filter == ServiceStaticFilter.childrenUnderTwo;

  _AreaFilter _buildAreaFilter({
    String? subVillageId,
    required List<Object?> args,
  }) {
    if (subVillageId == null || subVillageId.isEmpty) {
      return const _AreaFilter('', null, null);
    }
    args.add(subVillageId);
    const withClause = '''
WITH allowed_sub_villages(sub_village_id) AS (VALUES (?))
''';
    return const _AreaFilter(
      withClause,
      'hh.sub_village_id IN (SELECT sub_village_id FROM allowed_sub_villages)',
      'hhm.sub_village_id IN (SELECT sub_village_id FROM allowed_sub_villages)',
    );
  }

  String _filterPredicate(
    ServiceStaticFilter filter, {
    required _AreaFilter area,
    required bool restrictExternalToSkCreator,
  }) {
    final conditions = <String>[];

    void addHouseholdScope() {
      conditions.add(_hasHousehold);
      if (area.householdMatch != null) conditions.add(area.householdMatch!);
    }

    void addExternalScope() {
      if (area.memberMatch != null) conditions.add(area.memberMatch!);
    }

    void addSkExternalCreatorScope() {
      if (restrictExternalToSkCreator &&
          (filter == ServiceStaticFilter.externalMembers ||
              filter == ServiceStaticFilter.externalPregnantWomen)) {
        conditions.add(_skScopedExternalCreator);
      }
    }

    switch (filter) {
      case ServiceStaticFilter.allMembers:
        addHouseholdScope();
      case ServiceStaticFilter.externalMembers:
        conditions.add(_externalMember);
        addExternalScope();
        addSkExternalCreatorScope();
      case ServiceStaticFilter.externalPregnantWomen:
        conditions.add(_externalMember);
        addExternalScope();
        addSkExternalCreatorScope();
        conditions.add(_isActive);
        conditions.add(_activePregnancy);
      case ServiceStaticFilter.childrenUnderTwo:
        addHouseholdScope();
        conditions.add(_childrenUnderTwo);
      case ServiceStaticFilter.ncdServices:
      case ServiceStaticFilter.cataractScreening:
      case ServiceStaticFilter.eyeScreening:
      case ServiceStaticFilter.otherServices:
        addHouseholdScope();
        conditions.add(_isActive);
        conditions.add(switch (filter) {
          ServiceStaticFilter.ncdServices => _hasNcdHistory,
          ServiceStaticFilter.cataractScreening => _hasCataractHistory,
          ServiceStaticFilter.eyeScreening => _hasEyeHistory,
          ServiceStaticFilter.otherServices => _hasOtherServicesHistory,
          _ => '1',
        });
      case ServiceStaticFilter.pregnantWomen:
      case ServiceStaticFilter.highRiskPregnantWomen:
      case ServiceStaticFilter.familyPlanningCounselling:
      case ServiceStaticFilter.postnatalCareMothers:
      case ServiceStaticFilter.expectedDeliveries:
      case ServiceStaticFilter.pendingDeliveries:
        addHouseholdScope();
        conditions.add(_isActive);
        conditions.add(switch (filter) {
          ServiceStaticFilter.pregnantWomen => _activePregnancy,
          ServiceStaticFilter.highRiskPregnantWomen => _highRiskPregnant,
          ServiceStaticFilter.familyPlanningCounselling =>
            _familyPlanningEligible,
          ServiceStaticFilter.postnatalCareMothers => _postnatal,
          ServiceStaticFilter.expectedDeliveries => _expectedDelivery,
          ServiceStaticFilter.pendingDeliveries => _pendingDelivery,
          _ => '1',
        });
    }

    if (conditions.isEmpty) return '1';
    return conditions.map((c) => '($c)').join(' AND ');
  }
}

class _AreaFilter {
  const _AreaFilter(this.withClause, this.householdMatch, this.memberMatch);

  final String withClause;
  final String? householdMatch;
  final String? memberMatch;
}
