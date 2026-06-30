import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app_database.dart';

/// Cached AI response row. Payload is the raw JSON string returned by the
/// upstream AI service — the caller is responsible for decoding it into the
/// shape that surface expects.
class CachedAiResponse {
  const CachedAiResponse({
    required this.cacheKey,
    required this.kind,
    required this.contentHash,
    required this.payload,
    required this.createdAt,
    required this.expiresAt,
  });

  final String cacheKey;
  final String kind;
  final String contentHash;
  final String payload;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Data-access for [AppDatabase.tableAiResponseCache].
///
/// Generic JSON-blob cache. Each entry is keyed by a caller-controlled
/// `cacheKey` (typically `{kind}:{scopeId}` — e.g. `programme-reco:visit-1234`)
/// plus a `contentHash` the caller bumps when the upstream input changes.
/// The DAO does not interpret either field.
class AiResponseCacheDao {
  AiResponseCacheDao(this._db);

  final AppDatabase _db;

  /// Default TTL applied when [put] is called without an explicit `expiresAt`.
  /// 24 hours covers a single SK shift; longer TTLs need explicit opt-in via
  /// [put(..., ttl: ...)] so we never silently surface day-stale clinical
  /// rationale to the SK.
  static const Duration defaultTtl = Duration(hours: 24);

  /// Look up the cached payload for [cacheKey].
  ///
  /// Returns null when:
  ///   - no row exists for the key,
  ///   - the row's `content_hash` does not match [contentHash], OR
  ///   - the row has expired.
  ///
  /// Expired rows are eagerly deleted on lookup so the cache never grows
  /// unbounded without a separate purge job.
  Future<CachedAiResponse?> get(String cacheKey, {required String contentHash}) async {
    final rows = await _db.db.query(
      AppDatabase.tableAiResponseCache,
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final cached = _fromRow(row);
    if (cached.isExpired || cached.contentHash != contentHash) {
      await _db.db.delete(
        AppDatabase.tableAiResponseCache,
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
      );
      return null;
    }
    return cached;
  }

  /// Insert or overwrite the cache entry for [cacheKey]. [payload] is the
  /// JSON string the caller wants to round-trip.
  Future<void> put({
    required String cacheKey,
    required String kind,
    required String contentHash,
    required String payload,
    Duration? ttl,
  }) async {
    final now = DateTime.now();
    final expires = now.add(ttl ?? defaultTtl);
    await _db.db.insert(
      AppDatabase.tableAiResponseCache,
      {
        'cache_key': cacheKey,
        'kind': kind,
        'content_hash': contentHash,
        'payload': payload,
        'created_at': now.millisecondsSinceEpoch,
        'expires_at': expires.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Invalidate every entry of [kind] for a specific scope (e.g. all
  /// programme-reco entries for a visit). Useful when an upstream event
  /// invalidates the entire kind (logout, sync reset).
  Future<void> invalidateKind(String kind) async {
    await _db.db.delete(
      AppDatabase.tableAiResponseCache,
      where: 'kind = ?',
      whereArgs: [kind],
    );
  }

  /// Purge every expired row. Called opportunistically — not on the SK's hot
  /// path. Safe to schedule on app start or sync completion.
  Future<int> purgeExpired() async {
    return _db.db.delete(
      AppDatabase.tableAiResponseCache,
      where: 'expires_at < ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  CachedAiResponse _fromRow(Map<String, Object?> row) => CachedAiResponse(
        cacheKey: row['cache_key'] as String,
        kind: row['kind'] as String,
        contentHash: row['content_hash'] as String,
        payload: row['payload'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        expiresAt:
            DateTime.fromMillisecondsSinceEpoch(row['expires_at'] as int),
      );
}

