/// Training Hub — micro-coaching pilot (mock UI, no API calls).
///
/// Layout matches Screen 9 of apon_sushashthya_v10.html:
///   1. Leaderboard card (dark purple gradient)
///   2. Today's lessons — full-width video module cards
///   3. Monthly progress card (3-column stats)
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
    final repo = context.watch<CoachingRepository>();
    final modules = repo.modules;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxxl,
        vertical: AppSpacing.h6xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Leaderboard ─────────────────────────────────────────────
          const _LeaderboardCard(),
          const SizedBox(height: AppSpacing.h6xl),

          // ── 2. Today's lessons ─────────────────────────────────────────
          _SectionHeader(label: TrainingStrings.sectionTodaysLessons),
          const SizedBox(height: AppSpacing.xl),
          ...modules.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: _VideoModuleCard(module: m),
            ),
          ),
          const SizedBox(height: AppSpacing.h6xl),

          // ── 3. Monthly progress ────────────────────────────────────────
          const _MonthlyProgressCard(),
          const SizedBox(height: AppSpacing.h6xl),
        ],
      ),
    );
  }
}

// ─── Leaderboard card ─────────────────────────────────────────────────────────

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard();

  @override
  Widget build(BuildContext context) {
    final entries = MockCoachingData.leaderboard;
    // Find current user for motivation nudge
    final me = entries.where((e) => e.isCurrentUser).firstOrNull;
    final first = entries.first;
    final ptGap = me != null ? first.points - me.points : 0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D1B69), Color(0xFF4C3A99)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  TrainingStrings.leaderboardTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text(
                  'Ward 4 · Manikganj',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxxl),

          // Leaderboard rows
          ...entries.map((e) => _LeaderboardRow(entry: e)),

          // Motivation nudge
          if (me != null && ptGap > 0) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              '${TrainingStrings.leaderboardMotivationPrefix}'
              '$ptGap'
              '${TrainingStrings.leaderboardMotivationSuffix}',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final isTop2 = entry.rank <= 2;
    final rankLabel = switch (entry.rank) {
      1 => '🥇',
      2 => '🥈',
      _ => '${entry.rank}',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              rankLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isTop2 ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: isTop2 ? 18 : 13,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Avatar initials
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.isCurrentUser
                  ? const Color(0xFFFFD700)
                  : Colors.white.withAlpha(40),
              border: entry.isCurrentUser
                  ? Border.all(color: const Color(0xFFFFD700), width: 2)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              entry.initials,
              style: TextStyle(
                color: entry.isCurrentUser
                    ? const Color(0xFF2D1B69)
                    : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Name + ward
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (entry.isCurrentUser) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        TrainingStrings.leaderboardYou,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${entry.wardLabel} · ${entry.videoCount} videos',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),

          // Rank change arrow
          if (entry.rankChange != null && entry.rankChange != 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(
                entry.rankChange! > 0
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12,
                color: entry.rankChange! > 0
                    ? AppColors.statusSuccess
                    : AppColors.pink,
              ),
            ),

          // Points
          Text(
            '${entry.points} pts',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Video module card ────────────────────────────────────────────────────────

class _VideoModuleCard extends StatelessWidget {
  const _VideoModuleCard({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = module.isLocked;

    return Opacity(
      opacity: locked ? 0.65 : 1.0,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: locked
              ? () => _showLockedSnackbar(context)
              : () => _openModule(context, module),
          child: SizedBox(
            height: 96,
            child: Row(
              children: [
                // ── Thumbnail gradient ─────────────────────────────────
                _VideoThumbnail(module: module),

                // ── Content ────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxxl,
                      vertical: AppSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Title
                        Text(
                          module.titleEn,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),

                        // Duration + state badge row
                        Row(
                          children: [
                            Icon(Icons.schedule_rounded,
                                size: 12, color: AppColors.textMuted),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '${module.estimatedMinutes} ${CoachingStrings.minLabel}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            _StateBadge(module: module),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Pill badge ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xl),
                  child: _PillBadge(module: module),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Left-side gradient thumbnail with play/pause circle and progress bar.
class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final colors = _thumbnailGradient(module);

    return Container(
      width: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Play/pause icon
          Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(module.isLocked ? 60 : 120),
              ),
              child: Icon(
                module.isLocked
                    ? Icons.lock_rounded
                    : (module.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                color: Colors.white,
                size: 20,
              ),
            ),
          ),

          // Progress bar at bottom (only when playing or completed)
          if (module.progressFraction > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: module.progressFraction,
                minHeight: 3,
                backgroundColor: Colors.white24,
                color: module.isCompleted
                    ? AppColors.statusSuccess
                    : Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  List<Color> _thumbnailGradient(CoachingModule m) {
    if (m.isLocked) return const [Color(0xFF1F2937), Color(0xFF4B5563)];
    return switch (m.domain) {
      CoachingDomain.imci => const [Color(0xFF7F1D1D), Color(0xFFEF4444)],
      CoachingDomain.ncd => const [Color(0xFF022C22), Color(0xFF10B981)],
      CoachingDomain.anc => const [Color(0xFF831843), Color(0xFFEC4899)],
      CoachingDomain.tb => const [Color(0xFF1B4332), Color(0xFF34D399)],
      CoachingDomain.epi => const [Color(0xFF1E3A5F), Color(0xFF0EA5E9)],
      CoachingDomain.nutrition => const [Color(0xFF3B1F00), Color(0xFFF59E0B)],
    };
  }
}

/// NOW PLAYING / COMPLETED / (nothing for new) / LOCKED badge.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    if (module.isLocked) {
      return _Chip(
        label: TrainingStrings.badgeLocked,
        bg: Colors.grey.shade200,
        fg: AppColors.textMuted,
      );
    }
    if (module.isCompleted) {
      return _Chip(
        label: TrainingStrings.badgeCompleted,
        bg: AppColors.statusSuccessSurface,
        fg: AppColors.statusSuccessText,
      );
    }
    if (module.isPlaying) {
      return _Chip(
        label: TrainingStrings.badgeNowPlaying,
        bg: const Color(0xFFEDE9FE),
        fg: AppColors.aiPurpleDark,
      );
    }
    return const SizedBox.shrink();
  }
}

/// Right-side pill badge (Triggered / Done+pts / New / Locked).
class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color bg;
    final Color fg;

    if (module.isLocked) {
      label = TrainingStrings.pillLocked;
      bg = Colors.grey.shade200;
      fg = AppColors.textMuted;
    } else if (module.isCompleted) {
      label = TrainingStrings.pillDonePoints(module.pointsEarned);
      bg = AppColors.statusSuccessSurface;
      fg = AppColors.statusSuccessText;
    } else if (module.triggerReason != null) {
      label = TrainingStrings.pillTriggered(module.triggerReason!);
      bg = const Color(0xFFEDE9FE);
      fg = AppColors.aiPurpleDark;
    } else {
      label = TrainingStrings.pillNew;
      bg = const Color(0xFFEDE9FE);
      fg = AppColors.aiPurpleDark;
    }

    return _Chip(label: label, bg: bg, fg: fg);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
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

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TrainingStrings.sectionMonthlyProgress,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            Row(
              children: [
                Expanded(
                  child: _StatColumn(
                    value: '${stats.videosWatched}',
                    label: TrainingStrings.statVideos,
                    color: AppColors.aiPurple,
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    value: '${stats.pointsEarned}',
                    label: TrainingStrings.statPoints,
                    color: AppColors.pink,
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    value: '${stats.dayStreak}',
                    label: TrainingStrings.statStreak,
                    color: AppColors.statusSuccess,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
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
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
        ),
      ],
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _openModule(BuildContext context, CoachingModule module) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ModulePlayerScreen(module: module),
    ),
  );
}

void _showLockedSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text(TrainingStrings.lockedSnackbar),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
