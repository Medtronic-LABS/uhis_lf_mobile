import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/debug/console_log.dart';
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
  List<String> _cachedFaqs = [];
  List<String> _gapIds = [];
  List<KnowledgeDocument> _knowledgeDocs = [];
  final Map<String, String> _moduleThumbnails = {};
  bool _syncing = false;

  List<CoachingModule> get modules => List.unmodifiable(_modules);

  /// FAQ suggestion strings synced from the coaching backend, ordered by rank.
  List<String> get cachedFaqs => List.unmodifiable(_cachedFaqs);

  /// Modules flagged as behavioural gaps from the last sync.
  /// These populate the Refreshers section.
  List<CoachingModule> get gapModules =>
      _modules.where((m) => _gapIds.contains(m.id)).toList();

  /// Modules ranked for today (morning endpoint / gap fallback). Highest
  /// priority first — matches SQLite `ORDER BY priority_today DESC`.
  List<CoachingModule> get todaysPriorities =>
      _modules.where((m) => m.priorityToday).toList();

  bool get isSyncing => _syncing;

  /// Source documents synced from the coaching backend (knowledge library).
  List<KnowledgeDocument> get knowledgeDocs => List.unmodifiable(_knowledgeDocs);

  /// Presigned thumbnail URL for a module, or null if none fetched.
  String? moduleThumbnailUrl(String moduleId) => _moduleThumbnails[moduleId];

  /// Drops the in-memory module/progress snapshot. Call on logout — this
  /// repository is a single long-lived instance for the app's whole process
  /// (see main.dart), so without this the next user to log in on the same
  /// device would briefly see the previous user's cached training progress
  /// until [initialize] or [refresh] runs again.
  void clear() {
    _modules = [];
    _gapIds = [];
    _knowledgeDocs = [];
    _moduleThumbnails.clear();
    notifyListeners();
  }

  /// Loads modules from SQLite; shows empty state if none cached.
  Future<void> initialize() async {
    try {
      final rows = await _dao.allModulesWithProgress();
      if (rows.isNotEmpty) {
        _modules = rows.map(_rowToModule).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CoachingRepository] initialize DB read failed: $e');
    }
  }

  /// Resolves the signed-in user and pulls modules + morning priorities from
  /// the coaching service. On network failure, keeps whatever [initialize]
  /// already loaded (SQLite / debug mock). Safe to call repeatedly.
  Future<void> refresh() async {
    final userId = await _authRepo.userId();
    if (userId == null) {
      await initialize();
      return;
    }
    await syncFromApi(userId);
  }

  /// Fetches modules, gaps, and morning priorities from spice-coaching and
  /// persists them to SQLite. Non-fatal on failure (offline-first).
  Future<void> syncFromApi(int userId) async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();
    try {
      final since = _lastSyncIso();
      final base = AppConfig.coachingServiceUrl;
      final modulesUrl =
          '$base${Endpoints.coachingSyncModules}?since=$since&user_id=$userId';
      final gapsUrl =
          '$base${Endpoints.coachingSyncGaps}?chw_id=$userId&since=$since';
      final morningUrl =
          '$base${Endpoints.coachingMorningCards}?chw_id=$userId';

      ConsoleLog.banner(
        '[PayloadDebug] coaching-sync\n'
        'modules=$modulesUrl\n'
        'gaps=$gapsUrl\n'
        'morning=$morningUrl',
      );

      final [modulesRes, gapsRes, morningRes] = await Future.wait([
        _api.dio.get<Map<String, dynamic>>(modulesUrl),
        _api.dio.get<Map<String, dynamic>>(gapsUrl),
        _api.dio.get<Map<String, dynamic>>(morningUrl),
      ]);

      ConsoleLog.success(
        '[PayloadDebug] coaching-sync → '
        'modules=${modulesRes.statusCode} '
        'gaps=${gapsRes.statusCode} '
        'morning=${morningRes.statusCode}',
      );

      ConsoleLog.banner('[PayloadDebug] coaching-gaps-raw → ${gapsRes.data}');
      ConsoleLog.banner('[PayloadDebug] coaching-morning-raw → ${morningRes.data}');

      // Non-blocking: FAQ + knowledge sync failures don't abort the main sync.
      await Future.wait([
        syncChatFaqs(userId),
        _syncKnowledgeDocs(),
      ]);

      final gapIds = <String>{};
      final gaps = (gapsRes.data?['behavioural_gaps'] as List<dynamic>?) ?? [];
      for (final g in gaps) {
        if (g is! Map) continue;
        final mid = g['module_id'] ?? g['id'];
        if (mid is String && mid.isNotEmpty) gapIds.add(mid);
      }

      final morningIds = parseMorningModuleIds(morningRes.data);
      ConsoleLog.step('[PayloadDebug] coaching-parsed → gapDefs=${gapIds.length} morningIds=${morningIds.length}:$morningIds');

      final rawModules =
          (modulesRes.data?['modules'] as List<dynamic>?) ?? [];
      for (final raw in rawModules) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final parsed = _parseModule(m, null, false);
        if (parsed.id.isEmpty) continue;
        await _dao.upsertModule(
          id: parsed.id,
          domain: parsed.domain.name,
          titleEn: parsed.titleEn,
          titleBn: parsed.titleBn,
          estimatedMinutes: parsed.estimatedMinutes,
          rawJson: jsonEncode(m),
          priorityRank: 0,
        );
      }

      // Map gap definition UUIDs → module IDs for the Refreshers section.
      final gapModuleIds = <String>{};
      for (final raw in rawModules) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final moduleId = m['id'] as String? ?? '';
        if (moduleId.isEmpty) continue;
        final primaryGapId = m['primary_gap_id'] as String?;
        if (primaryGapId != null && gapIds.contains(primaryGapId)) {
          gapModuleIds.add(moduleId);
          continue;
        }
        final bgIds = (m['behavioural_gap_ids'] as List<dynamic>?)
                ?.whereType<String>()
                .toSet() ??
            {};
        if (bgIds.intersection(gapIds).isNotEmpty) {
          gapModuleIds.add(moduleId);
        }
      }
      _gapIds = gapModuleIds.toList();
      ConsoleLog.step('[PayloadDebug] coaching-gap-modules → ${_gapIds.length}:$_gapIds');
      // Non-blocking: thumbnail sync — best-effort.
      await _syncModuleThumbnails(rawModules);
      notifyListeners();

      // Morning list wins; if the morning endpoint is empty/unavailable,
      // fall back to gap-flagged modules so the Today section is not blank.
      if (morningIds.isNotEmpty) {
        await _dao.applyMorningPriorities(morningIds);
      } else if (gapIds.isNotEmpty) {
        await _dao.applyMorningPriorities(gapIds.toList());
      } else {
        await _dao.clearAllPriorities();
      }

      final rows = await _dao.allModulesWithProgress();
      if (rows.isNotEmpty) {
        _modules = rows.map(_rowToModule).toList();
      }
      notifyListeners();
    } catch (e) {
      ConsoleLog.warn('[PayloadDebug] coaching-sync failed: $e');
      debugPrint('[CoachingRepository] syncFromApi failed: $e');
      // Keep cached content — offline-first.
      if (_modules.isEmpty) {
        await initialize();
      }
    } finally {
      _syncing = false;
      notifyListeners();
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

  /// Fetches FAQ suggestions from the coaching backend and caches them in
  /// memory. Failures are non-fatal — the starters fall back to hardcoded copy.
  Future<void> syncChatFaqs(int userId) async {
    try {
      final base = AppConfig.coachingServiceUrl;
      final since = _lastSyncIso();
      final url = '$base${Endpoints.coachingSyncChatFaqs}?since=$since';
      ConsoleLog.step('[PayloadDebug] coaching-faqs → $url');
      final res = await _api.dio.get<Map<String, dynamic>>(url);
      ConsoleLog.step('[PayloadDebug] coaching-faqs → ${res.statusCode}');
      final faqs = (res.data?['faqs'] as List<dynamic>?) ?? [];
      final questions = <String>[];
      for (final faq in faqs) {
        if (faq is! Map) continue;
        final q = faq['question'];
        final en = q is Map ? (q['en'] as String?) : null;
        if (en != null && en.isNotEmpty) questions.add(en);
      }
      _cachedFaqs = questions;
      notifyListeners();
    } catch (e) {
      ConsoleLog.warn('[PayloadDebug] coaching-faqs sync failed: $e');
    }
  }

  // ─── Parsing ──────────────────────────────────────────────────────────────

  /// Extracts an ordered module-id list from a `/morning/cards` response body.
  ///
  /// Handles the canonical backend shape `{items: [{module_family_id, module_id, ...}]}`
  /// as well as legacy shapes `{modules|module_ids|priorities: [...]}`.
  @visibleForTesting
  static List<String> parseMorningModuleIds(Map<String, dynamic>? data) {
    if (data == null) return const [];
    // Canonical: { items: [ { module_family_id, module_id, source, ... } ] }
    final items = data['items'];
    if (items is List) {
      final ids = <String>[];
      for (final item in items) {
        if (item is String && item.isNotEmpty) {
          ids.add(item);
        } else if (item is Map) {
          final id = item['module_id'] ??
              item['module_family_id'] ??
              item['id'];
          if (id is String && id.isNotEmpty) ids.add(id);
        }
      }
      if (ids.isNotEmpty) return ids;
    }
    // Legacy fallback shapes.
    final modules =
        data['modules'] ?? data['module_ids'] ?? data['priorities'];
    if (modules is! List) return const [];
    final ids = <String>[];
    for (final item in modules) {
      if (item is String && item.isNotEmpty) {
        ids.add(item);
      } else if (item is Map) {
        final id = item['module_id'] ??
            item['id'] ??
            item['moduleFamilyId'] ??
            item['module_family_id'];
        if (id is String && id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  CoachingModule _rowToModule(Map<String, dynamic> row) {
    final rawJson = row['raw_json'] as String? ?? '{}';
    final raw = jsonDecode(rawJson) as Map<String, dynamic>;
    final passed = (row['passed'] as int?) == 1;
    final quizScore = (row['quiz_score'] as num?)?.toDouble() ?? 0.0;
    // priority_today stores a rank integer (>0 = in today's list).
    final priorityToday = ((row['priority_today'] as int?) ?? 0) > 0;
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
      // Bare ProseMirror doc (legacy unlocalized format).
      blocks = _parseProseMirror(body);
    } else if (body is Map) {
      // Localized body: {'en': <ProseMirror|string>, 'bn': ...}.
      final localized = body['en'] ?? body['bn'];
      if (localized is Map && localized['type'] == 'doc') {
        blocks = _parseProseMirror(localized);
      } else {
        final text = localized is String ? localized : '';
        blocks = text.isNotEmpty
            ? [ContentBlock(type: ContentBlockType.paragraph, text: text)]
            : [];
      }
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
    if (value is! Map) return null;
    final v = value[lang];
    return v is String ? v : null;
  }

  Future<void> _syncKnowledgeDocs() async {
    try {
      final base = AppConfig.coachingServiceUrl;
      final url = '$base${Endpoints.coachingSyncSourceDocuments}';
      ConsoleLog.step('[PayloadDebug] coaching-knowledge → $url');
      final res = await _api.dio.get<Map<String, dynamic>>(url);
      ConsoleLog.step('[PayloadDebug] coaching-knowledge → ${res.statusCode} body=${res.data}');
      final docs =
          (res.data?['source_documents'] as List<dynamic>?) ?? [];
      final parsed = <KnowledgeDocument>[];
      for (final d in docs) {
        if (d is! Map) continue;
        final id = d['source_document_id'] as String? ?? '';
        if (id.isEmpty) continue;
        final filename = d['original_filename'] as String? ?? '';
        final rawTitle = d['title'] as String?;
        final title = (rawTitle != null && rawTitle.isNotEmpty)
            ? rawTitle
            : (filename.isNotEmpty ? filename : id);
        parsed.add(KnowledgeDocument(
          id: id,
          titleEn: title,
          titleBn: title,
          domain: _domainFromFilename(filename),
          docType: _docTypeFromFilename(filename),
          presignedUrl: d['presigned_url'] as String?,
          thumbnailPresignedUrl: d['thumbnail_presigned_url'] as String?,
        ));
      }
      if (parsed.isNotEmpty) {
        _knowledgeDocs = parsed;
      }
      ConsoleLog.step('[PayloadDebug] coaching-knowledge → ${_knowledgeDocs.length} docs');
    } catch (e) {
      ConsoleLog.warn('[PayloadDebug] coaching-knowledge sync failed: $e');
    }
  }

  Future<void> _syncModuleThumbnails(List<dynamic> rawModules) async {
    try {
      final ids = rawModules
          .whereType<Map>()
          .where((m) => m['has_thumbnail'] == true)
          .map((m) => m['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isEmpty) return;
      final base = AppConfig.coachingServiceUrl;
      final url = '$base${Endpoints.coachingModuleThumbnails}';
      ConsoleLog.step('[PayloadDebug] coaching-thumbnails → $url ids=$ids');
      final res = await _api.dio.post<Map<String, dynamic>>(
        url,
        data: {'module_ids': ids},
      );
      ConsoleLog.step('[PayloadDebug] coaching-thumbnails → ${res.statusCode}');
      for (final u in (res.data?['urls'] as List<dynamic>?) ?? []) {
        if (u is! Map) continue;
        final moduleId = u['module_id'] as String? ?? '';
        final presigned = u['presigned_url'] as String? ?? '';
        if (moduleId.isNotEmpty && presigned.isNotEmpty) {
          _moduleThumbnails[moduleId] = presigned;
        }
      }
      ConsoleLog.step(
          '[PayloadDebug] coaching-thumbnails → ${_moduleThumbnails.length} urls');
    } catch (e) {
      ConsoleLog.warn('[PayloadDebug] coaching-thumbnails sync failed: $e');
    }
  }

  CoachingDomain _domainFromFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('anc') || lower.contains('maternal')) {
      return CoachingDomain.anc;
    }
    if (lower.contains('ncd') ||
        lower.contains('hypertension') ||
        lower.contains('diabetes')) {
      return CoachingDomain.ncd;
    }
    if (lower.contains('imci') || lower.contains('child')) {
      return CoachingDomain.imci;
    }
    if (lower.contains('tb') || lower.contains('tuberculosis')) {
      return CoachingDomain.tb;
    }
    if (lower.contains('epi') || lower.contains('vaccine')) {
      return CoachingDomain.epi;
    }
    if (lower.contains('nutrition') || lower.contains('muac')) {
      return CoachingDomain.nutrition;
    }
    return CoachingDomain.anc;
  }

  String _docTypeFromFilename(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'PDF',
      'doc' || 'docx' => 'Word',
      'ppt' || 'pptx' => 'Slides',
      'mp4' || 'mov' || 'avi' => 'Video',
      _ => 'Doc',
    };
  }

  String _lastSyncIso() {
    // TODO: persist last sync timestamp in sync_meta table.
    // For now, use a fixed past date so we always fetch everything.
    return '2020-01-01T00:00:00Z';
  }
}
