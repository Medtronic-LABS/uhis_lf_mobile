import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/form_fields/dialog_multi_select_field.dart';
import '../widgets/form_fields/radio_form_field.dart';
import 'canonical_visit_data.dart';
import 'form_config.dart';
import 'step2_asr_banner.dart';
import 'triage_symptom_mapper.dart';
import 'unified_form_notifier.dart';
import 'unified_section_rules.dart';

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
    this.enrolledFormTypes = const [],
    this.confirmedSymptoms = const [],
    this.aiPickedSymptoms = const {},
  });

  /// Ordered formType keys (e.g. `['anc', 'ncd']`) from activated pathways.
  final List<String> activeFormTypes;

  /// Called after [UnifiedFormNotifier.submit] succeeds. Navigation lives here.
  final VoidCallback onSubmitComplete;

  /// Passed to [UnifiedSectionRules] for conditional `birthPreparedness` visibility.
  final int? gestationalWeeks;

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

  // Used to suppress duplicate [Form] debug logs — only log when the section
  // count or field count actually changes between rebuilds.
  int _lastLoggedSectionCount = -1;
  int _lastLoggedFieldCount = -1;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<UnifiedFormNotifier>();

      if (widget.confirmedSymptoms.isNotEmpty) {
        // Store raw codes so section-rules can drive conditional visibility.
        notifier.updateField('_triageSymptoms', widget.confirmedSymptoms);

        // Pre-fill symptom fields derived from triage selections.
        // Done BEFORE loadDraft so that a saved draft can override these
        // suggestions (draft values win over triage-derived defaults).
        for (final ft in widget.activeFormTypes) {
          final prefills = TriageSymptomMapper.prefillsFor(
            ft,
            widget.confirmedSymptoms,
          );
          for (final entry in prefills.entries) {
            notifier.updateField(entry.key, entry.value);
          }
        }
      }

      notifier.loadDraft();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await FormConfig.load(rootBundle);
      if (mounted) setState(() { _config = cfg; _configLoading = false; });
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
        final annotated = UnifiedSectionRules.activeSections(
          config: _config!,
          activeFormTypes: widget.activeFormTypes,
          currentData: notifier.data,
          gestationalWeeks: widget.gestationalWeeks,
          enrolledFormTypes: widget.enrolledFormTypes,
        );

        // Only emit the [Form] debug summary when the section/field count
        // changes — suppresses per-keystroke log spam during form filling.
        final totalFields = annotated.fold<int>(
          0, (sum, a) => sum + a.section.fieldRefs.length);
        if (annotated.length != _lastLoggedSectionCount ||
            totalFields != _lastLoggedFieldCount) {
          _lastLoggedSectionCount = annotated.length;
          _lastLoggedFieldCount = totalFields;
          UnifiedSectionRules.debugLogSections(annotated, totalFields);
        }

        // Build the list items: programme-name dividers (with inline per-
        // programme symptom chips) + section cards.
        // The top-level banner is removed — symptoms appear inline under each
        // programme they are relevant to.
        final items = <Widget>[];

        String? lastFormType;
        for (final annotatedSection in annotated) {
          final ft = annotatedSection.section.formType;
          if (ft != lastFormType) {
            final label = annotatedSection.group == SectionGroup.vitals
                ? UnifiedFormStrings.vitalsGroupLabel
                : UnifiedFormStrings.programmeBadgeLabel(ft) ??
                    ft.toUpperCase();

            // For programme sections (non-vitals), compute which triage
            // symptoms are relevant to this formType to show as inline chips.
            final relevantCodes =
                annotatedSection.group == SectionGroup.vitals
                    ? const <String>[]
                    : TriageSymptomMapper.relevantCodes(
                        ft,
                        widget.confirmedSymptoms,
                      );

            items.add(_ProgrammeDivider(
              label: label,
              relevantSymptomCodes: relevantCodes,
              aiPickedSymptomCodes: widget.aiPickedSymptoms,
            ));
            lastFormType = ft;
          }
          items.add(_SectionCard(
            section: annotatedSection.section,
            config: _config!,
            data: notifier.data,
            validationErrors: notifier.validationErrors,
            onFieldChanged: notifier.updateField,
          ));
        }

        return Column(
          children: [
            // ── Step 2 AI ambient listening banner ──────────────────────────
            Step2AsrBanner(activeFormTypes: widget.activeFormTypes),
            // ── Assessment form sections ────────────────────────────────────
            Expanded(
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxxl,
                  vertical: AppSpacing.xxxl,
                ),
                children: items,
              ),
            ),
            _SubmitBar(
              submitting: notifier.submitting,
              onSubmit: () => _onSubmit(ctx, notifier, annotated),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onSubmit(
    BuildContext ctx,
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) async {
    if (_config == null) return;

    // Validate mandatory fields before submitting.
    final errors = _computeValidationErrors(notifier, annotated);
    if (errors.isNotEmpty) {
      notifier.setValidationErrors(errors);
      // Scroll to top so the SK sees the highlighted fields.
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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

    // Clear any previous errors before submitting.
    notifier.setValidationErrors(const {});

    try {
      await notifier.submit();
      widget.onSubmitComplete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(VisitFormStrings.saveFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  /// Returns the set of mandatory field IDs that have no value in [notifier].
  Set<String> _computeValidationErrors(
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) {
    final errors = <String>{};
    for (final a in annotated) {
      for (final ref in a.section.fieldRefs) {
        final def = _config!.fields[ref.id];
        if (def == null) continue;
        final mandatory = def.isMandatory || ref.isMandatory;
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
  });

  final String label;
  final List<String> relevantSymptomCodes;
  /// Codes from Step 1 that were pre-selected by the AI Scribe.
  /// Chips for these codes render with the purple AI palette.
  final Set<String> aiPickedSymptomCodes;

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

    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.sm,
        top: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Divider row — label left-aligned, AI badge on right ────────
          Row(
            children: [
              Text(
                widget.label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.textPrimary,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Divider(color: AppColors.border, height: 1)),
              // AI pre-fill badge — shown when triage symptoms were mapped
              // to this programme's fields.
              if (hasChips) ...[
                const SizedBox(width: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.aiPurpleDark, AppColors.aiPurple],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 10,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        UnifiedFormStrings.aiBadgeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          // ── Collapsible symptom strip ─────────────────────────────────
          if (hasChips) ...[
            const SizedBox(height: 6),
            // Tappable toggle row
            GestureDetector(
              onTap: () =>
                  setState(() => _symptomsExpanded = !_symptomsExpanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Symptoms from Step 1 (${codes.length})',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(width: 2),
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
              ),
            ),
            // Chip list — revealed when expanded
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
          ],
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
class _TriageChip extends StatelessWidget {
  const _TriageChip({required this.code, this.isAi = false});

  final String code;
  final bool isAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color bg;
    final Color border;
    final Color textColor;
    if (isAi) {
      bg = AppColors.aiSurfaceStart;
      border = AppColors.aiBorder;
      textColor = AppColors.aiPurple;
    } else {
      bg = AppColors.statusWarningSurface;
      border = AppColors.statusWarning.withValues(alpha: 0.30);
      textColor = AppColors.statusWarningText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAi) ...[
            const Icon(Icons.auto_awesome, size: 9, color: AppColors.aiPurple),
            const SizedBox(width: 3),
          ],
          Text(
            TriageStrings.symptomLabel(code),
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.config,
    required this.data,
    required this.validationErrors,
    required this.onFieldChanged,
  });

  final FormSection section;
  final FormConfig config;
  final CanonicalVisitData data;
  final Set<String> validationErrors;
  final void Function(String fieldId, dynamic value) onFieldChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Text(
              section.title.toUpperCase(),
              style: AppTextStyles.sectionLabel,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          ...section.fieldRefs.map((ref) {
            final def = config.fields[ref.id];
            if (def == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: _fieldRow(context, def, ref),
            );
          }),
        ],
      ),
    );
  }

  /// Builds one field row: self-contained fields (info / text label) render
  /// bare; every editable field is wrapped in a [_FieldShell] that owns the
  /// label, mandatory `*`, and the red error border.
  Widget _fieldRow(BuildContext context, FieldDef def, FieldRef ref) {
    final control = _buildField(context, def, ref, data.getValue(ref.id));
    switch (def.widgetHint) {
      case WidgetHint.infoLabel:
      case WidgetHint.textLabel:
        return control;
      default:
        return _FieldShell(
          label: def.label,
          isMandatory: def.isMandatory || ref.isMandatory,
          hasError: validationErrors.contains(ref.id),
          child: control,
        );
    }
  }

  Widget _buildField(
    BuildContext context,
    FieldDef def,
    FieldRef ref,
    dynamic currentValue,
  ) {
    switch (def.widgetHint) {
      case WidgetHint.radioGroup:
        // Canonical store uses option id; RadioFormField works with display names.
        // Translate: stored id → display name for render, selected name → id on change.
        final storedId = currentValue as String?;
        final displayName = def.options
            .cast<FieldOption?>()
            .firstWhere(
              (o) => o!.id == storedId || o.name == storedId,
              orElse: () => null,
            )
            ?.name;
        return RadioFormField(
          key: Key('unified_form_${def.id}_input'),
          options: def.options.map((o) => o.name).toList(),
          currentValue: displayName,
          onChanged: (name) {
            final id = def.options
                .cast<FieldOption?>()
                .firstWhere((o) => o!.name == name, orElse: () => null)
                ?.id ?? name;
            onFieldChanged(def.id, id);
          },
        );

      case WidgetHint.dialogCheckbox:
        // Canonical store uses list of option ids; widget works with display names.
        final storedIds = (currentValue is List)
            ? currentValue.cast<String>()
            : <String>[];
        final displayNames = storedIds.map((sid) {
          return def.options
                  .cast<FieldOption?>()
                  .firstWhere(
                    (o) => o!.id == sid || o.name == sid,
                    orElse: () => null,
                  )
                  ?.name ??
              sid;
        }).toList();
        return DialogMultiSelectField(
          key: Key('unified_form_${def.id}_input'),
          options: def.options.map((o) => o.name).toList(),
          currentValue: displayNames,
          onChanged: (names) {
            final ids = names.map((n) {
              return def.options
                      .cast<FieldOption?>()
                      .firstWhere((o) => o!.name == n, orElse: () => null)
                      ?.id ??
                  n;
            }).toList();
            onFieldChanged(def.id, ids);
          },
        );

      case WidgetHint.spinner:
        return _SpinnerField(
          key: Key('unified_form_${def.id}_input'),
          options: def.options,
          currentValue: currentValue as String?,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.numeric:
      case WidgetHint.bloodGlucose:
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
          hint: def.hintText,
          initialValue: currentValue?.toString(),
          onChanged: (v) {
            if (v == null || v.isEmpty) {
              onFieldChanged(def.id, null);
            } else {
              final parsed = isDecimal
                  ? double.tryParse(v)
                  : int.tryParse(v) ?? double.tryParse(v);
              onFieldChanged(def.id, parsed ?? v);
            }
          },
        );

      case WidgetHint.dateField:
        return _DateField(
          key: Key('unified_form_${def.id}_input'),
          currentValue: currentValue as String?,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.infoLabel:
        // Computed read-only value (e.g. BMI, CVD risk). Show value when
        // available; otherwise show a muted placeholder.
        return _InfoLabelField(
          key: Key('unified_form_${def.id}_info'),
          label: def.label,
          value: currentValue?.toString(),
        );

      case WidgetHint.textLabel:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(def.label, style: AppTextStyles.subText),
        );

      case WidgetHint.bpField:
        // Render a systolic / diastolic pair. Stores value as a list of
        // reading maps to match Android's bpLogDetails wire format.
        final readings = (currentValue is List)
            ? currentValue.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        return _BpReadingField(
          key: Key('unified_form_${def.id}_bp'),
          readings: readings,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.ageYmd:
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
/// a `1.5px` border (red when [hasError]), a bold label + mandatory `*`, then
/// the control [child].  Replaces the previous per-field [DecoratedBox] error
/// wrap and the doubled labels the inner widgets used to render.
class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.label,
    required this.child,
    this.isMandatory = false,
    this.hasError = false,
  });

  final String label;
  final Widget child;
  final bool isMandatory;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
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
            _FieldLabel(label: label, isMandatory: isMandatory),
            const SizedBox(height: 7),
          ],
          child,
        ],
      ),
    );
  }
}

// ── Inline micro-widgets (no hardcoded strings, tokens only) ─────────────────

class _NumericField extends StatefulWidget {
  const _NumericField({
    super.key,
    required this.isDecimal,
    required this.onChanged,
    this.initialValue,
    this.unit,
    this.hint,
  });

  final bool isDecimal;
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final String? unit;
  final String? hint;

  @override
  State<_NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends State<_NumericField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(_NumericField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue) {
      final newText = widget.initialValue ?? '';
      if (_ctrl.text != newText) {
        _ctrl.text = newText;
        _ctrl.selection = TextSelection.collapsed(offset: newText.length);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      keyboardType: widget.isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: [
        if (widget.isDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: _filledInputDecoration(
        hintText: widget.hint,
        suffixText: widget.unit,
      ),
      onChanged: widget.onChanged,
    );
  }
}

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
    final ids = options.map((o) => o.id).toSet();
    // Guard: only pass value if it matches a known option; avoids assertion.
    final safeValue = (currentValue != null && ids.contains(currentValue))
        ? currentValue
        : null;
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: _filledInputDecoration(),
      icon: const Icon(Icons.expand_more, color: AppColors.textMuted),
      items: options
          .map((o) => DropdownMenuItem(value: o.id, child: Text(o.name)))
          .toList(),
      onChanged: onChanged,
      style: theme.textTheme.bodyMedium,
    );
  }
}

class _DateField extends StatefulWidget {
  const _DateField({
    super.key,
    required this.onChanged,
    this.currentValue,
  });

  final String? currentValue;
  final ValueChanged<String?> onChanged;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue ?? '');
  }

  @override
  void didUpdateWidget(_DateField old) {
    super.didUpdateWidget(old);
    if (old.currentValue != widget.currentValue) {
      _ctrl.text = widget.currentValue ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          widget.onChanged(picked.toIso8601String().substring(0, 10));
        }
      },
    );
  }
}

// ── BP reading field ──────────────────────────────────────────────────────────

/// Systolic / diastolic pair that matches Android's `bpLogDetails` wire format.
///
/// Stores value as `List<Map<String, dynamic>>` with one entry per reading:
/// `[{'systolic': 120, 'diastolic': 80, 'pulse': 72}]`.
class _BpReadingField extends StatefulWidget {
  const _BpReadingField({
    super.key,
    required this.readings,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> readings;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<_BpReadingField> createState() => _BpReadingFieldState();
}

class _BpReadingFieldState extends State<_BpReadingField> {
  late TextEditingController _sys;
  late TextEditingController _dia;
  late TextEditingController _pulse;

  @override
  void initState() {
    super.initState();
    final first =
        widget.readings.isNotEmpty ? widget.readings.first : const {};
    _sys = TextEditingController(text: first['systolic']?.toString() ?? '');
    _dia = TextEditingController(text: first['diastolic']?.toString() ?? '');
    _pulse = TextEditingController(text: first['pulse']?.toString() ?? '');
  }

  @override
  void didUpdateWidget(_BpReadingField old) {
    super.didUpdateWidget(old);
    if (old.readings != widget.readings) {
      final first =
          widget.readings.isNotEmpty ? widget.readings.first : const {};
      _syncCtrl(_sys, first['systolic']?.toString() ?? '');
      _syncCtrl(_dia, first['diastolic']?.toString() ?? '');
      _syncCtrl(_pulse, first['pulse']?.toString() ?? '');
    }
  }

  void _syncCtrl(TextEditingController ctrl, String newText) {
    if (ctrl.text != newText) {
      ctrl.text = newText;
      ctrl.selection = TextSelection.collapsed(offset: newText.length);
    }
  }

  @override
  void dispose() {
    _sys.dispose();
    _dia.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _emit() {
    final sys = int.tryParse(_sys.text);
    final dia = int.tryParse(_dia.text);
    if (sys == null && dia == null) {
      widget.onChanged([]);
      return;
    }
    final reading = <String, dynamic>{};
    if (sys != null) reading['systolic'] = sys;
    if (dia != null) reading['diastolic'] = dia;
    final pulse = int.tryParse(_pulse.text);
    if (pulse != null) reading['pulse'] = pulse;
    widget.onChanged([reading]);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Systolic / diastolic pair joined by a "/" separator.
        Expanded(
          flex: 3,
          child: _bpCell(
            context,
            caption: UnifiedFormStrings.bpSystolicLabel,
            controller: _sys,
            suffixText: UnifiedFormStrings.bpUnit,
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
            controller: _dia,
          ),
        ),
        const SizedBox(width: 10),
        // Pulse.
        Expanded(
          flex: 3,
          child: _bpCell(
            context,
            caption: UnifiedFormStrings.bpPulseLabel,
            controller: _pulse,
            suffixText: UnifiedFormStrings.bpPulseUnit,
          ),
        ),
      ],
    );
  }

  /// One captioned, filled numeric input used for systolic / diastolic / pulse.
  Widget _bpCell(
    BuildContext context, {
    required String caption,
    required TextEditingController controller,
    String? suffixText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
              ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: _filledInputDecoration(suffixText: suffixText),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }
}

// ── Info label field ──────────────────────────────────────────────────────────

/// Read-only display for computed values (BMI, CVD risk score, etc.).
class _InfoLabelField extends StatelessWidget {
  const _InfoLabelField({
    super.key,
    required this.label,
    this.value,
  });

  final String label;
  final String? value;

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
          Text(
            hasValue ? value! : UnifiedFormStrings.autoComputedPlaceholder,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.navy,
            ),
          ),
        ],
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
                fontFamily: 'Nunito',
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
                : const Text(UnifiedFormStrings.submitLabel),
          ),
        ),
      ),
    );
  }
}
