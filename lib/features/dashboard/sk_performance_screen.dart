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
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 60,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 ${PerformanceStrings.title}',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            Text(
              PerformanceStrings.appBarSubtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
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
          return ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _PeriodToggle(
                showMonth: _showMonth,
                onToggle: (v) => setState(() => _showMonth = v),
              ),
              const SizedBox(height: 14),
              _HeroCard(stats: stats),
              const SizedBox(height: 14),
              _VisitTrendCard(stats: stats),
              const SizedBox(height: 14),
              _StatsGrid(stats: stats),
              const SizedBox(height: 14),
              _ServiceBreakdownCard(stats: stats),
              const SizedBox(height: 14),
              _InsightStrip(stats: stats),
            ],
          );
        },
      ),
    );
  }
}

// ── Period toggle ──────────────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.showMonth, required this.onToggle});

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
          _ToggleTab(
            label: PerformanceStrings.periodWeek,
            active: !showMonth,
            onTap: () => onToggle(false),
          ),
          _ToggleTab(
            label: PerformanceStrings.periodMonth,
            active: showMonth,
            onTap: () => onToggle(true),
          ),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
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
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.navy : AppColors.aiPurple,
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
  const _HeroCard({required this.stats});

  final SkPerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    final score = stats.performanceScore;
    final slaText =
        '${(stats.slaCompliance * 100).round()}%';
    final hrText = '${stats.highRiskResponseDays}d';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B2B5E), Color(0xFF2D3F7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circle gauge
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 7,
                        backgroundColor:
                            Colors.white.withAlpha(40),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF10B981),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$score',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                        const Text(
                          '/ 100',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Text block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      PerformanceStrings.heroScoreLabel,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stats.performanceRating} ${stats.performanceEmoji}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      PerformanceStrings.heroDesc,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(
              color: Colors.white.withAlpha(40),
              height: 1,
            ),
          ),

          // SLA + High-risk row
          Row(
            children: [
              Expanded(
                child: _MetricCell(
                  label: PerformanceStrings.slaLabel,
                  value: slaText,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withAlpha(40),
              ),
              Expanded(
                child: _MetricCell(
                  label: PerformanceStrings.highRiskLabel,
                  value: hrText,
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    this.align = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ── Visit trend card ──────────────────────────────────────────────────────────

class _VisitTrendCard extends StatelessWidget {
  const _VisitTrendCard({required this.stats});

  final SkPerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    final counts = stats.dailyVisitCounts;
    final maxCount =
        counts.reduce((a, b) => a > b ? a : b).toDouble();
    const maxBarH = 56.0;

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                PerformanceStrings.visitTrendLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Text(
                PerformanceStrings.trendSteady,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: maxBarH + 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final c = counts.length > i ? counts[i] : 0;
                final barH =
                    maxCount > 0 ? (c / maxCount) * maxBarH : 2.0;
                return Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (c > 0)
                          Text(
                            '$c',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                        const SizedBox(height: 3),
                        Container(
                          height: barH.clamp(2.0, maxBarH),
                          decoration: BoxDecoration(
                            color: AppColors.aiPurple
                                .withAlpha(180),
                            borderRadius:
                                const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          PerformanceStrings.weekdayLabels[i],
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats grid ────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final SkPerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    final completionPct = stats.referralsThisWeek > 0
        ? ((stats.referralsCompleted / stats.referralsThisWeek) * 100)
            .round()
        : 0;

    final tiles = [
      _StatTileData(
        icon: Icons.check_rounded,
        color: AppColors.navy,
        value: '${stats.visitsThisWeek} / ${SkPerformanceStats.visitsTarget}',
        label: PerformanceStrings.statVisitsCompleted,
      ),
      _StatTileData(
        icon: Icons.assignment_outlined,
        color: const Color(0xFFF59E0B),
        value: '${stats.referralsThisWeek}',
        label: PerformanceStrings.statReferralsMade,
      ),
      _StatTileData(
        icon: Icons.check_box_rounded,
        color: const Color(0xFF10B981),
        value: '${stats.referralsCompleted}',
        subValue: '$completionPct%',
        label: PerformanceStrings.statReferralsCompleted,
      ),
      _StatTileData(
        icon: Icons.home_rounded,
        color: AppColors.aiPurple,
        value: '${stats.totalHouseholds}',
        label: PerformanceStrings.statHouseholdsCovered,
      ),
      _StatTileData(
        icon: Icons.bolt_rounded,
        color: const Color(0xFFF59E0B),
        value: stats.avgVisitsPerDay.toStringAsFixed(1),
        label: PerformanceStrings.statAvgVisitsDay,
      ),
      _StatTileData(
        icon: Icons.alarm_rounded,
        color: const Color(0xFFEF4444),
        value: '${stats.missedOverdue}',
        label: PerformanceStrings.statMissedOverdue,
        valueIsRed: true,
      ),
    ];

    return Column(
      children: [
        for (int row = 0; row < 3; row++) ...[
          if (row > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _StatTile(data: tiles[row * 2])),
              const SizedBox(width: 10),
              Expanded(child: _StatTile(data: tiles[row * 2 + 1])),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatTileData {
  const _StatTileData({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.subValue,
    this.valueIsRed = false,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? subValue;
  final bool valueIsRed;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.data});

  final _StatTileData data;

  @override
  Widget build(BuildContext context) {
    final valueColor =
        data.valueIsRed ? const Color(0xFFEF4444) : data.color;

    return _WhiteCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: data.color, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      data.value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: valueColor,
                        height: 1,
                      ),
                    ),
                    if (data.subValue != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        data.subValue!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: data.color,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Service breakdown card ────────────────────────────────────────────────────

class _ServiceBreakdownCard extends StatelessWidget {
  const _ServiceBreakdownCard({required this.stats});

  final SkPerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    final byProg = stats.visitsByProgramme;
    final rows = [
      (PerformanceStrings.serviceAnc, byProg['ANC'] ?? 0, AppColors.ancHeader),
      (PerformanceStrings.serviceNcd, byProg['NCD'] ?? 0, const Color(0xFFF59E0B)),
      (PerformanceStrings.serviceChild, byProg['IMCI'] ?? 0, AppColors.aiPurpleDark),
      (PerformanceStrings.servicePnc, byProg['PNC'] ?? 0, AppColors.aiPurple),
      (PerformanceStrings.serviceHousehold, byProg['HOUSEHOLD'] ?? 0, AppColors.statusSuccess),
    ];

    final maxCount =
        rows.map((r) => r.$2).reduce((a, b) => a > b ? a : b);
    final denom = maxCount > 0 ? maxCount.toDouble() : 1.0;

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            PerformanceStrings.sectionServiceBreakdown,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          for (final (label, count, color) in rows) ...[
            _ServiceRow(
                label: label, count: count, color: color, denom: denom),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.label,
    required this.count,
    required this.color,
    required this.denom,
  });

  final String label;
  final int count;
  final Color color;
  final double denom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Spacer(),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: count / denom,
            minHeight: 6,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ── Insight strip ─────────────────────────────────────────────────────────────

class _InsightStrip extends StatelessWidget {
  const _InsightStrip({required this.stats});

  final SkPerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    const pct = 12;
    final full = PerformanceStrings.insightWeek(pct);
    final boldPhrase = '$pct% ${PerformanceStrings.insightBoldPhrase}';
    final idx = full.indexOf(boldPhrase);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ancSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.show_chart_rounded,
            color: AppColors.ancHeader,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: idx < 0
                ? Text(full,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMid))
                : Text.rich(
                    TextSpan(
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMid),
                      children: [
                        TextSpan(text: full.substring(0, idx)),
                        TextSpan(
                          text: boldPhrase,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ancHeader,
                          ),
                        ),
                        TextSpan(
                            text: full.substring(idx + boldPhrase.length)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Shared card container ─────────────────────────────────────────────────────

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
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
          const Icon(Icons.error_outline,
              size: 40, color: AppColors.textDisabled),
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
