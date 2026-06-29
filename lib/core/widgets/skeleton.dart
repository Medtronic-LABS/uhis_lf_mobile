import 'package:flutter/material.dart';

import '../../app/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Primitives
// ─────────────────────────────────────────────────────────────────────────────

/// Single shimmer rectangle — the building block for all skeleton loaders.
/// [shimmerValue] drives the highlight sweep (0.0–1.0).
/// [delay] offsets the sweep phase so adjacent boxes don't pulse in lock-step.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.shimmerValue,
    required this.height,
    this.width,
    this.borderRadius = 6,
    this.delay = 0,
  });

  final double shimmerValue;
  final double height;
  final double? width;
  final double borderRadius;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = (shimmerValue + delay) % 1.0;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            scheme.surfaceContainerLow,
            scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            scheme.surfaceContainerLow,
          ],
          stops: [
            (v - 0.3).clamp(0.0, 1.0),
            v,
            (v + 0.3).clamp(0.0, 1.0),
          ],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Runs a single [AnimationController] and exposes the shimmer value to [builder].
/// Wrap all skeleton composites for a given screen in one [SkeletonAnimation] to
/// share a single ticker rather than running one per composite.
class SkeletonAnimation extends StatefulWidget {
  const SkeletonAnimation({super.key, required this.builder});

  final Widget Function(BuildContext context, double shimmerValue) builder;

  @override
  State<SkeletonAnimation> createState() => _SkeletonAnimationState();
}

class _SkeletonAnimationState extends State<SkeletonAnimation>
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _animation,
        builder: (context, _) => widget.builder(context, _animation.value),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen composites
// ─────────────────────────────────────────────────────────────────────────────

/// Skeleton list matching [MissionQueueCard] shape.
/// Used by DashboardScreen and WorklistScreen.
class SkeletonPatientCardList extends StatelessWidget {
  const SkeletonPatientCardList({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) => SkeletonAnimation(
        builder: (context, v) => ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: count,
          itemBuilder: (_, i) => _PatientCardSkeleton(
            shimmerValue: v,
            delay: i * 0.12,
          ),
        ),
      );
}

class _PatientCardSkeleton extends StatelessWidget {
  const _PatientCardSkeleton({
    required this.shimmerValue,
    this.delay = 0,
  });

  final double shimmerValue;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>();
    final scheme = Theme.of(context).colorScheme;
    final cardBg = tokens?.cardSurface ?? scheme.surface;
    final v = (shimmerValue + delay) % 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: scheme.surfaceContainerHighest,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              SkeletonBox(shimmerValue: v, width: 44, height: 44, borderRadius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      SkeletonBox(shimmerValue: v, width: 130, height: 14, delay: 0.05),
                      const SizedBox(width: 8),
                      SkeletonBox(shimmerValue: v, width: 52, height: 18, borderRadius: 4, delay: 0.08),
                    ]),
                    const SizedBox(height: 6),
                    SkeletonBox(shimmerValue: v, width: 90, height: 18, borderRadius: 5, delay: 0.10),
                    const SizedBox(height: 6),
                    SkeletonBox(shimmerValue: v, width: 160, height: 11, delay: 0.12),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SkeletonBox(shimmerValue: v, width: 52, height: 32, borderRadius: 20, delay: 0.06),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton matching [PatientContextScreen] — header card + vitals row + assessments.
class SkeletonPatientDetail extends StatelessWidget {
  const SkeletonPatientDetail({super.key});

  @override
  Widget build(BuildContext context) => SkeletonAnimation(
        builder: (context, v) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient header
              _SkeletonCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(shimmerValue: v, width: 56, height: 56, borderRadius: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(shimmerValue: v, width: 160, height: 20, delay: 0.05),
                          const SizedBox(height: 8),
                          Row(children: [
                            SkeletonBox(shimmerValue: v, width: 64, height: 22, borderRadius: 11, delay: 0.08),
                            const SizedBox(width: 8),
                            SkeletonBox(shimmerValue: v, width: 64, height: 22, borderRadius: 11, delay: 0.10),
                          ]),
                          const SizedBox(height: 8),
                          SkeletonBox(shimmerValue: v, width: 100, height: 13, delay: 0.12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Vitals row
              _SkeletonCard(
                child: Row(
                  children: List.generate(3, (i) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(shimmerValue: v, width: 40, height: 11, delay: i * 0.06),
                            const SizedBox(height: 6),
                            SkeletonBox(shimmerValue: v, width: 60, height: 22, delay: i * 0.06 + 0.05),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 12),
              // Assessment section
              _SkeletonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      SkeletonBox(shimmerValue: v, width: 120, height: 16),
                      const Spacer(),
                      SkeletonBox(shimmerValue: v, width: 50, height: 13, delay: 0.05),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    ...List.generate(3, (i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(children: [
                        SkeletonBox(shimmerValue: v, width: 36, height: 36, borderRadius: 8, delay: i * 0.08),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(shimmerValue: v, width: 64, height: 18, borderRadius: 4, delay: i * 0.08 + 0.05),
                              const SizedBox(height: 6),
                              SkeletonBox(shimmerValue: v, width: 100, height: 12, delay: i * 0.08 + 0.08),
                            ],
                          ),
                        ),
                        SkeletonBox(shimmerValue: v, width: 16, height: 16, borderRadius: 8, delay: i * 0.08 + 0.10),
                      ]),
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// Skeleton matching household / member list tiles.
class SkeletonHouseholdList extends StatelessWidget {
  const SkeletonHouseholdList({super.key, this.count = 8});

  final int count;

  @override
  Widget build(BuildContext context) => SkeletonAnimation(
        builder: (context, v) => ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: count,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 70),
          itemBuilder: (_, i) {
            final d = (i * 0.10) % 1.0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                SkeletonBox(shimmerValue: (v + d) % 1.0, width: 42, height: 42, borderRadius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(shimmerValue: (v + d + 0.05) % 1.0, width: 140, height: 15),
                      const SizedBox(height: 6),
                      SkeletonBox(shimmerValue: (v + d + 0.10) % 1.0, width: 80, height: 12),
                    ],
                  ),
                ),
                SkeletonBox(shimmerValue: (v + d + 0.08) % 1.0, width: 16, height: 16, borderRadius: 8),
              ]),
            );
          },
        ),
      );
}

/// Skeleton for [SymptomPickerScreen] — AI briefing cards + search bar + chip rows.
class SkeletonSymptomPicker extends StatelessWidget {
  const SkeletonSymptomPicker({super.key});

  @override
  Widget build(BuildContext context) => SkeletonAnimation(
        builder: (context, v) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI briefing card stubs (collapsed shape)
              ...List.generate(3, (i) {
                final d = i * 0.10;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SkeletonCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      SkeletonBox(shimmerValue: (v + d) % 1.0, width: 20, height: 20, borderRadius: 10),
                      const SizedBox(width: 12),
                      SkeletonBox(shimmerValue: (v + d + 0.05) % 1.0, width: 140, height: 14),
                      const Spacer(),
                      SkeletonBox(shimmerValue: (v + d + 0.08) % 1.0, width: 16, height: 16, borderRadius: 8),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 8),
              // Search / custom-symptom bar
              SkeletonBox(shimmerValue: v, width: double.infinity, height: 48, borderRadius: 12, delay: 0.15),
              const SizedBox(height: 16),
              // Symptom chips — 3 rows of varying widths
              ...List.generate(3, (row) {
                final widths = row == 0
                    ? [80.0, 60.0, 100.0, 70.0]
                    : row == 1
                        ? [90.0, 75.0, 55.0]
                        : [65.0, 95.0, 70.0, 80.0, 60.0];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (var (idx, w) in widths.indexed)
                        SkeletonBox(
                          shimmerValue: (v + row * 0.10 + idx * 0.05) % 1.0,
                          width: w,
                          height: 32,
                          borderRadius: 16,
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      );
}
