/// Date picker widget — wraps the fixed [DateFormField].
library;

import 'package:flutter/material.dart';

import '../../../../features/visit/widgets/form_fields/date_form_field.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class DateFieldWidget extends StatelessWidget {
  const DateFieldWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// ISO-8601 date string or null.
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
        DateFormField(
          labelText: schema.label,
          currentValue: value,
          hint: schema.hint,
          onChanged: readOnly ? (_) {} : onChanged,
        ),
      ],
    );
  }
}
