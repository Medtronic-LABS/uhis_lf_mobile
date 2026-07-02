import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'enrollment_controller.dart';

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
      create: (_) => EnrollmentController(),
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
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    await context.read<EnrollmentController>().mockNidScan();
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _overlayState = _OverlayState.postScan;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scanResult = context.watch<EnrollmentController>().nidScanResult;
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
                onCapture: _handleCapture,
                onCreateHousehold: () {
                  Navigator.of(context).pop();
                  context.push('/household/enrollment/create');
                },
                onCancel: () => Navigator.of(context).pop(),
              ),
              if (_overlayState == _OverlayState.postScan)
                _PostScanSheet(
                  scanResult: scanResult,
                  onLinkExisting: () => Navigator.of(context).pop(),
                  onCreateNew: () {
                    Navigator.of(context).pop();
                    context.push(
                      '/household/enrollment/head-info',
                      extra: {'fromNidScan': true},
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
    required this.onCapture,
    required this.onCreateHousehold,
    required this.onCancel,
  });

  final bool isScanning;
  final bool readingCard;
  final Animation<double> sweep;
  final VoidCallback onCapture;
  final VoidCallback onCreateHousehold;
  final VoidCallback onCancel;

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
                ? 'AI extracting name, NID number, DOB'
                : 'Position the card within the frame',
            style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Viewfinder
          _Viewfinder(isScanning: isScanning, sweep: sweep),
          const SizedBox(height: 10),
          const Text(
            'Bangladesh National ID Card · Smart NID · Birth Registration',
            style: TextStyle(fontSize: 11, color: Color(0x73FFFFFF)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          // Capture button
          GestureDetector(
            onTap: (isScanning || readingCard) ? null : onCapture,
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
                      color: (isScanning || readingCard)
                          ? Colors.grey
                          : const Color(0xFF1a1a2e),
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
  const _Viewfinder({required this.isScanning, required this.sweep});

  final bool isScanning;
  final Animation<double> sweep;

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
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
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
                  child: isScanning
                      ? null
                      : const Center(
                          child: Icon(
                            Icons.credit_card_outlined,
                            color: Color(0x26FFFFFF),
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
                  builder: (_, __) => Positioned(
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
    required this.scanResult,
    required this.onLinkExisting,
    required this.onCreateNew,
  });

  final Map<String, dynamic>? scanResult;
  final VoidCallback onLinkExisting;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context) {
    final name = scanResult?['name'] as String? ?? 'Unknown';
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join();
    final idNumber = scanResult?['idNumber'] as String? ?? '';
    final gender = scanResult?['gender'] as String? ?? '';
    final dob = scanResult?['dateOfBirth'] as String? ?? '';
    final age = _computeAge(dob);

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
                        'New enrolment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _navy,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '✦ AI filled from e-Health card scan',
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
            // Navy gradient NID data card
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
              child: Stack(
                children: [
                  Positioned(
                    right: -10,
                    top: -10,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📲 SCANNED FROM E-HEALTH CARD',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0x80FFFFFF),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  age.isNotEmpty ? '$gender · Age $age' : gender,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0x99FFFFFF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DataCell(label: 'NID', value: idNumber),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _DataCell(label: 'DOB', value: dob),
                          ),
                        ],
                      ),
                    ],
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

  static String _computeAge(String dob) {
    try {
      final parts = dob.split('-');
      if (parts.length < 3) return '';
      final birth = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return '$age';
    } catch (_) {
      return '';
    }
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0x80FFFFFF),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
