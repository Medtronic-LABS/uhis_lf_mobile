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

/// SK (Shasthya Kormi) KPI dashboard for Leapfrog mobile — SK users only.
///
/// Matches Spice [DashboardFragment] when `shouldShowSkRmnchKpis()` is true:
/// Services | Demographic tabs, date range, SS / sub-village filters (not FO/PO SK picker).
class SkKpiDashboardTab extends StatefulWidget {
  const SkKpiDashboardTab({super.key});

  @override
  State<SkKpiDashboardTab> createState() => _SkKpiDashboardTabState();
}

enum _SkDashboardTab { services, demographic }

class _SkKpiDashboardTabState extends State<SkKpiDashboardTab> {
  late DateTime _from;
  late DateTime _to;
  Future<SpiceDashboardCounts>? _future;
  final Set<String> _selectedSsIds = {};
  final Set<String> _selectedSubVillageIds = {};
  late final SkDashboardGating _gating = SkDashboardGating.fromFormConfig();
  _SkDashboardTab _tab = _SkDashboardTab.services;
  SkDashboardServicesCategory _serviceCategory =
      SkDashboardServicesCategory.all;

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

  SkDashboardServicesCategory _effectiveServiceCategory() {
    final tabs = SkDashboardCardCatalog.serviceSubTabs(_gating);
    if (tabs.contains(_serviceCategory)) return _serviceCategory;
    return SkDashboardServicesCategory.all;
  }

  bool get _servicesShowGroupedAll =>
      _tab == _SkDashboardTab.services &&
      _effectiveServiceCategory() == SkDashboardServicesCategory.all;

  bool _showSkDashboardFilters(UserHierarchyService hierarchy) {
    final ss = hierarchy.ssWorkers ?? const [];
    final sv = hierarchy.subVillages ?? const [];
    return ss.isNotEmpty || sv.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final hierarchy = context.watch<UserHierarchyService>();
    final showFilters = _showSkDashboardFilters(hierarchy);
    final serviceSubTabs = SkDashboardCardCatalog.serviceSubTabs(_gating);
    return Column(
      children: [
        _SpiceDashboardTabs(
          selected: _tab,
          onSelected: (t) => setState(() => _tab = t),
        ),
        if (_tab == _SkDashboardTab.services)
          _SpiceServiceSubTabs(
            categories: serviceSubTabs,
            selected: _effectiveServiceCategory(),
            onSelected: (c) => setState(() => _serviceCategory = c),
          ),
        Material(
          color: const Color(0xFFF8F8FD),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _DateChip(
                    label: PerformanceStrings.dashboardFrom,
                    value: df.format(_from),
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateChip(
                    label: PerformanceStrings.dashboardTo,
                    value: df.format(_to),
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showFilters)
          Material(
            color: const Color(0xFFF8F8FD),
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: TextButton.icon(
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: _selectedSsIds.isNotEmpty ||
                        _selectedSubVillageIds.isNotEmpty,
                    smallSize: 8,
                    child: const Icon(Icons.filter_list, size: 20),
                  ),
                  label: Text(PerformanceStrings.dashboardFilterTitle),
                ),
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
              if (_servicesShowGroupedAll) {
                final entries =
                    SkDashboardCardCatalog.allServicesGrouped(c, _gating);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    if (e.isHeader) {
                      return _SpiceServiceGroupHeader(title: e.title);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _SpiceKpiCard(
                        title: e.title,
                        count: e.count ?? 0,
                      ),
                    );
                  },
                );
              }
              final cards = _tab == _SkDashboardTab.demographic
                  ? SkDashboardCardCatalog.demographic(c)
                  : SkDashboardCardCatalog.cardsForServiceCategory(
                      _effectiveServiceCategory(),
                      c,
                      _gating,
                    );
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, i) => _SpiceKpiCard(
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

/// Section title above a programme block on the **All** services view.
class _SpiceServiceGroupHeader extends StatelessWidget {
  const _SpiceServiceGroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5B7F95),
        ),
      ),
    );
  }
}

/// Programme chips under **Services** (All, RMNCH, CD, …).
class _SpiceServiceSubTabs extends StatelessWidget {
  const _SpiceServiceSubTabs({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<SkDashboardServicesCategory> categories;
  final SkDashboardServicesCategory selected;
  final ValueChanged<SkDashboardServicesCategory> onSelected;

  static const _selectedPurple = Color(0xFF6269DB);
  static const _bg = Color(0xFFF8F8FD);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final category in categories) _chip(category)],
        ),
      ),
    );
  }

  Widget _chip(SkDashboardServicesCategory category) {
    final isSelected = category == selected;
    return Material(
      color: isSelected ? _selectedPurple : Colors.white,
      shape: StadiumBorder(
        side: isSelected
            ? BorderSide.none
            : const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: () => onSelected(category),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            SkDashboardCardCatalog.labelFor(category),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Spice `dashboardTabs` — segmented Services | Demographic on lavender canvas.
class _SpiceDashboardTabs extends StatelessWidget {
  const _SpiceDashboardTabs({
    required this.selected,
    required this.onSelected,
  });

  final _SkDashboardTab selected;
  final ValueChanged<_SkDashboardTab> onSelected;

  static const _tabPurple = Color(0xFF6269DB);
  static const _tabBg = Color(0xFFF8F8FD);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _tabBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 15, 10, 0),
        child: Row(
          children: [
            Expanded(
              child: _tabButton(
                label: PerformanceStrings.dashboardServicesTab,
                isSelected: selected == _SkDashboardTab.services,
                onTap: () => onSelected(_SkDashboardTab.services),
                leftRounded: true,
              ),
            ),
            Expanded(
              child: _tabButton(
                label: PerformanceStrings.dashboardDemographicTab,
                isSelected: selected == _SkDashboardTab.demographic,
                onTap: () => onSelected(_SkDashboardTab.demographic),
                rightRounded: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool leftRounded = false,
    bool rightRounded = false,
  }) {
    const radius = Radius.circular(8);
    return Material(
      color: isSelected ? _tabPurple : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: leftRounded ? radius : Radius.zero,
          bottomLeft: leftRounded ? radius : Radius.zero,
          topRight: rightRounded ? radius : Radius.zero,
          bottomRight: rightRounded ? radius : Radius.zero,
        ),
        side: isSelected
            ? BorderSide.none
            : const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.only(
          topLeft: leftRounded ? radius : Radius.zero,
          bottomLeft: leftRounded ? radius : Radius.zero,
          topRight: rightRounded ? radius : Radius.zero,
          bottomRight: rightRounded ? radius : Radius.zero,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
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
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF5B7F95),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textStrong,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today_outlined, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Spice `list_item_user_dashboard` — title left, count on lavender strip right.
class _SpiceKpiCard extends StatelessWidget {
  const _SpiceKpiCard({required this.title, required this.count});

  final String title;
  final int count;

  static const _countBg = Color(0xFFDDDEFF);
  static const _countFg = Color(0xFF2514BE);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 75,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textStrong,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 25,
              child: ColoredBox(
                color: _countBg,
                child: Center(
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _countFg,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
