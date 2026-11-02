import 'package:flutter/foundation.dart';

import '../db/member_dao.dart';
import '../db/pregnancy_detail_dao.dart';
import '../db/pregnancy_detail_rebuilder.dart';
import '../db/pregnancy_episode_dao.dart';
import '../db/pregnancy_snapshot_dao.dart';
import '../mission/mission_pregnancy_facts.dart';
import '../models/json_read.dart';
import '../sync/pregnancy_delivery_sync.dart';

/// Rebuilds Spice-shaped [PregnancyDetailRow] from MAH and projects into
/// [pregnancy_episodes] + [patient_pregnancy_snapshot] (Spice 3+1 parity).
class PregnancyMahProjection {
  PregnancyMahProjection({
    required PregnancyDetailDao pregnancyDetail,
    required PregnancyEpisodeDao pregnancyEpisode,
    required PregnancySnapshotDao pregnancySnapshot,
    required MemberDao members,
  })  : _detail = pregnancyDetail,
        _episode = pregnancyEpisode,
        _snapshot = pregnancySnapshot,
        _members = members;

  final PregnancyDetailDao _detail;
  final PregnancyEpisodeDao _episode;
  final PregnancySnapshotDao _snapshot;
  final MemberDao _members;

  /// Full rebuild after cold sync / MAH replace.
  Future<int> rebuildAllAndProject() async {
    await _detail.rebuildAllFromMah();
    final rows = await _detail.allDetails();
    await _projectRows(rows);
    debugPrint(
      '[PregnancyMahProjection] full rebuild projected ${rows.length} episode row(s)',
    );
    return rows.length;
  }

  /// Incremental rebuild for members touched by assessment-history delta.
  Future<int> rebuildMembersAndProject(List<int> memberLocalIds) async {
    final ids = memberLocalIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) return 0;
    await _detail.rebuildForMemberLocalIds(ids);
    final rows = await _detail.detailsForMemberLocalIds(ids);
    await _projectRows(rows);
    debugPrint(
      '[PregnancyMahProjection] incremental projected ${rows.length} episode row(s) '
      'for ${ids.length} member(s)',
    );
    return rows.length;
  }

  Future<void> _projectRows(List<PregnancyDetailRow> details) async {
    if (details.isEmpty) return;
    final memberLocals =
        details.map((d) => d.householdMemberLocalId).toSet().toList();
    final patientByLocal = await _patientIdsForMembers(memberLocals);
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    final byPatient = <String, List<PregnancyDetailRow>>{};
    for (final d in details) {
      final patientId = patientByLocal[d.householdMemberLocalId];
      if (patientId == null || patientId.isEmpty) continue;
      byPatient.putIfAbsent(patientId, () => []).add(d);
    }

    for (final entry in byPatient.entries) {
      final patientId = entry.key;
      final episodes = entry.value
        ..sort((a, b) => _endAtMs(b).compareTo(_endAtMs(a)));

      await _replaceEpisodesForPatient(patientId, episodes, nowMs, now);

      final current = _pickCurrentEpisode(episodes, now: now);
      if (current != null) {
        final snap = _snapshotFromDetail(patientId, current, now: now);
        await _snapshot.upsertOne(snap);
      }
    }
  }

  Future<void> _replaceEpisodesForPatient(
    String patientId,
    List<PregnancyDetailRow> episodes,
    int nowMs,
    DateTime now,
  ) async {
    await _episode.deleteAllForPatient(patientId);
    for (final d in episodes) {
      final snap = _snapshotFromDetail(patientId, d, now: now);
      final deliveryMs = snap.deliveryDateMillis;
      final startedMs = _startAtMs(d) ?? snap.lmpDate ?? nowMs;
      final int? closedAt;
      if (deliveryMs != null &&
          PregnancyDeliverySync.isWithinPostpartumWindow(deliveryMs, now)) {
        closedAt = deliveryMs;
      } else if (_hasOutcome(d)) {
        closedAt = deliveryMs ?? nowMs;
      } else {
        closedAt = null;
      }

      final row = PregnancyEpisodeRow(
        id: d.pregnancyEpisodeId,
        patientId: patientId,
        startedAt: startedMs,
        closedAt: closedAt,
        obstetric: snap.copyWith(updatedAt: nowMs),
      );
      await _episode.insertEpisodeRow(row);
    }
  }

  static PregnancyDetailRow? _pickCurrentEpisode(
    List<PregnancyDetailRow> episodes, {
    required DateTime now,
  }) {
    if (episodes.isEmpty) return null;
    for (final e in episodes) {
      if (!_hasOutcome(e)) return e;
    }
    for (final e in episodes) {
      final deliveryMs = _deliveryMs(e);
      if (deliveryMs != null &&
          PregnancyDeliverySync.isWithinPostpartumWindow(deliveryMs, now)) {
        return e;
      }
    }
    return episodes.first;
  }

  static bool _hasOutcome(PregnancyDetailRow d) {
    final delivery = d.dateOfDelivery?.trim();
    if (delivery != null && delivery.isNotEmpty) return true;
    final abort = d.typeOfAbortion?.trim();
    return abort != null && abort.isNotEmpty;
  }

  PregnancySnapshotRow _snapshotFromDetail(
    String patientId,
    PregnancyDetailRow d, {
    required DateTime now,
  }) {
    final lmpMs = _isoToMs(d.lastMenstrualPeriod);
    final eddMs = _isoToMs(d.estimatedDeliveryDate);
    final deliveryMs = _deliveryMs(d);
    final facts = _factsFromDetail(d, now: now, deliveryMs: deliveryMs, eddMs: eddMs);
    return PregnancySnapshotRow(
      patientId: patientId,
      facts: facts,
      updatedAt: now.millisecondsSinceEpoch,
      lmpDate: lmpMs,
      eddDate: eddMs,
      deliveryDateMillis: deliveryMs,
      ancVisitNo: d.ancVisitNo,
      gravida: d.gravida,
      parity: d.parity,
      existingIllness: d.pregnantWomanExistingIllness,
    );
  }

  static PregnancyFacts _factsFromDetail(
    PregnancyDetailRow d, {
    required DateTime now,
    int? deliveryMs,
    int? eddMs,
  }) {
    final highRisk = _hasContent(d.highRiskPregnantWoman);
    final gapsAnc = _hasContent(d.gapsInAnc);
    final isPostpartum = deliveryMs != null &&
        PregnancyDeliverySync.isWithinPostpartumWindow(deliveryMs, now);
    final isNearTerm = eddMs != null &&
        _withinDaysFromEpoch(eddMs, 14, now: now, future: true);
    return PregnancyFacts(
      highRiskPregnantWoman: highRisk,
      hasGapsInAnc: gapsAnc,
      isPostpartumWindow: isPostpartum,
      isNearTermAnc: isNearTerm,
      hadDeliveryComplications: false,
      hasPncIllness: false,
    );
  }

  static bool _hasContent(String? value) {
    if (value == null) return false;
    final s = value.trim();
    if (s.isEmpty || s == '[]' || s == '{}') return false;
    return true;
  }

  static bool _withinDaysFromEpoch(
    int epochMs,
    int windowDays, {
    required DateTime now,
    bool future = false,
  }) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final diff = future ? dt.difference(now) : now.difference(dt);
    return diff.inDays >= 0 && diff.inDays <= windowDays;
  }

  static int? _isoToMs(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    return JsonRead.epochMillis({'_': iso}, const ['_']);
  }

  static int? _deliveryMs(PregnancyDetailRow d) => _isoToMs(d.dateOfDelivery);

  static int _endAtMs(PregnancyDetailRow d) =>
      _isoToMs(d.endAt) ?? _isoToMs(d.startAt) ?? 0;

  static int? _startAtMs(PregnancyDetailRow d) => _isoToMs(d.startAt);

  Future<Map<int, String>> _patientIdsForMembers(List<int> memberLocals) async {
    final fhirByLocal = await _members.fhirIdsByLocalIds(memberLocals);
    final out = <int, String>{};
    for (final local in memberLocals) {
      final fhir = fhirByLocal[local];
      if (fhir != null && fhir.isNotEmpty) {
        final mapped = await _members.patientIdsByMemberIds([fhir]);
        final pid = mapped[fhir];
        if (pid != null && pid.isNotEmpty) {
          out[local] = pid;
          continue;
        }
      }
      out[local] = local.toString();
    }
    return out;
  }
}
