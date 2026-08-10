import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/sync/offline_sync_service.dart';
import '../../core/sync/sync_progress.dart';

/// Slim in-app banner shown across every tab while a sync is running.
///
/// Until this existed, sync progress was visible only on `/sync`, which is
/// reachable from login, PIN setup and onboarding alone — so a connectivity-
/// triggered sync (measured at ~113 s against production) ran completely
/// invisibly while the SK worked the dashboard.
///
/// Owns its own subscription rather than having [BottomNavShell] watch the
/// service, so a progress event rebuilds 28 logical pixels instead of the whole
/// tab shell.
class SyncProgressStrip extends StatelessWidget {
  const SyncProgressStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.read<OfflineSyncService>();
    return StreamBuilder<SyncProgress>(
      stream: sync.progressStream,
      initialData: sync.progress,
      builder: (context, snapshot) {
        final progress = snapshot.data;
        // Nothing running, or finished/failed — the strip is for in-flight work
        // only; failures surface on /sync and in the notification.
        if (progress == null ||
            !sync.isRunning ||
            progress.isComplete ||
            progress.hasError) {
          return const SizedBox.shrink();
        }
        return _StripBody(progress: progress);
      },
    );
  }
}

class _StripBody extends StatelessWidget {
  const _StripBody({required this.progress});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final determinate = progress.itemsTotal > 0;
    final label = progress.entityName.isNotEmpty
        ? progress.entityName
        : SyncStrings.inProgressStrip;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: determinate
                      ? progress.itemsDone / progress.itemsTotal
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  determinate
                      ? SyncStrings.notificationProgress(
                          label,
                          progress.itemsDone,
                          progress.itemsTotal,
                        )
                      : label,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
