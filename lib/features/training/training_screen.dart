/// Training Hub — micro-coaching pilot (mock UI, no API calls).
///
/// Three-loop model: Learn (this screen + module player + quiz)
/// → Apply (visit-triggered, future) → Measure (telemetry, future).
///
/// PILOT-SCOPE v1: shows only the 3 pilot care journeys (IMCI / ANC / NCD).
/// To restore TB, EPI, Nutrition modules: un-comment the entries below and
/// add their programmes to kPilotProgrammes in programme.dart.
///
/// Engineering Design Standards:
///   - Pure UI — no I/O, no business logic.
///   - All strings from [TrainingStrings] / [CoachingStrings].
///   - Mock data from [MockCoachingData]; swap for repository when
///     coaching endpoints are approved.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'coaching_models.dart';
import 'coaching_repository.dart';
import 'module_player_screen.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text(TrainingStrings.title),
        backgroundColor: AppColors.aiPurpleDark,
        foregroundColor: Colors.white,
      ),
      body: const TrainingBody(),
    );
  }
}

/// Embeddable training content — used both by [TrainingScreen] (standalone)
/// and by the Assistant tab's Training sub-tab.
class TrainingBody extends StatelessWidget {
  const TrainingBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.watch<CoachingRepository>();
    final priorities = repo.todaysPriorities;
    final all = repo.modules;

    return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Today's focus ─────────────────────────────────────────────
            if (priorities.isNotEmpty) ...[
              _SectionHeader(label: CoachingStrings.sectionTodayFocus),
              const SizedBox(height: AppSpacing.xl),
              ...priorities.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: _PriorityModuleCard(module: m),
                ),
              ),
              const SizedBox(height: AppSpacing.h6xl),
            ],

            // ── All modules ───────────────────────────────────────────────
            _SectionHeader(label: CoachingStrings.sectionAllModules),
            const SizedBox(height: AppSpacing.xl),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppSpacing.xl,
              mainAxisSpacing: AppSpacing.xl,
              childAspectRatio: 1.05,
              children: all.map((m) => _GridModuleCard(module: m)).toList(),
            ),

            const SizedBox(height: AppSpacing.h6xl),

            // ── Certificates (future) ─────────────────────────────────────
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.statusWarning,
                ),
                title: const Text(TrainingStrings.certificatesTitle),
                subtitle: const Text(TrainingStrings.certificatesSubtitle),
                trailing: Chip(
                  label: Text(
                    TrainingStrings.comingSoon,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textMuted,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

// ─── Priority card (full-width, shown in "Today's Focus") ────────────────────

class _PriorityModuleCard extends StatelessWidget {
  const _PriorityModuleCard({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _domainColor(module.domain);
    final surface = _domainSurface(module.domain);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openModule(context, module),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Row(
            children: [
              // ── Domain icon ───────────────────────────────────────────
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(AppRadius.rxIcon),
                ),
                child: Icon(_domainIcon(module.domain), color: color, size: 26),
              ),
              const SizedBox(width: AppSpacing.xxxl),

              // ── Title + meta ──────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.titleEn,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      module.titleBn,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        _DomainChip(domain: module.domain),
                        const SizedBox(width: AppSpacing.md),
                        Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${module.estimatedMinutes} ${CoachingStrings.minLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (module.passed) ...[
                          const SizedBox(width: AppSpacing.md),
                          _PassBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── CTA ───────────────────────────────────────────────────
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Grid card (compact, shown in "All Modules") ──────────────────────────────

class _GridModuleCard extends StatelessWidget {
  const _GridModuleCard({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _domainColor(module.domain);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openModule(context, module),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Icon ─────────────────────────────────────────────────
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Icon(_domainIcon(module.domain), size: 36, color: color),
                  if (module.passed)
                    Positioned(
                      top: -2,
                      right: -4,
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: AppColors.statusSuccess,
                      ),
                    ),
                ],
              ),

              // ── Label ────────────────────────────────────────────────
              Column(
                children: [
                  Text(
                    module.titleEn,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _DomainChip(domain: module.domain),
                ],
              ),

              // ── Progress bar ──────────────────────────────────────────
              Column(
                children: [
                  LinearProgressIndicator(
                    value: module.passed ? module.quizScore : 0,
                    backgroundColor: Colors.grey.shade200,
                    color: color,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    module.passed
                        ? '${(module.quizScore * 100).round()}%'
                        : '${module.estimatedMinutes} ${CoachingStrings.minLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _DomainChip extends StatelessWidget {
  const _DomainChip({required this.domain});

  final CoachingDomain domain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _domainSurface(domain),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        _domainLabel(domain),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _domainColor(domain),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PassBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusSuccessSurface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 11, color: AppColors.statusSuccessText),
          const SizedBox(width: 2),
          Text(
            CoachingStrings.passedLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.statusSuccessText,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _openModule(BuildContext context, CoachingModule module) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ModulePlayerScreen(module: module),
    ),
  );
}

Color _domainColor(CoachingDomain d) => switch (d) {
      CoachingDomain.anc => AppColors.ancHeader,
      CoachingDomain.ncd => AppColors.ncdHeader,
      CoachingDomain.imci => AppColors.imciHeader,
      CoachingDomain.tb => AppColors.tbHeader,
      CoachingDomain.epi => AppColors.statusSuccess,
      CoachingDomain.nutrition => AppColors.statusInfo,
    };

Color _domainSurface(CoachingDomain d) => switch (d) {
      CoachingDomain.anc => AppColors.ancSurface,
      CoachingDomain.ncd => AppColors.ncdSurface,
      CoachingDomain.imci => AppColors.imciSurface,
      CoachingDomain.tb => AppColors.tbSurface,
      CoachingDomain.epi => AppColors.statusSuccessSurface,
      CoachingDomain.nutrition => AppColors.statusInfoSurface,
    };

IconData _domainIcon(CoachingDomain d) => switch (d) {
      CoachingDomain.anc => Icons.pregnant_woman_rounded,
      CoachingDomain.ncd => Icons.monitor_heart_rounded,
      CoachingDomain.imci => Icons.child_care_rounded,
      CoachingDomain.tb => Icons.air_rounded,
      CoachingDomain.epi => Icons.vaccines_rounded,
      CoachingDomain.nutrition => Icons.restaurant_rounded,
    };

String _domainLabel(CoachingDomain d) => switch (d) {
      CoachingDomain.anc => CoachingStrings.domainAnc,
      CoachingDomain.ncd => CoachingStrings.domainNcd,
      CoachingDomain.imci => CoachingStrings.domainImci,
      CoachingDomain.tb => CoachingStrings.domainTb,
      CoachingDomain.epi => CoachingStrings.domainEpi,
      CoachingDomain.nutrition => CoachingStrings.domainNutrition,
    };
