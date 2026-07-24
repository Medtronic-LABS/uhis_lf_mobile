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
    int priorityRank = 0,
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
        // Higher rank floats first (ORDER BY priority_today DESC). 0 = not today.
        'priority_today': priorityRank,
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

  /// Clears every module's morning rank (sets `priority_today` to 0).
  Future<void> clearAllPriorities() async {
    await _db.db.update(tableModules, {'priority_today': 0});
  }

  /// Sets morning priority ranks. [orderedIds] is highest-priority first;
  /// the first id gets rank = length, the last gets rank = 1.
  Future<void> applyMorningPriorities(List<String> orderedIds) async {
    await clearAllPriorities();
    if (orderedIds.isEmpty) return;
    final n = orderedIds.length;
    for (var i = 0; i < n; i++) {
      await _db.db.update(
        tableModules,
        {'priority_today': n - i},
        where: 'id = ?',
        whereArgs: [orderedIds[i]],
      );
    }
  }

  Future<void> setPriorityRank(String moduleId, int rank) async {
    await _db.db.update(
      tableModules,
      {'priority_today': rank},
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

/// Persists the assistant chat history so the user sees prior messages across
/// app restarts.
class ChatMessageDao {
  const ChatMessageDao(this._db);

  final AppDatabase _db;

  static const String _table = AppDatabase.tableChatMessages;

  Future<void> insertMessage({
    required String id,
    required String role,
    required String text,
    required int timestampMs,
    String? suggestedQuestionsJson,
  }) async {
    await _db.db.insert(
      _table,
      {
        'id': id,
        'role': role,
        'text': text,
        'timestamp_ms': timestampMs,
        'suggested_questions': suggestedQuestionsJson,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns up to [limit] most recent messages, ordered oldest-first.
  Future<List<Map<String, dynamic>>> recentMessages({int limit = 50}) async {
    return _db.db.query(
      _table,
      orderBy: 'timestamp_ms ASC',
      limit: limit,
    );
  }

  Future<void> clearAll() async {
    await _db.db.delete(_table);
  }
}

/// Caches coaching FAQ suggestions synced from the platform backend.
class CoachingFaqDao {
  const CoachingFaqDao(this._db);

  final AppDatabase _db;

  static const String _table = AppDatabase.tableCoachingFaqs;

  Future<void> upsertFaq({
    required String id,
    required String questionEn,
    String? questionBn,
    required int occurrenceCount,
    required int rank,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.insert(
      _table,
      {
        'id': id,
        'question_en': questionEn,
        'question_bn': questionBn,
        'occurrence_count': occurrenceCount,
        'rank': rank,
        'synced_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns all FAQs ordered by rank ascending (lower rank = higher priority).
  Future<List<Map<String, dynamic>>> allFaqs() async {
    return _db.db.query(_table, orderBy: 'rank ASC');
  }

  Future<void> clearAll() async {
    await _db.db.delete(_table);
  }
}
