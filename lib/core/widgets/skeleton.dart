import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    // Shimmer tints sit between the canvas + card-surface palette so the
    // skeleton blends with the Leapfrog theme rather than the Material 3
    // default scheme (which leans grey-pink). Matches the visual weight of
    // the real mission card the skeleton stands in for.
    final tokens = Theme.of(context).extension<LeapfrogColors>();
    final base = tokens?.cardSurfaceMuted ?? AppColors.cardSurfaceMuted;
    final highlight = AppColors.border;
    final v = (shimmerValue + delay) % 1.0;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            base,
            highlight,
            base,
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
    final tokens = Theme.of(context).extension<LeapfrogColors>();
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: tokens?.cardSurface ?? AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
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
    // Mirror MissionQueueCard exactly so the swap from skeleton → real card
    // is visually seamless: same surface, same 4px grey left border
    // (#E5E7EB — never red, since the band is unknown during load), same
    // 12px corner radius, same 14/12 padding, same avatar + pill geometry.
    final tokens = Theme.of(context).extension<LeapfrogColors>();
    final cardBg = tokens?.cardSurface ?? AppColors.cardSurface;
    final v = (shimmerValue + delay) % 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border(
              left: BorderSide(color: AppColors.border, width: 4),
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

/// Skeleton matching [PatientContextScreen] — purple header + canvas body
/// + the three sections (Gemini summary banner, vitals strip, assessments).
///
/// Pass [name] when it is already known at navigation time so the header
/// shows the real patient name + initials instead of a shimmer box. Avoids
/// the all-white loader the SK previously saw when tapping a worklist card.
class SkeletonPatientDetail extends StatelessWidget {
  const SkeletonPatientDetail({super.key, this.name});

  /// Pre-known patient name — shown as real text; skeletons the rest.
  final String? name;

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>();
    final headerColor = tokens?.aiPurpleDark ?? AppColors.aiPurpleDark;
    final canvas = tokens?.canvas ?? AppColors.canvas;
    return Container(
      color: canvas,
      child: SkeletonAnimation(
        builder: (context, v) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Purple header (matches _PatientDetailHeader) ─────────────
            Container(
              color: headerColor,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const IconButton(
                        icon: Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: null,
                        tooltip: 'Back',
                      ),
                      const Expanded(
                        child: Text(
                          'Back to worklist',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const IconButton(
                        icon: Icon(Icons.cloud_download_outlined,
                            color: Colors.white),
                        onPressed: null,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.18),
                          child: Text(
                            name == null ? '?' : _initials(name!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (name != null)
                                Text(
                                  name!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              else
                                _PaleBar(
                                    shimmerValue: v,
                                    width: 160,
                                    height: 20,
                                    delay: 0.05),
                              const SizedBox(height: 6),
                              _PaleBar(
                                  shimmerValue: v,
                                  width: 110,
                                  height: 12,
                                  delay: 0.10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Canvas body — mirrors the real ListView ──────────────────
            Expanded(
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
                children: [
                  // 1) Gemini summary banner (light card + text lines).
                  _SkeletonCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          SkeletonBox(
                              shimmerValue: v,
                              width: 22,
                              height: 22,
                              borderRadius: 6),
                          const SizedBox(width: 8),
                          SkeletonBox(
                              shimmerValue: v,
                              width: 120,
                              height: 14,
                              delay: 0.04),
                        ]),
                        const SizedBox(height: 10),
                        SkeletonBox(
                            shimmerValue: v,
                            width: double.infinity,
                            height: 11,
                            delay: 0.08),
                        const SizedBox(height: 6),
                        SkeletonBox(
                            shimmerValue: v,
                            width: 240,
                            height: 11,
                            delay: 0.12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 2) Vitals strip.
                  _SkeletonCard(
                    child: Row(
                      children: List.generate(3, (i) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(
                                    shimmerValue: v,
                                    width: 40,
                                    height: 11,
                                    delay: i * 0.06),
                                const SizedBox(height: 6),
                                SkeletonBox(
                                    shimmerValue: v,
                                    width: 60,
                                    height: 22,
                                    delay: i * 0.06 + 0.05),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 3) Assessments section.
                  _SkeletonCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          SkeletonBox(
                              shimmerValue: v, width: 120, height: 16),
                          const Spacer(),
                          SkeletonBox(
                              shimmerValue: v,
                              width: 50,
                              height: 13,
                              delay: 0.05),
                        ]),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        ...List.generate(
                            3,
                            (i) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 7),
                                  child: Row(children: [
                                    SkeletonBox(
                                        shimmerValue: v,
                                        width: 36,
                                        height: 36,
                                        borderRadius: 8,
                                        delay: i * 0.08),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SkeletonBox(
                                              shimmerValue: v,
                                              width: 64,
                                              height: 18,
                                              borderRadius: 4,
                                              delay: i * 0.08 + 0.05),
                                          const SizedBox(height: 6),
                                          SkeletonBox(
                                              shimmerValue: v,
                                              width: 100,
                                              height: 12,
                                              delay: i * 0.08 + 0.08),
                                        ],
                                      ),
                                    ),
                                    SkeletonBox(
                                        shimmerValue: v,
                                        width: 16,
                                        height: 16,
                                        borderRadius: 8,
                                        delay: i * 0.08 + 0.10),
                                  ]),
                                )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White-tinted shimmer bar for use INSIDE the purple header where the
/// default canvas-tinted [SkeletonBox] would look too dark.
class _PaleBar extends StatelessWidget {
  const _PaleBar({
    required this.shimmerValue,
    required this.width,
    required this.height,
    this.delay = 0,
  });

  final double shimmerValue;
  final double width;
  final double height;
  final double delay;
  static const double borderRadius = 4;

  @override
  Widget build(BuildContext context) {
    final v = (shimmerValue + delay) % 1.0;
    final base = Colors.white.withValues(alpha: 0.16);
    final highlight = Colors.white.withValues(alpha: 0.32);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, highlight, base],
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
