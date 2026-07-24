import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/programme.dart';
import '../../core/theme/app_theme.dart';
import 'sk_performance_repository.dart';

final _cardDateFmt = DateFormat('dd MMM yyyy');

// ── Spice Android due-info colors ─────────────────────────────────────────────
const _kColorOverdue  = Color(0xFF994242);
const _kColorToday    = Color(0xFFEB956A);
const _kColorUpcoming = Color(0xFF54CC90);
const _kColorRoutine  = Color(0xFF667085);

// ── My Patients data model ────────────────────────────────────────────────────

class _PatientItem {
  const _PatientItem({
    required this.patient,
    required this.programmes,
  });
  final Patient patient;
  final Set<Programme> programmes;

  String get primaryService {
    if (programmes.contains(Programme.anc)) return 'ANC';
    if (programmes.contains(Programme.pnc)) return 'PNC';
    if (programmes.contains(Programme.ncd)) return 'NCD';
    if (programmes.contains(Programme.imci)) return 'IMCI';
    if (programmes.contains(Programme.epi)) return 'EPI';
    if (programmes.contains(Programme.familyPlanning)) return 'FP';
    if (programmes.contains(Programme.eyeCare)) return 'Eye Care';
    if (programmes.contains(Programme.cataract)) return 'Cataract';
    if (programmes.isNotEmpty) return programmes.first.name.toUpperCase();
    return '—';
  }

  /// Positive = days overdue, 0 = today, negative = days until due.
  int? get daysDelta {
    final due = patient.nextDueAt;
    if (due == null) return null;
    final dueDate = DateTime.fromMillisecondsSinceEpoch(due);
    return DateTime.now().difference(dueDate).inDays;
  }
}

Future<List<_PatientItem>> _loadMyPatients(AppDatabase db) async {
  final patientDao = PatientDao(db);
  final progDao = PatientProgrammesDao(db);
  final rows = await patientDao.queryWorklist(limit: 200);
  final patients = rows.map(Patient.fromDb).toList();
  final ids = patients.map((p) => p.id).toList();
  final progMap = await progDao.programmesForMany(ids);
  return patients
      .map((p) => _PatientItem(patient: p, programmes: progMap[p.id] ?? const {}))
      .toList();
}

// ── Screen ────────────────────────────────────────────────────────────────────

class SkPerformanceScreen extends StatefulWidget {
  const SkPerformanceScreen({super.key});

  @override
  State<SkPerformanceScreen> createState() => _SkPerformanceScreenState();
}

class _SkPerformanceScreenState extends State<SkPerformanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _showMonth = false;
  late Future<SkPerformanceStats> _statsFuture;
  late Future<List<_PatientItem>> _patientsFuture;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _load() {
    final db = context.read<AppDatabase>();
    _statsFuture = SkPerformanceRepository(db).load();
    _patientsFuture = _loadMyPatients(db);
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
            Text(
              '📊 ${PerformanceStrings.title}',
              style: const TextStyle(
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
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Performance'),
            Tab(text: 'My Patients'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Tab 0: Performance stats ──────────────────────────────────
          FutureBuilder<SkPerformanceStats>(
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
                  _HeroCard(stats: stats, showMonth: _showMonth),
                  const SizedBox(height: 14),
                  _VisitTrendCard(stats: stats, showMonth: _showMonth),
                  const SizedBox(height: 14),
                  _StatsGrid(stats: stats, showMonth: _showMonth),
                  const SizedBox(height: 14),
                  _ServiceBreakdownCard(stats: stats, showMonth: _showMonth),
                  const SizedBox(height: 14),
                  _InsightStrip(stats: stats, showMonth: _showMonth),
                ],
              );
            },
          ),

          // ── Tab 1: My Patients ────────────────────────────────────────
          FutureBuilder<List<_PatientItem>>(
            future: _patientsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorView(onRetry: _retry);
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'No patients',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: items.length,
                separatorBuilder: (context, i) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _MyPatientCard(
                  item: items[i],
                  onTap: () {
                    final pid = items[i].patient.id;
                    if (pid.isNotEmpty) context.push('/patients/$pid');
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── My Patients card (Spice Android style) ────────────────────────────────────

class _MyPatientCard extends StatelessWidget {
  const _MyPatientCard({required this.item, required this.onTap});
  final _PatientItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = item.patient;
    final nextDue = p.nextDueAt != null
        ? _cardDateFmt.format(DateTime.fromMillisecondsSinceEpoch(p.nextDueAt!))
        : '—';
    final lastVisit = p.lastVisitAt != null
        ? _cardDateFmt.format(DateTime.fromMillisecondsSinceEpoch(p.lastVisitAt!))
        : HouseholdDetailStrings.neverVisited;

    final agePart = p.age != null ? '${p.age}' : null;
    final genderPart = p.gender?.substring(0, 1).toUpperCase();
    final agGender = [agePart, genderPart].whereType<String>().join('/');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: const Border(
              left: BorderSide(color: AppColors.border, width: 4),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + chevron
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name ?? CommonStrings.unnamed,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
                ],
              ),
              // Age / Gender
              if (agGender.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    agGender,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Service
              _SpiceRow(label: 'Service', value: item.primaryService),
              // Next Visit
              _SpiceRow(label: 'Next Visit', value: nextDue),
              // Last Visit
              _SpiceRow(label: 'Last Visit', value: lastVisit),
              const SizedBox(height: 6),
              // Due info text
              _SpiceDueText(delta: item.daysDelta),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpiceRow extends StatelessWidget {
  const _SpiceRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF667085),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101828),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpiceDueText extends StatelessWidget {
  const _SpiceDueText({required this.delta});
  final int? delta;

  @override
  Widget build(BuildContext context) {
    final (text, color) = _resolve();
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }

  (String, Color) _resolve() {
    final d = delta;
    if (d == null) return ('Routine', _kColorRoutine);
    if (d < 0) {
      final days = d.abs();
      if (days == 1) return ('Tomorrow', _kColorUpcoming);
      return ('Upcoming in $days days', _kColorUpcoming);
    }
    if (d == 0) return ('Today', _kColorToday);
    return ('$d day(s) Overdue', _kColorOverdue);
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
  const _HeroCard({required this.stats, required this.showMonth});

  final SkPerformanceStats stats;
  final bool showMonth;

  @override
  Widget build(BuildContext context) {
    final score = showMonth ? stats.performanceScoreMonth : stats.performanceScore;
    final rating = showMonth ? stats.performanceRatingMonth : stats.performanceRating;
    final emoji  = showMonth ? stats.performanceEmojiMonth : stats.performanceEmoji;
    final slaText = '${(stats.slaCompliance * 100).round()}%';
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
                    Text(
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
                      '$rating $emoji',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
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
  const _VisitTrendCard({required this.stats, required this.showMonth});

  final SkPerformanceStats stats;
  final bool showMonth;

  @override
  Widget build(BuildContext context) {
    final counts = showMonth
        ? stats.weeklyVisitCounts
        : stats.dailyVisitCounts;
    final labels = showMonth
        ? PerformanceStrings.weekLabels
        : PerformanceStrings.weekdayLabels;
    final maxCount =
        counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);
    const maxBarH = 56.0;

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                PerformanceStrings.visitTrendLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
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
            height: maxBarH + 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(counts.length, (i) {
                final c = counts[i];
                final barH =
                    maxCount > 0 ? (c / maxCount) * maxBarH : 2.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
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
                            color: AppColors.aiPurple.withAlpha(180),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          labels.length > i ? labels[i] : '',
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
  const _StatsGrid({required this.stats, required this.showMonth});

  final SkPerformanceStats stats;
  final bool showMonth;

  @override
  Widget build(BuildContext context) {
    final visits = showMonth ? stats.visitsThisMonth : stats.visitsThisWeek;
    final target = showMonth
        ? SkPerformanceStats.visitsTargetMonth
        : SkPerformanceStats.visitsTarget;
    final referrals =
        showMonth ? stats.referralsThisMonth : stats.referralsThisWeek;
    final avgVisits = showMonth
        ? stats.avgVisitsPerDayMonth
        : stats.avgVisitsPerDay;
    final completionPct = referrals > 0
        ? ((stats.referralsCompleted / referrals) * 100).round()
        : 0;

    final tiles = [
      _StatTileData(
        icon: Icons.check_rounded,
        color: AppColors.navy,
        value: '$visits / $target',
        label: PerformanceStrings.statVisitsCompleted,
      ),
      _StatTileData(
        icon: Icons.assignment_outlined,
        color: const Color(0xFFF59E0B),
        value: '$referrals',
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
        value: avgVisits.toStringAsFixed(1),
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
  const _ServiceBreakdownCard({required this.stats, required this.showMonth});

  final SkPerformanceStats stats;
  final bool showMonth;

  @override
  Widget build(BuildContext context) {
    final byProg = showMonth ? stats.visitsByProgrammeMonth : stats.visitsByProgramme;
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
          Text(
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
  const _InsightStrip({required this.stats, required this.showMonth});

  final SkPerformanceStats stats;
  final bool showMonth;

  @override
  Widget build(BuildContext context) {
    const pct = 12;
    final full = showMonth
        ? PerformanceStrings.insightMonth(pct)
        : PerformanceStrings.insightWeek(pct);
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
            child: Text(CommonStrings.retry),
          ),
        ],
      ),
    );
  }
}
