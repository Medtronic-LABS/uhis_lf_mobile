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
/// - `pregnancyOutcome`: shown on delivery visits; ordered before PNC sections.
/// - `pncChild` / `pncNeonatal`: only when `isChildAlive` == `'yes'`.
/// - NCD `bpReadings`: only when NCD active and ANC is NOT active.
abstract final class UnifiedSectionRules {
  UnifiedSectionRules._();

  /// Section IDs whose sections are pinned to the top as the "Vitals" group.
  ///
  /// Empty: each programme now owns its own vitals sections (ncdBiometrics,
  /// ancSpecificVitals, maternalHealthAssessment, iccmVitals, etc.) and
  /// commonVitals is no longer injected as a shared pre-section. All sections
  /// are rendered under their programme group header instead.
  static const _vitalsSectionIds = <String>{};

  /// Semantic field equivalence groups (cross-programme).
  ///
  /// When any field in a group is claimed, the entire group is pre-claimed so
  /// that two programmes that represent the same measurement with different
  /// field IDs do not both render a capture widget.
  ///
  /// BP and BG are intentionally allowed in every programme that lists them:
  /// ANC and NCD each keep their own widgets in multi-programme visits.
  static const List<Set<String>> _semanticFieldGroups = [
    // Height / weight / BMI are intentionally NOT cross-claimed: Android NCD
    // shows its own Biometric card even when ANC/PNC also capture them.
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
  ];

  /// BG aliases — claimed only within a single formType so ANC lab + NCD
  /// glucoseLog can each show BloodGlucoseEntry, while the bare `glucose`
  /// field is still suppressed next to `glucoseType` inside NCD.
  static const Set<String> _bloodGlucoseFieldIds = {
    'glucoseType',
    'glucose',
    'bloodSugar',
    'ancBloodGlucose',
    'fastingBloodSugar',
    'randomBloodSugar',
  };

  /// Biometrics shared by id across programmes — claimed only within a
  /// formType so NCD keeps Height/Weight/BMI even when ANC also has Weight.
  static const Set<String> _biometricFieldIds = {
    'height',
    'weight',
    'bmi',
  };

  /// Returns a human-readable description of which semantic groups had members
  /// present in [activeFieldIds].  Used by the debug log at form-open time.
  static List<String> mergedGroupDescriptions(Set<String> activeFieldIds) {
    const groupLabels = <Set<String>, String>{
      {'folicAcidTotalConsumed', 'folicAcidTablets'}: 'Folic acid consumed',
      {'ifaTotalConsumed', 'ifaTabletsConsumed', 'ifaTablets'}: 'IFA consumed',
      {'ifaProvided', 'ifaTabletsProvided'}: 'IFA provided',
      {'calciumTotalConsumed', 'calciumTabletsConsumed', 'calciumTablets'}: 'Calcium consumed',
      {'calciumProvided', 'calciumTabletsProvided'}: 'Calcium provided',
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

  /// Within one formType: claim BG field + aliases so BloodGlucoseEntry and
  /// bare `glucose` never both render in the same programme section.
  static void _claimBloodGlucoseLocal(String fieldId, Set<String> localClaimed) {
    if (!_bloodGlucoseFieldIds.contains(fieldId)) {
      localClaimed.add(fieldId);
      return;
    }
    localClaimed.addAll(_bloodGlucoseFieldIds);
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

    // ── Pass 2: non-vitals sections ─────────────────────────────────────────
    //
    // Delivery visit (pregnancyOutcome active): outcome sections come FIRST
    // (Android: document birth before mother/child PNC), then enrolled PNC,
    // then any other recommended forms. Routine visits keep enrolled →
    // recommended order.
    final hasPregnancyOutcome = activeFormTypes.contains('pregnancyOutcome');

    void collectFormType(
      String formType,
      SectionGroup sectionGroup,
      List<AnnotatedFormSection> sink,
    ) {
      // Per-programme claim set so BG (same field ids) can reappear under
      // ANC and NCD, while still collapsing aliases inside one programme.
      final localClaimed = <String>{};
      for (final section in config.forms[formType] ?? []) {
        if (_vitalsSectionIds.contains(section.sectionId)) continue;
        if (!_isSectionVisible(
          section: section,
          activeFormTypes: activeFormTypes,
          enrolledFormTypes: enrolledFormTypes,
          currentData: currentData,
          gestationalWeeks: gestationalWeeks,
        )) {
          continue;
        }

        // Claim while filtering so glucoseType collapses bare `glucose`
        // in the same section before it is kept in [remaining]. Height /
        // weight / BMI are also per-formType so NCD biometrics survive ANC.
        final remaining = <FieldRef>[];
        for (final r in section.fieldRefs) {
          if (localClaimed.contains(r.id)) continue;
          final perFormType = _bloodGlucoseFieldIds.contains(r.id) ||
              _biometricFieldIds.contains(r.id);
          if (!perFormType && claimedFieldIds.contains(r.id)) {
            continue;
          }
          remaining.add(r);
          if (_bloodGlucoseFieldIds.contains(r.id)) {
            _claimBloodGlucoseLocal(r.id, localClaimed);
          } else if (_biometricFieldIds.contains(r.id)) {
            localClaimed.add(r.id);
          } else {
            _claimField(r.id, localClaimed);
            _claimField(r.id, claimedFieldIds);
          }
        }
        if (remaining.isEmpty) continue;

        sink.add(AnnotatedFormSection(
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

    final outcomeFirstSections = <AnnotatedFormSection>[];
    if (hasPregnancyOutcome) {
      collectFormType(
        'pregnancyOutcome',
        SectionGroup.recommended,
        outcomeFirstSections,
      );
    }

    final enrolledPass = activeFormTypes.where(
      (ft) => enrolledFormTypes.contains(ft) && ft != 'pregnancyOutcome',
    );
    final recommendedPass = activeFormTypes.where(
      (ft) => !enrolledFormTypes.contains(ft) && ft != 'pregnancyOutcome',
    );

    for (final formType in enrolledPass) {
      collectFormType(formType, SectionGroup.enrolled, enrolledSections);
    }
    for (final formType in recommendedPass) {
      collectFormType(formType, SectionGroup.recommended, recommendedSections);
    }

    final result = [
      ...vitalsSections,
      ...outcomeFirstSections,
      ...enrolledSections,
      ...recommendedSections,
    ];
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
    if (section.formType == 'pregnancyOutcome') {
      // ignore: avoid_print
      print('[SectionVisibility] pregnancyOutcome section=$id '
          'activeFormTypes=$activeFormTypes '
          'containsPregnancyOutcome=${activeFormTypes.contains('pregnancyOutcome')}');
    }

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

    // pregnancyOutcome: only shown when the SK confirmed a delivery visit
    // (isDeliveryVisit=true in VisitFormScreen → 'pregnancyOutcome' added to
    // activeFormTypes by _toFormTypes). Never shown on routine PNC visits.
    if (id == 'pregnancyOutcome') {
      return activeFormTypes.contains('pregnancyOutcome');
    }

    // pregnancyOutcome sub-sections: gated by deliveryOutcomeType selection.
    // outcomeType is the picker itself — always shown when pregnancyOutcome active.
    // All other sub-sections only appear once an outcome type is chosen.
    if (section.formType == 'pregnancyOutcome' && id != 'outcomeType') {
      final outcome = currentData.getValue('deliveryOutcomeType')?.toString();
      // ignore: avoid_print
      print('[SectionVisibility] pregnancyOutcome sub-section=$id outcome=$outcome');
      if (outcome == null || outcome.isEmpty) return false;
      switch (id) {
        case 'maternalDeath':
          return outcome == 'maternalDeath';
        case 'abortion':
          return outcome == 'abortion';
        case 'deliveryOutcomes':
        case 'newbornDetails':
          return outcome == 'liveBirth' || outcome == 'stillbirth';
        case 'counsellingAdverseEvent':
          return true; // show counselling for all outcome types
        default:
          return true;
      }
    }

    // Combined delivery visit: mother/child PNC only after a delivery-path
    // outcome (live birth / stillbirth). Abortion and maternal death end the
    // pregnancy episode without opening PNC (Android PregnancyCohortRules).
    if (activeFormTypes.contains('pregnancyOutcome') &&
        (section.formType == 'pncMother' ||
            section.formType == 'pncChild' ||
            section.formType == 'pncNeonatal')) {
      final outcome = currentData.getValue('deliveryOutcomeType')?.toString();
      if (outcome != 'liveBirth' && outcome != 'stillbirth') {
        return false;
      }
    }

    // pncChild / pncNeonatal: child alive field must be 'yes'.
    if (id == 'pncChild' || id == 'pncNeonatal') {
      final alive = currentData.getValue('isChildAlive') ??
          currentData.getValue('babyAlive');
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

  // Android AssessmentRMNCHFragment.updateANCConditionalFieldVisibility().
  static const int _gaWeek12 = 12;
  static const int _gaWeek13 = 13;
  static const int _gaWeek24 = 24;
  static const int _gaWeek27 = 27;
  static const int _gaWeek28 = 28;
  static const int _gaWeek40 = 40;

  /// Form types where Android filters `isSummary == true` out of the fill
  /// form (`AssessmentRMNCHFragment` for anc/pncMother;
  /// `AssessmentPregnancyOutcomeFragment` for pregnancyOutcome).
  /// Childhood visit / NCD / TB keep isSummary fields on the fill form
  /// (flag means "also show on summary").
  static const Set<String> _rmnchSummaryOnlyFormTypes = {
    'anc',
    'pncMother',
    'pregnancyOutcome',
  };

  /// Option name Android uses inside the NCD symptoms dialog to reveal the
  /// free-text "Any new or worsening symptoms" field
  /// (`BDNCDAssessmentFragment.hideOrShowAnyNewWorseningSymptomView`).
  static const String ncdAnyNewOrWorseningSymptomOption =
      'Any new or worsening symptoms';

  /// Returns whether [field] should render, given the current form [data]
  /// and the [rulesByTargetId] lookup built by
  /// `FormConfig.buildVisibilityRules`.
  ///
  /// Evaluation order:
  /// 0. `isSummary` fields — hide only on RMNCH fill forms (Android parity).
  /// 1. NCD `newWorseningSymptoms` — shown when that option is ticked in
  ///    `ncdSymptoms` (Android code path, not JSON `condition`).
  /// 2. A generic `condition` rule targeting this field (another field's
  ///    value equals a declared trigger value) — the common case, covers
  ///    ~96 Yes/No/Other-dependent follow-up fields.
  /// 3. The obstetric-history progressive-disclosure chain (Gravida → Parity
  ///    → Living Children → Age of Last Child) — a separate mechanism from
  ///    (2): the field library only tags `compositeRole` (trigger/member),
  ///    the actual reveal thresholds are hand-ported here from the design
  ///    mockup's `handleGravidaChange()`/`handleParityChange()`/
  ///    `handleLivingChange()` JS, since the JSON doesn't encode them.
  ///    Other `compositeGroup` values (e.g. supplement consumed/provided
  ///    pairs) are unrelated dedup metadata handled elsewhere and are not
  ///    interpreted here.
  /// 4. ANC gestational-age / visit-number gates — only when [formType] is
  ///    `anc` (must not hide NCD biometrics).
  /// 5. The field's own declared base `visibility` ("visible"/"gone").
  ///
  /// [gestationalWeeks] — current GA from LMP/snapshot; null when unknown.
  /// [ancVisitNumber] — 1-based ANC visit count; null treated as visit 1 for
  /// height / BMI / previous-pregnancy-complications gates.
  /// [formType] — owning programme layout key (e.g. `ncd`, `anc`).
  static bool isFieldVisible({
    required FieldDef field,
    required CanonicalVisitData data,
    required Map<String, List<FieldVisibilityRule>> rulesByTargetId,
    int? gestationalWeeks,
    int? ancVisitNumber,
    String? formType,
  }) {
    if (field.isSummary &&
        formType != null &&
        _rmnchSummaryOnlyFormTypes.contains(formType)) {
      return false;
    }

    // Android BDNCD: free-text field appears only when the matching symptom
    // checkbox is selected — not merely when hasSymptoms == Yes.
    if (field.id == 'newWorseningSymptoms') {
      return _ncdSymptomsIncludeAnyNewOrWorsening(data);
    }

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

    // ANC visit/GA gates apply only inside the ANC layout — never to NCD
    // height/weight/BMI (Android BDNCDAssessmentFragment shows Biometric always).
    if (formType == 'anc') {
      final ancGate = _ancConditionalVisibility(
        fieldId: field.id,
        data: data,
        gestationalWeeks: gestationalWeeks,
        ancVisitNumber: ancVisitNumber,
      );
      if (ancGate != null) return ancGate;
    }

    return field.visibility != 'gone';
  }

  /// True when the NCD symptoms multi-select includes the Android
  /// "Any new or worsening symptoms" option (by id or display name).
  static bool _ncdSymptomsIncludeAnyNewOrWorsening(CanonicalVisitData data) {
    final raw = data.getValue('ncdSymptoms');
    if (raw == null) return false;
    final values = raw is List
        ? raw.map((e) => e.toString()).toList()
        : <String>[raw.toString()];
    final needle = ncdAnyNewOrWorseningSymptomOption.toLowerCase();
    return values.any((v) {
      final s = v.trim().toLowerCase();
      return s == needle ||
          s == 'anyneworworseningsymptoms' ||
          s == 'any_new_or_worsening_symptoms';
    });
  }

  /// Android SPICE ANC field gates. Returns `null` when [fieldId] is not an
  /// ANC-gated field (caller falls through to base visibility).
  static bool? _ancConditionalVisibility({
    required String fieldId,
    required CanonicalVisitData data,
    int? gestationalWeeks,
    int? ancVisitNumber,
  }) {
    final visit = ancVisitNumber ?? 1;
    final ga = gestationalWeeks;
    final gravida =
        int.tryParse(data.getValue('gravida')?.toString() ?? '') ?? 0;

    switch (fieldId) {
      // Flutter-only alias of urinaryAlbumin — Android ANC has albumin only.
      case 'urineProtein':
        return false;

      // Android AssessmentRMNCHFragment: hide until an illness other than
      // "none" is selected; options are then the selected illnesses +
      // "Not taking any treatment" (built at render time).
      case 'pregnantWomanOnTreatment':
        return hasAncExistingIllnessForTreatment(data);

      case 'previousPregnancyComplications':
        return visit == 1 && gravida > 1;

      case 'height':
        return visit == 1;

      case 'bmi':
        return visit == 1 && (ga == null || ga < _gaWeek12);

      case 'edema':
        return ga != null && ga >= _gaWeek12;

      case 'fundalHeight':
        return ga != null && ga >= _gaWeek24;

      case 'folicAcidTablets':
      case 'folicAcidTotalConsumed':
      case 'folicAcidProvided':
        // GA unknown → show (Android: null || <= 12).
        return ga == null || ga <= _gaWeek12;

      case 'ifaTablets':
      case 'ifaTotalConsumed':
      case 'ifaProvided':
      case 'ifaTabletsConsumed':
      case 'ifaTabletsProvided':
        // GA unknown → show (Android: null || > 12).
        return ga == null || ga > _gaWeek12;

      case 'calciumTablets':
      case 'calciumTotalConsumed':
      case 'calciumProvided':
      case 'calciumTabletsConsumed':
      case 'calciumTabletsProvided':
        return ga == null || ga > _gaWeek12;

      case 'dangerSignsExperienced12':
        return ga == null || ga <= _gaWeek12;

      case 'dangerSignsExperienced13To27':
        return ga != null && ga >= _gaWeek13 && ga <= _gaWeek27;

      case 'dangerSignsExperienced28To40':
        return ga != null && ga >= _gaWeek28 && ga <= _gaWeek40;

      case 'ultrasound':
      case 'ancFromMedicalDoctor':
        return ga != null && ga >= _gaWeek28;

      default:
        return null;
    }
  }

  /// True when ANC existing-illness has at least one non-`none` selection.
  static bool hasAncExistingIllnessForTreatment(CanonicalVisitData data) {
    final raw = data.getValue('pregnantWomanExistingIllness');
    if (raw is! List || raw.isEmpty) return false;
    final ids = raw.map((e) => e.toString().toLowerCase()).toList();
    if (ids.any((id) => id == 'none')) return false;
    return ids.isNotEmpty;
  }

  /// Android on-treatment dialog options: selected illnesses + the static
  /// "Not taking any treatment" option from [onTreatmentField].
  static List<FieldOption> ancOnTreatmentOptions({
    required FieldDef illnessField,
    required FieldDef onTreatmentField,
    required CanonicalVisitData data,
  }) {
    final selected = data.getValue('pregnantWomanExistingIllness');
    final selectedIds = selected is List
        ? selected.map((e) => e.toString()).toSet()
        : <String>{};
    final illnessOpts = illnessField.options
        .where(
          (o) =>
              selectedIds.contains(o.id) ||
              selectedIds.contains(o.name) ||
              selectedIds.any(
                (s) => s.toLowerCase() == o.id.toLowerCase(),
              ),
        )
        .where((o) => o.id.toLowerCase() != 'none')
        .toList();
    final noneOpts = onTreatmentField.options
        .where((o) => o.id.toLowerCase() == 'none')
        .toList();
    return [...illnessOpts, ...noneOpts];
  }
}
