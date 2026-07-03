/// Danger signs composite widget — [FieldKind.dangerSigns].
///
/// Critical-surface multi-select shown on a red-tinted card. "None of the
/// above" is mutually exclusive with all other options.
/// Value shape: `["vaginalBleeding", "severeHeadache"]` or `["none"]`.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';

class DangerSignsWidget extends StatelessWidget {
  const DangerSignsWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// List of selected option values, or null.
  final List<dynamic>? value;
  final ValueChanged<List<String>> onChanged;
  final bool readOnly;

  static const _noneValue = 'none';

  List<String> get _selected =>
      (value ?? []).map((v) => v.toString()).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = schema.options;
    final selected = _selected;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.imciSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.imciBorder),
        boxShadow: const [],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppColors.dangerSignIconColor),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    text: schema.label.isEmpty ? 'Danger Signs' : schema.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.dangerSignText,
                      fontWeight: FontWeight.w700,
                    ),
                    children: schema.required
                        ? const [
                            TextSpan(
                              text: ' *',
                              style: TextStyle(color: AppColors.pink),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...options.map((opt) {
            final checked = selected.contains(opt.value);
            return _DangerSignTile(
              label: opt.label,
              checked: checked,
              readOnly: readOnly,
              onTap: () {
                if (readOnly) return;
                final next = List<String>.from(selected);
                if (checked) {
                  next.remove(opt.value);
                } else {
                  next.removeWhere((v) => v == _noneValue);
                  next.add(opt.value);
                }
                onChanged(next);
              },
            );
          }),
          const Divider(height: 16, color: AppColors.imciBorder),
          _DangerSignTile(
            label: 'None of the above',
            checked: selected.contains(_noneValue),
            readOnly: readOnly,
            isNone: true,
            onTap: () {
              if (readOnly) return;
              final hasNone = selected.contains(_noneValue);
              onChanged(hasNone ? [] : [_noneValue]);
            },
          ),
        ],
      ),
    );
  }
}

class _DangerSignTile extends StatelessWidget {
  const _DangerSignTile({
    required this.label,
    required this.checked,
    required this.onTap,
    this.readOnly = false,
    this.isNone = false,
  });

  final String label;
  final bool checked;
  final bool readOnly;
  final bool isNone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: checked
                    ? (isNone
                        ? AppColors.rangeNormal
                        : AppColors.dangerSignIconColor)
                    : Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: checked
                      ? (isNone
                          ? AppColors.rangeNormal
                          : AppColors.dangerSignIconColor)
                      : AppColors.imciBorder,
                  width: 1.5,
                ),
              ),
              child: checked
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isNone
                      ? AppColors.textMid
                      : AppColors.dangerSignText,
                  fontWeight:
                      isNone ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
