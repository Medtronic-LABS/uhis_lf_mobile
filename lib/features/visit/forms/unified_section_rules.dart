import 'canonical_visit_data.dart';
import 'form_config.dart';

/// Pure-Dart rules engine: given active formTypes + current field values,
/// returns the ordered, deduplicated list of [FormSection]s to render.
abstract final class UnifiedSectionRules {
  UnifiedSectionRules._();

  /// Returns ordered, deduplicated [FormSection]s for rendering.
  ///
  /// Dedup rule: if the same fieldId appears in sections from multiple
  /// formTypes, it is shown only in the first formType's section that claims
  /// it. Subsequent sections drop already-claimed fieldIds from their
  /// [FormSection.fieldRefs].  A section with no remaining fieldRefs is
  /// omitted entirely.
  ///
  /// Conditional rules (applied after dedup):
  /// - `birthPreparedness` section: only when `anc` active AND GA ≥ 28 weeks.
  ///   Weeks resolved from [gestationalWeeks] first; falls back to the
  ///   `gestationalAge` field value the SK may have already entered.
  /// - `pregnancyOutcome` sections: only when `pncMother` active.
  /// - `pncChild` / `pncNeonatal` sections: only when `isChildAlive` == `'yes'`.
  /// - NCD `bpReadings` section: only when NCD active AND `anc` is NOT active
  ///   (when ANC is active the single BP reading is captured there and reused
  ///   by the NCD payload mapper — no second BP entry needed).
  static List<FormSection> activeSections({
    required FormConfig config,
    required List<String> activeFormTypes,
    required CanonicalVisitData currentData,
    int? gestationalWeeks,
  }) {
    final claimedFieldIds = <String>{};
    final result = <FormSection>[];

    for (final formType in activeFormTypes) {
      final sections = config.forms[formType] ?? [];
      for (final section in sections) {
        // Apply conditional visibility rules before dedup.
        if (!_isSectionVisible(
          section: section,
          activeFormTypes: activeFormTypes,
          currentData: currentData,
          gestationalWeeks: gestationalWeeks,
        )) {
          continue;
        }

        // Dedup: keep only fieldRefs not already claimed.
        final remainingRefs = section.fieldRefs
            .where((ref) => !claimedFieldIds.contains(ref.id))
            .toList();

        if (remainingRefs.isEmpty) continue;

        // Claim all fieldIds in this section.
        for (final ref in remainingRefs) {
          claimedFieldIds.add(ref.id);
        }

        // Return a section with only the unclaimed refs.
        if (remainingRefs.length == section.fieldRefs.length) {
          result.add(section);
        } else {
          result.add(FormSection(
            sectionId: section.sectionId,
            title: section.title,
            formType: section.formType,
            fieldRefs: remainingRefs,
          ));
        }
      }
    }

    return result;
  }

  static bool _isSectionVisible({
    required FormSection section,
    required List<String> activeFormTypes,
    required CanonicalVisitData currentData,
    int? gestationalWeeks,
  }) {
    final id = section.sectionId;

    // birthPreparedness: ANC active + GA >= 28 weeks.
    // Prefer the screen-level gestationalWeeks (from PatientContext at launch)
    // over the in-form gestationalAge field the SK may not have entered yet.
    if (id == 'birthPreparedness') {
      if (!activeFormTypes.contains('anc')) return false;
      final weeks = gestationalWeeks ??
          () {
            final v = currentData.getValue('gestationalAge');
            return v is num
                ? v.toInt()
                : int.tryParse(v?.toString() ?? '') ?? 0;
          }();
      return weeks >= 28;
    }

    // pregnancyOutcome: always shown when pncMother is active.
    if (id == 'pregnancyOutcome') {
      return activeFormTypes.contains('pncMother');
    }

    // pncChild / pncNeonatal: child alive field must be 'yes'.
    if (id == 'pncChild' || id == 'pncNeonatal') {
      final alive = currentData.getValue('isChildAlive');
      return alive == 'yes' ||
          alive == true ||
          alive?.toString().toLowerCase() == 'yes';
    }

    // NCD bpReadings: show only when NCD active and ANC is NOT active.
    // When ANC is active, BP is collected in the ANC vitals section.
    if (id == 'bpReadings') {
      return activeFormTypes.contains('ncd') &&
          !activeFormTypes.contains('anc');
    }

    return true;
  }
}
