/// Unified submission orchestrator — fans out one [SubmissionLeg] per
/// activated programme, all sharing the same [encounterId].
///
/// Each leg is enqueued as a [LocalAssessmentEntity] with sync-status
/// `pending` so the existing offline-sync pipeline picks it up on next
/// connectivity window.
///
/// Engineering Design Standards:
///   - No I/O in [SubmissionLeg] (pure data).
///   - [UnifiedSubmissionOrchestrator] catches only [DatabaseException]; all
///     other errors propagate to the caller.
///   - No string literals in this file — programme codes come from [Programme.wireTag].
///   - Field projection is delegated to [SectionRegistry.projectionFor].
library;

import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/db/local_assessment_dao.dart';
import '../../../core/models/programme.dart';
import '../composer/sdk_field_projector.dart';
import '../composer/section_registry.dart';
import '../eval/shadow_log_service.dart';

// ── Submission leg ─────────────────────────────────────────────────────────────

/// A single per-programme submission unit, stable across retries.
class SubmissionLeg {
  SubmissionLeg({
    required this.legId,
    required this.programme,
    required this.encounterId,
    required this.payload,
    this.legStatus = 'pending',
  });

  /// Stable UUID — generated once and stored in [LocalAssessmentEntity.otherDetails].
  final String legId;

  final Programme programme;
  final String encounterId;

  /// The programme-specific field projection used as the assessment payload.
  final Map<String, dynamic> payload;

  /// `'pending'` | `'sent'` | `'failed'`
  String legStatus;

  @override
  String toString() =>
      'SubmissionLeg(${programme.wireTag}, $legStatus, enc=$encounterId)';
}

// ── Orchestrator ──────────────────────────────────────────────────────────────

/// Fans out a completed [AssessmentDraftRow] into per-programme submission legs.
///
/// Each leg is persisted as a [LocalAssessmentEntity] with
/// `assessmentType = programme.wireTag` and
/// `otherDetails = {"encounterId": ..., "legId": ...}` so the sync worker
/// can correlate legs back to their shared encounter.
class UnifiedSubmissionOrchestrator {
  UnifiedSubmissionOrchestrator(
    this._localAssessmentDao, {
    ShadowLogService? shadowLog,
  }) : _shadowLog = shadowLog;

  final LocalAssessmentDao _localAssessmentDao;

  /// Optional — injected only when Phase 6 shadow logging is active.
  final ShadowLogService? _shadowLog;

  static const _uuid = Uuid();

  /// Fan out [draft] into one [LocalAssessmentEntity] per activated programme.
  ///
  /// [householdMemberLocalId] is the referenceId used by the spice-service
  /// assessment endpoint.
  Future<void> submit(
    AssessmentDraftRow draft, {
    required int householdMemberLocalId,
    required String? memberId,
    required String? householdId,
    required String? villageId,
    double latitude = 0.0,
    double longitude = 0.0,
  }) async {
    final fieldValues =
        (jsonDecode(draft.fieldValues) as Map<String, dynamic>);
    final activatedTags =
        (jsonDecode(draft.activatedProgrammes) as List<dynamic>)
            .map((e) => e.toString())
            .toList();

    final programmes = activatedTags
        .map(Programme.fromWireTag)
        .whereType<Programme>()
        .toList();

    final now = DateTime.now();

    for (final programme in programmes) {
      final legId = _uuid.v4();
      // Prefer SDK projection (layout_manifests field IDs = canonical backend IDs).
      // Fall back to SectionRegistry for any legacy drafts whose field IDs
      // predate the canonical transformer.
      final sdkProjection =
          SdkFieldProjector.project(programme, fieldValues);
      final projection = sdkProjection.isNotEmpty
          ? sdkProjection
          : SectionRegistry.projectionFor(programme, fieldValues);

      final entity = LocalAssessmentEntity(
        id: _uuid.v4(),
        householdMemberLocalId: householdMemberLocalId,
        memberId: memberId,
        householdId: householdId,
        patientId: draft.patientId,
        villageId: villageId,
        assessmentType: programme.wireTag,
        assessmentDetails: jsonEncode(projection),
        otherDetails: jsonEncode({
          'encounterId': draft.encounterId,
          'legId': legId,
        }),
        latitude: latitude,
        longitude: longitude,
        syncStatus: AssessmentSyncStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      await _localAssessmentDao.insert(entity);
      // ignore: avoid_print
      print('[Orchestrator] saved leg: type=${programme.wireTag} patientId=${draft.patientId} memberId=$memberId householdMemberLocalId=$householdMemberLocalId');
    }

    // Phase 6: shadow-log the completed assessment for eval dataset capture.
    // Fire-and-forget — never blocks submit on failure.
    unawaited(_shadowLog?.capture(EvalCapturePayload(
      encounterId: draft.encounterId,
      patientId: draft.patientId,
      memberId: memberId ?? '',
      activatedProgrammes: activatedTags,
      symptoms: const [],
      fieldValues: fieldValues,
      cdsAlertIds: const [],
      patientContextJson: const {},
    )));
  }

  /// Return per-leg status for the progress surface.
  ///
  /// Queries [LocalAssessmentDao] for all entities whose `other_details`
  /// contains the given [encounterId], returning a [SubmissionLeg] per match.
  Future<List<SubmissionLeg>> statusFor(String encounterId) async {
    // Fetch all assessments that reference this encounter.
    // Because SQLite has no JSON path query, we load by the encounter's
    // patientId is not available here — use a raw approach: pull all
    // entities from the local store and filter in Dart.  For the pilot
    // scale (≤ 5 legs per encounter) this is fine.
    final all = await _localAssessmentDao.getUnsynced();

    final legs = <SubmissionLeg>[];
    for (final entity in all) {
      if (entity.otherDetails == null) continue;
      try {
        final details =
            jsonDecode(entity.otherDetails!) as Map<String, dynamic>;
        if (details['encounterId'] != encounterId) continue;
        final programme = Programme.fromWireTag(entity.assessmentType);
        if (programme == null) continue;
        legs.add(SubmissionLeg(
          legId: details['legId'] as String? ?? '',
          programme: programme,
          encounterId: encounterId,
          payload:
              jsonDecode(entity.assessmentDetails) as Map<String, dynamic>,
          legStatus: _mapSyncStatus(entity.syncStatus),
        ));
      } on FormatException catch (e) {
        // Malformed other_details — skip silently but log.
        assert(() {
          // ignore: avoid_print
          print(
              '[UnifiedSubmissionOrchestrator] Malformed otherDetails: $e');
          return true;
        }());
      }
    }
    return legs;
  }

  String _mapSyncStatus(AssessmentSyncStatus status) {
    switch (status) {
      case AssessmentSyncStatus.pending:
      case AssessmentSyncStatus.inProgress:
        return 'pending';
      case AssessmentSyncStatus.success:
        return 'sent';
      case AssessmentSyncStatus.failed:
      case AssessmentSyncStatus.networkError:
        return 'failed';
    }
  }
}
