import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class EnrollmentStatusHeader extends StatelessWidget {
  const EnrollmentStatusHeader({
    required this.title,
    this.subtitle,
    this.icon = Icons.check_circle,
    this.padding = const EdgeInsets.all(AppSpacing.h5xl),
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.statusSuccessSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: AppColors.statusSuccess,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.statusSuccessText,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.statusSuccessText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
