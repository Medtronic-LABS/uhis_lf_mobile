import 'package:flutter/material.dart';

import '../../../core/widgets/skeleton.dart';

export '../../../core/widgets/skeleton.dart' show SkeletonBox, SkeletonAnimation;

/// Shimmer loading skeleton for referral list.
class ReferralLoadingSkeleton extends StatelessWidget {
  const ReferralLoadingSkeleton({
    super.key,
    this.itemCount = 5,
  });

  final int itemCount;

  @override
  Widget build(BuildContext context) => SkeletonAnimation(
        builder: (context, v) => ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          itemBuilder: (_, i) => _ReferralCardSkeleton(
            shimmerValue: v,
            delay: i * 0.15,
          ),
        ),
      );
}

class _ReferralCardSkeleton extends StatelessWidget {
  const _ReferralCardSkeleton({
    required this.shimmerValue,
    this.delay = 0,
  });

  final double shimmerValue;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = (shimmerValue + delay) % 1.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Identity strip
            Row(children: [
              SkeletonBox(shimmerValue: v, width: 120, height: 20),
              const SizedBox(width: 8),
              SkeletonBox(shimmerValue: v, width: 40, height: 20, delay: 0.04),
              const Spacer(),
              SkeletonBox(shimmerValue: v, width: 70, height: 24, borderRadius: 12, delay: 0.06),
            ]),
            const SizedBox(height: 14),

            // SLA banner
            SkeletonBox(shimmerValue: v, width: double.infinity, height: 56, borderRadius: 12, delay: 0.08),
            const SizedBox(height: 14),

            // Metadata columns
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SkeletonBox(shimmerValue: v, width: 80, height: 14, delay: 0.10),
                  const SizedBox(height: 6),
                  SkeletonBox(shimmerValue: v, width: 120, height: 14, delay: 0.12),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SkeletonBox(shimmerValue: v, width: 60, height: 14, delay: 0.10),
                  const SizedBox(height: 6),
                  SkeletonBox(shimmerValue: v, width: 100, height: 14, delay: 0.12),
                ]),
              ),
            ]),
            const SizedBox(height: 14),

            // Timeline row
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  5,
                  (i) => SkeletonBox(
                    shimmerValue: v,
                    width: 40,
                    height: 24,
                    borderRadius: 12,
                    delay: 0.10 + i * 0.05,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Action buttons
            Row(children: [
              SkeletonBox(shimmerValue: v, width: 80, height: 32, borderRadius: 8, delay: 0.14),
              const SizedBox(width: 8),
              SkeletonBox(shimmerValue: v, width: 80, height: 32, borderRadius: 8, delay: 0.16),
              const Spacer(),
              SkeletonBox(shimmerValue: v, width: 100, height: 32, borderRadius: 8, delay: 0.18),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Empty state widget for when no referrals match the current filter.
class ReferralEmptyState extends StatelessWidget {
  const ReferralEmptyState({
    super.key,
    this.title = 'No Referrals Found',
    this.subtitle,
    this.icon = Icons.folder_open_rounded,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: scheme.outline),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: textTheme.bodyMedium?.copyWith(color: scheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Offline indicator banner.
class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({
    super.key,
    this.pendingActions = 0,
    this.onRetry,
  });

  final int pendingActions;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You\'re Offline',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onErrorContainer,
                      ),
                ),
                if (pendingActions > 0)
                  Text(
                    '$pendingActions action${pendingActions == 1 ? '' : 's'} queued',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer.withValues(alpha: 0.8),
                        ),
                  ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// Syncing indicator banner.
class SyncingIndicator extends StatelessWidget {
  const SyncingIndicator({super.key, this.message = 'Syncing...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            message,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}
