/// AI-extracted field from the scribe service.
///
/// Used for form_prefill and triage modes to populate assessment forms
/// with AI-extracted values that include confidence and source tracking.
library;

import 'package:flutter/foundation.dart';

/// Source of a field value for audit trail.
enum FieldSource {
  /// Value was entered manually by the user.
  manual,

  /// Value was extracted by AI and accepted by the user.
  aiAccepted,

  /// Value was extracted by AI but modified by the user.
  aiModified,

  /// Value was extracted by AI and pending review.
  aiPending,

  /// Value was extracted by AI and rejected by the user.
  aiRejected,
}

/// A single field extracted by the AI scribe service.
///
/// Contains the value, confidence score, and the transcript segment
/// that the AI used to extract this value.
@immutable
class AIExtractedField {
  const AIExtractedField({
    required this.fieldId,
    required this.value,
    required this.confidence,
    this.sourceSegment,
    this.source = FieldSource.aiPending,
    this.originalValue,
    this.extractedAt,
    this.reviewedAt,
  });

  /// Field identifier matching the form schema.
  final String fieldId;

  /// Extracted value (typed: bool, int, double, String, DateTime).
  final dynamic value;

  /// Confidence score from 0.0 to 1.0.
  /// - 1.0: Verbatim match from transcript
  /// - 0.8+: Clear paraphrase
  /// - 0.6-0.8: Inferred from context
  /// - <0.6: Low confidence, requires review
  final double confidence;

  /// Verbatim quote from the transcript supporting this extraction.
  final String? sourceSegment;

  /// Source of the value (manual, AI-accepted, AI-modified, etc.).
  final FieldSource source;

  /// Original AI-extracted value before user modification.
  /// Used for audit trail.
  final dynamic originalValue;

  /// When the AI extracted this value.
  final DateTime? extractedAt;

  /// When the user reviewed/accepted/rejected this value.
  final DateTime? reviewedAt;

  /// Whether this field needs human review.
  bool get requiresReview => confidence < 0.8 || source == FieldSource.aiPending;

  /// Whether this is an AI-populated field.
  bool get isAiPopulated =>
      source == FieldSource.aiAccepted ||
      source == FieldSource.aiModified ||
      source == FieldSource.aiPending;

  /// Confidence level for display.
  AIConfidenceLevel get confidenceLevel {
    if (confidence >= 0.9) return AIConfidenceLevel.high;
    if (confidence >= 0.7) return AIConfidenceLevel.medium;
    return AIConfidenceLevel.low;
  }

  AIExtractedField copyWith({
    String? fieldId,
    dynamic value,
    double? confidence,
    String? sourceSegment,
    FieldSource? source,
    dynamic originalValue,
    DateTime? extractedAt,
    DateTime? reviewedAt,
  }) =>
      AIExtractedField(
        fieldId: fieldId ?? this.fieldId,
        value: value ?? this.value,
        confidence: confidence ?? this.confidence,
        sourceSegment: sourceSegment ?? this.sourceSegment,
        source: source ?? this.source,
        originalValue: originalValue ?? this.originalValue,
        extractedAt: extractedAt ?? this.extractedAt,
        reviewedAt: reviewedAt ?? this.reviewedAt,
      );

  /// Accept this AI-extracted value.
  AIExtractedField accept() => copyWith(
        source: FieldSource.aiAccepted,
        reviewedAt: DateTime.now(),
      );

  /// Reject this AI-extracted value (value becomes null).
  AIExtractedField reject() => copyWith(
        source: FieldSource.aiRejected,
        value: null,
        reviewedAt: DateTime.now(),
      );

  /// Modify this AI-extracted value.
  AIExtractedField modify(dynamic newValue) => copyWith(
        source: FieldSource.aiModified,
        value: newValue,
        originalValue: value,
        reviewedAt: DateTime.now(),
      );

  factory AIExtractedField.fromJson(Map<String, dynamic> json) =>
      AIExtractedField(
        fieldId: json['fieldId'] as String,
        value: json['value'],
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        sourceSegment: json['sourceSegment'] as String?,
        source: FieldSource.aiPending,
        extractedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'fieldId': fieldId,
        'value': value,
        'confidence': confidence,
        'sourceSegment': sourceSegment,
        'source': source.name,
        if (originalValue != null) 'originalValue': originalValue,
        if (extractedAt != null) 'extractedAt': extractedAt!.toIso8601String(),
        if (reviewedAt != null) 'reviewedAt': reviewedAt!.toIso8601String(),
      };

  /// For audit trail: was this field AI-assisted?
  Map<String, dynamic> toAuditEntry() => {
        'fieldId': fieldId,
        'source': source.name,
        'confidence': confidence,
        'aiValue': source == FieldSource.aiModified ? originalValue : value,
        'finalValue': value,
        'extractedAt': extractedAt?.toIso8601String(),
        'reviewedAt': reviewedAt?.toIso8601String(),
      };
}

/// Confidence level for visual indicators.
enum AIConfidenceLevel {
  /// 90%+ confidence - green indicator
  high,

  /// 70-89% confidence - yellow indicator
  medium,

  /// <70% confidence - red indicator, requires review
  low;

  /// Get confidence level from a score.
  static AIConfidenceLevel fromScore(double score) {
    if (score >= 0.9) return AIConfidenceLevel.high;
    if (score >= 0.7) return AIConfidenceLevel.medium;
    return AIConfidenceLevel.low;
  }
}

/// Result from form_prefill mode.
@immutable
class FormPrefillResult {
  const FormPrefillResult({
    required this.fields,
    this.unmappedFindings = const [],
    this.transcriptText,
    this.noteId,
  });

  /// Extracted fields mapped to form schema.
  final List<AIExtractedField> fields;

  /// Clinical findings that didn't map to any field in the schema.
  final List<String> unmappedFindings;

  /// Original transcript text.
  final String? transcriptText;

  /// Note ID for accept/reject operations.
  final String? noteId;

  /// Get field by ID.
  AIExtractedField? getField(String fieldId) {
    final idx = fields.indexWhere((f) => f.fieldId == fieldId);
    return idx >= 0 ? fields[idx] : null;
  }

  /// Check if a field was extracted.
  bool hasField(String fieldId) => fields.any((f) => f.fieldId == fieldId);

  /// Get value for a field, or null if not extracted.
  dynamic getValue(String fieldId) => getField(fieldId)?.value;

  /// Number of fields requiring review.
  int get fieldsRequiringReview =>
      fields.where((f) => f.requiresReview).length;

  /// Number of fields pending user review/acceptance.
  int get pendingFieldCount =>
      fields.where((f) => f.source == FieldSource.aiPending).length;

  /// All fields have been reviewed.
  bool get allFieldsReviewed =>
      fields.every((f) => f.source != FieldSource.aiPending);

  factory FormPrefillResult.fromJson(Map<String, dynamic> json) {
    final fieldsJson = json['fields'] as List<dynamic>? ?? [];
    final result = FormPrefillResult(
      fields: fieldsJson
          .whereType<Map<String, dynamic>>()
          .map(AIExtractedField.fromJson)
          .toList(),
      unmappedFindings: (json['unmappedFindings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      transcriptText: json['transcriptText'] as String?,
      noteId: json['noteId'] as String?,
    );
    // Client-side safety net: LLM often drops height/hba1c in Hindi–Bangla
    // code-mix while weight/BP still arrive. Recover from the transcript.
    return result.withRecoveredVitals();
  }

  /// Deterministic height / weight / hba1c fill when the server omitted them.
  FormPrefillResult withRecoveredVitals() {
    final transcript = transcriptText;
    if (transcript == null || transcript.trim().isEmpty) return this;

    final present = fields.map((f) => f.fieldId).toSet();
    final extra = <AIExtractedField>[];
    final now = DateTime.now();

    void tryAdd(String fieldId, RegExp pattern, double lo, double hi) {
      if (present.contains(fieldId)) return;
      final matches = pattern.allMatches(transcript);
      if (matches.isEmpty) return;
      final m = matches.last;
      final raw = m.group(1)?.replaceAll(',', '.');
      final v = double.tryParse(raw ?? '');
      if (v == null || v < lo || v > hi) return;
      // "120/80" is BP, not height — digit must not be followed by '/'.
      if (fieldId == 'height') {
        final end = m.end;
        if (end < transcript.length && transcript[end] == '/') return;
      }
      extra.add(AIExtractedField(
        fieldId: fieldId,
        value: v == v.roundToDouble() ? v.toInt() : v,
        confidence: 1.0,
        source: FieldSource.aiPending,
        sourceSegment: m.group(0)!.trim(),
        extractedAt: now,
      ));
      present.add(fieldId);
    }

    tryAdd(
      'height',
      RegExp(
        r'(?:height|हाइट|हाईट|হাইট|উচ্চতা)'
        r'(?:\s*(?:is|=|:|হ্যায়|है|হয়))?\s*'
        r'(\d{2,3}(?:\.\d+)?)'
        r'(?:\s*(?:cm|সেন্টি(?:মিটার)?|सेंटी(?:मीटर)?))?',
        caseSensitive: false,
      ),
      30,
      250,
    );
    tryAdd(
      'weight',
      RegExp(
        r'(?:weight|ওজন|वजन|वेट)'
        r'(?:\s*(?:is|=|:|হ্যায়|है))?\s*'
        r'(\d{2,3}(?:\.\d+)?)'
        r'(?:\s*(?:kg|কেজি|किलो))?',
        caseSensitive: false,
      ),
      1,
      250,
    );
    tryAdd(
      'hba1c',
      // Dart RegExp is picky with mixed Devanagari/Bangla alternations —
      // keep this permissive (keyword then nearest number within ~40 chars).
      RegExp(
        r'(?:hba1c|hb\s*a\s*1\s*c|(?:এইচ|एच)).{0,40}?'
        r'(\d+(?:[.,]\d+)?)',
        caseSensitive: false,
        unicode: true,
      ),
      3,
      20,
    );

    if (extra.isEmpty) return this;
    return FormPrefillResult(
      fields: [...fields, ...extra],
      unmappedFindings: unmappedFindings,
      transcriptText: transcriptText,
      noteId: noteId,
    );
  }

  Map<String, dynamic> toJson() => {
        'fields': fields.map((f) => f.toJson()).toList(),
        'unmappedFindings': unmappedFindings,
        if (transcriptText != null) 'transcriptText': transcriptText,
        if (noteId != null) 'noteId': noteId,
      };

  /// Generate audit trail for all fields.
  List<Map<String, dynamic>> toAuditTrail() =>
      fields.map((f) => f.toAuditEntry()).toList();
}

/// Result from triage mode.
@immutable
class TriageExtractionResult {
  const TriageExtractionResult({
    required this.symptomCodes,
    this.transcriptText,
    this.noteId,
  });

  /// Extracted symptom codes with confidence.
  final List<AIExtractedField> symptomCodes;

  /// Original transcript text.
  final String? transcriptText;

  /// Note ID for accept/reject operations.
  final String? noteId;

  /// Get all symptom codes as strings.
  Set<String> get codes =>
      symptomCodes.map((s) => s.fieldId).toSet();

  /// Check if a symptom was detected.
  bool hasSymptom(String code) =>
      symptomCodes.any((s) => s.fieldId == code);

  /// Get confidence for a symptom.
  double? getConfidence(String code) {
    final idx = symptomCodes.indexWhere((s) => s.fieldId == code);
    return idx >= 0 ? symptomCodes[idx].confidence : null;
  }

  factory TriageExtractionResult.fromJson(Map<String, dynamic> json) {
    final codesJson = json['symptomCodes'] as Map<String, dynamic>? ?? {};
    final fields = <AIExtractedField>[];
    codesJson.forEach((code, data) {
      if (data is Map<String, dynamic>) {
        fields.add(AIExtractedField(
          fieldId: code,
          value: true,
          confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
          sourceSegment: data['sourceSegment'] as String?,
          source: FieldSource.aiPending,
          extractedAt: DateTime.now(),
        ));
      }
    });
    return TriageExtractionResult(
      symptomCodes: fields,
      transcriptText: json['transcriptText'] as String?,
      noteId: json['noteId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'symptomCodes': {
          for (final s in symptomCodes)
            s.fieldId: {
              'confidence': s.confidence,
              'sourceSegment': s.sourceSegment,
            },
        },
        if (transcriptText != null) 'transcriptText': transcriptText,
        if (noteId != null) 'noteId': noteId,
      };
}
