import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class EnrollmentButton extends StatelessWidget {
  const EnrollmentButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.variant = EnrollmentButtonVariant.primary,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isEnabled;
  final EnrollmentButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final bgColor = _getBackgroundColor();
    final fgColor = _getForegroundColor();

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        child: InkWell(
          onTap: isLoading || !isEnabled ? null : onPressed,
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fgColor,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    if (!isEnabled) return AppColors.textMuted.withValues(alpha: 0.2);

    switch (variant) {
      case EnrollmentButtonVariant.primary:
        return AppColors.navy;
      case EnrollmentButtonVariant.secondary:
        return AppColors.cardSurface;
      case EnrollmentButtonVariant.success:
        return AppColors.statusSuccess;
      case EnrollmentButtonVariant.danger:
        return AppColors.statusCritical;
    }
  }

  Color _getForegroundColor() {
    if (!isEnabled) return AppColors.textMuted;

    switch (variant) {
      case EnrollmentButtonVariant.primary:
        return AppColors.textOnNavy;
      case EnrollmentButtonVariant.secondary:
        return AppColors.navy;
      case EnrollmentButtonVariant.success:
        return AppColors.textOnNavy;
      case EnrollmentButtonVariant.danger:
        return AppColors.textOnNavy;
    }
  }
}

enum EnrollmentButtonVariant {
  primary,
  secondary,
  success,
  danger,
}
