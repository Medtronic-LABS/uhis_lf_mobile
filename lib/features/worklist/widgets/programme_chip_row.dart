import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/programme.dart';

/// Horizontal chip row above the worklist: All / IMCI / ANC / NCD / TB.
///
/// `selection` is a `Set<Programme>` — empty means "All". Chips are
/// single-select today (tapping any specific programme replaces selection);
/// flip to multi-select by passing a different [onChanged] strategy.
class ProgrammeChipRow extends StatelessWidget {
  const ProgrammeChipRow({
    super.key,
    required this.selection,
    required this.onChanged,
  });

  final Set<Programme> selection;
  final ValueChanged<Set<Programme>> onChanged;

  @override
  Widget build(BuildContext context) {
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _chip(
            context,
            label: WorklistStrings.filterAll,
            selected: selection.isEmpty,
            color: Theme.of(context).colorScheme.primary,
            onTap: () => onChanged(const <Programme>{}),
          ),
          const SizedBox(width: 8),
          _chip(
            context,
            label: WorklistStrings.filterImci,
            selected: selection.contains(Programme.imci),
            color: progColors.imci,
            onTap: () => onChanged(<Programme>{Programme.imci}),
          ),
          const SizedBox(width: 8),
          _chip(
            context,
            label: WorklistStrings.filterAnc,
            selected: selection.contains(Programme.anc),
            color: progColors.anc,
            onTap: () => onChanged(<Programme>{Programme.anc}),
          ),
          const SizedBox(width: 8),
          _chip(
            context,
            label: WorklistStrings.filterNcd,
            selected: selection.contains(Programme.ncd),
            color: progColors.ncd,
            onTap: () => onChanged(<Programme>{Programme.ncd}),
          ),
          const SizedBox(width: 8),
          _chip(
            context,
            label: WorklistStrings.filterTb,
            selected: selection.contains(Programme.tb),
            color: progColors.tb,
            onTap: () => onChanged(<Programme>{Programme.tb}),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? color : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? color : Theme.of(context).colorScheme.outlineVariant),
    );
  }
}
