import '../../../core/constants/app_strings.dart';
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

  /// Display label shown on the symptom chip (localized via [TriageStrings]).
  final String label;

  /// Programme section this symptom belongs to in the triage grid.
  final Programme programme;
}

/// Curated symptom catalog for the Step-1 triage grid.
///
/// Labels resolve through [TriageStrings.symptomLabel] so Bangla is applied.
/// Grouped into clinical programmes; each section is shown only when the
/// patient's context makes that programme relevant.
abstract final class SymptomCatalog {
  SymptomCatalog._();

  static List<SymptomDef> get all => [
        // ── ANC ──────────────────────────────────────────────────────────────
        _s('headache', Programme.anc),
        _s('swelling_face_hands', Programme.anc),
        _s('abdominal_pain', Programme.anc),
        _s('blurred_vision', Programme.anc),
        _s('reduced_fetal_movement', Programme.anc),

        // ── PNC ──────────────────────────────────────────────────────────────
        _s('vaginal_bleeding', Programme.pnc),
        _s('fever', Programme.pnc),
        _s('abdominal_pain', Programme.pnc),
        _s('headache', Programme.pnc),
        _s('dizziness', Programme.pnc),

        // ── NCD ──────────────────────────────────────────────────────────────
        _s('headache', Programme.ncd),
        _s('fatigue', Programme.ncd),
        _s('polydipsia', Programme.ncd),
        _s('chest_pain', Programme.ncd),
        _s('numbness', Programme.ncd),

        // ── TB ───────────────────────────────────────────────────────────────
        _s('cough_over_2_weeks', Programme.tb),
        _s('night_sweats', Programme.tb),
        _s('fever', Programme.tb),
        _s('weight_loss', Programme.tb),
        _s('weakness', Programme.tb),

        // ── IMCI (Child Health, under-5) ─────────────────────────────────────
        _s('fever', Programme.imci),
        _s('cough', Programme.imci),
        _s('fast_breathing', Programme.imci),
        _s('diarrhea', Programme.imci),
        _s('vomiting', Programme.imci),
        _s('not_eating', Programme.imci),
        _s('convulsions', Programme.imci),
        _s('lethargy', Programme.imci),
      ];

  static SymptomDef _s(String code, Programme programme) => SymptomDef(
        code: code,
        label: TriageStrings.symptomLabel(code),
        programme: programme,
      );

  static List<SymptomDef> byProgramme(Programme p) =>
      all.where((s) => s.programme == p).toList();
}
