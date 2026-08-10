import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/sync/offline_sync_service.dart';
import '../../core/sync/sync_progress.dart';
import '../../core/theme/app_theme.dart';

/// Slim banner shown directly above the bottom navigation while a sync runs.
///
/// Until this existed, sync progress was visible only on `/sync`, which is
/// reachable from login, PIN setup and onboarding alone — so a connectivity-
/// triggered sync (measured at ~113 s against production) ran completely
/// invisibly while the SK worked the dashboard.
///
/// Sits with the nav rather than under the app bar, matching the referral
/// alert banner's treatment so the SK reads both as the same class of ambient
/// status.
///
/// Owns its own subscription rather than having [BottomNavShell] watch the
/// service, so a progress event rebuilds this bar instead of the whole tab
/// shell.
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

  /// What the SK actually needs to read.
  ///
  /// Deliberately built from the *step label* ("Downloading patients"), not
  /// `entityName` — that carries a bare noun, which rendered as just
  /// "রোগী"/"patients" and told nobody anything. Counts are appended only when
  /// the total is known.
  String _message() {
    // Retrying is the more useful thing to say while it is happening.
    if (progress.isRetrying) {
      return SyncStrings.retryingAttempt(
        progress.retryAttempt!,
        progress.retryMaxAttempts!,
      );
    }
    // The persist phase is the more specific answer to "what is it doing" —
    // "Saving members 2400/3566" rather than "Processing data".
    final label = progress.persistPhase?.label ?? progress.currentStep.label;
    if (label.isEmpty) return SyncStrings.inProgressStrip;
    if (progress.itemsTotal > 0) {
      return SyncStrings.stripProgress(
        label,
        progress.itemsDone,
        progress.itemsTotal,
      );
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final determinate = progress.itemsTotal > 0;
    final background = Theme.of(context).brightness == Brightness.dark
        ? tokens.brandNavyDark
        : tokens.brandNavy;

    return Semantics(
      liveRegion: true,
      label: _message(),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          boxShadow: [
            BoxShadow(
              color: background.withValues(alpha: 0.25),
              offset: const Offset(0, -2),
              blurRadius: 6,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  value: determinate
                      ? progress.itemsDone / progress.itemsTotal
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _message(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
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
