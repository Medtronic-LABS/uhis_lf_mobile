import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/endpoints.dart';
import '../../../core/api/frappe_client.dart';
import '../../../core/db/ai_response_cache_dao.dart';
import 'briefing_models.dart';

/// Calls the Frappe `spice_next_ai` app ([Endpoints.visitBriefingGenerate],
/// [Endpoints.visitBriefingSummary]) via [FrappeClient] to generate pre-visit
/// guidance cards. Base URL: `AppConfig.spiceNextAiApiBaseUrl`. Failures throw
/// [FrappeException]; callers fall back to the local rule-based cards.
///
/// Results are cached in SQLite via [AiResponseCacheDao] when available so
/// re-opening the same visit / patient on the same day does not re-hit the
/// API. Cache TTL defaults to 24 hours; content_hash bumps when the input
/// payload changes so a stale entry is never served against a different
/// patient snapshot.
class VisitBriefingRepository {
  const VisitBriefingRepository(this._client, {AiResponseCacheDao? cache})
      : _cache = cache;

  final FrappeClient _client;
  final AiResponseCacheDao? _cache;

  /// Same budget the briefing had on the legacy ai-scribe route.
  static const _timeout = Duration(minutes: 1);

  // Cache namespace — bump when the API response shape changes so rows
  // written by the old client are ignored. Last bump: request payload now
  // sends 'clinicalFindings' (rule-computed) instead of the old ad-hoc
  // 'riskIndicators' list — a breaking change to what the backend prompt
  // produces.
  static const String _kindBriefing = 'visit-briefing.v6';
  static const String _kindSummary = 'patient-summary.v3';

  String _hashOf(Map<String, dynamic> ctx) =>
      jsonEncode(ctx).hashCode.toRadixString(16);

  String _cacheKeyFor(String kind, Map<String, dynamic> ctx) {
    final pid = (ctx['patientId'] as String?)?.trim() ?? 'unknown';
    final lang = (ctx['appLanguage'] as String?)?.trim() ?? 'en';
    return '$kind:$pid:$lang';
  }

  Future<VisitBriefingResponse> generate(Map<String, dynamic> patientContext) async {
    final cacheKey = _cacheKeyFor(_kindBriefing, patientContext);
    final hash = _hashOf(patientContext);

    // Cache hit short-circuits the API call. Mismatched hash → API; the DAO
    // drops the stale row automatically.
    final cache = _cache;
    if (cache != null) {
      final cached = await cache.get(cacheKey, contentHash: hash);
      debugPrint('[BriefingCache] key=$cacheKey hit=${cached != null}');
      if (cached != null) {
        final decoded = jsonDecode(cached.payload) as Map<String, dynamic>;
        return VisitBriefingResponse.fromJson(decoded);
      }
    }

    final raw = await _client.postJson(
      Endpoints.visitBriefingGenerate,
      patientContext,
      receiveTimeout: _timeout,
    );

    if (cache != null) {
      await cache.put(
        cacheKey: cacheKey,
        kind: _kindBriefing,
        contentHash: hash,
        payload: jsonEncode(raw),
      );
    }
    return VisitBriefingResponse.fromJson(raw);
  }

  /// Short 2-3 sentence summary for the patient context screen header.
  Future<String> summary(Map<String, dynamic> patientContext) async {
    final cacheKey = _cacheKeyFor(_kindSummary, patientContext);
    final hash = _hashOf(patientContext);

    final cache = _cache;
    if (cache != null) {
      final cached = await cache.get(cacheKey, contentHash: hash);
      if (cached != null) {
        final decoded = jsonDecode(cached.payload) as Map<String, dynamic>;
        return (decoded['summary'] as String?) ?? '';
      }
    }

    final raw = await _client.postJson(
      Endpoints.visitBriefingSummary,
      patientContext,
      receiveTimeout: _timeout,
    );

    if (cache != null) {
      await cache.put(
        cacheKey: cacheKey,
        kind: _kindSummary,
        contentHash: hash,
        payload: jsonEncode(raw),
      );
    }
    return (raw['summary'] as String?) ?? '';
  }
}
