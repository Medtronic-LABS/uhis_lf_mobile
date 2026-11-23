import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../guideline_visual_repository.dart';
import 'guideline_image_view.dart';

/// One page of the viewer: the picture and its full caption.
typedef GuidelineViewerItem = ({GuidelineImageData image, String caption});

/// Opens the full-size picture viewer at [initialIndex], each picture with its
/// full caption below. Swiping (or the arrows) moves between [items].
Future<void> showGuidelineVisualViewer(
  BuildContext context, {
  required List<GuidelineViewerItem> items,
  int initialIndex = 0,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        GuidelineVisualViewer(items: items, initialIndex: initialIndex),
  );
}

class GuidelineVisualViewer extends StatefulWidget {
  const GuidelineVisualViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  final List<GuidelineViewerItem> items;
  final int initialIndex;

  @override
  State<GuidelineVisualViewer> createState() => _GuidelineVisualViewerState();
}

class _GuidelineVisualViewerState extends State<GuidelineVisualViewer> {
  late final PageController _pages;
  late int _index;

  bool get _paged => widget.items.length > 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) => _pages.animateToPage(
    index,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      insetPadding: const EdgeInsets.all(AppSpacing.xxxl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          // Flexible: on a short (landscape) screen the square shrinks to
          // the height left after the header and footer instead of overflowing.
          Flexible(
            child: AspectRatio(
              aspectRatio: 1,
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.items.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: GuidelineImageView(data: widget.items[i].image),
                  ),
                ),
              ),
            ),
          ),
          _caption(),
          if (_paged) _footer() else const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.xs,
        AppSpacing.xs,
        0,
      ),
      child: Row(
        children: [
          if (_paged)
            Text(
              NabaVisualStrings.pageOf(_index + 1, widget.items.length),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: NabaVisualStrings.close,
            icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Full caption of the current page — never truncated.
  Widget _caption() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.h5xl,
        AppSpacing.xl,
        AppSpacing.h5xl,
        0,
      ),
      child: Text(
        widget.items[_index].caption,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: AppColors.textStrong,
        ),
      ),
    );
  }

  Widget _footer() {
    final last = widget.items.length - 1;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          _arrow(
            icon: Icons.chevron_left_rounded,
            tooltip: NabaVisualStrings.previous,
            onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i <= last; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppColors.aiPurple
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
          _arrow(
            icon: Icons.chevron_right_rounded,
            tooltip: NabaVisualStrings.next,
            onPressed: _index < last ? () => _goTo(_index + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _arrow({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton.outlined(
      tooltip: tooltip,
      icon: Icon(icon),
      color: AppColors.textPrimary,
      onPressed: onPressed,
    );
  }
}
