import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'epi_date_extraction_models.dart' show UnmatchedVaccineRow;
import 'epi_date_extraction_repository.dart';

/// Which engine produced an [EpiScanResult] — surfaced to the SK as a small
/// badge on the scanning-preview screen so it's clear which read the card.
enum EpiScanEngine { geminiVision, mlKitOffline }

/// Result of an EPI card scan — vaccine codes matched in the OCR text plus
/// whatever dates could be read.
class EpiScanResult {
  const EpiScanResult({
    required this.matchedCodes,
    this.extractedDate,
    required this.rawText,
    this.engine = EpiScanEngine.mlKitOffline,
    this.dateByCode = const {},
    this.confidenceByCode = const {},
    this.unmatchedRows = const [],
    this.flagged = false,
    this.flagReason,
  });

  /// Vaccine codes (from [EpiCardScanner._aliases]) found in the OCR output.
  final List<String> matchedCodes;

  /// Offline path only: first printed-looking date pattern parsed from the
  /// OCR text by regex. Handwritten dates are not reliably read this way —
  /// this is a best-effort fallback, not the primary date source once the
  /// online Gemini path is available.
  final DateTime? extractedDate;

  /// Full OCR text — retained for debug logging / future improvements.
  final String rawText;

  /// Which engine produced this result.
  final EpiScanEngine engine;

  /// Online path only: per-vaccine-code handwritten dates Gemini read.
  /// Empty on the offline path.
  final Map<String, DateTime> dateByCode;

  /// Online path only: model-reported confidence (0-1) per dated vaccine
  /// code — drives the scan-review sheet's "Read clearly" vs "Confirm date"
  /// badge. Empty on the offline path (no per-dose confidence signal there).
  final Map<String, double> confidenceByCode;

  /// Online path only: vaccines with no legible date, with a row location
  /// for highlighting which doses are missing. Empty on the offline path
  /// (no backend box-location call there).
  final List<UnmatchedVaccineRow> unmatchedRows;

  /// Online path only: true when the backend's regularity heuristic flagged
  /// this card's dates as suspiciously schedule-templated — see
  /// `EpiDateExtractionResult.flagged`. Always false offline (no dates read).
  final bool flagged;
  final String? flagReason;

  bool get anyMatched =>
      matchedCodes.isNotEmpty || extractedDate != null || dateByCode.isNotEmpty;
}

/// Quality signals detected in a captured card photo, checked before the
/// image is sent to Gemini — a blurry or glare-heavy capture (e.g.
/// photographing a screen rather than the physical card, or a shaky
/// handheld shot) degrades date-extraction accuracy more than the server's
/// multi-vote self-consistency checks can recover from. Heuristic and
/// advisory only — [EpiCardScanner.assessCaptureQuality] never blocks a
/// scan, it only lets the UI offer a retake before spending the call.
class CardCaptureQuality {
  const CardCaptureQuality({required this.isBlurry, required this.hasGlare});
  final bool isBlurry;
  final bool hasGlare;
  bool get hasIssue => isBlurry || hasGlare;
}

/// Where the card image comes from — keeps the `image_picker` transport type
/// out of the UI layer, which only chooses one of these.
enum EpiScanSource { camera, gallery }

/// Scans a photo of a child's EPI vaccination booklet and extracts which
/// vaccines were given and on what date.
///
/// The Bangladesh EPI booklet is printed in Bengali (বাংলা), with vaccine
/// names and handwritten dates in Bengali script/numerals. ML Kit ships no
/// Bengali recognizer, so scanning runs two on-device engines (dual-pass = A+B):
///
///   A. ML Kit Latin OCR — fast, already bundled; reads Latin vaccine tokens
///      and Latin-numeral dates.
///   B. Tesseract `ben` OCR — bundled `assets/tessdata/ben.traineddata`;
///      reads Bengali vaccine names and Bengali-numeral dates. Runs only when
///      pass A alone yields no usable match, so English cards stay fast.
///
/// Both passes feed [_match], which also carries Bengali vaccine-name aliases
/// and normalises Bengali numerals (০–৯ → 0–9) before date extraction.
///
/// Matching is offline-only — both engines run on-device and the alias table
/// is a compile-time constant. No network call is made.
abstract final class EpiCardScanner {
  EpiCardScanner._();

  /// Tesseract language pack bundled under `assets/tessdata/`.
  static const String _tessLanguage = 'ben';

  // Alias lists match case-insensitively via `contains`. Latin aliases are
  // lowercase; Bengali aliases have no case so appear verbatim. Bengali card
  // names carry no dose number (the dose is the column position), so a Bengali
  // row label such as পেন্টা maps to every dose of that vaccine — the single
  // extracted date is applied to each matched milestone for SK review.
  // Bengali aliases include BOTH the vaccine abbreviation (পেন্টা) AND the
  // descriptive disease wording actually printed on the national EPI card
  // (e.g. পেntavalent is listed as ডিপথেরিয়া / হুপিং কাশি / ধনুষ্টংকার /
  // হেপাটাইটিস বি / হিমোফাইলাস; MR as হাম / রুবেলা; PCV as নিউমোকক্কাল /
  // নিউমোনিয়া) — confirmed from on-device OCR of a real card. Substrings are
  // chosen to survive OCR spacing/conjunct noise.
  static const Map<String, List<String>> _aliases = {
    'BCG': ['bcg', 'bacille calmette', 'bacillus calmette', 'বিসিজি', 'যক্ষ্মা'],
    'PENTA1': [
      'penta-1', 'penta 1', 'pentavalent-1', 'pentavalent 1', 'penta1', 'পেন্টা',
      'ডিপথেরিয়া', 'হুপিং', 'ধনুষ্টংকার', 'হেপাটাইটিস', 'হিমোফাইলাস',
    ],
    'PENTA2': [
      'penta-2', 'penta 2', 'pentavalent-2', 'pentavalent 2', 'penta2', 'পেন্টা',
      'ডিপথেরিয়া', 'হুপিং', 'ধনুষ্টংকার', 'হেপাটাইটিস', 'হিমোফাইলাস',
    ],
    'PENTA3': [
      'penta-3', 'penta 3', 'pentavalent-3', 'pentavalent 3', 'penta3', 'পেন্টা',
      'ডিপথেরিয়া', 'হুপিং', 'ধনুষ্টংকার', 'হেপাটাইটিস', 'হিমোফাইলাস',
    ],
    'PCV1': ['pcv-1', 'pcv 1', 'pcv1', 'pneumococcal-1', 'pneumococcal 1', 'পিসিভি', 'নিউমোকক্কাল', 'নিউমোনিয়া'],
    'PCV2': ['pcv-2', 'pcv 2', 'pcv2', 'pneumococcal-2', 'pneumococcal 2', 'পিসিভি', 'নিউমোকক্কাল', 'নিউমোনিয়া'],
    'PCV3': ['pcv-3', 'pcv 3', 'pcv3', 'pneumococcal-3', 'pneumococcal 3', 'পিসিভি', 'নিউমোকক্কাল', 'নিউমোনিয়া'],
    'OPV1': ['opv-1', 'opv 1', 'opv1', 'polio-1', 'polio 1', 'ওপিভি', 'পোলিও'],
    'OPV2': ['opv-2', 'opv 2', 'opv2', 'polio-2', 'polio 2', 'ওপিভি', 'পোলিও'],
    'OPV3': ['opv-3', 'opv 3', 'opv3', 'polio-3', 'polio 3', 'ওপিভি', 'পোলিও'],
    'FIPV1': ['fipv-1', 'fipv 1', 'fipv1', 'ipv-1', 'ipv 1', 'ipv1', 'আইপিভি'],
    'FIPV2': ['fipv-2', 'fipv 2', 'fipv2', 'ipv-2', 'ipv 2', 'ipv2', 'আইপিভি'],
    'MR1': ['mr-1', 'mr 1', 'mr1', 'measles-rubella 1', 'measles rubella 1', 'এমআর', 'হাম', 'রুবেলা'],
    'MR2': ['mr-2', 'mr 2', 'mr2', 'measles-rubella 2', 'measles rubella 2', 'এমআর', 'হাম', 'রুবেলা'],
    'TCV': ['tcv', 'typhoid conjugate', 'typhoid', 'টিসিভি', 'টাইফয়েড'],
  };

  // Bengali (Bangla) digit → ASCII digit. Applied before date parsing so the
  // date regex — which matches ASCII \d — sees normalised numerals.
  static const Map<String, String> _bengaliDigits = {
    '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
    '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
  };

  // Matches DD/MM/YYYY, DD-MM-YYYY, D/M/YY (EPI card date formats).
  static final _dateRe =
      RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Acquires a card image from [source] (camera or gallery) via [image_picker],
  /// runs OCR, and returns matched codes + extracted date for [targetCodes]
  /// (a milestone's vaccine codes).
  ///
  /// Returns null if the user dismissed the picker without choosing an image.
  static Future<EpiScanResult?> pickAndScan(
    List<String> targetCodes, {
    EpiScanSource source = EpiScanSource.camera,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source == EpiScanSource.gallery
          ? ImageSource.gallery
          : ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return _scanFile(File(picked.path), targetCodes);
  }

  /// Runs OCR on an already-acquired [image] (captured or uploaded by the
  /// scan screen) and returns matched codes + extracted date for [targetCodes].
  ///
  /// Always offline (ML Kit + Tesseract) — see [scanImageAuto] for the
  /// online-preferred dispatch used by the scan screen.
  static Future<EpiScanResult> scanImage(
          File image, List<String> targetCodes) =>
      _scanFile(image, targetCodes);

  /// Picks the scan engine once, up front, based on connectivity:
  ///
  ///  * Online — sends [image] to Gemini vision via [dateExtractionRepo],
  ///    which reads vaccine names **and** per-vaccine handwritten dates in a
  ///    single call. Falls back to the offline path below if the call fails
  ///    (network drop mid-call, timeout, 5xx).
  ///  * Offline — runs the existing on-device ML Kit + Tesseract pass
  ///    ([scanImage]), names only, exactly as before.
  ///
  /// The caller (scan screen) checks connectivity itself first so it can
  /// show the right engine badge before OCR starts; this method re-derives
  /// the same decision so it is also safe to call directly in tests/other
  /// callers without duplicating the connectivity check.
  static Future<EpiScanResult> scanImageAuto(
    File image,
    List<String> targetCodes,
    EpiDateExtractionRepository dateExtractionRepo,
  ) async {
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity.any((r) => r != ConnectivityResult.none);
    if (isOnline) {
      try {
        final prepared = await prepareForVisionUpload(image);
        final result = await dateExtractionRepo.extractEpiDates(prepared);
        return EpiScanResult(
          matchedCodes: result.matchedCodes,
          dateByCode: result.dateByCode,
          confidenceByCode: result.confidenceByCode,
          unmatchedRows: result.unmatchedRows,
          rawText: '',
          engine: EpiScanEngine.geminiVision,
          flagged: result.flagged,
          flagReason: result.flagReason,
        );
      } on EpiDateExtractionException catch (e) {
        debugPrint('[EpiCardScanner] Gemini vision extraction failed, '
            'falling back to offline OCR: $e');
      }
    }
    return scanImage(image, targetCodes);
  }

  /// Pure text-matching path — exposed for unit tests (no camera/ML Kit needed).
  static EpiScanResult matchText(String ocrText, List<String> targetCodes) =>
      _match(ocrText, targetCodes);

  /// Checks a freshly captured/picked card photo for blur and glare before
  /// it's sent to Gemini — cheap, local, heuristic-only. Call this right
  /// after capture so the scan screen can offer a retake before spending an
  /// online extraction call on a photo that's unlikely to read well (most
  /// commonly: photographing a screen displaying the card rather than the
  /// physical card itself, which compounds glare and a moiré-like softness).
  static Future<CardCaptureQuality> assessCaptureQuality(
      File imageFile) async {
    try {
      final decoded = img.decodeImage(await imageFile.readAsBytes());
      if (decoded == null) {
        return const CardCaptureQuality(isBlurry: false, hasGlare: false);
      }
      var small = img.bakeOrientation(decoded);
      const target = 240;
      final longest = small.width >= small.height ? small.width : small.height;
      if (longest > target) {
        final scale = target / longest;
        small = img.copyResize(
          small,
          width: (small.width * scale).round(),
          height: (small.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
      }

      // Glare: fraction of near-pure-white pixels — a flash reflection or a
      // screen's backlight blows out a patch of the image toward white in a
      // way printed paper under normal light essentially never does.
      var brightCount = 0;
      final totalPixels = small.width * small.height;
      for (final p in small) {
        if (p.r > 250 && p.g > 250 && p.b > 250) brightCount++;
      }
      final hasGlare =
          totalPixels > 0 && (brightCount / totalPixels) > 0.10;

      // Blur: variance of a Laplacian edge response on a grayscale copy — a
      // sharp, in-focus photo has strong, varied edge responses; a blurry
      // one flattens toward a near-uniform response. Threshold is a rough
      // heuristic tuned conservatively (favours missing mild blur over
      // false-flagging a legitimately sharp card) since this only ever
      // prompts a retake, never blocks one.
      final gray = img.grayscale(small);
      final edges = img.convolution(gray, filter: const [
        0, -1, 0, //
        -1, 4, -1, //
        0, -1, 0, //
      ]);
      double sum = 0, sumSq = 0;
      var n = 0;
      for (final p in edges) {
        final v = p.r.toDouble();
        sum += v;
        sumSq += v * v;
        n++;
      }
      final mean = n == 0 ? 0.0 : sum / n;
      final variance = n == 0 ? 0.0 : (sumSq / n) - (mean * mean);
      final isBlurry = variance < 8.0;

      return CardCaptureQuality(isBlurry: isBlurry, hasGlare: hasGlare);
    } on Object catch (e) {
      debugPrint('[EpiCardScanner] assessCaptureQuality failed: $e');
      return const CardCaptureQuality(isBlurry: false, hasGlare: false);
    }
  }

  /// Prepares a captured card photo for the online Gemini call. Unlike
  /// [_preprocess] (grayscale + contrast, tuned for the offline ML Kit /
  /// Tesseract OCR engines), a vision model reads a clean color photo better
  /// than a grayscale-and-contrast-boosted one — this only bakes in EXIF
  /// orientation and caps an oversized raw camera capture, so a very large
  /// sensor photo doesn't balloon the upload for no accuracy benefit.
  /// Degrades to the original file on any decode/encode failure.
  static Future<File> prepareForVisionUpload(File src) async {
    try {
      final decoded = img.decodeImage(await src.readAsBytes());
      if (decoded == null) return src;
      var im = img.bakeOrientation(decoded);

      const maxDimension = 2048;
      final longest = im.width >= im.height ? im.width : im.height;
      if (longest > maxDimension) {
        final scale = maxDimension / longest;
        im = img.copyResize(
          im,
          width: (im.width * scale).round(),
          height: (im.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
      }

      final dir = await getTemporaryDirectory();
      final out = File(
          '${dir.path}/epi_vision_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(img.encodeJpg(im, quality: 92));
      return out;
    } on Object catch (e) {
      debugPrint('[EpiCardScanner] prepareForVisionUpload failed: $e');
      return src;
    }
  }

  /// Normalises Bengali numerals (০–৯) to ASCII (0–9). Exposed for tests.
  static String normalizeBengaliDigits(String s) {
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_bengaliDigits[ch] ?? ch);
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static Future<EpiScanResult> _scanFile(
      File imageFile, List<String> targetCodes) async {
    // Preprocess once (grayscale + upscale + contrast) — the single biggest
    // lever for on-device OCR of a phone photo of a Bengali booklet. Both
    // engines read the cleaned image.
    final prepared = await _preprocess(imageFile);

    // Pass A — ML Kit Latin (fast, always bundled).
    final latinText = await _recogniseLatin(prepared);
    final latinResult = _match(latinText, targetCodes);

    // English/Latin card fully read — skip the slower Bengali pass.
    if (latinResult.matchedCodes.isNotEmpty &&
        latinResult.extractedDate != null) {
      return latinResult;
    }

    // Pass B — Tesseract Bengali (reads Bengali names + numerals). Combine both
    // transcripts so a card mixing scripts still matches on either engine.
    final bengaliText = await _recogniseBengali(prepared);
    if (bengaliText.isEmpty) return latinResult;
    return _match('$latinText\n$bengaliText', targetCodes);
  }

  /// Cleans a card photo for OCR: upscales small captures, converts to
  /// grayscale, and lifts contrast. Bengali print on a phone photo is small and
  /// low-contrast; this markedly improves both ML Kit and Tesseract accuracy.
  /// Degrades to the original file on any decode/encode failure.
  static Future<File> _preprocess(File src) async {
    try {
      final decoded = img.decodeImage(await src.readAsBytes());
      if (decoded == null) return src;
      var im = img.bakeOrientation(decoded); // honour EXIF rotation

      // Normalise the longest side to ~1600px: DOWNSCALE large phone captures
      // (12MP photos otherwise spike memory and OOM low-RAM devices) and only
      // modestly upscale small ones. 1600 keeps Bengali print legible for OCR
      // without the memory cost of full resolution.
      const target = 1600;
      final longest = im.width >= im.height ? im.width : im.height;
      if (longest != target) {
        final scale = target / longest;
        im = img.copyResize(
          im,
          width: (im.width * scale).round(),
          height: (im.height * scale).round(),
          interpolation: scale < 1
              ? img.Interpolation.average // downscale: cheaper + anti-aliased
              : img.Interpolation.cubic,
        );
      }
      im = img.grayscale(im);
      im = img.adjustColor(im, contrast: 1.35);
      final dir = await getTemporaryDirectory();
      final out = File(
          '${dir.path}/epi_pre_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(img.encodeJpg(im, quality: 90));
      return out;
    } on Object catch (e) {
      debugPrint('[EpiCardScanner] preprocess failed: $e');
      return src;
    }
  }

  /// Runs ML Kit Latin OCR. Degrades to empty text on failure (e.g. a very
  /// large device capture, decode error) so the Bengali pass still runs rather
  /// than the whole scan throwing.
  static Future<String> _recogniseLatin(File imageFile) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognised =
          await recognizer.processImage(InputImage.fromFile(imageFile));
      return recognised.text;
    } on Object catch (e) {
      debugPrint('[EpiCardScanner] ML Kit Latin OCR failed: $e');
      return '';
    } finally {
      recognizer.close();
    }
  }

  /// Runs Tesseract `ben`. Degrades to empty text if the engine is unavailable
  /// (e.g. traineddata missing, platform unsupported) so the ML Kit result
  /// still stands rather than failing the whole scan.
  static Future<String> _recogniseBengali(File imageFile) async {
    try {
      return await FlutterTesseractOcr.extractText(
        imageFile.path,
        language: _tessLanguage,
        args: const {
          'preserve_interword_spaces': '1',
          // PSM 4: assume a single column of text of variable sizes — fits the
          // booklet's vaccine-name column better than the default page mode.
          'psm': '4',
        },
      );
    } on Object catch (e) {
      debugPrint('[EpiCardScanner] Tesseract ben OCR unavailable: $e');
      return '';
    }
  }

  static EpiScanResult _match(String ocrText, List<String> targetCodes) {
    // Normalise Bengali numerals once for both alias-matching and date parsing.
    final normalized = normalizeBengaliDigits(ocrText);
    final lower = normalized.toLowerCase();
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
      extractedDate: _extractDate(normalized),
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
