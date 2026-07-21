/// Training screen — matches spice-coaching-android SDK layout exactly.
/// SDK: PersonalisedCoachingScreen → two tabs (Coaching | Leaderboard).
/// [TrainingBody] is kept public for use in assistant_screen.dart Training tab.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import 'all_modules_screen.dart';
import 'coaching_models.dart';
import 'coaching_repository.dart';
import 'module_detail_screen.dart';
import 'quiz_screen.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────

const _kSpiceBlue = Color(0xFF2514BE);
const _kSpiceBlueDark = Color(0xFF1A0EA0);
const _kSpiceBlueContainer = Color(0xFFE8F0FE);
const _kSpiceMid = Color(0xFF1565C0);
const _kMetaTextColor = Color(0xFF6B7280);
const _kGold = Color(0xFFFFC107);
const _kSilver = Color(0xFFBDBDBD);
const _kBronze = Color(0xFFCD7F32);
const _kXpBg = Color(0xFFE8F0FE);
const _kYouBg = Color(0xFF1B2B5E);
const _kDividerColor = Color(0xFFE4E7EC);

// ─── TrainingScreen ───────────────────────────────────────────────────────────

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kSpiceBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          TrainingStrings.personalisedCoaching,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          indicatorWeight: 2.5,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: const [
            Tab(text: TrainingStrings.tabCoaching),
            Tab(text: TrainingStrings.tabLeaderboard),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _CoachingContent(),
          _LeaderboardContent(),
        ],
      ),
    );
  }
}

// ─── TrainingBody (public — used by assistant_screen.dart) ────────────────────

class TrainingBody extends StatelessWidget {
  const TrainingBody({super.key});

  @override
  Widget build(BuildContext context) => const _CoachingContent();
}

// ─── Coaching tab content ─────────────────────────────────────────────────────

class _CoachingContent extends StatefulWidget {
  const _CoachingContent();

  @override
  State<_CoachingContent> createState() => _CoachingContentState();
}

class _CoachingContentState extends State<_CoachingContent> {
  @override
  void initState() {
    super.initState();
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

    if (repo.isSyncing && modules.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Morning quiz card
          if (priorities.isNotEmpty) ...[
            _SdkMorningCard(module: priorities.first),
            const SizedBox(height: 20),
          ],

          // Refreshers section
          const _SectionHeader(label: TrainingStrings.refreshersSection),
          const SizedBox(height: 8),
          const _RefreshersEmpty(),
          const SizedBox(height: 20),

          // Training section
          _TrainingSectionHeader(modules: modules),
          const SizedBox(height: 10),
          _TrainingHorizontalList(modules: modules),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── SDK Morning card ─────────────────────────────────────────────────────────

class _SdkMorningCard extends StatelessWidget {
  const _SdkMorningCard({required this.module});

  final CoachingModule module;

  String get _displayText {
    if (module.quiz.isNotEmpty) {
      final q = module.quiz.first;
      return q.questionBn.isNotEmpty ? q.questionBn : q.questionEn;
    }
    return module.titleBn.isNotEmpty ? module.titleBn : module.titleEn;
  }

  void _onTap(BuildContext context) {
    if (module.quiz.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => QuizScreen(module: module)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ModuleDetailScreen(module: module)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kSpiceBlue, _kSpiceBlueDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            TrainingStrings.morningCardMicrocoaching,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _displayText,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.4,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => _onTap(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white60, width: 1.5),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text(
              TrainingStrings.morningCardTapToAnswer,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Refreshers empty ─────────────────────────────────────────────────────────

class _RefreshersEmpty extends StatelessWidget {
  const _RefreshersEmpty();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 80,
      child: Center(
        child: Text(
          TrainingStrings.noRefreshersYet,
          style: TextStyle(color: _kMetaTextColor, fontSize: 14),
        ),
      ),
    );
  }
}

// ─── Training section ─────────────────────────────────────────────────────────

class _TrainingSectionHeader extends StatelessWidget {
  const _TrainingSectionHeader({required this.modules});

  final List<CoachingModule> modules;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          TrainingStrings.trainingSection,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AllModulesScreen(modules: modules),
            ),
          ),
          child: const Text(
            TrainingStrings.seeAll,
            style: TextStyle(color: _kSpiceBlue, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _TrainingHorizontalList extends StatelessWidget {
  const _TrainingHorizontalList({required this.modules});

  final List<CoachingModule> modules;

  @override
  Widget build(BuildContext context) {
    if (modules.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text(
            'No modules yet.',
            style: TextStyle(color: _kMetaTextColor),
          ),
        ),
      );
    }
    return SizedBox(
      height: 215,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: modules.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) => _TrainingModuleCard(module: modules[i]),
      ),
    );
  }
}

class _TrainingModuleCard extends StatelessWidget {
  const _TrainingModuleCard({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final title = module.titleBn.isNotEmpty ? module.titleBn : module.titleEn;
    final meta =
        '${module.estimatedMinutes} ${CoachingStrings.minLabel} · '
        '${module.quiz.length} ${CoachingStrings.detailQuestions}';
    final pct = '${(module.progressFraction * 100).toInt()}%';

    return GestureDetector(
      onTap: () {
        if (module.isLocked) {
          _showLockedSnackbar(context);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ModuleDetailScreen(module: module),
          ),
        );
      },
      child: Opacity(
        opacity: module.isLocked ? 0.6 : 1.0,
        child: SizedBox(
          width: 170,
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Container(
                    height: 100,
                    width: double.infinity,
                    color: _kSpiceBlueContainer,
                    alignment: Alignment.center,
                    child: module.isLocked
                        ? const Icon(Icons.lock_rounded, color: _kSpiceMid, size: 28)
                        : null,
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kMetaTextColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: module.progressFraction.clamp(0.0, 1.0),
                        color: _kSpiceBlue,
                        backgroundColor: _kSpiceBlueContainer,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pct,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kMetaTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Leaderboard tab ──────────────────────────────────────────────────────────

class _LeaderboardContent extends StatefulWidget {
  const _LeaderboardContent();

  @override
  State<_LeaderboardContent> createState() => _LeaderboardContentState();
}

class _LeaderboardContentState extends State<_LeaderboardContent> {
  int _filterIdx = 0;

  static const _filterLabels = [
    TrainingStrings.leaderboardFilterAllTime,
    TrainingStrings.leaderboardFilterThisMonth,
    TrainingStrings.leaderboardFilterThisWeek,
  ];

  @override
  Widget build(BuildContext context) {
    final entries = MockCoachingData.leaderboard;
    final top3 = entries.where((e) => e.rank <= 3).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final rest = entries
        .where((e) => e.rank > 3 && !e.isCurrentUser)
        .toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final me = entries.firstWhere(
      (e) => e.isCurrentUser,
      orElse: () => entries.last,
    );

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: List.generate(_filterLabels.length, (i) {
              final selected = i == _filterIdx;
              return Padding(
                padding: EdgeInsets.only(
                  right: i < _filterLabels.length - 1 ? 8 : 0,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _filterIdx = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? _kSpiceBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      border: selected
                          ? null
                          : Border.all(color: _kDividerColor),
                    ),
                    child: Text(
                      _filterLabels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // Context row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Text(
                TrainingStrings.leaderboardContext,
                style: const TextStyle(fontSize: 12, color: _kMetaTextColor),
              ),
              const Spacer(),
              Text(
                '${TrainingStrings.leaderboardUpdated} 12:00',
                style: const TextStyle(fontSize: 12, color: _kMetaTextColor),
              ),
            ],
          ),
        ),

        // Podium
        if (top3.isNotEmpty) _PodiumSection(top3: top3),

        // Scrollable list (ranks > 3, not current user)
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: rest.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) =>
                _LeaderboardRow(entry: rest[i], isYou: false),
          ),
        ),

        // Pinned "You" row
        _YouRow(entry: me),
      ],
    );
  }
}

class _PodiumSection extends StatelessWidget {
  const _PodiumSection({required this.top3});

  final List<LeaderboardEntry> top3;

  @override
  Widget build(BuildContext context) {
    final rank1 = top3.firstWhere(
      (e) => e.rank == 1,
      orElse: () => top3.first,
    );
    final rank2 = top3.firstWhere(
      (e) => e.rank == 2,
      orElse: () => top3.first,
    );
    final rank3 = top3.length >= 3
        ? top3.firstWhere((e) => e.rank == 3, orElse: () => top3.last)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _PodiumCard(
              entry: rank2,
              badgeColor: _kSilver,
              avatarRadius: 26,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PodiumCard(
              entry: rank1,
              badgeColor: _kGold,
              avatarRadius: 32,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: rank3 != null
                ? _PodiumCard(
                    entry: rank3,
                    badgeColor: _kBronze,
                    avatarRadius: 26,
                  )
                : const SizedBox(),
          ),
        ],
      ),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.entry,
    required this.badgeColor,
    required this.avatarRadius,
  });

  final LeaderboardEntry entry;
  final Color badgeColor;
  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: avatarRadius,
                backgroundColor: _kSpiceBlueContainer,
                child: Text(
                  entry.initials,
                  style: TextStyle(
                    fontSize: avatarRadius * 0.5,
                    fontWeight: FontWeight.bold,
                    color: _kSpiceBlue,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.points} ${TrainingStrings.xpSuffix}',
                style: const TextStyle(fontSize: 11, color: _kMetaTextColor),
              ),
              if (entry.streakDays > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '🔥 ${entry.streakDays}${TrainingStrings.streakDaySuffix}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Rank badge
        CircleAvatar(
          radius: 14,
          backgroundColor: badgeColor,
          child: Text(
            '${entry.rank}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.isYou});

  final LeaderboardEntry entry;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isYou ? _kYouBg : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: isYou
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isYou ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 20,
            backgroundColor:
                isYou ? Colors.white24 : _kSpiceBlueContainer,
            child: Text(
              entry.initials,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isYou ? Colors.white : _kSpiceBlue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isCurrentUser
                      ? TrainingStrings.youLabel
                      : entry.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isYou ? Colors.white : Colors.black87,
                  ),
                ),
                if (entry.streakDays > 0)
                  Text(
                    '🔥 ${entry.streakDays}${TrainingStrings.streakDaySuffix}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isYou ? Colors.white70 : _kMetaTextColor,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isYou ? Colors.white24 : _kXpBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${entry.points} ${TrainingStrings.xpSuffix}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isYou ? Colors.white : _kSpiceBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YouRow extends StatelessWidget {
  const _YouRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 12,
        top: 8,
      ),
      child: _LeaderboardRow(entry: entry, isYou: true),
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
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _showLockedSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(TrainingStrings.lockedSnackbar),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
