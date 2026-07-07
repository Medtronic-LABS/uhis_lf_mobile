/// Dropdown widget for single-select fields with more than 4 options.
library;

import 'package:flutter/material.dart';

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
          // Inherits border/fill/padding/radius from Theme.of(context)
          // .inputDecorationTheme — matches text_field_widget.dart /
          // number_field_widget.dart, so it picks up app-theme changes
          // instead of duplicating them.
          decoration: InputDecoration(
            hintText: schema.hint ?? 'Select',
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
