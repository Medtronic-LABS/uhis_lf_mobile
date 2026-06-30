/// Radio group widget — wraps existing [RadioFormField] with the SDK contract.
library;

import 'package:flutter/material.dart';

import '../../../../features/visit/widgets/form_fields/radio_form_field.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class RadioGroupWidget extends StatelessWidget {
  const RadioGroupWidget({
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
        RadioFormField(
          labelText: schema.label,
          options: schema.options.map((o) => o.label).toList(),
          currentValue: value,
          onChanged: readOnly ? (_) {} : onChanged,
        ),
      ],
    );
  }
}
