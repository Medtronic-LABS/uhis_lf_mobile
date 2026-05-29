import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/sla.dart';

/// Section 1 — Identity Strip
/// Top-most compact row showing patient avatar, name, age, and priority badge.
class IdentityStrip extends StatelessWidget {
  const IdentityStrip({
    super.key,
    required this.patientName,
    this.patientAge,
    required this.priority,
    this.isCompleted = false,
  });

  final String patientName;
  final int? patientAge;
  final SlaPriority priority;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _getInitials(patientName);
    
    return Row(
      children: [
        // Avatar with initials
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _accentFor(priority, scheme).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              initials,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _accentFor(priority, scheme),
                  ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Patient name and age
        Expanded(
          child: Text(
            _formatLabel(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        // Priority badge
        _PriorityBadge(
          priority: priority,
          isCompleted: isCompleted,
        ),
      ],
    );
  }

  String _formatLabel() {
    if (patientAge == null) return patientName;
    return '$patientName, Age $patientAge';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return '${parts[0].substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
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
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({
    required this.priority,
    this.isCompleted = false,
  });

  final SlaPriority priority;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = isCompleted ? ReferralStrings.badgeCompleted : _labelFor(priority);
    final color = isCompleted ? scheme.primary : _colorFor(priority, scheme);
    final bgColor = isCompleted 
        ? scheme.primary.withValues(alpha: 0.12)
        : _bgColorFor(priority, scheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
      ),
    );
  }

  String _labelFor(SlaPriority p) {
    switch (p) {
      case SlaPriority.critical:
        return ReferralStrings.badgeCritical;
      case SlaPriority.high:
        return ReferralStrings.badgeHigh;
      case SlaPriority.medium:
        return ReferralStrings.badgeMedium;
      case SlaPriority.low:
        return ReferralStrings.badgeLow;
    }
  }

  Color _colorFor(SlaPriority p, ColorScheme scheme) {
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

  Color _bgColorFor(SlaPriority p, ColorScheme scheme) {
    switch (p) {
      case SlaPriority.critical:
        return scheme.errorContainer;
      case SlaPriority.high:
        return scheme.tertiaryContainer;
      case SlaPriority.medium:
        return scheme.primaryContainer;
      case SlaPriority.low:
        return scheme.surfaceContainerHighest;
    }
  }
}
