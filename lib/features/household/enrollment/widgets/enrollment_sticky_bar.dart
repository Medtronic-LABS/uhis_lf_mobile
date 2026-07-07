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
            color: AppColors.borderSoft,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.h5xl,
        AppSpacing.xl,
        AppSpacing.h5xl,
        AppSpacing.h5xl,
      ),
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
              borderRadius: BorderRadius.circular(AppRadius.patRow),
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
                  // Deliberately not Theme.of(context).textTheme.titleMedium:
                  // that style bakes in Colors.black87, which would break the
                  // white-on-navy CTA text (and its disabled-alpha dimming,
                  // handled by ElevatedButton.styleFrom above). Numeric
                  // literals kept intentionally — see AppTextStyles module
                  // doc for why no bare 15/w700-with-inherited-color token
                  // exists.
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
