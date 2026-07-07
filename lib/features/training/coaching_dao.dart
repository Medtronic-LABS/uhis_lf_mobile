import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';

class CoachingDao {
  const CoachingDao(this._db);

  final AppDatabase _db;

  static const String tableModules = AppDatabase.tableCoachingModules;
  static const String tableProgress = AppDatabase.tableCoachingProgress;

  Future<void> upsertModule({
    required String id,
    required String domain,
    required String titleEn,
    required String titleBn,
    required int estimatedMinutes,
    required String rawJson,
    required bool priorityToday,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.insert(
      tableModules,
      {
        'id': id,
        'domain': domain,
        'title_en': titleEn,
        'title_bn': titleBn,
        'estimated_minutes': estimatedMinutes,
        'raw_json': rawJson,
        'priority_today': priorityToday ? 1 : 0,
        'synced_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> allModulesWithProgress() async {
    return _db.db.rawQuery('''
      SELECT m.*, p.passed, p.quiz_score, p.last_card_viewed
      FROM $tableModules m
      LEFT JOIN $tableProgress p ON p.module_id = m.id
      ORDER BY m.priority_today DESC, m.domain
    ''');
  }

  Future<void> setPriorityToday(String moduleId, bool priority) async {
    await _db.db.update(
      tableModules,
      {'priority_today': priority ? 1 : 0},
      where: 'id = ?',
      whereArgs: [moduleId],
    );
  }

  Future<void> upsertProgress({
    required String moduleId,
    required bool passed,
    required double quizScore,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _db.db.query(
      tableProgress,
      where: 'module_id = ?',
      whereArgs: [moduleId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await _db.db.insert(tableProgress, {
        'module_id': moduleId,
        'passed': passed ? 1 : 0,
        'quiz_score': quizScore,
        'last_card_viewed': -1,
        'updated_at': now,
      });
    } else {
      await _db.db.update(
        tableProgress,
        {
          'passed': passed ? 1 : 0,
          'quiz_score': quizScore,
          'updated_at': now,
        },
        where: 'module_id = ?',
        whereArgs: [moduleId],
      );
    }
  }

  Future<void> markCardViewed(String moduleId, int cardIndex) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _db.db.query(
      tableProgress,
      where: 'module_id = ?',
      whereArgs: [moduleId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await _db.db.insert(tableProgress, {
        'module_id': moduleId,
        'passed': 0,
        'quiz_score': 0.0,
        'last_card_viewed': cardIndex,
        'updated_at': now,
      });
    } else {
      final lastViewed = (existing.first['last_card_viewed'] as int?) ?? -1;
      if (cardIndex > lastViewed) {
        await _db.db.update(
          tableProgress,
          {'last_card_viewed': cardIndex, 'updated_at': now},
          where: 'module_id = ?',
          whereArgs: [moduleId],
        );
      }
    }
  }

  Future<bool> isEmpty() async {
    final count = Sqflite.firstIntValue(
      await _db.db.rawQuery('SELECT COUNT(*) FROM $tableModules'),
    );
    return (count ?? 0) == 0;
  }
}
