import '../immunisation/card_extraction_transport.dart' show CardBoundingBox;

/// Data models for the Gemini-vision ANC card visit-vitals extraction
/// response. Mirrors `epi_date_extraction_models.dart`'s shape, but the card
/// is column-per-visit rather than row-per-vaccine, so the caller requests
/// one specific visit column (`AncVisitExtractionRepository.extractAncVisit`
/// takes a `visitNumber`) instead of getting every row back at once.
class AncVisitExtraction {
  const AncVisitExtraction({
    this.visitDate,
    this.weightKg,
    this.bpSystolic,
    this.bpDiastolic,
    this.fundalHeightCm,
    this.hemoglobinGmDl,
    this.glucoseMmolL,
    this.pulseBpm,
    this.temperatureF,
    this.fetalHeartSoundPresent,
    this.urinaryAlbuminPresent,
    this.urinaryBilirubinPresent,
    this.edemaPresent,
    this.ttTdCompleted,
    this.usgDone,
    this.confidence = 0.0,
    this.rawText,
    this.columnBoundingBox,
  });

  /// Visit date Gemini read for this column. Null when illegible/absent —
  /// never a guessed value (see `card_extraction_anc.txt`).
  final DateTime? visitDate;

  final double? weightKg;
  final int? bpSystolic;
  final int? bpDiastolic;
  final double? fundalHeightCm;
  final double? hemoglobinGmDl;
  final double? glucoseMmolL;
  final int? pulseBpm;
  final double? temperatureF;

  /// true = "+"/checkmark, false = "-"/cross, null = not recorded/illegible.
  final bool? fetalHeartSoundPresent;

  /// Urine test +/- checkboxes and TT/TD dose-completion checkbox — same
  /// true="+"/checkmark, false="-"/cross, null=illegible convention. Mapped
  /// to the form's existing "Present"/"Absent"/"yes"/"no" option ids by
  /// `UnifiedFormNotifier._ancScanFieldMap`, never shown as raw +/- in the UI.
  final bool? urinaryAlbuminPresent;
  final bool? urinaryBilirubinPresent;
  final bool? edemaPresent;
  final bool? ttTdCompleted;

  /// USG (ultrasound) done/not-done row. Same true="+"/checkmark/"Done",
  /// false="-"/cross/"Not done", null=not recorded/illegible/not on this
  /// card convention — mapped to the form's "ultrasound" field (option ids
  /// "done"/"notDone") by `UnifiedFormNotifier._ancScanFieldMap`.
  final bool? usgDone;

  /// Model-reported confidence (0-1) for this visit column overall.
  final double confidence;

  /// Verbatim handwritten text Gemini read for this visit's column, for
  /// SK/debug transparency.
  final String? rawText;

  /// Null unless the backend's independent reads reached consensus on the
  /// column's location (see class doc comment above).
  final CardBoundingBox? columnBoundingBox;

  factory AncVisitExtraction.fromJson(Map<String, dynamic> json) =>
      AncVisitExtraction(
        visitDate: json['visitDate'] != null
            ? DateTime.tryParse(json['visitDate'] as String)
            : null,
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        bpSystolic: (json['bpSystolic'] as num?)?.toInt(),
        bpDiastolic: (json['bpDiastolic'] as num?)?.toInt(),
        fundalHeightCm: (json['fundalHeightCm'] as num?)?.toDouble(),
        hemoglobinGmDl: (json['hemoglobinGmDl'] as num?)?.toDouble(),
        glucoseMmolL: (json['glucoseMmolL'] as num?)?.toDouble(),
        pulseBpm: (json['pulseBpm'] as num?)?.toInt(),
        temperatureF: (json['temperatureF'] as num?)?.toDouble(),
        fetalHeartSoundPresent: json['fetalHeartSoundPresent'] as bool?,
        urinaryAlbuminPresent: json['urinaryAlbuminPresent'] as bool?,
        urinaryBilirubinPresent: json['urinaryBilirubinPresent'] as bool?,
        edemaPresent: json['edemaPresent'] as bool?,
        ttTdCompleted: json['ttTdCompleted'] as bool?,
        usgDone: json['usgDone'] as bool?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        rawText: json['rawText'] as String?,
        columnBoundingBox: json['columnBoundingBox'] != null
            ? CardBoundingBox.fromJson(
                json['columnBoundingBox'] as Map<String, dynamic>)
            : null,
      );

  bool get anyFieldFound =>
      visitDate != null ||
      weightKg != null ||
      bpSystolic != null ||
      bpDiastolic != null ||
      fundalHeightCm != null ||
      hemoglobinGmDl != null ||
      glucoseMmolL != null ||
      pulseBpm != null ||
      temperatureF != null ||
      fetalHeartSoundPresent != null ||
      urinaryAlbuminPresent != null ||
      urinaryBilirubinPresent != null ||
      edemaPresent != null ||
      ttTdCompleted != null ||
      usgDone != null;
}

/// Result of a Gemini-vision ANC visit extraction call.
class AncVisitExtractionResult {
  const AncVisitExtractionResult({
    this.visit,
    this.flagged = false,
    this.flagReason,
  });

  /// Null when the requested visit column wasn't found on the card at all.
  final AncVisitExtraction? visit;

  /// True when the backend's majority-vote/regularity checks flagged this
  /// visit's data as suspicious (e.g. independent reads disagreed with no
  /// majority) — surfaced to the SK as a "double-check against the card"
  /// prompt, on top of the always-required review.
  final bool flagged;
  final String? flagReason;

  factory AncVisitExtractionResult.fromJson(Map<String, dynamic> json) =>
      AncVisitExtractionResult(
        visit: json['visit'] != null
            ? AncVisitExtraction.fromJson(json['visit'] as Map<String, dynamic>)
            : null,
        flagged: json['flagged'] as bool? ?? false,
        flagReason: json['flagReason'] as String?,
      );
}
