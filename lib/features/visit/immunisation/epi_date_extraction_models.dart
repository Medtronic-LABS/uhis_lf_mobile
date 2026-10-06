/// Data models for the Gemini-vision EPI card date-extraction response.
class EpiDoseExtraction {
  const EpiDoseExtraction({
    required this.vaccineCode,
    this.dose,
    this.date,
    this.confidence = 0.0,
    this.rawText,
  });

  /// Vaccine code (matches [EpiCardScanner]'s alias-table keys, e.g. BCG,
  /// PENTA1-3, PCV1-3, OPV1-3, FIPV1-2, MR1-2, TCV).
  final String vaccineCode;

  /// Dose number, when the card/model could disambiguate it. Null when the
  /// printed label carries no dose number (e.g. a Bengali row label applying
  /// to all doses of a vaccine).
  final int? dose;

  /// Handwritten date Gemini read for this dose. Null when illegible/absent
  /// on the card — never a guessed value (see `card_extraction_epi.txt`).
  final DateTime? date;

  /// Model-reported confidence (0-1) for this dose's date reading.
  final double confidence;

  /// Verbatim handwritten text Gemini read for this cell, for SK/debug
  /// transparency.
  final String? rawText;

  factory EpiDoseExtraction.fromJson(Map<String, dynamic> json) =>
      EpiDoseExtraction(
        vaccineCode: json['vaccineCode'] as String? ?? '',
        dose: json['dose'] as int?,
        date: json['date'] != null
            ? DateTime.tryParse(json['date'] as String)
            : null,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        rawText: json['rawText'] as String?,
      );
}

/// Result of a Gemini-vision card extraction call — the online counterpart
/// to [EpiCardScanner]'s offline name-only match.
class EpiDateExtractionResult {
  const EpiDateExtractionResult({required this.doses});

  final List<EpiDoseExtraction> doses;

  factory EpiDateExtractionResult.fromJson(Map<String, dynamic> json) =>
      EpiDateExtractionResult(
        doses: (json['doses'] as List<dynamic>?)
                ?.map((e) =>
                    EpiDoseExtraction.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// All vaccine codes Gemini matched on the card, regardless of whether a
  /// date was readable — this makes the online path a drop-in replacement
  /// for the offline name-matcher's `matchedCodes`.
  List<String> get matchedCodes =>
      {for (final d in doses) if (d.vaccineCode.isNotEmpty) d.vaccineCode}
          .toList();

  /// Per-vaccine-code date map, dropping entries with a null date (illegible
  /// on the card). When the same code appears more than once, the first
  /// non-null date wins.
  Map<String, DateTime> get dateByCode {
    final map = <String, DateTime>{};
    for (final d in doses) {
      if (d.date != null) map.putIfAbsent(d.vaccineCode, () => d.date!);
    }
    return map;
  }
}
