import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/clinical/assessment_thresholds.dart';
import '../../../core/clinical/pnc_mandatory_rules.dart';
import '../../../core/widgets/gestational_age_card.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/preferences/ai_feature_toggles_notifier.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/form_fields/age_or_dob_field.dart';
import '../widgets/form_fields/radio_form_field.dart';
import 'canonical_visit_data.dart';
import 'childhood_visit.dart';
import 'form_config.dart';
import 'form_field_visuals.dart';
import '../../scribe/form_field_schema_builder.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/widgets/ai_scribe_banner.dart';
import 'triage_symptom_mapper.dart';
import 'unified_form_notifier.dart';
import 'unified_section_rules.dart';
import 'vitals_trend.dart';

/// Returns the `formType_sectionId_fieldId`-scoped key of the first field in
/// [errors], walking [annotated] and each section's `fieldRefs` in the same
/// visual order the form renders them in (see
/// [UnifiedSectionRules.activeSections]). Scoped — not just the bare field id
/// — because the same field id (e.g. "weight") can legitimately appear in
/// more than one concurrently-mounted section on a combined-programme visit;
/// the scoping must match how `_SectionCard` registers its anchor keys.
/// Returns `null` when no ordinary field id in [errors] maps to a rendered
/// section — e.g. when the only error belongs to the dynamic newborn-details
/// cards, which have no single field anchor and are scrolled to at the
/// section level instead.
String? firstErrorFieldId(
  List<AnnotatedFormSection> annotated,
  Set<String> errors,
) {
  for (final a in annotated) {
    if (a.section.sectionId == 'newbornDetails' &&
        a.section.formType == 'pregnancyOutcome') {
      continue;
    }
    for (final ref in a.section.fieldRefs) {
      if (errors.contains(ref.id)) {
        return '${a.section.formType}_${a.section.sectionId}_${ref.id}';
      }
    }
  }
  return null;
}

/// JSON-driven assessment form.
///
/// Reads [FormConfig] from assets, applies [UnifiedSectionRules] to produce
/// an ordered, deduplicated section list, and renders each field using the
/// appropriate existing field widget. Delegates state to [UnifiedFormNotifier].
///
/// ## Section ordering
///
/// 1. **Vitals** — BP, weight, and other physical measurements, always first.
/// 2. **Enrolled programmes** — sections from [enrolledFormTypes] come next.
/// 3. **Recommended programmes** — new pathway-activated sections follow.
///
/// Triage symptoms selected in Step 1 are surfaced inline under each programme
/// divider (see [_ProgrammeDivider]) rather than in a single top banner, so the
/// SK sees only the symptoms relevant to the programme being assessed.
///
/// The caller wraps this widget in a [ChangeNotifierProvider<UnifiedFormNotifier>]
/// and supplies [onSubmitComplete] to handle post-submit navigation.
class UnifiedFormScreen extends StatefulWidget {
  const UnifiedFormScreen({
    super.key,
    required this.activeFormTypes,
    required this.onSubmitComplete,
    this.gestationalWeeks,
    this.lmpMs,
    this.eddMs,
    this.ageInMonths,
    this.enrolledFormTypes = const [],
    this.confirmedSymptoms = const [],
    this.aiPickedSymptoms = const {},
  });

  /// Ordered formType keys (e.g. `['anc', 'ncd']`) from activated pathways.
  final List<String> activeFormTypes;

  /// Called after [UnifiedFormNotifier.submit] succeeds. Navigation lives here.
  final VoidCallback onSubmitComplete;

  /// Passed to [UnifiedSectionRules] / ANC field GA gates. Prefer notifier
  /// value after [UnifiedFormNotifier.loadPregnancyData] resolves.
  final int? gestationalWeeks;

  /// Optional LMP/EDD epoch-ms already resolved by VisitFlow from the
  /// pregnancy snapshot — seeds the gestational-age card when the notifier
  /// lookup races or is keyed under memberId.
  final int? lmpMs;
  final int? eddMs;

  /// Child's age in whole months (from DOB). Drives childhood-visit age bands
  /// and weight validation. Null when unknown / not a child visit.
  final int? ageInMonths;

  /// FormType keys of programmes the patient is already enrolled in.
  /// These sections render after the Vitals group and before recommended ones.
  final List<String> enrolledFormTypes;

  /// Symptom codes selected in Step 1 (triage).  Displayed read-only at the
  /// top of the form and seeded into [CanonicalVisitData] so section rules can
  /// drive conditional visibility.
  final List<String> confirmedSymptoms;

  /// Subset of [confirmedSymptoms] pre-selected by the AI Scribe.
  /// Used to colour AI-sourced chips purple in the programme divider strips.
  final Set<String> aiPickedSymptoms;

  @override
  State<UnifiedFormScreen> createState() => _UnifiedFormScreenState();
}

class _UnifiedFormScreenState extends State<UnifiedFormScreen> {
  FormConfig? _config;
  bool _configLoading = true;
  Object? _configError;
  final ScrollController _scrollCtrl = ScrollController();

  // Activates the numeric-range `validator:`s already wired on individual
  // TextFormFields (e.g. _numericRangeValidator) — a FormFieldValidator only
  // ever runs inside a Form.validate() call.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Used to suppress duplicate [Form] debug logs — only log when the section
  // count or field count actually changes between rebuilds.
  int _lastLoggedSectionCount = -1;
  int _lastLoggedFieldCount = -1;

  /// Prior ANC visit snapshots for the vitals-trend card (oldest-first).
  /// Loaded once after init; empty until then / for non-ANC visits.
  List<VisitVitals> _priorAncVisits = const [];

  /// Completed ANC count from pregnancy snapshot (Spice ancVisitNo).
  int? _ancVisitNoFromSnapshot;

  /// Completed PNC mother count from pregnancy snapshot (Spice pncVisitNo).
  int? _pncVisitNoFromSnapshot;

  /// Weight (kg) from the patient's most-recent prior visit across ALL
  /// programme types — used for the weight-delta badge.  `null` until loaded.
  double? _lastRecordedWeight;

  // One GlobalKey per section — used to scroll to the first error section
  // on submit so the SK doesn't have to hunt for the highlighted field.
  final Map<String, GlobalKey> _sectionKeys = {};

  // One GlobalKey per field id — lets submit-time validation scroll straight
  // to the specific missing field instead of just its (possibly tall) section.
  final Map<String, GlobalKey> _fieldKeys = {};

  GlobalKey _fieldKeyFor(String fieldId) =>
      _fieldKeys.putIfAbsent(fieldId, GlobalKey.new);

  /// Composite rows (BP+pulse, glucose pair, height+weight pair, supplement
  /// pairs) render one anchor for several field ids — aliasing lets an error
  /// on any absorbed id (e.g. `diastolic`) still resolve to the shared card.
  void _aliasFieldKeys(Set<String> ids, GlobalKey key) {
    for (final id in ids) {
      _fieldKeys[id] = key;
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[_UnifiedFormScreenState] initState');
    _loadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<UnifiedFormNotifier>();

      if (widget.confirmedSymptoms.isNotEmpty) {
        // Store raw codes so section-rules can drive conditional visibility.
        notifier.updateField('_triageSymptoms', widget.confirmedSymptoms);
      }

      notifier.loadDraft().then((_) async {
        // Seed triage → form symptom fields after draft load so a prior
        // draft without symptoms does not leave Step 2 empty, while any
        // already-saved hasSymptoms / ncdSymptoms / danger-sign values win.
        if (widget.confirmedSymptoms.isNotEmpty) {
          for (final ft in widget.activeFormTypes) {
            final prefills = TriageSymptomMapper.prefillsFor(
              ft,
              widget.confirmedSymptoms,
            );
            for (final entry in prefills.entries) {
              final existing = notifier.data.getValue(entry.key);
              final empty = existing == null ||
                  (existing is String && existing.trim().isEmpty) ||
                  (existing is List && existing.isEmpty);
              if (empty) {
                notifier.updateField(entry.key, entry.value);
              }
            }
          }
        }
        await notifier.preloadBiometrics();
        final hasAnc = widget.activeFormTypes.contains('anc') ||
            widget.enrolledFormTypes.contains('anc');
        if (hasAnc) {
          await notifier.preloadFromPregnancySnapshot();
          await notifier.preloadAncMedicalHistory();
          await notifier.preloadAncChronic();
        }
        if (widget.activeFormTypes.contains('ncd') ||
            widget.enrolledFormTypes.contains('ncd')) {
          await notifier.preloadNcdChronic();
        }
        if (widget.activeFormTypes.contains('pncMother') ||
            widget.enrolledFormTypes.contains('pncMother')) {
          await notifier.preloadPncMotherChronic();
          await notifier.loadPncMandatoryHistory();
          await notifier.seedDaysSinceDeliveryIfNeeded();
        }
        if (widget.activeFormTypes.contains('familyPlanning') ||
            widget.enrolledFormTypes.contains('familyPlanning') ||
            widget.activeFormTypes.contains('family_planning') ||
            widget.enrolledFormTypes.contains('family_planning')) {
          await notifier.preloadFpChronic();
        }
        // Android RMNCH summary auto-fills next visit; seed after draft so
        // a saved SK override is never clobbered. PNC bands need
        // daysSinceDelivery (seeded above).
        notifier.seedRmnchFollowUpIfNeeded();
      });

      // Load the patient's most-recent weight from ANY prior visit so the
      // weight-delta badge shows "Last: X kg" regardless of programme type.
      notifier.lastRecordedWeight().then((w) {
        if (mounted && w != null) setState(() => _lastRecordedWeight = w);
      });

      // Load prior ANC visits for the vitals-trend card (ANC visits only).
      if (widget.activeFormTypes.contains('anc') ||
          widget.enrolledFormTypes.contains('anc')) {
        notifier.ancVitalsHistory().then((history) {
          if (mounted && history.isNotEmpty) {
            setState(() => _priorAncVisits = history);
          }
        });
        notifier.pregnancySnapshot().then((snap) {
          if (mounted && snap?.ancVisitNo != null) {
            setState(() => _ancVisitNoFromSnapshot = snap!.ancVisitNo);
          }
        });
        // Load LMP/EDD for the gestational-age card (snapshot → seed → history).
        _reloadPregnancyIfSeeded();
      }

      // PNC visit number drives visit-2+ chronic-field hide (Android
      // managePncFormBasedOnPregnancyDetail).
      if (widget.activeFormTypes.contains('pncMother') ||
          widget.enrolledFormTypes.contains('pncMother')) {
        notifier.pregnancySnapshot().then((snap) {
          if (!mounted) return;
          setState(() => _pncVisitNoFromSnapshot = snap?.pncVisitNo);
        });
      }
    });
  }

  /// Best available GA: notifier (post-load) then navigation seed.
  int? _effectiveGestationalWeeks(UnifiedFormNotifier notifier) =>
      notifier.gestationalWeeks ?? widget.gestationalWeeks;

  /// 1-based ANC visit number: Spice pregnancyDetail.ancVisitNo + 1.
  int _ancVisitNumber() => (_ancVisitNoFromSnapshot ?? 0) + 1;

  /// 1-based PNC mother visit number: Spice pregnancyDetail.pncVisitNo + 1.
  int _pncVisitNumber() => (_pncVisitNoFromSnapshot ?? 0) + 1;

  bool _isFieldVisible(
    FieldDef field,
    UnifiedFormNotifier notifier, {
    String? formType,
  }) {
    return FieldVisibilityRules.isFieldVisible(
      field: field,
      data: notifier.data,
      rulesByTargetId: _config!.visibilityRulesByTargetId,
      gestationalWeeks: _effectiveGestationalWeeks(notifier),
      ancVisitNumber: _ancVisitNumber(),
      pncVisitNumber: _pncVisitNumber(),
      formType: formType,
      ageInMonths: widget.ageInMonths,
      priorHeightLocked: notifier.isHeightLockedFromPrior,
      isNcdFollowUp: notifier.isNcdFollowUp,
    );
  }

  void _reloadPregnancyIfSeeded() {
    if (!(widget.activeFormTypes.contains('anc') ||
        widget.enrolledFormTypes.contains('anc'))) {
      return;
    }
    final notifier = context.read<UnifiedFormNotifier>();
    notifier.loadPregnancyData(
      seedLmp: widget.lmpMs != null
          ? DateTime.fromMillisecondsSinceEpoch(widget.lmpMs!)
          : null,
      seedEdd: widget.eddMs != null
          ? DateTime.fromMillisecondsSinceEpoch(widget.eddMs!)
          : null,
      seedWeeks: widget.gestationalWeeks,
    );
  }

  @override
  void didUpdateWidget(covariant UnifiedFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // VisitFlow resolves snapshot async — re-seed when LMP/EDD/weeks arrive.
    final seedChanged = oldWidget.lmpMs != widget.lmpMs ||
        oldWidget.eddMs != widget.eddMs ||
        oldWidget.gestationalWeeks != widget.gestationalWeeks;
    if (seedChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _reloadPregnancyIfSeeded();
      });
    }
  }

  /// Builds a snapshot of the current visit's live vitals from the form data,
  /// for the last ("Today") column of the trend card.

  @override
  void dispose() {
    _scrollCtrl.dispose();
    debugPrint('[_UnifiedFormScreenState] dispose');
    super.dispose();
  }

  Future<void> _loadConfig() async {
    debugPrint('[_UnifiedFormScreenState] _loadConfig');
    try {
      final cfg = await FormConfig.loadAndCache(rootBundle);
      if (!mounted) return;
      // The notifier needs the library to clear fields a condition has just
      // hidden, and to translate option ids to wire values at submit.
      context.read<UnifiedFormNotifier>().formConfig = cfg;
      setState(() { _config = cfg; _configLoading = false; });
    } catch (e, st) {
      debugPrint('[UnifiedForm] FormConfig.load failed: $e\n$st');
      if (mounted) setState(() { _configError = e; _configLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_configLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_configError != null || _config == null) {
      return Center(
        child: Text(
          UnifiedFormStrings.configLoadError,
          style: AppTextStyles.body,
        ),
      );
    }

    return Consumer<UnifiedFormNotifier>(
      builder: (ctx, notifier, _) {
        final effectiveGa = _effectiveGestationalWeeks(notifier);
        final annotated = UnifiedSectionRules.activeSections(
          config: _config!,
          activeFormTypes: widget.activeFormTypes,
          currentData: notifier.data,
          gestationalWeeks: effectiveGa,
          enrolledFormTypes: widget.enrolledFormTypes,
          ageInMonths: widget.ageInMonths,
        );
        final outcomeValue = notifier.data.getValue('deliveryOutcomeType');
        if (widget.activeFormTypes.contains('pregnancyOutcome')) {
          debugPrint('[DeliveryOutcome] rebuild sections=${annotated.length} '
              'deliveryOutcomeType=$outcomeValue '
              'sectionIds=${annotated.map((a) => a.section.sectionId).join(', ')}');
        }

        // Only emit the [Form] debug summary when the section/field count
        // changes — suppresses per-keystroke log spam during form filling.
        final totalFields = annotated.fold<int>(
          0, (sum, a) => sum + a.section.fieldRefs.length);
        if (annotated.length != _lastLoggedSectionCount ||
            totalFields != _lastLoggedFieldCount) {
          final isFirstLoad = _lastLoggedSectionCount == -1;
          _lastLoggedSectionCount = annotated.length;
          _lastLoggedFieldCount = totalFields;
          if (isFirstLoad) {
            // Collect all field IDs across sections to report merged groups.
            final allIds = <String>{};
            for (final a in annotated) {
              for (final r in a.section.fieldRefs) {
                allIds.add(r.id);
              }
            }
            final merged = UnifiedSectionRules.mergedGroupDescriptions(allIds);
            // ignore: avoid_print
            print('[Form] ── section order (${widget.activeFormTypes.join('+')} · '
                '${annotated.length} sections · $totalFields fields) ──────────');
            if (merged.isNotEmpty) {
              // ignore: avoid_print
              print('[Form]   merged (captured once): ${merged.join(', ')}');
            }
            for (var i = 0; i < annotated.length; i++) {
              final a = annotated[i];
              final fieldIds = a.section.fieldRefs.map((r) => r.id).join(' · ');
              // ignore: avoid_print
              print('[Form]   ${i + 1}. [${a.section.sectionId}] '
                  '${a.section.title} → $fieldIds');
            }
            // ignore: avoid_print
            print('[Form] ────────────────────────────────────────────────────');
          }
          UnifiedSectionRules.debugLogSections(annotated, totalFields);
        }

        // Build the list items: programme-name dividers (with inline per-
        // programme symptom chips) + section cards.
        // ANC-specific cards are pinned to fixed positions:
        //   • Gestational age card → first item (below the AI Scribe banner)
        //   • Vitals trend card    → last item before submit
        final items = <Widget>[];
        final isAnc = widget.activeFormTypes.contains('anc');

        // ── Gestational age card (ANC) — top of scroll area ────────────────
        final cardLmp = notifier.lmpDate ??
            (widget.lmpMs != null
                ? DateTime.fromMillisecondsSinceEpoch(widget.lmpMs!)
                : null);
        final cardEdd = notifier.eddDate ??
            (widget.eddMs != null
                ? DateTime.fromMillisecondsSinceEpoch(widget.eddMs!)
                : null);
        // Only show when we have real pregnancy dating (LMP, EDD, or GA).
        // Empty "—" placeholders confuse first-time PW+ANC (LMP still being
        // entered below) and hide nothing useful when PW never recorded LMP.
        final hasLmpData =
            cardLmp != null || cardEdd != null || effectiveGa != null;
        if (isAnc && hasLmpData) {
          debugPrint(
            '[LMP] card MOUNT patient=${notifier.patientId} '
            'lmp=$cardLmp edd=$cardEdd '
            'weeks=$effectiveGa',
          );
          items.add(GestationalAgeCard(
            lmpDate: cardLmp,
            eddDate: cardEdd,
            gestationalWeeks: effectiveGa,
            bottomPadding: AppSpacing.xl,
            ancVisitNumber: _ancVisitNumber().toString(),
          ));
        } else if (isAnc) {
          debugPrint(
            '[LMP] card HIDE — no LMP/EDD/GA yet patient=${notifier.patientId}',
          );
        } else {
          debugPrint(
            '[LMP] card SKIP — not ANC activeFormTypes=${widget.activeFormTypes}',
          );
        }

        String? lastFormType;
        for (final annotatedSection in annotated) {
          final ft = annotatedSection.section.formType;
          final isNew = ft.isNotEmpty &&
              annotatedSection.group != SectionGroup.vitals &&
              !widget.enrolledFormTypes.contains(ft);
          if (ft != lastFormType) {
            lastFormType = ft;
            if (annotatedSection.group != SectionGroup.vitals) {
              final label = UnifiedFormStrings.programmeBadgeLabel(ft) ??
                  ft.toUpperCase();
              items.add(_ProgrammeDivider(
                label: label,
                relevantSymptomCodes: TriageSymptomMapper.relevantCodes(
                    ft, widget.confirmedSymptoms),
                aiPickedSymptomCodes: widget.aiPickedSymptoms,
                isNewEnrolment: isNew,
                formType: ft,
              ));
            }
          }
          items.add(_SectionCard(
            key: _sectionKeyFor('${annotatedSection.section.formType}_${annotatedSection.section.sectionId}'),
            section: annotatedSection.section,
            config: _config!,
            data: notifier.data,
            validationErrors: notifier.validationErrors,
            onFieldChanged: notifier.updateField,
            fieldKeyFor: _fieldKeyFor,
            aliasFieldKeys: _aliasFieldKeys,
            previousWeight: _lastRecordedWeight,
            // Prior height is locked; NCD/cataract also hide the field (ANC
            // visit 2+ already hides via visit-number rules). Weight stays.
            heightReadOnly: notifier.isHeightLockedFromPrior,
            gestationalWeeks: effectiveGa,
            ancVisitNumber: _ancVisitNumber(),
            pncVisitNumber: _pncVisitNumber(),
            ageInMonths: widget.ageInMonths,
            isNcdFollowUp: notifier.isNcdFollowUp,
            isNewEnrolment: isNew,
          ));
        }

        // ── Vitals trend card (ANC) — bottom of scroll area ────────────────
        if (isAnc && _priorAncVisits.isNotEmpty) {
          items.add(_VitalsTrendCard(priorVisits: _priorAncVisits));
        }

        // Submit button lives inside the scroll view so it appears after the
        // last form field — not pinned to the screen bottom.
        items.add(_SubmitBar(
          submitting: notifier.submitting,
          onSubmit: () => _onSubmit(ctx, notifier, annotated),
        ));

        // Tapping anywhere outside a focused field dismisses the keyboard;
        // it only reopens when the SK explicitly taps back into a field.
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Column(
          children: [
            // ── Step 2 AI Scribe banner — the SAME widget as Step 1, in
            // live-first mode. When the programme mix supports auto-fill
            // (NCD/ANC), extractions come back as form_fill and are written
            // straight into the form through the validated prefill gate.
            if (AppConfig.scribeEnabled &&
                context.watch<AiFeatureTogglesNotifier>().toggles.step2AsrEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxxl, AppSpacing.xl, AppSpacing.xxxl, 0),
                child: AiScribeBanner(
                  encounterId: notifier.encounterId,
                  patientId: notifier.patientId,
                  isFemale: widget.activeFormTypes.contains('anc') ||
                      widget.activeFormTypes.contains('pnc'),
                  tapStartsLiveAsr: true,
                  assessmentType: FormFieldSchemaBuilder.assessmentTypeFor(
                      widget.activeFormTypes),
                  onFormFill: (fill) {
                    final rejected = notifier.applyAiPrefill(
                      fill.fields.where((f) => f.value != null).toList(),
                      fieldDefs: _config!.fields,
                    );
                    if (rejected.isNotEmpty) {
                      debugPrint(
                          '[Step2ASR] rejected: ${rejected.join(' | ')}');
                    }
                  },
                  // VisitFormScreen watches ScribeController state and
                  // auto-opens the SOAP review sheet when reviewReady — no
                  // action needed here.
                  onReviewReady: (_) {},
                ),
              ),
            // ── Assessment form sections + submit button ────────────────────
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: _scrollCtrl,
                  // A combined ANC+NCD visit can have 9+ sections; Flutter's
                  // default ~250px cache extent only keeps nearby sections
                  // mounted, so a distant section's/field's GlobalKey has a
                  // null currentContext by the time submit tries to scroll
                  // to it. This form is a bounded clinical assessment (not an
                  // arbitrarily long list), so keeping every section built
                  // is the correct trade-off — matches a plain Column's
                  // always-built behavior without giving up ListView.
                  scrollCacheExtent: const ScrollCacheExtent.pixels(20000),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxxl, AppSpacing.md, AppSpacing.xxxl, AppSpacing.xxxl),
                  children: items,
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  Future<void> _onSubmit(
    BuildContext ctx,
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) async {
    debugPrint('[_UnifiedFormScreenState] _onSubmit');
    if (_config == null) {
      _logSubmitBlocked(
        reason: 'form config not loaded yet',
        lines: const ['form_config.json still loading or failed to parse'],
      );
      return;
    }

    // Strip stale values for fields that are no longer visible (e.g. Parity
    // was answered while Gravida >= 2, then Gravida was changed back to 1) so
    // the submitted payload never contains a value the SK can't see or edit.
    final hiddenFieldIds = _computeHiddenFieldIds(notifier, annotated);
    if (hiddenFieldIds.isNotEmpty) {
      notifier.clearFields(hiddenFieldIds);
    }

    // Validate mandatory fields before submitting.
    final errors = _computeValidationErrors(notifier, annotated);
    if (errors.isNotEmpty) {
      _logSubmitBlocked(
        reason: '${errors.length} mandatory field(s) not filled',
        lines: _describeMissingMandatory(notifier, annotated, errors),
      );
      notifier.setValidationErrors(errors);
      // Scroll after the error-highlight rebuild — calling ensureVisible in
      // the same turn as setValidationErrors is cancelled when the ListView
      // rebuilds, leaving the SK stuck on the Submit button.
      _scrollToFirstError(annotated, errors);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            UnifiedFormStrings.validationFieldsRequired(errors.length),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
      return;
    }

    // Range-check numeric fields (BP, fundal height, glucose, Hb, temperature)
    // — activates the validators already attached to the individual
    // TextFormFields; Form.validate() renders each one's message inline
    // under the offending field.
    final rangeValid = _formKey.currentState?.validate() ?? true;
    if (!rangeValid) {
      final rangeErrors = _computeRangeErrorFieldIds(notifier, annotated);
      _logSubmitBlocked(
        reason: 'numeric value(s) out of the allowed range',
        lines: _describeRangeFailures(notifier, annotated),
      );
      if (rangeErrors.isNotEmpty) {
        _scrollToFirstError(annotated, rangeErrors);
      }
      return;
    }

    // Clear any previous errors before submitting.
    notifier.setValidationErrors(const {});

    try {
      // Option ids stored by the widgets are translated to their wire `value`
      // codes during submit — the mapper needs the field library to do that.
      notifier.formConfig = _config!;
      notifier.fieldDefs = _config!.fields;
      await notifier.submit();
      widget.onSubmitComplete();
    } catch (e) {
      _logSubmitBlocked(
        reason: 'save threw an exception',
        lines: ['$e'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(VisitFormStrings.saveFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  /// Prints why a Submit tap did not advance, framed by `***` markers so it is
  /// easy to find in a noisy `flutter logs` stream.
  void _logSubmitBlocked({
    required String reason,
    required List<String> lines,
  }) {
    debugPrint('********** SUBMIT BLOCKED START **********');
    debugPrint('[SubmitBlocked] reason: $reason');
    for (final line in lines) {
      debugPrint('[SubmitBlocked]   $line');
    }
    debugPrint('*********** SUBMIT BLOCKED END ***********');
  }

  /// Human-readable "which field and where" lines for each unfilled mandatory
  /// field, so the SK-facing snackbar count can be traced to actual field IDs.
  List<String> _describeMissingMandatory(
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
    Set<String> errors,
  ) {
    final lines = <String>[];
    final described = <String>{};

    for (final a in annotated) {
      for (final ref in a.section.fieldRefs) {
        if (!errors.contains(ref.id) || !described.add(ref.id)) continue;
        final def = _config!.fields[ref.id];
        final label = def?.label ?? ref.id;
        final value = notifier.data.getValue(ref.id);
        lines.add(
          'MISSING  ${ref.id}  ("$label")  '
          'section=${a.section.formType}/${a.section.sectionId}  '
          'widget=${def?.widgetHint.name ?? "unknown"}  '
          'value=${value ?? "null"}',
        );
      }
    }

    // Newborn card errors use synthetic ids (newbornDetails_<i>_<field>) that
    // do not exist in the field library / section fieldRefs.
    for (final id in errors) {
      if (!id.startsWith('newbornDetails') || !described.add(id)) continue;
      final parts = id.split('_');
      if (parts.length >= 3) {
        final babyNo = (int.tryParse(parts[1]) ?? 0) + 1;
        lines.add('MISSING  $id  (Baby $babyNo → ${parts.sublist(2).join("_")})');
      } else {
        lines.add('MISSING  $id  (no baby card answered yet)');
      }
    }

    // Anything left belongs to no rendered section, so the SK sees the "fields
    // required" snackbar with nothing highlighted — Submit looks dead.
    for (final id in errors) {
      if (!described.add(id)) continue;
      lines.add('MISSING (not rendered in any visible section)  $id');
    }
    return lines;
  }

  /// Re-runs the numeric range validators against current values so the log
  /// names the offending field, not just "validation failed".
  List<String> _describeRangeFailures(
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) {
    final lines = <String>[];
    final checked = <String>{};
    for (final a in annotated) {
      for (final ref in a.section.fieldRefs) {
        if (!checked.add(ref.id)) continue;
        final validator = _SectionCard._numericRangeValidator(
          ref.id,
          formType: a.section.formType,
          ageInMonths: widget.ageInMonths,
        );
        if (validator != null) {
          final raw = notifier.data.getValue(ref.id);
          final message = validator(raw?.toString());
          if (message != null) {
            lines.add(
              'OUT OF RANGE  ${ref.id}  value=${raw ?? "null"}  → $message',
            );
          }
        }
        if (ref.id == 'glucoseType') {
          final glucoseValidator = _SectionCard._numericRangeValidator(
            'glucose',
            formType: a.section.formType,
          );
          if (glucoseValidator != null) {
            final raw = notifier.data.getValue('glucose');
            final message = glucoseValidator(raw?.toString());
            if (message != null) {
              lines.add(
                'OUT OF RANGE  glucose  value=${raw ?? "null"}  → $message',
              );
            }
          }
        }
      }
    }
    if (lines.isEmpty) {
      lines.add(
          'an inline TextFormField validator rejected its value (check fields '
          'showing a red message)');
    }
    return lines;
  }

  /// Returns the set of mandatory field IDs that have no value in [notifier].
  Set<String> _computeValidationErrors(
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) {
    final errors = <String>{};
    for (final a in annotated) {
      // Dynamic newborn cards — validate each baby entry (Android
      // validateBabyFields).
      if (a.section.sectionId == 'newbornDetails' &&
          a.section.formType == 'pregnancyOutcome') {
        errors.addAll(_newbornValidationErrors(notifier));
        continue;
      }
      for (final ref in a.section.fieldRefs) {
        final def = _config!.fields[ref.id];
        if (def == null) continue;
        // A hidden field (e.g. Parity before Gravida >= 2) must never block
        // submission even if it's flagged mandatory in the field library.
        if (!_isFieldVisible(def, notifier, formType: a.section.formType)) {
          continue;
        }
        final mandatory = def.isMandatory ||
            ref.isMandatory ||
            _pncConditionallyRequired(ref.id, notifier, a.section.formType);
        if (!mandatory) continue;
        final v = notifier.data.getValue(ref.id);
        final empty = v == null ||
            (v is String && v.trim().isEmpty) ||
            (v is List && v.isEmpty);
        if (empty) errors.add(ref.id);
      }
    }
    return errors;
  }

  /// Android `managePncFormBasedOnPregnancyDetail` — Hb / blood sugar become
  /// mandatory in specific clinical contexts while the field is visible.
  bool _pncConditionallyRequired(
    String fieldId,
    UnifiedFormNotifier notifier,
    String formType,
  ) {
    if (formType != 'pncMother') return false;
    bool isYes(Object? v) {
      final s = v?.toString().trim().toLowerCase() ?? '';
      return s == 'yes' || s == 'true' || s == '1';
    }

    bool listIncludes(Object? raw, String code) {
      if (raw is! List) {
        final s = raw?.toString().trim().toLowerCase() ?? '';
        return s.contains(code.toLowerCase());
      }
      for (final e in raw) {
        final token = e is Map
            ? (e['value'] ?? e['id'] ?? e['name'])?.toString()
            : e?.toString();
        if (token == null) continue;
        if (token.trim().toLowerCase().contains(code.toLowerCase())) {
          return true;
        }
      }
      return false;
    }

    // Prefer notifier history (includes ANC anemia / prior pncIllness). Fall
    // back to snapshot visit counters so first-PNC-no-ANC still works if the
    // async history load has not finished.
    final history = notifier.pncMandatoryHistory.isLoaded
        ? notifier.pncMandatoryHistory
        : PncMandatoryHistory(
            pncVisitNumber: _pncVisitNumber(),
            ancVisitCount: _ancVisitNoFromSnapshot ?? 0,
          );

    final form = PncMandatoryFormSignals(
      heavyBleedingDangerSign:
          // Spice postpartumDangerSigns option id for heavy bleeding is "1".
          listIncludes(notifier.data.getValue('postpartumDangerSigns'), '1'),
      excessiveBleedingAtDelivery: listIncludes(
        notifier.data.getValue('complicationsDuringDelivery'),
        'excessiveBleeding',
      ),
      knownDmOrGdmOnForm: isYes(notifier.data.getValue('dmPatient')) ||
          isYes(notifier.data.getValue('gdmPatient')),
    );

    if (fieldId == 'hemoglobin') {
      return PncMandatoryRules.hemoglobinRequired(
        history: history,
        form: form,
      );
    }
    if (fieldId == 'bloodSugar' ||
        fieldId == 'fastingBloodSugar' ||
        fieldId == 'randomBloodSugar') {
      final required = PncMandatoryRules.bloodSugarRequired(
        history: history,
        form: form,
      );
      if (!required) return false;
      if (fieldId == 'bloodSugar') return true;
      final type =
          notifier.data.getValue('bloodSugar')?.toString().toLowerCase();
      if (fieldId == 'fastingBloodSugar') {
        return type == 'fasting' || type == 'fbs';
      }
      if (fieldId == 'randomBloodSugar') {
        return type == 'random' || type == 'rbs';
      }
    }
    return false;
  }

  /// Per-baby required fields: isBabyAlive + sex always; cause when dead.
  Set<String> _newbornValidationErrors(UnifiedFormNotifier notifier) {
    final errors = <String>{};
    final raw = notifier.data.getValue('newbornDetails');
    if (raw is! List || raw.isEmpty) {
      // Section is visible only when liveBirthNumbers >= 1, so an empty list
      // means the SK hasn't answered any baby card yet.
      errors.add('newbornDetails');
      return errors;
    }
    for (var i = 0; i < raw.length; i++) {
      final baby = raw[i];
      if (baby is! Map) {
        errors.add('newbornDetails_$i');
        continue;
      }
      final alive = baby['isBabyAlive']?.toString().trim() ?? '';
      final sex = baby['sex']?.toString().trim() ?? '';
      if (alive.isEmpty) errors.add('newbornDetails_${i}_isBabyAlive');
      if (sex.isEmpty) errors.add('newbornDetails_${i}_sex');
      if (alive.toLowerCase() == 'no') {
        final cause = baby['causeOfNeonatalDeath'];
        final emptyCause = cause == null ||
            (cause is String && cause.trim().isEmpty) ||
            (cause is List && cause.isEmpty);
        if (emptyCause) {
          errors.add('newbornDetails_${i}_causeOfNeonatalDeath');
        }
      }
    }
    return errors;
  }

  /// Returns or creates the [GlobalKey] for a section (by sectionId).
  GlobalKey _sectionKeyFor(String sectionId) =>
      _sectionKeys.putIfAbsent(sectionId, GlobalKey.new);

  /// Field IDs whose numeric range validators currently fail — used to scroll
  /// to the field that owns the first bad value after Form.validate().
  Set<String> _computeRangeErrorFieldIds(
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) {
    final errors = <String>{};
    final checked = <String>{};
    for (final a in annotated) {
      for (final ref in a.section.fieldRefs) {
        if (!checked.add(ref.id)) continue;
        final validator = _SectionCard._numericRangeValidator(
          ref.id,
          formType: a.section.formType,
          ageInMonths: widget.ageInMonths,
        );
        if (validator != null) {
          final raw = notifier.data.getValue(ref.id);
          if (validator(raw?.toString()) != null) errors.add(ref.id);
        }
        // BloodGlucoseEntry stores the numeric value under `glucose` while
        // the rendered field id is `glucoseType` — check both so submit
        // scrolls to / highlights the combined card.
        if (ref.id == 'glucoseType') {
          final glucoseValidator = _SectionCard._numericRangeValidator(
            'glucose',
            formType: a.section.formType,
          );
          if (glucoseValidator != null) {
            final raw = notifier.data.getValue('glucose');
            if (glucoseValidator(raw?.toString()) != null) {
              errors.add('glucoseType');
              errors.add('glucose');
            }
          }
        }
      }
    }
    return errors;
  }

  /// Scrolls to the first field (or, failing that, the first section) that
  /// contains a validation error, so the SK lands directly on the missing
  /// input instead of having to hunt within a (possibly tall) section.
  ///
  /// Must run in a post-frame callback: [UnifiedFormNotifier.setValidationErrors]
  /// notifies listeners and rebuilds the [ListView] in the same frame. An
  /// immediate [Scrollable.ensureVisible] starts an animation that that rebuild
  /// cancels, so the SK stays on the Submit button.
  void _scrollToFirstError(
    List<AnnotatedFormSection> annotated,
    Set<String> errors,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || errors.isEmpty) return;
      FocusScope.of(context).unfocus();
      final fieldId = firstErrorFieldId(annotated, errors);
      if (fieldId != null) {
        final ctx = _fieldKeys[fieldId]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            alignment: 0.2,
          );
          return;
        }
      }
      for (final a in annotated) {
        final hasError =
            a.section.fieldRefs.any((r) => errors.contains(r.id)) ||
                (a.section.sectionId == 'newbornDetails' &&
                    errors.any((e) => e.startsWith('newbornDetails')));
        if (!hasError) continue;
        if (_scrollToSection(a)) return;
      }
      // Fallback: scroll to top if no key context found yet.
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Scrolls to [a]'s section anchor. Returns false (without scrolling) if the
  /// section has no attached context yet, so the caller can fall through.
  bool _scrollToSection(AnnotatedFormSection a) {
    final key = _sectionKeys['${a.section.formType}_${a.section.sectionId}'];
    final ctx = key?.currentContext;
    if (ctx == null) return false;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.1,
    );
    return true;
  }

  /// Returns the set of field IDs that are currently hidden (per the same
  /// visibility rules used for rendering and validation) but still hold a
  /// value in [notifier] — these are stale and must not reach the payload.
  ///
  /// [height] is never stripped: when ANC visit 2+ / NCD prior-height hide the
  /// field, the prefilled value must still reach the payload (BMI + wire).
  /// PNC visit 2+ chronic illness radios are also preserved (Android hides
  /// them after prefill from prior `pncIllness`).
  Set<String> _computeHiddenFieldIds(
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) {
    const preserveHidden = {
      'height',
      'htnPatient',
      'eclampsia',
      'dmPatient',
      'gdmPatient',
    };
    final hidden = <String>{};
    for (final a in annotated) {
      for (final ref in a.section.fieldRefs) {
        if (preserveHidden.contains(ref.id)) continue;
        final def = _config!.fields[ref.id];
        if (def == null) continue;
        if (_isFieldVisible(def, notifier, formType: a.section.formType)) {
          continue;
        }
        if (notifier.data.getValue(ref.id) != null) hidden.add(ref.id);
      }
    }
    return hidden;
  }
}

// ── Programme divider ─────────────────────────────────────────────────────────

/// Labelled horizontal divider shown when the formType changes in the section
/// list.  The label is the programme name ("ANC", "NCD", "PNC", …) or
/// "Vitals" for the shared vitals group.
///
/// When [relevantSymptomCodes] is non-empty a collapsible chip row is shown
/// below the divider line, listing the triage symptoms that were reported and
/// are relevant to this programme.  Collapsed to the first 3 chips by default;
/// tap "N more" to reveal the rest.
class _ProgrammeDivider extends StatefulWidget {
  const _ProgrammeDivider({
    required this.label,
    this.relevantSymptomCodes = const [],
    this.aiPickedSymptomCodes = const {},
    this.isNewEnrolment = false,
    this.formType,
  });

  final String label;
  final List<String> relevantSymptomCodes;
  /// Codes from Step 1 that were pre-selected by the AI Scribe.
  /// Chips for these codes render with the purple AI palette.
  final Set<String> aiPickedSymptomCodes;
  /// True when this programme was not previously enrolled — drives accent tint.
  final bool isNewEnrolment;
  /// Raw formType key (e.g. 'ncd', 'anc') — used for colour lookup.
  final String? formType;

  @override
  State<_ProgrammeDivider> createState() => _ProgrammeDividerState();
}

class _ProgrammeDividerState extends State<_ProgrammeDivider> {
  /// Controls whether the symptom chip list is visible.
  bool _symptomsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codes = widget.relevantSymptomCodes;
    final hasChips = codes.isNotEmpty;

    final accentColor = widget.isNewEnrolment
        ? _newEnrolmentAccent(widget.formType ?? '')
        : null;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.sm,
        top: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Single divider row: LABEL ─── [symptom toggle] ────────────
          GestureDetector(
            onTap: hasChips
                ? () => setState(() => _symptomsExpanded = !_symptomsExpanded)
                : null,
            child: Row(
              children: [
                Text(
                  widget.label.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accentColor ?? AppColors.textPrimary,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Divider(color: accentColor ?? AppColors.border, height: 1)),
                if (hasChips) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.assignment_outlined,
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    UnifiedFormStrings.triageSymptomsCount(codes.length),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(width: 1),
                  AnimatedRotation(
                    turns: _symptomsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── Chip list — revealed when expanded ────────────────────────
          if (hasChips)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: codes
                      .map(
                        (c) => _TriageChip(
                          code: c,
                          isAi: widget.aiPickedSymptomCodes.contains(c),
                        ),
                      )
                      .toList(),
                ),
              ),
              crossFadeState: _symptomsExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// A single read-only triage symptom pill used inside programme dividers and
/// the collapsible banner.
///
/// When [isAi] is true the chip uses the purple AI palette (matching Step 1's
/// AI-ticked chip style) to signal that this symptom was pre-selected by the
/// AI Scribe.  Otherwise the amber warning palette is used for manually-selected
/// symptoms.
/// Read-only symptom chip shown in the Step 2 "Symptoms from Step 1" accordion.
///
/// Visually identical to [_PickerChip] in its **selected-AI** state so the SK
/// immediately recognises the same chips they confirmed in Step 1.
class _TriageChip extends StatelessWidget {
  const _TriageChip({required this.code, this.isAi = false});

  final String code;
  final bool isAi;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color borderColor;
    final Color textColor;
    if (isAi) {
      // Mirror _PickerChip's selected-AI colours exactly.
      bg = AppColors.aiSurfaceStart;
      borderColor = AppColors.aiBorder;
      textColor = AppColors.aiPurple;
    } else {
      bg = AppColors.statusWarningSurface;
      borderColor = AppColors.statusWarning.withValues(alpha: 0.30);
      textColor = AppColors.statusWarningText;
    }

    return Container(
      // Same padding as _PickerChip selected state.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isAi ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sparkle icon — same size (13) and spacing (4) as _PickerChip.
          Icon(
            isAi ? Icons.auto_awesome : Icons.circle,
            size: 13,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            TriageStrings.symptomLabel(code),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vitals-trend card ─────────────────────────────────────────────────────────

/// Collapsible amber accordion showing systolic / diastolic / weight / urine
/// protein across the last few ANC visits, with a 📈 marker on rising metrics.
///
/// Computes [VitalsTrendResult] internally on every build by watching
/// [UnifiedFormNotifier] directly — this guarantees the "Today" column
/// updates on every field keystroke without depending on a prop-chain through
/// the parent Consumer.  [priorVisits] is stable (loaded once in initState).
class _VitalsTrendCard extends StatefulWidget {
  const _VitalsTrendCard({required this.priorVisits});

  final List<VisitVitals> priorVisits;

  @override
  State<_VitalsTrendCard> createState() => _VitalsTrendCardState();
}

class _VitalsTrendCardState extends State<_VitalsTrendCard> {
  bool _expanded = false;

  static const _rising = '📈';
  static const _flat = '·';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Watch notifier directly — rebuilds on every updateField() call so
    // "Today" column reflects the latest typed value in real-time.
    final notifier = context.watch<UnifiedFormNotifier>();
    final data = notifier.data;
    final today = VisitVitals(
      systolic: () {
        final v = data.getValue('systolic');
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v);
        return null;
      }(),
      diastolic: () {
        final v = data.getValue('diastolic');
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v);
        return null;
      }(),
      weight: () {
        final v = data.getValue('weight');
        if (v is double) return v;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }(),
      urineProtein: () {
        final v = data.getValue('urinaryAlbumin');
        if (v == null) return null;
        return v is String ? v : v.toString();
      }(),
    );
    final result = VitalsTrendAnalyzer.analyze(
      priorVisits: widget.priorVisits,
      today: today,
    );
    // Hide until ≥1 metric qualifies (3 readings + rising ≥5 / urine Present).
    if (!result.show) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.catChildSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.statusWarningBorder, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Accordion header — always visible, tappable ─────────────────
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 17,
                      color: AppColors.fieldKindAmber,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        UnifiedFormStrings.trendCardTitle(result.columns.length),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.statusWarningText,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.fieldKindAmber,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Accordion body — collapsed by default ───────────────────────
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 1,
                      color: AppColors.statusWarningBorder,
                      margin: const EdgeInsets.only(bottom: 10),
                    ),
                    _buildTable(theme, result),
                    const SizedBox(height: 9),
                    Text(
                      result.show
                          ? UnifiedFormStrings.trendFooter
                          : UnifiedFormStrings.trendFooterStable,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.statusWarningText,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(ThemeData theme, VitalsTrendResult result) {
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.statusWarningText,
      fontWeight: FontWeight.w700,
      fontSize: 11,
    );
    final subStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.statusWarningText,
      fontWeight: FontWeight.w500,
      fontSize: 9.5,
    );

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: AppColors.statusWarningBorder.withValues(alpha: 0.7),
        ),
      ),
      columnWidths: const {0: FlexColumnWidth(2.2)},
      children: [
        // Header row
        TableRow(
          children: [
            const SizedBox.shrink(),
            for (final col in result.columns)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      col.isToday
                          ? UnifiedFormStrings.trendTodayColumn
                          : UnifiedFormStrings.trendVisitColumn(
                              col.visitNumber ?? 0),
                      textAlign: TextAlign.center,
                      style: headerStyle,
                    ),
                    if (!col.isToday && col.daysAgo != null)
                      Text(
                        UnifiedFormStrings.trendWeeksAgo(col.daysAgo!),
                        textAlign: TextAlign.center,
                        style: subStyle,
                      ),
                  ],
                ),
              ),
            Center(child: Text('↗', style: headerStyle)),
          ],
        ),
        // Metric rows
        for (final metric in result.metrics) _metricRow(theme, metric),
      ],
    );
  }

  TableRow _metricRow(ThemeData theme, VitalMetricTrend metric) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.statusWarningText,
      fontWeight: FontWeight.w600,
      fontSize: 11,
    );
    final priorStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.textMuted,
      fontSize: 11,
    );
    final todayStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.fieldKindAmber,
      fontWeight: FontWeight.w800,
      fontSize: 11.5,
    );

    final lastIndex = metric.values.length - 1;
    // For the weight row, deltas are computed from the earliest recorded reading.
    final weightBaseline = metric.metric == VitalMetric.weight
        ? metric.values.whereType<num>().firstOrNull
        : null;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(_metricLabel(metric.metric), style: labelStyle),
        ),
        for (var i = 0; i < metric.values.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              _formatValue(metric.metric, metric.values[i],
                  weightBaseline: weightBaseline),
              textAlign: TextAlign.center,
              style: i == lastIndex ? todayStyle : priorStyle,
            ),
          ),
        Center(
          child: Text(
            metric.rising ? _rising : _flat,
            style: TextStyle(fontSize: metric.rising ? 12 : 13,
                color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  String _metricLabel(VitalMetric metric) {
    switch (metric) {
      case VitalMetric.systolic:
        return UnifiedFormStrings.trendSystolic;
      case VitalMetric.diastolic:
        return UnifiedFormStrings.trendDiastolic;
      case VitalMetric.weight:
        return UnifiedFormStrings.trendWeightGain;
      case VitalMetric.urineProtein:
        return UnifiedFormStrings.trendUrineProtein;
    }
  }

  String _formatValue(VitalMetric metric, num? value, {num? weightBaseline}) {
    if (value == null) return UnifiedFormStrings.trendMissingValue;
    switch (metric) {
      case VitalMetric.systolic:
      case VitalMetric.diastolic:
        return value.toInt().toString();
      case VitalMetric.weight:
        if (weightBaseline == null) return value.toStringAsFixed(1);
        final delta = value.toDouble() - weightBaseline.toDouble();
        return delta >= 0
            ? '+${delta.toStringAsFixed(1)}'
            : delta.toStringAsFixed(1);
      case VitalMetric.urineProtein:
        switch (value.toInt()) {
          case 0:
            return UnifiedFormStrings.trendUrineAbsent;
          case 1:
            return UnifiedFormStrings.trendUrineTrace;
          case 2:
            return UnifiedFormStrings.trendUrinePresent;
          default:
            return UnifiedFormStrings.trendMissingValue;
        }
    }
  }
}

// _GestationalAgeCard and _DateSubBox extracted to
// lib/core/widgets/gestational_age_card.dart.

class _GestationalAgeCard extends StatelessWidget {
  const _GestationalAgeCard({
    required this.lmpDate,
    required this.eddDate,
    required this.gestationalWeeks,
  });

  final DateTime? lmpDate;
  final DateTime? eddDate;
  final int? gestationalWeeks;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmt(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _pinkAccent = Color(0xFF9D174D);
  static const _navy = Color(0xFF1B2B5E);
  static const _unitGrey = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final lmpStr = lmpDate != null ? _fmt(lmpDate!) : null;
    final eddStr = eddDate != null ? _fmt(eddDate!) : null;

    int? weeks;
    int? days;
    if (lmpDate != null) {
      final total = DateTime.now().difference(lmpDate!).inDays;
      weeks = total ~/ 7;
      days = total % 7;
    } else if (gestationalWeeks != null) {
      weeks = gestationalWeeks;
      days = 0;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDF2F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF9A8D4)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero row: circle avatar + label + number
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text('🤰', style: TextStyle(fontSize: 19)),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ComposerStrings.gestationalAgeLabel.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _pinkAccent,
                        letterSpacing: 0.6,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: AppFonts.display,
                          color: _navy,
                          height: 1,
                        ),
                        children: weeks != null
                            ? [
                                TextSpan(
                                  text: '$weeks ',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: ComposerStrings.gestationalAgeWeeks,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _unitGrey,
                                  ),
                                ),
                                if (days != null && days > 0) ...[
                                  TextSpan(
                                    text: ' $days ',
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      color: _navy,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ComposerStrings.gestationalAgeDays,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _unitGrey,
                                    ),
                                  ),
                                ],
                              ]
                            : [
                                TextSpan(
                                  text: '— ',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: ComposerStrings.gestationalAgeWeeks,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _unitGrey,
                                  ),
                                ),
                              ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // LMP + EDD row
            Row(
              children: [
                Expanded(
                  child: _DateSubBox(
                    emoji: '📅',
                    label: ComposerStrings.pregnancyOverviewLmp,
                    value: lmpStr,
                    valueColor: _navy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateSubBox(
                    emoji: '🍼',
                    label: ComposerStrings.pregnancyOverviewEdd,
                    value: eddStr,
                    valueColor: const Color(0xFFDB2777),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSubBox extends StatelessWidget {
  const _DateSubBox({
    required this.emoji,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String emoji;
  final String label;
  final String? value;
  final Color valueColor;

  static const _pinkAccent = Color(0xFF9D174D);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _pinkAccent,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          Text(
            value ?? '—',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── AI-filled badge wrap ──────────────────────────────────────────────────────

/// Overlays a small "AI — verify" pill on a form field whose current value
/// was filled by the realtime ASR scribe and not yet reviewed by the SK.
/// The badge disappears as soon as the SK edits the field (source flips to
/// [FieldSource.aiModified] in [UnifiedFormNotifier.updateField]).
class _AiFilledBadgeWrap extends StatelessWidget {
  const _AiFilledBadgeWrap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -6,
          right: 8,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.aiPurple,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome,
                    size: 10, color: Colors.white),
                const SizedBox(width: 3),
                Text(
                  Step2AsrStrings.aiFilledBadge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.section,
    required this.config,
    required this.data,
    required this.validationErrors,
    required this.onFieldChanged,
    required this.fieldKeyFor,
    required this.aliasFieldKeys,
    this.previousWeight,
    this.heightReadOnly = false,
    this.gestationalWeeks,
    this.ancVisitNumber = 1,
    this.pncVisitNumber = 1,
    this.ageInMonths,
    this.isNcdFollowUp = false,
    this.isNewEnrolment = false,
  });

  final FormSection section;
  final FormConfig config;
  final CanonicalVisitData data;
  final Set<String> validationErrors;
  final void Function(String fieldId, dynamic value) onFieldChanged;

  /// Returns (creating if absent) the anchor key used to scroll to this field
  /// on a failed submit — see `_UnifiedFormScreenState._fieldKeyFor`.
  final GlobalKey Function(String fieldId) fieldKeyFor;

  /// Registers a shared anchor key under every id a composite row covers
  /// (e.g. the BP+pulse card under `systolic`/`diastolic`/`pulse`).
  final void Function(Set<String> ids, GlobalKey key) aliasFieldKeys;

  /// Weight (kg) from the patient's most-recent prior ANC visit — used to
  /// compute the weight-delta badge.  `null` when unavailable.
  final double? previousWeight;

  /// When true, height was prefilled from a prior visit and cannot be edited.
  final bool heightReadOnly;

  /// Patient's current gestational age in weeks — used to compute the
  /// fundal-height expected value and lag/ahead badge.  `null` when unknown.
  final int? gestationalWeeks;

  /// 1-based ANC visit count for Android visit-number field gates.
  final int ancVisitNumber;

  /// 1-based PNC mother visit count — visit 2+ hides chronic illness radios.
  final int pncVisitNumber;

  /// Child age in whole months — childhood visit age bands / weight range.
  final int? ageInMonths;

  /// Android BDNCD SK: prior NCD assessment exists (follow-up visit).
  final bool isNcdFollowUp;

  /// True when this section belongs to a newly enrolled programme.
  /// Renders with a tinted background + accent border.
  final bool isNewEnrolment;

  // ── Tri-state clinical-severity chip colors ───────────────────────────────
  // Danger-sign-adjacent Yes/No/tri-state fields where the mockup colors
  // each option by clinical meaning rather than the generic navy selected
  // state — keyed by field id, then by the option's exact display name
  // (not id) since RadioFormField operates on display names.
  /// Severity colors keyed by option **id** (Android stores id, not label).
  static const Map<String, Map<String, Color>> _severityColorsByField = {
    'urinaryAlbumin': {
      'Present': AppColors.statusCritical,
      'present': AppColors.statusCritical,
      'Absent': AppColors.statusSuccess,
      'absent': AppColors.statusSuccess,
    },
    'fetalMovement': {
      'notFelt': AppColors.statusCritical,
      'lessThanUsual': AppColors.statusWarning,
      'normal': AppColors.statusSuccess,
    },
  };

  // ── Supplement pair detection ─────────────────────────────────────────────
  // Maps each numeric "consumed" field id → (possible "provided" field ids,
  // outer card label, emoji). TextLabel ids (ifaTablets / calciumTablets) are
  // NOT pair drivers — they are section headings skipped when a pair renders
  // (Android: one consumed + one provided under a single label).
  static Map<String, ({Set<String> providedIds, String label, String subLabel, String emoji})>
      get _supplementConsumedMap => {
    'folicAcidTotalConsumed': (
      providedIds: {'folicAcidProvided', 'folicAcidTablets'},
      label: UnifiedFormStrings.folatePairLabel,
      subLabel: UnifiedFormStrings.folatePairSubLabel,
      emoji: '💊',
    ),
    'ifaTotalConsumed': (
      providedIds: {'ifaProvided', 'ifaTabletsProvided'},
      label: UnifiedFormStrings.ifaPairLabel,
      subLabel: UnifiedFormStrings.ifaPairSubLabel,
      emoji: '🩸',
    ),
    'ifaTabletsConsumed': (
      providedIds: {'ifaProvided', 'ifaTabletsProvided'},
      label: UnifiedFormStrings.ifaPairLabel,
      subLabel: UnifiedFormStrings.ifaPairSubLabel,
      emoji: '🩸',
    ),
    'calciumTotalConsumed': (
      providedIds: {'calciumProvided', 'calciumTabletsProvided'},
      label: UnifiedFormStrings.calciumPairLabel,
      subLabel: UnifiedFormStrings.calciumPairSubLabel,
      emoji: '🦴',
    ),
    'calciumTabletsConsumed': (
      providedIds: {'calciumProvided', 'calciumTabletsProvided'},
      label: UnifiedFormStrings.calciumPairLabel,
      subLabel: UnifiedFormStrings.calciumPairSubLabel,
      emoji: '🦴',
    ),
  };

  bool _isVisibleById(String fieldId) {
    final def = config.fields[fieldId];
    if (def == null) return false;
    return FieldVisibilityRules.isFieldVisible(
      field: def,
      data: data,
      rulesByTargetId: config.visibilityRulesByTargetId,
      gestationalWeeks: gestationalWeeks,
      ancVisitNumber: ancVisitNumber,
      pncVisitNumber: pncVisitNumber,
      formType: section.formType,
      ageInMonths: ageInMonths,
      priorHeightLocked: heightReadOnly,
      isNcdFollowUp: isNcdFollowUp,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic N baby cards driven by liveBirthNumbers (Android
    // AssessmentPregnancyOutcomeFragment.updateBabySections).
    if (section.sectionId == 'newbornDetails' &&
        section.formType == 'pregnancyOutcome') {
      return _buildNewbornDetailsSection(context);
    }

    // Pre-compute the set of ref IDs in this section so all pair detectors
    // work regardless of field ordering.
    final sectionIds = section.fieldRefs.map((r) => r.id).toSet();

    final hasBpPair = sectionIds.contains('systolic') &&
        sectionIds.contains('diastolic');

    final hasBpPulseTriple = hasBpPair && sectionIds.contains('pulse');

    // Blood-glucose pair: fasting + random shown side-by-side, but only while
    // both are actually visible. PNC's `bloodSugar` selector reveals exactly
    // one of them (Spice rmnch_pnc_visit.json), and the pair card would then
    // swallow the very field the SK just asked for.
    final hasGlucosePair = sectionIds.contains('fastingBloodSugar') &&
        sectionIds.contains('randomBloodSugar') &&
        _isVisibleById('fastingBloodSugar') &&
        _isVisibleById('randomBloodSugar');

    // BloodGlucoseEntry drives both type toggle and numeric value via 'glucose'.
    // The standalone 'glucose' EditText must not render alongside it.
    final hasBloodGlucoseEntry = sectionIds.contains('glucoseType');

    // Height + weight pair: physical measurements shown side-by-side.
    // When ANC visit 2+ hides height, keep the pair shell and show weight only
    // so standalone weight is not dropped with the absorbed consumedIds entry.
    final heightInSection = sectionIds.contains('height');
    final weightInSection = sectionIds.contains('weight');
    final heightVisible = heightInSection && _isVisibleById('height');
    final weightVisible = weightInSection && _isVisibleById('weight');
    final hasHeightWeightPair =
        heightInSection && weightInSection && (heightVisible || weightVisible);

    // For each supplement consumed field, find which provided field (if any) is
    // present in the same section, so we can render a combined pair card.
    final Map<String, String?> supplementConsumedToProvidedRef = {};
    for (final entry in _supplementConsumedMap.entries) {
      if (sectionIds.contains(entry.key)) {
        final matchedProvided = entry.value.providedIds
            .cast<String?>()
            .firstWhere(sectionIds.contains, orElse: () => null);
        supplementConsumedToProvidedRef[entry.key] = matchedProvided;
      }
    }

    // TextLabel heading → consumed field that owns the pair card title.
    const supplementLabelForConsumed = {
      'ifaTablets': 'ifaTabletsConsumed',
      'calciumTablets': 'calciumTabletsConsumed',
      'folicAcidTablets': 'folicAcidTotalConsumed',
    };
    // IDs absorbed into a composite widget — skip when encountered individually.
    final consumedIds = <String>{
      // When a combined BP card is rendered, skip the standalone fields.
      if (hasBpPair) ...const {'bloodPressure', 'diastolic'},
      // When pulse is in the same section, absorb it into the BP card.
      if (hasBpPulseTriple) 'pulse',
      // Combined glucose pair — skip the random field (fasting card drives).
      if (hasGlucosePair) 'randomBloodSugar',
      // BloodGlucoseEntry handles glucose numeric value — skip the standalone field.
      if (hasBloodGlucoseEntry) ...const {'glucose', 'bloodSugar', 'ancBloodGlucose'},
      // Combined height+weight pair — skip weight (height card drives) when
      // height is visible; when height is hidden, skip height and let weight
      // drive the weight-only pair shell.
      if (hasHeightWeightPair && heightVisible) 'weight',
      if (hasHeightWeightPair && !heightVisible && weightVisible) 'height',
      // For each supplement pair, skip the "provided" counterpart field —
      // it will be rendered inline inside the consumed field's pair card.
      for (final p in supplementConsumedToProvidedRef.values) ?p,
      // Skip TextLabel headings when that supplement's pair card is present.
      for (final e in supplementLabelForConsumed.entries)
        if (supplementConsumedToProvidedRef[e.value] != null) e.key,
    };

    bool bpPairEmitted = false;
    bool glucosePairEmitted = false;
    bool heightWeightPairEmitted = false;

    // AI-provenance marking: fields filled by the realtime ASR scribe and
    // not yet reviewed render with a small "AI — verify" badge so the SK can
    // distinguish auto-filled values from typed ones. watch() keeps badges
    // live as extractions land / the SK edits.
    final notifier = context.watch<UnifiedFormNotifier>();
    bool aiPending(String fieldId) =>
        notifier.fieldSource(fieldId) == FieldSource.aiPending;

    final fieldWidgets = <Widget>[];
    // Sequential question numbering (matches the design mockup) — scoped to
    // the pregnancy-history section only, not a global _FieldLabel change.
    // Only counts fields that actually render, so a hidden question (e.g.
    // Parity before Gravida >= 2) doesn't leave a gap in the sequence.
    var pregnancyHistoryQuestionNumber = 0;
    for (final ref in section.fieldRefs) {
      if (consumedIds.contains(ref.id)) continue;

      final libraryDef = config.fields[ref.id];
      if (libraryDef == null) continue;
      final def = ref.options != null
          ? libraryDef.withOptions(ref.options!)
          : libraryDef;
      final visible = FieldVisibilityRules.isFieldVisible(
        field: def,
        data: data,
        rulesByTargetId: config.visibilityRulesByTargetId,
        gestationalWeeks: gestationalWeeks,
        ancVisitNumber: ancVisitNumber,
        pncVisitNumber: pncVisitNumber,
        formType: section.formType,
        ageInMonths: ageInMonths,
        priorHeightLocked: heightReadOnly,
        isNcdFollowUp: isNcdFollowUp,
      );
      if (section.formType == 'pregnancyOutcome') {
        // ignore: avoid_print
        print('[FieldVisibility] pregnancyOutcome.${section.sectionId}.${ref.id} '
            'baseVisibility=${def.visibility} visible=$visible '
            'deliveryOutcomeType=${data.getValue('deliveryOutcomeType')}');
      }
      if (!visible) {
        continue;
      }
      final questionNumber = section.sectionId == 'pregnancyHistory'
          ? ++pregnancyHistoryQuestionNumber
          : null;

      // IDs whose AI-pending state lights this widget's badge (composite
      // cards cover their absorbed counterpart fields too).
      var badgeIds = <String>{ref.id};

      Widget child;
      if (ref.id == 'systolic' && hasBpPair) {
        // Emit the combined BP card once (with optional pulse).
        if (!bpPairEmitted) {
          bpPairEmitted = true;
          badgeIds = {'systolic', 'diastolic', 'pulse', 'bpLogDetails'};
          final diaRef = section.fieldRefs.firstWhere((r) => r.id == 'diastolic');
          final diaDef = config.fields['diastolic'];
          if (diaDef != null) {
            final pulseRef = hasBpPulseTriple
                ? section.fieldRefs.cast<FieldRef?>().firstWhere(
                    (r) => r?.id == 'pulse', orElse: () => null)
                : null;
            final pulseDef = pulseRef != null ? config.fields['pulse'] : null;
            child = _bpPairCard(
              context, def, ref, diaDef, diaRef,
              pulseDef: pulseDef, pulseRef: pulseRef,
            );
          } else {
            child = _fieldRow(context, def, ref, questionNumber: questionNumber);
          }
        } else {
          continue;
        }
      } else if (ref.id == 'fastingBloodSugar' && hasGlucosePair) {
        // Emit the combined glucose pair card once (fasting drives, random follows).
        if (!glucosePairEmitted) {
          glucosePairEmitted = true;
          badgeIds = {'fastingBloodSugar', 'randomBloodSugar'};
          final randomRef = section.fieldRefs.firstWhere((r) => r.id == 'randomBloodSugar');
          final randomDef = config.fields['randomBloodSugar'];
          if (randomDef != null) {
            child = _glucosePairCard(context, def, ref, randomDef, randomRef);
          } else {
            child = _fieldRow(context, def, ref, questionNumber: questionNumber);
          }
        } else {
          continue;
        }
      } else if (ref.id == 'height' && hasHeightWeightPair && heightVisible) {
        // Emit the combined height + weight pair card once.
        if (!heightWeightPairEmitted) {
          heightWeightPairEmitted = true;
          badgeIds = {
            if (heightVisible) 'height',
            if (weightVisible) 'weight',
          };
          final weightRef =
              section.fieldRefs.firstWhere((r) => r.id == 'weight');
          final weightDef = config.fields['weight'];
          if (weightDef != null && weightVisible) {
            child = _heightWeightPairCard(
              context,
              def,
              ref,
              weightDef,
              weightRef,
              showHeight: true,
            );
          } else {
            child = _fieldRow(context, def, ref, questionNumber: questionNumber);
          }
        } else {
          continue;
        }
      } else if (ref.id == 'weight' &&
          hasHeightWeightPair &&
          !heightVisible &&
          weightVisible) {
        // Height hidden (ANC visit 2+ / NCD prior lock) — weight-only pair.
        if (!heightWeightPairEmitted) {
          heightWeightPairEmitted = true;
          badgeIds = {'weight'};
          final heightRef =
              section.fieldRefs.firstWhere((r) => r.id == 'height');
          final heightDef = config.fields['height'];
          if (heightDef != null) {
            child = _heightWeightPairCard(
              context,
              heightDef,
              heightRef,
              def,
              ref,
              showHeight: false,
            );
          } else {
            child = _fieldRow(context, def, ref, questionNumber: questionNumber);
          }
        } else {
          continue;
        }
      } else if (_supplementConsumedMap.containsKey(ref.id) &&
          supplementConsumedToProvidedRef.containsKey(ref.id)) {
        // Emit supplement pair card (consumed + provided side-by-side).
        final meta = _supplementConsumedMap[ref.id]!;
        final providedId = supplementConsumedToProvidedRef[ref.id];
        if (providedId != null) {
          final providedDef = config.fields[providedId];
          if (providedDef != null) {
            child = _supplementPairCard(context, def, ref, providedDef, providedId, meta);
          } else {
            child = _fieldRow(context, def, ref, questionNumber: questionNumber);
          }
        } else {
          child = _fieldRow(context, def, ref, questionNumber: questionNumber);
        }
      } else {
        child = _fieldRow(context, def, ref, questionNumber: questionNumber);
      }

      if (badgeIds.any(aiPending)) {
        child = _AiFilledBadgeWrap(child: child);
      }

      // Zero-height anchor so a failed submit can scroll straight to this
      // exact field (or, for composite rows, to the shared card) instead of
      // just its section — aliased under every id the row covers. Scoped by
      // formType_sectionId (matching _sectionKeys) since the same field id
      // (e.g. "weight") can legitimately appear in more than one
      // concurrently-mounted section on a combined-programme visit — a bare
      // field-id key would collide across them ("Duplicate GlobalKeys").
      String scopedFieldId(String id) =>
          '${section.formType}_${section.sectionId}_$id';
      final fieldAnchorKey = fieldKeyFor(scopedFieldId(ref.id));
      aliasFieldKeys(badgeIds.map(scopedFieldId).toSet(), fieldAnchorKey);

      fieldWidgets.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(key: fieldAnchorKey, height: 0),
            child,
          ],
        ),
      ));
    }

    if (section.formType == 'pregnancyOutcome') {
      // ignore: avoid_print
      print('[FieldRender] pregnancyOutcome.${section.sectionId} '
          'rendered=${fieldWidgets.length}/${section.fieldRefs.length} fields');
    }

    // Spice CardViews with every child gone are not drawn — skip empty
    // section chrome (cataract BP/glucose/referral before their gates fire).
    if (fieldWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    final inner = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Text(
              FormSectionStrings.headerFor(section.sectionId, section.title),
              style: AppTextStyles.sectionLabel,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          ...fieldWidgets,
        ],
      ),
    );

    if (!isNewEnrolment) return inner;

    final bg = _newEnrolmentBg(section.formType);
    final accent = _newEnrolmentAccent(section.formType);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent, width: 1.5),
      ),
      child: inner,
    );
  }

  /// One card per live birth (isBabyAlive / sex / causeOfNeonatalDeath).
  Widget _buildNewbornDetailsSection(BuildContext context) {
    final notifier = context.watch<UnifiedFormNotifier>();
    final raw = notifier.data.getValue('newbornDetails');
    final babies = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) babies.add(Map<String, dynamic>.from(e));
      }
    }

    final aliveDef = config.fields['babyAlive'];
    final sexDef = config.fields['babySex'];
    final causeDef = config.fields['neonatalDeathCause'];
    final aliveOptions = aliveDef?.options ??
        const [
          FieldOption(id: 'Yes', name: 'Yes'),
          FieldOption(id: 'No', name: 'No'),
        ];
    final sexOptions = sexDef?.options ?? const [];
    final causeOptions = causeDef?.options ?? const [];

    final cards = <Widget>[];
    for (var i = 0; i < babies.length; i++) {
      final baby = babies[i];
      final alive = baby['isBabyAlive']?.toString();
      final sex = baby['sex']?.toString();
      final causeRaw = baby['causeOfNeonatalDeath'];
      final causeIds = causeRaw is List
          ? causeRaw.map((e) => e.toString()).toList()
          : (causeRaw is String && causeRaw.isNotEmpty
              ? <String>[causeRaw]
              : <String>[]);
      final showCause = alive?.toLowerCase() == 'no';
      final aliveError =
          validationErrors.contains('newbornDetails_${i}_isBabyAlive');
      final sexError = validationErrors.contains('newbornDetails_${i}_sex');
      final causeError =
          validationErrors.contains('newbornDetails_${i}_causeOfNeonatalDeath');

      cards.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                UnifiedFormStrings.babyNumberLabel(i + 1),
                style: AppTextStyles.sectionLabel,
              ),
              const SizedBox(height: AppSpacing.md),
              _FieldShell(
                label: aliveDef?.displayLabel ??
                    UnifiedFormStrings.babyAliveLabel,
                isMandatory: true,
                hasError: aliveError,
                child: RadioFormField(
                  key: Key('unified_form_newborn_${i}_alive'),
                  options: aliveOptions
                      .map((o) => RadioOption(id: o.id, label: o.displayName))
                      .toList(),
                  currentValue: FieldOption.matchId(alive, aliveOptions),
                  onChanged: (id) =>
                      notifier.updateNewbornField(i, 'isBabyAlive', id),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _FieldShell(
                label: sexDef?.displayLabel ?? UnifiedFormStrings.babySexLabel,
                isMandatory: true,
                hasError: sexError,
                child: RadioFormField(
                  key: Key('unified_form_newborn_${i}_sex'),
                  options: sexOptions
                      .map((o) => RadioOption(id: o.id, label: o.displayName))
                      .toList(),
                  currentValue: FieldOption.matchId(sex, sexOptions),
                  onChanged: (id) =>
                      notifier.updateNewbornField(i, 'sex', id),
                ),
              ),
              if (showCause) ...[
                const SizedBox(height: AppSpacing.md),
                _InlineListSelectField(
                  key: Key('unified_form_newborn_${i}_cause'),
                  label: causeDef?.displayLabel ??
                      UnifiedFormStrings.neonatalDeathCauseLabel,
                  subLabel: null,
                  isMandatory: true,
                  hasError: causeError,
                  options: causeOptions.map((o) => o.displayName).toList(),
                  selectedValues: causeIds.map((sid) {
                    return causeOptions
                            .cast<FieldOption?>()
                            .firstWhere(
                              (o) => o!.id == sid || o.name == sid,
                              orElse: () => null,
                            )
                            ?.displayName ??
                        sid;
                  }).toList(),
                  onChanged: (names) {
                    final ids = names.map((n) {
                      return causeOptions
                              .cast<FieldOption?>()
                              .firstWhere(
                                (o) =>
                                    o!.displayName == n ||
                                    o.name == n ||
                                    o.id == n,
                                orElse: () => null,
                              )
                              ?.id ??
                          n;
                    }).toList();
                    notifier.updateNewbornField(
                      i,
                      'causeOfNeonatalDeath',
                      ids,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ));
    }

    if (babies.isEmpty) {
      cards.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Text(
          UnifiedFormStrings.newbornDetailsPrompt,
          style: AppTextStyles.subText,
        ),
      ));
    }

    final inner = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Text(
              FormSectionStrings.headerFor(section.sectionId, section.title),
              style: AppTextStyles.sectionLabel,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          ...cards,
        ],
      ),
    );

    if (!isNewEnrolment) return inner;
    final bg = _newEnrolmentBg(section.formType);
    final accent = _newEnrolmentAccent(section.formType);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent, width: 1.5),
      ),
      child: inner,
    );
  }

  /// Renders a combined Blood Pressure card with systolic / diastolic inputs
  /// side-by-side in one [_FieldShell].  When [pulseDef] / [pulseRef] are
  /// supplied the pulse input is appended in the same row after diastolic.
  Widget _bpPairCard(
    BuildContext context,
    FieldDef sysDef,
    FieldRef sysRef,
    FieldDef diaDef,
    FieldRef diaRef, {
    FieldDef? pulseDef,
    FieldRef? pulseRef,
  }) {
    final hasError = validationErrors.contains(sysRef.id) ||
        validationErrors.contains(diaRef.id) ||
        (pulseRef != null && validationErrors.contains(pulseRef.id));
    final isMandatory = sysDef.isMandatory ||
        sysRef.isMandatory ||
        diaDef.isMandatory ||
        diaRef.isMandatory ||
        (pulseDef?.isMandatory ?? false) ||
        (pulseRef?.isMandatory ?? false);
    final bpStatus = _VitalStatusEval.bloodPressure(
      _VitalStatusEval.asInt(data.getValue('systolic')),
      _VitalStatusEval.asInt(data.getValue('diastolic')),
    );

    final subLabel = pulseDef != null
        ? '${UnifiedFormStrings.bpUnit} · ${UnifiedFormStrings.bpPulseUnit}'
        : UnifiedFormStrings.bpUnit;

    return _FieldShell(
      label: UnifiedFormStrings.bpCardLabel,
      subLabel: subLabel,
      emoji: '🩺',
      emojiBg: const Color(0xFFEEF0FF),
      isMandatory: isMandatory,
      hasError: hasError,
      statusBadge: bpStatus != null
          ? _VitalBadge(label: bpStatus.label, color: bpStatus.color)
          : null,
      infoText: sysDef.isInfoVisible ? sysDef.displayInfoTitle : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _NumericField(
              key: const Key('unified_form_systolic_input'),
              isDecimal: false,
              hint: UnifiedFormStrings.bpSystolicLabel,
              initialValue: data.getValue('systolic')?.toString(),
              onChanged: (v) {
                if (v == null || v.isEmpty) {
                  onFieldChanged('systolic', null);
                } else {
                  onFieldChanged('systolic', int.tryParse(v) ?? double.tryParse(v) ?? v);
                }
              },
              validator: _numericRangeValidator('systolic'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 6, right: 6),
            child: Text(
              '/',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(
            child: _NumericField(
              key: const Key('unified_form_diastolic_input'),
              isDecimal: false,
              hint: UnifiedFormStrings.bpDiastolicLabel,
              initialValue: data.getValue('diastolic')?.toString(),
              onChanged: (v) {
                if (v == null || v.isEmpty) {
                  onFieldChanged('diastolic', null);
                } else {
                  onFieldChanged('diastolic', int.tryParse(v) ?? double.tryParse(v) ?? v);
                }
              },
              validator: _numericRangeValidator('diastolic'),
            ),
          ),
          if (pulseDef != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 6, right: 6),
              child: Text(
                '·',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Expanded(
              child: _NumericField(
                key: const Key('unified_form_pulse_input'),
                isDecimal: false,
                hint: 'Pulse',
                initialValue: data.getValue('pulse')?.toString(),
                onChanged: (v) {
                  if (v == null || v.isEmpty) {
                    onFieldChanged('pulse', null);
                  } else {
                    onFieldChanged('pulse', int.tryParse(v) ?? double.tryParse(v) ?? v);
                  }
                },
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = num.tryParse(v);
                  if (n == null || n < pulseFormMin || n > pulseFormMax) {
                    return ComposerStrings.pulseValidationError;
                  }
                  return null;
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Android TextLabel id that owns the outer pair-card heading for a
  /// consumed field (Spice `rmnch_*_visit.json` section titles).
  static const _supplementHeadingForConsumed = {
    'ifaTabletsConsumed': 'ifaTablets',
    'ifaTotalConsumed': 'ifaTablets',
    'calciumTabletsConsumed': 'calciumTablets',
    'calciumTotalConsumed': 'calciumTablets',
    'folicAcidTotalConsumed': 'folicAcidTablets',
  };

  /// Renders a supplement pair card — outer [_FieldShell] with the supplement
  /// name and Bengali label, containing "consumed" and "provided" inputs
  /// side-by-side. Column / heading copy comes from field_library (Android
  /// title / titleCulture), not the shared ANC-oriented string defaults.
  Widget _supplementPairCard(
    BuildContext context,
    FieldDef consumedDef,
    FieldRef consumedRef,
    FieldDef providedDef,
    String providedId,
    ({Set<String> providedIds, String label, String subLabel, String emoji}) meta,
  ) {
    final hasError = validationErrors.contains(consumedRef.id) ||
        validationErrors.contains(providedId);
    final isMandatory = consumedDef.isMandatory ||
        consumedRef.isMandatory ||
        providedDef.isMandatory;
    final headingId = _supplementHeadingForConsumed[consumedRef.id];
    final headingDef = headingId != null ? config.fields[headingId] : null;
    final outerLabel = headingDef?.displayLabel ?? meta.label;
    return _FieldShell(
      label: outerLabel,
      // Locale-pure primary label only — no second-language sub-line.
      subLabel: null,
      emoji: meta.emoji,
      emojiBg: const Color(0xFFF0FDF4),
      isMandatory: isMandatory,
      hasError: hasError,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  consumedDef.displayLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${consumedRef.id}_input'),
                  isDecimal: false,
                  hint: consumedDef.displayHint,
                  initialValue: data.getValue(consumedRef.id)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(consumedRef.id, null);
                    } else {
                      onFieldChanged(consumedRef.id, int.tryParse(v) ?? v);
                    }
                  },
                  validator: _numericRangeValidator(
                    consumedRef.id,
                    formType: section.formType,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  providedDef.displayLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${providedId}_input'),
                  isDecimal: false,
                  hint: providedDef.displayHint,
                  initialValue: data.getValue(providedId)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(providedId, null);
                    } else {
                      onFieldChanged(providedId, int.tryParse(v) ?? v);
                    }
                  },
                  validator: _numericRangeValidator(
                    providedId,
                    formType: section.formType,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders a combined Blood Glucose card — fasting and random inputs
  /// side-by-side under a shared header, with a rule-based elevation badge
  /// and an inline GDM / diabetes warning when values are high.
  Widget _glucosePairCard(
    BuildContext context,
    FieldDef fastingDef,
    FieldRef fastingRef,
    FieldDef randomDef,
    FieldRef randomRef,
  ) {
    final fastingVal = _VitalStatusEval.asDouble(data.getValue(fastingRef.id));
    final randomVal  = _VitalStatusEval.asDouble(data.getValue(randomRef.id));
    final glucoseStatus = _VitalStatusEval.bloodGlucose(fastingVal, randomVal);
    final hasError = validationErrors.contains(fastingRef.id) ||
        validationErrors.contains(randomRef.id);
    final isMandatory = fastingDef.isMandatory || fastingRef.isMandatory ||
        randomDef.isMandatory || randomRef.isMandatory;
    return _FieldShell(
      label: UnifiedFormStrings.glucosePairLabel,
      subLabel: UnifiedFormStrings.bloodGlucoseEntryUnit,
      emoji: '🩸',
      emojiBg: const Color(0xFFFFF1F2),
      isMandatory: isMandatory,
      hasError: hasError,
      statusBadge: glucoseStatus != null
          ? _VitalBadge(label: glucoseStatus.label, color: glucoseStatus.color)
          : null,
      inlineWarning: glucoseStatus?.warning,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UnifiedFormStrings.glucoseFastingLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${fastingRef.id}_input'),
                  isDecimal: true,
                  unit: 'mmol/L',
                  initialValue: data.getValue(fastingRef.id)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(fastingRef.id, null);
                    } else {
                      onFieldChanged(fastingRef.id, double.tryParse(v) ?? v);
                    }
                  },
                  validator: _numericRangeValidator(
                    fastingRef.id,
                    formType: section.formType,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UnifiedFormStrings.glucoseRandomLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${randomRef.id}_input'),
                  isDecimal: true,
                  unit: 'mmol/L',
                  initialValue: data.getValue(randomRef.id)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(randomRef.id, null);
                    } else {
                      onFieldChanged(randomRef.id, double.tryParse(v) ?? v);
                    }
                  },
                  validator: _numericRangeValidator(
                    randomRef.id,
                    formType: section.formType,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders a combined Height + Weight card — both numeric inputs side-by-side
  /// under a single header.  The weight-delta badge and "Last: X kg" sub-info
  /// are shown in the header when prior weight data is available.
  ///
  /// When [showHeight] is false (ANC visit 2+), only the weight column is
  /// rendered inside the same pair shell — height stays in form data/payload.
  Widget _heightWeightPairCard(
    BuildContext context,
    FieldDef heightDef,
    FieldRef heightRef,
    FieldDef weightDef,
    FieldRef weightRef, {
    bool showHeight = true,
  }) {
    final hasError = (showHeight && validationErrors.contains(heightRef.id)) ||
        validationErrors.contains(weightRef.id);
    final isMandatory = (showHeight &&
            (heightDef.isMandatory || heightRef.isMandatory)) ||
        weightDef.isMandatory ||
        weightRef.isMandatory;
    final currentWeight = _VitalStatusEval.asDouble(data.getValue(weightRef.id));
    final weightStatus = _VitalStatusEval.weight(currentWeight, previousWeight);
    // Sub-label: last weight info when available (no second language line).
    final subLabel = previousWeight != null
        ? UnifiedFormStrings.vsLastWeight(previousWeight!)
        : null;
    final weightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeight)
          Text(
            UnifiedFormStrings.weightSubLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        if (showHeight) const SizedBox(height: 5),
        _NumericField(
          key: Key('unified_form_${weightRef.id}_input'),
          isDecimal: true,
          unit: 'kg',
          initialValue: data.getValue(weightRef.id)?.toString(),
          onChanged: (v) {
            if (v == null || v.isEmpty) {
              onFieldChanged(weightRef.id, null);
            } else {
              onFieldChanged(weightRef.id, double.tryParse(v) ?? v);
            }
          },
        ),
      ],
    );
    return _FieldShell(
      label: showHeight
          ? UnifiedFormStrings.heightWeightPairLabel
          : UnifiedFormStrings.weightSubLabel,
      subLabel: subLabel,
      emoji: showHeight ? '📐' : '⚖️',
      emojiBg: const Color(0xFFEEF2FF),
      isMandatory: isMandatory,
      hasError: hasError,
      statusBadge: weightStatus != null
          ? _VitalBadge(label: weightStatus.label, color: weightStatus.color)
          : null,
      child: showHeight
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UnifiedFormStrings.heightSubLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _NumericField(
                        key: Key('unified_form_${heightRef.id}_input'),
                        isDecimal: true,
                        unit: 'cm',
                        readOnly: heightReadOnly,
                        initialValue: data.getValue(heightRef.id)?.toString(),
                        onChanged: (v) {
                          if (heightReadOnly) return;
                          if (v == null || v.isEmpty) {
                            onFieldChanged(heightRef.id, null);
                          } else {
                            onFieldChanged(
                                heightRef.id, double.tryParse(v) ?? v);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: weightColumn),
              ],
            )
          : weightColumn,
    );
  }

  /// Builds one field row: self-contained fields (info / text label) render
  /// bare; [dialogCheckbox] renders fully standalone (owns its own label +
  /// option list).  Every other editable field is wrapped in [_FieldShell].
  ///
  /// For the handful of vital-sign fields that have clinical rules (weight,
  /// fundal height, urine albumin, haemoglobin), a [_VitalBadge] and optional
  /// inline warning are computed from the current field value and appended.
  Widget _fieldRow(
    BuildContext context,
    FieldDef def,
    FieldRef ref, {
    int? questionNumber,
  }) {
    final currentValue = data.getValue(ref.id);
    final control =
        _buildField(context, def, ref, currentValue, questionNumber: questionNumber);
    switch (def.widgetHint) {
      case WidgetHint.infoLabel:
        // For BMI, enrich the read-only display with a WHO classification badge.
        if (ref.id == 'bmi') {
          final bmiStatus = _VitalStatusEval.bmi(
            _VitalStatusEval.asDouble(currentValue),
          );
          return _InfoLabelField(
            key: Key('unified_form_${def.id}_info'),
            label: def.displayLabel,
            value: currentValue?.toString(),
            statusBadge: bmiStatus != null
                ? _VitalBadge(label: bmiStatus.label, color: bmiStatus.color)
                : null,
          );
        }
        return control;
      case WidgetHint.textLabel:
        return control;
      // dialogCheckbox renders as a self-contained inline list with its own
      // label header — wrapping it in a _FieldShell would double the label.
      case WidgetHint.dialogCheckbox:
        return control;
      // bloodGlucoseEntry is self-contained: it wraps its own _FieldShell and
      // manages both glucoseType + glucose inline, so skip the outer shell.
      case WidgetHint.bloodGlucoseEntry:
        return control;
      default:
        final glyph = FormFieldVisuals.forField(def.id);
        final unit = def.unitMeasurement;

        // ── Vital-status enrichment (per-field rules) ─────────────────────
        // subLabel is unit / clinical extras only — never a second language.
        _VitalStatus? vitalStatus;
        List<String> subParts = [
          if (unit != null && unit.isNotEmpty) unit,
        ];

        switch (ref.id) {
          case 'weight':
            final w = _VitalStatusEval.asDouble(currentValue);
            vitalStatus = _VitalStatusEval.weight(w, previousWeight);
            if (previousWeight != null) {
              subParts = [
                if (unit != null && unit.isNotEmpty) unit,
                UnifiedFormStrings.vsLastWeight(previousWeight!),
              ];
            }

          case 'fundalHeight':
            final fh = _VitalStatusEval.asDouble(currentValue);
            vitalStatus = _VitalStatusEval.fundalHeight(fh, gestationalWeeks);
            if (gestationalWeeks != null) {
              subParts = [
                if (unit != null && unit.isNotEmpty) unit,
                UnifiedFormStrings.vsFhExpectedSubLabel(gestationalWeeks!),
              ];
            }

          case 'urinaryAlbumin':
            vitalStatus =
                _VitalStatusEval.urinaryAlbumin(currentValue as String?);

          case 'hemoglobin':
            vitalStatus =
                _VitalStatusEval.hemoglobin(_VitalStatusEval.asDouble(currentValue));

          case 'fastingBloodSugar':
            vitalStatus = _VitalStatusEval.bloodGlucose(
              _VitalStatusEval.asDouble(currentValue),
              null,
            );

          case 'randomBloodSugar':
            vitalStatus = _VitalStatusEval.bloodGlucose(
              null,
              _VitalStatusEval.asDouble(currentValue),
            );

          case 'bpLogDetails':
            // NCD's composite BP widget (_BpReadingField) — reuse the
            // existing badge/color logic rather than reimplementing it,
            // but with NCD's own thresholds (different from ANC's).
            final readings = currentValue is List
                ? currentValue.cast<Map<String, dynamic>>()
                : const <Map<String, dynamic>>[];
            if (readings.isNotEmpty) {
              final reading = readings.first;
              vitalStatus = _VitalStatusEval.bloodPressureNcd(
                _VitalStatusEval.asInt(reading['systolic']),
                _VitalStatusEval.asInt(reading['diastolic']),
              );
            }
        }

        // Layout fieldName disambiguates shared library labels (e.g. three
        // medication questions on NCD). Bangla uses fieldNameCulture when set,
        // else library titleCulture; English uses fieldName when set.
        final override = ref.fieldName?.trim();
        final overrideBn = ref.fieldNameCulture?.trim();
        final String primary;
        if (AppLocale.isBangla &&
            overrideBn != null &&
            overrideBn.isNotEmpty) {
          primary = overrideBn;
        } else if (!AppLocale.isBangla &&
            override != null &&
            override.isNotEmpty) {
          primary = override;
        } else {
          primary = def.displayLabel;
        }
        return _FieldShell(
          label: questionNumber != null ? '$questionNumber. $primary' : primary,
          subLabel: subParts.isEmpty ? null : subParts.join(' · '),
          emoji: glyph?.emoji,
          emojiBg: glyph?.background,
          isMandatory: def.isMandatory || ref.isMandatory,
          hasError: validationErrors.contains(ref.id),
          statusBadge: vitalStatus != null
              ? _VitalBadge(label: vitalStatus.label, color: vitalStatus.color)
              : null,
          inlineWarning: vitalStatus?.warning,
          infoText: def.isInfoVisible ? def.displayInfoTitle : null,
          child: control,
        );
    }
  }

  /// Returns a range validator for known clinical numeric fields.
  /// Returns null (no validation) for fields not in the list.
  static FormFieldValidator<String>? _numericRangeValidator(
    String fieldId, {
    String? formType,
    int? ageInMonths,
  }) {
    if (fieldId == 'weight' && formType == 'pncChild') {
      final range = ChildhoodVisit.weightRangeKg(ageInMonths);
      if (range == null) return null;
      final (minW, maxW) = range;
      return (v) {
        if (v == null || v.isEmpty) return null;
        final n = double.tryParse(v);
        if (n == null || n < minW || n > maxW) {
          return 'Enter a weight between $minW and $maxW kg';
        }
        return null;
      };
    }
    // PNC mother: Spice rmnch_pnc_visit.json ranges (form engine).
    if (formType == 'pncMother') {
      switch (fieldId) {
        case 'temperature':
          return (v) {
            if (v == null || v.isEmpty) return null;
            final n = double.tryParse(v);
            // 0 = not measured (Android naValue); else 86–113 °F.
            if (n == null || (n != 0 && (n < 86 || n > 113))) {
              return ComposerStrings.temperatureValidationError;
            }
            return null;
          };
        case 'pulse':
          return (v) {
            if (v == null || v.isEmpty) return null;
            final n = double.tryParse(v);
            if (n == null || n < 20 || n > 150) {
              return 'Enter a pulse between 20 and 150';
            }
            return null;
          };
        case 'weight':
          return (v) {
            if (v == null || v.isEmpty) return null;
            final n = double.tryParse(v);
            if (n == null || (n != 0 && (n < 10 || n > 250))) {
              return 'Enter a weight between 10 and 250 kg';
            }
            return null;
          };
        case 'systolic':
          return (v) {
            if (v == null || v.isEmpty) return null;
            final n = double.tryParse(v);
            if (n == null || (n != 0 && (n < 50 || n > 260))) {
              return ComposerStrings.bpValidationError;
            }
            return null;
          };
        case 'diastolic':
          return (v) {
            if (v == null || v.isEmpty) return null;
            final n = double.tryParse(v);
            if (n == null || (n != 0 && (n < 20 || n > 180))) {
              return ComposerStrings.bpValidationError;
            }
            return null;
          };
        // Hemoglobin / glucose / IFA+Calcium fall through to the shared
        // LeapWell ranges below (1–20, 0–33, max 60).
      }
    }

    switch (fieldId) {
      case 'fastingBloodSugar':
      case 'randomBloodSugar':
      case 'bloodSugarFasting':
      case 'bloodSugarRandom':
      case 'glucose':
        return (v) {
          if (v == null || v.isEmpty) return null;
          final n = double.tryParse(v);
          if (n == null || !isPlausibleGlucoseMmol(n)) {
            return ComposerStrings.glucoseValidationError;
          }
          return null;
        };
      case 'hemoglobin':
        return (v) {
          if (v == null || v.isEmpty) return null;
          final n = double.tryParse(v);
          if (n == null || !isPlausibleHemoglobin(n)) {
            return ComposerStrings.haemoglobinValidationError;
          }
          return null;
        };
      case 'ifaTabletsConsumed':
      case 'ifaTabletsProvided':
      case 'ifaTotalConsumed':
      case 'ifaProvided':
      case 'calciumTabletsConsumed':
      case 'calciumTabletsProvided':
      case 'calciumTotalConsumed':
      case 'calciumProvided':
        return (v) {
          if (v == null || v.isEmpty) return null;
          final n = double.tryParse(v);
          if (n == null || !isPlausibleSupplementTablets(n)) {
            return ComposerStrings.tabletCountValidationError;
          }
          return null;
        };
      case 'temperature':
        return (v) {
          if (v == null || v.isEmpty) return null;
          final n = double.tryParse(v);
          if (n == null || !isPlausibleTemperatureF(n)) {
            return ComposerStrings.temperatureValidationError;
          }
          return null;
        };
      case 'systolic':
      case 'diastolic':
        return (v) {
          if (v == null || v.isEmpty) return null;
          final n = double.tryParse(v);
          if (n == null || !isPlausibleBpReading(n)) {
            return ComposerStrings.bpValidationError;
          }
          return null;
        };
      case 'fundalHeight':
        return (v) {
          if (v == null || v.isEmpty) return null;
          final n = double.tryParse(v);
          if (n == null || !isPlausibleFundalHeightCm(n)) {
            return ComposerStrings.fundalHeightValidationError;
          }
          return null;
        };
      default:
        return null;
    }
  }

  /// True when a spinner's options are a boolean Yes/No pair — these render as
  /// pill buttons rather than a dropdown. Matches on id or display name so a
  /// localised label (titleCulture) does not defeat the check.
  static bool _isYesNoOptions(List<FieldOption> options) {
    if (options.isEmpty || options.length > 2) return false;
    const yesNo = {'yes', 'no'};
    return options.every((o) =>
        yesNo.contains(o.id.toLowerCase()) ||
        yesNo.contains(o.name.toLowerCase()));
  }

  Widget _buildField(
    BuildContext context,
    FieldDef def,
    FieldRef ref,
    dynamic currentValue, {
    int? questionNumber,
  }) {
    switch (def.widgetHint) {
      case WidgetHint.radioGroup:
        // Android SingleSelectionCustomView: show cultureValue/label, store id.
        // Prefill/history may leave a Dart bool (e.g. isRegularSmoker) — never
        // cast with `as String?`; matchId coerces aliases to option id.
        return RadioFormField(
          key: Key('unified_form_${def.id}_input'),
          options: def.options
              .map((o) => RadioOption(id: o.id, label: o.displayName))
              .toList(),
          currentValue: FieldOption.matchId(currentValue, def.options),
          severityColors: _severityColorsByField[def.id],
          onChanged: (id) => onFieldChanged(def.id, id),
        );

      case WidgetHint.dialogCheckbox:
        // Canonical store uses list of option ids; inline list works with display names.
        // ANC on-treatment options are derived from selected illnesses
        // (Android AssessmentRMNCHFragment.onCheckBoxDialogueClicked).
        // Childhood illness options are age-filtered (Spice childIllnessType).
        var effectiveOptions = def.id == 'pregnantWomanOnTreatment'
            ? FieldVisibilityRules.ancOnTreatmentOptions(
                illnessField:
                    config.fields['pregnantWomanExistingIllness'] ?? def,
                onTreatmentField: def,
                data: data,
              )
            : def.options;
        if (def.id == 'childIllnessType' && ageInMonths != null) {
          final excluded =
              ChildhoodVisit.illnessOptionIdsExcluded(ageInMonths!);
          effectiveOptions = effectiveOptions
              .where((o) => !excluded.contains(o.id))
              .toList();
        }
        final storedIds = (currentValue is List)
            ? currentValue.cast<String>()
            : <String>[];
        final displayNames = storedIds.map((sid) {
          return effectiveOptions
                  .cast<FieldOption?>()
                  .firstWhere(
                    (o) => o!.id == sid || o.name == sid,
                    orElse: () => null,
                  )
                  ?.displayName ??
              sid;
        }).toList();
        // Mutual-exclusion "none" options: Spice uses id "none" or a numeric
        // id with name "None" (ANC dangerSignsExperienced* → 6/7). Match by
        // English name so Bangla culture labels still work via displayName.
        final noneLabels = effectiveOptions
            .where(
              (o) =>
                  o.id.toLowerCase() == 'none' ||
                  o.name.toLowerCase() == 'none',
            )
            .map((o) => o.displayName)
            .toSet();
        return _InlineListSelectField(
          key: Key('unified_form_${def.id}_input'),
          label: def.displayLabel,
          subLabel: null,
          isMandatory: def.isMandatory || ref.isMandatory,
          hasError: validationErrors.contains(ref.id),
          options: effectiveOptions.map((o) => o.displayName).toList(),
          selectedValues: displayNames,
          noneOptionLabels: noneLabels,
          onChanged: (names) {
            final ids = names.map((n) {
              return effectiveOptions
                      .cast<FieldOption?>()
                      .firstWhere(
                        (o) =>
                            o!.displayName == n ||
                            o.name == n ||
                            o.id == n,
                        orElse: () => null,
                      )
                      ?.id ??
                  n;
            }).toList();
            onFieldChanged(def.id, ids);
          },
        );

      case WidgetHint.spinner:
        // Yes/No (boolean) spinners render as pill buttons, not a dropdown —
        // a dropdown for a two-way choice is heavier than the tap target the
        // SK expects. Genuine multi-option spinners (e.g. deliveryFacilityType)
        // keep the dropdown.
        if (_isYesNoOptions(def.options)) {
          return RadioFormField(
            key: Key('unified_form_${def.id}_input'),
            options: def.options
                .map((o) => RadioOption(id: o.id, label: o.displayName))
                .toList(),
            currentValue: FieldOption.matchId(currentValue, def.options),
            onChanged: (id) => onFieldChanged(def.id, id),
          );
        }
        return _SpinnerField(
          key: Key('unified_form_${def.id}_input'),
          options: def.options,
          currentValue: FieldOption.coerceId(currentValue),
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.bloodGlucoseEntry:
        // Renders FBS/RBS type toggle + numeric value input in one card.
        // glucoseType (def.id) stores the selected type; 'glucose' stores the
        // numeric value.  Both are written to CanonicalVisitData individually.
        return _BloodGlucoseEntryField(
          // Scope by formType so ANC + NCD can both mount glucoseType.
          key: Key('unified_form_${section.formType}_${def.id}_bge'),
          options: def.options,
          glucoseType: currentValue as String?,
          glucoseValue: data.getValue('glucose'),
          isMandatory: def.isMandatory || ref.isMandatory,
          hasError: validationErrors.contains(ref.id) ||
              validationErrors.contains('glucose'),
          onTypeChanged: (type) => onFieldChanged(def.id, type),
          onValueChanged: (val) => onFieldChanged('glucose', val),
          valueValidator: _numericRangeValidator(
            'glucose',
            formType: section.formType,
          ),
        );

      case WidgetHint.numeric:
      case WidgetHint.bloodGlucose:
        // inputType 0 = text (e.g. newWorseningSymptoms comment field) — no
        // numeric keyboard, no unit, no parse. Render as plain text input.
        if (ref.inputType == 0 && def.unitMeasurement == null) {
          return TextFormField(
            initialValue: currentValue?.toString(),
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: _filledInputDecoration(hintText: def.displayHint),
            maxLines: 3,
            onChanged: (v) => onFieldChanged(def.id, v.isEmpty ? null : v),
          );
        }
        // inputType 2 = numberDecimal; "decimal" string (from EditText fields) is
        // also treated as decimal — use isDecimal flag.
        final isDecimal = ref.inputType == 2 ||
            (currentValue is double) ||
            (def.unitMeasurement != null &&
                !def.unitMeasurement!.contains('whole'));
        return _NumericField(
          key: Key('unified_form_${def.id}_input'),
          isDecimal: isDecimal,
          unit: def.unitMeasurement,
          hint: def.displayHint,
          readOnly: def.id == 'height' && heightReadOnly,
          initialValue: currentValue?.toString(),
          onChanged: (v) {
            if (def.id == 'height' && heightReadOnly) return;
            if (v == null || v.isEmpty) {
              onFieldChanged(def.id, null);
            } else {
              final parsed = isDecimal
                  ? double.tryParse(v)
                  : int.tryParse(v) ?? double.tryParse(v);
              onFieldChanged(def.id, parsed ?? v);
            }
          },
          validator: _numericRangeValidator(
            def.id,
            formType: section.formType,
            ageInMonths: ageInMonths,
          ),
        );

      case WidgetHint.dateField:
        // Follow-up is always a future date. Fields with disableFutureDate
        // (or any non-follow-up date) stay past/today-only.
        final allowFuture =
            def.id == 'followUpVisit' && !def.disableFutureDate;
        // Android DatePicker minDays (LMP = 294 in pregnancy_woman_profile).
        final minDaysBefore = (def.minDays != null && def.minDays! > 0)
            ? def.minDays
            : (def.id == 'lmp' ? FieldVisibilityRules.lmpMinDaysBefore : null);
        return _DateField(
          key: Key('unified_form_${def.id}_input'),
          currentValue: currentValue as String?,
          onChanged: (v) => onFieldChanged(def.id, v),
          allowFuture: allowFuture,
          minDaysBefore: minDaysBefore,
        );

      case WidgetHint.infoLabel:
        // Computed read-only value (e.g. BMI, CVD risk). Show value when
        // available; otherwise show a muted placeholder.
        return _InfoLabelField(
          key: Key('unified_form_${def.id}_info'),
          label: def.displayLabel,
          value: currentValue?.toString(),
        );

      case WidgetHint.textLabel:
        // Title labels use displayLabel; value labels (EDD / gestationalWeek)
        // have an empty label and show the computed currentValue instead.
        final label = def.displayLabel.trim();
        final valueText = currentValue?.toString().trim() ?? '';
        final text = valueText.isNotEmpty
            ? valueText
            : (label.isNotEmpty ? label : null);
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(text, style: AppTextStyles.subText),
        );

      case WidgetHint.bpField:
        // Render a systolic / diastolic pair. Stores value as a list of
        // reading maps to match Android's bpLogDetails wire format.
        // Spice ncd.json / cataract.json set showPulse: false.
        final readings = (currentValue is List)
            ? currentValue.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        return _BpReadingField(
          key: Key('unified_form_${def.id}_bp'),
          readings: readings,
          showPulse: false,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.ageOrDob:
      case WidgetHint.ageYmd:
        // Android AgeOrDob — DOB + age side-by-side (Add Member maths).
        // ageOfLastChild saves via `_asDobWire` (date string or years→Jan 1).
        // FP caps last-child age at 18; other AgeOrDob fields use enrollment max.
        final maxAge = def.id == 'ageOfLastChild' ? 18 : 130;
        return AgeOrDobField(
          key: Key('unified_form_${def.id}_input'),
          currentValue: currentValue?.toString(),
          maxAgeYears: maxAge,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.pregnancyProfile:
      case WidgetHint.unknown:
        // Complex fields delegated to specialised widgets in Section overrides.
        // Fall back to a numeric text field so data is never silently dropped.
        return _NumericField(
          key: Key('unified_form_${def.id}_input'),
          isDecimal: true,
          initialValue: currentValue?.toString(),
          onChanged: (v) => onFieldChanged(def.id, v),
        );
    }
  }
}

// ── Vital status evaluation ────────────────────────────────────────────────────

/// Compact value object returned by [_VitalStatusEval] methods.
///
/// [label] is the display text for the badge pill.
/// [color] drives the badge's background tint and text color.
/// [warning] is optional inline text rendered below the field control.
class _VitalStatus {
  const _VitalStatus({
    required this.label,
    required this.color,
    this.warning,
  });

  final String label;
  final Color color;
  final String? warning;
}

/// Pure rule-based evaluator — no ML, fully explainable.
///
/// Each method returns `null` when the input is absent or out of the
/// evaluable range so the caller can simply skip the badge.
abstract final class _VitalStatusEval {
  _VitalStatusEval._();

  // ── Blood pressure ───────────────────────────────────────────────────────
  // Android AssessmentRMNCHFragment: High Risk only when sys ≥ 140 or
  // dia ≥ 90 (AssessmentDefinedParams.HIGH_BP_*). No "elevated" band below
  // that — 120/80 is Normal on ANC (same as NCD green).
  static _VitalStatus? bloodPressure(int? sys, int? dia) {
    if (sys == null && dia == null) return null;
    final s = sys ?? 0;
    final d = dia ?? 0;
    if (s >= 160 || d >= 110) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpSevere,
        color: AppColors.statusCritical,
      );
    }
    if (s >= bpHighSystolic || d >= bpHighDiastolic) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpHigh,
        color: AppColors.statusCritical,
      );
    }
    if (s > 0 || d > 0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpNormal,
        color: AppColors.statusSuccess,
      );
    }
    return null;
  }

  /// NCD badge bands — Android NCDReferralColorEvaluator green when
  /// sys < 140 and dia < 90. Higher bands mirror crisis / Upazila limits.
  static _VitalStatus? bloodPressureNcd(int? sys, int? dia) {
    if (sys == null && dia == null) return null;
    final s = sys ?? 0;
    final d = dia ?? 0;
    if (s >= bpCrisisSystolic || d >= bpCrisisDiastolic) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpSevere,
        color: AppColors.statusCritical,
      );
    }
    if (s >= upazilaUpperLimitSystolic || d >= upazilaUpperLimitDiastolic) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpHigh,
        color: AppColors.statusCritical,
      );
    }
    if (s >= bpHighSystolic || d >= bpHighDiastolic) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpSlightlyElevated,
        color: AppColors.statusWarning,
      );
    }
    if (s > 0 || d > 0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpNormal,
        color: AppColors.statusSuccess,
      );
    }
    return null;
  }

  // ── Weight delta ─────────────────────────────────────────────────────────
  static _VitalStatus? weight(double? current, double? previous) {
    if (current == null || previous == null) return null;
    final delta = current - previous;
    final abs = delta.abs();
    // Colour by gain magnitude (ANC context — 0.5–2 kg/4 wks is normal).
    Color color;
    if (delta >= 0 && abs <= 2.0) {
      color = AppColors.statusSuccess;
    } else if (abs <= 3.5) {
      color = AppColors.statusWarning;
    } else {
      color = AppColors.statusCritical;
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsWeightDelta(delta),
      color: color,
    );
  }

  // ── Fundal height ────────────────────────────────────────────────────────
  // Bartholomew's rule: FH (cm) ≈ gestational age (weeks).
  static _VitalStatus? fundalHeight(double? measured, int? gestWeeks) {
    if (measured == null || gestWeeks == null || gestWeeks <= 0) return null;
    final diff = (measured - gestWeeks).round();
    if (diff <= -2) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsFhLag(diff.abs()),
        color: AppColors.statusWarning,
      );
    }
    if (diff >= 2) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsFhAhead(diff),
        color: AppColors.navy,
      );
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsFhExpected,
      color: AppColors.statusSuccess,
    );
  }

  // ── Urinary albumin / urine protein ─────────────────────────────────────
  static _VitalStatus? urinaryAlbumin(String? value) {
    if (value == null || value.isEmpty) return null;
    final v = value.toLowerCase();
    if (v.contains('absent') || v.contains('neg')) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsUrineAbsent,
        color: AppColors.statusSuccess,
      );
    }
    if (v.contains('trace')) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsUrineTrace,
        color: AppColors.statusWarning,
      );
    }
    if (v.contains('present') || v.contains('pos')) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsUrinePresent,
        color: AppColors.statusCritical,
      );
    }
    return null;
  }

  // ── Haemoglobin ──────────────────────────────────────────────────────────
  // WHO thresholds for pregnant women (≥11 g/dL = normal).
  static _VitalStatus? hemoglobin(double? value) {
    if (value == null) return null;
    if (value < 7.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsHbSevere,
        color: AppColors.statusCritical,
        warning: UnifiedFormStrings.vsHbWarningLong,
      );
    }
    if (value < 10.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsHbModerate,
        color: AppColors.statusCritical,
        warning: UnifiedFormStrings.vsHbWarningLong,
      );
    }
    if (value < 11.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsHbMild,
        color: AppColors.statusWarning,
        warning: UnifiedFormStrings.vsHbWarningLong,
      );
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsHbNormal,
      color: AppColors.statusSuccess,
    );
  }

  // ── Blood glucose ────────────────────────────────────────────────────────
  // Uses the higher of fasting / random to determine severity.
  // ADA / GDM thresholds: fasting ≥5.1 = GDM risk; fasting ≥7.0 = DM;
  // random ≥7.8 = elevated; random ≥11.1 = DM.
  static _VitalStatus? bloodGlucose(double? fasting, double? random) {
    if (fasting == null && random == null) return null;
    // High (diabetes level): fasting ≥7.0 OR random ≥11.1
    final isHigh =
        (fasting != null && fasting >= 7.0) ||
        (random  != null && random  >= 11.1);
    if (isHigh) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsGlucoseHigh,
        color: AppColors.statusCritical,
        warning: UnifiedFormStrings.vsGlucoseWarningHigh,
      );
    }
    // Elevated: fasting ≥5.1 OR random ≥7.8
    final isElevated =
        (fasting != null && fasting >= 5.1) ||
        (random  != null && random  >= 7.8);
    if (isElevated) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsGlucoseElevated,
        color: AppColors.statusWarning,
        warning: UnifiedFormStrings.vsGlucoseWarningElevated,
      );
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsGlucoseNormal,
      color: AppColors.statusSuccess,
    );
  }

  // ── BMI ──────────────────────────────────────────────────────────────────
  // WHO adult classification thresholds.
  static _VitalStatus? bmi(double? value) {
    if (value == null) return null;
    if (value < 18.5) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBmiUnderweight,
        color: AppColors.navy,
      );
    }
    if (value < 25.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBmiNormal,
        color: AppColors.statusSuccess,
      );
    }
    if (value < 30.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBmiOverweight,
        color: AppColors.statusWarning,
      );
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsBmiObese,
      color: AppColors.statusCritical,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static double? asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// Small coloured pill that shows a vital-status label.
///
/// Uses a translucent background tinted from [color] so it works over both
/// white field cards and the dark card borders.
class _VitalBadge extends StatelessWidget {
  const _VitalBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}

// ── Field chrome (v13 visual system) ─────────────────────────────────────────

/// Local visual constants for the Step 2 form, mirroring the `apon_sushashthya`
/// v13 mockup's form styling.  Kept private to this screen so the shared global
/// theme is untouched; all colours still come from [AppColors] tokens.
const double _kFieldCardRadius = AppRadius.button; // 12 — white field card
const double _kControlRadius = AppRadius.field; // 10 — filled input control
const double _kControlBorderWidth = 1.5;

/// Filled input decoration shared by every text / number / date / select
/// control so their fill, border, radius, and padding are pixel-consistent
/// with the v13 mockup (`#F8F9FC` fill, `1.5px #E5E7EB` border, radius 10).
InputDecoration _filledInputDecoration({
  String? hintText,
  String? suffixText,
  Widget? suffixIcon,
}) {
  final enabled = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_kControlRadius),
    borderSide: const BorderSide(
      color: AppColors.border,
      width: _kControlBorderWidth,
    ),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: AppColors.cardSurfaceMuted,
    hintText: hintText,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
    border: enabled,
    enabledBorder: enabled,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kControlRadius),
      borderSide: const BorderSide(
        color: AppColors.navy,
        width: _kControlBorderWidth,
      ),
    ),
  );
}

/// The label line shown above every field: bold dark text with a red `*` when
/// the field is mandatory (matches the v13 `.field-label` styling).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.isMandatory = false});

  final String label;
  final bool isMandatory;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          height: 1.25,
        );
    return Text.rich(
      TextSpan(
        text: label,
        style: base,
        children: isMandatory
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: AppColors.statusCritical,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]
            : const [],
      ),
    );
  }
}

/// The consistent chrome around every editable field: a white rounded card with
/// a `1.5px` border (red when [hasError]).  The header row mirrors the v13
/// mockup's vitals cards — an optional pastel [emoji] tile, the bold locale-pure
/// [label] + mandatory `*`, and an optional muted [subLabel] (unit / clinical
/// extras only — never a second language) — with the control [child] below.
class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.label,
    required this.child,
    this.subLabel,
    this.emoji,
    this.emojiBg,
    this.isMandatory = false,
    this.hasError = false,
    this.statusBadge,
    this.inlineWarning,
    this.infoText,
  });

  final String label;
  final Widget child;

  /// Muted second line under the label (e.g. unit `"mmHg"`, not a second language).
  final String? subLabel;

  /// Optional decorative emoji shown in a pastel tile to the left of the label.
  final String? emoji;
  final Color? emojiBg;

  final bool isMandatory;
  final bool hasError;

  /// Optional status pill rendered at the far right of the header row.
  /// Typically a [_VitalBadge] instance.
  final Widget? statusBadge;

  /// Optional inline warning shown below the field control (⚠ text).
  final String? inlineWarning;

  /// Optional short clinical guidance shown between the label and the
  /// control (e.g. "0 = if BP could not be measured") — from the field
  /// library's `infoTitle`, previously parsed but never rendered.
  final String? infoText;

  @override
  Widget build(BuildContext context) {
    final hasSubLabel = subLabel != null && subLabel!.isNotEmpty;
    final hasWarning  = inlineWarning != null && inlineWarning!.isNotEmpty;
    final hasInfoText = infoText != null && infoText!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(_kFieldCardRadius),
        border: Border.all(
          color: hasError ? AppColors.statusCritical : AppColors.border,
          width: _kControlBorderWidth,
        ),
        boxShadow: AppShadows.statBox,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (emoji != null) ...[
                  _EmojiTile(emoji: emoji!, background: emojiBg),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FieldLabel(label: label, isMandatory: isMandatory),
                      if (hasSubLabel) ...[
                        const SizedBox(height: 2),
                        Text(
                          subLabel!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textMuted,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (statusBadge != null) ...[
                  const SizedBox(width: 6),
                  statusBadge!,
                ],
              ],
            ),
            const SizedBox(height: 9),
          ],
          if (hasInfoText) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡', style: TextStyle(fontSize: 10)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    infoText!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          child,
          if (hasWarning) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    inlineWarning!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.statusWarningText,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Rounded pastel tile holding a single decorative emoji, matching the v13
/// mockup's `30x30` vitals-card icon tile.
class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, this.background});

  final String emoji;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? AppColors.cardSurfaceMuted,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 15)),
    );
  }
}

// ── Inline micro-widgets (no hardcoded strings, tokens only) ─────────────────

/// Combined blood-glucose card: FBS / RBS type toggle + numeric value input.
///
/// Replaces the separate `glucoseType` (Spinner) + `glucose` (EditText) pair
/// with a single self-contained card.  Both fields are still written to
/// [CanonicalVisitData] under their original IDs so the payload mapper is
/// unaffected.
class _BloodGlucoseEntryField extends StatefulWidget {
  const _BloodGlucoseEntryField({
    super.key,
    required this.options,
    required this.onTypeChanged,
    required this.onValueChanged,
    this.glucoseType,
    this.glucoseValue,
    this.isMandatory = false,
    this.hasError = false,
    this.valueValidator,
  });

  /// Options from the `glucoseType` field definition (FBS, RBS).
  final List<FieldOption> options;

  /// Current selected type id ('fbs' | 'rbs' | null).
  final String? glucoseType;

  /// Current glucose value (double | null).
  final dynamic glucoseValue;

  final void Function(String? type) onTypeChanged;
  final void Function(dynamic value) onValueChanged;
  final bool isMandatory;
  final bool hasError;
  final FormFieldValidator<String>? valueValidator;

  @override
  State<_BloodGlucoseEntryField> createState() =>
      _BloodGlucoseEntryFieldState();
}

class _BloodGlucoseEntryFieldState extends State<_BloodGlucoseEntryField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    debugPrint('[_BloodGlucoseEntryFieldState] initState');
    _ctrl = TextEditingController(
      text: widget.glucoseValue?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(_BloodGlucoseEntryField old) {
    super.didUpdateWidget(old);
    if (old.glucoseValue != widget.glucoseValue) {
      final newText = widget.glucoseValue?.toString() ?? '';
      if (_ctrl.text != newText) {
        final ctrlNum = double.tryParse(_ctrl.text);
        final newNum = double.tryParse(newText);
        final sameValue =
            ctrlNum != null && newNum != null && ctrlNum == newNum;
        if (!sameValue) {
          // Defer so controller updates never fire mid-build (Form setState).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _ctrl.text == newText) return;
            final curNum = double.tryParse(_ctrl.text);
            final tgtNum = double.tryParse(newText);
            if (curNum != null && tgtNum != null && curNum == tgtNum) return;
            _ctrl.text = newText;
            _ctrl.selection =
                TextSelection.collapsed(offset: newText.length);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    debugPrint('[_BloodGlucoseEntryFieldState] dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentType = widget.glucoseType;
    final glucoseNum = _VitalStatusEval.asDouble(widget.glucoseValue);

    // Route value to fasting vs random threshold depending on selected type.
    final fastingVal = currentType == 'fbs' ? glucoseNum : null;
    final randomVal = currentType == 'rbs' ? glucoseNum : null;
    final status = _VitalStatusEval.bloodGlucose(fastingVal, randomVal);

    return _FieldShell(
      label: UnifiedFormStrings.bloodGlucoseEntryLabel,
      subLabel: UnifiedFormStrings.bloodGlucoseEntryUnit,
      emoji: '🩸',
      emojiBg: const Color(0xFFFEE2E2),
      isMandatory: widget.isMandatory,
      hasError: widget.hasError,
      statusBadge: status != null
          ? _VitalBadge(label: status.label, color: status.color)
          : null,
      inlineWarning: status?.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Type toggle row ─────────────────────────────────────────────
          Row(
            children: List.generate(widget.options.length, (i) {
              final opt = widget.options[i];
              final isSelected = currentType == opt.id;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i < widget.options.length - 1 ? AppSpacing.xs : 0,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      // Tap again to deselect.
                      widget.onTypeChanged(isSelected ? null : opt.id);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.navy
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.navy
                              : AppColors.border,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        opt.displayName,
                        style: AppTextStyles.chip.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textMuted,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          // ── Value input ─────────────────────────────────────────────────
          TextFormField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: _filledInputDecoration(
              hintText: UnifiedFormStrings.bloodGlucoseEntryHint,
              suffixText: UnifiedFormStrings.bloodGlucoseEntryUnit,
            ),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: widget.valueValidator,
            onChanged: (v) {
              if (v.isEmpty) {
                widget.onValueChanged(null);
              } else {
                widget.onValueChanged(double.tryParse(v) ?? v);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _NumericField extends StatefulWidget {
  const _NumericField({
    super.key,
    required this.isDecimal,
    required this.onChanged,
    this.initialValue,
    this.unit,
    this.hint,
    this.validator,
    this.readOnly = false,
  });

  final bool isDecimal;
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final String? unit;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final bool readOnly;

  @override
  State<_NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends State<_NumericField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    debugPrint('[_NumericFieldState] initState');
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(_NumericField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue) {
      final newText = widget.initialValue ?? '';
      if (_ctrl.text != newText) {
        // Skip the update when the controller text and the incoming value
        // represent the same number but differ only in float representation
        // (e.g. "1" vs "1.0").  Without this guard, storing a parsed double
        // after every keystroke causes "120" to become "1.20": the controller
        // is reset to "1.0" after the first "1", and the next character
        // inserts at the wrong cursor position.
        final ctrlNum = double.tryParse(_ctrl.text);
        final newNum = double.tryParse(newText);
        final sameValue =
            ctrlNum != null && newNum != null && ctrlNum == newNum;
        if (!sameValue) {
          // Defer so TextEditingController.text= never fires mid-build.
          // It notifies TextFormField → FormState._forceRebuild → setState(),
          // which crashes if called during the build phase.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _ctrl.text == newText) return;
            final curNum = double.tryParse(_ctrl.text);
            final tgtNum = double.tryParse(newText);
            if (curNum != null && tgtNum != null && curNum == tgtNum) return;
            _ctrl.text = newText;
            _ctrl.selection =
                TextSelection.collapsed(offset: newText.length);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    debugPrint('[_NumericFieldState] dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.readOnly;
    return TextFormField(
      controller: _ctrl,
      readOnly: readOnly,
      enabled: !readOnly,
      // Use the plain number keyboard for ALL numeric fields — even decimal
      // ones.  Some Android keyboards in currency/decimal mode auto-insert a
      // decimal point when `decimal: true` is set, causing "190" to appear
      // as "1.90" without the user intending it.  The plain number keyboard
      // never auto-inserts a point; users who need decimals (e.g. temperature
      // "36.5") can still type the "." manually since the formatter below
      // allows it.
      keyboardType: TextInputType.number,
      inputFormatters: [
        if (widget.isDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: readOnly
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)
                : null,
          ),
      decoration: _filledInputDecoration(
        hintText: widget.hint,
        suffixText: widget.unit,
      ).copyWith(
        fillColor: readOnly
            ? Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.55)
            : null,
      ),
      onChanged: readOnly ? null : widget.onChanged,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: widget.validator,
    );
  }
}

/// Single-select field.  Rendered as the same chip/pill row as [RadioFormField]
/// (not a dropdown) to match the v13 mockup: ≤3 options fill a row, more options
/// wrap as chips.  The canonical store keeps the option id; the pill widget
/// works with display names, so ids are translated in both directions.
class _SpinnerField extends StatelessWidget {
  const _SpinnerField({
    super.key,
    required this.options,
    required this.onChanged,
    this.currentValue,
  });

  final List<FieldOption> options;
  final String? currentValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Resolve stored id → matching option (id or name match).
    final matched = options
        .cast<FieldOption?>()
        .firstWhere(
          (o) => o!.id == currentValue || o.name == currentValue,
          orElse: () => null,
        );
    final safeValue = matched?.id;

    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: safeValue,
      hint: Text(
        ComposerStrings.selectPlaceholder,
        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
      ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.navy, width: 1.5),
        ),
        filled: true,
        fillColor: AppColors.cardSurface,
      ),
      items: options
          .map(
            (o) => DropdownMenuItem<String>(
              value: o.id,
              child: Text(
                o.displayName,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (id) => onChanged(id),
    );
  }
}

class _DateField extends StatefulWidget {
  const _DateField({
    super.key,
    required this.onChanged,
    this.currentValue,
    this.allowFuture = false,
    this.minDaysBefore,
  });

  final String? currentValue;
  final ValueChanged<String?> onChanged;

  /// When true (e.g. follow-up visit), picker allows future dates.
  final bool allowFuture;

  /// When set (e.g. LMP = 294), earliest selectable date is today minus
  /// this many days. Null keeps the legacy lower bound (year 1900 / today).
  final int? minDaysBefore;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    debugPrint('[_DateFieldState] initState');
    _ctrl = TextEditingController(text: widget.currentValue ?? '');
  }

  @override
  void didUpdateWidget(_DateField old) {
    super.didUpdateWidget(old);
    if (old.currentValue != widget.currentValue) {
      // Defer the controller update so it never fires inside a build phase.
      // Setting TextEditingController.text= triggers FormField.didChange →
      // FormState._forceRebuild → setState(), which crashes if called mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ctrl.text = widget.currentValue ?? '';
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    debugPrint('[_DateFieldState] dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      controller: _ctrl,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: _filledInputDecoration(
        suffixIcon: const Icon(
          Icons.calendar_today_outlined,
          size: 18,
          color: AppColors.textMuted,
        ),
      ),
      onTap: () async {
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);
        final parsed = DateTime.tryParse(widget.currentValue ?? '');
        final first = widget.allowFuture
            ? todayStart
            : (widget.minDaysBefore != null
                ? todayStart.subtract(Duration(days: widget.minDaysBefore!))
                : DateTime(1900));
        final last = widget.allowFuture
            ? todayStart.add(const Duration(days: 365 * 2))
            : todayStart;
        var initial = parsed ?? (widget.allowFuture
            ? todayStart.add(const Duration(days: 28))
            : todayStart);
        if (initial.isBefore(first)) initial = first;
        if (initial.isAfter(last)) initial = last;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: first,
          lastDate: last,
        );
        if (picked != null) {
          widget.onChanged(picked.toIso8601String().substring(0, 10));
        }
      },
    );
  }
}

// ── BP reading field ──────────────────────────────────────────────────────────

/// Multi-reading BP widget matching Android's `bpLogDetails` wire format.
///
/// Supports up to 3 readings (Android parity). Each row captures systolic and
/// diastolic; pulse is optional ([showPulse], false on Spice BD NCD/cataract).
/// Stores value as `List<Map<String, dynamic>>`:
/// `[{'systolic': 120, 'diastolic': 80, 'pulse': 72}, ...]`.
class _BpReadingField extends StatefulWidget {
  const _BpReadingField({
    super.key,
    required this.readings,
    required this.onChanged,
    this.showPulse = false,
  });

  static const int _maxReadings = 3;

  final List<Map<String, dynamic>> readings;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool showPulse;

  @override
  State<_BpReadingField> createState() => _BpReadingFieldState();
}

class _BpReadingFieldState extends State<_BpReadingField> {
  // One triplet of controllers per row (up to _maxReadings).
  late List<(TextEditingController, TextEditingController, TextEditingController)> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _buildRows(widget.readings);
  }

  List<(TextEditingController, TextEditingController, TextEditingController)> _buildRows(
    List<Map<String, dynamic>> readings,
  ) {
    final source = readings.isNotEmpty ? readings : [const <String, dynamic>{}];
    return source.map((r) {
      return (
        TextEditingController(text: r['systolic']?.toString() ?? ''),
        TextEditingController(text: r['diastolic']?.toString() ?? ''),
        TextEditingController(text: r['pulse']?.toString() ?? ''),
      );
    }).toList();
  }

  @override
  void didUpdateWidget(_BpReadingField old) {
    super.didUpdateWidget(old);
    if (old.readings != widget.readings) {
      // Sync only rows that haven't changed length; rebuild otherwise.
      if (widget.readings.length != _rows.length) {
        for (final (s, d, p) in _rows) {
          s.dispose();
          d.dispose();
          p.dispose();
        }
        setState(() => _rows = _buildRows(widget.readings));
      } else {
        for (var i = 0; i < _rows.length; i++) {
          final r = widget.readings[i];
          final (s, d, p) = _rows[i];
          _syncCtrl(s, r['systolic']?.toString() ?? '');
          _syncCtrl(d, r['diastolic']?.toString() ?? '');
          _syncCtrl(p, r['pulse']?.toString() ?? '');
        }
      }
    }
  }

  void _syncCtrl(TextEditingController ctrl, String newText) {
    if (ctrl.text == newText) return;
    // Defer so controller updates never fire mid-build (Form setState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ctrl.text == newText) return;
      ctrl.text = newText;
      ctrl.selection = TextSelection.collapsed(offset: newText.length);
    });
  }

  @override
  void dispose() {
    for (final (s, d, p) in _rows) {
      s.dispose();
      d.dispose();
      p.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final out = <Map<String, dynamic>>[];
    for (final (s, d, p) in _rows) {
      final sys = int.tryParse(s.text);
      final dia = int.tryParse(d.text);
      if (sys == null && dia == null) continue;
      final reading = <String, dynamic>{};
      if (sys != null) reading['systolic'] = sys;
      if (dia != null) reading['diastolic'] = dia;
      if (widget.showPulse) {
        final pulse = int.tryParse(p.text);
        if (pulse != null) reading['pulse'] = pulse;
      }
      out.add(reading);
    }
    widget.onChanged(out);
  }

  void _addRow() {
    if (_rows.length >= _BpReadingField._maxReadings) return;
    setState(() {
      _rows.add((
        TextEditingController(),
        TextEditingController(),
        TextEditingController(),
      ));
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    final (s, d, p) = _rows[index];
    s.dispose();
    d.dispose();
    p.dispose();
    setState(() => _rows.removeAt(index));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _rows.length; i++) ...[
          if (_rows.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(
                    '${UnifiedFormStrings.bpReadingNumberLabel} ${i + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (i > 0)
                    GestureDetector(
                      onTap: () => _removeRow(i),
                      child: Text(
                        UnifiedFormStrings.bpRemoveReadingTooltip,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.statusCritical,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          _BpReadingRow(
            sysCtrl: _rows[i].$1,
            diaCtrl: _rows[i].$2,
            pulseCtrl: _rows[i].$3,
            showPulse: widget.showPulse,
            onChanged: (_) => _emit(),
          ),
          if (i < _rows.length - 1) const SizedBox(height: 10),
        ],
        if (_rows.length < _BpReadingField._maxReadings) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _addRow,
            child: Text(
              UnifiedFormStrings.bpAddReadingLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Single systolic / diastolic / optional pulse row inside [_BpReadingField].
class _BpReadingRow extends StatelessWidget {
  const _BpReadingRow({
    required this.sysCtrl,
    required this.diaCtrl,
    required this.pulseCtrl,
    required this.onChanged,
    this.showPulse = false,
  });

  final TextEditingController sysCtrl;
  final TextEditingController diaCtrl;
  final TextEditingController pulseCtrl;
  final ValueChanged<void> onChanged;
  final bool showPulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: _bpCell(
            context,
            caption: UnifiedFormStrings.bpSystolicLabel,
            controller: sysCtrl,
            suffixText: UnifiedFormStrings.bpUnit,
            validator: _SectionCard._numericRangeValidator('systolic'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 6, right: 6),
          child: Text(
            '/',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _bpCell(
            context,
            caption: UnifiedFormStrings.bpDiastolicLabel,
            controller: diaCtrl,
            validator: _SectionCard._numericRangeValidator('diastolic'),
          ),
        ),
        if (showPulse) ...[
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: _bpCell(
              context,
              caption: UnifiedFormStrings.bpPulseLabel,
              controller: pulseCtrl,
              suffixText: UnifiedFormStrings.bpPulseUnit,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bpCell(
    BuildContext context, {
    required String caption,
    required TextEditingController controller,
    String? suffixText,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: _filledInputDecoration(hintText: caption, suffixText: suffixText),
      onChanged: (_) => onChanged(null),
      validator: validator,
    );
  }
}

// ── Info label field ──────────────────────────────────────────────────────────

/// Read-only display for computed values (BMI, CVD risk score, etc.).
///
/// Accepts an optional [statusBadge] (e.g. a [_VitalBadge]) that is shown
/// to the right of the numeric value so the SK gets instant classification
/// context (e.g. "Normal", "Overweight") without reading a table.
class _InfoLabelField extends StatelessWidget {
  const _InfoLabelField({
    super.key,
    required this.label,
    this.value,
    this.statusBadge,
  });

  final String label;
  final String? value;

  /// Optional status pill rendered to the right of the displayed value.
  final Widget? statusBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurfaceMuted,
        borderRadius: BorderRadius.circular(_kControlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Uppercase caption + purple (auto) tag.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                UnifiedFormStrings.autoComputedTag,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.aiPurple,
                  fontWeight: FontWeight.w600,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                hasValue ? value! : UnifiedFormStrings.autoComputedPlaceholder,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.navy,
                ),
              ),
              if (statusBadge != null && hasValue) ...[
                const SizedBox(width: 8),
                statusBadge!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Inline list multi-select ──────────────────────────────────────────────────

/// Multi-select field rendered as an inline tappable list — one rounded row per
/// option.  Matches the "Any danger signs now?" UI in the v13 reference mockup:
/// each option is a white card-row with a leading emoji tile (if provided) and
/// the label, with a navy-filled style when selected.  The "None of these"
/// option (detected by a case-insensitive "none" prefix) deselects everything
/// else and shows a ✓ prefix.
class _InlineListSelectField extends StatelessWidget {
  const _InlineListSelectField({
    super.key,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    this.hasError = false,
    this.label,
    this.subLabel,
    this.isMandatory = false,
    this.noneOptionLabels = const {},
  });

  final List<String> options;
  final List<String> selectedValues;
  final ValueChanged<List<String>> onChanged;
  final bool hasError;
  final String? label;
  final String? subLabel;
  final bool isMandatory;

  /// Display labels for options with id `none` (locale-aware). Preferred over
  /// English string heuristics so "Not taking any treatment" / Bangla work.
  final Set<String> noneOptionLabels;

  static const _noneKey = 'none';

  bool _isNone(String opt) {
    if (noneOptionLabels.contains(opt)) return true;
    final lower = opt.toLowerCase();
    // Fallback when [noneOptionLabels] is empty (e.g. newborn cause list).
    return lower == _noneKey ||
        lower.startsWith('$_noneKey ') ||
        lower.contains('not taking any treatment');
  }

  void _toggle(String option) {
    final current = List<String>.from(selectedValues);
    if (_isNone(option)) {
      // Selecting "None" clears all other selections.
      onChanged(current.contains(option) ? [] : [option]);
      return;
    }
    // Selecting any real option clears every "none"-class selection.
    if (current.contains(option)) {
      current.remove(option);
    } else {
      current.removeWhere(_isNone);
      current.add(option);
    }
    onChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: label + Bengali sublabel + mandatory marker.
        if (label != null && label!.isNotEmpty) ...[
          _InlineListHeader(
            label: label!,
            subLabel: subLabel,
            isMandatory: isMandatory,
            hasError: hasError,
          ),
          const SizedBox(height: 8),
        ],
        // Option rows.
        for (final option in options) ...[
          _InlineListRow(
            label: option,
            isSelected: selectedValues.contains(option),
            isNone: _isNone(option),
            onTap: () => _toggle(option),
          ),
          const SizedBox(height: 6),
        ],
        // Red error hint below the list.
        if (hasError) ...[
          const SizedBox(height: 2),
          Text(
            UnifiedFormStrings.selectAtLeastOneOptionError,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.statusCritical,
            ),
          ),
        ],
      ],
    );
  }
}

/// Header section for [_InlineListSelectField]: bold English label + muted
/// Bengali sub-label + mandatory `*`.
class _InlineListHeader extends StatelessWidget {
  const _InlineListHeader({
    required this.label,
    this.subLabel,
    this.isMandatory = false,
    this.hasError = false,
  });

  final String label;
  final String? subLabel;
  final bool isMandatory;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: hasError
                      ? AppColors.statusCritical
                      : AppColors.textPrimary,
                  height: 1.25,
                ),
            children: isMandatory
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(
                        color: AppColors.statusCritical,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]
                : null,
          ),
        ),
        if (subLabel != null && subLabel!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subLabel!,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

/// A single selectable row inside [_InlineListSelectField].
///
/// Unselected: white card with a `1.5px` grey border.
/// Selected (normal): navy-filled card.
/// Selected (none): light grey-filled card with ✓ prefix.
class _InlineListRow extends StatelessWidget {
  const _InlineListRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isNone = false,
  });

  final String label;
  final bool isSelected;
  final bool isNone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;

    if (isNone && isSelected) {
      bg = AppColors.cardSurfaceMuted;
      fg = AppColors.textPrimary;
      border = AppColors.border;
    } else if (isSelected) {
      bg = AppColors.navy;
      fg = AppColors.textOnNavy;
      border = AppColors.navy;
    } else {
      bg = Colors.white;
      fg = AppColors.textPrimary;
      border = AppColors.border;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(_kFieldCardRadius),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isNone && isSelected ? '✓ $label' : label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                  height: 1.3,
                ),
              ),
            ),
            if (isSelected && !isNone)
              Icon(Icons.check_circle_rounded, size: 18, color: fg),
          ],
        ),
      ),
    );
  }
}

// ── Submit bar ────────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.submitting, required this.onSubmit});

  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xl,
        ),
        child: SizedBox(
          width: double.infinity,
          // A disabled button swallows nothing, so this catches taps made
          // while a save is still in flight — otherwise Submit looks dead
          // with no trace in the logs.
          child: GestureDetector(
            onTap: submitting
                ? () => debugPrint(
                    '[SubmitBlocked] tapped while a previous save is still '
                    'in flight — button disabled')
                : null,
            child: ElevatedButton(
              key: const Key('unified_form_submit_button'),
              onPressed: submitting ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pink,
                foregroundColor: AppColors.textOnNavy,
                disabledBackgroundColor: AppColors.pink.withValues(alpha: 0.5),
                disabledForegroundColor: AppColors.textOnNavy,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textOnNavy,
                      ),
                    )
                  : Text(UnifiedFormStrings.submitLabel),
            ),
          ),
        ),
      ),
    );
  }
}

// ── New-enrolment colour helpers ──────────────────────────────────────────────

Color _newEnrolmentBg(String formType) => switch (formType) {
      'anc' || 'pnc' => const Color(0xFFFFF0F5),
      'ncd'          => const Color(0xFFFEFCE8),
      'imci'         => const Color(0xFFEFF6FF),
      'tb'           => const Color(0xFFF0FDF4),
      _              => const Color(0xFFF8F8F8),
    };

Color _newEnrolmentAccent(String formType) => switch (formType) {
      'anc' || 'pnc' => const Color(0xFFEC4899),
      'ncd'          => const Color(0xFFF59E0B),
      'imci'         => const Color(0xFF3B82F6),
      'tb'           => const Color(0xFF10B981),
      _              => const Color(0xFF6B7280),
    };
