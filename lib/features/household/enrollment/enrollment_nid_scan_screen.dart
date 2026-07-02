import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import 'enrollment_controller.dart';
import 'household_enrollment_sheet.dart';
import 'widgets/enrollment_button.dart';

/// First step of the household enrollment overlay: scan household head's ID.
///
/// User can either scan an ID card (camera overlay with mint-green corners
/// and dashed border) or skip to manual entry. Mock scan returns pre-filled
/// head information. Navigation uses the inner [Navigator] provided by
/// [HouseholdEnrollmentSheet]; the close button dismisses the overlay via
/// the root navigator.
class EnrollmentNidScanScreen extends StatefulWidget {
  const EnrollmentNidScanScreen({super.key});

  @override
  State<EnrollmentNidScanScreen> createState() =>
      _EnrollmentNidScanScreenState();
}

class _EnrollmentNidScanScreenState extends State<EnrollmentNidScanScreen> {
  bool _showCameraOverlay = false;
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<EnrollmentController>(
      builder: (context, controller, child) {
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: EnrollmentOverlayHeader(
              title: EnrollmentStrings.nidScanTitle,
              showBack: false,
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    EnrollmentStrings.nidScanSubtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: !_showCameraOverlay
                        ? _buildCameraPrompt(context, controller)
                        : _buildCameraOverlay(context, controller),
                  ),
                  const SizedBox(height: 20),
                  _buildActionButtons(context, controller),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraPrompt(
    BuildContext context,
    EnrollmentController controller,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.aiSurfaceStart,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.camera_alt_outlined,
            size: 48,
            color: AppColors.aiPurple,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          EnrollmentStrings.nidScanCameraHint,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Position the household head\'s NID or birth registration card in the frame',
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCameraOverlay(
    BuildContext context,
    EnrollmentController controller,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.textMuted,
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: Center(
                child: _isScanning
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.aiPurple,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Scanning...',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        EnrollmentStrings.nidScanCameraHint,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFF1BD8B8),
                      width: 2,
                    ),
                    left: BorderSide(
                      color: const Color(0xFF1BD8B8),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFF1BD8B8),
                      width: 2,
                    ),
                    right: BorderSide(
                      color: const Color(0xFF1BD8B8),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFF1BD8B8),
                      width: 2,
                    ),
                    left: BorderSide(
                      color: const Color(0xFF1BD8B8),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFF1BD8B8),
                      width: 2,
                    ),
                    right: BorderSide(
                      color: const Color(0xFF1BD8B8),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
        FloatingActionButton(
          onPressed: _isScanning ? null : () => _performMockScan(controller),
          backgroundColor: AppColors.aiPurple,
          elevation: 4,
          child: const Icon(
            Icons.camera,
            color: AppColors.textOnNavy,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap the button to scan',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textMuted.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    EnrollmentController controller,
  ) {
    return Column(
      children: [
        if (!_showCameraOverlay)
          EnrollmentButton(
            label: EnrollmentStrings.nidScanTitle,
            onPressed: () {
              setState(() => _showCameraOverlay = true);
            },
          ),
        if (_showCameraOverlay) ...[
          EnrollmentButton(
            label: EnrollmentStrings.createHousehold,
            onPressed: () {
              Navigator.of(context).pushNamed('/create');
            },
            variant: EnrollmentButtonVariant.secondary,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<void> _performMockScan(EnrollmentController controller) async {
    setState(() => _isScanning = true);

    try {
      await controller.mockNidScan();

      if (mounted) {
        setState(() => _isScanning = false);

        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ID scanned successfully'),
            duration: Duration(seconds: 2),
          ),
        );

        // Navigate to head info screen with pre-filled data
        if (mounted) {
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            Navigator.of(context).pushNamed('/head-info');
          }
        }
      }
    } catch (e) {
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
