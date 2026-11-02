import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'form_control_sync.dart';

/// Text input whose displayed value follows parent [value] except while focused.
///
/// Used across Step 2 so vitals mirroring, BMI recompute, and live scribe
/// fills can update the notifier without stealing focus/caret from the field
/// the SK is editing. Scribe continues to fill other fields immediately.
class FormBoundTextField extends StatefulWidget {
  const FormBoundTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.style,
    this.decoration,
    this.validator,
    this.autovalidateMode,
    this.maxLines = 1,
    this.readOnly = false,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final InputDecoration? decoration;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final int maxLines;
  final bool readOnly;
  final bool enabled;

  @override
  State<FormBoundTextField> createState() => _FormBoundTextFieldState();
}

class _FormBoundTextFieldState extends State<FormBoundTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _controller = TextEditingController(text: widget.value ?? '');
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _syncFromParent();
    }
  }

  void _syncFromParent() {
    FormControlSync.applyExternalText(
      mounted: () => mounted,
      focusNode: _focusNode,
      controller: _controller,
      newText: widget.value ?? '',
    );
  }

  @override
  void didUpdateWidget(FormBoundTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _syncFromParent();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      style: widget.style,
      decoration: widget.decoration,
      maxLines: widget.maxLines,
      autovalidateMode: widget.autovalidateMode,
      validator: widget.validator,
      onChanged: widget.onChanged,
    );
  }
}
