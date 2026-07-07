import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
  bool _showMonth = false;
  late Future<SkPerformanceStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final db = context.read<AppDatabase>();
    _statsFuture = SkPerformanceRepository(db).load();
  }

  void _retry() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.textOnNavy,
        elevation: 0,
        title: const Text(
          PerformanceStrings.title,
          style: TextStyle(
            color: AppColors.textOnNavy,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: false,
      ),
      body: FutureBuilder<SkPerformanceStats>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorView(onRetry: _retry);
          }
          final stats = snapshot.data!;
          final visitCount =
              _showMonth ? stats.visitsThisMonth : stats.visitsThisWeek;
          return ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _PeriodToggle(
                showMonth: _showMonth,
                onToggle: (v) => setState(() => _showMonth = v),
              ),
              const SizedBox(height: 14),
              _HeroCard(
                visitCount: visitCount,
                showMonth: _showMonth,
                stats: stats,
              ),
              const SizedBox(height: 14),
              _StatGrid(stats: stats, showMonth: _showMonth),
              const SizedBox(height: 20),
              _ProgrammeStrip(stats: stats),
              const SizedBox(height: 20),
              _RecentActivity(items: stats.recentActivity),
            ],
          );
        },
      ),
    );
  }
}

// ── Period toggle ──────────────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({
    required this.showMonth,
    required this.onToggle,
  });

  final bool showMonth;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _Tab(
            label: PerformanceStrings.periodWeek,
            active: !showMonth,
            onTap: () => onToggle(false),
          ),
          _Tab(
            label: PerformanceStrings.periodMonth,
            active: showMonth,
            onTap: () => onToggle(true),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: active ? AppColors.cardSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.navy : AppColors.onDarkMid,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.visitCount,
    required this.showMonth,
    required this.stats,
  });

  final int visitCount;
  final bool showMonth;
  final SkPerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    final progress =
        (visitCount / SkPerformanceStats.weeklyTarget).clamp(0.0, 1.0);
    final periodLabel = showMonth
        ? PerformanceStrings.periodLabelMonth(stats.monthStartDate)
        : PerformanceStrings.periodLabelWeek(
            stats.weekStartDate,
            stats.weekStartDate.add(const Duration(days: 6)),
          );

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.aiPurpleDark, AppColors.aiPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel,
            style: const TextStyle(
              color: AppColors.onDarkMid,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$visitCount',
                style: const TextStyle(
                  color: AppColors.textOnNavy,
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  PerformanceStrings.heroSubline,
                  style: const TextStyle(
                    color: AppColors.onDarkLow,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!showMonth) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  PerformanceStrings.weeklyTarget,
                  style: const TextStyle(
                    color: AppColors.onDarkLow,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$visitCount / ${SkPerformanceStats.weeklyTarget}',
                  style: const TextStyle(
                    color: AppColors.textOnNavy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.onDarkSurface,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.pink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stat grid ─────────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.showMonth});

  final SkPerformanceStats stats;
  final bool showMonth;

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
          accentColor: AppColors.aiPurpleDark,
        ),
        _StatCard(
          value: '${stats.totalHouseholds}',
          label: PerformanceStrings.statHouseholds,
          subline: PerformanceStrings.statHouseholdsSub,
          accentColor: AppColors.navy,
        ),
        _StatCard(
          value: '${stats.referralsThisWeek}',
          label: PerformanceStrings.statReferrals,
          subline: PerformanceStrings.statReferralsSub,
          accentColor: AppColors.statusWarning,
        ),
        _StatCard(
          value: showMonth
              ? '${stats.visitsThisMonth}'
              : '${stats.visitsThisWeek}',
          label: showMonth
              ? PerformanceStrings.statThisMonth
              : PerformanceStrings.statThisWeek,
          subline: PerformanceStrings.statTotalVisitsSub,
          accentColor: AppColors.statusSuccess,
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
    required this.accentColor,
  });

  final String value;
  final String label;
  final String subline;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border(top: BorderSide(color: accentColor, width: 3)),
        boxShadow: AppShadows.statBox,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: accentColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMid,
                ),
              ),
              Text(
                subline,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textDisabled,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Programme strip ────────────────────────────────────────────────────────────

class _ProgrammeStrip extends StatelessWidget {
  const _ProgrammeStrip({required this.stats});

  final SkPerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PerformanceStrings.sectionProgramme,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ProgCard(
                label: 'IMCI',
                count: stats.visitsByProgramme['IMCI'] ?? 0,
                color: AppColors.imciHeader,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ProgCard(
                label: 'ANC',
                count: stats.visitsByProgramme['ANC'] ?? 0,
                color: AppColors.ancHeader,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ProgCard(
                label: 'NCD',
                count: stats.visitsByProgramme['NCD'] ?? 0,
                color: AppColors.ncdHeader,
              ),
            ),
          ],
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.field),
        boxShadow: AppShadows.statBox,
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            'visits',
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha:0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recent activity ────────────────────────────────────────────────────────────

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.items});

  final List<RecentVisitActivity> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    String dateHeader(DateTime dt) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(dt.year, dt.month, dt.day);
      if (d == today) return PerformanceStrings.today;
      if (d == today.subtract(const Duration(days: 1))) {
        return PerformanceStrings.yesterday;
      }
      return DateFormat('MMM d').format(dt);
    }

    final grouped = <String, List<RecentVisitActivity>>{};
    for (final item in items) {
      final key = dateHeader(item.createdAt);
      grouped.putIfAbsent(key, () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PerformanceStrings.sectionRecent,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(AppRadius.button),
            boxShadow: AppShadows.statBox,
          ),
          child: Column(
            children: [
              for (final entry in grouped.entries) ...[
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDisabled,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                for (int i = 0; i < entry.value.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, indent: 56, endIndent: 14, thickness: 0.5),
                  _ActivityRow(item: entry.value[i]),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final RecentVisitActivity item;

  @override
  Widget build(BuildContext context) {
    final initial =
        item.patientName.isNotEmpty ? item.patientName[0].toUpperCase() : '?';
    final canNavigate = item.patientId != null;

    return InkWell(
      onTap: canNavigate
          ? () => context.push('/patients/${item.patientId}')
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.aiPurpleDark.withValues(alpha: 0.12),
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.aiPurpleDark,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textStrong,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${item.programme}  ·  ${item.villageName}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: item.isReferred
                        ? AppColors.statusWarning.withValues(alpha: 0.12)
                        : AppColors.statusSuccess.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.isReferred
                        ? PerformanceStrings.badgeReferred
                        : PerformanceStrings.badgeCompleted,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: item.isReferred
                          ? AppColors.statusWarning
                          : AppColors.statusSuccess,
                    ),
                  ),
                ),
                if (canNavigate)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.borderDashed,
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

// ── Error view ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: AppColors.textDisabled),
          const SizedBox(height: 12),
          Text(
            PerformanceStrings.loadError,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text(CommonStrings.retry),
          ),
        ],
      ),
    );
  }
}
