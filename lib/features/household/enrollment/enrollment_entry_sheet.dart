import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_repository.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/patient.dart';
import 'enrollment_controller.dart';
import 'nid_ocr_service.dart';
import 'patient_lookup_repository.dart';

// Design tokens — prototype-aligned
const _teal = Color(0xFF6EE7B7);
const _navy = Color(0xFF1B2B5E);
const _muted = Color(0xFF6B7280);

/// Full-screen dark overlay with NID camera viewfinder.
///
/// Two states:
///   1. [_OverlayState.scanner] — camera viewfinder, sweep animation, capture
///      button, "Create Household" fallback card, Cancel.
///   2. [_OverlayState.postScan] — slide-up white sheet with scanned identity
///      card and two household linking options.
///
/// Rest of enrollment (form screens) uses GoRouter routes.
void showEnrollmentEntrySheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    enableDrag: false,
    builder: (_) => ChangeNotifierProvider(
      create: (ctx) => EnrollmentController(
        auth: ctx.read<AuthRepository>(),
        apiClient: ctx.read<ApiClient>(),
      ),
      child: const _EnrollmentOverlay(),
    ),
  );
}

enum _OverlayState { scanner, postScan }

class _EnrollmentOverlay extends StatefulWidget {
  const _EnrollmentOverlay();

  @override
  State<_EnrollmentOverlay> createState() => _EnrollmentOverlayState();
}

class _EnrollmentOverlayState extends State<_EnrollmentOverlay>
    with SingleTickerProviderStateMixin {
  _OverlayState _overlayState = _OverlayState.scanner;
  bool _isScanning = false;
  NidCardData? _scanned;

  /// Non-null when the scanned NID already belongs to a registered patient.
  Patient? _existingPatient;

  final NidOcrService _ocr = NidOcrService();

  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _cameraUnavailable = false;

  late final AnimationController _sweepCtrl;
  late final Animation<double> _sweep;

  @override
  void initState() {
    super.initState();
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _sweep = Tween<double>(begin: 0.06, end: 0.92).animate(
      CurvedAnimation(parent: _sweepCtrl, curve: Curves.easeInOut),
    );
    _initCamera();
  }

  /// Request camera permission and start the live preview inside the overlay.
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
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } on CameraException catch (e) {
      debugPrint('EnrollmentOverlay: camera init failed: $e');
      if (mounted) setState(() => _cameraUnavailable = true);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _sweepCtrl.dispose();
    super.dispose();
  }

  /// Capture a frame from the live preview and read the NID number from it.
  Future<void> _handleCapture() async {
    final controller = _cameraController;
    if (_isScanning || controller == null || !_cameraReady) return;
    setState(() => _isScanning = true);

    NidScanResult result;
    try {
      final frame = await controller.takePicture();
      result = await _ocr.extractNidFromImage(frame.path);
    } on CameraException catch (e) {
      debugPrint('EnrollmentOverlay: takePicture failed: $e');
      result = const NidScanResult(NidScanStatus.error);
    }
    if (!mounted) return;
    setState(() => _isScanning = false);

    switch (result.status) {
      case NidScanStatus.success:
        setState(() {
          _scanned = result.data;
          _existingPatient = null;
          _overlayState = _OverlayState.postScan;
        });
        final nid = result.data?.nidNumber;
        if (nid != null) _lookupExisting(nid);
      case NidScanStatus.notFound:
        _showSnack(EnrollmentStrings.nidScanNotFound);
      case NidScanStatus.error:
        _showSnack(EnrollmentStrings.nidScanError);
      case NidScanStatus.cancelled:
        break;
    }
  }

  /// Best-effort remote check: does this scanned NID already belong to a
  /// registered patient? Surfaces a de-duplication banner on the post-scan
  /// sheet. Offline / transport failures degrade silently.
  Future<void> _lookupExisting(String nid) async {
    final repo = context.read<PatientLookupRepository>();
    try {
      final patient = await repo.lookupByNid(nid);
      if (!mounted || patient == null) return;
      setState(() => _existingPatient = patient);
    } on DioException catch (_) {
      // Offline or transport error — no duplicate warning, no user-facing error.
    } on ApiException catch (e) {
      debugPrint('EnrollmentOverlay: patient lookup failed: $e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenH,
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Stack(
            children: [
              _ScannerBody(
                isScanning: _isScanning,
                sweep: _sweep,
                readingCard: _overlayState == _OverlayState.postScan,
                cameraController: _cameraReady ? _cameraController : null,
                cameraUnavailable: _cameraUnavailable,
                onCapture: _handleCapture,
                onCreateHousehold: () {
                  Navigator.of(context).pop();
                  context.push('/household/enrollment/create');
                },
                onCancel: () => Navigator.of(context).pop(),
              ),
              if (_overlayState == _OverlayState.postScan)
                _PostScanSheet(
                  data: _scanned,
                  existing: _existingPatient,
                  onLinkExisting: () => Navigator.of(context).pop(),
                  onCreateNew: () {
                    Navigator.of(context).pop();
                    context.push(
                      '/household/enrollment/head-info',
                      extra: {
                        'fromNidScan': true,
                        'nidNumber': _scanned?.nidNumber,
                        'name': _scanned?.name,
                        'dateOfBirth': _scanned?.dateOfBirth,
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Scanner body ─────────────────────────────────────────────────────────────

class _ScannerBody extends StatelessWidget {
  const _ScannerBody({
    required this.isScanning,
    required this.sweep,
    required this.readingCard,
    required this.cameraController,
    required this.cameraUnavailable,
    required this.onCapture,
    required this.onCreateHousehold,
    required this.onCancel,
  });

  final bool isScanning;
  final bool readingCard;
  final Animation<double> sweep;

  /// Live preview controller, or null while initialising / unavailable.
  final CameraController? cameraController;
  final bool cameraUnavailable;
  final VoidCallback onCapture;
  final VoidCallback onCreateHousehold;
  final VoidCallback onCancel;

  bool get _canCapture =>
      !isScanning && !readingCard && cameraController != null;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        children: [
          // Title
          Text(
            readingCard
                ? '🔍 Reading card details…'
                : 'Take a Photo of NID Card',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            readingCard
                ? 'Reading the NID number…'
                : cameraUnavailable
                    ? 'Camera unavailable — use Create Household below'
                    : 'Position the card within the frame',
            style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Viewfinder with live camera preview
          _Viewfinder(
            isScanning: isScanning,
            sweep: sweep,
            cameraController: cameraController,
            cameraUnavailable: cameraUnavailable,
          ),
          const SizedBox(height: 10),
          const Text(
            'Bangladesh National ID Card · Smart NID · Birth Registration',
            style: TextStyle(fontSize: 11, color: Color(0x73FFFFFF)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          // Capture button
          GestureDetector(
            onTap: _canCapture ? onCapture : null,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 4,
                ),
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: _canCapture
                          ? const Color(0xFF1a1a2e)
                          : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: (isScanning || readingCard)
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1a1a2e),
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: Color(0xFF1a1a2e),
                          size: 24,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap to capture',
            style: TextStyle(fontSize: 11, color: Color(0x80FFFFFF)),
          ),
          const SizedBox(height: 20),
          // Or divider
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0x66FFFFFF),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Create Household card
          GestureDetector(
            onTap: onCreateHousehold,
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.home_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create Household',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Register a new household manually',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0x8CFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0x80FFFFFF),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Cancel
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Viewfinder ───────────────────────────────────────────────────────────────

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.isScanning,
    required this.sweep,
    required this.cameraController,
    required this.cameraUnavailable,
  });

  final bool isScanning;
  final Animation<double> sweep;
  final CameraController? cameraController;
  final bool cameraUnavailable;

  static const double _inset = 10;
  static const double _cSize = 28;
  static const double _cThick = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = w / 1.586; // credit-card landscape ratio
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              // Live camera preview (cover-fit into the card rect) or a
              // translucent placeholder while the camera initialises.
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: cameraController != null
                      ? FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: cameraController!.value.previewSize?.height ??
                                w,
                            height:
                                cameraController!.value.previewSize?.width ?? h,
                            child: CameraPreview(cameraController!),
                          ),
                        )
                      : Container(
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                ),
              ),
              // Inner dashed hint
              Positioned(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: (isScanning || cameraController != null)
                      ? null
                      : Center(
                          child: Icon(
                            cameraUnavailable
                                ? Icons.no_photography_outlined
                                : Icons.credit_card_outlined,
                            color: const Color(0x26FFFFFF),
                            size: 40,
                          ),
                        ),
                ),
              ),
              // Corner brackets
              _corner(top: _inset, left: _inset),
              _corner(
                top: _inset,
                left: w - _inset - _cSize,
                flipH: true,
              ),
              _corner(
                top: h - _inset - _cSize,
                left: _inset,
                flipV: true,
              ),
              _corner(
                top: h - _inset - _cSize,
                left: w - _inset - _cSize,
                flipH: true,
                flipV: true,
              ),
              // Sweep line
              if (!isScanning)
                AnimatedBuilder(
                  animation: sweep,
                  builder: (context2, value) => Positioned(
                    top: sweep.value * h,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            _teal,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Scanning spinner
              if (isScanning)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: _teal,
                        strokeWidth: 2.5,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Scanning...',
                        style: TextStyle(
                          color: Color(0xB3FFFFFF),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static Widget _corner({
    required double top,
    required double left,
    bool flipH = false,
    bool flipV = false,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: SizedBox(
        width: _cSize,
        height: _cSize,
        child: CustomPaint(
          painter: _CornerPainter(flipH: flipH, flipV: flipV, thick: _cThick),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.flipH,
    required this.flipV,
    required this.thick,
  });

  final bool flipH, flipV;
  final double thick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _teal
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final x = flipH ? size.width : 0.0;
    final y = flipV ? size.height : 0.0;
    final xEnd = flipH ? 0.0 : size.width;
    final yEnd = flipV ? 0.0 : size.height;

    canvas.drawLine(Offset(x, y), Offset(xEnd, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, yEnd), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ─── Post-scan bottom sheet ───────────────────────────────────────────────────

class _PostScanSheet extends StatelessWidget {
  const _PostScanSheet({
    required this.data,
    required this.existing,
    required this.onLinkExisting,
    required this.onCreateNew,
  });

  final NidCardData? data;

  /// Non-null when the scanned NID matches a patient already registered.
  final Patient? existing;
  final VoidCallback onLinkExisting;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context) {
    final name = data?.name;
    final dob = data?.dateOfBirth;
    final nid = data?.nidNumber;
    final existingName = existing?.name;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Color(0x2E000000),
              blurRadius: 32,
              offset: Offset(0, -8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NID card scanned',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _navy,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '✦ Details read on-device',
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onLinkExisting,
                  child: const Icon(Icons.close, color: _muted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Navy gradient card with the auto-filled fields
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_navy, Color(0xFF2d3f7a)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NidField(
                    label: 'NAME',
                    value: name ?? 'Not read — enter manually',
                    dim: name == null,
                  ),
                  const _NidDivider(),
                  _NidField(
                    label: 'DATE OF BIRTH',
                    value: dob ?? 'Not read — enter manually',
                    dim: dob == null,
                  ),
                  const _NidDivider(),
                  _NidField(
                    label: 'NID NUMBER',
                    value: nid ?? '—',
                    emphasise: true,
                  ),
                ],
              ),
            ),
            // Existing-registration de-duplication banner
            if (existing != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  border: Border.all(color: const Color(0xFF3B82F6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.badge_outlined,
                        size: 16, color: Color(0xFF1D4ED8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EnrollmentStrings.existingPatientFound(
                                existingName ?? ''),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            EnrollmentStrings.existingPatientHint,
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF1D4ED8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Father / Mother cannot be OCR'd (Bengali only) — set expectation.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                border: Border.all(color: const Color(0xFFFED7AA)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 15, color: Color(0xFF9A3412)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Father's & mother's names are printed in Bangla — "
                      'please type them in.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9A3412)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Link to household',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1a1a2e),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _SheetOptionButton(
              icon: Icons.link_rounded,
              title: 'Link to existing household',
              subtitle: 'Search and select from your households',
              bgColor: const Color(0xFFF8F9FC),
              onTap: onLinkExisting,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
              ],
            ),
            const SizedBox(height: 10),
            _SheetOptionButton(
              icon: Icons.home_outlined,
              title: 'Create new household',
              subtitle: 'Register this member under a new household',
              bgColor: Colors.white,
              bordered: true,
              onTap: onCreateNew,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOptionButton extends StatelessWidget {
  const _SheetOptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.onTap,
    this.bordered = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color bgColor;
  final VoidCallback onTap;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: bordered ? _navy : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: _navy, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF9CA3AF),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// One label/value row inside the navy scanned-details card.
class _NidField extends StatelessWidget {
  const _NidField({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.dim = false,
  });

  final String label;
  final String value;
  final bool emphasise;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0x80FFFFFF),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasise ? 20 : 14,
            fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: emphasise ? 1.5 : 0,
            fontStyle: dim ? FontStyle.italic : FontStyle.normal,
            color: dim ? const Color(0x80FFFFFF) : Colors.white,
          ),
        ),
      ],
    );
  }
}

class _NidDivider extends StatelessWidget {
  const _NidDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}
