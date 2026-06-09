import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/db/follow_up_dao.dart';
import '../../../core/models/programme.dart';
import 'pathway_review_sheet.dart';

/// Follow-up reason for deferred screening.
///
/// Used when a rule-activated pathway is skipped by the SK.
abstract final class DeferredScreeningReason {
  DeferredScreeningReason._();

  static const String deferredScreening = 'DEFERRED_SCREENING';
  static const String skippedIccm = 'SKIPPED_ICCM';
  static const String skippedAnc = 'SKIPPED_ANC';
  static const String skippedPnc = 'SKIPPED_PNC';
  static const String skippedNcd = 'SKIPPED_NCD';
  static const String skippedTb = 'SKIPPED_TB';

  static String forProgramme(Programme programme) {
    switch (programme) {
      case Programme.imci:
        return skippedIccm;
      case Programme.anc:
        return skippedAnc;
      case Programme.pnc:
        return skippedPnc;
      case Programme.ncd:
        return skippedNcd;
      case Programme.tb:
        return skippedTb;
      case Programme.unknown:
        return deferredScreening;
    }
  }
}

/// Protocol intervals for deferred screening follow-ups (days).
abstract final class DeferredScreeningInterval {
  DeferredScreeningInterval._();

  /// Default interval for most programmes.
  static const int defaultDays = 7;

  /// ICCM/child health — sooner follow-up.
  static const int iccmDays = 3;

  /// ANC — next routine visit.
  static const int ancDays = 14;

  /// NCD — standard follow-up.
  static const int ncdDays = 14;

  /// TB — urgent screening.
  static const int tbDays = 7;

  static int forProgramme(Programme programme) {
    switch (programme) {
      case Programme.imci:
        return iccmDays;
      case Programme.anc:
        return ancDays;
      case Programme.pnc:
        return ancDays;
      case Programme.ncd:
        return ncdDays;
      case Programme.tb:
        return tbDays;
      case Programme.unknown:
        return defaultDays;
    }
  }
}

/// Service for creating follow-ups when pathways are skipped.
///
/// When a rule-activated pathway is skipped, this service:
/// 1. Creates a deferred-screening follow-up locally
/// 2. Queues it for sync to the server
///
/// This ensures the pathway surfaces in the next visit.
class SkippedPathwayFollowUpService {
  SkippedPathwayFollowUpService({
    required ApiClient api,
    FollowUpDao? followUpDao,
  })  : _api = api,
        _followUpDao = followUpDao;

  final ApiClient _api;
  final FollowUpDao? _followUpDao;

  /// Create follow-ups for skipped pathways.
  ///
  /// Returns the number of follow-ups created.
  Future<int> createFollowUps({
    required String patientId,
    required String? memberId,
    required String encounterId,
    required List<SkippedPathway> skippedPathways,
  }) async {
    if (skippedPathways.isEmpty) return 0;

    var created = 0;

    for (final skipped in skippedPathways) {
      try {
        await _createFollowUp(
          patientId: patientId,
          memberId: memberId,
          encounterId: encounterId,
          skipped: skipped,
        );
        created++;
      } catch (e) {
        debugPrint('Failed to create follow-up for ${skipped.programme}: $e');
        // Continue with other follow-ups
      }
    }

    return created;
  }

  Future<void> _createFollowUp({
    required String patientId,
    required String? memberId,
    required String encounterId,
    required SkippedPathway skipped,
  }) async {
    final reason = DeferredScreeningReason.forProgramme(skipped.programme);
    final intervalDays = DeferredScreeningInterval.forProgramme(skipped.programme);
    final nextVisitDate = DateTime.now().add(Duration(days: intervalDays));

    // Build follow-up DTO
    final followUpDto = {
      'patientId': patientId,
      'memberId': memberId,
      'encounterId': encounterId,
      'reason': reason,
      'type': 'DEFERRED_SCREENING',
      'encounterType': skipped.programme.wireTag,
      'nextVisitDate': nextVisitDate.toIso8601String().split('T').first,
      'rationaleKey': skipped.rationaleKey,
      'triggerType': skipped.trigger.name,
      'createdAt': skipped.timestamp.toIso8601String(),
    };

    // Try to sync immediately
    try {
      await _api.dio.post<Map<String, dynamic>>(
        Endpoints.followUpCreate,
        data: followUpDto,
      );
    } catch (e) {
      // Queue for offline sync
      debugPrint('Follow-up sync failed, queuing for offline: $e');
      await _queueForOfflineSync(
        patientId: patientId,
        reason: reason,
        nextVisitDate: nextVisitDate,
        rawJson: followUpDto,
      );
    }
  }

  Future<void> _queueForOfflineSync({
    required String patientId,
    required String reason,
    required DateTime nextVisitDate,
    required Map<String, dynamic> rawJson,
  }) async {
    if (_followUpDao == null) {
      debugPrint('FollowUpDao not available for offline queue');
      return;
    }

    final followUpDao = _followUpDao;

    final row = FollowUpRow(
      id: const Uuid().v4(),
      patientId: patientId,
      kind: FollowUpKind.screening,
      dueAt: nextVisitDate.millisecondsSinceEpoch,
      completedAt: null,
      attempts: 0,
      unsuccessfulAttempts: 0,
      type: 'DEFERRED_SCREENING',
      referredSiteId: null,
      isLost: false,
      rawJson: rawJson.toString(),
    );

    await followUpDao.upsertMany([row]);
  }
}
