/// Danger signs composite widget — [FieldKind.dangerSigns].
///
/// Critical-surface multi-select shown on a red-tinted card. "None of the
/// above" is mutually exclusive with all other options.
/// Value shape: `["vaginalBleeding", "severeHeadache"]` or `["none"]`.
library;

import 'package:flutter/material.dart';

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
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
        // ignore: prefer_const_constructors
        boxShadow: const [],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: 6),
              Text(
                schema.label.isEmpty ? 'Danger Signs' : schema.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF7F1D1D),
                  fontWeight: FontWeight.w700,
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
          const Divider(height: 16, color: Color(0xFFFCA5A5)),
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
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626))
                    : Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: checked
                      ? (isNone
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626))
                      : const Color(0xFFFCA5A5),
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
                      ? const Color(0xFF374151)
                      : const Color(0xFF7F1D1D),
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
