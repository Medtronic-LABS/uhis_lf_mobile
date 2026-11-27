import 'dart:io';

import 'epi_card_scanner.dart' show EpiCardScanner;

/// Why a card scan failed — the one vocabulary shared by the transport, every
/// programme's extraction repository and the scan screens, so the UI can show
/// a specific, localized message per cause instead of one generic error.
enum CardScanFailure {
  /// Photo is out of focus (set by the on-device quality check, not the server).
  blurry,

  /// No card could be located in the frame.
  cardNotIdentified,

  /// Card was found but holds no data for the requested visit.
  visitDataMissing,

  /// Card was found but its contents could not be read.
  unreadable,

  /// The visit the scan targets could not be determined before scanning.
  visitNotResolved,

  /// No connectivity (or the request timed out) — manual entry is the fallback.
  offline,

  /// Extraction service reachable but failed or answered unexpectedly.
  serviceUnavailable,
}

/// Refines a read failure with a blur check on the captured photo: a blurry
/// photo is the most actionable cause (retake), so it wins over the generic
/// "unreadable" / "no data" outcomes. Connectivity and service failures are
/// never blur-related and pass through untouched.
Future<CardScanFailure> refineScanFailure(
  File image,
  CardScanFailure failure,
) async {
  const refinable = {
    CardScanFailure.unreadable,
    CardScanFailure.visitDataMissing,
    CardScanFailure.cardNotIdentified,
  };
  if (!refinable.contains(failure)) return failure;
  final quality = await EpiCardScanner.assessCaptureQuality(image);
  return quality.isBlurry ? CardScanFailure.blurry : failure;
}
