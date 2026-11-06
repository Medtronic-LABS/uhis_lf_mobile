import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import 'epi_card_scanner.dart';

/// Checks a just-captured card photo for blur/glare before an extraction call
/// is spent on it. Shared by every programme's scan screen (EPI, ANC, NCD).
///
/// Returns null when the SK chooses "Retake photo" (or the screen unmounted
/// mid-check); otherwise the assessed [CardCaptureQuality] — `hasIssue` is
/// true only when the SK proceeded past a warning via "Use anyway".
Future<CardCaptureQuality?> confirmCaptureQualityOrRetake(
  BuildContext context,
  File image,
) async {
  final quality = await EpiCardScanner.assessCaptureQuality(image);
  if (!quality.hasIssue) return quality;
  if (!context.mounted) return null;
  final message = quality.isBlurry && quality.hasGlare
      ? EpiStrings.scanQualityBothMessage
      : quality.isBlurry
      ? EpiStrings.scanQualityBlurryMessage
      : EpiStrings.scanQualityGlareMessage;
  final useAnyway = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(EpiStrings.scanQualityWarningTitle),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(EpiStrings.scanQualityRetake),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(EpiStrings.scanQualityUseAnyway),
        ),
      ],
    ),
  );
  return useAnyway == true ? quality : null;
}
