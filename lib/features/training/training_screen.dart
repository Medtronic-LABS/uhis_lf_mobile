/// Training Hub placeholder screen.
///
/// Shows 6 programme training module cards in a 2-column grid plus a
/// certificates card. All cards are UI scaffolds — no API calls.
///
/// Engineering Design Standards:
///   - Pure UI — no I/O, no business logic.
///   - All strings from [TrainingStrings].
library;

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  static const _trainingModules = [
    (
      label: 'IMCI',
      icon: Icons.child_care_rounded,
      color: AppColors.imciHeader
    ),
    (
      label: 'ANC',
      icon: Icons.pregnant_woman_rounded,
      color: AppColors.ancHeader
    ),
    (
      label: 'NCD',
      icon: Icons.monitor_heart_rounded,
      color: AppColors.ncdHeader
    ),
    (label: 'TB', icon: Icons.air_rounded, color: AppColors.tbHeader),
    (
      label: 'EPI',
      icon: Icons.vaccines_rounded,
      color: AppColors.statusSuccess
    ),
    (
      label: 'Nutrition',
      icon: Icons.restaurant_rounded,
      color: AppColors.statusInfo
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text(TrainingStrings.title),
        backgroundColor: AppColors.aiPurpleDark,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Subtitle ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.md,
                bottom: AppSpacing.xxxl,
              ),
              child: Text(
                TrainingStrings.subtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),

            // ── Module grid ───────────────────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppSpacing.xl,
              mainAxisSpacing: AppSpacing.xl,
              childAspectRatio: 1.1,
              children: _trainingModules.map((module) {
                return _ModuleCard(module: module);
              }).toList(),
            ),

            const SizedBox(height: AppSpacing.h6xl),

            // ── Certificates card ─────────────────────────────────────────
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.statusWarning,
                ),
                title: const Text(TrainingStrings.certificatesTitle),
                subtitle: const Text(TrainingStrings.certificatesSubtitle),
                trailing: const Chip(
                  label: Text(TrainingStrings.comingSoon),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single programme training module card with progress bar.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final ({String label, IconData icon, Color color}) module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(TrainingStrings.comingSoon),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Icon ─────────────────────────────────────────────────
              Icon(
                module.icon,
                size: 36,
                color: module.color,
              ),

              // ── Label ────────────────────────────────────────────────
              Text(
                module.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),

              // ── Progress ─────────────────────────────────────────────
              Column(
                children: [
                  LinearProgressIndicator(
                    value: 0,
                    backgroundColor: Colors.grey.shade200,
                    color: module.color,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '0%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
