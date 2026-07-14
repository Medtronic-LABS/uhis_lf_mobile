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
    required this.options,
    required this.onChanged,
    this.currentValue,
    this.severityColors,
  });

  final List<String> options;
  final String? currentValue;

  /// Called with the tapped option's string, or `null` when the already-
  /// selected option is tapped again (toggle-deselect).
  final ValueChanged<String?> onChanged;

  /// Optional per-option selected-state color, keyed by the option's display
  /// name — e.g. `{'Present': red, 'Absent': green}` for a danger-sign-
  /// adjacent tri-state field. Options not present in the map (or when this
  /// is null) fall back to the default navy selected color.
  final Map<String, Color>? severityColors;

  @override
  Widget build(BuildContext context) {
    // Label is provided by the enclosing field shell; this widget renders the
    // pill row only.
    return options.length <= 3
        ? Row(
            children: _buildOptions(context, withFlex: true),
          )
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buildOptions(context, withFlex: false),
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
        selectedColor: severityColors?[opt],
        // Tapping the already-selected pill deselects (sends null); tapping
        // an unselected pill selects it.
        onTap: () => onChanged(selected ? null : opt),
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
    this.selectedColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Overrides the default navy selected-state color (see
  /// [RadioFormField.severityColors]).
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = selectedColor ?? AppColors.navy;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? activeColor : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? activeColor : AppColors.border,
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
