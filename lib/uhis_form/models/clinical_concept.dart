/// A single clinical terminology entry (e.g. SNOMED CT or LOINC code).
///
/// Used in [FieldSchema.clinicalConcept] to carry standardised coding for
/// clinical data elements so the form SDK can annotate FHIR Observations
/// with correct codings at submission time.
library;

/// A single clinical code from a named terminology system.
class ClinicalConcept {
  const ClinicalConcept({
    required this.system,
    required this.code,
    required this.display,
  });

  /// Terminology system identifier (e.g. `'SNOMED_CT'`, `'LOINC'`).
  final String system;

  /// The code value within [system] (e.g. `'8310-5'`).
  final String code;

  /// Human-readable description of the concept.
  final String display;

  factory ClinicalConcept.fromJson(Map<String, dynamic> json) =>
      ClinicalConcept(
        system: json['system'] as String,
        code: json['code'] as String,
        display: json['display'] as String? ?? '',
      );

  @override
  String toString() => 'ClinicalConcept($system|$code)';

  @override
  bool operator ==(Object other) =>
      other is ClinicalConcept &&
      other.system == system &&
      other.code == code;

  @override
  int get hashCode => Object.hash(system, code);
}
