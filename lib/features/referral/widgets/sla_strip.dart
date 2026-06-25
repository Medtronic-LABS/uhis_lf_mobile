import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

/// Analogue of `SyncStrip` from the worklist — data-age + breach count.
class SlaStrip extends StatelessWidget {
  const SlaStrip({
    super.key,
    required this.lastSyncedAt,
    required this.breachCount,
    required this.escalationsPending,
    this.onSyncNow,
  });

  final DateTime? lastSyncedAt;
  final int breachCount;
  final int escalationsPending;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final relative = _relative(lastSyncedAt);
    final ageColor = _ageColor(lastSyncedAt, scheme);
    final breachColor = breachCount > 0 ? scheme.error : scheme.onSurfaceVariant;
    final slaStatus = breachCount > 0
        ? 'SLA status: $breachCount breach${breachCount == 1 ? '' : 'es'}'
        : 'SLA status: no breaches';
    return Semantics(
      label: onSyncNow != null ? '$slaStatus, tap to sync now' : slaStatus,
      button: onSyncNow != null,
      child: InkWell(
      onTap: onSyncNow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_done_outlined, size: 18, color: ageColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                ReferralStrings.syncedAgo(relative),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ageColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              ReferralStrings.breachesCount(breachCount),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: breachColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (escalationsPending > 0) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  ReferralStrings.escalationsCount(escalationsPending),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
            const Spacer(),
            if (onSyncNow != null)
              Icon(Icons.refresh, size: 20, color: scheme.primary),
          ],
        ),
      ),
      ),
    );
  }

  static String _relative(DateTime? at) {
    if (at == null) return 'never';
    final delta = DateTime.now().difference(at);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }

  Color _ageColor(DateTime? at, ColorScheme scheme) {
    if (at == null) return scheme.error;
    final delta = DateTime.now().difference(at);
    if (delta.inDays > 7) return scheme.error;
    if (delta.inDays > 1) return scheme.tertiary;
    return scheme.onSurfaceVariant;
  }
}
