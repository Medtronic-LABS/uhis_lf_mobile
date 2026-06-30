/// Age Y/M/D widget — wraps the fixed [AgeYmdField].
library;

import 'package:flutter/material.dart';

import '../../../../features/visit/widgets/form_fields/age_ymd_field.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class AgeYmdWidget extends StatelessWidget {
  const AgeYmdWidget({
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
        AgeYmdField(
          labelText: schema.label,
          currentValue: value,
          onChanged: readOnly ? (_) {} : onChanged,
        ),
      ],
    );
  }
}
