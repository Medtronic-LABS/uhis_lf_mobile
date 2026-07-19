import '../../../core/models/programme.dart';

/// A simple symptom entry for the triage picker grid.
class SymptomDef {
  const SymptomDef({
    required this.code,
    required this.label,
    required this.programme,
  });

  /// Canonical code passed to [PathwayEngine] — must match [PathwayRule.anyOf]
  /// or [PathwayRule.combinations] entries in pathway_rules_v1.dart.
  final String code;

  /// Display label shown on the symptom chip (English).
  final String label;

  /// Programme section this symptom belongs to in the triage grid.
  final Programme programme;
}

/// Curated 20-symptom catalog for the Step-1 triage grid.
///
/// Grouped into 4 clinical programmes. Each section is shown only when the
/// patient's context makes that programme relevant (pregnant → ANC, postpartum
/// → PNC, adults → NCD + TB). Order within each section follows clinical
/// priority.
///
/// Search beyond this catalog is available via the free-text search box —
/// any typed symptom not matching these tiles is added as a custom free-text
/// chip.
abstract final class SymptomCatalog {
  SymptomCatalog._();

  static const all = <SymptomDef>[
    // ── ANC ──────────────────────────────────────────────────────────────────
    SymptomDef(code: 'headache',               label: 'Headache',         programme: Programme.anc),
    SymptomDef(code: 'swelling_face_hands',    label: 'Swelling',         programme: Programme.anc),
    SymptomDef(code: 'abdominal_pain',         label: 'Abdominal pain',   programme: Programme.anc),
    SymptomDef(code: 'blurred_vision',         label: 'Blurry vision',    programme: Programme.anc),
    SymptomDef(code: 'reduced_fetal_movement', label: 'Baby not moving',  programme: Programme.anc),

    // ── PNC ──────────────────────────────────────────────────────────────────
    SymptomDef(code: 'vaginal_bleeding', label: 'Bleeding',       programme: Programme.pnc),
    SymptomDef(code: 'fever',            label: 'Fever',          programme: Programme.pnc),
    SymptomDef(code: 'abdominal_pain',   label: 'Abdominal pain', programme: Programme.pnc),
    SymptomDef(code: 'headache',         label: 'Headache',       programme: Programme.pnc),
    SymptomDef(code: 'dizziness',        label: 'Dizziness',      programme: Programme.pnc),

    // ── NCD ──────────────────────────────────────────────────────────────────
    SymptomDef(code: 'headache',    label: 'Headache',          programme: Programme.ncd),
    SymptomDef(code: 'fatigue',     label: 'Feeling tired/weak', programme: Programme.ncd),
    SymptomDef(code: 'polydipsia',  label: 'Very thirsty',       programme: Programme.ncd),
    SymptomDef(code: 'chest_pain',  label: 'Chest pain',         programme: Programme.ncd),
    SymptomDef(code: 'numbness',    label: 'Numbness',           programme: Programme.ncd),

    // ── TB ───────────────────────────────────────────────────────────────────
    SymptomDef(code: 'cough_over_2_weeks', label: 'Cough',         programme: Programme.tb),
    SymptomDef(code: 'night_sweats',       label: 'Night sweats',  programme: Programme.tb),
    SymptomDef(code: 'fever',              label: 'Fever',         programme: Programme.tb),
    SymptomDef(code: 'weight_loss',        label: 'Losing weight', programme: Programme.tb),
    SymptomDef(code: 'weakness',           label: 'Feeling weak',  programme: Programme.tb),
  ];

  static List<SymptomDef> byProgramme(Programme p) =>
      all.where((s) => s.programme == p).toList();
}
