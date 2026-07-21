/// Training Hub — micro-coaching pilot (Learn loop).
///
/// Matches Screen 9 of apon_sushashthya_v10.html exactly:
///   1. Leaderboard card (navy gradient #1B2B5E → #2d3f7a)
///   2. Section label "TODAY'S LESSONS — BASED ON YOUR VISITS"
///   3. Morning-prioritized module cards from [CoachingRepository]
///   4. Monthly progress card (3 columns)
///
/// Engineering Design Standards:
///   - UI watches [CoachingRepository]; sync lives in the repository layer.
///   - All strings from [TrainingStrings] / [CoachingStrings].
///   - Leaderboard / monthly stats remain mock until supervisor APIs land.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'coaching_models.dart';
import 'coaching_repository.dart';
import 'module_detail_screen.dart';

// ─── Screen & body ────────────────────────────────────────────────────────────

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TrainingStrings.title,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              TrainingStrings.subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: AppColors.aiPurpleDark,
        foregroundColor: Colors.white,
        toolbarHeight: 60,
      ),
      body: const TrainingBody(),
    );
  }
}

class TrainingBody extends StatefulWidget {
  const TrainingBody({super.key});

  @override
  State<TrainingBody> createState() => _TrainingBodyState();
}

class _TrainingBodyState extends State<TrainingBody> {
  @override
  void initState() {
    super.initState();
    // Pull latest morning priorities when the SK opens Training (covers
    // sessions that skipped /sync, e.g. biometric re-entry).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CoachingRepository>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CoachingRepository>();
    final modules = repo.modules;
    final priorities = repo.todaysPriorities;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (repo.isSyncing && modules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // 1. Today's focus — morning priority modules
            if (priorities.isNotEmpty) ...[
              _SectionLabel(label: CoachingStrings.sectionMorningCards),
              const SizedBox(height: 10),
              ...priorities.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MorningModuleCard(module: m),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // 2. All modules grid
            _SectionLabel(label: CoachingStrings.sectionAllModulesGrid),
            const SizedBox(height: 10),
            _ModuleGrid(modules: modules),
            const SizedBox(height: 4),
          ],

          // 3. Monthly progress
          const _MonthlyProgressCard(),
        ],
      ),
    );
  }
}

// ─── Morning module card (SDK: MorningCard) ───────────────────────────────────
// Matches SDK MorningCard.kt exactly: horizontal tile, icon block, eyebrow,
// title, Skip text button, Start filled pill.

class _MorningModuleCard extends StatelessWidget {
  const _MorningModuleCard({required this.module});

  final CoachingModule module;

  static const _iconBg = Color(0xFFE8F0FE);
  static const _navy = Color(0xFF1B2B5E);
  static const _skipGray = Color(0xFF6B7280);

  String _eyebrow() {
    final hasCards = module.cards.isNotEmpty;
    final hasQuiz = module.quiz.isNotEmpty;
    if (hasCards && hasQuiz) return CoachingStrings.refresherTypeMicrocoaching;
    if (hasCards) return CoachingStrings.refresherTypeLearningCard;
    return CoachingStrings.refresherTypeQuiz;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Leading icon block
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.groups_outlined, color: _navy, size: 24),
            ),
            const SizedBox(width: 12),

            // Eyebrow + title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eyebrow(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: _navy,
                    ),
                  ),
                  Text(
                    module.titleEn,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Skip
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Skipped'), duration: Duration(seconds: 1)),
              ),
              child: Text(
                CoachingStrings.morningCardSkip,
                style: const TextStyle(color: _skipGray, fontWeight: FontWeight.w500),
              ),
            ),

            // Start
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ModuleDetailScreen(module: module),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(
                CoachingStrings.morningCardStart,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 2-column module grid (SDK: AllModulesScreen) ─────────────────────────────

// SDK ModuleTile TRAINING variant — full-width horizontal row.
// Layout: 56dp thumbnail | Column(title + subtitle) | 40dp CompletionRing
const _kSpiceBlueContainer = Color(0xFFE8F0FE);
const _kSpiceNavy = Color(0xFF1B2B5E);
const _kSpiceBlueDark = Color(0xFF1565C0);
const _kMetaTextColor = Color(0xFF6B7280);

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({required this.modules});

  final List<CoachingModule> modules;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: modules
          .map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ModuleTile(module: m),
            ),
          )
          .toList(),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final CoachingModule module;

  void _onTap(BuildContext context) {
    if (module.isLocked) {
      _showLockedSnackbar(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ModuleDetailScreen(module: module)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle =
        '${module.estimatedMinutes} ${CoachingStrings.minLabel} · '
        '${module.quiz.length} ${CoachingStrings.detailQuestions}';

    return Opacity(
      opacity: module.isLocked ? 0.6 : 1.0,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        child: InkWell(
          onTap: () => _onTap(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 56dp thumbnail — SpiceBlueContainer fallback
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: _kSpiceBlueContainer,
                    child: module.isLocked
                        ? const Icon(Icons.lock_rounded, color: _kSpiceBlueDark, size: 24)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),

                // Title + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        module.titleEn,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _kSpiceNavy,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: _kMetaTextColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // 40dp completion ring
                _CompletionRing(progress: module.progressFraction),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionRing extends StatelessWidget {
  const _CompletionRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            color: _kSpiceBlueDark,
            backgroundColor: _kSpiceBlueContainer,
            strokeWidth: 3,
          ),
          Text(
            '${(progress * 100).toInt()}%',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _kSpiceBlueDark,
                  fontSize: 9,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Monthly progress card ────────────────────────────────────────────────────

class _MonthlyProgressCard extends StatelessWidget {
  const _MonthlyProgressCard();

  @override
  Widget build(BuildContext context) {
    final stats = MockCoachingData.monthlyStats;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TrainingStrings.sectionMonthlyProgress,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  value: '${stats.videosWatched}',
                  label: TrainingStrings.statVideos,
                  color: AppColors.aiPurple,
                ),
              ),
              Expanded(
                child: _StatCell(
                  value: '${stats.pointsEarned}',
                  label: TrainingStrings.statPoints,
                  color: AppColors.pink,
                ),
              ),
              Expanded(
                child: _StatCell(
                  value: '${stats.dayStreak}',
                  label: TrainingStrings.statStreak,
                  color: AppColors.statusSuccess,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.07 * 11,
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _showLockedSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(TrainingStrings.lockedSnackbar),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
