/// Radio group field — API viewType `RadioGroup` / `SingleSelectionView`.
///
/// Mirrors Android `SingleSelectionCustomView`: the pill shows a translated
/// [RadioOption.label], but selection state and [onChanged] always use the
/// stable option [RadioOption.id] (never the display string).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// One selectable radio pill — id for wire/state, label for UI.
class RadioOption {
  const RadioOption({required this.id, required this.label});

  final String id;
  final String label;
}

class RadioFormField extends StatelessWidget {
  const RadioFormField({
    super.key,
    required this.options,
    required this.onChanged,
    this.currentValue,
    this.severityColors,
  });

  final List<RadioOption> options;

  /// Stored option **id** (Android `DefinedParams.ID`), not the label.
  final String? currentValue;

  /// Called with the tapped option's **id**, or `null` when the already-
  /// selected option is tapped again (toggle-deselect).
  final ValueChanged<String?> onChanged;

  /// Optional per-option selected-state color, keyed by option **id**.
  final Map<String, Color>? severityColors;

  @override
  Widget build(BuildContext context) {
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
      final selected = opt.id == currentValue;
      final tile = _PillButton(
        label: opt.label,
        selected: selected,
        selectedColor: severityColors?[opt.id],
        onTap: () => onChanged(selected ? null : opt.id),
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
