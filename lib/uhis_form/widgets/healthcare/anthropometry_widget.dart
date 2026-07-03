/// Anthropometry composite widget — [FieldKind.anthropometry].
///
/// Height + weight side-by-side inputs with auto-computed BMI row.
/// Value shape: `{"height": 165.0, "weight": 72.0, "bmi": 26.4}`.
///
/// BMI categories (WHO):
///   Underweight : < 18.5
///   Normal      : 18.5–24.9
///   Overweight  : 25–29.9
///   Obese       : ≥ 30
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class AnthropometryWidget extends StatefulWidget {
  const AnthropometryWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with keys 'height' (cm), 'weight' (kg), 'bmi'.
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<AnthropometryWidget> createState() => _AnthropometryWidgetState();
}

class _AnthropometryWidgetState extends State<AnthropometryWidget> {
  late final TextEditingController _heightCtrl;
  late final TextEditingController _weightCtrl;

  @override
  void initState() {
    super.initState();
    _heightCtrl = TextEditingController(
        text: widget.value?['height']?.toString() ?? '');
    _weightCtrl = TextEditingController(
        text: widget.value?['weight']?.toString() ?? '');
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    setState(() {});
    final h = double.tryParse(_heightCtrl.text);
    final w = double.tryParse(_weightCtrl.text);
    if (h != null && w != null && h > 0) {
      final bmi = w / ((h / 100) * (h / 100));
      widget.onChanged({
        'height': h,
        'weight': w,
        'bmi': double.parse(bmi.toStringAsFixed(1)),
      });
    } else if (h != null || w != null) {
      final partial = <String, dynamic>{};
      if (h != null) partial['height'] = h;
      if (w != null) partial['weight'] = w;
      widget.onChanged(partial);
    }
  }

  double? get _bmi {
    final h = double.tryParse(_heightCtrl.text);
    final w = double.tryParse(_weightCtrl.text);
    if (h == null || w == null || h <= 0) return null;
    return w / ((h / 100) * (h / 100));
  }

  @override
  Widget build(BuildContext context) {
    final bmi = _bmi;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: widget.schema),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _LabeledInput(
                ctrl: _heightCtrl,
                label: ComposerStrings.heightShort,
                unit: 'cm',
                readOnly: widget.readOnly,
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledInput(
                ctrl: _weightCtrl,
                label: ComposerStrings.weightShort,
                unit: 'kg',
                readOnly: widget.readOnly,
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
        if (bmi != null) ...[
          const SizedBox(height: 8),
          _BmiRow(bmi: bmi),
        ],
      ],
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.ctrl,
    required this.label,
    required this.unit,
    required this.onChanged,
    this.readOnly = false,
  });

  final TextEditingController ctrl;
  final String label;
  final String unit;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: ctrl,
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            suffixText: unit,
            contentPadding: AppTheme.denseFieldPadding,
          ),
          onChanged: onChanged,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _BmiRow extends StatelessWidget {
  const _BmiRow({required this.bmi});

  final double bmi;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _classify(bmi);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Text(
            'BMI  ${bmi.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '— $label',
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static (String, Color) _classify(double bmi) {
    if (bmi < 18.5) return ('Underweight', AppColors.rangeElevated);
    if (bmi < 25)   return (ComposerStrings.rangeNormal, AppColors.rangeNormal);
    if (bmi < 30)   return ('Overweight', AppColors.rangeAbnormal);
    return ('Obese', AppColors.rangeCritical);
  }
}
