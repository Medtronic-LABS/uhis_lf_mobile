import 'package:flutter/material.dart';

import '../../app/theme.dart';

class LockProgramHeader extends StatelessWidget {
  const LockProgramHeader({
    super.key,
    required this.title,
    this.subtitle = 'Community Health',
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
      color: AppColors.navy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'NunitoSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.70),
                ),
              ),
              const SizedBox(height: 16),
              LockPageDots(count: pageCount, current: currentPage),
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
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.30),
            ),
          ),
        );
      }),
    );
  }
}
