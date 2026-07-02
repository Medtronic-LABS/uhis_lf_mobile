import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Compact pill-style section header for enrollment forms.
///
/// Renders the [title] in uppercase navy 10px w800 on a light blue
/// (#EEF0FF) background pill with 8px radius. An emoji prefix can be
/// included directly in the [title] string (e.g. "🏠 HOUSEHOLD INFORMATION").
/// The optional [subtitle] parameter is kept for API compatibility but is
/// intentionally unused in the redesigned layout.
class EnrollmentSectionHeader extends StatelessWidget {
  const EnrollmentSectionHeader({
    required this.title,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    super.key,
  });

  final String title;

  /// Kept for backwards compatibility; not rendered in the updated design.
  final String? subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.aiSurfaceStart,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: padding,
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
