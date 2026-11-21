import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'member_assessment_history_dao.dart';
import 'member_dao.dart';
import 'pregnancy_detail_rebuilder.dart';

/// Materialized Spice [PregnancyDetail] — rebuilt from MAH for UHIS dashboard SQL parity.
class PregnancyDetailDao {
  PregnancyDetailDao(this._db, this._mah, this._members);

  final AppDatabase _db;
  final MemberAssessmentHistoryDao _mah;
  final MemberDao _members;

  static const String tableName = 'pregnancy_detail';

  /// Rebuilds all mother-side episodes from MAH (batch queries, Spice-shaped).
  Future<void> rebuildAllFromMah() async {
    final memberIds = await _mah.distinctMemberLocalIdsWithMotherHistory();
    if (memberIds.isEmpty) {
      await _db.db.delete(tableName);
      return;
    }
    const chunkSize = 200;
    final allDetails = <PregnancyDetailRow>[];
    for (var i = 0; i < memberIds.length; i += chunkSize) {
      final chunk = memberIds.sublist(
        i,
        i + chunkSize > memberIds.length ? memberIds.length : i + chunkSize,
      );
      final history = await _mah.getByMemberLocalIdsAndServiceTypes(
        chunk,
        PregnancyDetailRebuilder.motherServiceTypes,
      );
      if (history.isEmpty) continue;
      final fhirByLocal = await _members.fhirIdsByLocalIds(chunk);
      final grouped = <int, List<MemberAssessmentHistoryRow>>{};
      for (final row in history) {
        final id = row.memberId;
        if (id == null) continue;
        grouped.putIfAbsent(id, () => []).add(row);
      }
      for (final entry in grouped.entries) {
        allDetails.addAll(
          PregnancyDetailRebuilder.rebuildMotherEpisodes(
            householdMemberLocalId: entry.key,
            householdMemberFhirId: fhirByLocal[entry.key],
            history: entry.value,
          ),
        );
      }
    }
    await _db.db.transaction((tx) async {
      if (allDetails.isEmpty) {
        await tx.delete(tableName);
        return;
      }
      await _upsertAllByEpisodeId(tx, allDetails);
      final kept = allDetails.map((d) => d.pregnancyEpisodeId).toSet();
      final stale = await tx.query(
        tableName,
        columns: ['id', 'pregnancy_episode_id'],
      );
      for (final row in stale) {
        final episodeId = row['pregnancy_episode_id'] as String?;
        if (episodeId == null || kept.contains(episodeId)) continue;
        await tx.delete(
          tableName,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
  }

  Future<void> _upsertAllByEpisodeId(
    DatabaseExecutor tx,
    List<PregnancyDetailRow> details,
  ) async {
    if (details.isEmpty) return;
    final episodeIds =
        details.map((d) => d.pregnancyEpisodeId).toSet().toList();
    final placeholders = List.filled(episodeIds.length, '?').join(',');
    final existingRows = await tx.rawQuery(
      'SELECT * FROM $tableName WHERE pregnancy_episode_id IN ($placeholders)',
      episodeIds,
    );
    final existingByEpisode = {
      for (final r in existingRows)
        r['pregnancy_episode_id'] as String: PregnancyDetailRow.fromDb(r),
    };
    for (final detail in details) {
      final prior = existingByEpisode[detail.pregnancyEpisodeId];
      final row = detail.toDb()..remove('id');
      if (prior?.id != null) {
        row['id'] = prior!.id;
      }
      await tx.insert(
        tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
