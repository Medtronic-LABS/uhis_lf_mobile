/// Obstetric history composite widget — [FieldKind.obstetricHistory].
///
/// Gravida + Parity + Living children trio with inline G/P notation and soft
/// cross-field validation (parity ≤ gravida, living ≤ parity).
/// Value shape: `{"gravida": 3, "parity": 2, "livingChildren": 2}`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class ObstetricHistoryWidget extends StatefulWidget {
  const ObstetricHistoryWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with keys: gravida, parity, livingChildren (int values).
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<ObstetricHistoryWidget> createState() =>
      _ObstetricHistoryWidgetState();
}

class _ObstetricHistoryWidgetState extends State<ObstetricHistoryWidget> {
  late final TextEditingController _gravidaCtrl;
  late final TextEditingController _parityCtrl;
  late final TextEditingController _livingCtrl;

  @override
  void initState() {
    super.initState();
    final v = widget.value ?? {};
    _gravidaCtrl = TextEditingController(text: v['gravida']?.toString() ?? '');
    _parityCtrl  = TextEditingController(text: v['parity']?.toString() ?? '');
    _livingCtrl  = TextEditingController(text: v['livingChildren']?.toString() ?? '');
  }

  @override
  void dispose() {
    _gravidaCtrl.dispose();
    _parityCtrl.dispose();
    _livingCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final g = int.tryParse(_gravidaCtrl.text);
    final p = int.tryParse(_parityCtrl.text);
    final l = int.tryParse(_livingCtrl.text);
    final result = <String, dynamic>{};
    if (g != null) result['gravida'] = g;
    if (p != null) result['parity'] = p;
    if (l != null) result['livingChildren'] = l;
    if (result.isNotEmpty) widget.onChanged(result);
  }

  String? get _validationWarning {
    final g = int.tryParse(_gravidaCtrl.text);
    final p = int.tryParse(_parityCtrl.text);
    final l = int.tryParse(_livingCtrl.text);
    if (g != null && p != null && p > g) {
      return 'Parity cannot exceed gravida';
    }
    if (p != null && l != null && l > p) {
      return 'Living children cannot exceed parity';
    }
    return null;
  }

  String get _notation {
    final g = int.tryParse(_gravidaCtrl.text);
    final p = int.tryParse(_parityCtrl.text);
    final l = int.tryParse(_livingCtrl.text);
    if (g == null && p == null) return '';
    final parts = <String>[];
    if (g != null) parts.add('G$g');
    if (p != null) parts.add('P$p');
    if (l != null) parts.add('L$l');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = _validationWarning;
    final notation = _notation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: widget.schema, fallback: 'Obstetric History'),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _ObsInput(
                ctrl: _gravidaCtrl,
                label: ComposerStrings.fieldGravida,
                readOnly: widget.readOnly,
                onChanged: (_) => setState(_emit),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ObsInput(
                ctrl: _parityCtrl,
                label: ComposerStrings.parityShort,
                readOnly: widget.readOnly,
                onChanged: (_) => setState(_emit),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ObsInput(
                ctrl: _livingCtrl,
                label: ComposerStrings.livingShort,
                readOnly: widget.readOnly,
                onChanged: (_) => setState(_emit),
              ),
            ),
          ],
        ),
        if (notation.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            notation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (warning != null) ...[
          const SizedBox(height: 4),
          Text(
            warning,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.rangeAbnormal,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _ObsInput extends StatelessWidget {
  const _ObsInput({
    required this.ctrl,
    required this.label,
    required this.onChanged,
    this.readOnly = false,
  });

  final TextEditingController ctrl;
  final String label;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TextFormField(
          controller: ctrl,
          readOnly: readOnly,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            contentPadding: AppTheme.denseFieldPadding,
          ),
          onChanged: onChanged,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}
