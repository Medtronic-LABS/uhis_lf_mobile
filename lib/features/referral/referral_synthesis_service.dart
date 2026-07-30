import 'dart:convert';

import '../../core/db/assessment_dao.dart';
import '../../core/db/referral_dao.dart';
import '../../core/debug/console_log.dart';
import '../../core/models/referral.dart';
import 'referral_repository.dart';

/// Background synthesis of referral state from local assessment history.
///
/// The backend never updates `patientStatus` on a referral ticket after a
/// nurse completes a medical review — it stays "Referred". This service
/// bridges that gap by reading assessment rows from the local AssessmentDao
/// (written during offline sync) and deriving state:
///
/// NCD (NCDMEDICALREVIEW / MEDICALREVIEWVISIT):
///   ncdPatientStatus=CONTROLLED   → ReferralStatus.closedRecovered
///   ncdPatientStatus=UN_CONTROLLED → ReferralStatus.treatmentStarted
///
/// ANC / PNC / PW / other (referralStatus field on any assessment row):
///   Recovered   → ReferralStatus.closedRecovered
///   OnTreatment → ReferralStatus.treatmentStarted
///
/// Also patches `facilityName` from the review row into the referral
/// rawJson so the CCE card subtitle shows "{facility} · {diagnosis}".
///
/// Call sites (no patient screen required):
///   - After offline sync completes (sync_progress_screen.dart)
///   - When CceAlertsDrawer opens
class ReferralSynthesisService {
  const ReferralSynthesisService({
    required AssessmentDao assessments,
    required ReferralDao referralDao,
    required ReferralRepository repository,
  })  : _assessments = assessments,
        _dao = referralDao,
        _repo = repository;

  final AssessmentDao _assessments;
  final ReferralDao _dao;
  final ReferralRepository _repo;

  static const _ncdReviewKinds = {'NCDMEDICALREVIEW', 'MEDICALREVIEWVISIT'};

  /// Synthesize state for all open referrals from local assessment DB.
  /// Returns count of referrals updated.
  Future<int> synthesizeAll() async {
    try {
      final open = await _dao.allOpen();
      if (open.isEmpty) return 0;

      final patientIds = open.map((r) => r.patientId).toSet().toList();
      final byPatient = await _assessments.forMany(patientIds);

      const openStates = {ReferralStatus.created, ReferralStatus.inTransit};
      final toUpsert = <Referral>[];

      for (final referral in open) {
        final rows = byPatient[referral.patientId] ?? [];

        // ── Pass 1: NCD — look for nurse medical review with ncdPatientStatus ──
        AssessmentRow? nurseReview;
        String ncdStatus = '';
        for (final row in rows) {
          final kind = (row.kind ?? '').toUpperCase();
          if (!_ncdReviewKinds.contains(kind)) continue;
          final flat = _flatten(row.rawJson);
          final s = (flat['ncdPatientStatus'] as String? ?? '').trim();
          if (s.isEmpty) continue;
          if (nurseReview == null ||
              (row.occurredAt ?? 0) > (nurseReview.occurredAt ?? 0)) {
            nurseReview = row;
            ncdStatus = s;
          }
        }

        ReferralStatus? synthesized;
        String? facility;

        if (nurseReview != null) {
          synthesized = ncdStatus.toUpperCase() == 'CONTROLLED'
              ? ReferralStatus.closedRecovered
              : ReferralStatus.treatmentStarted;
          final nurseFlat = _flatten(nurseReview.rawJson);
          facility = (nurseFlat['facilityName'] as String? ?? '').trim();
          if (facility.isEmpty) facility = null;
        } else {
          // ── Pass 2: ANC / PNC / PW / other — referralStatus on assessment row ──
          AssessmentRow? latestWithStatus;
          String referralStatus = '';
          for (final row in rows) {
            final kind = (row.kind ?? '').toUpperCase();
            if (_ncdReviewKinds.contains(kind)) continue;
            final flat = _flatten(row.rawJson);
            final s = (flat['referralStatus'] as String? ?? '').trim();
            if (s.isEmpty) continue;
            if (latestWithStatus == null ||
                (row.occurredAt ?? 0) > (latestWithStatus.occurredAt ?? 0)) {
              latestWithStatus = row;
              referralStatus = s;
            }
          }
          if (latestWithStatus != null) {
            final upper = referralStatus.toUpperCase();
            if (upper == 'RECOVERED') {
              synthesized = ReferralStatus.closedRecovered;
            } else if (upper == 'ONTREATMENT' || upper == 'ON_TREATMENT') {
              synthesized = ReferralStatus.treatmentStarted;
            }
            if (synthesized != null) {
              final flat = _flatten(latestWithStatus.rawJson);
              final f = (flat['facilityName'] as String? ?? '').trim();
              if (f.isNotEmpty) facility = f;
            }
          }
        }

        if (synthesized == null) continue;

        final patchedRaw = _patchFacility(referral.rawJson, facility ?? '');
        final stateChanged = openStates.contains(referral.state);
        final rawChanged = patchedRaw != referral.rawJson;
        if (!stateChanged && !rawChanged) continue;

        toUpsert.add(referral.copyWith(
          state: stateChanged ? synthesized : null,
          rawJson: patchedRaw,
        ));
      }

      if (toUpsert.isEmpty) return 0;

      await _dao.upsertMany(toUpsert);
      await _repo.recomputeAllAfterSync();

      ConsoleLog.step(
        '[ReferralSynthesis] synthesized ${toUpsert.length} referral(s) from local history',
      );
      return toUpsert.length;
    } catch (e) {
      ConsoleLog.warn('[ReferralSynthesis] failed: $e');
      return 0;
    }
  }

  Map<String, dynamic> _flatten(String rawJsonStr) {
    try {
      final raw = jsonDecode(rawJsonStr) as Map<String, dynamic>;
      final obs = raw['observations'];
      if (obs is Map) {
        return {...raw, ...Map<String, dynamic>.from(obs)};
      }
      return raw;
    } catch (_) {
      return {};
    }
  }

  String? _patchFacility(String? rawJson, String facility) {
    if (facility.isEmpty) return rawJson;
    try {
      final raw = rawJson != null
          ? Map<String, dynamic>.from(jsonDecode(rawJson) as Map)
          : <String, dynamic>{};
      final hasFacility =
          (raw['facilityName'] as String? ?? '').trim().isNotEmpty ||
          (raw['referredTo'] as String? ?? '').trim().isNotEmpty;
      if (hasFacility) return rawJson;
      raw['facilityName'] = facility;
      return jsonEncode(raw);
    } catch (_) {
      return rawJson;
    }
  }
}
