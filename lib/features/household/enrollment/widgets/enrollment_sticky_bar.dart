import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Sticky bottom action bar shared across the household-enrollment flow.
///
/// Renders a full-width primary navy CTA on the page-background canvas with a
/// soft top shadow + hairline border so it reads as floating above scrolling
/// form content. Supports a [loading] spinner and a disabled ([enabled]:false)
/// state (spec: keep the CTA disabled until mandatory fields are complete).
///
/// Replaces the sticky-CTA block that was previously duplicated verbatim across
/// the create / head-info / add-member / success screens (single home for the
/// bar's spacing, radius, elevation, and disabled styling).
class EnrollmentStickyBar extends StatelessWidget {
  const EnrollmentStickyBar({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.enabled = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.pageBackground,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: active ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.4),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
