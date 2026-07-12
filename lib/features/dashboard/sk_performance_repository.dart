import '../../core/db/app_database.dart';
import '../../core/db/local_assessment_dao.dart';

class RecentVisitActivity {
  const RecentVisitActivity({
    required this.patientName,
    required this.villageName,
    required this.programme,
    required this.isReferred,
    required this.createdAt,
    this.patientId,
  });

  final String patientName;
  final String villageName;
  final String programme;
  final bool isReferred;
  final DateTime createdAt;
  final String? patientId;
}

class SkPerformanceStats {
  const SkPerformanceStats({
    required this.visitsToday,
    required this.visitsThisWeek,
    required this.visitsThisMonth,
    required this.referralsThisWeek,
    required this.referralsThisMonth,
    required this.totalHouseholds,
    required this.visitsByProgramme,
    required this.visitsByProgrammeMonth,
    required this.recentActivity,
    required this.weekStartDate,
    required this.monthStartDate,
  });

  final int visitsToday;
  final int visitsThisWeek;
  final int visitsThisMonth;
  final int referralsThisWeek;
  final int referralsThisMonth;
  final int totalHouseholds;

  /// Programme breakdown for THIS WEEK.
  final Map<String, int> visitsByProgramme;

  /// Programme breakdown for THIS MONTH.
  final Map<String, int> visitsByProgrammeMonth;

  final List<RecentVisitActivity> recentActivity;
  final DateTime weekStartDate;
  final DateTime monthStartDate;

  static const int weeklyTarget = 15;
  static const int monthlyTarget = 60;
}

class SkPerformanceRepository {
  SkPerformanceRepository(this._db);

  final AppDatabase _db;

  Future<SkPerformanceStats> load() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    final todayMs = todayStart.millisecondsSinceEpoch;
    final weekMs = weekStart.millisecondsSinceEpoch;
    final monthMs = monthStart.millisecondsSinceEpoch;

    final table = LocalAssessmentDao.tableName;
    final db = _db.db;

    int count(List<Map<String, Object?>> rows) =>
        (rows.first['c'] as int?) ?? 0;

    final results = await Future.wait([
      // 0: today visits
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE created_at >= ?', [todayMs]),
      // 1: week visits
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE created_at >= ?', [weekMs]),
      // 2: month visits
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE created_at >= ?', [monthMs]),
      // 3: referrals this week
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE is_referred = 1 AND created_at >= ?',
          [weekMs]),
      // 4: total households
      db.rawQuery(
          'SELECT COUNT(*) as c FROM ${AppDatabase.tableHouseholds}', []),
      // 5: visits by programme this week
      db.rawQuery(
          'SELECT assessment_type, COUNT(*) as c FROM $table '
          'WHERE created_at >= ? GROUP BY assessment_type',
          [weekMs]),
      // 6: recent activity
      db.rawQuery(
          '''
          SELECT la.assessment_type, la.is_referred, la.created_at,
                 la.patient_id,
                 m.name as member_name, m.village_name,
                 p.name as patient_name, p.village_name as p_village_name
          FROM $table la
          LEFT JOIN ${AppDatabase.tableMembers} m
            ON la.household_member_local_id = CAST(m.id AS INTEGER)
          LEFT JOIN ${AppDatabase.tablePatients} p
            ON la.patient_id = p.id
          ORDER BY la.created_at DESC
          LIMIT 8
          ''',
          []),
      // 7: referrals this month
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE is_referred = 1 AND created_at >= ?',
          [monthMs]),
      // 8: visits by programme this month
      db.rawQuery(
          'SELECT assessment_type, COUNT(*) as c FROM $table '
          'WHERE created_at >= ? GROUP BY assessment_type',
          [monthMs]),
    ]);

    Map<String, int> buildByProgramme(List<Map<String, Object?>> rows) {
      final map = <String, int>{
        'ANC': 0, 'NCD': 0, 'IMCI': 0, 'PNC': 0, 'HOUSEHOLD': 0,
      };
      for (final row in rows) {
        final type = (row['assessment_type'] as String?)?.toUpperCase() ?? '?';
        map[type] = (row['c'] as int?) ?? 0;
      }
      return map;
    }

    final recent = results[6].map((row) {
      final name = (row['member_name'] as String?) ??
          (row['patient_name'] as String?) ??
          'Unknown';
      final village = (row['village_name'] as String?) ??
          (row['p_village_name'] as String?) ??
          '';
      final programme =
          (row['assessment_type'] as String?)?.toUpperCase() ?? '';
      final referred = (row['is_referred'] as int?) == 1;
      final ts = row['created_at'] as int? ?? 0;
      return RecentVisitActivity(
        patientName: name,
        villageName: village,
        programme: programme,
        isReferred: referred,
        createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
        patientId: row['patient_id'] as String?,
      );
    }).toList();

    return SkPerformanceStats(
      visitsToday: count(results[0]),
      visitsThisWeek: count(results[1]),
      visitsThisMonth: count(results[2]),
      referralsThisWeek: count(results[3]),
      referralsThisMonth: count(results[7]),
      totalHouseholds: count(results[4]),
      visitsByProgramme: buildByProgramme(results[5]),
      visitsByProgrammeMonth: buildByProgramme(results[8]),
      recentActivity: recent,
      weekStartDate: weekStart,
      monthStartDate: monthStart,
    );
  }
}
