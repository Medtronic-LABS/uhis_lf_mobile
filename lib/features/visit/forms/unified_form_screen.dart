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
/// A read-only banner of triage symptoms selected in Step 1 is displayed at
/// the top of the form so the SK can see what was reported.
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

  @override
  State<UnifiedFormScreen> createState() => _UnifiedFormScreenState();
}

class _UnifiedFormScreenState extends State<UnifiedFormScreen> {
  FormConfig? _config;
  bool _configLoading = true;
  Object? _configError;
  final ScrollController _scrollCtrl = ScrollController();

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

// ── Triage symptoms banner ────────────────────────────────────────────────────

/// Collapsible summary of ALL symptom codes selected in Step 1.
///
/// Collapsed by default — shows a count badge and a chevron.  Tap to expand
/// the full pill-chip list.  Always rendered at the top of the form so the SK
/// can review what was reported without navigating away.
class _TriageSymptomsBanner extends StatefulWidget {
  const _TriageSymptomsBanner({required this.symptomCodes});

  final List<String> symptomCodes;

  @override
  State<_TriageSymptomsBanner> createState() => _TriageSymptomsBannerState();
}

class _TriageSymptomsBannerState extends State<_TriageSymptomsBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.symptomCodes.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row (always visible) ────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 15,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      UnifiedFormStrings.triageSymptomsTitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  // Count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Expandable chip list ───────────────────────────────────────
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.symptomCodes.map((code) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      TriageStrings.symptomLabel(code),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
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
  });

  final String label;
  final List<String> relevantSymptomCodes;

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
          // ── Divider row — label left-aligned, divider extends right ───
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
                  children: codes.map((c) => _TriageChip(code: c)).toList(),
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
class _TriageChip extends StatelessWidget {
  const _TriageChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.statusWarningSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.statusWarning.withValues(alpha: 0.30),
        ),
      ),
      child: Text(
        TriageStrings.symptomLabel(code),
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.statusWarningText,
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (section.title.isNotEmpty) ...[
              Text(
                section.title.toUpperCase(),
                style: AppTextStyles.sectionLabel,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            ...section.fieldRefs.map((ref) {
              final def = config.fields[ref.id];
              if (def == null) return const SizedBox.shrink();
              final hasError = validationErrors.contains(ref.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: hasError
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.statusCritical,
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: _buildField(
                              context, def, ref, data.getValue(ref.id)),
                        ),
                      )
                    : _buildField(context, def, ref, data.getValue(ref.id)),
              );
            }),
          ],
        ),
      ),
    );
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
          labelText: def.label,
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
          labelText: def.label,
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
          label: def.label,
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
          label: def.label,
          isMandatory: ref.isMandatory,
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
          label: def.label,
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
          label: def.label,
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
          label: def.label,
          isMandatory: ref.isMandatory,
          isDecimal: true,
          initialValue: currentValue?.toString(),
          onChanged: (v) => onFieldChanged(def.id, v),
        );
    }
  }
}

// ── Inline micro-widgets (no hardcoded strings, tokens only) ─────────────────

class _NumericField extends StatefulWidget {
  const _NumericField({
    super.key,
    required this.label,
    required this.isMandatory,
    required this.isDecimal,
    required this.onChanged,
    this.initialValue,
    this.unit,
    this.hint,
  });

  final String label;
  final bool isMandatory;
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
      decoration: InputDecoration(
        labelText: widget.isMandatory ? '${widget.label} *' : widget.label,
        suffixText: widget.unit,
        hintText: widget.hint,
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _SpinnerField extends StatelessWidget {
  const _SpinnerField({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.currentValue,
  });

  final String label;
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
      decoration: InputDecoration(labelText: label),
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
    required this.label,
    required this.onChanged,
    this.currentValue,
  });

  final String label;
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
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
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
    required this.label,
    required this.readings,
    required this.onChanged,
  });

  final String label;
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _sys,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: UnifiedFormStrings.bpSystolicLabel,
                  suffixText: UnifiedFormStrings.bpUnit,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _dia,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: UnifiedFormStrings.bpDiastolicLabel,
                  suffixText: UnifiedFormStrings.bpUnit,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _pulse,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: UnifiedFormStrings.bpPulseLabel,
                  suffixText: UnifiedFormStrings.bpPulseUnit,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
          ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted)),
          if (value != null && value!.isNotEmpty)
            Text(value!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ))
          else
            Text('—',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textMuted)),
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
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(UnifiedFormStrings.submitLabel),
          ),
        ),
      ),
    );
  }
}
