/// Dart models for the AI Next Best Action (NABA) service.
///
/// Mirrors the Python Pydantic models in
/// `leapfrog-setup/ai-scribe-service/app/models/naba.py`.
///
/// Every [NabaResponse] carries a mandatory [RationalePayload] (architecture.md §5.2).
/// The response is a *proposal* — FHIR resources are written only after the SK accepts.
library;

// ── Inbound sub-models ────────────────────────────────────────────────────────

class NabaLabResult {
  const NabaLabResult({
    required this.name,
    required this.value,
    required this.unit,
    this.referenceRange,
    this.abnormal = false,
    this.loincCode,
  });

  final String name;
  final String value;
  final String unit;
  final String? referenceRange;
  final bool abnormal;
  final String? loincCode;

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'unit': unit,
        if (referenceRange != null) 'referenceRange': referenceRange,
        'abnormal': abnormal,
        if (loincCode != null) 'loincCode': loincCode,
      };
}

class NabaVitalSnapshot {
  const NabaVitalSnapshot({
    this.bloodPressureSystolic,
    this.bloodPressureDiastolic,
    this.weight,
    this.temperature,
    this.glucoseFasting,
    this.glucoseRandom,
    this.glucoseUnit,
    this.spO2,
    this.heartRate,
    this.bmi,
  });

  final int? bloodPressureSystolic;
  final int? bloodPressureDiastolic;
  final double? weight;
  final double? temperature;
  final double? glucoseFasting;
  final double? glucoseRandom;
  final String? glucoseUnit;
  final int? spO2;
  final int? heartRate;
  final double? bmi;

  Map<String, dynamic> toJson() => {
        if (bloodPressureSystolic != null)
          'bloodPressureSystolic': bloodPressureSystolic,
        if (bloodPressureDiastolic != null)
          'bloodPressureDiastolic': bloodPressureDiastolic,
        if (weight != null) 'weight': weight,
        if (temperature != null) 'temperature': temperature,
        if (glucoseFasting != null) 'glucoseFasting': glucoseFasting,
        if (glucoseRandom != null) 'glucoseRandom': glucoseRandom,
        if (glucoseUnit != null) 'glucoseUnit': glucoseUnit,
        if (spO2 != null) 'spO2': spO2,
        if (heartRate != null) 'heartRate': heartRate,
        if (bmi != null) 'bmi': bmi,
      };
}

class NabaPriorVisit {
  const NabaPriorVisit({
    required this.date,
    this.programme,
    this.keyFindings = const [],
    this.actionsTaken = const [],
  });

  final String date;
  final String? programme;
  final List<String> keyFindings;
  final List<String> actionsTaken;

  Map<String, dynamic> toJson() => {
        'date': date,
        if (programme != null) 'programme': programme,
        'keyFindings': keyFindings,
        'actionsTaken': actionsTaken,
      };
}

/// One assessment's clinical inputs for NABA.
///
/// For referral programmes, mirrors Flutter `_computeReferral` inputs so the
/// backend can recompute the same rules. For `PWPROFILE` / `FAMILY_PLANNING`,
/// carries form context (those flows have no Step 2 referral card).
class NabaReferralAssessment {
  const NabaReferralAssessment({
    required this.assessmentType,
    required this.referralInputs,
  });

  /// Wire assessment type: `ANC`, `NCD`, `PNC_MOTHER`, `CHILDHOOD_VISIT`,
  /// `PWPROFILE`, `FAMILY_PLANNING`, …
  final String assessmentType;

  /// Clinical fields for this assessment type (referral inputs, or form
  /// context for PW / FP).
  final Map<String, dynamic> referralInputs;

  Map<String, dynamic> toJson() => {
        'assessmentType': assessmentType,
        'referralInputs': referralInputs,
      };
}

// ── Primary request ───────────────────────────────────────────────────────────

class NabaRequest {
  const NabaRequest({
    required this.requestId,
    required this.patientId,
    this.visitType = 'routine',
    this.aiScribeConfidence = 1.0,
    this.clinicalRuleIds = const [],
    this.ageYears,
    this.sex,
    this.activeProgrammes = const [],
    this.gestationalWeeks,
    this.isPregnant,
    this.aiDetectedSymptoms = const [],
    this.manuallySelectedSymptoms = const [],
    this.scribeTranscriptExcerpt,
    this.currentVitals,
    this.labResults = const [],
    this.currentMedications = const [],
    this.medicationAdherence,
    this.priorVisits = const [],
    this.openFollowUps = const [],
    this.riskIndicators = const [],
    this.assessments = const [],
    this.isReferred = false,
    this.referredReasons = const [],
    this.referralReason,
  });

  final String requestId;
  final String patientId;
  final String visitType;
  final double aiScribeConfidence;
  final List<String> clinicalRuleIds;
  final int? ageYears;
  final String? sex;
  final List<String> activeProgrammes;
  final int? gestationalWeeks;
  final bool? isPregnant;
  final List<String> aiDetectedSymptoms;
  final List<String> manuallySelectedSymptoms;
  final String? scribeTranscriptExcerpt;
  final NabaVitalSnapshot? currentVitals;
  final List<NabaLabResult> labResults;
  final List<String> currentMedications;
  final String? medicationAdherence;
  final List<NabaPriorVisit> priorVisits;
  final List<Map<String, dynamic>> openFollowUps;
  final List<String> riskIndicators;

  /// Per-assessment referral inputs (same fields Flutter uses clinically).
  final List<NabaReferralAssessment> assessments;

  /// Step 2 clinical referral flag (same gate as the Step 3 referral card).
  final bool isReferred;

  /// Step 2 wire reasons shown on the offline referral card (bullets).
  final List<String> referredReasons;

  /// Joined referral-card body text (offline card copy / clinical fallback).
  final String? referralReason;

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'patientId': patientId,
        'visitType': visitType,
        'aiScribeConfidence': aiScribeConfidence,
        'clinicalRuleIds': clinicalRuleIds,
        if (ageYears != null) 'ageYears': ageYears,
        if (sex != null) 'sex': sex,
        'activeProgrammes': activeProgrammes,
        if (gestationalWeeks != null) 'gestationalWeeks': gestationalWeeks,
        if (isPregnant != null) 'isPregnant': isPregnant,
        'aiDetectedSymptoms': aiDetectedSymptoms,
        'manuallySelectedSymptoms': manuallySelectedSymptoms,
        if (scribeTranscriptExcerpt != null)
          'scribeTranscriptExcerpt': scribeTranscriptExcerpt,
        if (currentVitals != null) 'currentVitals': currentVitals!.toJson(),
        if (labResults.isNotEmpty)
          'labResults': labResults.map((l) => l.toJson()).toList(),
        'currentMedications': currentMedications,
        if (medicationAdherence != null) 'medicationAdherence': medicationAdherence,
        'priorVisits': priorVisits.map((v) => v.toJson()).toList(),
        'openFollowUps': openFollowUps,
        'riskIndicators': riskIndicators,
        if (assessments.isNotEmpty)
          'assessments': assessments.map((a) => a.toJson()).toList(),
        'isReferred': isReferred,
        'referredReasons': referredReasons,
        if (referralReason != null && referralReason!.isNotEmpty)
          'referralReason': referralReason,
      };
}

// ── Outbound sub-models ───────────────────────────────────────────────────────

class NabaRationale {
  const NabaRationale({
    required this.guidelineIds,
    this.guidelineNote,
    required this.sourceObservations,
    this.observationNote,
    required this.modelVersion,
    required this.confidence,
    required this.humanReviewRequired,
  });

  final List<String> guidelineIds;
  final String? guidelineNote;
  final List<String> sourceObservations;
  final String? observationNote;
  final String modelVersion;
  final double confidence;
  final bool humanReviewRequired;

  factory NabaRationale.fromJson(Map<String, dynamic> j) => NabaRationale(
        guidelineIds: List<String>.from(j['guidelineIds'] ?? []),
        guidelineNote: j['guidelineNote'] as String?,
        sourceObservations: List<String>.from(j['sourceObservations'] ?? []),
        observationNote: j['observationNote'] as String?,
        modelVersion: j['modelVersion'] as String? ?? '',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        humanReviewRequired: j['humanReviewRequired'] as bool? ?? false,
      );
}

class NabaVisitSummary {
  const NabaVisitSummary({required this.title, required this.summary});
  final String title;
  final String summary;
  factory NabaVisitSummary.fromJson(Map<String, dynamic> j) => NabaVisitSummary(
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
      );
}

class NabaClinicalFinding {
  const NabaClinicalFinding({
    required this.severity,
    required this.finding,
    required this.reason,
    required this.confidence,
    this.guidelineId,
    this.conflict = false,
  });

  final String severity; // 'High' | 'Medium' | 'Low'
  final String finding;
  final String reason;
  final double confidence;
  final String? guidelineId;
  final bool conflict;

  factory NabaClinicalFinding.fromJson(Map<String, dynamic> j) =>
      NabaClinicalFinding(
        severity: j['severity'] as String? ?? 'Low',
        finding: j['finding'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        guidelineId: j['guidelineId'] as String?,
        conflict: j['conflict'] as bool? ?? false,
      );
}

class NabaNextAction {
  const NabaNextAction({
    required this.priority,
    required this.action,
    required this.urgency,
    this.programme,
  });

  final int priority;
  final String action;
  final String urgency; // 'Now' | 'Today' | 'This week' | 'Routine'
  final String? programme;

  factory NabaNextAction.fromJson(Map<String, dynamic> j) => NabaNextAction(
        priority: (j['priority'] as num?)?.toInt() ?? 0,
        action: j['action'] as String? ?? '',
        urgency: j['urgency'] as String? ?? 'Routine',
        programme: j['programme'] as String?,
      );
}

class NabaReferralRecommendation {
  const NabaReferralRecommendation({
    required this.required_,
    this.destination,
    this.urgency,
    this.reason,
    this.guidelineId,
  });

  final bool required_;
  final String? destination;
  final String? urgency;
  final String? reason;
  final String? guidelineId;

  factory NabaReferralRecommendation.fromJson(Map<String, dynamic> j) =>
      NabaReferralRecommendation(
        required_: j['required'] as bool? ?? false,
        destination: j['destination'] as String?,
        urgency: j['urgency'] as String?,
        reason: j['reason'] as String?,
        guidelineId: j['guidelineId'] as String?,
      );
}

class NabaFollowUpItem {
  const NabaFollowUpItem({
    required this.activity,
    required this.timeline,
    this.programme,
    this.resolvedDate,
  });

  final String activity;
  final String timeline;
  final String? programme;

  /// Exact date to pre-fill in the follow-up date picker, when already known
  /// precisely (e.g. EPI's next milestone date) — checked first by
  /// `_FollowUpDateRowState.resolveDate()`/`_initialDate()` ahead of the
  /// programme-day-offset / timeline-regex heuristics used for every other
  /// programme. Never populated by [fromJson] — the backend NABA response has
  /// no equivalent field, so AI-path items always fall back to timeline-based
  /// resolution unchanged.
  final DateTime? resolvedDate;

  factory NabaFollowUpItem.fromJson(Map<String, dynamic> j) => NabaFollowUpItem(
        activity: j['activity'] as String? ?? '',
        timeline: j['timeline'] as String? ?? '',
        programme: j['programme'] as String?,
      );
}

// ── Primary response ──────────────────────────────────────────────────────────

class NabaResponse {
  const NabaResponse({
    required this.requestId,
    required this.modelVersion,
    required this.generatedAt,
    required this.rationale,
    required this.visitSummary,
    this.clinicalFindings = const [],
    this.nextActions = const [],
    this.dangerSigns = const [],
    this.followUp = const [],
    this.counselling = const [],
    this.familyCounselling = const [],
    this.medicationAdvice = const [],
    this.whatsappSummary,
    this.doctorHandover,
    this.referralRecommendation,
    this.contextTruncated = false,
  });

  final String requestId;
  final String modelVersion;
  final String generatedAt;
  final NabaRationale rationale;
  final NabaVisitSummary visitSummary;
  final List<NabaClinicalFinding> clinicalFindings;
  final List<NabaNextAction> nextActions;
  final List<String> dangerSigns;
  final List<NabaFollowUpItem> followUp;
  final List<String> counselling;
  final List<String> familyCounselling;
  final List<String> medicationAdvice;
  final String? whatsappSummary;
  final String? doctorHandover;
  final NabaReferralRecommendation? referralRecommendation;
  final bool contextTruncated;

  factory NabaResponse.fromJson(Map<String, dynamic> j) => NabaResponse(
        requestId: j['requestId'] as String? ?? '',
        modelVersion: j['modelVersion'] as String? ?? '',
        generatedAt: j['generatedAt'] as String? ?? '',
        rationale: NabaRationale.fromJson(
            j['rationale'] as Map<String, dynamic>? ?? {}),
        visitSummary: NabaVisitSummary.fromJson(
            j['visit_summary'] as Map<String, dynamic>? ?? {}),
        clinicalFindings: (j['clinical_findings'] as List<dynamic>? ?? [])
            .map((e) =>
                NabaClinicalFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextActions: (j['next_actions'] as List<dynamic>? ?? [])
            .map((e) => NabaNextAction.fromJson(e as Map<String, dynamic>))
            .toList(),
        dangerSigns: List<String>.from(j['danger_signs'] ?? []),
        followUp: (j['follow_up'] as List<dynamic>? ?? [])
            .map((e) => NabaFollowUpItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        counselling: List<String>.from(j['counselling'] ?? []),
        familyCounselling: List<String>.from(j['family_counselling'] ?? []),
        medicationAdvice: List<String>.from(j['medication_advice'] ?? []),
        whatsappSummary: j['whatsapp_summary'] as String?,
        doctorHandover: j['doctor_handover'] as String?,
        referralRecommendation: j['referral_recommendation'] != null
            ? NabaReferralRecommendation.fromJson(
                j['referral_recommendation'] as Map<String, dynamic>)
            : null,
        contextTruncated: j['contextTruncated'] as bool? ?? false,
      );
}
