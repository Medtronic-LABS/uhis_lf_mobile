/// Plain text input widget — [FieldKind.textInput].
library;

import 'package:flutter/material.dart';

import '../../models/field_schema.dart';

class TextFieldWidget extends StatefulWidget {
  const TextFieldWidget({
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
  State<TextFieldWidget> createState() => _TextFieldWidgetState();
}

class _TextFieldWidgetState extends State<TextFieldWidget> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(TextFieldWidget old) {
    super.didUpdateWidget(old);
    final newText = widget.value ?? '';
    if (newText != _ctrl.text) _ctrl.text = newText;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      readOnly: widget.readOnly,
      decoration: InputDecoration(
        labelText: widget.schema.label,
        hintText: widget.schema.hint,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onChanged: widget.readOnly ? null : widget.onChanged,
    );
  }
}
