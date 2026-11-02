import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_strings.dart';
import '../immunisation/card_extraction_transport.dart' show CardBoundingBox;
import '../immunisation/card_highlight_overlay.dart';
import 'ncd_visit_extraction_models.dart';
import 'ncd_visit_extraction_repository.dart';

/// Full-screen "scan" surface for the NCD BP/glucose follow-up card — a live
/// rear-camera viewfinder with a capture button and an in-frame "upload from
/// gallery" affordance, targeted at one specific visit row ([visitNumber])
/// since that's the one the SK is currently recording. Unlike ANC's
/// column-per-visit card, the NCD card is row-per-visit — confirmed against
/// a real scanned card sample, not assumed from the app's form shape alone.
///
/// After capture, shows the photo with a sweeping scan-line and reveals each
/// found field one by one (same box-table reveal as
/// [AncCardScanScreen]/`EpiCardScanScreen`) — then pops the already-complete
/// [NcdVisitExtractionResult].
class NcdCardScanScreen extends StatefulWidget {
  const NcdCardScanScreen({
    super.key,
    required this.visitNumber,
    required this.repository,
  });

  /// Which visit row to target (1-indexed, top-to-bottom dated rows on the
  /// card).
  final int visitNumber;

  final NcdVisitExtractionRepository repository;

  @override
  State<NcdCardScanScreen> createState() => _NcdCardScanScreenState();
}

class _NcdCardScanScreenState extends State<NcdCardScanScreen>
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
  CardBoundingBox? _rowBox;

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
      debugPrint('NcdCardScanScreen: camera init failed: $e');
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
      debugPrint('NcdCardScanScreen: takePicture failed: $e');
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
  /// scan looked for. `visitDate` is omitted — no mobile form field to
  /// confirm it against (same reasoning as ANC's `visitDate` omission).
  List<_FoundEntry> _entriesFor(NcdVisitExtraction visit) {
    String bp() => '${visit.bpSystolic}/${visit.bpDiastolic}';
    String glucose() {
      final value = '${visit.glucoseMmolL} mmol/L';
      return visit.glucoseType != null
          ? '$value (${visit.glucoseType!.toUpperCase()})'
          : value;
    }

    return [
      _FoundEntry(
        NcdScanStrings.weightLabel,
        visit.weightKg != null ? '${visit.weightKg} kg' : null,
      ),
      _FoundEntry(
        NcdScanStrings.heightLabel,
        visit.heightCm != null ? '${visit.heightCm} cm' : null,
      ),
      _FoundEntry(
        NcdScanStrings.bpLabel,
        visit.bpSystolic != null && visit.bpDiastolic != null ? bp() : null,
      ),
      _FoundEntry(
        NcdScanStrings.glucoseLabel,
        visit.glucoseMmolL != null ? glucose() : null,
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

    NcdVisitExtractionResult result;
    try {
      result =
          await widget.repository.extractNcdVisit(image, widget.visitNumber);
    } on NcdVisitExtractionException catch (e) {
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
        _rowBox = visit.rowBoundingBox;
        _found.add(
            _FoundEntry(NcdScanStrings.visitRowFound(widget.visitNumber), ''));
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 260));

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
                  rowBox: _rowBox,
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

            // Card-shaped alignment guide + hint (only over a live preview).
            if (_cameraReady)
              CardAlignmentGuide(hint: EpiStrings.scanFrameHint),

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

/// Captured image under a sweeping scan line while extraction runs —
/// mirrors `AncCardScanScreen`'s `_ScanningPreview`. When [rowBox] is
/// non-null (the backend's 3 reads reached consensus on where the targeted
/// visit row is), draws a translucent highlight over it once the image's
/// natural size is known — advisory only, see [CardBoundingBox]'s doc
/// comment.
class _ScanningPreview extends StatelessWidget {
  const _ScanningPreview({
    required this.image,
    required this.sweep,
    required this.found,
    required this.visitNumber,
    this.rowBox,
  });

  final File image;
  final Animation<double> sweep;
  final List<_FoundEntry> found;
  final int visitNumber;
  final CardBoundingBox? rowBox;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Image.file(image, fit: BoxFit.contain)),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.25)),
        ),
        if (rowBox != null)
          Positioned.fill(
            child: CardHighlightOverlay(image: image, box: rowBox!),
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
                '📷 ${NcdScanStrings.scanningVisit(visitNumber)}',
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
/// row-located caption line, then a box containing a Field/Value table for
/// every scanned field — rows stagger in as the scan "finds" them, same
/// timing/layout as `AncCardScanScreen`'s `_RevealTable`.
class _RevealTable extends StatelessWidget {
  const _RevealTable({required this.entries});

  final List<_FoundEntry> entries;

  @override
  Widget build(BuildContext context) {
    final markers = entries.where((e) => e.value == '');
    final fieldEntries = entries.where((e) => e.value != '');

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
        if (fieldEntries.isNotEmpty)
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
                const _TableHeaderRow(),
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
                found ? entry.value! : NcdScanStrings.notFoundValue,
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
/// card; `''` is reserved for the row-located marker, not a real field).
class _FoundEntry {
  const _FoundEntry(this.label, this.value);

  final String label;
  final String? value;
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
