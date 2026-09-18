import 'dart:ui' show Rect;

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

/// A member's gender as read from an NID. Kept as a small enum (rather than a
/// raw string) so callers map it onto their own option lists deterministically.
enum NidGender {
  male,
  female;

  /// Human-readable label callers match against their own option lists
  /// (e.g. `EnrollmentStrings.gendersMember`), case-insensitively.
  String get label => this == NidGender.male ? 'Male' : 'Female';
}

/// Fields read from a Bangladesh NID card.
///
/// Latin-script fields (NID number, English name, date of birth) come from
/// on-device Latin OCR. [gender] is only reliably available from the card's
/// **back-side 2D barcode / MRZ** — the Latin front rarely prints "Sex" — so it
/// is often null after a front-only scan and left for the health worker to pick
/// in the review step. পিতা (father) / মাতা (mother) print in Bengali only and
/// cannot be read by the Latin recognizer.
class NidCardData {
  const NidCardData({
    this.nidNumber,
    this.name,
    this.dateOfBirth,
    this.gender,
  });

  /// NID number, digits only (10 / 13 / 17).
  final String? nidNumber;

  /// English name as printed under the "Name" label.
  final String? name;

  /// Date of birth, ISO `yyyy-MM-dd` when parseable, else the raw match.
  final String? dateOfBirth;

  /// Gender, when it could be determined (barcode/MRZ, or an explicit Latin
  /// "Sex" label). Null when the scan could not read it.
  final NidGender? gender;

  /// Merge [other]'s non-null fields over this one — used to layer an
  /// authoritative barcode read on top of a front OCR read (or vice-versa).
  NidCardData mergeMissing(NidCardData other) => NidCardData(
        nidNumber: nidNumber ?? other.nidNumber,
        name: name ?? other.name,
        dateOfBirth: dateOfBirth ?? other.dateOfBirth,
        gender: gender ?? other.gender,
      );
}

/// Result of a single NID scan. [data] is set when [status] is
/// [NidScanStatus.success].
class NidScanResult {
  const NidScanResult(this.status, [this.data]);

  final NidScanStatus status;
  final NidCardData? data;
}

/// Captures a photo of a Bangladesh NID card and extracts its fields.
///
/// On-device only (Google ML Kit) — no network, so it works offline. Every
/// field is a proposal the health worker confirms before it is saved, so
/// partial/imperfect OCR is safe.
///
/// Accuracy notes:
///  * The name is located by **layout** — the text block directly below the
///    "Name" label — not by a blind "next line" split, which reorders
///    unpredictably. A stop-word list rejects card boilerplate (Republic,
///    Bangladesh, Government, …) so the name field can never be filled with the
///    card header or another label.
///  * If the captured image contains the back-side 2D barcode / QR, it is
///    decoded and its (authoritative) fields — including gender — are layered
///    over the OCR read.
class NidOcrService {
  NidOcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Bangladesh NID numbers are 10 (Smart NID), 13, or 17 digits.
  static const Set<int> _validNidLengths = {10, 13, 17};

  static const Map<String, int> _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Card boilerplate and field labels that must never be mistaken for a name.
  /// Lower-cased; matched against a whole candidate line.
  static const Set<String> _nameStopWords = {
    'government', "government of the people's republic of bangladesh",
    'peoples republic of bangladesh', "people's republic of bangladesh",
    'republic', 'bangladesh', 'national', 'national id card', 'national id',
    'id card', 'smart', 'smart card', 'nid', 'name', 'date of birth',
    'date', 'birth', 'id no', 'id no.', 'idno', 'blood group', 'sex',
    'gender', 'father', 'mother', 'husband', 'wife', 'address',
  };

  /// Words that appearing anywhere in a candidate line disqualify it as a name.
  static const Set<String> _nameBlocklistTokens = {
    'republic', 'bangladesh', 'government', 'national', 'card', 'smart',
    'birth', 'blood',
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
  /// 128, PDF417 and EAN-13 — the formats most likely on health cards, the
  /// Bangladesh Smart NID back, and patient wristbands in this context.
  Future<String?> extractQrCode(String imagePath) async {
    final scanner = BarcodeScanner(formats: [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.pdf417,
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

  /// Runs OCR (and an opportunistic barcode decode) on an already-captured
  /// image file and extracts the NID card fields.
  Future<NidScanResult> extractNidFromImage(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final text = recognized.text;

      var data = NidCardData(
        nidNumber: extractNidNumber(text),
        name: extractNameFromRecognizedText(recognized),
        dateOfBirth: extractDateOfBirth(text),
        gender: extractGender(text),
      );

      // Layer the authoritative back-side sources over the front OCR read:
      //  1. the machine-readable zone (MRZ) — reliable name + sex + DOB;
      //  2. the 2D barcode / QR, when the decoder can read it.
      final fromMrz = parseMrz(text);
      if (fromMrz != null) data = fromMrz.mergeMissing(data);

      final raw = await extractQrCode(imagePath);
      final fromBarcode = raw == null ? null : parseNidBarcode(raw);
      if (fromBarcode != null) data = fromBarcode.mergeMissing(data);

      if (data.nidNumber == null) {
        return const NidScanResult(NidScanStatus.notFound);
      }
      return NidScanResult(NidScanStatus.success, data);
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

  /// Extracts the English name using the card **layout**: the recognised text
  /// block/line directly below the "Name" label, horizontally aligned with it.
  /// Falls back to the text-only heuristic ([extractName]) when the layout can't
  /// be resolved. This is the accurate path that avoids grabbing unrelated card
  /// text.
  static String? extractNameFromRecognizedText(RecognizedText recognized) {
    // Flatten to (text, box) pairs in reading order.
    final lines = <_OcrLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isEmpty) continue;
        lines.add(_OcrLine(t, line.boundingBox));
      }
    }
    if (lines.isEmpty) return null;

    // 1) Inline "Name ROMANA RAHMAN" on the label line itself.
    for (final l in lines) {
      final inline = RegExp(r'^name[:\s]+(.+)$', caseSensitive: false)
          .firstMatch(l.text);
      if (inline != null) {
        final cand = inline.group(1)!.trim();
        if (_looksLikeName(cand)) return _titleCase(cand);
      }
    }

    // 2) Positional: find the "Name" label, then the nearest line below it that
    //    horizontally overlaps and looks like a name.
    _OcrLine? label;
    for (final l in lines) {
      final lower = l.text.toLowerCase().replaceAll(RegExp(r'[:\s]+$'), '');
      if (lower == 'name') {
        label = l;
        break;
      }
    }
    if (label != null) {
      _OcrLine? best;
      for (final l in lines) {
        if (identical(l, label)) continue;
        // Must sit below the label and share horizontal span with it.
        final below = l.box.top >= label.box.top;
        final overlaps = l.box.left < label.box.right &&
            l.box.right > label.box.left - label.box.width;
        if (below && overlaps && _looksLikeName(l.text)) {
          if (best == null || l.box.top < best.box.top) best = l;
        }
      }
      if (best != null) return _titleCase(best.text);
    }

    // 3) Fall back to the text-only heuristic.
    return extractName(recognized.text);
  }

  /// Text-only name extraction (no layout). Kept for callers/tests that only
  /// have raw text. Uses the "line after the Name label" heuristic, guarded by
  /// [_looksLikeName]'s stop-word rejection. Exposed for unit testing.
  static String? extractName(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      // Inline form: "Name ROMANA RAHMAN".
      final inline = RegExp(r'^name[:\s]+(.+)$', caseSensitive: false)
          .firstMatch(lines[i]);
      if (inline != null && _looksLikeName(inline.group(1)!)) {
        return _titleCase(inline.group(1)!.trim());
      }
      // The standalone "Name" label — value is the next name-like line.
      if ((lower == 'name' || lower == 'name:') && i + 1 < lines.length) {
        for (var j = i + 1; j < lines.length; j++) {
          if (_looksLikeName(lines[j])) return _titleCase(lines[j]);
          // Stop scanning once we hit another label — the name is missing.
          if (_isLabelLine(lines[j])) break;
        }
      }
    }
    return null;
  }

  /// Extracts gender from an explicit Latin "Sex"/"Gender" label, when the card
  /// prints one. Returns null otherwise (the common front-only case). Exposed
  /// for unit testing.
  static NidGender? extractGender(String rawText) {
    for (final line in rawText.split('\n')) {
      final m = RegExp(r'\b(sex|gender)\b[:\s]*([a-z]+)', caseSensitive: false)
          .firstMatch(line);
      if (m == null) continue;
      final v = m.group(2)!.toLowerCase();
      if (v.startsWith('m')) return NidGender.male; // male / m
      if (v.startsWith('f')) return NidGender.female; // female / f
    }
    return null;
  }

  /// Best-effort parse of a decoded NID barcode/QR payload. The Bangladesh
  /// Smart NID back encodes delimited `key=value` (or line) fields including
  /// name, date of birth, NID and sex. Returns null when nothing usable is
  /// found. Exposed for unit testing.
  static NidCardData? parseNidBarcode(String raw) {
    if (raw.trim().isEmpty) return null;
    final nid = extractNidNumber(raw);
    final dob = extractDateOfBirth(raw);
    NidGender? gender = extractGender(raw);
    String? name;

    // key=value / key:value pairs, one per line or delimited.
    for (final part in raw.split(RegExp(r'[\n;|]'))) {
      final kv = RegExp(r'^\s*([A-Za-z ]+)\s*[:=]\s*(.+)$').firstMatch(part);
      if (kv == null) continue;
      final key = kv.group(1)!.trim().toLowerCase();
      final value = kv.group(2)!.trim();
      if (name == null && (key == 'name' || key == 'name_eng') &&
          _looksLikeName(value)) {
        name = _titleCase(value);
      }
      if (gender == null && (key == 'sex' || key == 'gender')) {
        final v = value.toLowerCase();
        if (v.startsWith('m')) gender = NidGender.male;
        if (v.startsWith('f')) gender = NidGender.female;
      }
    }

    if (nid == null && name == null && dob == null && gender == null) {
      return null;
    }
    return NidCardData(
        nidNumber: nid, name: name, dateOfBirth: dob, gender: gender);
  }

  /// Parses the 3-line TD1 machine-readable zone printed on the **back** of a
  /// Bangladesh Smart NID, e.g.:
  /// ```
  /// I<BGD000000000<00<<<<<<<<<<<<<
  /// 0000000M0000000BGD<<<<<<<<<<<<0
  /// MONDOL<<RANU<<<<<<<<<<<<<<<<
  /// ```
  /// Returns name (given + surname), sex and DOB when found — the reliable
  /// source for gender, which the Latin front does not print. NID number is left
  /// null (the MRZ document number is not the 10-digit NID). Returns null when
  /// no MRZ-shaped lines are present. Exposed for unit testing.
  static NidCardData? parseMrz(String rawText) {
    // MRZ lines are uppercase [A-Z0-9<]; keep only those with a filler run.
    final mrzLines = <String>[];
    for (final line in rawText.toUpperCase().split('\n')) {
      final compact = line.replaceAll(RegExp(r'\s'), '');
      if (compact.contains('<<') ||
          RegExp(r'^[A-Z0-9<]{10,}$').hasMatch(compact) &&
              compact.contains('<')) {
        mrzLines.add(compact);
      }
    }
    if (mrzLines.isEmpty) return null;

    NidGender? gender;
    String? name;
    String? dob;

    for (final l in mrzLines) {
      // Sex line: <6-7 digits><M|F|X><digits…>. The char after the birth-date
      // group is the sex.
      final sex = RegExp(r'^\d{6,7}([MFX])\d').firstMatch(l);
      if (sex != null && gender == null) {
        final s = sex.group(1)!;
        if (s == 'M') gender = NidGender.male;
        if (s == 'F') gender = NidGender.female;
        // Birth date = first 6 digits, YYMMDD.
        final yymmdd = l.substring(0, 6);
        final yy = int.tryParse(yymmdd.substring(0, 2));
        final mm = int.tryParse(yymmdd.substring(2, 4));
        final dd = int.tryParse(yymmdd.substring(4, 6));
        if (yy != null && mm != null && mm >= 1 && mm <= 12 &&
            dd != null && dd >= 1 && dd <= 31) {
          // NID holders are alive today → 19xx/20xx pivot at the current-ish
          // two-digit boundary; use 30 as a safe cut (00–30 → 20xx, else 19xx).
          final year = yy <= 30 ? 2000 + yy : 1900 + yy;
          dob = '$year-${_two(mm)}-${_two(dd)}';
        }
      }
      // Name line: SURNAME<<GIVEN<NAMES.
      final nameLine = RegExp(r'^([A-Z]+(?:<[A-Z]+)*)<<([A-Z<]+)$').firstMatch(l);
      if (nameLine != null && name == null) {
        final surname = nameLine.group(1)!.replaceAll('<', ' ').trim();
        final given = nameLine.group(2)!.replaceAll('<', ' ').trim();
        final full = '$given $surname'.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (_looksLikeName(full)) name = _titleCase(full);
      }
    }

    if (gender == null && name == null && dob == null) return null;
    return NidCardData(name: name, dateOfBirth: dob, gender: gender);
  }

  /// Extracts the date of birth (e.g. "25 Nov 1983") as ISO `yyyy-MM-dd`.
  /// Exposed for unit testing.
  static String? extractDateOfBirth(String rawText) {
    final match = RegExp(r'(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})')
        .firstMatch(rawText);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = _fuzzyMonth(match.group(2)!);
    final year = int.parse(match.group(3)!);
    if (month == null) return match.group(0); // month unrecognised → raw
    return '$year-${_two(month)}-${_two(day)}';
  }

  /// Resolves a month token to 1–12, tolerating the single-character misreads
  /// ML Kit makes on card fonts (e.g. `Noy`→`Nov`, `Jun`/`Jul`). Exact prefix
  /// first, then the month whose 3-letter prefix is within one substitution.
  static int? _fuzzyMonth(String raw) {
    final tok = raw.toLowerCase();
    if (tok.length < 3) return null;
    final key = tok.substring(0, 3);
    final exact = _months[key];
    if (exact != null) return exact;
    for (final entry in _months.entries) {
      var diffs = 0;
      for (var i = 0; i < 3; i++) {
        if (key[i] != entry.key[i]) diffs++;
      }
      if (diffs <= 1) return entry.value;
    }
    return null;
  }

  /// True when [s] plausibly IS a person's name — Latin letters/spaces/dots
  /// only, 2–40 chars, ≥2 letters — AND is not NID boilerplate or a field
  /// label (the guard that stops "Republic"/"Bangladesh"/"Government" landing
  /// in the name field).
  static bool _looksLikeName(String s) {
    final t = s.trim();
    if (!RegExp(r'^[A-Za-z][A-Za-z .]{1,39}$').hasMatch(t)) return false;
    if (RegExp(r'[A-Za-z]').allMatches(t).length < 2) return false;
    final lower = t.toLowerCase();
    if (_nameStopWords.contains(lower)) return false;
    final tokens = lower.split(RegExp(r'\s+'));
    for (final tok in tokens) {
      if (_nameBlocklistTokens.contains(tok)) return false;
    }
    return true;
  }

  /// True when [s] reads as a field label rather than a value — used to stop the
  /// text-only scan from walking past the name into other fields.
  static bool _isLabelLine(String s) {
    final lower = s.toLowerCase().replaceAll(RegExp(r'[:\s]+$'), '');
    return _nameStopWords.contains(lower) ||
        RegExp(r'\d').hasMatch(s); // DOB / ID No lines carry digits
  }

  static String _titleCase(String s) => s
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// One recognised OCR line with its bounding box, for layout-based parsing.
class _OcrLine {
  const _OcrLine(this.text, this.box);
  final String text;
  final Rect box;
}
