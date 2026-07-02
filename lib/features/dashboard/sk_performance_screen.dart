import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import 'sk_performance_repository.dart';

class SkPerformanceScreen extends StatefulWidget {
  const SkPerformanceScreen({super.key});

  @override
  State<SkPerformanceScreen> createState() => _SkPerformanceScreenState();
}

class _SkPerformanceScreenState extends State<SkPerformanceScreen> {
  bool _weekView = true;
  SkPerformanceStats? _stats;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = SkPerformanceRepository(context.read<AppDatabase>());
      final stats = await repo.load();
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: tokens.brandNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          PerformanceStrings.title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _PeriodToggle(
              weekView: _weekView,
              onChanged: (v) => setState(() => _weekView = v),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _Body(stats: _stats!, weekView: _weekView),
                ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.weekView, required this.onChanged});

  final bool weekView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tab(
            label: PerformanceStrings.periodWeek,
            active: weekView,
            onTap: () => onChanged(true),
          ),
          _Tab(
            label: PerformanceStrings.periodMonth,
            active: !weekView,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active
                ? AppColors.aiPurpleDark
                : Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats, required this.weekView});

  final SkPerformanceStats stats;
  final bool weekView;

  @override
  Widget build(BuildContext context) {
    final visits = weekView ? stats.visitsThisWeek : stats.visitsThisMonth;
    final target = weekView ? stats.weekTarget : stats.weekTarget * 4;
    final progress = (visits / target).clamp(0.0, 1.0);

    final now = DateTime.now();
    final weekday = now.weekday;
    final weekStart = now.subtract(Duration(days: weekday - 1));
    final periodLabel = weekView
        ? PerformanceStrings.periodLabelWeek(weekStart, now)
        : PerformanceStrings.periodLabelMonth(now);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      children: [
        _HeroCard(
          visits: visits,
          target: target,
          progress: progress,
          periodLabel: periodLabel,
          streak: _computeStreak(),
        ),
        const SizedBox(height: 12),
        _StatGrid(stats: stats, weekView: weekView),
        const SizedBox(height: 12),
        _ProgrammeStrip(byProgramme: stats.visitsByProgramme, weekView: weekView),
        const SizedBox(height: 12),
        _RecentActivity(items: stats.recentActivity),
      ],
    );
  }

  // Naive streak: count consecutive days with ≥1 visit back from today.
  // Real implementation would query per-day counts; for now returns a fixed
  // placeholder since daily-bucketed counts require an extra query.
  int _computeStreak() => 0;
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.visits,
    required this.target,
    required this.progress,
    required this.periodLabel,
    required this.streak,
  });

  final int visits;
  final int target;
  final double progress;
  final String periodLabel;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.aiPurpleDark, Color(0xFF5448C8)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$visits',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -2,
                    height: 1,
                  ),
                ),
                const TextSpan(
                  text: '  visits',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white54,
                    letterSpacing: 0,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            PerformanceStrings.heroSubline,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                PerformanceStrings.weeklyTarget,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$visits / $target',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.pink),
              minHeight: 5,
            ),
          ),
          if (streak > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                PerformanceStrings.streak(streak),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 2×2 stat grid ─────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.weekView});

  final SkPerformanceStats stats;
  final bool weekView;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        _StatCard(
          value: '${stats.visitsToday}',
          label: PerformanceStrings.statVisitsToday,
          subline: PerformanceStrings.statVisitsTodaySub,
          accent: AppColors.aiPurpleDark,
          pulsing: true,
        ),
        _StatCard(
          value: '${stats.householdsTotal}',
          label: PerformanceStrings.statHouseholds,
          subline: PerformanceStrings.statHouseholdsSub,
          accent: AppColors.statusSuccess,
        ),
        _StatCard(
          value: '${stats.referralsThisWeek}',
          label: PerformanceStrings.statReferrals,
          subline: PerformanceStrings.statReferralsSub,
          accent: AppColors.statusWarning,
        ),
        _StatCard(
          value: weekView
              ? '${stats.visitsThisWeek}'
              : '${stats.visitsThisMonth}',
          label: weekView
              ? PerformanceStrings.statThisWeek
              : PerformanceStrings.statThisMonth,
          subline: PerformanceStrings.statTotalVisitsSub,
          accent: AppColors.pink,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.subline,
    required this.accent,
    this.pulsing = false,
  });

  final String value;
  final String label;
  final String subline;
  final Color accent;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: accent,
                              height: 1,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (pulsing) ...[
                            const SizedBox(width: 4),
                            _PulseDot(color: accent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subline,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: accent.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Programme strip ───────────────────────────────────────────────────────────

class _ProgrammeStrip extends StatelessWidget {
  const _ProgrammeStrip({
    required this.byProgramme,
    required this.weekView,
  });

  final Map<String, int> byProgramme;
  final bool weekView;

  static const _programmes = [
    (key: 'IMCI', color: AppColors.imciHeader),
    (key: 'ANC', color: AppColors.ancHeader),
    (key: 'NCD', color: AppColors.ncdHeader),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            PerformanceStrings.sectionProgramme,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        Row(
          children: _programmes.map((p) {
            final count = byProgramme[p.key] ?? 0;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ProgCard(
                  label: p.key,
                  count: count,
                  color: p.color,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ProgCard extends StatelessWidget {
  const _ProgCard({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: color.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent activity ───────────────────────────────────────────────────────────

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.items});

  final List<RecentVisitActivity> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final yesterday = todayStart.subtract(const Duration(days: 1));

    String dateHeader(DateTime dt) {
      final d = DateTime(dt.year, dt.month, dt.day);
      if (!d.isBefore(todayStart)) return PerformanceStrings.today;
      if (!d.isBefore(yesterday)) return PerformanceStrings.yesterday;
      return '${dt.day}/${dt.month}/${dt.year}';
    }

    String? lastHeader;
    final rows = <Widget>[];
    for (final item in items) {
      final header = dateHeader(item.createdAt);
      if (header != lastHeader) {
        lastHeader = header;
        rows.add(_ActivitySectionHeader(label: header));
      }
      rows.add(_ActivityRow(item: item));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            PerformanceStrings.sectionRecent,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _ActivitySectionHeader extends StatelessWidget {
  const _ActivitySectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F2F8))),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF374151),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final RecentVisitActivity item;

  Color _progColor(String prog) {
    switch (prog) {
      case 'IMCI':
        return AppColors.imciHeader;
      case 'ANC':
        return AppColors.ancHeader;
      case 'NCD':
        return AppColors.ncdHeader;
      default:
        return AppColors.aiPurpleDark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _progColor(item.programme);
    final badge = item.isReferred
        ? (
            label: PerformanceStrings.badgeReferred,
            bg: const Color(0xFFFEF3C7),
            fg: const Color(0xFF92400E),
          )
        : (
            label: PerformanceStrings.badgeCompleted,
            bg: const Color(0xFFD1FAE5),
            fg: const Color(0xFF065F46),
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF9FAFB))),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                item.programme.isNotEmpty ? item.programme[0] : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.patientName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  [
                    item.programme,
                    if (item.villageName != null) item.villageName!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: badge.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badge.label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: badge.fg,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(PerformanceStrings.loadError),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text(CommonStrings.retry),
          ),
        ],
      ),
    );
  }
}
