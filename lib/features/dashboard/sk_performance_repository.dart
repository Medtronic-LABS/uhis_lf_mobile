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
    required this.referralsCompleted,
    required this.totalHouseholds,
    required this.visitsByProgramme,
    required this.visitsByProgrammeMonth,
    required this.recentActivity,
    required this.weekStartDate,
    required this.monthStartDate,
    required this.dailyVisitCounts,
    required this.weeklyVisitCounts,
    required this.avgVisitsPerDay,
    required this.avgVisitsPerDayMonth,
    required this.missedOverdue,
    required this.slaCompliance,
    required this.highRiskResponseDays,
    required this.performanceScore,
    required this.performanceScoreMonth,
  });

  final int visitsToday;
  final int visitsThisWeek;
  final int visitsThisMonth;
  final int referralsThisWeek;
  final int referralsThisMonth;
  final int referralsCompleted;
  final int totalHouseholds;

  /// Programme breakdown for THIS WEEK.
  final Map<String, int> visitsByProgramme;

  /// Programme breakdown for THIS MONTH.
  final Map<String, int> visitsByProgrammeMonth;

  final List<RecentVisitActivity> recentActivity;
  final DateTime weekStartDate;
  final DateTime monthStartDate;

  /// Count per weekday Mon(0)→Sun(6) for the current week's bar chart.
  final List<int> dailyVisitCounts;

  /// Count per week W1–W4 within the current month's bar chart.
  final List<int> weeklyVisitCounts;

  final double avgVisitsPerDay;
  final double avgVisitsPerDayMonth;
  final int missedOverdue;

  /// 0.0–1.0 (mocked at 1.0 until SLA data is available).
  final double slaCompliance;

  /// Days (mocked at 1.2 until CCE data is available).
  final double highRiskResponseDays;

  /// 0–100 composite score for THIS WEEK.
  final int performanceScore;

  /// 0–100 composite score for THIS MONTH.
  final int performanceScoreMonth;

  static const int visitsTarget = 40;
  static const int visitsTargetMonth = 160;

  String ratingFor(int score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 60) return 'Fair';
    return 'Needs Improvement';
  }

  String emojiFor(int score) {
    if (score >= 90) return '⭐';
    if (score >= 75) return '👍';
    if (score >= 60) return '👌';
    return '💪';
  }

  String get performanceRating => ratingFor(performanceScore);
  String get performanceEmoji => emojiFor(performanceScore);
  String get performanceRatingMonth => ratingFor(performanceScoreMonth);
  String get performanceEmojiMonth => emojiFor(performanceScoreMonth);
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

    // Weekly boundaries for month (W1–W4)
    final daysInMonth =
        DateTime(now.year, now.month + 1, 0).day;
    final weeklyMs = List.generate(4, (i) {
      final start = monthStart.add(Duration(days: i * 7));
      final end = (i == 3)
          ? DateTime(now.year, now.month + 1, 1)
          : monthStart.add(Duration(days: (i + 1) * 7));
      return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
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

    // Daily counts Mon–Sun
    final dailyCounts = <int>[];
    for (final (start, end) in dailyMs) {
      final rows = await db.rawQuery(
          'SELECT COUNT(*) as c FROM $table '
          'WHERE created_at >= ? AND created_at < ?',
          [start, end]);
      dailyCounts.add((rows.first['c'] as int?) ?? 0);
    }

    // Weekly counts W1–W4 within month
    final weeklyCounts = <int>[];
    for (final (start, end) in weeklyMs) {
      final rows = await db.rawQuery(
          'SELECT COUNT(*) as c FROM $table '
          'WHERE created_at >= ? AND created_at < ?',
          [start, end]);
      weeklyCounts.add((rows.first['c'] as int?) ?? 0);
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
    final monthVisits = count(results[2]);
    final weekReferrals = count(results[3]);
    final monthReferrals = count(results[7]);

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

    final weekScore =
        (50 + (weekVisits * 1.2 + weekReferrals * 2)).clamp(0, 100).toInt();
    final monthScore =
        (50 + (monthVisits * 0.3 + monthReferrals * 0.5)).clamp(0, 100).toInt();

    return SkPerformanceStats(
      visitsToday: count(results[0]),
      visitsThisWeek: weekVisits,
      visitsThisMonth: monthVisits,
      referralsThisWeek: weekReferrals,
      referralsThisMonth: monthReferrals,
      referralsCompleted: weekReferrals,
      totalHouseholds: count(results[4]),
      visitsByProgramme: buildByProgramme(results[5]),
      visitsByProgrammeMonth: buildByProgramme(results[8]),
      recentActivity: recent,
      weekStartDate: weekStart,
      monthStartDate: monthStart,
      dailyVisitCounts: dailyCounts,
      weeklyVisitCounts: weeklyCounts,
      avgVisitsPerDay: weekVisits / 7.0,
      avgVisitsPerDayMonth: monthVisits / daysInMonth,
      missedOverdue: missed,
      slaCompliance: 1.0,
      highRiskResponseDays: 1.2,
      performanceScore: weekScore,
      performanceScoreMonth: monthScore,
    );
  }
}
