import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'enrollment_controller.dart';

const _mintGreen = Color(0xFF1BD8B8);
const _navy = Color(0xFF24356F);
const _purple = Color(0xFF5B4FD9);
const _green = Color(0xFF14996A);
const _bg = Color(0xFFF5F6FB);

/// Shows the household enrollment entry sheet as a modal bottom sheet.
///
/// Presents two paths:
///   1. Scan NID card — camera frame with mint-green corners, shutter CTA
///   2. Create Household manually — taps through to the form screens
///
/// Rest of the enrollment flow (form, head info, success, add member) uses
/// the existing GoRouter routes.
void showEnrollmentEntrySheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    enableDrag: true,
    builder: (_) => ChangeNotifierProvider(
      create: (_) => EnrollmentController(),
      child: const _EnrollmentEntrySheet(),
    ),
  );
}

class _EnrollmentEntrySheet extends StatefulWidget {
  const _EnrollmentEntrySheet();

  @override
  State<_EnrollmentEntrySheet> createState() => _EnrollmentEntrySheetState();
}

class _EnrollmentEntrySheetState extends State<_EnrollmentEntrySheet> {
  bool _scanning = false;
  bool _showCamera = false;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle pill
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Capture Household',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Scan NID or register manually',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: _navy),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _showCamera
                      ? _CameraFrame(
                          scanning: _scanning,
                          onShutter: _handleScan,
                        )
                      : _ScanPromptCard(
                          onTap: () => setState(() => _showCamera = true),
                        ),
                  const SizedBox(height: 28),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _CreateHouseholdCard(
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/household/enrollment/create');
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleScan() async {
    setState(() => _scanning = true);
    final controller = context.read<EnrollmentController>();

    await Future.delayed(const Duration(milliseconds: 1800));
    await controller.mockNidScan();

    if (!mounted) return;
    setState(() => _scanning = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('NID scanned — details pre-filled'),
        backgroundColor: _green,
        duration: Duration(seconds: 2),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    Navigator.of(context).pop();
    context.push('/household/enrollment/head-info');
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ScanPromptCard extends StatelessWidget {
  const _ScanPromptCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEBFF),
                borderRadius: BorderRadius.circular(36),
              ),
              child: const Icon(Icons.camera_alt_outlined, size: 36, color: _purple),
            ),
            const SizedBox(height: 16),
            const Text(
              'Take a Photo of NID Card',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _navy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Position the card within the frame',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: _purple,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Open Camera',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraFrame extends StatelessWidget {
  const _CameraFrame({required this.scanning, required this.onShutter});
  final bool scanning;
  final VoidCallback onShutter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Frame
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: scanning
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: _mintGreen,
                            strokeWidth: 2.5,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Scanning...',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.credit_card_outlined,
                              size: 48, color: Colors.white24),
                          const SizedBox(height: 8),
                          const Text(
                            'Position card in frame',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
              ),
            ),
            // Mint corner brackets
            ..._corners(),
          ],
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: scanning ? null : onShutter,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scanning ? Colors.grey.shade400 : _purple,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _purple.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.camera, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Tap to capture',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  static List<Widget> _corners() {
    const size = 28.0;
    const thick = 3.0;

    Widget corner({required AlignmentGeometry align, bool top = true, bool left = true}) {
      return Positioned.fill(
        child: Align(
          alignment: align,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(painter: _CornerPainter(top: top, left: left, thick: thick)),
            ),
          ),
        ),
      );
    }

    return [
      corner(align: Alignment.topLeft, top: true, left: true),
      corner(align: Alignment.topRight, top: true, left: false),
      corner(align: Alignment.bottomLeft, top: false, left: true),
      corner(align: Alignment.bottomRight, top: false, left: false),
    ];
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.top, required this.left, required this.thick});
  final bool top, left;
  final double thick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _mintGreen
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    final xEnd = left ? size.width : 0.0;
    final yEnd = top ? size.height : 0.0;

    canvas.drawLine(Offset(x, y), Offset(xEnd, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, yEnd), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

class _CreateHouseholdCard extends StatelessWidget {
  const _CreateHouseholdCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEDF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.home_outlined, color: _navy, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Household',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Register a new household manually',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
