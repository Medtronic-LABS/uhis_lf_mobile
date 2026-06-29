/// Numeric input widget — handles both integer and decimal [FieldKind]s.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/field_schema.dart';

class NumberFieldWidget extends StatefulWidget {
  const NumberFieldWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    required this.decimal,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;
  final bool decimal;
  final num? value;
  final ValueChanged<num> onChanged;
  final bool readOnly;

  @override
  State<NumberFieldWidget> createState() => _NumberFieldWidgetState();
}

class _NumberFieldWidgetState extends State<NumberFieldWidget> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(NumberFieldWidget old) {
    super.didUpdateWidget(old);
    final newText = widget.value?.toString() ?? '';
    if (newText != _ctrl.text) _ctrl.text = newText;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _emit(String raw) {
    final parsed = widget.decimal
        ? double.tryParse(raw)
        : int.tryParse(raw);
    if (parsed == null) return;
    final min = widget.schema.min;
    final max = widget.schema.max;
    if (min != null && parsed < min) return;
    if (max != null && parsed > max) return;
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      readOnly: widget.readOnly,
      keyboardType: widget.decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: widget.decimal
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: widget.schema.label,
        hintText: widget.schema.hint,
        suffixText: widget.schema.unit,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onChanged: _emit,
    );
  }
}
