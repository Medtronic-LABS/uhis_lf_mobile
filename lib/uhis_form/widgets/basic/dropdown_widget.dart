/// Dropdown widget for single-select fields with more than 4 options.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';

class DropdownWidget extends StatelessWidget {
  const DropdownWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          schema.label,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: schema.options.any((o) => o.value == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: schema.hint ?? 'Select',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: schema.options
              .map((o) => DropdownMenuItem(
                    value: o.value,
                    child: Text(o.label),
                  ))
              .toList(),
          onChanged: readOnly
              ? null
              : (v) {
                  if (v != null) onChanged(v);
                },
        ),
      ],
    );
  }
}
