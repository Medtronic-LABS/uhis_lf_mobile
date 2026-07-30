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

  /// From a live [ReferralData] ticket fetched via
  /// `POST /spice-service/patient/referral-tickets`.
  ///
  /// Wire shape (from Spice Android `ReferralData.kt`):
  ///   id, referredBy, phoneNumber, referredTo (site NAME — not id),
  ///   patientStatus, referredReason, dateOfOnset, referredDate,
  ///   referredDates: [{ id, date, type }]
  ///
  /// [patientStatus] after nurse medical review (NurseMedicalReviewActivity):
  ///   "REFERRED"      → ReferralStatus.created     (open, not yet reviewed)
  ///   "Controlled"    → ReferralStatus.closedRecovered  (nurse review: stable)
  ///   "Uncontrolled"  → ReferralStatus.treatmentStarted (nurse review: needs care)
  ///   "REVIEWED"      → ReferralStatus.treatmentStarted (generic reviewed state)
  ///   anything else   → ReferralStatus.fromWireTag (handles legacy 4-state enum)
  ///
  /// Note: [referredTo] is a facility name string, not an integer site id.
  /// We store it as `facilityName` in rawJson — never write to referredSiteId.
  ///
  /// Returns null if [ticket] has no id (malformed) — caller skips the row.
  static Referral? fromReferralTicket(
    Map<String, dynamic> ticket, {
    required String patientId,
    String? householdId,
    String? villageId,
  }) {
    final ticketId = ticket['id']?.toString().trim() ?? '';
    if (ticketId.isEmpty) {
      // DEBUG: malformed ticket — id missing. Log and skip.
      return null;
    }

    final rawStatus = _firstString(ticket, const [
      'patientStatus',
      'referralStatus',
      'status',
    ]);

    // Map nurse-review wire values that fromWireTag doesn't know about.
    final state = _mapPatientStatus(rawStatus);

    final reason = _firstString(ticket, const [
      'referredReason',
      'referralReason',
      'reason',
    ]);

    // referredTo is a site name string from the wire — never a site id.
    final siteName = _firstString(ticket, const [
      'referredTo',
      'referredSiteName',
      'facilityName',
    ]);

    final createdAtMs = _parseDateMs(ticket['referredDate']) ??
        _parseDateMs(ticket['dateOfOnset']) ??
        DateTime.now().millisecondsSinceEpoch;

    return Referral(
      // Stable id — distinct namespace from ref-fu-* and ref-hist-*,
      // so upsertMany is idempotent across repeated fetches.
      id: 'ref-ticket-$ticketId',
      patientId: patientId,
      householdId: householdId,
      villageId: villageId,
      slaTier: SlaTier.inferFromReason(reason),
      diagnosisLabel: reason,
      state: state,
      createdAt: createdAtMs,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      closedAt: state.isClosed ? createdAtMs : null,
      rawJson: jsonEncode({
        ...ticket,
        // Preserve site name under a stable key so Referral.facilityName
        // getter can find it regardless of which field the server used.
        if (siteName != null) 'facilityName': siteName,
        // Explicitly NOT setting referredSiteId — wire gives name, not int id.
        'source': 'referral-ticket',
        // DEBUG: capture the raw patientStatus so logs can trace mapping.
        '__rawPatientStatus': rawStatus,
      }),
    );
  }

  /// Maps nurse medical review wire values to device-side [ReferralStatus].
  ///
  /// The Spice Android `NurseMedicalReviewActivity` sets patientStatus to
  /// "Controlled" or "Uncontrolled" after review — these are not in the
  /// standard 14-state enum so we intercept them here before fromWireTag.
  static ReferralStatus _mapPatientStatus(String? raw) {
    switch ((raw ?? '').trim()) {
      // Nurse review outcomes from NurseMedicalReviewActivity.
      case 'Controlled':
        // Patient stable after review → referral closed (recovered).
        return ReferralStatus.closedRecovered;
      case 'Uncontrolled':
      case 'UN_CONTROLLED':
        // Patient still needs care → treatment is underway.
        // Wire: NurseMedicalReviewActivity sends "UN_CONTROLLED" (confirmed logcat 2026-07-30).
        return ReferralStatus.treatmentStarted;
      case 'REVIEWED':
      case 'Reviewed':
        // Generic reviewed state — treatment in progress.
        return ReferralStatus.treatmentStarted;
      default:
        // Delegate to existing 14-state + legacy 4-state mapping.
        return ReferralStatus.fromWireTag(raw);
    }
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
