/// Static text display — renders plain label text or a styled instruction block.
///
/// Not interactive; carries no [onChanged]. Used for API viewType `TextLabel`
/// and `Instruction`. When [isInstruction] is true the text is wrapped in a
/// left-bordered container matching the design reference accent style.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class TextLabelField extends StatelessWidget {
  const TextLabelField({
    super.key,
    required this.text,
    this.isInstruction = false,
  });

  final String text;

  /// When true, renders with a 3 px navy left border and light surface tint
  /// (instruction block style). When false, renders as plain inline text.
  final bool isInstruction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: AppColors.textMid,
        height: 1.5,
      ),
    );

    if (!isInstruction) return content;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        border: const Border(
          left: BorderSide(color: AppColors.navy, width: 3),
        ),
      ),
      child: content,
    );
  }
}
