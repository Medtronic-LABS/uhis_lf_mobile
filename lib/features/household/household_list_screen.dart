import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/widgets/location_filter_sheet.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/mission_dashboard_repository.dart';
import 'household_detail_screen.dart';
import '../../core/widgets/skeleton.dart';

/// View mode for the list screen.
enum HouseholdListMode {
  /// Show households with member counts.
  households,

  /// Show a flat list of all members across households.
  members,
}

/// Filter for members: show all members or only assigned patients.
enum MemberFilter {
  /// Show only patients assigned to the logged-in SK (via patients table).
  myPatients,

  /// Show all members in the village.
  allMembers,
}

class HouseholdListScreen extends StatefulWidget {
  const HouseholdListScreen({
    super.key,
    required this.mode,
    this.initialTier,
  });

  final HouseholdListMode mode;

  /// Optional tier filter pre-selected from dashboard deep-link
  /// (`/patients?tier=overdue`). When non-null, the tier chip row appears
  /// with this tier pre-selected.
  final DashboardTier? initialTier;

  @override
  State<HouseholdListScreen> createState() => _HouseholdListScreenState();
}

class _HouseholdListScreenState extends State<HouseholdListScreen> with SingleTickerProviderStateMixin {
  Future<List<_HouseholdItem>>? _future;
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;
  
  // Filter state for members view — default to allMembers so data is visible
  // before patient-ID cross-reference is verified against the members table.
  MemberFilter _filter = MemberFilter.allMembers;
  Set<String> _myPatientIds = {};


  // 5-tier filter state (null = All)
  DashboardTier? _selectedTier;
  Map<String, DashboardTier>? _patientTiers;

  // Location / SS filter state (null = show all)
  String? _selectedVillageId;
  String? _selectedSubVillageId;
  String? _selectedShebikaId;

  // Inline village chip row (populated from local DB after data loads)
  List<({String id, String name})> _inlineVillages = const [];
  String? _selectedInlineVillageId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedTier = widget.initialTier;
    // Defer loading until after first frame when context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadData();
        _loadPatientTiers();
      }
    });
  }

  /// Load the tiered queue to get patient-tier mapping for filtering.
  Future<void> _loadPatientTiers() async {
    if (!mounted) return;
    try {
      final missionRepo = context.read<MissionDashboardRepository>();
      final queue = await missionRepo.loadQueue();
      if (!mounted) return;
      final tiers = <String, DashboardTier>{};
      for (final item in queue) {
        if (item.patientId != null) {
          tiers[item.patientId!] = item.tier;
        }
      }
      setState(() => _patientTiers = tiers);
    } catch (e) {
      debugPrint('[HouseholdList] Failed to load patient tiers: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadData() {
    final householdDao = context.read<HouseholdDao>();
    final memberDao = context.read<MemberDao>();
    final repo = context.read<DashboardRepository>();

    // Load distinct villages for inline chip row
    memberDao.getDistinctVillages().then((villages) {
      if (mounted && villages.length > 1) {
        setState(() => _inlineVillages = villages);
      }
    });

    setState(() {
      _future = _fetchHouseholds(
        householdDao,
        memberDao,
        repo,
        villageId: _selectedVillageId,
        subVillageId: _selectedSubVillageId,
        shebikaId: _selectedShebikaId,
      ).then((households) async {
        final patientIds = await memberDao.getMyPatientIds();
        if (mounted) {
          _myPatientIds = patientIds;
        }
        return households;
      });
    });
  }

  /// Opens the location/SS filter bottom sheet backed by the API hierarchy.
  Future<void> _openFilterSheet() async {
    final hierarchySvc = context.read<UserHierarchyService>();
    // One prefetch covers villages, subVillages, and ssWorkers — single HTTP call.
    await hierarchySvc.prefetch();
    if (!mounted) return;
    final villages = hierarchySvc.villages ?? const [];
    final allSubVillages = hierarchySvc.subVillages ?? const [];
    final ssWorkers = hierarchySvc.ssWorkers ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LocationFilterSheet(
        villages: villages
            .map((v) => (id: v.id, name: v.name))
            .toList(),
        allSubVillages: allSubVillages,
        ssWorkers: ssWorkers,
        selectedVillageId: _selectedVillageId,
        selectedSubVillageId: _selectedSubVillageId,
        selectedShebikaId: _selectedShebikaId,
        onApply: (v, sv, ss) {
          setState(() {
            _selectedVillageId = v;
            _selectedSubVillageId = sv;
            _selectedShebikaId = ss;
          });
          _loadData();
        },
      ),
    );
  }

  /// Fetches households from LOCAL SQLite first (instant), falls back to API.
  Future<List<_HouseholdItem>> _fetchHouseholds(
    HouseholdDao householdDao,
    MemberDao memberDao,
    DashboardRepository repo, {
    String? villageId,
    String? subVillageId,
    String? shebikaId,
  }) async {
    // Resolve SS → sub-village IDs before the first await so we don't use
    // BuildContext across an async gap.
    List<String>? ssSubVillageIds;
    if (shebikaId != null) {
      final hierarchySvc = context.read<UserHierarchyService>();
      final ssWorkers = hierarchySvc.ssWorkers ?? const [];
      final ss = ssWorkers.where((s) => s.id == shebikaId).firstOrNull;
      if (ss != null && ss.subVillages.isNotEmpty) {
        ssSubVillageIds = ss.subVillages.map((sv) => sv.id).toList();
        // ignore: avoid_print
        print('[HouseholdList] SS $shebikaId → ${ssSubVillageIds.length} sub-villages');
      }
    }

    try {
      // Try local SQLite first (INSTANT - no network latency)
      final localHouseholds = await householdDao.getAll(limit: 1000);
      // ignore: avoid_print
      print('[HouseholdList] Found ${localHouseholds.length} households in local DB');
      if (localHouseholds.isNotEmpty) {
        // ignore: avoid_print
        print('[HouseholdList] Sample household IDs: ${localHouseholds.take(3).map((h) => h.id).toList()}');
      }

      // Get members grouped by household, with optional location/SS filter.
      final membersByHousehold = await memberDao.getAllGroupedByHousehold(
        villageId: villageId,
        subVillageId: subVillageId,
        shasthyaShebikaId: shebikaId,
        subVillageIds: ssSubVillageIds,
      );
      // ignore: avoid_print
      print('[HouseholdList] Got members grouped by ${membersByHousehold.length} households');
      // ignore: avoid_print
      print('[HouseholdList] Member household IDs: ${membersByHousehold.keys.take(3).toList()}');
      
      // For Members view, use members directly grouped by household (bypass household table)
      // This ensures we show all 39 members, not just those linked to old household records
      if (membersByHousehold.isNotEmpty) {
        // ignore: avoid_print
        print('[HouseholdList] Using member-derived households');
        final items = <_HouseholdItem>[];
        for (final entry in membersByHousehold.entries) {
          final hhId = entry.key;
          final members = entry.value;
          if (members.isEmpty) continue;
          // Create household item from member data
          final firstMember = members.first;
          final memberList = members.map(_HouseholdMember.fromEntity).toList();
          
          // Find household head to derive household name
          final head = memberList.firstWhere(
            (m) => m.isHouseholdHead == true,
            orElse: () => memberList.first,
          );
          // Use head's name as household name, or fallback to "Household #ID"
          final householdName = head.name != null 
              ? "${head.name}'s Household"
              : (hhId.isNotEmpty ? 'Household #$hhId' : null);
          
          items.add(_HouseholdItem(
            id: hhId,
            householdNo: hhId,
            name: householdName,
            village: firstMember.villageId,
            memberCount: members.length,
            members: memberList,
          ));
        }
        return items;
      }
      
      // Fallback to household table if no members
      if (localHouseholds.isNotEmpty) {
        final items = localHouseholds.map((hh) {
          return _HouseholdItem.fromEntity(hh, []);
        }).toList();
        return items;
      }
      
      // Fallback to API if local cache is empty
      // ignore: avoid_print
      print('[HouseholdList] Local cache empty, falling back to API');
      final rawList = await repo.getHouseholdsWithMembers();
      return rawList.map((raw) => _HouseholdItem.fromJson(raw)).toList();
    } catch (e, stack) {
      // ignore: avoid_print
      print('[HouseholdList] Exception: $e');
      // ignore: avoid_print
      print('[HouseholdList] Stack: $stack');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        // No back button - this is a root tab in bottom navigation
        automaticallyImplyLeading: false,
        title: const Text('Patients'),
        actions: [
          // Filter icon shows a badge dot when any location filter is active.
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: HouseholdListStrings.filterTitle,
                onPressed: _openFilterSheet,
              ),
              if (_selectedVillageId != null ||
                  _selectedSubVillageId != null ||
                  _selectedShebikaId != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_loadData),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Members', icon: Icon(Icons.people_outline)),
            Tab(text: 'Households', icon: Icon(Icons.home_outlined)),
          ],
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.onSurfaceVariant,
          indicatorColor: scheme.primary,
        ),
      ),
      body: _future == null
          ? const SkeletonHouseholdList()
          : FutureBuilder<List<_HouseholdItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SkeletonHouseholdList();
          }
          if (snapshot.hasError) {
            // ignore: avoid_print
            print('[HouseholdList] Error: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(HouseholdListStrings.loadError),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      '${snapshot.error}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => setState(_loadData),
                    child: const Text(CommonStrings.retry),
                  ),
                ],
              ),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    HouseholdListStrings.noMembers,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          // Use TabBarView to show Members or Households
          return TabBarView(
            controller: _tabController,
            children: [
              Column(children: [
                _buildActiveFilterRow(context, householdCount: items.length),
                Expanded(child: _buildMembersList(context, items)),
              ]),
              Column(children: [
                _buildActiveFilterRow(context, householdCount: items.length),
                Expanded(child: _buildHouseholdsList(context, items)),
              ]),
            ],
          );
        },
      ),
    );
  }

  /// Renders household count + dismissible chips for active location/SS filters.
  /// Hidden when no location filters are active.
  Widget _buildActiveFilterRow(
    BuildContext context, {
    required int householdCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasLocationFilter = _selectedVillageId != null ||
        _selectedSubVillageId != null ||
        _selectedShebikaId != null;
    if (!hasLocationFilter) return const SizedBox.shrink();

    final hierarchy = context.read<UserHierarchyService>();
    final chips = <Widget>[];

    void addChip(String label, VoidCallback onRemove) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          onDeleted: onRemove,
          deleteIconColor: scheme.onSecondaryContainer,
          backgroundColor: scheme.secondaryContainer,
          labelStyle: TextStyle(color: scheme.onSecondaryContainer),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ));
    }

    if (_selectedVillageId != null) {
      final name = hierarchy.villages
              ?.where((v) => v.id == _selectedVillageId)
              .firstOrNull
              ?.name ??
          _selectedVillageId!;
      addChip('${HouseholdListStrings.filterVillage}: $name', () {
        setState(() {
          _selectedVillageId = null;
          _selectedSubVillageId = null;
          _selectedShebikaId = null;
        });
        _loadData();
      });
    }
    if (_selectedSubVillageId != null) {
      final name = hierarchy.subVillages
              ?.where((sv) => sv.id == _selectedSubVillageId)
              .firstOrNull
              ?.name ??
          _selectedSubVillageId!;
      addChip('${HouseholdListStrings.filterSubVillage}: $name', () {
        setState(() {
          _selectedSubVillageId = null;
          _selectedShebikaId = null;
        });
        _loadData();
      });
    }
    if (_selectedShebikaId != null) {
      final name = hierarchy.ssWorkers
              ?.where((ss) => ss.id == _selectedShebikaId)
              .firstOrNull
              ?.name ??
          _selectedShebikaId!;
      addChip('${HouseholdListStrings.filterSS}: $name', () {
        setState(() => _selectedShebikaId = null);
        _loadData();
      });
    }

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            HouseholdListStrings.householdsCount(householdCount),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHouseholdsList(BuildContext context, List<_HouseholdItem> items) {
    final scheme = Theme.of(context).colorScheme;

    // Apply inline village filter to households tab
    final filteredItems = _selectedInlineVillageId != null
        ? items
            .where((h) => h.members.any((m) => m.villageId == _selectedInlineVillageId))
            .toList()
        : items;

    final totalMembers = filteredItems.fold<int>(0, (sum, h) => sum + (h.memberCount ?? 0));

    return Column(
      children: [
        _buildInlineVillageChipRow(scheme),
        Container(
          padding: const EdgeInsets.all(16),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              Expanded(
                child: _SummaryChip(
                  icon: Icons.home_work_outlined,
                  label: HouseholdListStrings.householdsCount(filteredItems.length),
                  color: scheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryChip(
                  icon: Icons.people_alt_outlined,
                  label: HouseholdListStrings.membersCount(totalMembers),
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: filteredItems.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return _HouseholdTile(
                item: item,
                onTap: () => _navigateToDetail(context, item),
              );
            },
          ),
        ),
      ],
    );
  }

  void _navigateToDetail(BuildContext context, _HouseholdItem item) {
    final id = item.id;
    if (id == null || id.isEmpty) {
      debugPrint('[HouseholdList] Skipping nav — household has empty ID');
      return;
    }
    context.push('/patients/household/$id', extra: item.toDetailData());
  }

  void _navigateToMemberDetail(BuildContext context, _MemberInfo member) {
    final id = (member.patientId != null && member.patientId!.isNotEmpty)
        ? member.patientId!
        : member.id;
    // Guard: id must be a non-empty, non-keyword string before navigating.
    if (id == null || id.isEmpty || id == 'household' || id == 'households') {
      debugPrint('[HouseholdList] Skipping nav — member has no usable ID: ${member.name}');
      return;
    }
    context.push(
      '/patient/$id',
      extra: {
        'id': member.id,
        'name': member.name,
        'gender': member.gender,
        'age': member.age,
        'dateOfBirth': member.dateOfBirth,
        'phoneNumber': member.phoneNumber,
        'isPregnant': member.isPregnant,
        'householdId': member.householdId,
        'householdName': member.householdName,
        'patientId': member.patientId,
      },
    );
  }

  Widget _buildMembersList(BuildContext context, List<_HouseholdItem> items) {
    final scheme = Theme.of(context).colorScheme;
    // Flatten all members from all households
    final allMembers = <_MemberInfo>[];
    for (final household in items) {
      for (final member in household.members) {
        allMembers.add(_MemberInfo.fromMember(member, household));
      }
    }

    // Apply village chip filter first so counts reflect the current location context.
    var villageFiltered = _selectedInlineVillageId != null
        ? allMembers.where((m) => m.villageId == _selectedInlineVillageId).toList()
        : allMembers;

    // Apply tier filter.
    if (_selectedTier != null && _patientTiers != null) {
      villageFiltered = villageFiltered.where((m) {
        final tier = _patientTiers![m.id] ?? _patientTiers![m.patientId];
        return tier == _selectedTier;
      }).toList();
    }

    // Counts derived AFTER location/tier filters so chips always match the list.
    final allMembersCount = villageFiltered.length;
    final myPatientsCount = villageFiltered
        .where((m) => _myPatientIds.contains(m.id) || _myPatientIds.contains(m.patientId))
        .length;

    // Apply patient-type filter last.
    final members = _filter == MemberFilter.myPatients
        ? villageFiltered.where((m) => _myPatientIds.contains(m.id) || _myPatientIds.contains(m.patientId)).toList()
        : villageFiltered;

    // Calculate total from noOfPeople if we don't have individual members
    final totalFromCount = items.fold<int>(0, (sum, h) => sum + (h.memberCount ?? 0));

    // If we have no individual members but have a count, show households with counts.
    // Filter toggle is hidden here — it would show (0) for both options and confuse the user.
    if (allMembers.isEmpty && totalFromCount > 0) {
      return Column(
        children: [
          if (widget.initialTier != null || _selectedTier != null)
            _buildTierChipRow(),
          _buildInlineVillageChipRow(scheme),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final item = items[index];
                return _HouseholdWithMemberCountTile(
                  item: item,
                  onTap: () => _navigateToDetail(context, item),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (widget.initialTier != null || _selectedTier != null)
          _buildTierChipRow(),
        _buildInlineVillageChipRow(scheme),
        _buildFilterToggle(scheme, allCount: allMembersCount, myCount: myPatientsCount),
        Expanded(
          child: members.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: scheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        _filter == MemberFilter.myPatients
                            ? HouseholdListStrings.noPatientsAssigned
                            : HouseholdListStrings.noMembers,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: members.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return _MemberTile(
                      member: member,
                      onTap: () => _navigateToMemberDetail(context, member),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Inline village chip row — "WHICH VILLAGE ARE YOU VISITING?"
  /// Mirrors the dashboard pattern. Hidden when ≤1 village in local data.
  Widget _buildInlineVillageChipRow(ColorScheme scheme) {
    if (_inlineVillages.isEmpty) return const SizedBox.shrink();
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            MissionDashboardStrings.whichVillageVisiting,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _InlineVillageChip(
                  label: MissionDashboardStrings.allVillages,
                  isActive: _selectedInlineVillageId == null,
                  navyColor: AppColors.navy,
                  onTap: () => setState(() => _selectedInlineVillageId = null),
                ),
                ..._inlineVillages.map((v) => _InlineVillageChip(
                      label: v.name,
                      isActive: _selectedInlineVillageId == v.id,
                      navyColor: AppColors.navy,
                      onTap: () => setState(() {
                        _selectedInlineVillageId =
                            _selectedInlineVillageId == v.id ? null : v.id;
                      }),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Builds the filter toggle chips (My Patients / All Members).
  /// [allCount] and [myCount] are post-filter counts so the labels always
  /// match the list length the user sees.
  Widget _buildFilterToggle(ColorScheme scheme, {required int allCount, required int myCount}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          _FilterChip(
            label: HouseholdListStrings.myPatientsCount(myCount),
            isSelected: _filter == MemberFilter.myPatients,
            onTap: () => setState(() => _filter = MemberFilter.myPatients),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: HouseholdListStrings.allMembersCount(allCount),
            isSelected: _filter == MemberFilter.allMembers,
            onTap: () => setState(() => _filter = MemberFilter.allMembers),
          ),
        ],
      ),
    );
  }

  /// Builds the 5-tier chip row for filtering by dashboard tier.
  /// Renders when navigating from dashboard with `?tier=...` or when
  /// the user toggles into tier-filter mode.
  Widget _buildTierChipRow() {
    final scheme = Theme.of(context).colorScheme;
    final tiers = [null, ...DashboardTier.values];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tiers.map((tier) {
            final isSelected = _selectedTier == tier;
            final label = tier == null
                ? 'All'
                : MissionDashboardStrings.tierLabel(tier);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _TierFilterChip(
                label: label,
                tier: tier,
                isSelected: isSelected,
                onTap: () => setState(() => _selectedTier = tier),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Chip for tier filtering.
class _TierFilterChip extends StatelessWidget {
  const _TierFilterChip({
    required this.label,
    required this.tier,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final DashboardTier? tier;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final urgency = Theme.of(context).extension<UrgencyTheme>()!;
    final color = _tierColor(tier, urgency, tokens);
    return Semantics(
      label: 'Filter by $label',
      button: true,
      selected: isSelected,
      child: GestureDetector(
        key: const Key('household_tier_filter_tap'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : tokens.textMuted.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? color : tokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Color _tierColor(DashboardTier? t, UrgencyTheme urgency, LeapfrogColors tokens) {
    if (t == null) return tokens.brandNavy;
    switch (t) {
      case DashboardTier.critical:
      case DashboardTier.overdue:
        return urgency.visitNow;
      case DashboardTier.dueToday:
        return urgency.today;
      case DashboardTier.thisWeek:
        return urgency.thisWeek;
      case DashboardTier.upcoming:
        return tokens.textMuted;
    }
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip toggle for filter selection.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      button: true,
      selected: isSelected,
      child: GestureDetector(
        key: const Key('household_programme_filter_tap'),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? scheme.onPrimary : scheme.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _HouseholdTile extends StatelessWidget {
  const _HouseholdTile({required this.item, this.onTap});

  final _HouseholdItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    // Use brand navy for icons - visible in both light and dark modes
    final iconColor = tokens.brandNavy;
    final iconBgColor = tokens.brandNavy.withValues(alpha: 0.1);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: iconBgColor,
        child: Icon(Icons.home_outlined, color: iconColor),
      ),
      title: Text(
        item.name ?? HouseholdListStrings.unnamedHousehold,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      subtitle: Text(
        item.householdNo ?? '',
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 16, color: iconColor),
                const SizedBox(width: 4),
                Text(
                  '${item.memberCount ?? 0}',
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: scheme.outline),
        ],
      ),
    );
  }
}

/// Tile for displaying households with member counts in the "All Members" view
/// when individual member data is not available from the API.
class _HouseholdWithMemberCountTile extends StatelessWidget {
  const _HouseholdWithMemberCountTile({required this.item, this.onTap});

  final _HouseholdItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = item.memberCount ?? 0;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          '$count',
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        item.name ?? HouseholdListStrings.unnamedHousehold,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      subtitle: Text(
        HouseholdListStrings.membersCount(count),
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.outline),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, this.onTap});

  final _MemberInfo member;
  final VoidCallback? onTap;

  IconData _genderIcon() {
    final g = member.gender?.toLowerCase();
    if (g == 'male' || g == 'm') return Icons.male;
    if (g == 'female' || g == 'f') return Icons.female;
    return Icons.person_outline;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    // Build metadata parts: Age · Gender · House #
    final metaParts = <String>[];
    if (member.age != null) {
      metaParts.add('Age ${member.age}');
    }
    if (member.gender != null) {
      metaParts.add(member.gender!);
    }
    if (member.householdNo != null) {
      metaParts.add('House #${member.householdNo}');
    } else if (member.householdName != null) {
      metaParts.add(member.householdName!);
    }
    final metaLine = metaParts.join(' · ');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: member.isPregnant
            ? scheme.tertiaryContainer
            : scheme.primaryContainer,
        child: member.isPregnant
            ? const Text('🤰', style: TextStyle(fontSize: 20))
            : Icon(_genderIcon(), color: scheme.onPrimaryContainer),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              member.name ?? HouseholdListStrings.unnamedMember,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.isPregnant)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Pregnant',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member.relation != null)
            Text(
              member.relation!,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (metaLine.isNotEmpty)
            Text(
              metaLine,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.outline),
      isThreeLine: member.relation != null,
    );
  }
}

class _HouseholdItem {
  _HouseholdItem({
    this.id,
    this.name,
    this.householdNo,
    this.village,
    this.subVillage,
    this.memberCount,
    this.latitude,
    this.longitude,
    this.members = const [],
    this.rawJson,
  });

  final String? id;
  final String? name;
  final String? householdNo;
  final String? village;
  final String? subVillage;
  final int? memberCount;
  final double? latitude;
  final double? longitude;
  final List<_HouseholdMember> members;
  final Map<String, dynamic>? rawJson;

  /// Convert to HouseholdDetailData for the detail screen.
  /// Directly creates HouseholdDetailData with our members (no JSON re-parsing).
  HouseholdDetailData toDetailData() {
    // Convert _HouseholdMember list to HouseholdMemberData list
    final memberDataList = members.map((m) {
      int? age;
      if (m.dateOfBirth != null) {
        try {
          final dob = DateTime.parse(m.dateOfBirth!);
          final now = DateTime.now();
          age = now.year - dob.year;
          if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
            age = age - 1;
          }
        } catch (_) {}
      }
      return HouseholdMemberData(
        id: m.id,
        patientId: m.patientId,
        name: m.name,
        relation: m.relation,
        age: age,
        gender: m.gender,
        phoneNumber: m.phoneNumber,
        dateOfBirth: m.dateOfBirth,
        isHead: m.isHouseholdHead ?? false,
        isPregnant: m.isPregnant ?? false,
        householdId: m.householdId ?? id,
        villageId: m.villageId,
      );
    }).toList();

    return HouseholdDetailData(
      id: id,
      name: name,
      householdNo: householdNo,
      village: village,
      subVillage: subVillage,
      memberCount: memberDataList.isNotEmpty ? memberDataList.length : memberCount,
      latitude: latitude,
      longitude: longitude,
      members: memberDataList,
    );
  }

  static _HouseholdItem fromJson(Map json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? members;
    final members1 = json['noOfPeople'];
    if (members1 is int) {
      members = members1;
    } else if (members1 is num) {
      members = members1.toInt();
    } else if (members1 is String) {
      members = int.tryParse(members1);
    }

    double? lat, lng;
    final latVal = json['latitude'];
    final lngVal = json['longitude'];
    if (latVal is double) { lat = latVal; }
    else if (latVal is num) { lat = latVal.toDouble(); }
    if (lngVal is double) { lng = lngVal; }
    else if (lngVal is num) { lng = lngVal.toDouble(); }

    final memberList = <_HouseholdMember>[];
    if (json['householdMembers'] is List) {
      for (final m in json['householdMembers']) {
        if (m is Map) {
          memberList.add(_HouseholdMember.fromJson(m));
        }
      }
      members ??= memberList.length;
    }

    return _HouseholdItem(
      id: str('id'),
      name: str('name'),
      householdNo: str('householdNo'),
      village: str('village'),
      subVillage: str('subVillage'),
      memberCount: members,
      latitude: lat,
      longitude: lng,
      members: memberList,
      rawJson: json is Map<String, dynamic> ? json : Map<String, dynamic>.from(json),
    );
  }

  /// Creates from local SQLite entities (HouseholdEntity + MemberEntities).
  static _HouseholdItem fromEntity(
    HouseholdEntity hh,
    List<HouseholdMemberEntity> members,
  ) {
    final memberList = members.map(_HouseholdMember.fromEntity).toList();
    return _HouseholdItem(
      id: hh.id,
      name: hh.name,
      householdNo: hh.householdNo,
      village: hh.village,
      subVillage: null,
      memberCount: memberList.isNotEmpty ? memberList.length : hh.memberCount,
      latitude: null,
      longitude: null,
      members: memberList,
      rawJson: {
        'id': hh.id,
        'name': hh.name,
        'householdNo': hh.householdNo,
        'village': hh.village,
        'villageId': hh.villageId,
        'noOfPeople': memberList.isNotEmpty ? memberList.length : hh.memberCount,
      },
    );
  }
}

class _HouseholdMember {
  _HouseholdMember({
    this.id,
    this.patientId,
    this.name,
    this.relation,
    this.gender,
    this.dateOfBirth,
    this.phoneNumber,
    this.isHouseholdHead,
    this.isPregnant,
    this.householdId,
    this.villageId,
  });

  final String? id;
  final String? patientId;
  final String? name;
  final String? relation;
  final String? gender;
  final String? dateOfBirth;
  final String? phoneNumber;
  final bool? isHouseholdHead;
  final bool? isPregnant;
  final String? householdId;
  final String? villageId;

  static _HouseholdMember fromJson(Map json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    // Parse householdHeadRelationship (API field name) or relation
    final relation = str('householdHeadRelationship') ?? str('relation');
    final relationLower = relation?.toLowerCase();
    final isHead = relationLower == 'head' ||
        relationLower == 'self' ||
        relationLower == 'household head' ||
        relationLower == 'householdhead' ||
        json['isHouseholdHead'] == true;

    return _HouseholdMember(
      id: str('id'),
      patientId: str('patientId'),
      name: str('name') ?? str('firstName'),
      relation: relation,
      gender: str('gender'),
      dateOfBirth: str('dateOfBirth'),
      phoneNumber: str('phoneNumber'),
      isHouseholdHead: isHead,
      isPregnant: json['isPregnant'] == true,
      householdId: str('householdId'),
      villageId: str('villageId'),
    );
  }

  /// Creates from local SQLite HouseholdMemberEntity.
  static _HouseholdMember fromEntity(HouseholdMemberEntity e) {
    return _HouseholdMember(
      id: e.id,
      patientId: e.patientId,
      name: e.name,
      relation: e.relation,
      gender: e.gender,
      dateOfBirth: e.dob,
      phoneNumber: e.phone,
      isHouseholdHead: e.isHouseholdHead,
      isPregnant: e.isPregnant,
      householdId: e.householdId,
      villageId: e.villageId,
    );
  }
}

class _MemberInfo {
  _MemberInfo({
    this.id,
    this.patientId,
    this.name,
    this.relation,
    this.gender,
    this.age,
    this.dateOfBirth,
    this.phoneNumber,
    this.isPregnant = false,
    this.householdId,
    this.householdName,
    this.householdNo,
    this.villageId,
  });

  final String? id;
  final String? patientId;
  final String? name;
  final String? relation;
  final String? gender;
  final int? age;
  final String? dateOfBirth;
  final String? phoneNumber;
  final bool isPregnant;
  final String? householdId;
  final String? householdName;
  final String? householdNo;
  final String? villageId;

  /// Calculate age from date of birth if not directly provided.
  static int? _calculateAge(String? dateOfBirth) {
    if (dateOfBirth == null) return null;
    try {
      final dob = DateTime.parse(dateOfBirth);
      final now = DateTime.now();
      var age = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  /// Create from _HouseholdMember and household context.
  factory _MemberInfo.fromMember(_HouseholdMember member, _HouseholdItem household) {
    return _MemberInfo(
      id: member.id,
      patientId: member.patientId,
      name: member.name,
      relation: member.relation,
      gender: member.gender,
      age: _calculateAge(member.dateOfBirth),
      dateOfBirth: member.dateOfBirth,
      phoneNumber: member.phoneNumber,
      isPregnant: member.isPregnant ?? false,
      householdId: member.householdId ?? household.id,
      householdName: household.name,
      householdNo: household.householdNo,
      villageId: member.villageId,
    );
  }
}

class _InlineVillageChip extends StatelessWidget {
  const _InlineVillageChip({
    required this.label,
    required this.isActive,
    required this.navyColor,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final Color navyColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        label: 'Filter by village: $label',
        button: true,
        selected: isActive,
        child: GestureDetector(
          key: ValueKey('household_inline_village_$label'),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? navyColor : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isActive ? navyColor : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AppColors.textStrong,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// _LocationFilterSheet and _FilterDropdown have been extracted to
// lib/core/widgets/location_filter_sheet.dart as LocationFilterSheet
// and LocationFilterDropdown (public, shared with mission_dashboard_screen).
