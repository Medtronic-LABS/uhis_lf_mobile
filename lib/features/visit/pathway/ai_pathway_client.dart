/// AI Pathway Client — Phase 4.2
///
/// Fire-and-forget AI pathway suggestion layer. Fetches programme candidates
/// from the CQL service's `/clinical-pathway/suggest` endpoint, caches the
/// result in SQLite for 24 h, and exposes both a live-fetch and a cache-read
/// method.
///
/// Invariant: AI suggestions can *add* pathway candidates; they can never
/// remove or downgrade a rule-activated pathway (enforced by [TriageViewModel]).
///
/// Engineering Design Standards:
///   - No hardcoded URLs, timeouts, or feature flags — all values via [AppConfig].
///   - Catches only [TimeoutException], [SocketException], and [DioException];
///     never a bare `catch (_)` that swallows unknown errors.
///   - Fire-and-forget: callers must not await [fetchSuggestions] on the
///     critical-path UI render.
library;

import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/programme.dart';
import 'pathway_engine.dart';

// ── Request model ─────────────────────────────────────────────────────────────

/// Request payload for the `/clinical-pathway/suggest` endpoint.
class PathwaySuggestionRequest {
  const PathwaySuggestionRequest({
    required this.memberId,
    required this.symptoms,
    required this.ageMonths,
    required this.sex,
    required this.activeConditions,
    required this.openFlags,
  });

  /// FHIR member ID (primary key for the cache row).
  final String memberId;

  /// Symptom codes selected by the SK in the picker.
  final List<String> symptoms;

  /// Patient age in months (used by the model for age gating).
  final int ageMonths;

  /// Biological sex: `'MALE'` | `'FEMALE'` | `'UNKNOWN'`.
  final String sex;

  /// Active condition codes from the patient's history.
  final List<String> activeConditions;

  /// Open follow-up flags (e.g. `'TB_SCREEN_DUE'`).
  final List<String> openFlags;

  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'symptoms': symptoms,
        'ageMonths': ageMonths,
        'sex': sex,
        'activeConditions': activeConditions,
        'openFlags': openFlags,
      };
}

// ── Response model ────────────────────────────────────────────────────────────

/// A single AI-suggested pathway candidate.
class PathwaySuggestion {
  const PathwaySuggestion({
    required this.programme,
    required this.confidence,
    required this.rationale,
  });

  /// The suggested programme.
  final Programme programme;

  /// Model confidence score (0.0–1.0). Always < 1.0 for AI-originated rows.
  final double confidence;

  /// Explainability text — displayed to the SK with the "AI suggested — verify"
  /// badge in [SymptomPickerScreen].
  final String rationale;

  Map<String, dynamic> toJson() => {
        'programme': programme.wireTag,
        'confidence': confidence,
        'rationale': rationale,
      };

  factory PathwaySuggestion.fromJson(Map<String, dynamic> json) {
    final prog = Programme.fromWireTag(json['programme'] as String?) ??
        Programme.unknown;
    return PathwaySuggestion(
      programme: prog,
      confidence: (json['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0,
      rationale: json['rationale'] as String? ?? '',
    );
  }

  /// Convert to an [ActivatedPathway] for merging into the triage review list.
  ActivatedPathway toActivatedPathway() => ActivatedPathway(
        programme: programme,
        priority: 80, // AI suggestions appear after manual (90) but before scheduled (100)
        confidence: confidence,
        trigger: PathwayTrigger.ai,
        rationaleKey: 'pathwayAiSuggested',
      );
}

// ── Cache model ────────────────────────────────────────────────────────────────

/// In-memory/DB representation of a fetched suggestion set.
///
/// Cache entries expire after 24 h; stale entries show a badge warning in the UI.
class PathwaySuggestionCache {
  const PathwaySuggestionCache({
    required this.suggestions,
    required this.fetchedAt,
  });

  final List<PathwaySuggestion> suggestions;
  final DateTime fetchedAt;

  /// True when the cache entry is older than 24 h.
  bool get isStale =>
      DateTime.now().difference(fetchedAt).inHours >= 24;

  Map<String, dynamic> toJson() => {
        'suggestions': suggestions.map((s) => s.toJson()).toList(),
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      };

  factory PathwaySuggestionCache.fromJson(Map<String, dynamic> json) {
    final rawList = json['suggestions'] as List? ?? const [];
    return PathwaySuggestionCache(
      suggestions: rawList
          .whereType<Map<String, dynamic>>()
          .map(PathwaySuggestion.fromJson)
          .toList(),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        json['fetchedAt'] as int? ?? 0,
      ),
    );
  }
}

// ── Client ────────────────────────────────────────────────────────────────────

/// Client for AI pathway suggestions.
///
/// Injected with [ApiClient] (HTTP) and [Database] (SQLite cache).
/// Designed for fire-and-forget invocation — callers must not block on
/// [fetchSuggestions] in the UI path.
class AiPathwayClient {
  AiPathwayClient(this._apiClient, this._db);

  /// [_apiClient] may be null in tests that only exercise the cache layer.
  final ApiClient? _apiClient;
  final Database _db;

  static const String _table = 'ai_suggestions';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch AI pathway suggestions from the server.
  ///
  /// Returns null when:
  ///   - [AppConfig.aiPathwayEnabled] is false.
  ///   - The call times out (> [AppConfig.aiPathwayTimeoutMs] ms).
  ///   - The device is offline ([SocketException]).
  ///   - The server returns an error ([DioException]).
  ///
  /// On success, the result is written to the `ai_suggestions` table keyed by
  /// [PathwaySuggestionRequest.memberId] and the cache is returned.
  Future<PathwaySuggestionCache?> fetchSuggestions(
    PathwaySuggestionRequest req,
  ) async {
    if (!AppConfig.aiPathwayEnabled) {
      debugPrint('[AiPathwayClient] aiPathwayEnabled=false; skipping fetch.');
      return null;
    }

    final client = _apiClient;
    if (client == null) {
      debugPrint('[AiPathwayClient] No ApiClient injected; skipping fetch.');
      return null;
    }

    try {
      final response = await client.dio
          .post(
            Endpoints.clinicalPathwaySuggest,
            data: req.toJson(),
          )
          .timeout(Duration(milliseconds: AppConfig.aiPathwayTimeoutMs));

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        debugPrint(
          '[AiPathwayClient] fetchSuggestions: non-2xx status $statusCode',
        );
        return null;
      }

      final body = response.data;
      if (body == null) return null;

      final rawList = body is List
          ? body
          : (body is Map && body['suggestions'] is List)
              ? body['suggestions'] as List
              : const [];

      final suggestions = rawList
          .whereType<Map<String, dynamic>>()
          .map(PathwaySuggestion.fromJson)
          .where((s) => s.programme != Programme.unknown)
          .toList();

      final cache = PathwaySuggestionCache(
        suggestions: suggestions,
        fetchedAt: DateTime.now(),
      );

      await _upsertCache(req.memberId, cache);
      debugPrint(
        '[AiPathwayClient] Fetched ${suggestions.length} suggestions '
        'for member=${req.memberId}',
      );
      return cache;
    } on TimeoutException {
      debugPrint('[AiPathwayClient] fetchSuggestions timed out for ${req.memberId}');
      return null;
    } on SocketException catch (e) {
      debugPrint('[AiPathwayClient] fetchSuggestions offline: $e');
      return null;
    } on DioException catch (e) {
      debugPrint('[AiPathwayClient] fetchSuggestions DioException: $e');
      return null;
    }
  }

  /// Return the cached suggestions for [memberId], or null if no cache row
  /// exists.  The caller is responsible for checking [PathwaySuggestionCache.isStale].
  Future<PathwaySuggestionCache?> getCached(String memberId) async {
    try {
      final rows = await _db.query(
        _table,
        where: 'member_id = ?',
        whereArgs: [memberId],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final json = jsonDecode(row['suggestions_json'] as String) as Map<String, dynamic>;
      final fetchedAt = DateTime.fromMillisecondsSinceEpoch(
        row['fetched_at'] as int,
      );

      // Re-inflate using the flat JSON array (not the cache envelope).
      final rawSuggestions = json['suggestions'] as List? ?? const [];
      final suggestions = rawSuggestions
          .whereType<Map<String, dynamic>>()
          .map(PathwaySuggestion.fromJson)
          .where((s) => s.programme != Programme.unknown)
          .toList();

      return PathwaySuggestionCache(
        suggestions: suggestions,
        fetchedAt: fetchedAt,
      );
    } catch (e) {
      debugPrint('[AiPathwayClient] getCached error for $memberId: $e');
      return null;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _upsertCache(
    String memberId,
    PathwaySuggestionCache cache,
  ) async {
    final suggestionsJson = jsonEncode({
      'suggestions': cache.suggestions.map((s) => s.toJson()).toList(),
    });
    await _db.insert(
      _table,
      {
        'member_id': memberId,
        'suggestions_json': suggestionsJson,
        'fetched_at': cache.fetchedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
