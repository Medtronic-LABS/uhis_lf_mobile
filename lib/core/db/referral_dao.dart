import 'package:sqflite/sqflite.dart';

import '../models/referral.dart';
import '../models/sla.dart';
import 'app_database.dart';

/// DAO for the device-side referral SLA tables (schema v3).
///
/// Mirrors the `FollowUpDao` shape: row-class round-trip, bulk upsert,
/// indexed read methods. The single home for `referrals` /
/// `referral_status_events` / `notification_log` SQL — no inline query lives
/// outside this file.
///
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md`.
class ReferralDao {
  ReferralDao(this._db);

  final AppDatabase _db;

  /// Bulk upsert of referrals. Caller is responsible for being inside a
  /// transaction when persisting alongside other entities.
  Future<void> upsertMany(List<Referral> referrals) async {
    if (referrals.isEmpty) return;
    final batch = _db.db.batch();
    for (final r in referrals) {
      batch.insert(
        AppDatabase.tableReferrals,
        r.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Referral?> byId(String id) async {
    final rows = await _db.db.query(
      AppDatabase.tableReferrals,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Referral.fromDb(rows.first);
  }

  Future<List<Referral>> forPatient(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tableReferrals,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Referral.fromDb).toList(growable: false);
  }

  Future<Map<String, List<Referral>>> forMany(List<String> patientIds) async {
    if (patientIds.isEmpty) return const <String, List<Referral>>{};
    final placeholders = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.query(
      AppDatabase.tableReferrals,
      where: 'patient_id IN ($placeholders)',
      whereArgs: patientIds,
      orderBy: 'patient_id, created_at DESC',
    );
    final out = <String, List<Referral>>{};
    for (final r in rows) {
      final referral = Referral.fromDb(r);
      out.putIfAbsent(referral.patientId, () => <Referral>[]).add(referral);
    }
    return out;
  }

  /// Worklist-equivalent dashboard query — ordered by priority score
  /// (descending), then by earliest breach, then by tier.
  Future<List<Referral>> queryDashboard({
    SlaPriority? levelFilter,
    bool includeClosed = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (levelFilter != null) {
      whereClauses.add('priority_level = ?');
      whereArgs.add(levelFilter.wireTag);
    }
    if (!includeClosed) {
      whereClauses.add("state NOT IN ('closedRecovered','closedDeceased','duplicate')");
    }
    final where = whereClauses.isEmpty ? null : whereClauses.join(' AND ');
    final rows = await _db.db.query(
      AppDatabase.tableReferrals,
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy:
          'priority_score DESC NULLS LAST, breached_since ASC NULLS LAST, sla_tier ASC, created_at ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Referral.fromDb).toList(growable: false);
  }

  Future<int> countByLevel(SlaPriority level) async {
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableReferrals} '
      'WHERE priority_level = ? AND state NOT IN (?, ?, ?)',
      [
        level.wireTag,
        ReferralStatus.closedRecovered.wireTag,
        ReferralStatus.closedDeceased.wireTag,
        ReferralStatus.duplicate.wireTag,
      ],
    );
    final c = rows.first['c'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return 0;
  }

  Future<int> countActive() async {
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableReferrals} '
      'WHERE state NOT IN (?, ?, ?)',
      [
        ReferralStatus.closedRecovered.wireTag,
        ReferralStatus.closedDeceased.wireTag,
        ReferralStatus.duplicate.wireTag,
      ],
    );
    final c = rows.first['c'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return 0;
  }

  Future<List<Referral>> allOpen({int limit = 1000}) async {
    return queryDashboard(includeClosed: false, limit: limit);
  }

  /// Patch only the engine-derived columns. Mirrors `PatientDao.updateRisk()`
  /// so we never accidentally wipe demographics when recomputing the SLA.
  Future<void> updateAssessment({
    required String referralId,
    required int score,
    required String level,
    required String driversJson,
    required String rationaleJson,
    required String state,
    int? breachedSince,
    int? dueArrivalAt,
    int? dueTreatmentAt,
    int escalationLevel = 0,
    int? updatedAt,
    int? closedAt,
  }) async {
    await _db.db.update(
      AppDatabase.tableReferrals,
      {
        'priority_score': score,
        'priority_level': level,
        'priority_drivers': driversJson,
        'rationale_json': rationaleJson,
        'state': state,
        'breached_since': breachedSince,
        'due_arrival_at': dueArrivalAt,
        'due_treatment_at': dueTreatmentAt,
        'escalation_level': escalationLevel,
        'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        'closed_at': ?closedAt,
      },
      where: 'id = ?',
      whereArgs: [referralId],
    );
  }

  // ── Status events (append-only audit log) ────────────────────────────────

  Future<void> appendStatusEvent(ReferralStatusEventRow event) async {
    await _db.db.insert(
      AppDatabase.tableReferralStatusEvents,
      event.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReferralStatusEventRow>> eventsForReferral(
      String referralId) async {
    final rows = await _db.db.query(
      AppDatabase.tableReferralStatusEvents,
      where: 'referral_id = ?',
      whereArgs: [referralId],
      orderBy: 'occurred_at ASC',
    );
    return rows
        .map(ReferralStatusEventRow.fromDb)
        .toList(growable: false);
  }

  // ── Notification log ─────────────────────────────────────────────────────

  Future<void> logNotification(NotificationLogRow row) async {
    await _db.db.insert(
      AppDatabase.tableNotificationLog,
      row.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<NotificationLogRow>> pendingRepeats({int? olderThanMs}) async {
    final ts = olderThanMs ?? DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.db.query(
      AppDatabase.tableNotificationLog,
      where: 'next_repeat_at IS NOT NULL AND next_repeat_at <= ?',
      whereArgs: [ts],
      orderBy: 'next_repeat_at ASC',
    );
    return rows.map(NotificationLogRow.fromDb).toList(growable: false);
  }

  Future<NotificationLogRow?> latestForReferral(
      String referralId, String channel) async {
    final rows = await _db.db.query(
      AppDatabase.tableNotificationLog,
      where: 'referral_id = ? AND channel = ?',
      whereArgs: [referralId, channel],
      orderBy: 'fired_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NotificationLogRow.fromDb(rows.first);
  }
}
