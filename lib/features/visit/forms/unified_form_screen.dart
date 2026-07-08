import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/form_fields/dialog_multi_select_field.dart';
import '../widgets/form_fields/radio_form_field.dart';
import 'canonical_visit_data.dart';
import 'form_config.dart';
import 'unified_form_notifier.dart';
import 'unified_section_rules.dart';

/// JSON-driven assessment form.
///
/// Reads [FormConfig] from assets, applies [UnifiedSectionRules] to produce
/// an ordered, deduplicated section list, and renders each field using the
/// appropriate existing field widget. Delegates state to [UnifiedFormNotifier].
///
/// The caller wraps this widget in a [ChangeNotifierProvider<UnifiedFormNotifier>]
/// and supplies [onSubmitComplete] to handle post-submit navigation.
class UnifiedFormScreen extends StatefulWidget {
  const UnifiedFormScreen({
    super.key,
    required this.activeFormTypes,
    required this.onSubmitComplete,
    this.gestationalWeeks,
  });

  /// Ordered formType keys (e.g. `['anc', 'ncd']`) from activated pathways.
  final List<String> activeFormTypes;

  /// Called after [UnifiedFormNotifier.submit] succeeds. Navigation lives here.
  final VoidCallback onSubmitComplete;

  /// Passed to [UnifiedSectionRules] for conditional `birthPreparedness` visibility.
  final int? gestationalWeeks;

  @override
  State<UnifiedFormScreen> createState() => _UnifiedFormScreenState();
}

class _UnifiedFormScreenState extends State<UnifiedFormScreen> {
  FormConfig? _config;
  bool _configLoading = true;
  Object? _configError;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<UnifiedFormNotifier>().loadDraft();
      }
    });
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await FormConfig.load(rootBundle);
      if (mounted) setState(() { _config = cfg; _configLoading = false; });
    } catch (e) {
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
        final sections = UnifiedSectionRules.activeSections(
          config: _config!,
          activeFormTypes: widget.activeFormTypes,
          currentData: notifier.data,
        );

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxxl,
                  vertical: AppSpacing.xxxl,
                ),
                itemCount: sections.length,
                itemBuilder: (ctx, i) =>
                    _SectionCard(
                      section: sections[i],
                      config: _config!,
                      data: notifier.data,
                      onFieldChanged: notifier.updateField,
                    ),
              ),
            ),
            _SubmitBar(
              submitting: notifier.submitting,
              onSubmit: () => _onSubmit(ctx, notifier),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onSubmit(BuildContext ctx, UnifiedFormNotifier notifier) async {
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
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.config,
    required this.data,
    required this.onFieldChanged,
  });

  final FormSection section;
  final FormConfig config;
  final CanonicalVisitData data;
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
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: _buildField(context, def, ref, data.getValue(ref.id)),
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
        return RadioFormField(
          key: Key('unified_form_${def.id}_input'),
          labelText: def.label,
          options: def.options.map((o) => o.name).toList(),
          currentValue: currentValue as String?,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.dialogCheckbox:
        final selected = (currentValue is List)
            ? currentValue.cast<String>()
            : <String>[];
        return DialogMultiSelectField(
          key: Key('unified_form_${def.id}_input'),
          labelText: def.label,
          options: def.options.map((o) => o.name).toList(),
          currentValue: selected,
          onChanged: (v) => onFieldChanged(def.id, v),
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
        return _NumericField(
          key: Key('unified_form_${def.id}_input'),
          label: def.label,
          isMandatory: ref.isMandatory,
          isDecimal: ref.inputType == 2,
          initialValue: currentValue?.toString(),
          onChanged: (v) {
            if (v == null || v.isEmpty) {
              onFieldChanged(def.id, null);
            } else {
              final parsed = ref.inputType == 2
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
      case WidgetHint.textLabel:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(def.label, style: AppTextStyles.subText),
        );

      case WidgetHint.bpField:
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

class _NumericField extends StatelessWidget {
  const _NumericField({
    super.key,
    required this.label,
    required this.isMandatory,
    required this.isDecimal,
    required this.onChanged,
    this.initialValue,
  });

  final String label;
  final bool isMandatory;
  final bool isDecimal;
  final String? initialValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: [
        if (isDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: isMandatory ? '$label *' : label,
      ),
      onChanged: onChanged,
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
    return DropdownButtonFormField<String>(
      initialValue: currentValue,
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
