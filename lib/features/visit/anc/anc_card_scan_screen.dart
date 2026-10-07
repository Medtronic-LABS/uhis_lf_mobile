import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_strings.dart';
import '../immunisation/epi_card_scanner.dart' show EpiCardScanner;
import 'anc_visit_extraction_models.dart';
import 'anc_visit_extraction_repository.dart';

/// Full-screen "scan" surface for the ANC "মা ও নবজাতক স্বাস্থ্য তথ্যকার্ড"
/// card — a live rear-camera viewfinder with a capture button and an
/// in-frame "upload from gallery" affordance, targeted at one specific
/// visit column ([visitNumber]) since that's the one the SK is currently
/// recording.
///
/// After capture, shows the photo with a sweeping scan-line and reveals each
/// found field one by one (mirrors [EpiCardScanScreen]'s reveal chrome, but
/// visit-targeted field/value pairs instead of a per-vaccine checklist) —
/// then pops the already-complete [AncVisitExtractionResult].
class AncCardScanScreen extends StatefulWidget {
  const AncCardScanScreen({
    super.key,
    required this.visitNumber,
    required this.repository,
  });

  /// Which visit column to target (1-indexed, left-to-right on the card).
  final int visitNumber;

  final AncVisitExtractionRepository repository;

  @override
  State<AncCardScanScreen> createState() => _AncCardScanScreenState();
}

class _AncCardScanScreenState extends State<AncCardScanScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _cameraReady = false;
  bool _cameraUnavailable = false;
  bool _busy = false;
  File? _preview;
  late final AnimationController _sweepCtrl;

  /// Field/value lines revealed one-by-one as the scan "finds" them.
  final List<_FoundEntry> _found = [];
  String? _error;
  AncColumnBoundingBox? _columnBox;

  @override
  void initState() {
    super.initState();
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _cameraUnavailable = true);
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraUnavailable = true);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraReady = true;
      });
    } on CameraException catch (e) {
      debugPrint('AncCardScanScreen: camera init failed: $e');
      if (mounted) setState(() => _cameraUnavailable = true);
    }
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_busy || controller == null || !_cameraReady) return;
    setState(() => _busy = true);
    try {
      final frame = await controller.takePicture();
      if (!mounted) return;
      await _runExtraction(File(frame.path));
    } on CameraException catch (e) {
      debugPrint('AncCardScanScreen: takePicture failed: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (!mounted) return;
    if (picked == null) {
      setState(() => _busy = false);
      return;
    }
    await _runExtraction(File(picked.path));
  }

  /// Builds the ordered (label, formatted value) list for every field the
  /// scan looked for — present entries render a green check, missing ones
  /// an amber "not found" line. `visitDate`/`fetalHeartSoundPresent` are
  /// omitted (no mobile form field to confirm them against yet — see
  /// `UnifiedFormNotifier._ancScanFieldMap`'s doc comment).
  List<_FoundEntry> _entriesFor(AncVisitExtraction visit) {
    String bp() => '${visit.bpSystolic}/${visit.bpDiastolic}';
    return [
      _FoundEntry(
        AncScanStrings.weightLabel,
        visit.weightKg != null ? '${visit.weightKg} kg' : null,
      ),
      _FoundEntry(
        AncScanStrings.bpLabel,
        visit.bpSystolic != null && visit.bpDiastolic != null ? bp() : null,
      ),
      _FoundEntry(
        AncScanStrings.fundalHeightLabel,
        visit.fundalHeightCm != null ? '${visit.fundalHeightCm} cm' : null,
      ),
      _FoundEntry(
        AncScanStrings.hemoglobinLabel,
        visit.hemoglobinGmDl != null ? '${visit.hemoglobinGmDl} g/dL' : null,
      ),
      _FoundEntry(
        AncScanStrings.glucoseLabel,
        visit.glucoseMmolL != null ? '${visit.glucoseMmolL} mmol/L' : null,
      ),
      _FoundEntry(
        AncScanStrings.pulseLabel,
        visit.pulseBpm != null ? '${visit.pulseBpm} bpm' : null,
      ),
      _FoundEntry(
        AncScanStrings.temperatureLabel,
        visit.temperatureF != null ? '${visit.temperatureF} °F' : null,
      ),
      _FoundEntry(
        AncScanStrings.urinaryAlbuminLabel,
        visit.urinaryAlbuminPresent != null
            ? (visit.urinaryAlbuminPresent! ? '+' : '-')
            : null,
      ),
      _FoundEntry(
        AncScanStrings.urinaryBilirubinLabel,
        visit.urinaryBilirubinPresent != null
            ? (visit.urinaryBilirubinPresent! ? '+' : '-')
            : null,
      ),
      _FoundEntry(
        AncScanStrings.edemaLabel,
        visit.edemaPresent != null ? (visit.edemaPresent! ? '+' : '-') : null,
      ),
      _FoundEntry(
        AncScanStrings.ttTdLabel,
        visit.ttTdCompleted != null ? (visit.ttTdCompleted! ? '✓' : '✗') : null,
      ),
    ];
  }

  Future<void> _runExtraction(File image) async {
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    setState(() {
      _preview = image;
      _cameraReady = false;
    });

    AncVisitExtractionResult result;
    try {
      result =
          await widget.repository.extractAncVisit(image, widget.visitNumber);
    } on AncVisitExtractionException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      return;
    }

    final visit = result.visit;
    if (visit == null || !visit.anyFieldFound) {
      if (!mounted) return;
      setState(() => _error = EpiStrings.scanFailed);
      return;
    }

    if (mounted) {
      setState(() {
        _columnBox = visit.columnBoundingBox;
        _found.add(
            _FoundEntry(AncScanStrings.visitColumnFound(widget.visitNumber), ''));
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 260));

    // Shows the literal handwriting BEFORE the parsed fields below, so the
    // reveal reads as one flow — "here's what's written" then "here's what
    // we parsed from it" — rather than a disconnected note trailing after
    // every field. Bengali digits transliterated to ASCII so a misread
    // (e.g. ৩/৮/৯/০ confusion) is visible without reading Bengali numeral
    // shapes. One block for the whole visit column, not per-field — the
    // backend tracks rawText per visit, not per individual field (see
    // AncVisitExtraction's doc comment), so it can't yet sit next to one
    // specific line like Hemoglobin alone.
    if (visit.rawText != null && visit.rawText!.isNotEmpty) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      setState(() => _found.add(_FoundEntry(
            AncScanStrings.asWrittenLabel,
            EpiCardScanner.normalizeBengaliDigits(visit.rawText!),
            isRawText: true,
            flagged: result.flagged,
          )));
    }

    for (final entry in _entriesFor(visit)) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      setState(() => _found.add(entry));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    if (_preview != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _error != null
              ? _ErrorOverlay(
                  image: _preview!,
                  message: _error!,
                  onDismiss: () => Navigator.of(context).pop(null),
                )
              : _ScanningPreview(
                  image: _preview!,
                  sweep: _sweepCtrl,
                  found: _found,
                  visitNumber: widget.visitNumber,
                  columnBox: _columnBox,
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_cameraReady && _controller != null)
              Positioned.fill(child: CameraPreview(_controller!))
            else if (_cameraUnavailable)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    EpiStrings.scanCameraUnavailable,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              )
            else
              const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined,
                        color: Colors.white, size: 32),
                    onPressed: _busy ? null : _pickFromGallery,
                  ),
                  if (_cameraReady)
                    GestureDetector(
                      onTap: _busy ? null : _capture,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 3),
                              )
                            : const Icon(Icons.circle,
                                color: Colors.white, size: 52),
                      ),
                    )
                  else
                    const SizedBox(width: 72),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves a [File] image's natural pixel dimensions — needed to map the
/// backend's normalized column bounding box onto screen coordinates once
/// `Image.file` has laid it out with `BoxFit.contain` (which letterboxes
/// unless the photo's aspect ratio exactly matches the available space).
Future<Size> _resolveImageSize(File file) {
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
/// `BoxFit.contain`-laid-out image, given the container size it's
/// rendered into and the image's natural pixel size.
Rect _containFitRect(Size container, Size imageSize, AncColumnBoundingBox box) {
  final scale = (container.width / imageSize.width <
          container.height / imageSize.height)
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

/// Captured image under a sweeping scan line while extraction runs —
/// mirrors `EpiCardScanScreen`'s `_ScanningPreview`. When [columnBox] is
/// non-null (the backend's 3 reads reached consensus on where the targeted
/// visit column is), draws a translucent highlight over it once the image's
/// natural size is known — advisory only, see [AncColumnBoundingBox]'s doc
/// comment.
class _ScanningPreview extends StatelessWidget {
  const _ScanningPreview({
    required this.image,
    required this.sweep,
    required this.found,
    required this.visitNumber,
    this.columnBox,
  });

  final File image;
  final Animation<double> sweep;
  final List<_FoundEntry> found;
  final int visitNumber;
  final AncColumnBoundingBox? columnBox;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Image.file(image, fit: BoxFit.contain)),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.25)),
        ),
        if (columnBox != null)
          Positioned.fill(
            child: FutureBuilder<Size>(
              future: _resolveImageSize(image),
              builder: (context, snapshot) {
                final imgSize = snapshot.data;
                if (imgSize == null) return const SizedBox.shrink();
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final rect = _containFitRect(
                        constraints.biggest, imgSize, columnBox!);
                    // A fresh inner Stack — `Positioned` only works as a
                    // direct Stack child, and the outer screen Stack is too
                    // far up the tree (through FutureBuilder/LayoutBuilder,
                    // neither of which is a Stack) to apply to directly.
                    return Stack(
                      children: [
                        Positioned.fromRect(
                          rect: rect,
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF34D399).withValues(alpha: 0.18),
                              border: Border.all(
                                  color: const Color(0xFF34D399), width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: sweep,
            builder: (context, _) {
              return Align(
                alignment: Alignment(0, sweep.value * 2 - 1),
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34D399),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF34D399).withValues(alpha: 0.6),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          top: 24,
          left: 16,
          right: 16,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '📷 ${AncScanStrings.scanningVisit(visitNumber)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        if (found.isNotEmpty)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: _RevealTable(entries: found),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              ),
              const SizedBox(height: 12),
              Text(
                EpiStrings.scanReadingCard,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Wraps the revealed entries into one bordered "box table": a
/// column-located caption line, then a box containing the raw-text row
/// (full width, when present) and a Field/Value table for every scanned
/// field — rows stagger in as the scan "finds" them, same timing as before,
/// just laid out as table rows instead of floating pills.
class _RevealTable extends StatelessWidget {
  const _RevealTable({required this.entries});

  final List<_FoundEntry> entries;

  @override
  Widget build(BuildContext context) {
    final markers = entries.where((e) => !e.isRawText && e.value == '');
    final rawTextEntries = entries.where((e) => e.isRawText);
    final fieldEntries = entries.where((e) => !e.isRawText && e.value != '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in markers)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _animatedRow(
              m.label,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF34D399), size: 16),
                  const SizedBox(width: 6),
                  Text(m.label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        if (rawTextEntries.isNotEmpty || fieldEntries.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in rawTextEntries) _RawTextRow(r),
                if (fieldEntries.isNotEmpty) const _TableHeaderRow(),
                for (final (i, f) in fieldEntries.indexed)
                  _TableFieldRow(
                    f,
                    showDivider: i < fieldEntries.length - 1,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _animatedRow(String key, Widget child) => TweenAnimationBuilder<double>(
        key: ValueKey(key),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (context, t, c) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: c),
        ),
        child: child,
      );
}

/// Full-width row at the top of the table showing the verbatim handwriting
/// (digit-transliterated) — see [_FoundEntry]'s doc comment.
class _RawTextRow extends StatelessWidget {
  const _RawTextRow(this.entry);

  final _FoundEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.flagged ? const Color(0xFFFBBF24) : Colors.white70;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white24, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.text_snippet_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${entry.label}: ${entry.value}',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white24, width: 1)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('FIELD', style: style)),
          Expanded(flex: 2, child: Text('VALUE', style: style)),
        ],
      ),
    );
  }
}

class _TableFieldRow extends StatelessWidget {
  const _TableFieldRow(this.entry, {required this.showDivider});

  final _FoundEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final found = entry.value != null;
    final color = found ? Colors.white : const Color(0xFFFBBF24);
    return TweenAnimationBuilder<double>(
      key: ValueKey(entry.label),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 6), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(
                  bottom: BorderSide(color: Colors.white12, width: 1))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(entry.label,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                found ? entry.value! : AncScanStrings.notFoundValue,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A revealed field's label + formatted value (null = not found on the
/// card; `''` is reserved for the column-located marker, not a real field).
/// [isRawText] marks the single "as written on card" block (verbatim
/// handwriting, digit-transliterated) — rendered distinctly from a normal
/// found/not-found field line; [flagged] (only meaningful when
/// [isRawText] is true) emphasizes it in amber when the card was flagged.
class _FoundEntry {
  const _FoundEntry(
    this.label,
    this.value, {
    this.isRawText = false,
    this.flagged = false,
  });

  final String label;
  final String? value;
  final bool isRawText;
  final bool flagged;
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({
    required this.image,
    required this.message,
    required this.onDismiss,
  });

  final File image;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Image.file(image, fit: BoxFit.contain)),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.6)),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(EpiStrings.cancel,
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: onDismiss,
          ),
        ),
      ],
    );
  }
}
