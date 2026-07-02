import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Outcome of an NID-number capture attempt.
enum NidScanStatus {
  /// A valid NID number was extracted.
  success,

  /// The user backed out of the camera without taking a photo.
  cancelled,

  /// A photo was taken but no NID-shaped number could be read.
  notFound,

  /// The camera or OCR pipeline failed.
  error,
}

/// Result of a single NID scan. [nidNumber] is only set when [status] is
/// [NidScanStatus.success].
class NidScanResult {
  const NidScanResult(this.status, [this.nidNumber]);

  final NidScanStatus status;
  final String? nidNumber;
}

/// Captures a photo of a Bangladesh NID card and extracts the NID number.
///
/// On-device only (Google ML Kit Latin text recognition + camera) — no network,
/// so it works offline. We deliberately extract *only* the NID number: the
/// health worker confirms/edits it before it is saved, so partial OCR is safe.
class NidOcrService {
  NidOcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Bangladesh NID numbers are 10 (Smart NID), 13, or 17 digits.
  static const Set<int> _validNidLengths = {10, 13, 17};

  /// Opens the camera, OCRs the captured card, and returns the NID number.
  /// Opens the system camera app, OCRs the captured card, returns the NID
  /// number. Used by surfaces without a live in-app preview (e.g. Add Member).
  Future<NidScanResult> captureNidNumber() async {
    final XFile? photo;
    try {
      photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
    } on Exception catch (e) {
      debugPrint('NidOcrService: pickImage failed: $e');
      return const NidScanResult(NidScanStatus.error);
    }
    if (photo == null) return const NidScanResult(NidScanStatus.cancelled);
    return extractNidFromImage(photo.path);
  }

  /// Runs OCR on an already-captured image file (e.g. a frame from the in-app
  /// camera preview) and extracts the NID number.
  Future<NidScanResult> extractNidFromImage(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final nid = extractNidNumber(recognized.text);
      return nid == null
          ? const NidScanResult(NidScanStatus.notFound)
          : NidScanResult(NidScanStatus.success, nid);
    } on Exception catch (e) {
      debugPrint('NidOcrService: OCR failed: $e');
      return const NidScanResult(NidScanStatus.error);
    } finally {
      await recognizer.close();
    }
  }

  /// Pulls the most likely NID number out of raw OCR text.
  ///
  /// Scans each line for a digit run of a known NID length (ignoring the spaces
  /// OCR often inserts between digit groups) and prefers the longest match.
  /// Exposed for unit testing.
  static String? extractNidNumber(String rawText) {
    final candidates = <String>[];
    for (final line in rawText.split('\n')) {
      final digits = line.replaceAll(RegExp(r'\D'), '');
      if (_validNidLengths.contains(digits.length)) {
        candidates.add(digits);
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }
}
