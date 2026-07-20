/// Training Hub — micro-coaching pilot (mock UI, no API calls).
///
/// Matches Screen 9 of apon_sushashthya_v10.html exactly:
///   1. Leaderboard card (navy gradient #1B2B5E → #2d3f7a)
///   2. Section label "TODAY'S LESSONS — BASED ON YOUR VISITS"
///   3. Video module cards (vertical: thumbnail top, body below)
///   4. Monthly progress card (3 columns)
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

class TrainingBody extends StatelessWidget {
  const TrainingBody({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CoachingRepository>();
    final modules = repo.modules;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Leaderboard
          const _LeaderboardCard(),
          const SizedBox(height: 14),

          // 2. Section label
          _SectionLabel(label: TrainingStrings.sectionTodaysLessons),
          const SizedBox(height: 10),

          // 3. Video module cards
          ...modules.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _VideoModuleCard(module: m),
            ),
          ),
          const SizedBox(height: 4),

          // 4. Monthly progress
          const _MonthlyProgressCard(),
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
    final me = entries.where((e) => e.isCurrentUser).firstOrNull;
    final first = entries.first;
    final ptGap = me != null ? first.points - me.points : 0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.navyMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  TrainingStrings.leaderboardTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                'Ward 4 · Manikganj',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Rows
          ...entries.map((e) => _LeaderboardRow(entry: e)),

          // Motivation nudge
          if (me != null && ptGap > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x1FFFD700),
                border: Border.all(color: const Color(0x40FFD700)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 11,
                  ),
                  children: [
                    TextSpan(text: TrainingStrings.leaderboardMotivationPrefix),
                    TextSpan(
                      text: '$ptGap pts',
                      style: const TextStyle(
                        color: AppColors.tagGold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(text: TrainingStrings.leaderboardMotivationSuffix),
                  ],
                ),
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

    final avatarBg = switch (entry.rank) {
      1 => AppColors.tagGold,
      2 => const Color(0xFFC0C0C0),
      _ => entry.isCurrentUser
          ? AppColors.pink
          : AppColors.aiPurple,
    };
    final avatarFg = switch (entry.rank) {
      1 => const Color(0xFF78350F),
      2 => const Color(0xFF374151),
      _ => Colors.white,
    };

    final subText = entry.isCurrentUser && entry.weeklyRankChangeLabel != null
        ? '${entry.wardLabel} · ${entry.videoCount} videos · ${entry.weeklyRankChangeLabel}'
        : '${entry.wardLabel} · ${entry.videoCount} videos';

    Widget rowContent = Row(
      children: [
        // Rank
        SizedBox(
          width: 24,
          child: Text(
            rankLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isTop2 || entry.isCurrentUser
                  ? AppColors.tagGold
                  : Colors.white54,
              fontWeight: FontWeight.w800,
              fontSize: isTop2 ? 17 : 12,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Avatar
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarBg,
            border: entry.isCurrentUser
                ? Border.all(color: AppColors.tagGold, width: 2)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            entry.initials,
            style: TextStyle(
              color: avatarFg,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Name + sub
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(
                      color: AppColors.onDarkHigh,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  if (entry.isCurrentUser) ...[
                    const SizedBox(width: 4),
                    Text(
                      TrainingStrings.leaderboardYou,
                      style: const TextStyle(
                        color: Color(0xCCFFD700),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                subText,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),

        // Score
        Text(
          '${entry.points}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const Text(
          'pts',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );

    // Wrap current-user row in a gold-tinted rounded container
    if (entry.isCurrentUser) {
      rowContent = Container(
        decoration: BoxDecoration(
          color: const Color(0x1FFFD700),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: rowContent,
      );
    } else {
      rowContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: rowContent,
      );
    }

    return Column(
      children: [
        rowContent,
        if (entry != MockCoachingData.leaderboard.last)
          const Divider(color: Color(0x12FFFFFF), height: 1),
      ],
    );
  }
}

// ─── Video module card — vertical layout ─────────────────────────────────────

class _VideoModuleCard extends StatelessWidget {
  const _VideoModuleCard({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: module.isLocked ? 0.6 : 1.0,
      child: GestureDetector(
        onTap: module.isLocked
            ? () => _showLockedSnackbar(context)
            : () => _openModule(context, module),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VideoThumbnail(module: module),
              _VideoCardBody(module: module),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final gradientColors = _gradientFor(module);
    final isPlaying = module.isPlaying;
    final isLocked = module.isLocked;
    final isCompleted = module.isCompleted;

    return SizedBox(
      height: 96,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient background
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Play / pause / lock button (centered)
          Center(
            child: _PlayButton(
              isPlaying: isPlaying,
              isLocked: isLocked,
              isCompleted: isCompleted,
              domain: module.domain,
            ),
          ),

          // State badge — top left
          if (isPlaying || isCompleted || isLocked)
            Positioned(
              top: 8,
              left: 8,
              child: _ThumbnailBadge(module: module),
            ),

          // Progress bar — bottom
          if (module.progressFraction > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: module.progressFraction,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCompleted
                      ? AppColors.statusSuccess
                      : AppColors.pink,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Color> _gradientFor(CoachingModule m) {
    if (m.isLocked) return const [AppColors.textStrong, AppColors.textMid];
    return switch (m.domain) {
      CoachingDomain.imci => const [AppColors.rangeCrisis, AppColors.statusCritical],
      CoachingDomain.ncd => const [Color(0xFF022C22), AppColors.statusSuccess],
      CoachingDomain.anc => const [AppColors.ancHeader, Color(0xFFEC4899)],
      CoachingDomain.tb => const [Color(0xFF0C2340), Color(0xFF1D4ED8)],
      CoachingDomain.epi => const [Color(0xFF1E3A5F), AppColors.statusInfo],
      CoachingDomain.nutrition => const [Color(0xFF3B1F00), AppColors.statusWarning],
    };
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.isLocked,
    required this.isCompleted,
    required this.domain,
  });

  final bool isPlaying;
  final bool isLocked;
  final bool isCompleted;
  final CoachingDomain domain;

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final Color bgColor;
    final IconData icon;

    if (isLocked) {
      bgColor = Colors.white24;
      iconColor = AppColors.textDisabled;
      icon = Icons.lock_rounded;
    } else if (isPlaying) {
      bgColor = AppColors.pink;
      iconColor = AppColors.pink;
      icon = Icons.pause_rounded;
    } else if (isCompleted) {
      bgColor = Colors.white;
      iconColor = AppColors.statusSuccess;
      icon = Icons.play_arrow_rounded;
    } else {
      bgColor = Colors.white;
      iconColor = _domainPlayColor(domain);
      icon = Icons.play_arrow_rounded;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isPlaying ? bgColor : const Color(0xEBFFFFFF),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: iconColor, size: isLocked ? 18 : 20),
    );
  }

  Color _domainPlayColor(CoachingDomain d) => switch (d) {
        CoachingDomain.imci => AppColors.statusCritical,
        CoachingDomain.ncd => AppColors.statusSuccess,
        CoachingDomain.anc => const Color(0xFFEC4899),
        CoachingDomain.tb => const Color(0xFF1D4ED8),
        CoachingDomain.epi => AppColors.statusInfo,
        CoachingDomain.nutrition => AppColors.statusWarning,
      };
}

class _ThumbnailBadge extends StatelessWidget {
  const _ThumbnailBadge({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color bg;

    if (module.isLocked) {
      label = TrainingStrings.badgeLocked;
      bg = const Color(0x80000000);
    } else if (module.isCompleted) {
      label = TrainingStrings.badgeCompleted;
      bg = const Color(0xD910B981);
    } else {
      // isPlaying
      label = TrainingStrings.badgeNowPlaying;
      bg = const Color(0x73000000);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _VideoCardBody extends StatelessWidget {
  const _VideoCardBody({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            module.titleEn,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(
                '${module.estimatedMinutes} ${CoachingStrings.minLabel}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(width: 8),
              _PillBadge(module: module),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Pill badge ───────────────────────────────────────────────────────────────

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color bg;
    final Color fg;

    if (module.isLocked) {
      final n = module.unlockAfterN;
      label = n != null
          ? TrainingStrings.pillUnlockAfter(n)
          : TrainingStrings.pillLocked;
      bg = AppColors.progressTrack;
      fg = AppColors.textDisabled;
    } else if (module.isCompleted) {
      label = TrainingStrings.pillDonePoints(module.pointsEarned);
      bg = AppColors.statusSuccessSurface;
      fg = AppColors.statusSuccessText;
    } else if (module.triggerReason != null) {
      label = TrainingStrings.pillTriggered(module.triggerReason!);
      bg = AppColors.tagBlueSurface;
      fg = AppColors.tagBlueText;
    } else {
      label = TrainingStrings.pillNew;
      bg = AppColors.tagBlueSurface;
      fg = AppColors.tagBlueText;
    }

    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
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

void _openModule(BuildContext context, CoachingModule module) {
  debugPrint('[_VideoModuleCard] _openModule moduleId=${module.id} title=${module.titleEn}');
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ModulePlayerScreen(module: module),
    ),
  );
}

void _showLockedSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(TrainingStrings.lockedSnackbar),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
