import 'programme.dart';

/// Structured rationale payload for AI explainability (architecture.md §3.4).
///
/// Every AI output carries this shape so the SK can understand *why* a patient
/// scored high. The `drivers` list contains machine-readable tags (e.g.
/// 'under-5', 'missed-visits:3') which the UI localises into human-readable
/// `reasons` via [formattedReasons].
class RiskRationale {
  const RiskRationale({
    required this.drivers,
    required this.modelVersion,
    required this.computedAt,
    this.confidence,
    this.humanReviewRequired = false,
    this.guidelineIds = const <String>[],
    this.sourceObservationIds = const <String>[],
  });

  /// Machine-readable risk drivers, e.g. ['under-5', 'pregnancy', 'missed-visits:3'].
  /// The structured source of truth; UI derives display text from these.
  final List<String> drivers;

  /// Model or rule-engine version, e.g. 'on-device-rule-v1'.
  final String modelVersion;

  /// When this score was computed.
  final DateTime computedAt;

  /// Null for rule-based scoring; populated when ML model lands.
  final double? confidence;

  /// True when band == urgent; prompts the SK to review immediately.
  final bool humanReviewRequired;

  /// Future: WHO PEN, IMCI guideline codes that triggered this score.
  final List<String> guidelineIds;

  /// FHIR Observation IDs that fed this assessment (for audit trail).
  final List<String> sourceObservationIds;

  /// Convert structured drivers to user-facing reasons.
  /// Localisation seam: when multi-language lands, this method reads from
  /// a locale-aware formatter.
  List<String> get formattedReasons {
    return drivers.map(_formatDriver).toList(growable: false);
  }

  static String _formatDriver(String driver) {
    // Parse structured drivers into human-readable text.
    // Format: 'key' or 'key:value'
    final parts = driver.split(':');
    final key = parts[0];
    final value = parts.length > 1 ? parts[1] : null;

    switch (key) {
      case 'under-5':
        return value != null ? 'Under-5 child (age $value)' : 'Under-5 child';
      case 'senior':
        return value != null ? 'Senior (age $value)' : 'Senior';
      case 'pregnancy':
        return 'Pregnancy / ANC enrolled';
      case 'ncd':
        return 'NCD enrolment';
      case 'tb':
        return 'TB enrolment';
      case 'imci':
        return 'IMCI eligibility';
      case 'missed-visits':
        return '$value missed visit(s) in last 90 days';
      case 'lost-to-follow-up':
        return 'Lost to follow-up';
      case 'server-risk-red':
        return 'Server risk flag: red';
      case 'server-risk-yellow':
        return 'Server risk flag: yellow';
      case 'server-risk-high':
        return 'Server risk level: HIGH';
      case 'clinician-red-flag':
        return 'Patient flagged red by clinician';
      case 'no-programme':
        return 'No programme enrolment recorded';
      default:
        return driver; // Fallback: return raw driver
    }
  }

  Map<String, dynamic> toJson() => {
        'drivers': drivers,
        'modelVersion': modelVersion,
        'computedAt': computedAt.toIso8601String(),
        if (confidence != null) 'confidence': confidence,
        'humanReviewRequired': humanReviewRequired,
        'guidelineIds': guidelineIds,
        'sourceObservationIds': sourceObservationIds,
      };

  factory RiskRationale.fromJson(Map<String, dynamic> json) => RiskRationale(
        drivers: (json['drivers'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[],
        modelVersion: json['modelVersion'] as String? ?? 'unknown',
        computedAt: json['computedAt'] != null
            ? DateTime.parse(json['computedAt'] as String)
            : DateTime.now(),
        confidence: (json['confidence'] as num?)?.toDouble(),
        humanReviewRequired: json['humanReviewRequired'] as bool? ?? false,
        guidelineIds: (json['guidelineIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[],
        sourceObservationIds: (json['sourceObservationIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[],
      );
}

/// Severity band derived from the normalised 0–100 risk score.
///
/// Bands are an enum (not free strings) so list ordering, color mapping, and
/// chip filtering can be exhaustive — `switch` on this enum becomes a
/// compile-time gate when a new band is added.
enum RiskBand {
  urgent,
  high,
  moderate,
  low;

  String get wireTag {
    switch (this) {
      case RiskBand.urgent:
        return 'urgent';
      case RiskBand.high:
        return 'high';
      case RiskBand.moderate:
        return 'moderate';
      case RiskBand.low:
        return 'low';
    }
  }

  static RiskBand fromWireTag(String? tag) {
    switch ((tag ?? '').toLowerCase()) {
      case 'urgent':
        return RiskBand.urgent;
      case 'high':
        return RiskBand.high;
      case 'moderate':
        return RiskBand.moderate;
      default:
        return RiskBand.low;
    }
  }
}

/// Inputs to [RiskScoringService.score]. Built by the worklist repository as a
/// single join over the cached SQLite rows — never assembled from a network
/// call directly (offline-first tenet).
class PatientFacts {
  const PatientFacts({
    required this.patientId,
    this.ageYears,
    this.programmes = const <Programme>{},
    this.missedVisitsLast90d = 0,
    this.daysSinceLastVisit,
    this.nextDueAt,
    this.lostToFollowUp = false,
    this.redFlag = false,
    this.serverRiskLevel,
    this.serverRiskColor,
    this.diagnosisCount = 0,
  });

  final String patientId;
  final int? ageYears;
  final Set<Programme> programmes;
  final int missedVisitsLast90d;
  final int? daysSinceLastVisit;
  final DateTime? nextDueAt;
  final bool lostToFollowUp;
  final bool redFlag;

  /// Server-side hint from `PatientDetailsDTO.riskLevel` (`HIGH|MEDIUM|LOW`).
  /// Treated as a *signal*, never the final score.
  final String? serverRiskLevel;

  /// Server-side hint from `PatientDetailsDTO.riskColorCode` (`RED|YELLOW|GREEN`).
  final String? serverRiskColor;

  /// Number of recorded diagnoses on the patient (used as a tie-breaker).
  final int diagnosisCount;
}

/// The risk-engine output. Persisted into the `patients` row so the worklist
/// query is a simple `ORDER BY risk_score DESC`.
class RiskAssessment {
  const RiskAssessment({
    required this.score,
    required this.band,
    required this.programmes,
    required this.reasons,
    this.rationale,
  });

  /// 0–100 normalised.
  final int score;
  final RiskBand band;
  final Set<Programme> programmes;

  /// Short human-readable rationale lines (Leapfrog Tenet 6: Explainable).
  /// Derived from [rationale.drivers] when structured rationale is available;
  /// persisted as a JSON array in `patients.risk_reasons` so the worklist
  /// card tooltip and the future Context Screen rationale list read from the
  /// same source.
  final List<String> reasons;

  /// Structured rationale payload (architecture.md §3.4 contract).
  /// Contains machine-readable drivers, model version, and audit metadata.
  /// Null for legacy assessments created before structured rationale shipped.
  final RiskRationale? rationale;

  bool get isUrgent => band == RiskBand.urgent;
}
