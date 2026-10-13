import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Keeps [TextEditingController] text aligned with parent form state without
/// disturbing the caret while the SK is typing.
abstract final class FormControlSync {
  FormControlSync._();

  /// True when [a] and [b] parse to the same number (e.g. `120` vs `120.0`).
  static bool numericEquivalent(String a, String b) {
    final an = double.tryParse(a);
    final bn = double.tryParse(b);
    if (an != null && bn != null) return an == bn;
    return false;
  }

  /// Applies [newText] to [controller] after build, unless [focusNode] has
  /// focus (manual entry in progress). Caret moves to end only when text
  /// actually changes.
  static void applyExternalText({
    required bool Function() mounted,
    required FocusNode focusNode,
    required TextEditingController controller,
    required String newText,
  }) {
    if (focusNode.hasFocus) return;
    if (controller.text == newText) return;
    if (numericEquivalent(controller.text, newText)) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted()) return;
      if (focusNode.hasFocus) return;
      if (controller.text == newText) return;
      if (numericEquivalent(controller.text, newText)) return;
      controller.text = newText;
      controller.selection = TextSelection.collapsed(offset: newText.length);
    });
  }
}
