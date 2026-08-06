import 'package:uuid/uuid.dart';

import '../mission/mission_pregnancy_facts.dart';
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
    final closed = base.copyWith(
      closedAt: nowMs,
      obstetric: base.obstetric.copyWith(
        deliveryDateMillis: deliveryDateMillis,
        facts: facts ?? base.obstetric.facts,
        updatedAt: nowMs,
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
}
