/// Age or DOB widget — wraps the fixed [AgeOrDobField].
library;

import 'package:flutter/material.dart';

import '../../../../features/visit/widgets/form_fields/age_or_dob_field.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class AgeOrDobWidget extends StatelessWidget {
  const AgeOrDobWidget({
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
        AgeOrDobField(
          labelText: schema.label,
          currentValue: value,
          onChanged: readOnly ? (_) {} : onChanged,
        ),
      ],
    );
  }
}
