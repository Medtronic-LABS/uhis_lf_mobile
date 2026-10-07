import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'card_extraction_transport.dart' show CardBoundingBox;

/// Resolves a [File] image's natural pixel dimensions — needed to map the
/// backend's normalized bounding boxes onto screen coordinates once
/// `Image.file` has laid it out with `BoxFit.contain` (which letterboxes
/// unless the photo's aspect ratio exactly matches the available space).
Future<Size> resolveImageSize(File file) {
  final completer = Completer<Size>();
  final provider = FileImage(file);
  late ImageStreamListener listener;
  final stream = provider.resolve(const ImageConfiguration());
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(
          Size(info.image.width.toDouble(), info.image.height.toDouble()),
        );
      }
      stream.removeListener(listener);
    },
    onError: (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// Maps a normalized (0-1) box onto the actual on-screen rect of a
/// `BoxFit.contain`-laid-out image, given the container size it's rendered
/// into and the image's natural pixel size. Shared by every scan screen
/// that draws a [CardBoundingBox] highlight (ANC's located visit column,
/// EPI's not-given vaccine rows) — the contain-fit letterboxing math is
/// identical regardless of what the box represents.
Rect containFitRect(Size container, Size imageSize, CardBoundingBox box) {
  final scale =
      (container.width / imageSize.width < container.height / imageSize.height)
          ? container.width / imageSize.width
          : container.height / imageSize.height;
  final displayedW = imageSize.width * scale;
  final displayedH = imageSize.height * scale;
  final offsetX = (container.width - displayedW) / 2;
  final offsetY = (container.height - displayedH) / 2;
  return Rect.fromLTRB(
    offsetX + box.xMin * displayedW,
    offsetY + box.yMin * displayedH,
    offsetX + box.xMax * displayedW,
    offsetY + box.yMax * displayedH,
  );
}

/// Draws a translucent highlight rect over [box]'s located region once the
/// image's natural size is known. One [CardBoundingBox] per call — for
/// multiple boxes (e.g. EPI's several not-given vaccine rows), use one
/// [CardHighlightOverlay] per box, or wrap several in the same `FutureBuilder`
/// via [CardHighlightOverlays] below to resolve the image size only once.
class CardHighlightOverlay extends StatelessWidget {
  const CardHighlightOverlay({
    super.key,
    required this.image,
    required this.box,
    this.color = const Color(0xFF34D399),
  });

  final File image;
  final CardBoundingBox box;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CardHighlightOverlays(image: image, boxes: [box], color: color);
  }
}

/// Draws one highlight rect per box in [boxes], resolving the image's
/// natural size only once for all of them.
class CardHighlightOverlays extends StatelessWidget {
  const CardHighlightOverlays({
    super.key,
    required this.image,
    required this.boxes,
    this.color = const Color(0xFF34D399),
  });

  final File image;
  final List<CardBoundingBox> boxes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (boxes.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<Size>(
      future: resolveImageSize(image),
      builder: (context, snapshot) {
        final imgSize = snapshot.data;
        if (imgSize == null) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            // A fresh inner Stack — `Positioned` only works as a direct
            // Stack child, and the outer screen Stack is too far up the
            // tree (through FutureBuilder/LayoutBuilder, neither of which
            // is a Stack) to apply to directly.
            return Stack(
              children: [
                for (final box in boxes)
                  Positioned.fromRect(
                    rect: containFitRect(constraints.biggest, imgSize, box),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        border: Border.all(color: color, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
