import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Wire-side kind tags for the `follow_ups.kind` column. Centralised so
/// `OfflineSyncService` and `RiskScoringService` agree on the spelling.
abstract final class FollowUpKind {
  FollowUpKind._();

  static const String generic = 'generic';
  static const String ncd = 'ncd';
  static const String screening = 'screening';
  static const String medicalReview = 'medical_review';
  static const String assessment = 'assessment';
  static const String lost = 'lost';
}

/// Sync state of a follow-up row (mirrors Android `OfflineSyncStatus`).
/// `success` = server-authoritative; `notSynced` = a device call attempt is
/// pending push; `inProgress` = pushed, awaiting server confirmation on the
/// next pull; `networkError` = push failed, eligible for retry.
abstract final class FollowUpSyncStatus {
  FollowUpSyncStatus._();

  static const String success = 'Success';
  static const String notSynced = 'NotSynced';
  static const String inProgress = 'InProgress';
  static const String networkError = 'NetworkError';

  /// Rows that must be included in the next push.
  static const List<String> pending = [notSynced, networkError];
}

/// Outcome of a single call attempt (mirrors Android `FollowUpCallStatus` →
/// backend `CallStatus`). The backend enum only knows SUCCESSFUL/UNSUCCESSFUL;
/// a wrong number is an unsuccessful call that also closes the ticket.
abstract final class FollowUpCallStatus {
  FollowUpCallStatus._();

  static const String successful = 'SUCCESSFUL';
  static const String unsuccessful = 'UNSUCCESSFUL';
  static const String wrongNumber = 'WRONG_NUMBER';

  /// Wire value the backend `CallStatus` enum accepts (wrong-number folds to
  /// UNSUCCESSFUL on the wire; the closure is carried by `isCompleted`).
  static String toWire(String status) =>
      status == successful ? successful : unsuccessful;
}

class FollowUpRow {
  const FollowUpRow({
    required this.id,
    required this.patientId,
    required this.kind,
    this.dueAt,
    this.completedAt,
    this.attempts,
    this.unsuccessfulAttempts,
    this.type,
    this.referredSiteId,
    this.isLost = false,
    this.backendId,
    this.syncStatus = FollowUpSyncStatus.success,
    this.updatedAt,
    required this.rawJson,
  });

  final String id;
  final String patientId;
  final String kind;
  final int? dueAt;
  final int? completedAt;
  final int? attempts;

  /// Number of unsuccessful contact attempts (bundle field
  /// `unsuccessfulAttempts`). Drives the `ltfu-streak` OVERDUE-min driver
  /// and the composite-score `min(attempts, 5) × 5` term.
  final int? unsuccessfulAttempts;

  /// Server-side classification (`REFERRED` / `SCREENED` / `LOST_TO_FOLLOW_UP`
  /// / `MEDICAL_REVIEW`). Stored verbatim — orthogonal to [kind] (which is
  /// derived for risk scoring). Drives the LTFU + TB-default-risk drivers.
  final String? type;

  /// Facility ID the patient was referred to (`referredSiteId`). Marks the
  /// patient as ever-referred for the composite-score continuity bonus.
  final String? referredSiteId;

  final bool isLost;

  /// Server-assigned numeric id (`FollowUpDTO.id`). Null for a follow-up the
  /// server has never seen; on the wire this becomes `id` (null → create,
  /// non-null → update).
  final int? backendId;

  /// One of [FollowUpSyncStatus]. Rows in [FollowUpSyncStatus.pending] ride
  /// the next push.
  final String syncStatus;

  /// Epoch ms of the last device edit. Serialized as the numeric `updatedAt`
  /// the backend sorts on.
  final int? updatedAt;

  final String rawJson;

  bool get isCompleted => completedAt != null;

  Map<String, Object?> toDb() => {
        'id': id,
        'patient_id': patientId,
        'kind': kind,
        'due_at': dueAt,
        'completed_at': completedAt,
        'attempts': attempts,
        'unsuccessful_attempts': unsuccessfulAttempts,
        'type': type,
        'referred_site_id': referredSiteId,
        'is_lost': isLost ? 1 : 0,
        'backend_id': backendId,
        'sync_status': syncStatus,
        'updated_at': updatedAt,
        'raw_json': rawJson,
      };

  FollowUpRow copyWith({
    String? patientId,
    int? completedAt,
    int? attempts,
    int? unsuccessfulAttempts,
    bool? isLost,
    String? syncStatus,
    int? updatedAt,
  }) =>
      FollowUpRow(
        id: id,
        patientId: patientId ?? this.patientId,
        kind: kind,
        dueAt: dueAt,
        completedAt: completedAt ?? this.completedAt,
        attempts: attempts ?? this.attempts,
        unsuccessfulAttempts: unsuccessfulAttempts ?? this.unsuccessfulAttempts,
        type: type,
        referredSiteId: referredSiteId,
        isLost: isLost ?? this.isLost,
        backendId: backendId,
        syncStatus: syncStatus ?? this.syncStatus,
        updatedAt: updatedAt ?? this.updatedAt,
        rawJson: rawJson,
      );

  static FollowUpRow fromDb(Map<String, Object?> row) => FollowUpRow(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        kind: row['kind'] as String? ?? FollowUpKind.generic,
        dueAt: row['due_at'] as int?,
        completedAt: row['completed_at'] as int?,
        attempts: row['attempts'] as int?,
        unsuccessfulAttempts: row['unsuccessful_attempts'] as int?,
        type: row['type'] as String?,
        referredSiteId: row['referred_site_id'] as String?,
        isLost: row['is_lost'] == 1,
        backendId: (row['backend_id'] as num?)?.toInt(),
        syncStatus:
            row['sync_status'] as String? ?? FollowUpSyncStatus.success,
        updatedAt: (row['updated_at'] as num?)?.toInt(),
        rawJson: row['raw_json'] as String? ?? '{}',
      );
}

/// A single logged call attempt against a follow-up (mirrors Android
/// `FollowUpCall`). Persisted in `follow_up_calls`; pushed inline as one entry
/// of the parent follow-up's `followUpDetails` array.
class FollowUpCallRow {
  const FollowUpCallRow({
    required this.id,
    required this.followUpId,
    required this.callDate,
    required this.status,
    this.duration,
    this.reason,
    this.otherReason,
    this.patientStatus,
    this.attempts,
    this.latitude,
    this.longitude,
    this.isSynced = false,
    this.rawJson = '{}',
  });

  final String id;
  final String followUpId;
  final int callDate; // epoch ms
  final String status; // FollowUpCallStatus.*
  final double? duration; // minutes
  final String? reason;
  final String? otherReason;
  final String? patientStatus;
  final int? attempts;
  final String? latitude;
  final String? longitude;
  final bool isSynced;
  final String rawJson;

  Map<String, Object?> toDb() => {
        'id': id,
        'follow_up_id': followUpId,
        'call_date': callDate,
        'duration': duration,
        'status': status,
        'reason': reason,
        'other_reason': otherReason,
        'patient_status': patientStatus,
        'attempts': attempts,
        'latitude': latitude,
        'longitude': longitude,
        'is_synced': isSynced ? 1 : 0,
        'raw_json': rawJson,
      };

  /// Serialize into one `followUpDetails[]` entry for the offline-sync push.
  /// Field names match the backend `FollowUpDetailDTO` (no @JsonProperty, so
  /// Java field name == wire name).
  Map<String, Object?> toWire() => {
        'callDate': DateTime.fromMillisecondsSinceEpoch(callDate)
            .toUtc()
            .toIso8601String(),
        'duration': duration,
        'status': FollowUpCallStatus.toWire(status),
        'reason': reason,
        'otherReason': otherReason,
        'patientStatus': patientStatus,
        'attempts': attempts,
        'latitude': latitude,
        'longitude': longitude,
        'isInitiated': true,
      };

  static FollowUpCallRow fromDb(Map<String, Object?> row) => FollowUpCallRow(
        id: row['id'] as String,
        followUpId: row['follow_up_id'] as String,
        callDate: (row['call_date'] as num?)?.toInt() ?? 0,
        status: row['status'] as String? ?? FollowUpCallStatus.unsuccessful,
        duration: (row['duration'] as num?)?.toDouble(),
        reason: row['reason'] as String?,
        otherReason: row['other_reason'] as String?,
        patientStatus: row['patient_status'] as String?,
        attempts: (row['attempts'] as num?)?.toInt(),
        latitude: row['latitude'] as String?,
        longitude: row['longitude'] as String?,
        isSynced: row['is_synced'] == 1,
        rawJson: row['raw_json'] as String? ?? '{}',
      );
}

class FollowUpDao {
  FollowUpDao(this._db);

  final AppDatabase _db;

  Future<void> upsertMany(List<FollowUpRow> rows) async {
    if (rows.isEmpty) return;
    // Protect locally-edited rows: a server pull must never clobber a
    // follow-up whose device call attempt is still pending push (mirrors
    // Android `insertOrUpdateFromBE`). Rows in [FollowUpSyncStatus.pending]
    // are skipped until their push is confirmed.
    final ids = rows.map((r) => r.id).toList();
    final idPlaceholders = List.filled(ids.length, '?').join(',');
    final pendingRows = await _db.db.query(
      AppDatabase.tableFollowUps,
      columns: ['id'],
      where: 'id IN ($idPlaceholders) AND sync_status IN (?, ?)',
      whereArgs: [
        ...ids,
        FollowUpSyncStatus.notSynced,
        FollowUpSyncStatus.networkError,
      ],
    );
    final locked = pendingRows.map((r) => r['id'] as String).toSet();
    final batch = _db.db.batch();
    for (final r in rows) {
      if (locked.contains(r.id)) continue;
      batch.insert(
        AppDatabase.tableFollowUps,
        r.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<FollowUpRow>> forPatient(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tableFollowUps,
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
    return rows.map(FollowUpRow.fromDb).toList(growable: false);
  }

  Future<FollowUpRow?> byId(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tableFollowUps,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FollowUpRow.fromDb(rows.first);
  }

  /// Replace a single follow-up row (used by the call/close lifecycle).
  Future<void> update(FollowUpRow row) async {
    await _db.db.insert(
      AppDatabase.tableFollowUps,
      row.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Call attempts ──────────────────────────────────────────────────────────

  Future<void> insertCall(FollowUpCallRow call) async {
    await _db.db.insert(
      AppDatabase.tableFollowUpCalls,
      call.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<FollowUpCallRow>> callsFor(String followUpId,
      {bool onlyUnsynced = false}) async {
    final rows = await _db.db.query(
      AppDatabase.tableFollowUpCalls,
      where: onlyUnsynced
          ? 'follow_up_id = ? AND is_synced = 0'
          : 'follow_up_id = ?',
      whereArgs: [followUpId],
      orderBy: 'call_date ASC',
    );
    return rows.map(FollowUpCallRow.fromDb).toList(growable: false);
  }

  // ── Push bookkeeping ─────────────────────────────────────────────────────

  /// Follow-ups with a pending device edit that must ride the next push.
  Future<List<FollowUpRow>> pendingPush() async {
    final placeholders =
        List.filled(FollowUpSyncStatus.pending.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableFollowUps,
      where: 'sync_status IN ($placeholders)',
      whereArgs: FollowUpSyncStatus.pending,
    );
    return rows.map(FollowUpRow.fromDb).toList(growable: false);
  }

  Future<int> pendingPushCount() async {
    final placeholders =
        List.filled(FollowUpSyncStatus.pending.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableFollowUps} '
      'WHERE sync_status IN ($placeholders)',
      FollowUpSyncStatus.pending,
    );
    final c = rows.first['c'];
    return c is num ? c.toInt() : 0;
  }

  /// After a successful push: flip the given follow-ups to InProgress and
  /// mark their calls synced, so they are not re-pushed.
  Future<void> markPushed(List<String> followUpIds) async {
    if (followUpIds.isEmpty) return;
    final placeholders = List.filled(followUpIds.length, '?').join(',');
    await _db.db.update(
      AppDatabase.tableFollowUps,
      {'sync_status': FollowUpSyncStatus.inProgress},
      where: 'id IN ($placeholders)',
      whereArgs: followUpIds,
    );
    await _db.db.update(
      AppDatabase.tableFollowUpCalls,
      {'is_synced': 1},
      where: 'follow_up_id IN ($placeholders)',
      whereArgs: followUpIds,
    );
  }

  /// After a failed push: mark the given follow-ups NetworkError so they are
  /// retried on the next connectivity event.
  Future<void> markPushFailed(List<String> followUpIds) async {
    if (followUpIds.isEmpty) return;
    final placeholders = List.filled(followUpIds.length, '?').join(',');
    await _db.db.update(
      AppDatabase.tableFollowUps,
      {'sync_status': FollowUpSyncStatus.networkError},
      where: 'id IN ($placeholders)',
      whereArgs: followUpIds,
    );
  }

  /// Bulk read for the worklist: returns a `patientId → rows` map for the
  /// given patient IDs. Single SQL round-trip.
  Future<Map<String, List<FollowUpRow>>> forMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const <String, List<FollowUpRow>>{};
    final placeholders = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableFollowUps,
      where: 'patient_id IN ($placeholders)',
      whereArgs: patientIds,
    );
    final out = <String, List<FollowUpRow>>{};
    for (final r in rows) {
      final pid = r['patient_id'] as String?;
      if (pid == null) continue;
      (out[pid] ??= <FollowUpRow>[]).add(FollowUpRow.fromDb(r));
    }
    return out;
  }
}
