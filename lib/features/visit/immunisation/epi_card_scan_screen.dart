import 'dart:io';

import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/i18n/app_date_format.dart';
import 'card_highlight_overlay.dart';
import 'epi_card_scanner.dart';
import 'epi_date_extraction_models.dart' show UnmatchedVaccineRow;
import 'epi_date_extraction_repository.dart';

/// Full-screen "scan" surface for the EPI card — a live rear-camera viewfinder
/// with a capture button and an in-frame "upload from gallery" affordance, the
/// same shape UPI apps use.
///
/// After an image is captured/picked it shows that image with a sweeping
/// scan-line while OCR runs — Gemini vision when online (names + handwritten
/// dates in one call), ML Kit + Tesseract offline (names only) — then pops
/// the resulting [EpiScanResult] back to the caller (or null if dismissed).
/// Which engine ran is shown as a small badge over the preview.
///
/// Mirrors the app's existing NID scan pattern (`enrollment_entry_sheet.dart`):
/// camera permission via `permission_handler`, `availableCameras()` → back lens,
/// `CameraController`. If the camera is unavailable (denied / none / error), it
/// degrades to a gallery-only surface so the SK can still upload a photo.
class EpiCardScanScreen extends StatefulWidget {
  const EpiCardScanScreen({
    super.key,
    required this.targetCodes,
    required this.codeLabels,
    required this.dateExtractionRepo,
  });

  /// Vaccine codes the OCR should match against (the timeline's full set).
  final List<String> targetCodes;

  /// Vaccine code → friendly display label, for the "✓ … found" reveal.
  final Map<String, String> codeLabels;

  /// Online date-extraction client — used when connectivity is available;
  /// see [EpiCardScanner.scanImageAuto].
  final EpiDateExtractionRepository dateExtractionRepo;

  @override
  State<EpiCardScanScreen> createState() => _EpiCardScanScreenState();
}

class _EpiCardScanScreenState extends State<EpiCardScanScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _cameraReady = false;
  bool _cameraUnavailable = false;
  bool _busy = false;

  /// Non-null once an image is captured/picked — drives the preview + OCR phase.
  File? _preview;
  late final AnimationController _sweepCtrl;

  /// Matched vaccine labels revealed one-by-one as the scan "finds" them.
  final List<_FoundEntry> _found = [];

  /// Online path only: vaccines with no legible date, for row highlighting.
  List<UnmatchedVaccineRow> _unmatchedRows = const [];

  /// Which engine is running this scan — decided once, before OCR starts,
  /// from the connectivity check in [_runOcr].
  EpiScanEngine _engine = EpiScanEngine.mlKitOffline;

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
      debugPrint('EpiCardScanScreen: camera init failed: $e');
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
      await _runOcr(File(frame.path));
    } on CameraException catch (e) {
      debugPrint('EpiCardScanScreen: takePicture failed: $e');
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
      setState(() => _busy = false); // cancelled — re-enable controls
      return;
    }
    await _runOcr(File(picked.path));
  }

  /// Shows the chosen image with the scan-line sweep while OCR runs — Gemini
  /// vision when online, ML Kit + Tesseract offline — then pops the result.
  /// Releases the camera first so the preview is stable.
  Future<void> _runOcr(File image) async {
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;

    // Decide the engine up front (same check `scanImageAuto` makes
    // internally) so the badge is visible for the whole "Reading card…"
    // phase, not just after the call completes.
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity.any((r) => r != ConnectivityResult.none);
    if (!mounted) return;
    setState(() {
      _preview = image;
      _cameraReady = false;
      _engine =
          isOnline ? EpiScanEngine.geminiVision : EpiScanEngine.mlKitOffline;
    });

    EpiScanResult result;
    try {
      result = await EpiCardScanner.scanImageAuto(
        image,
        widget.targetCodes,
        widget.dateExtractionRepo,
      );
    } on Object catch (e) {
      // Any OCR failure degrades to an empty result → the timeline shows the
      // amber "couldn't read card" banner rather than an unhandled error.
      debugPrint('EpiCardScanScreen: OCR failed: $e');
      result = const EpiScanResult(matchedCodes: [], rawText: '');
    }
    if (!mounted) return;
    // The offline fallback inside scanImageAuto may have silently kicked in
    // (Gemini call failed mid-flight) — reflect the engine it actually used.
    if (mounted && result.engine != _engine) {
      setState(() => _engine = result.engine);
    }
    if (mounted && result.unmatchedRows.isNotEmpty) {
      setState(() => _unmatchedRows = result.unmatchedRows);
    }

    // Reveal each matched vaccine one-by-one over the preview — the scan
    // "finding" them — then pop the (already-complete) result. Online
    // (Gemini) matches carry a per-vaccine date; offline matches never do,
    // so [_FoundEntry.date] is simply null there.
    final entries = <_FoundEntry>[];
    final seenLabels = <String>{};
    for (final code in result.matchedCodes) {
      final label = widget.codeLabels[code] ?? code;
      if (!seenLabels.add(label)) continue;
      final date = result.dateByCode[code];
      entries.add(_FoundEntry(
        name: label,
        date: date != null ? AppDateFormat.dayMonthYear(date) : null,
      ));
    }
    for (final entry in entries) {
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      setState(() => _found.add(entry));
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    // OCR phase — show the captured image with the sweeping scan line.
    if (_preview != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _ScanningPreview(
            image: _preview!,
            sweep: _sweepCtrl,
            found: _found,
            engine: _engine,
            unmatchedRows: _unmatchedRows,
          ),
        ),
      );
    }

    // Capture phase — live camera + controls.
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_cameraReady && _controller != null)
              Positioned.fill(child: CameraPreview(_controller!))
            else if (_cameraUnavailable)
              const _CameraUnavailable()
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Card-shaped alignment guide + hint (only over a live preview).
            if (_cameraReady) const _AlignmentGuide(),

            // Close button.
            Positioned(
              top: 8,
              left: 8,
              child: _RoundIconButton(
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),

            // Bottom controls: gallery upload (left) + capture (center).
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: _BottomControls(
                showCapture: _cameraReady,
                busy: _busy,
                onUpload: _pickFromGallery,
                onCapture: _capture,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Captured image under a sweeping scan line while OCR runs — the document
/// scanner "reading" affordance.
class _ScanningPreview extends StatelessWidget {
  const _ScanningPreview({
    required this.image,
    required this.sweep,
    required this.found,
    required this.engine,
    this.unmatchedRows = const [],
  });

  final File image;
  final Animation<double> sweep;
  final List<_FoundEntry> found;
  final EpiScanEngine engine;

  /// Vaccines with no legible date — highlighted in amber directly on the
  /// photo, so the SK can see which doses are missing at a glance. Only
  /// codes the backend's independent reads agreed closely enough on a row
  /// location for; others are silently omitted (no highlight) rather than
  /// guessed (see `UnmatchedVaccineRow`'s doc comment).
  final List<UnmatchedVaccineRow> unmatchedRows;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(image, fit: BoxFit.contain),
        ),
        // Dim scrim so the reveal chips read over any image.
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.25)),
        ),
        if (unmatchedRows.isNotEmpty)
          Positioned.fill(
            child: CardHighlightOverlays(
              image: image,
              boxes: [
                for (final row in unmatchedRows)
                  if (row.rowBoundingBox != null) row.rowBoundingBox!,
              ],
              color: const Color(0xFFFBBF24),
            ),
          ),
        // Sweeping scan line.
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
        // Which engine is reading this card.
        Positioned(
          top: 24,
          left: 16,
          right: 16,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _EngineBadge(engine: engine),
          ),
        ),
        // "✓ vaccine found" reveal — grows as OCR results stream in, laid
        // out as a bordered Vaccine/Date table (mirrors AncCardScanScreen's
        // _RevealTable).
        if (found.isNotEmpty)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: _EpiRevealTable(entries: found),
          ),
        // "Reading card…" label.
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

/// Small pill naming which engine is reading this card — "⚡ Gemini Vision"
/// (online: names + handwritten dates) or "📷 ML Kit (offline)" (names only).
class _EngineBadge extends StatelessWidget {
  const _EngineBadge({required this.engine});

  final EpiScanEngine engine;

  @override
  Widget build(BuildContext context) {
    final isGemini = engine == EpiScanEngine.geminiVision;
    final label =
        isGemini ? EpiStrings.scanEngineGemini : EpiStrings.scanEngineOffline;
    final icon = isGemini ? '⚡' : '📷';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$icon $label',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Bordered "box table" of every matched vaccine and its date — mirrors
/// AncCardScanScreen's `_RevealTable`. Every entry here is a vaccine the
/// scan actually matched (unmatched vaccines simply never appear), so
/// there's no "not found" row here — a missing [date] just shows as
/// "No date" in the Date column, not an amber warning.
class _EpiRevealTable extends StatelessWidget {
  const _EpiRevealTable({required this.entries});

  final List<_FoundEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _EpiTableHeaderRow(),
          for (final (i, e) in entries.indexed)
            _EpiTableRow(e, showDivider: i < entries.length - 1),
        ],
      ),
    );
  }
}

class _EpiTableHeaderRow extends StatelessWidget {
  const _EpiTableHeaderRow();

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
          Expanded(flex: 3, child: Text('VACCINE', style: style)),
          Expanded(flex: 2, child: Text('DATE', style: style)),
        ],
      ),
    );
  }
}

class _EpiTableRow extends StatelessWidget {
  const _EpiTableRow(this.entry, {required this.showDivider});

  final _FoundEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(entry.name),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF34D399), size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(entry.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                entry.date ?? EpiStrings.scanNoDateFound,
                style: TextStyle(
                  color: entry.date != null
                      ? const Color(0xFF34D399)
                      : Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A matched vaccine's display label plus its extracted date (online/Gemini
/// path only — always null offline).
class _FoundEntry {
  const _FoundEntry({required this.name, this.date});

  final String name;
  final String? date;
}

class _AlignmentGuide extends StatelessWidget {
  const _AlignmentGuide();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1.5,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            EpiStrings.scanFrameHint,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.showCapture,
    required this.busy,
    required this.onUpload,
    required this.onCapture,
  });

  final bool showCapture;
  final bool busy;
  final VoidCallback onUpload;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Gallery / upload.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundIconButton(
              icon: Icons.photo_library_outlined,
              onTap: busy ? null : onUpload,
            ),
            const SizedBox(height: 6),
            Text(
              EpiStrings.scanUploadLabel,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),

        // Capture — only when a live preview is available.
        if (showCapture)
          GestureDetector(
            onTap: busy ? null : onCapture,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.2),
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 3),
                    )
                  : const Icon(Icons.circle, color: Colors.white, size: 52),
            ),
          )
        else
          const SizedBox(width: 72),

        // Spacer to balance the row against the left control.
        const SizedBox(width: 48),
      ],
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera_outlined,
                color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              EpiStrings.scanCameraUnavailable,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
