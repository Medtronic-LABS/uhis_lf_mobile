import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../guideline_visual_repository.dart';

/// Draws one guideline picture — the embedded raster when available,
/// otherwise the SVG — scaled to fit its box.
class GuidelineImageView extends StatelessWidget {
  const GuidelineImageView({super.key, required this.data, this.cacheWidth});

  final GuidelineImageData data;

  /// Decode width in physical pixels, so a small tile doesn't keep a full
  /// 1024 px bitmap in memory. Null decodes at full size (the viewer).
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final raster = data.raster;
    if (raster != null) {
      return Image.memory(
        raster,
        fit: BoxFit.contain,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return SvgPicture.string(data.svg!, fit: BoxFit.contain);
  }
}
