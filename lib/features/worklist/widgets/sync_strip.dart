import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

class SyncStrip extends StatelessWidget {
  const SyncStrip({
    super.key,
    required this.lastSyncedAt,
    required this.syncing,
    required this.isOnline,
    required this.onSyncNow,
  });

  final DateTime? lastSyncedAt;
  final bool syncing;
  final bool isOnline;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _label(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          SizedBox(
            height: 28,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: syncing ? null : onSyncNow,
              icon: syncing
                  ? const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5))
                  : const Icon(Icons.refresh, size: 14),
              label: Text(
                syncing ? WorklistStrings.syncing : WorklistStrings.syncNow,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _label() {
    final prefix = isOnline ? '' : '${WorklistStrings.offlineSuffix} · ';
    final t = lastSyncedAt;
    if (t == null) return '$prefix${WorklistStrings.emptyBody}';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '$prefix${WorklistStrings.syncedJustNow}';
    if (diff.inMinutes < 60) {
      return '$prefix${WorklistStrings.syncedMinutes(diff.inMinutes)}';
    }
    if (diff.inHours < 24) {
      return '$prefix${WorklistStrings.syncedHours(diff.inHours)}';
    }
    return '$prefix${WorklistStrings.syncedDays(diff.inDays)}';
  }
}
