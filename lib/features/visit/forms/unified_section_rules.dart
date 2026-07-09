import 'canonical_visit_data.dart';
import 'form_config.dart';

/// Section-group tag attached to each [FormSection] in the result of
/// [UnifiedSectionRules.activeSections].  Consumers use this to render
/// group-divider rows (Vitals / Enrolled Programmes / Recommended Programmes).
enum SectionGroup { vitals, enrolled, recommended }

/// A [FormSection] annotated with its [SectionGroup].
class AnnotatedFormSection {
  const AnnotatedFormSection({required this.section, required this.group});

  final FormSection section;
  final SectionGroup group;
}

/// Pure-Dart rules engine: given active formTypes + current field values,
/// returns the ordered, deduplicated list of [AnnotatedFormSection]s to render.
///
/// ## Ordering contract
///
/// 1. **Vitals** — sections whose [FormSection.sectionId] is in
///    [_vitalsSectionIds] are collected first, across all active form types.
///    Their field IDs are claimed before any other pass so they never appear
///    duplicated in programme sections.
/// 2. **Enrolled programme sections** — sections from form types listed in
///    [enrolledFormTypes] are collected next, deduplicating against vitals.
/// 3. **Recommended programme sections** — sections from the remaining
///    (pathway-recommended) form types are collected last.
///
/// ## Dedup rule
///
/// A fieldId is claimed the first time a section that owns it is added to the
/// result. All later sections that reference the same fieldId have it stripped.
/// A section left with no remaining fieldRefs is omitted entirely.
///
/// ## Conditional visibility rules
///
/// - `birthPreparedness`: `anc` active AND gestational age ≥ 28 weeks.
///   [gestationalWeeks] (from PatientContext at launch) takes precedence over
///   the in-form `gestationalAge` field the SK may not have filled yet.
/// - `pregnancyOutcome`: always shown when `pncMother` active.
/// - `pncChild` / `pncNeonatal`: only when `isChildAlive` == `'yes'`.
/// - NCD `bpReadings`: only when NCD active and ANC is NOT active.
abstract final class UnifiedSectionRules {
  UnifiedSectionRules._();

  /// Section IDs whose sections are pinned to the top as the "Vitals" group.
  ///
  /// Chosen because they capture the physical measurements (weight, BP, BMI,
  /// pulse, temperature) that are identical across all clinical programmes.
  /// ANC uses `todaysVitals`; NCD/cataract use `bpLog`.
  static const _vitalsSectionIds = {'todaysVitals', 'bpLog'};

  /// Semantic field equivalence groups.
  ///
  /// When any field in a group is claimed, the entire group is pre-claimed so
  /// that two programmes that represent the same measurement with different
  /// field IDs do not both render a capture widget.
  ///
  /// Example: ANC uses {bloodPressure, systolic, diastolic} for BP entry while
  /// NCD uses {bpLogDetails}.  Claiming one set pre-claims the other, so only
  /// the first-encountered BP section renders a BP widget.
  static const List<Set<String>> _semanticFieldGroups = [
    {'bloodPressure', 'systolic', 'diastolic', 'bpLogDetails'},
  ];

  /// Claim [fieldId] in [claimed] and also pre-claim every field in the same
  /// semantic equivalence group (if any).
  static void _claimField(String fieldId, Set<String> claimed) {
    claimed.add(fieldId);
    for (final group in _semanticFieldGroups) {
      if (group.contains(fieldId)) {
        claimed.addAll(group);
        return;
      }
    }
  }

  /// Returns ordered, deduplicated [AnnotatedFormSection]s for rendering.
  ///
  /// [enrolledFormTypes] — the expanded formType keys (from `_toFormTypes()`)
  /// of programmes the patient is already enrolled in.  These sections are
  /// rendered between Vitals and the pathway-recommended sections.
  static List<AnnotatedFormSection> activeSections({
    required FormConfig config,
    required List<String> activeFormTypes,
    required CanonicalVisitData currentData,
    int? gestationalWeeks,
    List<String> enrolledFormTypes = const [],
  }) {
    final claimedFieldIds = <String>{};
    final vitalsSections = <AnnotatedFormSection>[];
    final enrolledSections = <AnnotatedFormSection>[];
    final recommendedSections = <AnnotatedFormSection>[];

    // ── Pass 1: vitals sections (pinned first, claimed first) ──────────────
    for (final formType in activeFormTypes) {
      for (final section in config.forms[formType] ?? []) {
        if (!_vitalsSectionIds.contains(section.sectionId)) { continue; }
        if (!_isSectionVisible(
          section: section,
          activeFormTypes: activeFormTypes,
          currentData: currentData,
          gestationalWeeks: gestationalWeeks,
        )) { continue; }

        final remaining =
            section.fieldRefs.where((r) => !claimedFieldIds.contains(r.id)).toList();
        if (remaining.isEmpty) { continue; }
        for (final ref in remaining) { _claimField(ref.id, claimedFieldIds); }

        vitalsSections.add(AnnotatedFormSection(
          section: remaining.length == section.fieldRefs.length
              ? section
              : FormSection(
                  sectionId: section.sectionId,
                  title: section.title,
                  formType: section.formType,
                  fieldRefs: remaining,
                ),
          group: SectionGroup.vitals,
        ));
      }
    }

    // ── Pass 2: non-vitals sections — enrolled first, then recommended ─────
    //
    // Preserve the relative order within each group by walking activeFormTypes
    // twice (enrolled-only, then non-enrolled-only).
    final enrolledPass = activeFormTypes.where(enrolledFormTypes.contains);
    final recommendedPass =
        activeFormTypes.where((ft) => !enrolledFormTypes.contains(ft));

    for (final group in [
      (enrolledPass, SectionGroup.enrolled),
      (recommendedPass, SectionGroup.recommended),
    ]) {
      final (formTypes, sectionGroup) = group;
      for (final formType in formTypes) {
        for (final section in config.forms[formType] ?? []) {
          if (_vitalsSectionIds.contains(section.sectionId)) { continue; }
          if (!_isSectionVisible(
            section: section,
            activeFormTypes: activeFormTypes,
            currentData: currentData,
            gestationalWeeks: gestationalWeeks,
          )) { continue; }

          final remaining = section.fieldRefs
              .where((r) => !claimedFieldIds.contains(r.id))
              .toList();
          if (remaining.isEmpty) { continue; }
          for (final ref in remaining) { _claimField(ref.id, claimedFieldIds); }

          (sectionGroup == SectionGroup.enrolled
                  ? enrolledSections
                  : recommendedSections)
              .add(AnnotatedFormSection(
            section: remaining.length == section.fieldRefs.length
                ? section
                : FormSection(
                    sectionId: section.sectionId,
                    title: section.title,
                    formType: section.formType,
                    fieldRefs: remaining,
                  ),
            group: sectionGroup,
          ));
        }
      }
    }

    final result = [...vitalsSections, ...enrolledSections, ...recommendedSections];

    // Debug: log section ordering and field counts.
    // ignore: avoid_print
    print('[UnifiedSectionRules] activeSections result '
        '(${result.length} sections, '
        '${claimedFieldIds.length} unique field IDs):');
    for (final a in result) {
      final ids = a.section.fieldRefs.map((r) => r.id).join(', ');
      // ignore: avoid_print
      print('  [${a.group.name}] ${a.section.sectionId} '
          '(${a.section.formType}) → [$ids]');
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
    if (id == 'bpReadings') {
      return activeFormTypes.contains('ncd') &&
          !activeFormTypes.contains('anc');
    }

    return true;
  }
}
