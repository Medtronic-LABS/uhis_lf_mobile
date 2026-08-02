import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// One row in a settings list — colored icon chip + title + optional
/// subtitle + trailing chevron. Shared by the dashboard's popup Settings
/// menu and [SettingsScreen] so both surfaces render identically.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.emoji,
    required this.chipColor,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.showChevron = true,
  });

  final String emoji;
  final Color chipColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: titleColor ?? AppColors.textPrimary,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showChevron)
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
      ],
    );
  }
}
