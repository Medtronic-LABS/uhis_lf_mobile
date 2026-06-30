/// Numeric input widget — handles both integer and decimal [FieldKind]s.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class NumberFieldWidget extends StatefulWidget {
  const NumberFieldWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    required this.decimal,
    this.value,
    this.readOnly = false,
    this.errorText,
  });

  final FieldSchema schema;
  final bool decimal;
  final num? value;
  final ValueChanged<num> onChanged;
  final bool readOnly;
  final String? errorText;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: widget.schema),
        const SizedBox(height: 4),
        TextFormField(
          controller: _ctrl,
          readOnly: widget.readOnly,
          keyboardType: widget.decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          inputFormatters: widget.decimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontFamily: 'NunitoSans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: widget.schema.hint,
            suffixText: widget.schema.unit,
            errorText: widget.errorText,
          ),
          onChanged: _emit,
        ),
      ],
    );
  }
}
