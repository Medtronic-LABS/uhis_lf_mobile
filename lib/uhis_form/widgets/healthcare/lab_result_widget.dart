/// Lab result composite widget — [FieldKind.labResult].
///
/// Numeric input with an inline status badge showing in-range / out-of-range,
/// plus a small reference range row below.
/// Value shape: `{"value": 10.5}`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';
import '../_shared/status_badge.dart';

class LabResultWidget extends StatefulWidget {
  const LabResultWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with key 'value' (double).
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<LabResultWidget> createState() => _LabResultWidgetState();
}

class _LabResultWidgetState extends State<LabResultWidget> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value?['value']?.toString() ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? get _parsed => double.tryParse(_ctrl.text);

  bool? get _inRange {
    final v = _parsed;
    final min = widget.schema.min;
    final max = widget.schema.max;
    if (v == null) return null;
    if (min != null && v < min) return false;
    if (max != null && v > max) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final inRange = _inRange;
    final min = widget.schema.min;
    final max = widget.schema.max;
    final unit = widget.schema.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(
          schema: widget.schema,
          trailing: inRange != null
              ? SdkStatusBadge(
                  label: inRange
                      ? ComposerStrings.rangeInRange
                      : ComposerStrings.rangeOutOfRange,
                  textColor:
                      inRange ? AppColors.rangeNormal : AppColors.rangeCritical,
                  surfaceColor: inRange
                      ? AppColors.rangeNormalSurface
                      : AppColors.rangeCriticalSurface,
                )
              : null,
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _ctrl,
          readOnly: widget.readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(
            fontFamily: 'NunitoSans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: widget.schema.hint,
            suffixText: unit,
          ),
          onChanged: (v) {
            setState(() {});
            final parsed = double.tryParse(v);
            if (parsed != null) widget.onChanged({'value': parsed});
          },
        ),
        if (min != null || max != null) ...[
          const SizedBox(height: 4),
          Text(
            _refLabel(min, max, unit),
            style: const TextStyle(
              fontFamily: 'NunitoSans',
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  static String _refLabel(double? min, double? max, String? unit) {
    final u = unit ?? '';
    if (min != null && max != null) {
      return '${ComposerStrings.labReferencePrefix} $min–$max$u';
    }
    if (min != null) return '${ComposerStrings.labReferencePrefix} ≥ $min$u';
    if (max != null) return '${ComposerStrings.labReferencePrefix} ≤ $max$u';
    return '';
  }
}
