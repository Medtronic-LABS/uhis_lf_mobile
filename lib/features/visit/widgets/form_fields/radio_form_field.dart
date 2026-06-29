/// Radio group field — API viewType `RadioGroup`.
///
/// Renders a horizontal row of pill buttons for 2-option (Yes/No) questions.
/// For 3+ options, the buttons wrap automatically. Selected option is navy;
/// unselected options are white with a border. Value is the raw option string.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class RadioFormField extends StatelessWidget {
  const RadioFormField({
    super.key,
    required this.labelText,
    required this.options,
    required this.onChanged,
    this.currentValue,
  });

  final String labelText;
  final List<String> options;
  final String? currentValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        options.length <= 3
            ? Row(
                children: _buildOptions(context, withFlex: true),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildOptions(context, withFlex: false),
              ),
      ],
    );
  }

  List<Widget> _buildOptions(BuildContext context, {required bool withFlex}) {
    final List<Widget> items = [];
    for (int i = 0; i < options.length; i++) {
      final opt = options[i];
      final selected = opt == currentValue;
      final tile = _PillButton(
        label: opt,
        selected: selected,
        onTap: () => onChanged(opt),
      );
      if (withFlex) {
        items.add(Expanded(child: tile));
        if (i < options.length - 1) items.add(const SizedBox(width: 8));
      } else {
        items.add(tile);
      }
    }
    return items;
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.border,
            width: 2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected ? AppColors.textOnNavy : AppColors.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
