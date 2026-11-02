import '../immunisation/card_extraction_transport.dart' show CardBoundingBox;

/// Data models for the Gemini-vision NCD card visit-vitals extraction
/// response. Unlike ANC/EPI, the NCD card is a visit-PER-ROW log (confirmed
/// against a real scanned card sample) — each row is one dated follow-up
/// visit, each column a field (BP, glucose, weight, height). The caller
/// requests one specific visit row (`NcdVisitExtractionRepository.extractNcdVisit`
/// takes a `visitNumber`, counting dated rows top-to-bottom) rather than
/// getting every row back at once — same single-target reasoning as ANC's
/// per-column request, just rotated 90°.
class NcdVisitExtraction {
  const NcdVisitExtraction({
    this.visitDate,
    this.bpSystolic,
    this.bpDiastolic,
    this.glucoseMmolL,
    this.glucoseType,
    this.weightKg,
    this.heightCm,
    this.confidence = 0.0,
    this.rawText,
    this.rowBoundingBox,
  });

  /// Visit date Gemini read for this row. Null when illegible/absent — never
  /// a guessed value (see `card_extraction_ncd.txt`).
  final DateTime? visitDate;

  final int? bpSystolic;
  final int? bpDiastolic;
  final double? glucoseMmolL;

  /// "fbs" (fasting sub-column had the value) | "rbs" (random sub-column had
  /// it) | null — matches the app's `glucoseType` option ids exactly, not a
  /// free-text label.
  final String? glucoseType;

  final double? weightKg;
  final double? heightCm;

  /// Model-reported confidence (0-1) for this visit row overall.
  final double confidence;

  /// Verbatim handwritten text Gemini read across this visit's row, for
  /// SK/debug transparency.
  final String? rawText;

  /// Null unless the backend's independent reads reached consensus on the
  /// row's location (see class doc comment above).
  final CardBoundingBox? rowBoundingBox;

  factory NcdVisitExtraction.fromJson(Map<String, dynamic> json) =>
      NcdVisitExtraction(
        visitDate: json['visitDate'] != null
            ? DateTime.tryParse(json['visitDate'] as String)
            : null,
        bpSystolic: (json['bpSystolic'] as num?)?.toInt(),
        bpDiastolic: (json['bpDiastolic'] as num?)?.toInt(),
        glucoseMmolL: (json['glucoseMmolL'] as num?)?.toDouble(),
        glucoseType: json['glucoseType'] as String?,
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        heightCm: (json['heightCm'] as num?)?.toDouble(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        rawText: json['rawText'] as String?,
        rowBoundingBox: json['rowBoundingBox'] != null
            ? CardBoundingBox.fromJson(
                json['rowBoundingBox'] as Map<String, dynamic>)
            : null,
      );

  bool get anyFieldFound =>
      visitDate != null ||
      bpSystolic != null ||
      bpDiastolic != null ||
      glucoseMmolL != null ||
      weightKg != null ||
      heightCm != null;
}

/// Result of a Gemini-vision NCD visit extraction call.
class NcdVisitExtractionResult {
  const NcdVisitExtractionResult({
    this.visit,
    this.flagged = false,
    this.flagReason,
  });

  /// Null when the requested visit row wasn't found on the card at all.
  final NcdVisitExtraction? visit;

  /// True when the backend's majority-vote/regularity checks flagged this
  /// visit's data as suspicious (e.g. independent reads disagreed with no
  /// majority) — surfaced to the SK as a "double-check against the card"
  /// prompt, on top of the always-required review.
  final bool flagged;
  final String? flagReason;

  factory NcdVisitExtractionResult.fromJson(Map<String, dynamic> json) =>
      NcdVisitExtractionResult(
        visit: json['ncdVisit'] != null
            ? NcdVisitExtraction.fromJson(
                json['ncdVisit'] as Map<String, dynamic>)
            : null,
        flagged: json['flagged'] as bool? ?? false,
        flagReason: json['flagReason'] as String?,
      );
}
