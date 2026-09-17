import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../mission/mission_pregnancy_facts.dart';
import '../sync/pregnancy_delivery_sync.dart';
import 'app_database.dart';
import 'pregnancy_snapshot_dao.dart';

/// Assessment types Android links to a pregnancy episode via
/// `pregnancyEpisodeId` (`OfflineSyncRepository.getPregnancyEpisodeId`) —
/// single source of truth for this gate, reused by `AssessmentRepository`,
/// `UnifiedFormNotifier`, and `LocalAssessmentDao` so those call sites can't
/// drift from each other (or from Android) again. Android does NOT link
/// PNC_NEONATE/PNC_CHILD to a pregnancy episode.
const Set<String> kPregnancyEpisodeLinkedTypes = {
  'PWPROFILE', 'PW_PROFILE',
  'PREGNANCY_OUTCOME', 'PREGNANCYOUTCOME',
  'ANC',
  'PNC_MOTHER', 'PNC',
  'CHILDHOOD_VISIT', 'CHILD_MENU',
};

/// One row per pregnancy episode (mirrors Android's `PregnancyDetail` — a
/// fresh row per pregnancy, unlike [PregnancySnapshotRow] which is a
/// single-row-per-patient "current state" projection derived from this).
///
/// Composes a [PregnancySnapshotRow] for all the shared obstetric fields
/// instead of duplicating its field declarations / `toDb` / `fromDb` /
/// `copyWith` / `mergedWith` logic — [obstetric] carries everything except
/// the episode's own identity/lifecycle fields ([id], [startedAt], [closedAt]).
class PregnancyEpisodeRow {
  const PregnancyEpisodeRow({
    required this.id,
    required this.patientId,
    required this.startedAt,
    this.closedAt,
    required this.obstetric,
  });

  /// UUID — this IS `pregnancyEpisodeId` on the wire.
  final String id;
  final String patientId;

  /// Epoch ms, set once when the episode is created.
  final int startedAt;

  /// Epoch ms; null while the pregnancy is still open. Unlike Android's
  /// `PregnancyDetail.endAt` (bumped on every save, used only for sort
  /// order), this is set exactly once, at Pregnancy Outcome — a more
  /// literal episode-lifecycle field than Android's own.
  final int? closedAt;

  /// Shared obstetric fields (facts, LMP/EDD, visit counters, gravida/parity,
  /// …) — same shape as a [PregnancySnapshotRow] row.
  final PregnancySnapshotRow obstetric;

  bool get isOpen => closedAt == null;

  Map<String, Object?> toDb() => {
        ...obstetric.copyWith(patientId: patientId).toDb(),
        'id': id,
        'started_at': startedAt,
        'closed_at': closedAt,
      };

  static PregnancyEpisodeRow fromDb(Map<String, Object?> row) {
    final obstetric = PregnancySnapshotRow.fromDb(row);
    return PregnancyEpisodeRow(
      id: row['id'] as String,
      patientId: obstetric.patientId,
      startedAt: row['started_at'] as int,
      closedAt: row['closed_at'] as int?,
      obstetric: obstetric,
    );
  }

  PregnancyEpisodeRow copyWith({
    int? closedAt,
    PregnancySnapshotRow? obstetric,
  }) =>
      PregnancyEpisodeRow(
        id: id,
        patientId: patientId,
        startedAt: startedAt,
        closedAt: closedAt ?? this.closedAt,
        obstetric: obstetric ?? this.obstetric,
      );
}

/// DAO for the `pregnancy_episodes` table — the authoritative write path for
/// starting, updating, and closing a pregnancy episode. Every write also
/// refreshes [PregnancySnapshotDao]'s single-row-per-patient projection, so
/// the many existing read call sites (`PatientContextBuilder`,
/// `MissionDashboardRepository`, gestational-age card, revisit-interval
/// checks, …) keep working unchanged against that projection.
class PregnancyEpisodeDao {
  PregnancyEpisodeDao(this._db, this._snapshotDao);

  final AppDatabase _db;
  final PregnancySnapshotDao _snapshotDao;

  /// Open episodes for many patients — one query, most recent open per patient.
  Future<Map<String, PregnancyEpisodeRow>> openEpisodesForMany(
    List<String> patientIds,
  ) async {
    if (patientIds.isEmpty) return const {};
    final unique = patientIds.toSet().toList(growable: false);
    final out = <String, PregnancyEpisodeRow>{};
    const chunkSize = 500;
    for (var i = 0; i < unique.length; i += chunkSize) {
      final chunk = unique.sublist(
        i,
        i + chunkSize > unique.length ? unique.length : i + chunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await _db.db.rawQuery(
        'SELECT * FROM ${AppDatabase.tablePregnancyEpisodes} '
        'WHERE closed_at IS NULL AND patient_id IN ($placeholders) '
        'ORDER BY started_at DESC',
        chunk,
      );
      for (final row in rows) {
        final episode = PregnancyEpisodeRow.fromDb(row);
        out.putIfAbsent(episode.patientId, () => episode);
      }
    }
    return out;
  }

  /// Batch sync from coalesced bundle snapshots — one open-episode lookup,
  /// one transaction for writes, one projection batch.
  Future<void> syncCoalescedSnapshots(
    List<PregnancySnapshotRow> coalesced,
  ) async {
    if (coalesced.isEmpty) return;
    final patientIds = coalesced.map((r) => r.patientId).toList(growable: false);
    final openByPatient = await openEpisodesForMany(patientIds);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final projections = <PregnancySnapshotRow>[];

    await _db.db.transaction((tx) async {
      for (final row in coalesced) {
        final open = openByPatient[row.patientId];
        if (open != null) {
          final mergedObstetric = open.obstetric.mergedWith(
            row.copyWith(patientId: row.patientId),
          );
          final updated = open.copyWith(obstetric: mergedObstetric);
          await tx.update(
            AppDatabase.tablePregnancyEpisodes,
            updated.toDb(),
            where: 'id = ?',
            whereArgs: [updated.id],
          );
          projections.add(mergedObstetric.copyWith(patientId: row.patientId));
        } else {
          final episode = PregnancyEpisodeRow(
            id: const Uuid().v4(),
            patientId: row.patientId,
            startedAt: nowMs,
            obstetric: row.copyWith(patientId: row.patientId),
          );
          await tx.insert(AppDatabase.tablePregnancyEpisodes, episode.toDb());
          projections.add(episode.obstetric);
        }
      }
    });

    if (projections.isNotEmpty) {
      await _snapshotDao.upsertMany(projections);
    }
  }

  /// Seeds [lastAncVisitDateMs] on open episodes without regressing newer local
  /// values. Returns the number of episodes updated.
  Future<int> seedLastAncVisitDates(Map<String, int> lastAncVisitMs) async {
    if (lastAncVisitMs.isEmpty) return 0;
    final openByPatient =
        await openEpisodesForMany(lastAncVisitMs.keys.toList(growable: false));
    final toUpdate = <PregnancyEpisodeRow>[];
    final projections = <PregnancySnapshotRow>[];

    for (final entry in lastAncVisitMs.entries) {
      final open = openByPatient[entry.key];
      if (open == null) continue;
      final existingMs = open.obstetric.lastAncVisitDateMs;
      if (existingMs != null && existingMs >= entry.value) continue;
      final mergedObstetric = open.obstetric.copyWith(
        lastAncVisitDateMs: entry.value,
      );
      toUpdate.add(open.copyWith(obstetric: mergedObstetric));
      projections.add(
        mergedObstetric.copyWith(patientId: entry.key),
      );
    }

    if (toUpdate.isEmpty) return 0;

    await _db.db.transaction((tx) async {
      for (final episode in toUpdate) {
        await tx.update(
          AppDatabase.tablePregnancyEpisodes,
          episode.toDb(),
          where: 'id = ?',
          whereArgs: [episode.id],
        );
      }
    });
    await _snapshotDao.upsertMany(projections);
    return toUpdate.length;
  }

  /// The currently open (not yet delivered) episode for this patient, if any.
  Future<PregnancyEpisodeRow?> openEpisodeFor(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tablePregnancyEpisodes,
      where: 'patient_id = ? AND closed_at IS NULL',
      whereArgs: [patientId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PregnancyEpisodeRow.fromDb(rows.first);
  }

  /// The most recent episode for this patient, open or closed.
  Future<PregnancyEpisodeRow?> mostRecentFor(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tablePregnancyEpisodes,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PregnancyEpisodeRow.fromDb(rows.first);
  }

  /// Starts a brand-new episode — mirrors Android's `savePregnancyDetails()`,
  /// which always creates a fresh `PregnancyDetail` row regardless of prior
  /// state. Does not check for an existing open episode first; the caller is
  /// responsible for only calling this when registration is actually allowed.
  Future<PregnancyEpisodeRow> startNewEpisode({
    required String patientId,
    required PregnancySnapshotRow obstetric,
  }) async {
    final episode = PregnancyEpisodeRow(
      id: const Uuid().v4(),
      patientId: patientId,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      obstetric: obstetric.copyWith(patientId: patientId),
    );
    await _db.db.insert(AppDatabase.tablePregnancyEpisodes, episode.toDb());
    await _refreshProjection(episode);
    return episode;
  }

  /// Merges [patch] onto the currently open episode — mirrors Android's
  /// `saveAncPregnancyDetails()`, which fetches and reuses the existing open
  /// row. Falls back to [startNewEpisode] if no open episode exists (e.g. a
  /// data-quality gap / sync hasn't landed yet) so the visit never fails to
  /// attach an episode.
  Future<PregnancyEpisodeRow> updateOpenEpisode({
    required String patientId,
    required PregnancySnapshotRow patch,
  }) async {
    final existing = await openEpisodeFor(patientId);
    if (existing == null) {
      return startNewEpisode(patientId: patientId, obstetric: patch);
    }
    final merged =
        existing.obstetric.mergedWith(patch.copyWith(patientId: patientId));
    final updated = existing.copyWith(obstetric: merged);
    await _db.db.update(
      AppDatabase.tablePregnancyEpisodes,
      updated.toDb(),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    await _refreshProjection(updated);
    return updated;
  }

  /// Closes the currently open episode (Pregnancy Outcome recorded) — sets
  /// [PregnancyEpisodeRow.closedAt] and the delivery date. Falls back to the
  /// most recent episode, then to a fresh one, if somehow none is open —
  /// mirrors the resilience posture of the pre-migration code path.
  Future<PregnancyEpisodeRow> closeEpisode({
    required String patientId,
    required int deliveryDateMillis,
    PregnancyFacts? facts,
    PregnancySnapshotRow? obstetricPatch,
  }) async {
    final existing =
        await openEpisodeFor(patientId) ?? await mostRecentFor(patientId);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final base = existing ??
        PregnancyEpisodeRow(
          id: const Uuid().v4(),
          patientId: patientId,
          startedAt: nowMs,
          obstetric: PregnancySnapshotRow(
            patientId: patientId,
            facts: PregnancyFacts.empty,
          ),
        );
    final patch = obstetricPatch ??
        PregnancySnapshotRow(
          patientId: patientId,
          facts: facts ?? const PregnancyFacts(isPostpartumWindow: true),
        );
    final closed = base.copyWith(
      closedAt: nowMs,
      obstetric: base.obstetric.mergedWith(
        patch.copyWith(
          patientId: patientId,
          deliveryDateMillis: deliveryDateMillis,
          facts: facts ?? patch.facts,
          updatedAt: nowMs,
        ),
      ),
    );
    if (existing == null) {
      await _db.db.insert(AppDatabase.tablePregnancyEpisodes, closed.toDb());
    } else {
      await _db.db.update(
        AppDatabase.tablePregnancyEpisodes,
        closed.toDb(),
        where: 'id = ?',
        whereArgs: [closed.id],
      );
    }
    await _refreshProjection(closed);
    return closed;
  }

  Future<void> _refreshProjection(PregnancyEpisodeRow episode) async {
    await _snapshotDao.upsertOne(
      episode.obstetric.copyWith(patientId: episode.patientId),
    );
  }

  /// Applies one coalesced `pregnancyInfos[]` row from offline sync without
  /// reopening a pregnancy that was already closed locally after PO.
  Future<void> applyIncomingSyncRow({
    required String patientId,
    required PregnancySnapshotRow row,
  }) async {
    final open = await openEpisodeFor(patientId);
    final recent = await mostRecentFor(patientId);
    final recentDelivery = recent?.obstetric.deliveryDateMillis;
    final effectiveDelivery = row.deliveryDateMillis ?? recentDelivery;

    if (effectiveDelivery != null &&
        PregnancyDeliverySync.isWithinPostpartumWindow(effectiveDelivery)) {
      final postpartumFacts = row.facts.isPostpartumWindow
          ? row.facts
          : const PregnancyFacts(isPostpartumWindow: true);

      if (open != null) {
        await closeEpisode(
          patientId: patientId,
          deliveryDateMillis: effectiveDelivery,
          facts: postpartumFacts,
        );
        return;
      }

      if (recent != null && !recent.isOpen) {
        await _upsertClosedEpisodeObstetric(
          recent,
          recent.obstetric.mergedWith(row).copyWith(
                patientId: patientId,
                deliveryDateMillis: effectiveDelivery,
                facts: postpartumFacts,
              ),
        );
        return;
      }

      await closeEpisode(
        patientId: patientId,
        deliveryDateMillis: effectiveDelivery,
        facts: postpartumFacts,
      );
      return;
    }

    if (open != null) {
      await updateOpenEpisode(patientId: patientId, patch: row);
      return;
    }

    if (recent != null &&
        !recent.isOpen &&
        recentDelivery != null &&
        PregnancyDeliverySync.isWithinPostpartumWindow(recentDelivery)) {
      await _upsertClosedEpisodeObstetric(
        recent,
        recent.obstetric.mergedWith(row).copyWith(
              patientId: patientId,
              deliveryDateMillis: recentDelivery,
            ),
      );
      debugPrint(
        '[PregnancyEpisodeDao] sync preserved postpartum closed episode '
        'for $patientId (deliveryMs=$recentDelivery)',
      );
      return;
    }

    await startNewEpisode(patientId: patientId, obstetric: row);
  }

  /// Closes or refreshes postpartum state from a synced/local PO assessment
  /// when `pregnancyInfos[]` has not yet caught up.
  Future<void> applyDeliveryFromAssessmentHistory({
    required String patientId,
    required int deliveryDateMillis,
  }) async {
    if (!PregnancyDeliverySync.isWithinPostpartumWindow(deliveryDateMillis)) {
      return;
    }

    final open = await openEpisodeFor(patientId);
    final recent = await mostRecentFor(patientId);
    final recentDelivery = recent?.obstetric.deliveryDateMillis;

    if (open == null &&
        recent != null &&
        !recent.isOpen &&
        recentDelivery != null &&
        recentDelivery >= deliveryDateMillis) {
      return;
    }

    await closeEpisode(
      patientId: patientId,
      deliveryDateMillis: deliveryDateMillis,
      facts: const PregnancyFacts(isPostpartumWindow: true),
    );
  }

  Future<void> _upsertClosedEpisodeObstetric(
    PregnancyEpisodeRow episode,
    PregnancySnapshotRow mergedObstetric,
  ) async {
    final updated = episode.copyWith(obstetric: mergedObstetric);
    await _db.db.update(
      AppDatabase.tablePregnancyEpisodes,
      updated.toDb(),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    await _refreshProjection(updated);
  }
}
