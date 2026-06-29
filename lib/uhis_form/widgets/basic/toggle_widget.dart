/// Toggle (checkbox) widget — [FieldKind.toggleSwitch].
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';

class ToggleWidget extends StatelessWidget {
  const ToggleWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;
  final bool? value;
  final ValueChanged<bool> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Checkbox(
          value: value ?? false,
          onChanged: readOnly ? null : (v) => onChanged(v ?? false),
          activeColor: AppColors.navy,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: GestureDetector(
            onTap: readOnly ? null : () => onChanged(!(value ?? false)),
            child: Text(
              schema.label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}
