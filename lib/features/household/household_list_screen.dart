import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/models/programme.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/widgets/location_filter_sheet.dart';
import '../../core/widgets/patient_filter_panel.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/mission_dashboard_repository.dart';
import '../visit/widgets/mission_queue_card.dart';
import 'household_detail_screen.dart';

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

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Filter state for members view — default to allMembers so data is visible
  // before patient-ID cross-reference is verified against the members table.
  MemberFilter _filter = MemberFilter.allMembers;
  Set<String> _myPatientIds = {};

  // 5-tier filter state (null = All)
  DashboardTier? _selectedTier;
  Map<String, DashboardTier>? _patientTiers;
  Map<String, MissionQueueItem> _queueItems = {};

  // Location / SS filter state (null = show all)
  String? _selectedVillageId;
  String? _selectedSubVillageId;
  String? _selectedShebikaId;

  // Inline village chip row (populated from local DB after data loads)
  List<({String id, String name})> _inlineVillages = const [];
  String? _selectedInlineVillageId;

  // Need / programme filter state (derived from queue items)
  Set<NeedFilter> _selectedNeeds = const {};
  Set<NeedFilter> _availableNeeds = const {};

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
      final queueMap = <String, MissionQueueItem>{};
      for (final item in queue) {
        if (item.patientId != null) {
          tiers[item.patientId!] = item.tier;
          queueMap[item.patientId!] = item;
        }
      }
      final availableNeeds = computeAvailableNeeds(queue);
      setState(() {
        _patientTiers = tiers;
        _queueItems = queueMap;
        _availableNeeds = availableNeeds;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
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
      }
    }

    try {
      final localHouseholds = await householdDao.getAll(limit: 1000);

      // Get members grouped by household, with optional location/SS filter.
      final membersByHousehold = await memberDao.getAllGroupedByHousehold(
        villageId: villageId,
        subVillageId: subVillageId,
        shasthyaShebikaId: shebikaId,
        subVillageIds: ssSubVillageIds,
      );

      // Use members directly grouped by household (bypass household table)
      // to ensure all members are shown even when household records are stale.
      if (membersByHousehold.isNotEmpty) {
        // Batch-load programmes for all members in one SQL round-trip.
        final allEntities = membersByHousehold.values.expand((e) => e).toList();
        final allPatientIds = allEntities
            .map((e) => e.patientId)
            .whereType<String>()
            .toSet()
            .toList();
        final programmesDao = PatientProgrammesDao(context.read<AppDatabase>());
        final programmesByPatient =
            await programmesDao.programmesForMany(allPatientIds);

        final items = <_HouseholdItem>[];
        for (final entry in membersByHousehold.entries) {
          final hhId = entry.key;
          final members = entry.value;
          if (members.isEmpty) continue;
          // Create household item from member data
          final firstMember = members.first;
          final memberList = members.map((e) {
            final progs = e.patientId != null
                ? (programmesByPatient[e.patientId!] ?? const <Programme>{})
                : const <Programme>{};
            return _HouseholdMember.fromEntity(e, programmes: progs);
          }).toList();
          
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
      final rawList = await repo.getHouseholdsWithMembers();
      return rawList.map((raw) => _HouseholdItem.fromJson(raw)).toList();
    } catch (_) {
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      ),
      body: Column(
        children: [
          // Compact pill tab strip — always visible.
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) => _buildCompactTabStrip(context),
          ),
          // Shared search bar — always visible.
          _buildSearchBar(),
          // Shared village + need filter panel — visible when data present.
          _buildPatientFilterPanel(),
          // Content area.
          Expanded(
            child: _future == null
                ? const SizedBox.shrink()
                : FutureBuilder<List<_HouseholdItem>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
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
                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildMembersList(context, items),
                          _buildHouseholdsList(context, items),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTabStrip(BuildContext context) {
    final selectedIdx = _tabController.index;
    return Container(
      color: AppColors.cardSurface,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: _TabPill(
              label: 'My Patients',
              icon: Icons.people_outline,
              isSelected: selectedIdx == 0,
              onTap: () => _tabController.animateTo(0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TabPill(
              label: 'My Households',
              icon: Icons.home_outlined,
              isSelected: selectedIdx == 1,
              onTap: () => _tabController.animateTo(1),
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: filteredItems.length,
            separatorBuilder: (context, idx) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return _HouseholdCard(
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
    // Push directly to /patients/:id — the /patient/:id redirect drops extra.
    context.push(
      '/patients/$id',
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

  bool _needMatchesMember(_MemberInfo m) {
    if (_selectedNeeds.isEmpty) return true;
    final pid = m.patientId ?? m.id;
    if (pid == null) return false;
    final qItem = _queueItems[pid];
    if (qItem == null) return false;
    return _selectedNeeds.any((need) => need.matches(qItem));
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

    // Apply need filter (matches queue items; members without queue items shown when no filter active).
    if (_selectedNeeds.isNotEmpty) {
      villageFiltered = villageFiltered.where(_needMatchesMember).toList();
    }

    // Counts derived AFTER location/tier/need filters so chips always match the list.
    final allMembersCount = villageFiltered.length;
    final myPatientsCount = villageFiltered
        .where((m) => _myPatientIds.contains(m.id) || _myPatientIds.contains(m.patientId))
        .length;

    // Apply patient-type filter.
    var members = _filter == MemberFilter.myPatients
        ? villageFiltered.where((m) => _myPatientIds.contains(m.id) || _myPatientIds.contains(m.patientId)).toList()
        : villageFiltered;

    // Apply search filter last.
    if (_searchQuery.isNotEmpty) {
      members = members.where((m) {
        final name = (m.name ?? '').toLowerCase();
        final hno = (m.householdNo ?? '').toLowerCase();
        return name.contains(_searchQuery) || hno.contains(_searchQuery);
      }).toList();
    }

    // Village-wise sort: group members by village name so the SK visits
    // one locality before moving to the next.
    members.sort((a, b) {
      final va = _inlineVillages
          .where((v) => v.id == a.villageId)
          .map((v) => v.name)
          .firstOrNull ?? (a.villageId ?? '');
      final vb = _inlineVillages
          .where((v) => v.id == b.villageId)
          .map((v) => v.name)
          .firstOrNull ?? (b.villageId ?? '');
      final cmp = va.compareTo(vb);
      if (cmp != 0) return cmp;
      return (a.name ?? '').compareTo(b.name ?? '');
    });

    // Calculate total from noOfPeople if we don't have individual members
    final totalFromCount = items.fold<int>(0, (sum, h) => sum + (h.memberCount ?? 0));

    // If we have no individual members but have a count, show households with counts.
    if (allMembers.isEmpty && totalFromCount > 0) {
      return Column(
        children: [
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (context, idx) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = items[index];
                return _HouseholdCard(
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
        if (_selectedTier != null) _buildTierChipRow(),
        _buildFilterToggle(scheme, allCount: allMembersCount, myCount: myPatientsCount),
        if (members.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Showing ${members.length} patient${members.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        Expanded(
          child: members.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: scheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No results for "$_searchQuery"'
                            : _filter == MemberFilter.myPatients
                                ? HouseholdListStrings.noPatientsAssigned
                                : HouseholdListStrings.noMembers,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: members.length,
                  separatorBuilder: (context, idx) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final pid = member.patientId ?? member.id;
                    final queueItem = pid != null ? _queueItems[pid] : null;
                    if (queueItem != null) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: MissionQueueCard(
                          item: queueItem,
                          compact: true,
                          onTap: () {
                            final navId = queueItem.patientId;
                            if (navId != null && navId.isNotEmpty &&
                                navId != 'household' && navId != 'households') {
                              context.go('/patients/$navId',
                                  extra: {'name': queueItem.patientName});
                            }
                          },
                        ),
                      );
                    }
                    return _PatientCard(
                      member: member,
                      onTap: () => _navigateToMemberDetail(context, member),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search by name or house number...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
      ),
    );
  }

  /// Dashboard-style filter panel: village tabs + need category bubbles.
  Widget _buildPatientFilterPanel() {
    if (_inlineVillages.isEmpty && _availableNeeds.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: PatientFilterPanel(
        villages: _inlineVillages
            .map((v) => (value: v.id, label: v.name))
            .toList(),
        selectedVillageValue: _selectedInlineVillageId,
        onVillageSelected: (id) =>
            setState(() => _selectedInlineVillageId = id),
        availableNeeds: _availableNeeds,
        selectedNeeds: _selectedNeeds,
        onNeedToggled: (need) {
          setState(() {
            final updated = Set<NeedFilter>.from(_selectedNeeds);
            if (updated.contains(need)) {
              updated.remove(need);
            } else {
              updated.add(need);
            }
            _selectedNeeds = updated;
          });
        },
        onClearNeeds: () => setState(() => _selectedNeeds = const {}),
      ),
    );
  }

  /// Builds the filter toggle chips (My Patients / All Members).
  /// [allCount] and [myCount] are post-filter counts so the labels always
  /// match the list length the user sees.
  Widget _buildFilterToggle(ColorScheme scheme, {required int allCount, required int myCount}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: _SegmentButton(
                label: HouseholdListStrings.myPatientsCount(myCount),
                isSelected: _filter == MemberFilter.myPatients,
                onTap: () => setState(() => _filter = MemberFilter.myPatients),
              ),
            ),
            Expanded(
              child: _SegmentButton(
                label: HouseholdListStrings.allMembersCount(allCount),
                isSelected: _filter == MemberFilter.allMembers,
                onTap: () => setState(() => _filter = MemberFilter.allMembers),
              ),
            ),
          ],
        ),
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
    final color = _tierColor(tier, tokens);
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
              color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? color : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Color _tierColor(DashboardTier? t, LeapfrogColors tokens) {
    if (t == null) return tokens.brandNavy;
    switch (t) {
      case DashboardTier.critical:
      case DashboardTier.dueToday:
        return const Color(0xFF16A34A); // green — Now / Today
      case DashboardTier.overdue:
        return const Color(0xFFDC2626); // red — Overdue
      case DashboardTier.thisWeek:
        return const Color(0xFFB45309); // amber — This week
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

/// Segmented toggle button — used in the My Patients / All Members toggle.
class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
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
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: double.infinity,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Card for a household — used in the Households tab.
class _HouseholdCard extends StatelessWidget {
  const _HouseholdCard({required this.item, this.onTap});

  final _HouseholdItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final navy = tokens.brandNavy;
    final navyLight = navy.withValues(alpha: 0.10);
    final count = item.memberCount ?? 0;
    final title = item.name ??
        (item.householdNo != null ? 'Household #${item.householdNo}' : HouseholdListStrings.unnamedHousehold);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: AppShadows.card,
            color: Colors.white,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: navyLight, shape: BoxShape.circle),
                child: Icon(Icons.home_outlined, color: navy, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.village != null && item.village!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.village!,
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: navyLight, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline, size: 14, color: navy),
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: navy),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: AppColors.border, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card for a patient member — used in the Members tab for non-queue patients.
class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.member, this.onTap});

  final _MemberInfo member;
  final VoidCallback? onTap;

  static String _initials(String? name) {
    if (name == null || name.isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final navy = tokens.brandNavy;
    final isPregnant = member.isPregnant;

    final avatarBg = isPregnant ? AppColors.tagTealSurface : navy.withValues(alpha: 0.10);
    final avatarFg = isPregnant ? AppColors.tagTealText : navy;

    final initials = _initials(member.name);

    final metaParts = <String>[];
    if (member.age != null) metaParts.add('Age ${member.age}');
    if (member.gender != null) metaParts.add(member.gender!);
    if (member.householdNo != null) {
      metaParts.add('House #${member.householdNo}');
    } else if (member.householdName != null) {
      metaParts.add(member.householdName!);
    }
    if (member.householdMemberCount != null && member.householdMemberCount! > 1) {
      metaParts.add('${member.householdMemberCount} members');
    }
    final metaLine = metaParts.join(' · ');

    final showRelation = member.relation != null &&
        member.relation!.toLowerCase() != 'head' &&
        member.relation!.toLowerCase() != 'self';

    // Accent: ANC/PNC=crimson, else=teal (matches MissionQueueCard._programmeColor)
    final accentColor = isPregnant
        ? const Color(0xFF9D174D)
        : const Color(0xFF0F766E);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.15),
                offset: const Offset(-4, 0),
                blurRadius: 10,
              ),
              ...AppShadows.card,
            ],
            border: Border(
              left: BorderSide(color: accentColor, width: 4),
            ),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: avatarBg, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: initials.isNotEmpty
                    ? Text(
                        initials,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: avatarFg),
                      )
                    : Icon(Icons.person_outline, color: avatarFg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name ?? HouseholdListStrings.unnamedMember,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (member.programmes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: member.programmes
                            .where((p) => p != Programme.unknown)
                            .map((p) => _ProgrammeTag(programme: p))
                            .toList(),
                      ),
                    ],
                    if (metaLine.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        metaLine,
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (showRelation) ...[
                      const SizedBox(height: 2),
                      Text(
                        member.relation!,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: AppColors.border, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgrammeTag extends StatelessWidget {
  const _ProgrammeTag({required this.programme});

  final Programme programme;

  static (Color surface, Color text, IconData icon, String label) _style(Programme p) {
    switch (p) {
      case Programme.anc:
        return (AppColors.ancSurface, AppColors.ancText, Icons.pregnant_woman_rounded, 'ANC');
      case Programme.pnc:
        return (AppColors.pncSurface, AppColors.pncText, Icons.child_friendly_rounded, 'PNC');
      case Programme.ncd:
        return (AppColors.ncdSurface, AppColors.ncdText, Icons.monitor_heart_outlined, 'NCD');
      case Programme.imci:
        return (AppColors.imciSurface, AppColors.imciText, Icons.child_care_rounded, 'Child');
      case Programme.tb:
        return (AppColors.tbSurface, AppColors.tbText, Icons.sick_outlined, 'TB');
      case Programme.epi:
        return (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), Icons.vaccines_rounded, 'EPI');
      case Programme.nutrition:
        return (const Color(0xFFF0FDF4), const Color(0xFF15803D), Icons.restaurant_rounded, 'Nutrition');
      case Programme.familyPlanning:
        return (const Color(0xFFFFF7ED), const Color(0xFF92400E), Icons.family_restroom_rounded, 'FP');
      case Programme.cataract:
        return (const Color(0xFFF5F3FF), const Color(0xFF5B21B6), Icons.visibility_outlined, 'Cataract');
      case Programme.eyeCare:
        return (const Color(0xFFF5F3FF), const Color(0xFF5B21B6), Icons.remove_red_eye_outlined, 'Eye Care');
      default:
        return (AppColors.canvas, AppColors.textMuted, Icons.local_hospital_rounded, p.wireTag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (surface, text, icon, label) = _style(programme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: text),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: text),
          ),
        ],
      ),
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
    this.programmes = const {},
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
  final Set<Programme> programmes;

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
  static _HouseholdMember fromEntity(HouseholdMemberEntity e,
      {Set<Programme> programmes = const {}}) {
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
      programmes: programmes,
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
    this.householdMemberCount,
    this.programmes = const {},
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
  final int? householdMemberCount;
  final Set<Programme> programmes;

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
      householdMemberCount: household.memberCount,
      programmes: member.programmes,
    );
  }
}


// _LocationFilterSheet and _FilterDropdown have been extracted to
// lib/core/widgets/location_filter_sheet.dart as LocationFilterSheet
// and LocationFilterDropdown (public, shared with mission_dashboard_screen).

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.textOnNavy : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.textOnNavy : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
