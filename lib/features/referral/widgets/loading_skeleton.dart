import 'package:flutter/material.dart';

/// Shimmer loading skeleton for referral list.
class ReferralLoadingSkeleton extends StatefulWidget {
  const ReferralLoadingSkeleton({
    super.key,
    this.itemCount = 5,
  });

  final int itemCount;

  @override
  State<ReferralLoadingSkeleton> createState() => _ReferralLoadingSkeletonState();
}

class _ReferralLoadingSkeletonState extends State<ReferralLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.itemCount,
        itemBuilder: (context, index) => _SkeletonCard(
          shimmerValue: _animation.value,
          delay: index * 0.15,
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({
    required this.shimmerValue,
    this.delay = 0,
  });

  final double shimmerValue;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final adjustedValue = (shimmerValue + delay) % 1.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Identity strip skeleton
            Row(
              children: [
                _ShimmerBox(
                  width: 120,
                  height: 20,
                  value: adjustedValue,
                  scheme: scheme,
                ),
                const SizedBox(width: 8),
                _ShimmerBox(
                  width: 40,
                  height: 20,
                  value: adjustedValue,
                  scheme: scheme,
                ),
                const Spacer(),
                _ShimmerBox(
                  width: 70,
                  height: 24,
                  borderRadius: 12,
                  value: adjustedValue,
                  scheme: scheme,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // SLA banner skeleton
            _ShimmerBox(
              width: double.infinity,
              height: 56,
              borderRadius: 12,
              value: adjustedValue,
              scheme: scheme,
            ),
            const SizedBox(height: 14),

            // Metadata skeleton
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerBox(
                        width: 80,
                        height: 14,
                        value: adjustedValue,
                        scheme: scheme,
                      ),
                      const SizedBox(height: 6),
                      _ShimmerBox(
                        width: 120,
                        height: 14,
                        value: adjustedValue,
                        scheme: scheme,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerBox(
                        width: 60,
                        height: 14,
                        value: adjustedValue,
                        scheme: scheme,
                      ),
                      const SizedBox(height: 6),
                      _ShimmerBox(
                        width: 100,
                        height: 14,
                        value: adjustedValue,
                        scheme: scheme,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Timeline skeleton
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
                  (i) => _ShimmerBox(
                    width: 40,
                    height: 24,
                    borderRadius: 12,
                    value: (adjustedValue + i * 0.1) % 1.0,
                    scheme: scheme,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Action buttons skeleton
            Row(
              children: [
                _ShimmerBox(
                  width: 80,
                  height: 32,
                  borderRadius: 8,
                  value: adjustedValue,
                  scheme: scheme,
                ),
                const SizedBox(width: 8),
                _ShimmerBox(
                  width: 80,
                  height: 32,
                  borderRadius: 8,
                  value: adjustedValue,
                  scheme: scheme,
                ),
                const Spacer(),
                _ShimmerBox(
                  width: 100,
                  height: 32,
                  borderRadius: 8,
                  value: adjustedValue,
                  scheme: scheme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.value,
    required this.scheme,
    this.borderRadius = 6,
  });

  final double width;
  final double height;
  final double value;
  final ColorScheme scheme;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // Gradient that slides across the box
    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        scheme.surfaceContainerLow,
        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        scheme.surfaceContainerLow,
      ],
      stops: [
        (value - 0.3).clamp(0.0, 1.0),
        value,
        (value + 0.3).clamp(0.0, 1.0),
      ],
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
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
              child: Icon(
                icon,
                size: 64,
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.outline,
                ),
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

/// Offline indicator banner that shows when device is offline.
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
          Icon(
            Icons.cloud_off_rounded,
            size: 20,
            color: scheme.onErrorContainer,
          ),
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
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// Syncing indicator that shows during sync operations.
class SyncingIndicator extends StatelessWidget {
  const SyncingIndicator({
    super.key,
    this.message = 'Syncing...',
  });

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
