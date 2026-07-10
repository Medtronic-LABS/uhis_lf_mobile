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
import '../../core/models/mission_queue_item.dart';
import '../../core/widgets/location_filter_sheet.dart';
import '../../core/widgets/mockup_svg_icons.dart';
import '../../core/widgets/patient_filter_panel.dart' show VillageFilterTab;
import '../dashboard/dashboard_repository.dart';
import '../dashboard/mission_dashboard_repository.dart';
import '../visit/widgets/mission_queue_card.dart';
import 'household_detail_screen.dart';

/// The Patients tab — a single household-card list matching the v13 mockup's
/// `#householdsScreen` exactly: no separate flat-member view, no My-Patients/
/// My-Households toggle, no tier/need filters (none of those exist in the
/// mockup). Village filtering, search, and the location/SS filter sheet are
/// kept as real app capability beyond the mockup.
class HouseholdListScreen extends StatefulWidget {
  const HouseholdListScreen({super.key});

  @override
  State<HouseholdListScreen> createState() => _HouseholdListScreenState();
}

class _HouseholdListScreenState extends State<HouseholdListScreen> {
  Future<List<_HouseholdItem>>? _future;
  final ScrollController _scrollController = ScrollController();

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // patientId -> queue item, so a household's flagged member (if any) can be
  // rendered with its real urgency badge/status via MissionQueueCard.
  Map<String, MissionQueueItem> _queueItems = {};

  // Location / SS filter state (null = show all) — kept: real capability
  // beyond the mockup, not part of the structural-parity cut.
  String? _selectedVillageId;
  String? _selectedSubVillageId;
  String? _selectedShebikaId;

  // Inline village-tab row (populated from local DB after data loads).
  List<({String id, String name})> _inlineVillages = const [];
  String? _selectedInlineVillageId;

  // Household IDs whose "other members" panel is expanded.
  final Set<String> _expandedHouseholdIds = {};

  @override
  void initState() {
    super.initState();
    // Defer loading until after first frame when context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadData();
        _loadQueueItems();
      }
    });
  }

  /// Loads the mission queue so a household's flagged member (if any) can
  /// render with its real urgency badge/status.
  Future<void> _loadQueueItems() async {
    if (!mounted) return;
    try {
      final missionRepo = context.read<MissionDashboardRepository>();
      final queue = await missionRepo.loadQueue();
      if (!mounted) return;
      final queueMap = <String, MissionQueueItem>{};
      for (final item in queue) {
        if (item.patientId != null) {
          queueMap[item.patientId!] = item;
        }
      }
      setState(() => _queueItems = queueMap);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadData() {
    final householdDao = context.read<HouseholdDao>();
    final memberDao = context.read<MemberDao>();
    final repo = context.read<DashboardRepository>();

    // Load distinct villages for the village-tab row.
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
      );
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
        villages: villages.map((v) => (id: v.id, name: v.name)).toList(),
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
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FutureBuilder<List<_HouseholdItem>>(
              future: _future,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <_HouseholdItem>[];
                final filtered = _filterByVillage(items);
                final totalMembers =
                    filtered.fold<int>(0, (sum, h) => sum + (h.memberCount ?? 0));
                return _buildHeader(context, filtered.length, totalMembers);
              },
            ),
            _buildVillageTabRow(),
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
                        return _buildHouseholdsList(context, items);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Households matching the selected village tab (search is applied
  /// per-item in [_buildHouseholdsList] since it also needs the member list).
  List<_HouseholdItem> _filterByVillage(List<_HouseholdItem> items) {
    if (_selectedInlineVillageId == null) return items;
    return items
        .where((h) => h.members.any((m) => m.villageId == _selectedInlineVillageId))
        .toList();
  }

  /// Navy header: 🏠-prefixed title, combined live "N households · M
  /// patients" count, and the search bar — matching the v13 mockup's
  /// `#householdsScreen` header exactly (background, padding, type).
  Widget _buildHeader(BuildContext context, int householdCount, int patientCount) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      HouseholdListStrings.headerTitle,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      HouseholdListStrings.headerSummary(householdCount, patientCount),
                      style: TextStyle(
                        fontFamily: 'NunitoSans',
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // Filter/refresh affordances aren't in the mockup for this
              // screen (its only header controls are back + search) — the
              // location/SS filter sheet is real, kept capability, so it
              // needs an entry point; styled like the mockup's own header
              // icon-button treatment (28×28, white 15%-alpha circle) for
              // visual consistency rather than inventing a new style.
              _HeaderIconButton(
                icon: Icons.filter_list,
                tooltip: HouseholdListStrings.filterTitle,
                onTap: _openFilterSheet,
                showDot: _selectedVillageId != null ||
                    _selectedSubVillageId != null ||
                    _selectedShebikaId != null,
              ),
              const SizedBox(width: 8),
              _HeaderIconButton(
                icon: Icons.refresh,
                tooltip: HouseholdListStrings.refreshTooltip,
                onTap: () => setState(_loadData),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                MockupIcons.search(),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    style: const TextStyle(fontFamily: 'NunitoSans', fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: HouseholdListStrings.searchHint,
                      hintStyle: TextStyle(
                        fontFamily: 'NunitoSans',
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(Icons.clear, size: 18, color: Color(0xFF9CA3AF)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Village-tab row — matches the mockup's `.village-tab` row exactly
  /// (already-correct `VillageFilterTab` widget, no need-filter bubbles).
  Widget _buildVillageTabRow() {
    if (_inlineVillages.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            VillageFilterTab(
              label: MissionDashboardStrings.allVillages,
              isActive: _selectedInlineVillageId == null,
              onTap: () => setState(() => _selectedInlineVillageId = null),
            ),
            for (final v in _inlineVillages)
              VillageFilterTab(
                label: v.name,
                isActive: _selectedInlineVillageId == v.id,
                onTap: () => setState(() => _selectedInlineVillageId = v.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseholdsList(BuildContext context, List<_HouseholdItem> items) {
    final villageFiltered = _filterByVillage(items);
    final filteredItems = _searchQuery.isEmpty
        ? villageFiltered
        : villageFiltered.where((h) => _matchesSearch(h, _searchQuery)).toList();

    if (filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              HouseholdListStrings.noMembers,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: filteredItems.length,
      separatorBuilder: (context, idx) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        final primary = _primaryMember(item);
        final others = item.members.where((m) => m != primary).toList();
        final id = item.id ?? '';
        return _HouseholdCard(
          item: item,
          villageDisplayName: _villageDisplayName(item.village),
          primaryMemberRow: _buildMemberRow(context, _MemberInfo.fromMember(primary, item)),
          otherMembers: others,
          isExpanded: _expandedHouseholdIds.contains(id),
          onToggleExpanded: id.isEmpty
              ? null
              : () => setState(() {
                    if (!_expandedHouseholdIds.remove(id)) {
                      _expandedHouseholdIds.add(id);
                    }
                  }),
          onMemberTap: (other) =>
              _navigateToMemberDetail(context, _MemberInfo.fromMember(other, item)),
          onTap: () => _navigateToDetail(context, item),
        );
      },
    );
  }

  /// Matches the mockup's search predicate: name, house/household number,
  /// or village name.
  bool _matchesSearch(_HouseholdItem h, String query) {
    final villageName = _villageDisplayName(h.village) ?? '';
    final haystack = [
      h.name ?? '',
      h.householdNo ?? '',
      villageName,
      ...h.members.map((m) => m.name ?? ''),
    ].join(' ').toLowerCase();
    return haystack.contains(query);
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

  /// Shared member-row widget: a `MissionQueueCard` (embedded/flush, no own
  /// card chrome) when the member has an active mission-queue entry, else a
  /// plain `_PatientCard`.
  Widget _buildMemberRow(BuildContext context, _MemberInfo member) {
    final pid = member.patientId ?? member.id;
    final queueItem = pid != null ? _queueItems[pid] : null;
    if (queueItem != null) {
      return MissionQueueCard(
        item: queueItem,
        compact: true,
        embedded: true,
        onTap: () {
          final navId = queueItem.patientId;
          if (navId != null && navId.isNotEmpty && navId != 'household' && navId != 'households') {
            context.go('/patients/$navId', extra: {'name': queueItem.patientName});
          }
        },
      );
    }
    return _PatientCard(
      member: member,
      onTap: () => _navigateToMemberDetail(context, member),
    );
  }

  /// Resolves a household's stored village value (which may be a raw village
  /// id from the members-grouping path, or already a name from the entity/
  /// JSON fallback paths) to a display name via the same village list the
  /// filter tabs use. Falls back to the stored value when no match is found.
  String? _villageDisplayName(String? villageIdOrName) {
    if (villageIdOrName == null || villageIdOrName.isEmpty) return null;
    for (final v in _inlineVillages) {
      if (v.id == villageIdOrName) return v.name;
    }
    return villageIdOrName;
  }

  /// Picks the one member to surface inline on a household card: the member
  /// with an active mission-queue entry (if any), else the household head,
  /// else the first member — mirrors the v13 mockup's single "flagged
  /// member" per household card.
  _HouseholdMember _primaryMember(_HouseholdItem item) {
    for (final m in item.members) {
      final pid = m.patientId ?? m.id;
      if (pid != null && _queueItems.containsKey(pid)) return m;
    }
    return item.members.firstWhere(
      (m) => m.isHouseholdHead == true,
      orElse: () => item.members.first,
    );
  }
}

/// Small circular icon button on the navy header — same treatment as the
/// mockup's own header back-button (28×28, white 15%-alpha circle) so the
/// app-only filter/refresh affordances read as part of the same header
/// family rather than a bolted-on Material default.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: Colors.white),
            ),
            if (showDot)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.pinkWorklist,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Initials for an avatar (e.g. "Rafiqul Islam" -> "RI"). Shared by
/// [_OtherMemberRow] (and, until it was needed, [_PatientCard]).
String _memberInitials(String? name) {
  if (name == null || name.isEmpty) return '';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

/// Card for a household — used in the Households tab.
///
/// Self-sufficient, matching the v13 mockup exactly: the household header
/// (🏠 emoji, head name, house+village, member-count pill), the one flagged/
/// actionable member inline ([primaryMemberRow]), and — if there are more
/// members — an expandable "+N other household members" panel. No extra
/// navigation is needed to see who's in the household.
class _HouseholdCard extends StatelessWidget {
  const _HouseholdCard({
    required this.item,
    required this.villageDisplayName,
    required this.primaryMemberRow,
    required this.otherMembers,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onMemberTap,
    this.onTap,
  });

  final _HouseholdItem item;
  final String? villageDisplayName;
  final Widget primaryMemberRow;
  final List<_HouseholdMember> otherMembers;
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;
  final void Function(_HouseholdMember other) onMemberTap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = item.memberCount ?? 0;
    // Bare head name (mockup shows just the name, e.g. "Nasrin Begum") — the
    // "'s Household" suffix on `item.name` is this screen's own construction
    // for when no bare head name is available.
    final headName = item.members.isNotEmpty
        ? (item.members.firstWhere((m) => m.isHouseholdHead == true, orElse: () => item.members.first).name)
        : null;
    final title = headName ??
        item.name ??
        (item.householdNo != null ? 'Household #${item.householdNo}' : HouseholdListStrings.unnamedHousehold);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.householdCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                color: AppColors.cardSurfaceMuted,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Text('🏠', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: AppColors.navy,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (villageDisplayName != null && villageDisplayName!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              villageDisplayName!,
                              style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.aiSurfaceStart,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        HouseholdListStrings.membersCount(count),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.aiPurpleDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: primaryMemberRow,
          ),
          if (otherMembers.isNotEmpty) ...[
            InkWell(
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      HouseholdListStrings.otherMembersToggle(otherMembers.length),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.aiPurple,
                      ),
                    ),
                    const SizedBox(width: 5),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: MockupIcons.chevronDown(),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 1, color: AppColors.progressTrack),
                    for (final other in otherMembers)
                      _OtherMemberRow(member: other, onTap: () => onMemberTap(other)),
                  ],
                ),
              ),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeOut,
            ),
          ],
        ],
      ),
    );
  }
}

/// One row in a household card's expanded "other members" panel — initials
/// avatar, name, relation + age/gender, and an "Enrolled" tag, matching the
/// v13 mockup's `otherMembers` treatment. The mockup's static prototype has
/// no tap action here; this app has a real Patient Details page, so tapping
/// opens it — real capability shouldn't regress just because the mockup
/// couldn't demonstrate it.
class _OtherMemberRow extends StatelessWidget {
  const _OtherMemberRow({required this.member, required this.onTap});

  final _HouseholdMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ageGender = [
      if (member.dateOfBirth != null) '${_ageFromDob(member.dateOfBirth)}',
      if (member.gender != null) member.gender,
    ].whereType<String>().join('/');
    final subtitle = [
      if (member.relation != null && member.relation!.isNotEmpty) member.relation,
      if (ageGender.isNotEmpty) ageGender,
    ].whereType<String>().join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: AppColors.progressTrack, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                _memberInitials(member.name),
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name ?? HouseholdListStrings.unnamedMember,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.catHomeSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                HouseholdListStrings.enrolledTag,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.statusSuccessAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int? _ageFromDob(String? dob) {
    if (dob == null) return null;
    try {
      final d = DateTime.parse(dob);
      final now = DateTime.now();
      var age = now.year - d.year;
      if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
      return age;
    } catch (_) {
      return null;
    }
  }
}

/// Flush member row for a primary member with no mission-queue entry —
/// matches the v13 mockup's member-row shape exactly (name+age/gender+badge,
/// address line, phone line — no avatar, no card chrome of its own, since
/// it's always embedded inside a [_HouseholdCard]). Reuses the same
/// `AppTextStyles.worklist*` tokens `MissionQueueCard` uses so the two
/// widgets never visually drift from each other.
class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.member, this.onTap});

  final _MemberInfo member;
  final VoidCallback? onTap;

  /// Mirrors `MissionReasonBadge._badgeColors` (mission_queue_card.dart) so
  /// the fallback badge for a non-queue member matches the real queue-driven
  /// badge's palette. Duplicated here (not shared) because that method is
  /// private to a `MissionQueueItem`-shaped widget; unify if this recurs.
  static (String label, Color bg, Color fg) _badgeFor(Set<Programme> programmes) {
    if (programmes.contains(Programme.anc) || programmes.contains(Programme.pnc)) {
      return (MissionDashboardStrings.enrolled, const Color(0xFFFDF2F8), const Color(0xFF9D174D));
    }
    if (programmes.contains(Programme.imci) ||
        programmes.contains(Programme.epi) ||
        programmes.contains(Programme.ncd)) {
      final label = programmes.contains(Programme.ncd)
          ? MissionDashboardStrings.ncdCheckup
          : MissionDashboardStrings.childImmunisation;
      return (label, const Color(0xFFFFFBEB), const Color(0xFF92400E));
    }
    if (programmes.contains(Programme.tb)) {
      return (MissionDashboardStrings.tbCheck, const Color(0xFFF0FDF4), const Color(0xFF065F46));
    }
    return (MissionDashboardStrings.newVisit, AppColors.aiSurfaceStart, AppColors.navy);
  }

  @override
  Widget build(BuildContext context) {
    final (badgeLabel, badgeBg, badgeFg) = _badgeFor(member.programmes);

    final address = [
      member.householdNo != null ? 'House #${member.householdNo}' : null,
      member.householdName,
    ].whereType<String>().join(', ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 3,
                    children: [
                      Text(
                        member.name ?? HouseholdListStrings.unnamedMember,
                        style: AppTextStyles.worklistPatientName,
                      ),
                      if (member.age != null || member.gender != null)
                        Text(
                          [
                            if (member.age != null) '${member.age}',
                            if (member.gender != null) member.gender!.substring(0, 1).toUpperCase(),
                          ].join('/'),
                          style: AppTextStyles.worklistPatientMeta,
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(5)),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(fontFamily: 'NunitoSans', fontSize: 10, fontWeight: FontWeight.w700, color: badgeFg),
                        ),
                      ),
                    ],
                  ),
                  if (address.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.worklistAddress.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  if (member.phoneNumber != null && member.phoneNumber!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        member.phoneNumber!,
                        style: AppTextStyles.worklistPhone.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
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
