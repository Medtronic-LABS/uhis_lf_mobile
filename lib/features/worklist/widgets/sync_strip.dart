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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _label(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          TextButton.icon(
            onPressed: syncing ? null : onSyncNow,
            icon: syncing
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 16),
            label: Text(syncing
                ? WorklistStrings.syncing
                : WorklistStrings.syncNow),
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
