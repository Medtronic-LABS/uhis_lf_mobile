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
    required this.referralsCompleted,
    required this.totalHouseholds,
    required this.visitsByProgramme,
    required this.recentActivity,
    required this.weekStartDate,
    required this.monthStartDate,
    required this.dailyVisitCounts,
    required this.avgVisitsPerDay,
    required this.missedOverdue,
    required this.slaCompliance,
    required this.highRiskResponseDays,
    required this.performanceScore,
  });

  final int visitsToday;
  final int visitsThisWeek;
  final int visitsThisMonth;
  final int referralsThisWeek;
  final int referralsCompleted;
  final int totalHouseholds;
  final Map<String, int> visitsByProgramme;
  final List<RecentVisitActivity> recentActivity;
  final DateTime weekStartDate;
  final DateTime monthStartDate;

  /// Count per weekday Mon(0)→Sun(6) for the current week's bar chart.
  final List<int> dailyVisitCounts;
  final double avgVisitsPerDay;
  final int missedOverdue;

  /// 0.0–1.0 (mocked at 1.0 until SLA data is available).
  final double slaCompliance;

  /// Days (mocked at 1.2 until CCE data is available).
  final double highRiskResponseDays;

  /// 0–100 composite score.
  final int performanceScore;

  static const int visitsTarget = 40;

  String get performanceRating {
    if (performanceScore >= 90) return 'Excellent';
    if (performanceScore >= 75) return 'Good';
    if (performanceScore >= 60) return 'Fair';
    return 'Needs Improvement';
  }

  String get performanceEmoji {
    if (performanceScore >= 90) return '⭐';
    if (performanceScore >= 75) return '👍';
    if (performanceScore >= 60) return '👌';
    return '💪';
  }
}

class SkPerformanceRepository {
  SkPerformanceRepository(this._db);

  final AppDatabase _db;

  Future<SkPerformanceStats> load() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // Monday of current week
    final weekStart =
        todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    final todayMs = todayStart.millisecondsSinceEpoch;
    final weekMs = weekStart.millisecondsSinceEpoch;
    final monthMs = monthStart.millisecondsSinceEpoch;

    final table = LocalAssessmentDao.tableName;
    final db = _db.db;

    int count(List<Map<String, Object?>> rows) =>
        (rows.first['c'] as int?) ?? 0;

    // Build daily boundaries Mon–Sun
    final dailyMs = List.generate(7, (i) {
      final day = weekStart.add(Duration(days: i));
      final start = day.millisecondsSinceEpoch;
      final end =
          day.add(const Duration(days: 1)).millisecondsSinceEpoch;
      return (start, end);
    });

    final results = await Future.wait([
      // 0: today visits
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE created_at >= ?',
          [todayMs]),
      // 1: week visits
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE created_at >= ?',
          [weekMs]),
      // 2: month visits
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE created_at >= ?',
          [monthMs]),
      // 3: referrals this week
      db.rawQuery(
          'SELECT COUNT(*) as c FROM $table WHERE is_referred = 1 AND created_at >= ?',
          [weekMs]),
      // 4: total households
      db.rawQuery(
          'SELECT COUNT(*) as c FROM ${AppDatabase.tableHouseholds}',
          []),
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
    ]);

    // Daily counts Mon–Sun
    final dailyCounts = <int>[];
    for (final (start, end) in dailyMs) {
      final rows = await db.rawQuery(
          'SELECT COUNT(*) as c FROM $table '
          'WHERE created_at >= ? AND created_at < ?',
          [start, end]);
      dailyCounts.add((rows.first['c'] as int?) ?? 0);
    }

    // Missed / overdue — patients with a past-due follow-up date
    int missed = 0;
    try {
      final missedRows = await db.rawQuery(
          'SELECT COUNT(*) as c FROM ${AppDatabase.tablePatients} '
          'WHERE next_due_at IS NOT NULL AND next_due_at < ?',
          [todayMs]);
      missed = (missedRows.first['c'] as int?) ?? 0;
    } catch (_) {
      missed = 0;
    }

    final weekVisits = count(results[1]);
    final weekReferrals = count(results[3]);

    final byProgramme = <String, int>{
      'ANC': 0,
      'NCD': 0,
      'IMCI': 0,
      'PNC': 0,
      'HOUSEHOLD': 0,
    };
    for (final row in results[5]) {
      final type =
          (row['assessment_type'] as String?)?.toUpperCase() ?? '?';
      byProgramme[type] = (row['c'] as int?) ?? 0;
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

    final score =
        (50 + (weekVisits * 1.2 + weekReferrals * 2)).clamp(0, 100).toInt();

    return SkPerformanceStats(
      visitsToday: count(results[0]),
      visitsThisWeek: weekVisits,
      visitsThisMonth: count(results[2]),
      referralsThisWeek: weekReferrals,
      referralsCompleted: weekReferrals,
      totalHouseholds: count(results[4]),
      visitsByProgramme: byProgramme,
      recentActivity: recent,
      weekStartDate: weekStart,
      monthStartDate: monthStart,
      dailyVisitCounts: dailyCounts,
      avgVisitsPerDay: weekVisits / 7.0,
      missedOverdue: missed,
      slaCompliance: 1.0,
      highRiskResponseDays: 1.2,
      performanceScore: score,
    );
  }
}
