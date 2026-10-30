import 'dart:convert';

import '../models/assessment_history_item.dart';
import '../models/json_read.dart';
import '../sync/pregnancy_mah_projection.dart';
import 'app_database.dart';
import 'local_assessment_dao.dart';
import 'local_mah_observations.dart';
import 'member_assessment_history_dao.dart';
import 'member_dao.dart';
import 'pregnancy_detail_rebuilder.dart';

/// Writes [MemberAssessmentHistoryRow] on sync ingest and local visit save.
class MemberAssessmentHistoryWriter {
  MemberAssessmentHistoryWriter({
    required MemberAssessmentHistoryDao mah,
    required MemberDao members,
    required AppDatabase appDb,
    PregnancyMahProjection? pregnancyProjection,
  })  : _mah = mah,
        _members = members,
        _appDb = appDb,
        _pregnancyProjection = pregnancyProjection;

  final MemberAssessmentHistoryDao _mah;
  final MemberDao _members;
  final AppDatabase _appDb;
  final PregnancyMahProjection? _pregnancyProjection;

  /// Clears MAH before a full assessment-history pull (Spice initial sync parity).
  Future<void> clearAllForFullSync() => _mah.deleteAll();

  /// Rebuild MAH from the synced [assessments] cache (same source Spice persists after sync).
  Future<int> rebuildFromAssessmentsTable() async {
    const table = AppDatabase.tableAssessments;
    final rows = await _appDb.db.query(table);
    final items = <AssessmentHistoryItem>[];
    for (final row in rows) {
      final item = _assessmentHistoryItemFromAssessmentRow(row);
      if (item != null) items.add(item);
    }
    await upsertFromHistoryItems(items);
    return items.length;
  }

  /// Merge offline [local_assessments] into MAH so unsynced SK visits count on dashboard.
  Future<int> rebuildFromLocalAssessments() async {
    const table = AppDatabase.tableLocalAssessments;
    final rows = await _appDb.db.query(table);
    for (final row in rows) {
      await upsertFromLocal(
        LocalAssessmentEntity.fromDb(row),
        projectPregnancy: false,
      );
    }
    return rows.length;
  }

  AssessmentHistoryItem? _assessmentHistoryItemFromAssessmentRow(
    Map<String, Object?> row,
  ) =>
      // One home for the column-into-payload folding: the assessment
      // repository reads visit history the same way.
      AssessmentHistoryItem.fromAssessmentRow(row);

  Future<void> upsertFromHistoryItems(List<AssessmentHistoryItem> items) async {
    if (items.isEmpty) return;
    final memberIds = items.map((i) => i.householdMemberId).toSet().toList();
    final memberToLocal = await _resolveLocalMemberIds(memberIds);
    final rows = <MemberAssessmentHistoryRow>[];
    for (final item in items) {
      final row = _fromHistoryItem(
        item,
        memberId: memberToLocal[item.householdMemberId],
      );
      if (row != null) rows.add(row);
    }
    await _mah.upsertMany(rows);
  }

  Future<void> upsertFromLocal(
    LocalAssessmentEntity entity, {
    bool projectPregnancy = true,
  }) async {
    var localMemberId = entity.householdMemberLocalId;
    if (localMemberId <= 0) {
      final m = entity.memberId != null
          ? await _members.getByFhirId(entity.memberId!)
          : null;
      localMemberId = int.tryParse(m?.id ?? '') ?? 0;
    }
    final encounterId = _encounterIdFromOtherDetails(entity.otherDetails);
    if (encounterId == null || encounterId.isEmpty) return;

    Map<String, dynamic> details = {};
    try {
      details = jsonDecode(entity.assessmentDetails) as Map<String, dynamic>;
    } catch (_) {}

    final observations = LocalMahObservations.build(
      entity: entity,
      details: details,
    );
    final visitAt = entity.createdAt ?? entity.updatedAt ?? DateTime.now();
    final visitDate = visitAt.toUtc().toIso8601String();
    final serviceProvided = wireServiceProvided(entity.assessmentType);

    await _mah.upsertMany([
      MemberAssessmentHistoryRow(
        memberId: localMemberId > 0 ? localMemberId : null,
        memberFhirId: entity.memberId,
        visitDate: visitDate,
        serviceProvided: serviceProvided,
        encounterId: encounterId,
        customStatus: entity.customStatus,
        latestVisit: true,
        referralStatus: entity.isReferred
            ? (entity.referralStatus?.trim().isNotEmpty == true
                ? entity.referralStatus
                : 'Referred')
            : entity.referralStatus,
        referralReason: entity.referredReasons,
        practitionerId: null,
        observationsJson:
            observations.isNotEmpty ? jsonEncode(observations) : null,
        shasthyaShebikaId: null,
      ),
    ]);

    if (projectPregnancy &&
        localMemberId > 0 &&
        PregnancyDetailRebuilder.isMotherServiceProvided(serviceProvided)) {
      await _pregnancyProjection?.rebuildMembersAndProject([localMemberId]);
    }
  }

  Future<Map<String, int?>> _resolveLocalMemberIds(List<String> keys) async {
    final resolved = await _members.patientIdsByMemberIds(keys);
    return {
      for (final e in resolved.entries)
        e.key: int.tryParse(e.value),
    };
  }

  MemberAssessmentHistoryRow? _fromHistoryItem(
    AssessmentHistoryItem item, {
    required int? memberId,
  }) {
    if (item.encounterId.isEmpty) return null;
    return MemberAssessmentHistoryRow(
      memberId: memberId,
      memberFhirId: item.householdMemberId,
      visitDate: item.visitDate.toUtc().toIso8601String(),
      serviceProvided: _normalizeServiceProvided(item.serviceProvided),
      encounterId: item.encounterId,
      customStatus: item.customStatus.isEmpty
          ? null
          : jsonEncode(item.customStatus),
      latestVisit: item.isLatestVisit,
      referralStatus: _resolveReferralStatus(item),
      referralReason: item.referralReason,
      nextFollowUpDate: item.nextFollowUpDate?.toUtc().toIso8601String(),
      practitionerId: JsonRead.firstString(
        item.rawJson,
        const ['practitionerId'],
      ),
      observationsJson:
          item.observations != null ? jsonEncode(item.observations) : null,
    );
  }

  static String? _resolveReferralStatus(AssessmentHistoryItem item) {
    final direct = item.referralStatus?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    for (final s in item.customStatus) {
      final t = s.trim();
      if (t == 'Referred' || t.startsWith('Referred To')) return t;
    }
    return JsonRead.firstString(
      item.rawJson,
      const ['referralStatus', 'patientStatus'],
    );
  }

  static String? encounterIdFromOtherDetails(String? otherDetailsJson) =>
      _encounterIdFromOtherDetails(otherDetailsJson);

  static String? _encounterIdFromOtherDetails(String? otherDetailsJson) {
    if (otherDetailsJson == null || otherDetailsJson.isEmpty) return null;
    try {
      final map = jsonDecode(otherDetailsJson) as Map<String, dynamic>;
      final id = map['encounterId']?.toString().trim();
      return (id != null && id.isNotEmpty) ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// Maps Flutter assessment types to Spice `serviceProvided` wire tags.
  static String? _normalizeServiceProvided(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw.trim().replaceAll('-', '_');
    return wireServiceProvided(normalized);
  }

  static String wireServiceProvided(String assessmentType) {
    final key = assessmentType.trim().replaceAll('-', '_');
    switch (key.toUpperCase()) {
      case 'EYECARE':
        return 'eye_care';
      case 'PNC_MOTHER':
      case 'PNC':
        return 'pnc_mother';
      case 'PNC_CHILD':
      case 'PNC_NEONATE':
        return 'pnc_child';
      case 'CHILDHOOD_VISIT':
      case 'CHILD_MENU':
        return 'childhood_visit';
      case 'PREGNANCYOUTCOME':
      case 'PREGNANCY_OUTCOME':
        return 'pregnancyoutcome';
      case 'PWPROFILE':
      case 'PW_PROFILE':
        return 'pwprofile';
      case 'FAMILY_PLANNING':
        return 'family_planning';
      case 'EYE_CARE':
        return 'eye_care';
      default:
        return assessmentType.toLowerCase();
    }
  }
}
