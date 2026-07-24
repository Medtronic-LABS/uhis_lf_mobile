/// Maps sync / assessment referral signals into device [Referral] rows for CCE.
///
/// Pure Dart — no Flutter / DAO deps. Callers persist via [ReferralDao.upsertMany]
/// then run [ReferralRepository.recomputeAllAfterSync] so SLA + priority columns
/// are filled.
library;

import 'dart:convert';

import '../db/follow_up_dao.dart';
import '../models/assessment_history_item.dart';
import '../models/referral.dart';

/// Builds [Referral] rows from follow-ups, assessment history, and local
/// referred assessments. Deterministic ids make re-sync / re-submit idempotent.
class ReferralIngestMapper {
  const ReferralIngestMapper._();

  /// From a synced [FollowUpRow] when the row signals an open referral
  /// (`type == REFERRED`, `referredSiteId`, or open `referralStatus` in raw).
  static Referral? fromFollowUp(
    FollowUpRow row, {
    String? householdId,
    String? villageId,
  }) {
    final raw = _decodeMap(row.rawJson);
    final status = _firstString(raw, const [
      'referralStatus',
      'patientStatus',
    ]);
    if (_isClosedStatus(status)) return null;

    final isReferredType = (row.type ?? '').toUpperCase() == 'REFERRED';
    final hasSite =
        row.referredSiteId != null && row.referredSiteId!.trim().isNotEmpty;
    final openStatus = _isOpenStatus(status);
    if (!isReferredType && !hasSite && !openStatus) return null;

    final reason = _firstString(raw, const [
      'referralReason',
      'referredReason',
      'referredReasons',
      'reason',
    ]);
    final facility = _firstString(raw, const [
      'referredSiteName',
      'referredTo',
      'facilityName',
      'referredSite',
    ]) ??
        row.referredSiteId;
    final createdAt = row.dueAt ??
        _parseDateMs(raw['referredDate']) ??
        row.updatedAt ??
        DateTime.now().millisecondsSinceEpoch;
    final state = status != null
        ? ReferralStatus.fromWireTag(status)
        : ReferralStatus.created;

    return Referral(
      id: 'ref-fu-${row.id}',
      patientId: row.patientId,
      householdId: householdId,
      villageId: villageId,
      slaTier: SlaTier.inferFromReason(reason),
      diagnosisLabel: reason,
      state: state,
      createdAt: createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      closedAt: state.isClosed ? createdAt : null,
      rawJson: jsonEncode({
        ...raw,
        'facilityName': ?facility,
        'referredSiteId': ?row.referredSiteId,
        'source': 'follow-up',
      }),
    );
  }

  /// From member-assessment-history when the visit is still an open referral.
  static Referral? fromAssessmentHistory(
    AssessmentHistoryItem item, {
    required String patientId,
    String? householdId,
    String? villageId,
  }) {
    final status = item.referralStatus ??
        _statusFromCustom(item.customStatus) ??
        _firstString(item.rawJson, const ['patientStatus', 'referralStatus']);
    if (!_isOpenStatus(status) &&
        !_customHasOpenReferral(item.customStatus)) {
      return null;
    }

    final reason = item.referralReason ??
        _firstString(item.rawJson, const [
          'referralReason',
          'referredReason',
          'referredReasons',
        ]);
    final createdAt = item.visitDate.millisecondsSinceEpoch;
    final resolvedStatus = status ?? 'Referred';
    final state = ReferralStatus.fromWireTag(resolvedStatus);

    return Referral(
      id: 'ref-hist-${item.encounterId}',
      patientId: patientId,
      householdId: householdId,
      villageId: villageId,
      slaTier: SlaTier.inferFromReason(reason),
      diagnosisLabel: reason,
      diagnosisCode: item.serviceProvided,
      state: state.isClosed ? ReferralStatus.created : state,
      createdAt: createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      rawJson: jsonEncode({
        ...item.rawJson,
        'source': 'assessment-history',
        'referredReason': ?reason,
        'patientStatus': resolvedStatus,
      }),
    );
  }

  /// Stable local referral for a just-submitted referred assessment.
  static Referral fromLocalAssessment({
    required String assessmentId,
    required String patientId,
    List<String> reasons = const [],
    String? facilityName,
    String? householdId,
    String? villageId,
    String? diagnosisCode,
    DateTime? now,
  }) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final label = reasons.where((r) => r.trim().isNotEmpty).join(', ');
    return Referral.draft(
      id: 'ref-assess-$assessmentId',
      patientId: patientId,
      slaTier: SlaTier.inferFromReason(label.isEmpty ? null : label),
      householdId: householdId,
      villageId: villageId,
      diagnosisCode: diagnosisCode,
      diagnosisLabel: label.isEmpty ? null : label,
      facilityName: facilityName,
      now: now ?? DateTime.fromMillisecondsSinceEpoch(ts),
    );
  }

  static bool _isOpenStatus(String? status) {
    if (status == null || status.trim().isEmpty) return false;
    final state = ReferralStatus.fromWireTag(status);
    return !state.isClosed;
  }

  static bool _isClosedStatus(String? status) {
    if (status == null || status.trim().isEmpty) return false;
    return ReferralStatus.fromWireTag(status).isClosed;
  }

  static bool _customHasOpenReferral(List<String> custom) {
    for (final s in custom) {
      final t = s.trim();
      if (t == 'Referred' || t == 'OnTreatment') return true;
    }
    return false;
  }

  static String? _statusFromCustom(List<String> custom) {
    for (final s in custom) {
      final t = s.trim();
      if (t == 'Referred' || t == 'OnTreatment') return t;
    }
    return null;
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Malformed raw — treat as empty; caller still has column fields.
    }
    return const {};
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return null;
  }

  static int? _parseDateMs(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt;
    return DateTime.tryParse(s)?.millisecondsSinceEpoch;
  }
}
