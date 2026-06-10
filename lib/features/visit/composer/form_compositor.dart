/// Form compositor — pure function that assembles a [ComposedForm] from a list
/// of activated pathways.
///
/// Engineering Design Standards:
///   - Pure function: no I/O, no clock, no side effects.
///   - Depends on [SectionRegistry] (data only); never on widgets.
///   - All deduplication is deterministic: the first (lowest priority) section
///     that owns a fieldId wins ownership; later sections mark it shared.
library;

import '../pathway/pathway_engine.dart';
import '../../../core/models/programme.dart';
import 'form_section.dart';
import 'section_registry.dart';

// ── Output types ──────────────────────────────────────────────────────────────

/// The assembled form, ready for the sectioned assessment screen to render.
class ComposedForm {
  const ComposedForm({
    required this.sections,
    required this.fieldOwnership,
  });

  /// Ordered, deduplicated list of sections to render.
  ///
  /// Sorted by [FormSection.priority] ascending.  Sections are unique by
  /// [FormSection.sectionId].
  final List<FormSection> sections;

  /// Maps each unique [FieldDef.fieldId] to the [FormSection.sectionId] that
  /// owns (renders) it.  Shared occurrences in later sections are stripped.
  final Map<String, String> fieldOwnership;

  @override
  String toString() => 'ComposedForm(sections=${sections.map((s) => s.sectionId).join(", ")})';
}

// ── Compositor ────────────────────────────────────────────────────────────────

/// Assembles a [ComposedForm] from a list of [ActivatedPathway]s.
///
/// Algorithm:
/// 1. Derive the set of activated [Programme]s from [pathways].
/// 2. Collect all [FormSection]s from [SectionRegistry] whose programme set
///    intersects the activated set.
/// 3. Sort sections by [FormSection.priority] (ascending).
/// 4. Build [fieldOwnership]: iterate sections in priority order; first
///    section to claim a fieldId owns it.  The same fieldId in a later
///    section is already in [FormSection.sharedFieldIds] by registry
///    convention, but the compositor enforces this invariant independently.
/// 5. Defensive cross-section reveal: if coughDays ≥ 14 is present in the
///    pathway trigger symptoms and `tb-screen-detail` is not already included,
///    add it. The engine will have caught this, but the compositor handles it
///    defensively.
class FormCompositor {
  FormCompositor._();

  /// Compose a [ComposedForm] from the given activated pathways.
  ///
  /// Pure function: result depends only on [pathways] and [SectionRegistry].
  static ComposedForm compose(List<ActivatedPathway> pathways) {
    // 1. Derive activated programmes.
    final activatedProgrammes = <Programme>{};
    for (final pathway in pathways) {
      activatedProgrammes.add(pathway.programme);
    }

    // 2. Collect matching sections (already sorted by priority).
    final matchingSections =
        SectionRegistry.forProgrammes(activatedProgrammes);

    // 5. Defensive cross-section reveal for TB.
    //    If any pathway carries 'cough_over_2_weeks' or 'cough_over_14_days'
    //    in its triggerSymptoms, and TB is not already active, add tb-screen-detail.
    final hasCoughTrigger = pathways.any(
      (p) =>
          p.triggerSymptoms.contains('cough_over_2_weeks') ||
          p.triggerSymptoms.contains('cough_over_14_days'),
    );
    final hasTbSection =
        matchingSections.any((s) => s.sectionId == 'tb-screen-detail');

    List<FormSection> sections;
    if (hasCoughTrigger && !hasTbSection) {
      final tbSection = SectionRegistry.byId('tb-screen-detail');
      if (tbSection != null) {
        sections = [...matchingSections, tbSection]
          ..sort((a, b) => a.priority.compareTo(b.priority));
      } else {
        sections = matchingSections;
      }
    } else {
      sections = matchingSections;
    }

    // 3. Deduplicate sections (byId — should already be unique from registry,
    //    but guard against test helpers adding duplicates).
    final seenSectionIds = <String>{};
    final dedupedSections = <FormSection>[];
    for (final section in sections) {
      if (seenSectionIds.add(section.sectionId)) {
        dedupedSections.add(section);
      }
    }

    // 4. Build field ownership map: first section (lowest priority) wins.
    final fieldOwnership = <String, String>{}; // fieldId → sectionId
    for (final section in dedupedSections) {
      for (final field in section.fields) {
        // Only claim ownership if not already owned by an earlier section.
        fieldOwnership.putIfAbsent(field.fieldId, () => section.sectionId);
      }
    }

    return ComposedForm(
      sections: List.unmodifiable(dedupedSections),
      fieldOwnership: Map.unmodifiable(fieldOwnership),
    );
  }
}
