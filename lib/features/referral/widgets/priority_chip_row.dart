import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/sla.dart';

/// Horizontal chip row above the referral dashboard: All / Critical / High /
/// Medium / Low. Single-select for now (matches `ProgrammeChipRow`).
class PriorityChipRow extends StatelessWidget {
  const PriorityChipRow({
    super.key,
    required this.selected,
    required this.onChanged,
    this.counts = const <SlaPriority, int>{},
  });

  final SlaPriority? selected;
  final ValueChanged<SlaPriority?> onChanged;
  final Map<SlaPriority, int> counts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _chip(context,
              label: ReferralStrings.filterAll,
              selected: selected == null,
              color: scheme.primary,
              onTap: () => onChanged(null)),
          const SizedBox(width: 10),
          for (final p in SlaPriority.values) ...[
            _chip(context,
                label: '${_labelFor(p)} ${_countFor(p)}'.trim(),
                selected: selected == p,
                color: _accentFor(p, scheme),
                onTap: () => onChanged(p)),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  String _countFor(SlaPriority p) {
    final c = counts[p];
    return (c == null || c == 0) ? '' : '($c)';
  }

  static String _labelFor(SlaPriority p) {
    switch (p) {
      case SlaPriority.critical:
        return ReferralStrings.filterCritical;
      case SlaPriority.high:
        return ReferralStrings.filterHigh;
      case SlaPriority.medium:
        return ReferralStrings.filterMedium;
      case SlaPriority.low:
        return ReferralStrings.filterLow;
    }
  }

  static Color _accentFor(SlaPriority p, ColorScheme scheme) {
    switch (p) {
      case SlaPriority.critical:
        return scheme.error;
      case SlaPriority.high:
        return scheme.tertiary;
      case SlaPriority.medium:
        return scheme.primary;
      case SlaPriority.low:
        return scheme.onSurfaceVariant;
    }
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
      selectedColor: color.withValues(alpha: 0.25),
      labelStyle: TextStyle(
        color: selected ? color : Theme.of(context).colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: 14,
      ),
      side: BorderSide(
          color:
              selected ? color : Theme.of(context).colorScheme.outline,
          width: selected ? 1.5 : 1),
    );
  }
}
