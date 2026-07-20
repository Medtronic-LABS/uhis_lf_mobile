import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';

class LockProgramHeader extends StatelessWidget {
  const LockProgramHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.pageCount = 1,
    this.currentPage = 0,
  });

  final String title;
  final String? subtitle;
  final int pageCount;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.navy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.h5xl,
            0,
            AppSpacing.h5xl,
            AppSpacing.h4xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.headerTitle),
              const SizedBox(height: 2),
              Text(subtitle ?? LockStrings.programSubtitle, style: AppTextStyles.headerSub),
              const SizedBox(height: AppSpacing.xxl),
              Center(child: LockPageDots(count: pageCount, current: currentPage)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stepper dots — `.flow-dot`/`.flow-dot.active`: 6x6 circle at 0.30 alpha,
/// active dot grows into a 20x6 pill at full opacity.
class LockPageDots extends StatelessWidget {
  const LockPageDots({super.key, required this.count, required this.current});

  final int count;
  final int current;

  static const double _inactiveSize = 6;
  static const double _activeWidth = 20;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == current;
        return Padding(
          padding: EdgeInsets.only(right: i < count - 1 ? AppSpacing.sm : 0),
          child: AnimatedContainer(
            duration: AppAnimations.control,
            curve: AppAnimations.standard,
            width: active ? _activeWidth : _inactiveSize,
            height: _inactiveSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(active ? 3 : _inactiveSize / 2),
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.30),
            ),
          ),
        );
      }),
    );
  }
}
