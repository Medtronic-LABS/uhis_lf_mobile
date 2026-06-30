/// Dropdown widget for single-select fields with more than 4 options.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: schema),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: schema.options.any((o) => o.value == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: schema.hint ?? 'Select',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
              borderSide:
                  const BorderSide(color: AppColors.aiBorder, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
              borderSide:
                  const BorderSide(color: AppColors.aiBorder, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
              borderSide:
                  const BorderSide(color: AppColors.aiPurple, width: 1.5),
            ),
            filled: true,
            fillColor: AppColors.cardSurfaceMuted,
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
