/// Date picker widget — wraps the fixed [DateFormField].
library;

import 'package:flutter/material.dart';

import '../../../../features/visit/widgets/form_fields/date_form_field.dart';
import '../../models/field_schema.dart';

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
    return DateFormField(
      labelText: schema.label,
      currentValue: value,
      hint: schema.hint,
      onChanged: readOnly ? (_) {} : onChanged,
    );
  }
}
