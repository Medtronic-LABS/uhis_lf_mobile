import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Result of an EPI card scan — vaccine codes matched in the OCR text plus
/// the first parseable date found on the card.
class EpiScanResult {
  const EpiScanResult({
    required this.matchedCodes,
    this.extractedDate,
    required this.rawText,
  });

  /// Vaccine codes (from [EpiCardScanner._aliases]) found in the OCR output.
  final List<String> matchedCodes;

  /// First date pattern successfully parsed from the OCR text. Null if no
  /// recognisable date was present.
  final DateTime? extractedDate;

  /// Full OCR text — retained for debug logging / future improvements.
  final String rawText;

  bool get anyMatched => matchedCodes.isNotEmpty || extractedDate != null;
}

/// Scans a photo of a child's EPI vaccination booklet and extracts which
/// vaccines were given and on what date.
///
/// Matching is offline-only — ML Kit text recognition runs on-device and
/// the vaccine alias table is a compile-time constant. No network call is made.
abstract final class EpiCardScanner {
  EpiCardScanner._();

  // Alias lists are lowercase; matching is case-insensitive.
  static const Map<String, List<String>> _aliases = {
    'BCG': ['bcg', 'bacille calmette', 'bacillus calmette'],
    'PENTA1': ['penta-1', 'penta 1', 'pentavalent-1', 'pentavalent 1', 'penta1'],
    'PENTA2': ['penta-2', 'penta 2', 'pentavalent-2', 'pentavalent 2', 'penta2'],
    'PENTA3': ['penta-3', 'penta 3', 'pentavalent-3', 'pentavalent 3', 'penta3'],
    'PCV1': ['pcv-1', 'pcv 1', 'pcv1', 'pneumococcal-1', 'pneumococcal 1'],
    'PCV2': ['pcv-2', 'pcv 2', 'pcv2', 'pneumococcal-2', 'pneumococcal 2'],
    'PCV3': ['pcv-3', 'pcv 3', 'pcv3', 'pneumococcal-3', 'pneumococcal 3'],
    'OPV1': ['opv-1', 'opv 1', 'opv1', 'polio-1', 'polio 1'],
    'OPV2': ['opv-2', 'opv 2', 'opv2', 'polio-2', 'polio 2'],
    'OPV3': ['opv-3', 'opv 3', 'opv3', 'polio-3', 'polio 3'],
    'FIPV1': ['fipv-1', 'fipv 1', 'fipv1', 'ipv-1', 'ipv 1', 'ipv1'],
    'FIPV2': ['fipv-2', 'fipv 2', 'fipv2', 'ipv-2', 'ipv 2', 'ipv2'],
    'MR1': ['mr-1', 'mr 1', 'mr1', 'measles-rubella 1', 'measles rubella 1'],
    'MR2': ['mr-2', 'mr 2', 'mr2', 'measles-rubella 2', 'measles rubella 2'],
    'TCV': ['tcv', 'typhoid conjugate', 'typhoid'],
  };

  // Matches DD/MM/YYYY, DD-MM-YYYY, D/M/YY (EPI card date formats).
  static final _dateRe =
      RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Opens the device camera via [image_picker], runs OCR, and returns matched
  /// codes + extracted date for [targetCodes] (a milestone's vaccine codes).
  ///
  /// Returns null if the user cancelled the camera without capturing.
  static Future<EpiScanResult?> pickAndScan(List<String> targetCodes) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return _scanFile(File(picked.path), targetCodes);
  }

  /// Pure text-matching path — exposed for unit tests (no camera/ML Kit needed).
  static EpiScanResult matchText(String ocrText, List<String> targetCodes) =>
      _match(ocrText, targetCodes);

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static Future<EpiScanResult> _scanFile(
      File imageFile, List<String> targetCodes) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognised =
          await recognizer.processImage(InputImage.fromFile(imageFile));
      return _match(recognised.text, targetCodes);
    } finally {
      recognizer.close();
    }
  }

  static EpiScanResult _match(String ocrText, List<String> targetCodes) {
    final lower = ocrText.toLowerCase();
    final matched = <String>[];
    for (final code in targetCodes) {
      final aliases = _aliases[code];
      if (aliases == null) continue;
      for (final alias in aliases) {
        if (lower.contains(alias)) {
          matched.add(code);
          break;
        }
      }
    }
    return EpiScanResult(
      matchedCodes: matched,
      extractedDate: _extractDate(ocrText),
      rawText: ocrText,
    );
  }

  static DateTime? _extractDate(String text) {
    for (final m in _dateRe.allMatches(text)) {
      try {
        final day = int.parse(m.group(1)!);
        final month = int.parse(m.group(2)!);
        int year = int.parse(m.group(3)!);
        if (year < 100) year += 2000;
        if (month < 1 || month > 12 || day < 1 || day > 31) continue;
        final candidate = DateTime(year, month, day);
        if (candidate.isAfter(DateTime(2010)) &&
            !candidate.isAfter(DateTime.now())) {
          return candidate;
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
