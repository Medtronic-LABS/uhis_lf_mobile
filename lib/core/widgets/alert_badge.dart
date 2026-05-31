import 'package:flutter/material.dart';

/// A badge widget that displays an alert with a warning icon and reason text.
/// Used in visit rows to show why a patient needs attention.
class AlertBadge extends StatelessWidget {
  const AlertBadge({
    super.key,
    required this.reason,
    this.isUrgent = false,
    this.maxLines = 1,
    this.compact = false,
  });

  /// The alert reason text to display.
  final String reason;

  /// Whether this is an urgent alert (uses error colors).
  final bool isUrgent;

  /// Maximum lines for the reason text.
  final int maxLines;

  /// Use compact styling (smaller padding and font).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isUrgent ? scheme.error : scheme.primary;
    final bgColor = isUrgent
        ? scheme.errorContainer.withValues(alpha: 0.5)
        : scheme.primaryContainer.withValues(alpha: 0.5);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(compact ? 6 : 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUrgent ? Icons.warning_amber_rounded : Icons.info_outline,
            size: compact ? 14 : 18,
            color: color,
          ),
          SizedBox(width: compact ? 4 : 8),
          Flexible(
            child: Text(
              reason,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An inline alert indicator (just icon + text, no background).
class AlertIndicator extends StatelessWidget {
  const AlertIndicator({
    super.key,
    required this.reason,
    this.isUrgent = false,
  });

  final String reason;
  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isUrgent ? scheme.error : scheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            reason,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
