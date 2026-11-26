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
import 'sync_meta_dao.dart';

/// Writes [MemberAssessmentHistoryRow] on sync ingest and local visit save.
class MemberAssessmentHistoryWriter {
  MemberAssessmentHistoryWriter({
    required MemberAssessmentHistoryDao mah,
    required MemberDao members,
    required AppDatabase appDb,
    PregnancyMahProjection? pregnancyProjection,
    Future<String?> Function()? currentUserFhirId,
    SyncMetaDao? syncMeta,
  }) : _mah = mah,
       _members = members,
       _appDb = appDb,
       _pregnancyProjection = pregnancyProjection,
       _currentUserFhirId = currentUserFhirId,
       _syncMeta = syncMeta;

  final MemberAssessmentHistoryDao _mah;
  final MemberDao _members;
  final AppDatabase _appDb;
  final PregnancyMahProjection? _pregnancyProjection;

  /// The logged-in SK. Spice stamps it on every visit saved on the device, and
  /// the linked-to-care count only counts NCD visits stamped with this user.
  final Future<String?> Function()? _currentUserFhirId;

  Future<String?> _practitionerId() async {
    final id = (await _currentUserFhirId?.call())?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  /// Bump when the way a synced visit is parsed into a history row changes
  /// (for example a `customStatus` fix). Rows already on the device are then
  /// re-written once from the cached history; see
  /// `SkSpiceDashboardRepository.hydrateMah`.
  static const int normalizeVersion = 1;

  /// Remembers which [normalizeVersion] the rows on this device were written
  /// with. Without it they are never re-written.
  final SyncMetaDao? _syncMeta;

  static const String _normalizeMetaEntity = 'mah_normalize';

  /// True when rows on this device were written by older parse rules.
  Future<bool> needsNormalize() async {
    final meta = _syncMeta;
    if (meta == null) return false;
    final row = await meta.read(_normalizeMetaEntity);
    return row?.cursor != normalizeVersion;
  }

  /// Records that every row now on the device follows the current rules.
  Future<void> markNormalized() async {
    await _syncMeta?.upsert(
      const SyncMetaRow(entity: _normalizeMetaEntity, cursor: normalizeVersion),
    );
  }

  /// Rebuild MAH from the synced [assessments] cache (same source Spice persists after sync).
  ///
  /// [onlyExisting]: re-write only visits already in MAH, so current parse
  /// rules reach old rows without bringing back visits a full sync removed
  /// (the cache is never cleared).
  Future<int> rebuildFromAssessmentsTable({bool onlyExisting = false}) async {
    const table = AppDatabase.tableAssessments;
    final rows = await _appDb.db.query(table);
    final existing = onlyExisting ? await _mah.encounterIds() : null;
    final items = <AssessmentHistoryItem>[];
    for (final row in rows) {
      final item = _assessmentHistoryItemFromAssessmentRow(row);
      if (item == null) continue;
      if (existing != null && !existing.contains(item.encounterId)) continue;
      items.add(item);
    }
    await upsertFromHistoryItems(items);
    return items.length;
  }

  /// Merge offline [local_assessments] into MAH so unsynced SK visits count on dashboard.
  ///
  /// Does not stamp a practitioner: a local assessment does not record who
  /// saved it, and on a shared device the logged-in SK may not be that
  /// person. The stamp written when the visit was saved is kept.
  Future<int> rebuildFromLocalAssessments() async {
    const table = AppDatabase.tableLocalAssessments;
    final rows = await _appDb.db.query(table);
    final visits = <DeviceVisit>[];
    for (final row in rows) {
      final local = await _deviceVisitFor(
        LocalAssessmentEntity.fromDb(row),
        practitionerId: null,
      );
      if (local != null) visits.add(local.visit);
    }
    await _mah.mergeDeviceVisits(visits);
    return rows.length;
  }

  AssessmentHistoryItem? _assessmentHistoryItemFromAssessmentRow(
    Map<String, Object?> row,
  ) =>
      // One home for the column-into-payload folding: the assessment
      // repository reads visit history the same way.
      AssessmentHistoryItem.fromAssessmentRow(row);

  /// [replaceAll]: a full history pull. Rows the server no longer returns are
  /// removed in the same transaction that writes [items]; visits saved on
  /// this device and not yet replaced by a server row are kept.
  Future<void> upsertFromHistoryItems(
    List<AssessmentHistoryItem> items, {
    bool replaceAll = false,
  }) async {
    if (items.isEmpty) return;
    final memberIds = items.map((i) => i.householdMemberId).toSet().toList();
    final memberToLocal = await _resolveLocalMemberIds(memberIds);
    final rows = <MemberAssessmentHistoryRow>[];
    for (final item in items) {
      // Spice drops these before saving synced history.
      if (MemberAssessmentHistoryDao.isMedicalReviewService(
        item.serviceProvided,
      )) {
        continue;
      }
      final row = _fromHistoryItem(
        item,
        memberId: memberToLocal[item.householdMemberId],
      );
      if (row != null) rows.add(row);
    }
    await _mah.upsertMany(
      rows,
      fromServer: true,
      replaceServerRows: replaceAll,
    );
    // Every row was just written by the current parse rules.
    if (replaceAll) await markNormalized();
  }

  Future<void> upsertFromLocal(
    LocalAssessmentEntity entity, {
    bool projectPregnancy = true,
  }) async {
    final local = await _deviceVisitFor(
      entity,
      practitionerId: await _practitionerId(),
    );
    if (local == null) return;
    await _mah.mergeDeviceVisits(
      [local.visit],
      memberId: local.visit.row.memberId,
      memberFhirId: local.visit.row.memberFhirId,
    );
    final service = local.visit.row.serviceProvided;
    if (projectPregnancy &&
        local.localMemberId > 0 &&
        service != null &&
        PregnancyDetailRebuilder.isMotherServiceProvided(service)) {
      await _pregnancyProjection?.rebuildMembersAndProject([
        local.localMemberId,
      ]);
    }
  }

  /// A local assessment as the history row the dashboard counts, or null when
  /// it carries no visit id. [practitionerId] null keeps the stored stamp.
  ///
  /// Once uploaded, the server's copy of the visit (pulled from
  /// member-assessment-history under its own encounter id) is the one the
  /// dashboard counts. `mergeDeviceVisits` drops this device copy then:
  /// keeping both counted every synced visit twice (LEAP-128).
  Future<({DeviceVisit visit, int localMemberId})?> _deviceVisitFor(
    LocalAssessmentEntity entity, {
    required String? practitionerId,
  }) async {
    var localMemberId = entity.householdMemberLocalId;
    if (localMemberId <= 0) {
      final m = entity.memberId != null
          ? await _members.getByFhirId(entity.memberId!)
          : null;
      localMemberId = int.tryParse(m?.id ?? '') ?? 0;
    }
    final encounterId = _encounterIdFromOtherDetails(entity.otherDetails);
    if (encounterId == null || encounterId.isEmpty) return null;

    Map<String, dynamic> details = {};
    try {
      details = jsonDecode(entity.assessmentDetails) as Map<String, dynamic>;
    } catch (_) {}

    final observations = LocalMahObservations.build(
      entity: entity,
      details: details,
    );
    final visitAt = entity.createdAt ?? entity.updatedAt ?? DateTime.now();
    final row = MemberAssessmentHistoryRow(
      memberId: localMemberId > 0 ? localMemberId : null,
      memberFhirId: entity.memberId,
      visitDate: visitAt.toUtc().toIso8601String(),
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
      practitionerId: practitionerId,
      observationsJson: observations.isNotEmpty
          ? jsonEncode(observations)
          : null,
      shasthyaShebikaId: null,
    );
    return (
      visit: (
        row: row,
        serverEncounterId: JsonRead.idOrNull(entity.fhirId),
        uploaded: entity.syncStatus == AssessmentSyncStatus.success,
      ),
      localMemberId: localMemberId,
    );
  }

  Future<Map<String, int?>> _resolveLocalMemberIds(List<String> keys) async {
    final resolved = await _members.patientIdsByMemberIds(keys);
    return {for (final e in resolved.entries) e.key: int.tryParse(e.value)};
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
      practitionerId: JsonRead.firstString(item.rawJson, const [
        'practitionerId',
      ]),
      observationsJson: item.observations != null
          ? jsonEncode(item.observations)
          : null,
    );
  }

  static String? _resolveReferralStatus(AssessmentHistoryItem item) {
    final direct = item.referralStatus?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    for (final s in item.customStatus) {
      final t = s.trim();
      if (t == 'Referred' || t.startsWith('Referred To')) return t;
    }
    return JsonRead.firstString(item.rawJson, const [
      'referralStatus',
      'patientStatus',
    ]);
  }

  static String? encounterIdFromOtherDetails(String? otherDetailsJson) =>
      _encounterIdFromOtherDetails(otherDetailsJson);

  static String? _encounterIdFromOtherDetails(String? otherDetailsJson) =>
      MemberAssessmentHistoryDao.deviceEncounterId(otherDetailsJson);

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
      // The server's spelling: without this its row never matches the
      // device copy and the visit is counted twice.
      case 'FAMILYPLANNING':
        return 'family_planning';
      case 'EYE_CARE':
        return 'eye_care';
      default:
        return assessmentType.toLowerCase();
    }
  }
}
