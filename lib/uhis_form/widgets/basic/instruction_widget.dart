/// Instruction block — wraps [TextLabelField] with isInstruction=true.
library;

import 'package:flutter/material.dart';

import '../../../../features/visit/widgets/form_fields/text_label_field.dart';
import '../../models/field_schema.dart';

class InstructionWidget extends StatelessWidget {
  const InstructionWidget({super.key, required this.schema});

  final FieldSchema schema;

  @override
  Widget build(BuildContext context) {
    return TextLabelField(
      text: schema.label,
      isInstruction: true,
    );
  }
}
