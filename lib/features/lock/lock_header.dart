import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';

class LockProgramHeader extends StatelessWidget {
  const LockProgramHeader({
    super.key,
    required this.title,
    this.subtitle = LockStrings.programSubtitle,
    this.pageCount = 1,
    this.currentPage = 0,
  });

  final String title;
  final String subtitle;
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'NunitoSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.60),
                ),
              ),
              const SizedBox(height: 14),
              Center(child: LockPageDots(count: pageCount, current: currentPage)),
            ],
          ),
        ),
      ),
    );
  }
}

class LockPageDots extends StatelessWidget {
  const LockPageDots({super.key, required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == current;
        return Padding(
          padding: EdgeInsets.only(right: i < count - 1 ? 6 : 0),
          child: SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.30),
              ),
            ),
          ),
        );
      }),
    );
  }
}
