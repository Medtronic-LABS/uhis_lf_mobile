import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Outcome of an NID capture attempt.
enum NidScanStatus {
  /// At least the NID number was extracted.
  success,

  /// The user backed out of the camera without taking a photo.
  cancelled,

  /// A photo was taken but no NID-shaped number could be read.
  notFound,

  /// The camera or OCR pipeline failed.
  error,

  /// The SK chose to register the member without scanning an NID card.
  /// Caller should open the form with blank NID fields for manual entry.
  skipped,
}

/// Fields read from a Bangladesh NID card via on-device Latin OCR.
///
/// Only Latin-script fields are populated. The card also prints পিতা (father)
/// and মাতা (mother) names in **Bengali only**, which the Latin recognizer
/// cannot read — those stay null and must be entered manually.
class NidCardData {
  const NidCardData({this.nidNumber, this.name, this.dateOfBirth});

  /// NID number, digits only (10 / 13 / 17).
  final String? nidNumber;

  /// English name as printed under the "Name" label.
  final String? name;

  /// Date of birth, ISO `yyyy-MM-dd` when parseable, else the raw match.
  final String? dateOfBirth;
}

/// Result of a single NID scan. [data] is set when [status] is
/// [NidScanStatus.success].
class NidScanResult {
  const NidScanResult(this.status, [this.data]);

  final NidScanStatus status;
  final NidCardData? data;
}

/// Captures a photo of a Bangladesh NID card and extracts the Latin-script
/// fields (NID number, English name, date of birth).
///
/// On-device only (Google ML Kit Latin text recognition) — no network, so it
/// works offline. Every field is a proposal the health worker confirms before
/// it is saved, so partial/imperfect OCR is safe.
class NidOcrService {
  NidOcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Bangladesh NID numbers are 10 (Smart NID), 13, or 17 digits.
  static const Set<int> _validNidLengths = {10, 13, 17};

  static const Map<String, int> _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Opens the system camera app, OCRs the captured card, returns the fields.
  /// Used by surfaces without a live in-app preview (e.g. Add Member).
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

  /// Scans [imagePath] for any barcode / QR code. Returns the raw decoded
  /// value, or null when no code is found or the scan fails. Checks QR, Code
  /// 128 and EAN-13 — the formats most likely on health cards and patient
  /// wristbands in this context.
  Future<String?> extractQrCode(String imagePath) async {
    final scanner = BarcodeScanner(formats: [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.ean13,
    ]);
    try {
      final barcodes =
          await scanner.processImage(InputImage.fromFilePath(imagePath));
      return barcodes.isEmpty ? null : barcodes.first.rawValue;
    } on Exception catch (e) {
      debugPrint('NidOcrService: barcode scan failed: $e');
      return null;
    } finally {
      await scanner.close();
    }
  }

  /// Runs OCR on an already-captured image file (e.g. a frame from the in-app
  /// camera preview) and extracts the NID card fields.
  Future<NidScanResult> extractNidFromImage(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final text = recognized.text;
      final nid = extractNidNumber(text);
      if (nid == null) return const NidScanResult(NidScanStatus.notFound);
      return NidScanResult(
        NidScanStatus.success,
        NidCardData(
          nidNumber: nid,
          name: extractName(text),
          dateOfBirth: extractDateOfBirth(text),
        ),
      );
    } on Exception catch (e) {
      debugPrint('NidOcrService: OCR failed: $e');
      return const NidScanResult(NidScanStatus.error);
    } finally {
      await recognizer.close();
    }
  }

  /// Pulls the most likely NID number out of raw OCR text: the longest digit
  /// run of a valid NID length, tolerating spaces OCR inserts between groups.
  /// Exposed for unit testing.
  static String? extractNidNumber(String rawText) {
    final candidates = <String>[];
    for (final line in rawText.split('\n')) {
      final digits = line.replaceAll(RegExp(r'\D'), '');
      if (_validNidLengths.contains(digits.length)) candidates.add(digits);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }

  /// Extracts the English name printed under the "Name" label. The value is on
  /// the line after the label (Bengali নাম line sits above it). Exposed for
  /// unit testing.
  static String? extractName(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      // The standalone "Name" label — not the "National ID Card" header.
      if ((lower == 'name' || lower == 'name:') &&
          i + 1 < lines.length &&
          _looksLikeName(lines[i + 1])) {
        return _titleCase(lines[i + 1]);
      }
      // Inline form: "Name ROMANA RAHMAN".
      final inline = RegExp(r'^name[:\s]+(.+)$', caseSensitive: false)
          .firstMatch(lines[i]);
      if (inline != null && _looksLikeName(inline.group(1)!)) {
        return _titleCase(inline.group(1)!.trim());
      }
    }
    return null;
  }

  /// Extracts the date of birth (e.g. "25 Nov 1983") as ISO `yyyy-MM-dd`.
  /// Exposed for unit testing.
  static String? extractDateOfBirth(String rawText) {
    final match = RegExp(r'(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})')
        .firstMatch(rawText);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = _months[match.group(2)!.toLowerCase().substring(0, 3)];
    final year = int.parse(match.group(3)!);
    if (month == null) return match.group(0); // month unrecognised → raw
    return '$year-${_two(month)}-${_two(day)}';
  }

  static bool _looksLikeName(String s) {
    final t = s.trim();
    // Latin letters + spaces/dots only, 2–40 chars, at least two letters.
    return RegExp(r'^[A-Za-z][A-Za-z .]{1,39}$').hasMatch(t) &&
        RegExp(r'[A-Za-z]').allMatches(t).length >= 2;
  }

  static String _titleCase(String s) => s
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  static String _two(int n) => n.toString().padLeft(2, '0');
}
