/// Blood glucose composite widget — [FieldKind.bloodGlucose].
///
/// Type selector (Fasting / Random / Post-prandial) + numeric value + unit.
/// Value shape: `{"type": "fasting", "value": 6.2, "unit": "mmol/L"}`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';
import '../_shared/status_badge.dart';

class BloodGlucoseWidget extends StatefulWidget {
  const BloodGlucoseWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with keys: type (String), value (double), unit (String).
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<BloodGlucoseWidget> createState() => _BloodGlucoseWidgetState();
}

class _BloodGlucoseWidgetState extends State<BloodGlucoseWidget> {
  // Spec §4.2.3: 2hr PP option removed. Fasting threshold ≥5.1, Random ≥11.1.
  static const _types = ['Fasting', 'Random'];
  static const _unit = 'mmol/L';

  late String _selectedType;
  late final TextEditingController _valueCtrl;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.value?['type']?.toString() ?? 'Fasting';
    _valueCtrl = TextEditingController(
        text: widget.value?['value']?.toString() ?? '');
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    setState(() {});
    final v = double.tryParse(_valueCtrl.text);
    if (v != null) {
      widget.onChanged({
        'type': _selectedType.toLowerCase(),
        'value': v,
        'unit': _unit,
      });
    }
  }

  double? get _normalMax {
    return switch (_selectedType) {
      'Fasting' => 5.1,
      'Random'  => 11.1,
      _         => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = double.tryParse(_valueCtrl.text);
    final max = _normalMax;
    final inRange = parsed != null && max != null && parsed < max;
    final outRange = parsed != null && max != null && parsed >= max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: widget.schema, fallback: 'Blood Glucose'),
        const SizedBox(height: 4),
        // Type selector
        Wrap(
          spacing: 8,
          children: _types.map((t) {
            final selected = t == _selectedType;
            return GestureDetector(
              onTap: widget.readOnly ? null : () => setState(() {
                _selectedType = t;
                _emit();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? AppColors.navy : AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? AppColors.navy : AppColors.border,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  t,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? AppColors.textOnNavy
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // Value input
        TextFormField(
          controller: _valueCtrl,
          readOnly: widget.readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            suffixText: _unit,
            contentPadding: AppTheme.denseFieldPadding,
          ),
          onChanged: (_) => _emit(),
        ),
        if (inRange) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: SdkStatusBadge(
              label: ComposerStrings.rangeInRange,
              textColor: AppColors.rangeNormal,
              surfaceColor: AppColors.rangeNormalSurface,
            ),
          ),
        ] else if (outRange) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: SdkStatusBadge(
              label: ComposerStrings.rangeOutOfRange,
              textColor: AppColors.rangeCritical,
              surfaceColor: AppColors.rangeCriticalSurface,
            ),
          ),
        ],
      ],
    );
  }
}
