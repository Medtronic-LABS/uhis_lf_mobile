/// Pregnancy profile composite widget — [FieldKind.pregnancyProfile].
///
/// LMP date picker → computed EDD (LMP + 280 days) and gestational age.
/// Shows amber warning if gestational age < 37 weeks.
/// Value shape: `{"lmp": "2025-09-01", "edd": "2026-06-08", "weeks": 28}`.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';
import '../basic/date_field_widget.dart';

class PregnancyProfileWidget extends StatefulWidget {
  const PregnancyProfileWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with keys: lmp (ISO date String), edd, weeks.
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<PregnancyProfileWidget> createState() => _PregnancyProfileWidgetState();
}

class _PregnancyProfileWidgetState extends State<PregnancyProfileWidget> {
  String? _lmp;

  @override
  void initState() {
    super.initState();
    _lmp = widget.value?['lmp']?.toString();
  }

  int? get _weeks {
    if (_lmp == null) return null;
    final lmpDate = DateTime.tryParse(_lmp!);
    if (lmpDate == null) return null;
    return DateTime.now().difference(lmpDate).inDays ~/ 7;
  }

  String? get _edd {
    if (_lmp == null) return null;
    final lmpDate = DateTime.tryParse(_lmp!);
    if (lmpDate == null) return null;
    final edd = lmpDate.add(const Duration(days: 280));
    return '${edd.year}-${edd.month.toString().padLeft(2, '0')}-${edd.day.toString().padLeft(2, '0')}';
  }

  void _emit(String lmp) {
    final lmpDate = DateTime.tryParse(lmp);
    if (lmpDate == null) return;
    final edd = lmpDate.add(const Duration(days: 280));
    final eddStr =
        '${edd.year}-${edd.month.toString().padLeft(2, '0')}-${edd.day.toString().padLeft(2, '0')}';
    final weeks = DateTime.now().difference(lmpDate).inDays ~/ 7;
    widget.onChanged({'lmp': lmp, 'edd': eddStr, 'weeks': weeks});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = _weeks;
    final eddStr = _edd;
    final isPreterm = weeks != null && weeks < 37;

    final lmpSchema = FieldSchema(
      fieldId: 'lmp',
      label: ComposerStrings.lmpLabel,
      kind: widget.schema.kind,
      required: widget.schema.required,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: widget.schema, fallback: 'Pregnancy Profile'),
        const SizedBox(height: 4),
        DateFieldWidget(
          schema: lmpSchema,
          value: _lmp,
          readOnly: widget.readOnly,
          onChanged: (v) {
            setState(() => _lmp = v);
            _emit(v);
          },
        ),
        if (eddStr != null) ...[
          const SizedBox(height: 10),
          _InfoRow(
            label: ComposerStrings.eddLabel,
            value: eddStr,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _InfoRow(
            label: ComposerStrings.gestationalAgeLabel,
            value: '$weeks ${ComposerStrings.gestationalAgeWeeks}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isPreterm ? AppColors.rangeElevated : AppColors.textPrimary,
            ),
            trailing: isPreterm
                ? Text(
                    ComposerStrings.gestationalAgePreterm,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.rangeElevated,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.style,
    this.trailing,
  });

  final String label;
  final String value;
  final TextStyle? style;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '$label:',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        Text(value, style: style),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}
