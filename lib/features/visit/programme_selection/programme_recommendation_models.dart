/// Dart models for the AI Programme Recommendation API.
///
/// Mirrors the Pydantic shapes defined in
/// `leapfrog-ai-services/app/models/programme_recommendation.py`. Update both
/// sides together — drift between client + service is the main failure mode.
library;

import '../../../core/models/programme.dart';

/// Source tag for a single rationale bullet — controls the chip rendered in
/// the recommendation card. Mirrors the Pydantic `ProgrammeRationaleBullet.source`.
enum RationaleSource {
  brac,
  bdNational,
  patientContext,
  symptom,
  general;

  static RationaleSource fromWire(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'brac':
        return RationaleSource.brac;
      case 'bd-national':
        return RationaleSource.bdNational;
      case 'patient-context':
        return RationaleSource.patientContext;
      case 'symptom':
        return RationaleSource.symptom;
      default:
        return RationaleSource.general;
    }
  }

  String get displayLabel {
    switch (this) {
      case RationaleSource.brac:
        return 'BRAC protocol';
      case RationaleSource.bdNational:
        return 'BD national guideline';
      case RationaleSource.patientContext:
        return 'Patient context';
      case RationaleSource.symptom:
        return 'Symptom';
      case RationaleSource.general:
        return '';
    }
  }
}

/// One rationale bullet rendered verbatim inside a recommendation card.
class ProgrammeRationaleBullet {
  const ProgrammeRationaleBullet({required this.text, required this.source});

  final String text;
  final RationaleSource source;

  factory ProgrammeRationaleBullet.fromJson(Map<String, dynamic> json) =>
      ProgrammeRationaleBullet(
        text: (json['text'] as String?)?.trim() ?? '',
        source: RationaleSource.fromWire(json['source'] as String?),
      );
}

/// One recommendation card — programme, confidence (0..1), and 1–6 rationale
/// bullets sourced from BRAC + Bangladesh national clinical guidelines.
class ProgrammeRecommendation {
  const ProgrammeRecommendation({
    required this.programme,
    required this.confidence,
    required this.rationale,
    required this.isCurrent,
  });

  final Programme programme;

  /// 0..1 — the mobile app renders this as a percentage on the card.
  final double confidence;

  final List<ProgrammeRationaleBullet> rationale;

  /// True when [programme] already appears in the patient's
  /// currentProgrammes list — used by the screen to badge the card.
  final bool isCurrent;

  /// Confidence as a 0–100 integer for chip display.
  int get confidencePct => (confidence.clamp(0.0, 1.0) * 100).round();

  factory ProgrammeRecommendation.fromJson(Map<String, dynamic> json) =>
      ProgrammeRecommendation(
        programme: Programme.fromWireTag(json['programme'] as String?) ??
            Programme.unknown,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        rationale: (json['rationale'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(ProgrammeRationaleBullet.fromJson)
                .toList(growable: false) ??
            const [],
        isCurrent: (json['isCurrent'] as bool?) ?? false,
      );
}

/// Cross-programme callout — patient is enrolled in one programme but the AI
/// identifies symptoms suggesting another.
class CrossProgrammeNotice {
  const CrossProgrammeNotice({
    required this.currentProgramme,
    required this.suggestedProgramme,
    required this.message,
  });

  final Programme currentProgramme;
  final Programme suggestedProgramme;
  final String message;

  factory CrossProgrammeNotice.fromJson(Map<String, dynamic> json) =>
      CrossProgrammeNotice(
        currentProgramme:
            Programme.fromWireTag(json['currentProgramme'] as String?) ??
                Programme.unknown,
        suggestedProgramme:
            Programme.fromWireTag(json['suggestedProgramme'] as String?) ??
                Programme.unknown,
        message: (json['message'] as String?)?.trim() ?? '',
      );
}

/// Full response from POST /programme-recommendation/recommend.
class ProgrammeRecommendationResponse {
  const ProgrammeRecommendationResponse({
    required this.recommendations,
    this.crossProgrammeNotice,
    required this.modelVersion,
  });

  final List<ProgrammeRecommendation> recommendations;
  final CrossProgrammeNotice? crossProgrammeNotice;
  final String modelVersion;

  factory ProgrammeRecommendationResponse.fromJson(Map<String, dynamic> json) =>
      ProgrammeRecommendationResponse(
        recommendations: (json['recommendations'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(ProgrammeRecommendation.fromJson)
                .toList(growable: false) ??
            const [],
        crossProgrammeNotice: json['crossProgrammeNotice'] is Map<String, dynamic>
            ? CrossProgrammeNotice.fromJson(
                json['crossProgrammeNotice'] as Map<String, dynamic>)
            : null,
        modelVersion:
            (json['modelVersion'] as String?) ?? 'programme-recommendation',
      );
}
