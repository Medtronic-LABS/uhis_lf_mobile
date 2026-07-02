import '../../core/db/app_database.dart';

class SkPerformanceStats {
  const SkPerformanceStats({
    required this.visitsToday,
    required this.visitsThisWeek,
    required this.visitsThisMonth,
    required this.referralsThisWeek,
    required this.householdsTotal,
    required this.visitsByProgramme,
    required this.recentActivity,
    required this.weekTarget,
  });

  final int visitsToday;
  final int visitsThisWeek;
  final int visitsThisMonth;
  final int referralsThisWeek;
  final int householdsTotal;
  final Map<String, int> visitsByProgramme;
  final List<RecentVisitActivity> recentActivity;
  final int weekTarget;
}

class RecentVisitActivity {
  const RecentVisitActivity({
    required this.patientName,
    required this.programme,
    required this.villageName,
    required this.isReferred,
    required this.createdAt,
  });

  final String patientName;
  final String programme;
  final String? villageName;
  final bool isReferred;
  final DateTime createdAt;
}

class SkPerformanceRepository {
  SkPerformanceRepository(this._db);

  final AppDatabase _db;

  static const int _weekTargetDefault = 15;

  Future<SkPerformanceStats> load() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekday = now.weekday; // Mon=1 … Sun=7
    final weekStart = todayStart.subtract(Duration(days: weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    final todayMs = todayStart.millisecondsSinceEpoch;
    final weekMs = weekStart.millisecondsSinceEpoch;
    final monthMs = monthStart.millisecondsSinceEpoch;

    final db = _db.db;

    final results = await Future.wait([
      db.rawQuery(
        'SELECT COUNT(*) AS c FROM local_assessments WHERE created_at >= ?',
        [todayMs],
      ),
      db.rawQuery(
        'SELECT COUNT(*) AS c FROM local_assessments WHERE created_at >= ?',
        [weekMs],
      ),
      db.rawQuery(
        'SELECT COUNT(*) AS c FROM local_assessments WHERE created_at >= ?',
        [monthMs],
      ),
      db.rawQuery(
        'SELECT COUNT(*) AS c FROM local_assessments WHERE is_referred = 1 AND created_at >= ?',
        [weekMs],
      ),
      db.rawQuery('SELECT COUNT(*) AS c FROM households'),
      db.rawQuery(
        'SELECT assessment_type, COUNT(*) AS c FROM local_assessments WHERE created_at >= ? GROUP BY assessment_type',
        [weekMs],
      ),
      db.rawQuery(
        '''
        SELECT la.assessment_type, la.is_referred, la.created_at,
               COALESCE(p.name, m.name, 'Unknown') AS patient_name,
               COALESCE(p.village_name, m.village_name) AS village_name
        FROM local_assessments la
        LEFT JOIN patients p ON la.patient_id = p.patient_id
        LEFT JOIN members m ON la.household_member_local_id = m.id
        ORDER BY la.created_at DESC
        LIMIT 8
        ''',
      ),
    ]);

    int count(List<Map<String, Object?>> rows) =>
        rows.first['c'] as int? ?? 0;

    final byProg = <String, int>{};
    for (final row in results[5]) {
      final type = (row['assessment_type'] as String? ?? '').toUpperCase();
      if (type.isNotEmpty) byProg[type] = (row['c'] as int? ?? 0);
    }

    final activity = results[6].map((row) {
      final tsMs = row['created_at'] as int?;
      return RecentVisitActivity(
        patientName: row['patient_name'] as String? ?? 'Unknown',
        programme: (row['assessment_type'] as String? ?? '').toUpperCase(),
        villageName: row['village_name'] as String?,
        isReferred: (row['is_referred'] as int?) == 1,
        createdAt: tsMs != null
            ? DateTime.fromMillisecondsSinceEpoch(tsMs)
            : DateTime.now(),
      );
    }).toList();

    return SkPerformanceStats(
      visitsToday: count(results[0]),
      visitsThisWeek: count(results[1]),
      visitsThisMonth: count(results[2]),
      referralsThisWeek: count(results[3]),
      householdsTotal: count(results[4]),
      visitsByProgramme: byProg,
      recentActivity: activity,
      weekTarget: _weekTargetDefault,
    );
  }
}
