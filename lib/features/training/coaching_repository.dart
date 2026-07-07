import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/config/app_config.dart';
import 'coaching_dao.dart';
import 'coaching_models.dart';
import 'coaching_telemetry_service.dart';

class CoachingRepository extends ChangeNotifier {
  CoachingRepository(this._dao, ApiClient api, this._authRepo)
      : _telemetry = CoachingTelemetryService(api),
        _api = api;

  final CoachingDao _dao;
  final ApiClient _api;
  final AuthRepository _authRepo;
  final CoachingTelemetryService _telemetry;

  List<CoachingModule> _modules = [];

  List<CoachingModule> get modules => List.unmodifiable(_modules);

  List<CoachingModule> get todaysPriorities =>
      _modules.where((m) => m.priorityToday).toList();

  /// Loads modules from SQLite; falls back to mock data in debug builds.
  Future<void> initialize() async {
    try {
      final rows = await _dao.allModulesWithProgress();
      if (rows.isNotEmpty) {
        _modules = rows.map(_rowToModule).toList();
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('[CoachingRepository] initialize DB read failed: $e');
    }
    // Fallback: mock data in debug builds so the UI is never empty.
    if (kDebugMode) {
      _modules = MockCoachingData.allModules;
      notifyListeners();
    }
  }

  /// Fetches from the spice-coaching backend and persists to SQLite.
  Future<void> syncFromApi(int userId) async {
    try {
      final since = _lastSyncIso();
      final modulesUrl =
          '${AppConfig.coachingServiceUrl}/medtronics-api/sync/modules'
          '?since=$since&user_id=$userId';
      final gapsUrl =
          '${AppConfig.coachingServiceUrl}/medtronics-api/sync/gaps'
          '?chw_id=$userId&since=$since';

      final [modulesRes, gapsRes] = await Future.wait([
        _api.dio.get<Map<String, dynamic>>(modulesUrl),
        _api.dio.get<Map<String, dynamic>>(gapsUrl),
      ]);

      final gapIds = <String>{};
      final gaps =
          (gapsRes.data?['gaps'] as List<dynamic>?) ?? [];
      for (final g in gaps) {
        final mid = (g as Map)['module_id'];
        if (mid is String) gapIds.add(mid);
      }

      final rawModules =
          (modulesRes.data?['modules'] as List<dynamic>?) ?? [];
      for (final raw in rawModules) {
        final m = raw as Map<String, dynamic>;
        final id = m['id'] as String;
        final parsed = _parseModule(m, null, gapIds.contains(id));
        await _dao.upsertModule(
          id: parsed.id,
          domain: parsed.domain.name,
          titleEn: parsed.titleEn,
          titleBn: parsed.titleBn,
          estimatedMinutes: parsed.estimatedMinutes,
          rawJson: jsonEncode(m),
          priorityToday: parsed.priorityToday,
        );
      }

      // Reload from DB after sync.
      final rows = await _dao.allModulesWithProgress();
      _modules = rows.map(_rowToModule).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[CoachingRepository] syncFromApi failed: $e');
    }
  }

  Future<void> markCardViewed(String moduleId, int cardIndex) async {
    try {
      await _dao.markCardViewed(moduleId, cardIndex);
      final userId = await _authRepo.userId();
      if (userId != null) {
        _telemetry.fireCardViewed(userId, moduleId, cardIndex);
      }
    } catch (e) {
      debugPrint('[CoachingRepository] markCardViewed failed: $e');
    }
  }

  Future<void> markQuizCompleted(String moduleId, double score) async {
    final passed = score >= 0.70;
    try {
      await _dao.upsertProgress(
          moduleId: moduleId, passed: passed, quizScore: score);
      // Update in-memory list.
      _modules = _modules.map((m) {
        if (m.id != moduleId) return m;
        return CoachingModule(
          id: m.id,
          domain: m.domain,
          titleEn: m.titleEn,
          titleBn: m.titleBn,
          estimatedMinutes: m.estimatedMinutes,
          cards: m.cards,
          quiz: m.quiz,
          passed: passed,
          quizScore: score,
          priorityToday: m.priorityToday,
        );
      }).toList();
      notifyListeners();
      final userId = await _authRepo.userId();
      if (userId != null) {
        _telemetry.fireQuizAttempted(userId, moduleId, score, passed);
      }
    } catch (e) {
      debugPrint('[CoachingRepository] markQuizCompleted failed: $e');
    }
  }

  // ─── Parsing ──────────────────────────────────────────────────────────────

  CoachingModule _rowToModule(Map<String, dynamic> row) {
    final rawJson = row['raw_json'] as String? ?? '{}';
    final raw = jsonDecode(rawJson) as Map<String, dynamic>;
    final passed = (row['passed'] as int?) == 1;
    final quizScore = (row['quiz_score'] as num?)?.toDouble() ?? 0.0;
    final priorityToday = (row['priority_today'] as int?) == 1;
    return _parseModule(raw, {'passed': passed, 'quiz_score': quizScore},
        priorityToday);
  }

  CoachingModule _parseModule(
    Map<String, dynamic> raw,
    Map<String, dynamic>? progress,
    bool priorityToday,
  ) {
    final id = raw['id'] as String? ?? '';
    final domainStr = raw['domain'] as String? ?? 'anc';
    final domain = _parseDomain(domainStr);
    final titleEn = _locale(raw['title'], 'en') ?? id;
    final titleBn = _locale(raw['title'], 'bn') ?? titleEn;
    final estimatedMinutes = (raw['estimated_minutes'] as num?)?.toInt() ?? 5;
    final rawCards = (raw['cards'] as List<dynamic>?) ?? [];
    final rawQuiz = (raw['quiz'] as List<dynamic>?) ?? [];

    return CoachingModule(
      id: id,
      domain: domain,
      titleEn: titleEn,
      titleBn: titleBn,
      estimatedMinutes: estimatedMinutes,
      cards: rawCards.map((c) => _parseCard(c as Map<String, dynamic>)).toList(),
      quiz: rawQuiz
          .map((q) => _parseQuestion(q as Map<String, dynamic>))
          .toList(),
      passed: (progress?['passed'] as bool?) ?? false,
      quizScore: (progress?['quiz_score'] as double?) ?? 0.0,
      priorityToday: priorityToday,
    );
  }

  LessonCard _parseCard(Map<String, dynamic> raw) {
    final titleEn = _locale(raw['title'], 'en') ?? '';
    final titleBn = _locale(raw['title'], 'bn') ?? titleEn;
    final body = raw['body'];
    List<ContentBlock> blocks;
    if (body is Map && body['type'] == 'doc') {
      blocks = _parseProseMirror(body);
    } else if (body is Map) {
      // Plain locale dict
      final text = _locale(body, 'en') ?? '';
      blocks = [ContentBlock(type: ContentBlockType.paragraph, text: text)];
    } else {
      blocks = [];
    }
    return LessonCard(titleEn: titleEn, titleBn: titleBn, blocks: blocks);
  }

  List<ContentBlock> _parseProseMirror(Map doc) {
    final content = (doc['content'] as List<dynamic>?) ?? [];
    final blocks = <ContentBlock>[];
    for (final node in content) {
      final n = node as Map;
      final type = n['type'] as String? ?? '';
      switch (type) {
        case 'paragraph':
          final text = _extractText(n);
          if (text.isNotEmpty) {
            blocks.add(ContentBlock(type: ContentBlockType.paragraph, text: text));
          }
        case 'heading':
          final text = _extractText(n);
          if (text.isNotEmpty) {
            blocks.add(ContentBlock(type: ContentBlockType.heading, text: text));
          }
        case 'bullet_list':
          final items = _extractListItems(n);
          if (items.isNotEmpty) {
            blocks.add(ContentBlock(type: ContentBlockType.bulletList, items: items));
          }
        case 'ordered_list':
          final items = _extractListItems(n);
          if (items.isNotEmpty) {
            blocks.add(ContentBlock(type: ContentBlockType.orderedList, items: items));
          }
      }
    }
    return blocks;
  }

  String _extractText(Map node) {
    final content = (node['content'] as List<dynamic>?) ?? [];
    final buf = StringBuffer();
    for (final child in content) {
      final c = child as Map;
      if (c['type'] == 'text') {
        buf.write(c['text'] as String? ?? '');
      }
    }
    return buf.toString();
  }

  List<String> _extractListItems(Map node) {
    final items = <String>[];
    final content = (node['content'] as List<dynamic>?) ?? [];
    for (final item in content) {
      final i = item as Map;
      if (i['type'] == 'list_item') {
        final paraContent = (i['content'] as List<dynamic>?) ?? [];
        for (final para in paraContent) {
          final text = _extractText(para as Map);
          if (text.isNotEmpty) items.add(text);
        }
      }
    }
    return items;
  }

  QuizQuestion _parseQuestion(Map<String, dynamic> raw) {
    final questionEn = _locale(raw['question'], 'en') ?? '';
    final questionBn = _locale(raw['question'], 'bn') ?? questionEn;
    final rawOptions = (raw['options'] as List<dynamic>?) ?? [];
    final options =
        rawOptions.map((o) => _locale(o as Map, 'en') ?? '').toList();
    final correctIndices = (raw['correct_indices'] as List<dynamic>?) ?? [];
    final correctIndex =
        correctIndices.isNotEmpty ? (correctIndices.first as num).toInt() : 0;
    final rationale = _locale(raw['rationale'], 'en') ?? '';
    return QuizQuestion(
      questionEn: questionEn,
      questionBn: questionBn,
      options: options,
      correctIndex: correctIndex,
      rationale: rationale,
    );
  }

  CoachingDomain _parseDomain(String s) => switch (s) {
        'anc' => CoachingDomain.anc,
        'ncd' => CoachingDomain.ncd,
        'imci' => CoachingDomain.imci,
        'tb' => CoachingDomain.tb,
        'epi' => CoachingDomain.epi,
        'nutrition' => CoachingDomain.nutrition,
        _ => CoachingDomain.anc,
      };

  String? _locale(dynamic value, String lang) {
    if (value is Map) return value[lang] as String?;
    return null;
  }

  String _lastSyncIso() {
    // TODO: persist last sync timestamp in sync_meta table.
    // For now, use a fixed past date so we always fetch everything.
    return '2020-01-01T00:00:00Z';
  }
}
