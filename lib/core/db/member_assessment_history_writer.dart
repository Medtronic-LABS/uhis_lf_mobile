import 'dart:convert';

import '../models/assessment_history_item.dart';
import '../models/json_read.dart';
import 'app_database.dart';
import 'local_assessment_dao.dart';
import 'member_assessment_history_dao.dart';
import 'member_dao.dart';

/// Writes [MemberAssessmentHistoryRow] on sync ingest and local visit save.
class MemberAssessmentHistoryWriter {
  MemberAssessmentHistoryWriter({
    required MemberAssessmentHistoryDao mah,
    required MemberDao members,
    required AppDatabase appDb,
  })  : _mah = mah,
        _members = members,
        _appDb = appDb;

  final MemberAssessmentHistoryDao _mah;
  final MemberDao _members;
  final AppDatabase _appDb;

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
      await upsertFromLocal(LocalAssessmentEntity.fromDb(row));
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

  Future<void> upsertFromLocal(LocalAssessmentEntity entity) async {
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

    final observations = _observationsForLocal(entity.assessmentType, details);
    final visitAt = entity.createdAt ?? entity.updatedAt ?? DateTime.now();
    final visitDate = visitAt.toUtc().toIso8601String();

    await _mah.upsertMany([
      MemberAssessmentHistoryRow(
        memberId: localMemberId > 0 ? localMemberId : null,
        memberFhirId: entity.memberId,
        visitDate: visitDate,
        serviceProvided: wireServiceProvided(entity.assessmentType),
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
            observations != null ? jsonEncode(observations) : null,
        shasthyaShebikaId: null,
      ),
    ]);
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

  static Map<String, dynamic>? _observationsForLocal(
    String assessmentType,
    Map<String, dynamic> details,
  ) {
    final upper = assessmentType.toUpperCase();
    if (details.containsKey('observations') &&
        details['observations'] is Map) {
      return Map<String, dynamic>.from(details['observations'] as Map);
    }
    if (upper == 'ANC' && details.containsKey('anc')) {
      final anc = details['anc'];
      if (anc is Map) return Map<String, dynamic>.from(anc);
    }
    return details.isEmpty ? null : details;
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
