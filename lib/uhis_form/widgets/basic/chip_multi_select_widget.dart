/// Chip multi-select widget — wraps existing [DialogMultiSelectField].
library;

import 'package:flutter/material.dart';

import '../../../../features/visit/widgets/form_fields/dialog_multi_select_field.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class ChipMultiSelectWidget extends StatelessWidget {
  const ChipMultiSelectWidget({
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

  @override
  Widget build(BuildContext context) {
    final selected = (value ?? []).map((v) => v.toString()).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: schema),
        const SizedBox(height: 4),
        DialogMultiSelectField(
          labelText: schema.label,
          options: schema.options.map((o) => o.label).toList(),
          currentValue: selected,
          onChanged: readOnly ? (_) {} : onChanged,
        ),
      ],
    );
  }
}
