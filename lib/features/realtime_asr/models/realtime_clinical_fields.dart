/// Mirrors ai-scribe-service's ClinicalExtraction shape — the `data` payload
/// of a `{"type": "symptoms", ...}` message on `/scribe/realtime/transcribe`.
class RealtimeClinicalFields {
  const RealtimeClinicalFields({
    this.diagnosis,
    this.bloodPressure,
    this.bloodGlucose,
    this.comorbidities = const [],
    this.complications = const [],
    this.chiefComplaints = const [],
    this.clinicalNotes,
  });

  final String? diagnosis;
  final String? bloodPressure;
  final String? bloodGlucose;
  final List<String> comorbidities;
  final List<String> complications;
  final List<String> chiefComplaints;
  final String? clinicalNotes;

  factory RealtimeClinicalFields.fromJson(Map<String, dynamic> j) =>
      RealtimeClinicalFields(
        diagnosis: j['diagnosis'] as String?,
        bloodPressure: j['bloodPressure'] as String?,
        bloodGlucose: j['bloodGlucose'] as String?,
        comorbidities: (j['comorbidities'] as List?)?.cast<String>() ?? const [],
        complications: (j['complications'] as List?)?.cast<String>() ?? const [],
        // Same "Other:"-prefix exclusion the batch flow already applies to
        // detectedSymptoms (app/api/scribe.py) — the extraction prompt's
        // 'Other: <symptom>' template occasionally leaks through verbatim
        // (unfilled placeholder) on short/fragmentary live-partial
        // transcripts; excluding all "Other:" entries filters that out the
        // same way the batch path already does, not just the leaked ones.
        chiefComplaints: ((j['chiefComplaints'] as List?)?.cast<String>() ?? const [])
            .where((s) => !s.startsWith('Other:'))
            .toList(),
        clinicalNotes: j['clinicalNotes'] as String?,
      );

  bool get isEmpty =>
      diagnosis == null &&
      bloodPressure == null &&
      bloodGlucose == null &&
      comorbidities.isEmpty &&
      complications.isEmpty &&
      chiefComplaints.isEmpty &&
      clinicalNotes == null;
}
