import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/spice_dashboard_dao.dart';
import 'sk_dashboard_card_catalog.dart';
import 'sk_dashboard_gating.dart';
import 'sk_spice_dashboard_repository.dart';

/// SK dashboard — same layout as Spice: date range, filter, single KPI list.
class SkKpiDashboardTab extends StatefulWidget {
  const SkKpiDashboardTab({super.key});

  @override
  State<SkKpiDashboardTab> createState() => _SkKpiDashboardTabState();
}

class _SkKpiDashboardTabState extends State<SkKpiDashboardTab> {
  late DateTime _from;
  late DateTime _to;
  Future<SpiceDashboardCounts>? _future;
  final Set<String> _selectedSsIds = {};
  final Set<String> _selectedSubVillageIds = {};
  late final SkDashboardGating _gating = SkDashboardGating.fromFormConfig();

  bool _depsReady = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day);
    _to = _from;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_depsReady) {
      _depsReady = true;
      _reload();
    }
  }

  void _reload() {
    final repo = context.read<SkSpiceDashboardRepository>();
    setState(() {
      _future = repo.load(
        from: _from,
        to: _to,
        ssIds: _selectedSsIds.toList(),
        subVillageIds: _selectedSubVillageIds.toList(),
      );
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = DateTime(picked.year, picked.month, picked.day);
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = DateTime(picked.year, picked.month, picked.day);
        if (_to.isBefore(_from)) _from = _to;
      }
    });
    _reload();
  }

  Future<void> _openFilters() async {
    final hierarchy = context.read<UserHierarchyService>();
    final ssWorkers = hierarchy.ssWorkers ?? const [];
    final subVillages = hierarchy.subVillages ?? const [];

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    PerformanceStrings.dashboardFilterTitle,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(PerformanceStrings.dashboardFilterSs,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final ss in ssWorkers)
                        FilterChip(
                          label: Text(ss.name),
                          selected: _selectedSsIds.contains(ss.id),
                          onSelected: (v) {
                            setModal(() {
                              if (v) {
                                _selectedSsIds.add(ss.id);
                              } else {
                                _selectedSsIds.remove(ss.id);
                              }
                              _selectedSubVillageIds.clear();
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(PerformanceStrings.dashboardFilterSubVillage,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final sv in subVillages)
                        FilterChip(
                          label: Text(sv.name),
                          selected: _selectedSubVillageIds.contains(sv.id),
                          onSelected: (v) {
                            setModal(() {
                              if (v) {
                                _selectedSubVillageIds.add(sv.id);
                              } else {
                                _selectedSubVillageIds.remove(sv.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _reload();
                    },
                    child: Text(PerformanceStrings.dashboardFilterApply),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Column(
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _DateChip(
                    label: PerformanceStrings.dashboardFrom,
                    value: df.format(_from),
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateChip(
                    label: PerformanceStrings.dashboardTo,
                    value: df.format(_to),
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
                IconButton(
                  tooltip: PerformanceStrings.dashboardFilterTitle,
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: _selectedSsIds.isNotEmpty ||
                        _selectedSubVillageIds.isNotEmpty,
                    smallSize: 8,
                    child: const Icon(Icons.filter_list),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<SpiceDashboardCounts>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(PerformanceStrings.dashboardLoadError),
                );
              }
              final c = snapshot.data ?? const SpiceDashboardCounts();
              final cards = SkDashboardCardCatalog.services(c, _gating);
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _KpiCard(
                  title: cards[i].title,
                  count: cards[i].count,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
