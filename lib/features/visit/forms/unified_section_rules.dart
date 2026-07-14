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
  /// - `birthPreparedness`: `anc` active (no GA threshold).
///   [gestationalWeeks] (from PatientContext at launch) takes precedence over
///   the in-form `gestationalAge` field the SK may not have filled yet.
/// - `pregnancyOutcome`: always shown when `pncMother` active.
/// - `pncChild` / `pncNeonatal`: only when `isChildAlive` == `'yes'`.
/// - NCD `bpReadings`: only when NCD active and ANC is NOT active.
abstract final class UnifiedSectionRules {
  UnifiedSectionRules._();

  /// Section IDs whose sections are pinned to the top as the "Vitals" group.
  ///
  /// `commonVitals` captures Height, Weight, BMI, Blood Pressure exactly once.
  /// ANC-specific clinical exam fields (urineProtein, fundalHeight,
  /// fetalMovement) live in `ancSpecificVitals`; NCD has no extra vitals.
  /// Lab investigations (urinaryAlbumin, urinarySugar, hemoglobin,
  /// blood glucose) live in `labInvestigations`.
  static const _vitalsSectionIds = {'commonVitals'};

  /// Semantic field equivalence groups.
  ///
  /// When any field in a group is claimed, the entire group is pre-claimed so
  /// that two programmes that represent the same measurement with different
  /// field IDs do not both render a capture widget.
  ///
  /// BP: `commonVitals` uses {bloodPressure, systolic, diastolic}; cataract's
  ///   bpLog uses {bpLogDetails}. Claiming the common set pre-claims bpLogDetails
  ///   so cataract does not show a duplicate BP widget.
  /// Height / Weight / BMI: commonVitals claims these; any programme-specific
  ///   section that also lists them gets deduplicated.
  /// Glucose: NCD glucoseLog uses {glucoseType} rendered as BloodGlucoseEntry
  ///   which internally handles the glucose value too.  All aliases (bloodSugar,
  ///   fastingBloodSugar, randomBloodSugar, ancBloodGlucose, glucose) are merged
  ///   into one group so claiming glucoseType pre-claims every alias — preventing
  ///   the bare `glucose` field from double-rendering alongside BloodGlucoseEntry.
  static const List<Set<String>> _semanticFieldGroups = [
    // ── Blood pressure ──────────────────────────────────────────────────────
    {'bloodPressure', 'systolic', 'diastolic', 'bpLogDetails'},
    // ── Biometrics (all now captured in commonVitals) ───────────────────────
    {'height'},
    {'weight'},
    {'bmi'},
    {'pulse'},
    // ── Folic acid supplements ───────────────────────────────────────────────
    {'folicAcidTotalConsumed', 'folicAcidTablets'},
    {'folicAcidProvided'},
    // ── IFA / iron supplements ──────────────────────────────────────────────
    {'ifaTotalConsumed', 'ifaTabletsConsumed', 'ifaTablets'},
    {'ifaProvided', 'ifaTabletsProvided'},
    // ── Calcium supplements ─────────────────────────────────────────────────
    {'calciumTotalConsumed', 'calciumTabletsConsumed', 'calciumTablets'},
    {'calciumProvided', 'calciumTabletsProvided'},
    // ── Blood glucose — combined BloodGlucoseEntry widget ─────────────────
    // glucoseType renders as BloodGlucoseEntry (toggle FBS/RBS + numeric).
    // Used in both ANC labInvestigations and NCD glucoseLog.
    // glucose / bloodSugar / ancBloodGlucose are aliases — claiming glucoseType
    // pre-claims every alias so no duplicate widget can appear.
    {'glucoseType', 'glucose', 'bloodSugar', 'ancBloodGlucose'},
  ];

  /// Returns a human-readable description of which semantic groups had members
  /// present in [activeFieldIds].  Used by the debug log at form-open time.
  static List<String> mergedGroupDescriptions(Set<String> activeFieldIds) {
    const groupLabels = <Set<String>, String>{
      {'bloodPressure', 'systolic', 'diastolic', 'bpLogDetails'}: 'BP (systolic|diastolic)',
      {'folicAcidTotalConsumed', 'folicAcidTablets'}: 'Folic acid consumed',
      {'ifaTotalConsumed', 'ifaTabletsConsumed', 'ifaTablets'}: 'IFA consumed',
      {'ifaProvided', 'ifaTabletsProvided'}: 'IFA provided',
      {'calciumTotalConsumed', 'calciumTabletsConsumed', 'calciumTablets'}: 'Calcium consumed',
      {'calciumProvided', 'calciumTabletsProvided'}: 'Calcium provided',
      {'glucoseType', 'glucose', 'bloodSugar', 'ancBloodGlucose'}: 'Blood glucose (NCD combined)',
    };
    final merged = <String>[];
    for (final entry in groupLabels.entries) {
      final presentCount = entry.key.where(activeFieldIds.contains).length;
      if (presentCount > 1) {
        merged.add(entry.value);
      }
    }
    return merged;
  }

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
          enrolledFormTypes: enrolledFormTypes,
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
            enrolledFormTypes: enrolledFormTypes,
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

    // Debug log is intentionally NOT called here — the caller
    // (UnifiedFormScreen) gates it so it only fires when the section shape
    // actually changes, suppressing per-field-change spam.

    return result;
  }

  static void debugLogSections(
      List<AnnotatedFormSection> result, int uniqueFieldCount) {
    // Collect all field IDs that are present across ALL sections (before
    // dedup) so mergedGroupDescriptions can flag cross-program duplicates.
    final allFieldIds = <String>{};
    for (final a in result) {
      for (final r in a.section.fieldRefs) {
        allFieldIds.add(r.id);
      }
    }
    final merged = mergedGroupDescriptions(allFieldIds);
    // ignore: avoid_print
    print('[Form] ── Section breakdown '
        '(${result.length} sections · $uniqueFieldCount unique fields) ──');
    if (merged.isNotEmpty) {
      // ignore: avoid_print
      print('[Form]   📎 Common fields merged (captured once): ${merged.join(', ')}');
    }

    String? lastHeader;
    for (final a in result) {
      final formType = a.section.formType;
      final programme = _programmeLabel(formType);
      final header = switch (a.group) {
        SectionGroup.vitals => '📊 COMMON VITALS',
        SectionGroup.enrolled => '✅ $programme (enrolled)',
        SectionGroup.recommended => '🔵 $programme (recommended)',
      };
      if (header != lastHeader) {
        // ignore: avoid_print
        print('[Form]   $header');
        lastHeader = header;
      }
      final fields = a.section.fieldRefs.map((r) => r.id).join(' · ');
      // ignore: avoid_print
      print('[Form]     · ${a.section.sectionId}: $fields');
    }
    // ignore: avoid_print
    print('[Form] ── end ──────────────────────────────────────────────');
  }

  /// Returns a human-readable programme name from a formType key.
  static String _programmeLabel(String formType) => switch (formType) {
        'commonVitals' => 'Vitals',
        'anc' => 'ANC',
        'pncMother' => 'PNC (Mother)',
        'pncChild' => 'PNC (Child)',
        'pncNeonatal' => 'PNC (Neonate)',
        'pregnancyOutcome' => 'Pregnancy Outcome',
        'ncd' => 'NCD',
        'cataract' => 'Cataract',
        'eye_care' => 'Eye Care',
        'family_planning' => 'Family Planning',
        'pwProfile' => 'PW Profile',
        _ => formType.toUpperCase(),
      };

  static bool _isSectionVisible({
    required FormSection section,
    required List<String> activeFormTypes,
    required CanonicalVisitData currentData,
    List<String> enrolledFormTypes = const [],
    int? gestationalWeeks,
  }) {
    final id = section.sectionId;

    // pregnancyDetailsAndHistory: only for first-time pregnancy registration.
    // Once PW/ANC is on file the LMP cannot be re-edited — hide on all
    // subsequent visits where the patient is already enrolled in ANC or pwProfile.
    if (id == 'pregnancyDetailsAndHistory') {
      return !enrolledFormTypes.contains('anc') &&
          !enrolledFormTypes.contains('pwProfile');
    }

    // birthPreparedness: shown whenever ANC is active.
    if (id == 'birthPreparedness') {
      return activeFormTypes.contains('anc');
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

/// Field-level (as opposed to [UnifiedSectionRules]'s section-level)
/// conditional-visibility evaluation — replaces what used to be silently
/// discarded `condition`/`visibility`/`compositeGroup` data from
/// `field_library.json` (see `FieldDef.fromJson`, `FormConfig.
/// buildVisibilityRules`).
abstract final class FieldVisibilityRules {
  FieldVisibilityRules._();

  /// Returns whether [field] should render, given the current form [data]
  /// and the [rulesByTargetId] lookup built by
  /// `FormConfig.buildVisibilityRules`.
  ///
  /// Evaluation order:
  /// 1. A generic `condition` rule targeting this field (another field's
  ///    value equals a declared trigger value) — the common case, covers
  ///    ~96 Yes/No/Other-dependent follow-up fields.
  /// 2. The obstetric-history progressive-disclosure chain (Gravida → Parity
  ///    → Living Children → Age of Last Child) — a separate mechanism from
  ///    (1): the field library only tags `compositeRole` (trigger/member),
  ///    the actual reveal thresholds are hand-ported here from the design
  ///    mockup's `handleGravidaChange()`/`handleParityChange()`/
  ///    `handleLivingChange()` JS, since the JSON doesn't encode them.
  ///    Other `compositeGroup` values (e.g. supplement consumed/provided
  ///    pairs) are unrelated dedup metadata handled elsewhere and are not
  ///    interpreted here.
  /// 3. The field's own declared base `visibility` ("visible"/"gone").
  static bool isFieldVisible({
    required FieldDef field,
    required CanonicalVisitData data,
    required Map<String, List<FieldVisibilityRule>> rulesByTargetId,
  }) {
    final rules = rulesByTargetId[field.id];
    if (rules != null && rules.isNotEmpty) {
      for (final rule in rules) {
        final driverValue = data.getValue(rule.driverId)?.toString();
        if (rule.matches(driverValue)) {
          return rule.visibility == 'visible';
        }
      }
      // No rule's trigger value matched — fall through to base visibility.
    }

    if (field.compositeGroup == 'obstetricHistory') {
      int asInt(String fieldId) =>
          int.tryParse(data.getValue(fieldId)?.toString() ?? '') ?? 0;
      switch (field.id) {
        case 'gravida':
          // Trigger — always visible once the section itself renders,
          // regardless of its own base visibility (declared "gone" in the
          // JSON, since Android reveals it via app-side composite-group
          // handling this Flutter port doesn't otherwise have visibility into).
          return true;
        case 'parity':
          return asInt('gravida') >= 2;
        case 'livingChildren':
          return asInt('parity') >= 1;
        case 'ageOfLastChild':
          return asInt('livingChildren') >= 1;
      }
    }

    return field.visibility != 'gone';
  }
}
