/// Computed label (read-only value display) — wraps [InfoLabelField].
library;

import 'package:flutter/material.dart';

import '../../../../features/visit/widgets/form_fields/info_label_field.dart';
import '../../models/field_schema.dart';

class ComputedLabelWidget extends StatelessWidget {
  const ComputedLabelWidget({
    super.key,
    required this.schema,
    this.value,
  });

  final FieldSchema schema;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return InfoLabelField(
      labelText: schema.label,
      currentValue: value?.toString(),
    );
  }
}
