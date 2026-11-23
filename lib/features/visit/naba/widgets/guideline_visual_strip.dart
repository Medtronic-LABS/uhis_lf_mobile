import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../guideline_visual_repository.dart';
import '../guideline_visual_selector.dart';
import 'guideline_image_view.dart';
import 'guideline_visual_viewer.dart';

/// Row of guideline picture tiles shown on Step 3 above the AI Counselling
/// Guide. Each tile is one picture (no caption); tapping opens the full-size
/// viewer, which shows the picture with its full caption. Pictures that fail to load are dropped
/// and the row shrinks to what is left; with none left it takes no space.
class GuidelineVisualStrip extends StatefulWidget {
  const GuidelineVisualStrip({super.key, required this.visuals});

  final List<SelectedGuidelineVisual> visuals;

  @override
  State<GuidelineVisualStrip> createState() => _GuidelineVisualStripState();
}

typedef _LoadedVisual = ({
  SelectedGuidelineVisual visual,
  GuidelineImageData data,
});

class _GuidelineVisualStripState extends State<GuidelineVisualStrip> {
  late Future<List<_LoadedVisual>> _loaded;

  @override
  void initState() {
    super.initState();
    _loaded = _load();
  }

  @override
  void didUpdateWidget(GuidelineVisualStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePointers(oldWidget.visuals, widget.visuals)) _loaded = _load();
  }

  static bool _samePointers(
    List<SelectedGuidelineVisual> a,
    List<SelectedGuidelineVisual> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].image.sha256 != b[i].image.sha256) return false;
    }
    return true;
  }

  Future<List<_LoadedVisual>> _load() async {
    // Nothing selected (e.g. rule-based fallback): no repository needed.
    if (widget.visuals.isEmpty) return const [];
    final repo = context.read<GuidelineVisualRepository>();
    final results = await Future.wait(
      widget.visuals.map((v) => repo.load(v.image)),
    );
    return [
      for (var i = 0; i < widget.visuals.length; i++)
        if (results[i] case final data?)
          (visual: widget.visuals[i], data: data),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visuals.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<_LoadedVisual>>(
      future: _loaded,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _spaced(
            _row(
              count: widget.visuals.length,
              tile: (_, _) => const _TileSkeleton(),
            ),
          );
        }
        final loaded = snapshot.data ?? const <_LoadedVisual>[];
        if (loaded.isEmpty) return const SizedBox.shrink();
        return _spaced(
          _row(
            count: loaded.length,
            tile: (i, width) => _GuidelineVisualTile(
              caption: loaded[i].visual.caption,
              data: loaded[i].data,
              cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              onTap: () => showGuidelineVisualViewer(
                context,
                items: [
                  for (final l in loaded)
                    (image: l.data, caption: l.visual.caption),
                ],
                initialIndex: i,
              ),
            ),
          ),
        );
      },
    );
  }

  /// The strip owns its bottom gap so it disappears with the strip.
  static Widget _spaced(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
    child: child,
  );

  /// Tiles keep a fixed one-third width whatever the count, so one or two
  /// pictures don't blow up to full width; the row is centred.
  Widget _row({
    required int count,
    required Widget Function(int index, double width) tile,
  }) {
    const gap = AppSpacing.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth -
                gap * (GuidelineVisualSelector.maxVisuals - 1)) /
            GuidelineVisualSelector.maxVisuals;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              SizedBox(width: width, child: tile(i, width)),
            ],
          ],
        );
      },
    );
  }
}

/// Width ÷ height of a preview tile. Wider than square so the (square)
/// picture draws at ~80% of the tile width — the full-size view, with its
/// caption, is one tap away in the viewer.
const double _previewAspectRatio = 1.25;

/// Picture-only preview tile. The caption is not drawn here (it appears in
/// the viewer) but is kept as the screen-reader label.
class _GuidelineVisualTile extends StatelessWidget {
  const _GuidelineVisualTile({
    required this.caption,
    required this.data,
    required this.cacheWidth,
    required this.onTap,
  });

  final String caption;
  final GuidelineImageData data;
  final int cacheWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: NabaVisualStrings.openPicture(caption),
      excludeSemantics: true,
      child: Material(
        color: AppColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.patRow),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: _previewAspectRatio,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: GuidelineImageView(
                      data: data,
                      cacheWidth: cacheWidth,
                    ),
                  ),
                ),
                const Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: _ExpandBadge(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandBadge extends StatelessWidget {
  const _ExpandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: AppColors.textMuted,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.open_in_full_rounded,
        size: 12,
        color: AppColors.textOnNavy,
      ),
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _previewAspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.progressTrack,
          borderRadius: BorderRadius.circular(AppRadius.patRow),
        ),
      ),
    );
  }
}
