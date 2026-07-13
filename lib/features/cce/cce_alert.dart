/// Care Coordination Engine (CCE) — view model + derivation.
///
/// The CCE feature is a **presentation layer** over the existing on-device
/// referral SLA engine (`ReferralRepository` + `SlaEvaluator` +
/// `PriorityScorer`). It re-frames the same `referrals` rows as an
/// action-first "who is slipping between SK and facility" alert list.
///
/// This file is pure Dart — no Flutter, no sqflite — so the derivation stays
/// unit-testable. The mapping from the 14-state [ReferralStatus] lifecycle +
/// SLA bookkeeping onto the 4-step care journey lives here and nowhere else.
///
/// Wireframe: `apon_sushashthya_v13.html` → CCE NOTIFICATION DRAWER.
library;

import 'dart:convert';

import '../../core/models/patient.dart';
import '../../core/models/referral.dart';
import '../../core/models/sla.dart';

/// Severity band that drives card colour, sort order and whether the alert
/// counts toward the "N actions needed" badge.
enum CceSeverity {
  /// SLA window already breached and the referral is still open. Red.
  breached,

  /// Not yet breached but the window closes soon, or a critical case is
  /// waiting. Amber — SK action recommended.
  warning,

  /// Active and on schedule. Neutral — no action needed right now.
  onTrack,

  /// Closed (recovered / discharged / deceased / duplicate). Green — resolved.
  completed;

  /// Whether this severity should surface in the "actions needed" count and
  /// sort ahead of resolved / on-track work.
  bool get needsAction =>
      this == CceSeverity.breached || this == CceSeverity.warning;
}

/// Per-node state in the 4-step care journey strip.
enum CceStepState { done, missed, pending }

/// One node in the referral care journey (SK Visit → Referred → Facility →
/// Treatment).
class CceJourneyStep {
  const CceJourneyStep({
    required this.label,
    required this.sublabel,
    required this.state,
  });

  final String label;
  final String sublabel;
  final CceStepState state;
}

/// A single CCE alert — one open (or recently-closed) referral, enriched with
/// patient identity and reduced to the fields the drawer renders.
class CceAlert {
  const CceAlert({
    required this.referralId,
    required this.patientId,
    required this.patientName,
    required this.severity,
    required this.slaBadge,
    required this.referredMeta,
    required this.statusLine,
    required this.intelTags,
    required this.journey,
    required this.priorityScore,
    this.patientAge,
    this.patientGender,
    this.patientPhone,
    this.villageName,
    this.facilityName,
    this.latitude,
    this.longitude,
    this.landmark,
  });

  final String referralId;
  final String patientId;
  final String patientName;
  final int? patientAge;
  final String? patientGender;
  final String? patientPhone;
  final String? villageName;

  /// Referral target facility name (e.g. "UHC Manikganj"), parsed from the
  /// referral payload when present.
  final String? facilityName;

  /// Patient household location — drives a precise "Locate" when present.
  final double? latitude;
  final double? longitude;
  final String? landmark;
  final CceSeverity severity;

  /// Whether a precise map pin is available (vs. a name-based search).
  bool get hasGeo => latitude != null && longitude != null;

  /// Right-aligned pill text, e.g. "SLA BREACHED +4d" / "SLA: 1d left" /
  /// "Completed".
  final String slaBadge;

  /// Sub-header, e.g. "Referred: 13 May · Severe pneumonia".
  final String referredMeta;

  /// Emphasised status sentence, e.g. "Not arrived · 7 days overdue · SLA was
  /// 3 days".
  final String statusLine;

  /// Short chips surfacing the "why", e.g. ["Not checked in", "Transport
  /// barrier?"].
  final List<String> intelTags;

  /// Four-step care journey for the timeline strip.
  final List<CceJourneyStep> journey;

  /// Priority score carried through for stable secondary sort.
  final int priorityScore;

  bool get hasPhone => patientPhone != null && patientPhone!.trim().isNotEmpty;

  /// Derive a [CceAlert] from a referral row + (optional) cached patient.
  ///
  /// [now] is injected so the same referral yields deterministic output in
  /// tests. All timing text is computed here — the widgets are pure render.
  factory CceAlert.fromReferral(
    Referral r, {
    Patient? patient,
    double? latitude,
    double? longitude,
    String? landmark,
    required DateTime now,
  }) {
    final severity = _severity(r, now);
    final arrived = _arrived(r.state);
    final treated = _treated(r.state);
    final facility = _facilityName(r);

    return CceAlert(
      referralId: r.id,
      patientId: r.patientId,
      patientName: patient?.name?.trim().isNotEmpty == true
          ? patient!.name!.trim()
          : _CceCopy.unknownPatient,
      patientAge: patient?.age,
      patientGender: patient?.gender,
      patientPhone: patient?.phone,
      villageName: patient?.villageName,
      facilityName: facility,
      latitude: latitude,
      longitude: longitude,
      landmark: landmark,
      severity: severity,
      slaBadge: _slaBadge(r, severity, now),
      referredMeta: _referredMeta(r, facility),
      statusLine: _statusLine(r, severity, arrived, treated, now),
      intelTags: _intelTags(r, severity, arrived, treated),
      journey: _journey(r, arrived, treated),
      priorityScore: r.priorityScore ?? 0,
    );
  }

  /// Best-effort facility name from the referral payload. The `Referral`
  /// model carries no dedicated facility field, so we read the original
  /// server/seed JSON, tolerant of the several keys the wire has used.
  static String? _facilityName(Referral r) {
    final raw = r.rawJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      for (final k in const [
        'facilityName',
        'referredTo',
        'referredSiteName',
        'referredSite',
      ]) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    } catch (_) {}
    return null;
  }

  // ── Derivation constants (pilot-grade; clinical lead to tune) ─────────────

  /// How close to the SLA deadline an open referral must be before it flips
  /// from on-track to amber "warning". 24h.
  static const int _warnWindowMs = 24 * 60 * 60 * 1000;

  // ── State helpers ─────────────────────────────────────────────────────────

  static bool _arrived(ReferralStatus s) =>
      s == ReferralStatus.arrived ||
      s == ReferralStatus.treatmentStarted ||
      s == ReferralStatus.closedRecovered ||
      s == ReferralStatus.closedDeceased;

  static bool _treated(ReferralStatus s) =>
      s == ReferralStatus.treatmentStarted ||
      s == ReferralStatus.closedRecovered ||
      s == ReferralStatus.closedDeceased;

  static CceSeverity _severity(Referral r, DateTime now) {
    if (r.state.isClosed) return CceSeverity.completed;
    if (r.breachedSince != null) return CceSeverity.breached;

    // Pick the deadline that matters for the current stage: treatment window
    // once arrived, arrival window before that.
    final due = _arrived(r.state) ? r.dueTreatmentAt : r.dueArrivalAt;
    if (due != null) {
      final remaining = due - now.millisecondsSinceEpoch;
      if (remaining <= _warnWindowMs) return CceSeverity.warning;
    }

    // A critical-band case that is still waiting always warns, even if the
    // clock has room — losing it is the expensive failure.
    if (SlaPriority.fromWireTag(r.priorityLevel) == SlaPriority.critical) {
      return CceSeverity.warning;
    }
    return CceSeverity.onTrack;
  }

  static String _slaBadge(Referral r, CceSeverity severity, DateTime now) {
    switch (severity) {
      case CceSeverity.breached:
        final over = r.dueArrivalAt != null
            ? now.millisecondsSinceEpoch - r.dueArrivalAt!
            : (r.breachedSince != null
                ? now.millisecondsSinceEpoch - r.breachedSince!
                : 0);
        return _CceCopy.breachBadge(_humanizeShort(over));
      case CceSeverity.warning:
        final due = _arrived(r.state) ? r.dueTreatmentAt : r.dueArrivalAt;
        if (due != null) {
          final left = due - now.millisecondsSinceEpoch;
          if (left > 0) return _CceCopy.leftBadge(_humanizeShort(left));
        }
        return _CceCopy.attentionBadge;
      case CceSeverity.onTrack:
        return _CceCopy.onTrackBadge;
      case CceSeverity.completed:
        return _CceCopy.completedBadge;
    }
  }

  static String _referredMeta(Referral r, String? facility) {
    final date = _dateShort(r.createdAt);
    final reason = (r.diagnosisLabel != null && r.diagnosisLabel!.isNotEmpty)
        ? r.diagnosisLabel!
        : _CceCopy.referralReasonFallback;
    return _CceCopy.referredMeta(date, facility, reason);
  }

  static String _statusLine(
    Referral r,
    CceSeverity severity,
    bool arrived,
    bool treated,
    DateTime now,
  ) {
    switch (severity) {
      case CceSeverity.breached:
        if (!arrived) {
          final over = r.dueArrivalAt != null
              ? now.millisecondsSinceEpoch - r.dueArrivalAt!
              : now.millisecondsSinceEpoch - (r.breachedSince ?? r.createdAt);
          return _CceCopy.notArrivedOverdue(
            _humanizeLong(over),
            _slaWindowText(r),
          );
        }
        // Arrived but treatment window breached.
        return _CceCopy.treatmentOverdue(_slaWindowText(r));
      case CceSeverity.warning:
        if (arrived && !treated) {
          final waiting = now.millisecondsSinceEpoch -
              (r.updatedAt);
          return _CceCopy.awaitingReview(_humanizeLong(waiting));
        }
        final due = arrived ? r.dueTreatmentAt : r.dueArrivalAt;
        if (due != null) {
          final left = due - now.millisecondsSinceEpoch;
          if (left > 0) return _CceCopy.dueSoon(_humanizeLong(left));
        }
        return _CceCopy.actionRecommended;
      case CceSeverity.onTrack:
        if (arrived && !treated) return _CceCopy.atFacilityOnTrack;
        return _CceCopy.onTrackLine;
      case CceSeverity.completed:
        final closed = r.closedAt ?? r.updatedAt;
        if (r.state == ReferralStatus.closedDeceased) {
          return _CceCopy.closedDeceased(_dateShort(closed));
        }
        return _CceCopy.dischargedLine(_dateShort(closed));
    }
  }

  static List<String> _intelTags(
    Referral r,
    CceSeverity severity,
    bool arrived,
    bool treated,
  ) {
    final tags = <String>[];
    if (severity == CceSeverity.completed) {
      tags.add(_CceCopy.tagCareComplete);
    } else if (arrived && !treated) {
      tags.add(_CceCopy.tagAtFacility);
    } else if (severity == CceSeverity.breached && !arrived) {
      tags.add(_CceCopy.tagNotCheckedIn);
    }

    // Transport friction is the single most common "not arrived" cause in
    // pilot data — surface it as a prompt the SK can confirm.
    if (r.state == ReferralStatus.transportDeclined ||
        (severity == CceSeverity.breached &&
            r.state == ReferralStatus.inTransit)) {
      tags.add(_CceCopy.tagTransportBarrier);
    }
    if (r.escalationLevel > 0) {
      tags.add(_CceCopy.tagEscalated(r.escalationLevel));
    }
    return tags;
  }

  static List<CceJourneyStep> _journey(
    Referral r,
    bool arrived,
    bool treated,
  ) {
    final createdDate = _dateShort(r.createdAt);
    final notArrivedBreach = r.breachedSince != null && !arrived;

    return <CceJourneyStep>[
      CceJourneyStep(
        label: _CceCopy.stepSkVisit,
        sublabel: createdDate,
        state: CceStepState.done,
      ),
      CceJourneyStep(
        label: _CceCopy.stepReferred,
        sublabel: createdDate,
        state: CceStepState.done,
      ),
      CceJourneyStep(
        label: _CceCopy.stepFacility,
        sublabel: arrived
            ? _CceCopy.stepArrived
            : (notArrivedBreach
                ? _CceCopy.stepNotArrived
                : _CceCopy.stepPending),
        state: arrived
            ? CceStepState.done
            : (notArrivedBreach ? CceStepState.missed : CceStepState.pending),
      ),
      CceJourneyStep(
        label:
            treated ? _CceCopy.stepTreated : _CceCopy.stepTreatment,
        sublabel: r.state == ReferralStatus.closedRecovered
            ? _CceCopy.stepDischarged
            : (treated ? _CceCopy.stepInProgress : _CceCopy.stepPending),
        state: treated ? CceStepState.done : CceStepState.pending,
      ),
    ];
  }

  // ── Formatting helpers ────────────────────────────────────────────────────

  /// SLA window between creation and the arrival deadline, humanised — the
  /// "SLA was 3 days" figure. Falls back to the tier's nominal window.
  static String _slaWindowText(Referral r) {
    if (r.dueArrivalAt != null) {
      return _humanizeLong(r.dueArrivalAt! - r.createdAt);
    }
    switch (r.slaTier) {
      case SlaTier.emergency:
        return _CceCopy.slaEmergencyWindow;
      case SlaTier.urgent:
        return _CceCopy.slaUrgentWindow;
      case SlaTier.routine:
        return _CceCopy.slaRoutineWindow;
    }
  }

  /// Compact duration for badges: "4d", "6h", "45m". Always non-negative.
  static String _humanizeShort(int ms) {
    final v = ms.abs();
    final days = v ~/ (24 * 60 * 60 * 1000);
    if (days >= 1) return '${days}d';
    final hours = v ~/ (60 * 60 * 1000);
    if (hours >= 1) return '${hours}h';
    final mins = v ~/ (60 * 1000);
    return '${mins}m';
  }

  /// Sentence-friendly duration: "7 days", "6 hours", "45 minutes".
  static String _humanizeLong(int ms) {
    final v = ms.abs();
    final days = v ~/ (24 * 60 * 60 * 1000);
    if (days >= 1) return '$days day${days == 1 ? '' : 's'}';
    final hours = v ~/ (60 * 60 * 1000);
    if (hours >= 1) return '$hours hour${hours == 1 ? '' : 's'}';
    final mins = v ~/ (60 * 1000);
    return '$mins minute${mins == 1 ? '' : 's'}';
  }

  static String _dateShort(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

/// Centralised CCE copy. Kept private to this file's derivation; the
/// widget-facing strings live in `CceStrings` (app_strings.dart). This holds
/// only the strings the pure-Dart derivation interpolates, so the model has
/// no dependency on the Flutter strings layer.
abstract final class _CceCopy {
  static const String unknownPatient = 'Patient';
  static const String referralReasonFallback = 'Referral';
  static const String attentionBadge = 'Needs attention';
  static const String onTrackBadge = 'On track';
  static const String completedBadge = 'Completed';

  static const String slaEmergencyWindow = '6 hours';
  static const String slaUrgentWindow = '24 hours';
  static const String slaRoutineWindow = '72 hours';

  static const String stepSkVisit = 'SK Visit';
  static const String stepReferred = 'Referred';
  static const String stepFacility = 'Facility';
  static const String stepArrived = 'Arrived';
  static const String stepNotArrived = 'Not arrived';
  static const String stepPending = 'Pending';
  static const String stepTreatment = 'Treatment';
  static const String stepTreated = 'Treated';
  static const String stepInProgress = 'In progress';
  static const String stepDischarged = 'Discharged';

  static const String tagCareComplete = 'Care completed';
  static const String tagAtFacility = 'At facility';
  static const String tagNotCheckedIn = 'Not checked in';
  static const String tagTransportBarrier = 'Transport barrier?';

  static const String actionRecommended = 'Action recommended';
  static const String atFacilityOnTrack = 'At facility — care in progress';
  static const String onTrackLine = 'On track — no action needed';

  static String breachBadge(String over) => 'SLA BREACHED +$over';
  static String leftBadge(String left) => 'SLA: $left left';
  static String referredMeta(String date, String? facility, String reason) =>
      (facility != null && facility.isNotEmpty)
          ? 'Referred: $date · $facility · $reason'
          : 'Referred: $date · $reason';
  static String notArrivedOverdue(String overdue, String slaWindow) =>
      'Not arrived · $overdue overdue · SLA was $slaWindow';
  static String treatmentOverdue(String slaWindow) =>
      'Treatment overdue · SLA was $slaWindow';
  static String awaitingReview(String waiting) =>
      'Checked in — awaiting review · $waiting waiting';
  static String dueSoon(String left) => 'Due in $left · act soon';
  static String dischargedLine(String date) =>
      'Discharged $date · care complete';
  static String closedDeceased(String date) => 'Closed $date · deceased';
  static String tagEscalated(int level) => 'Escalated L$level';
}
