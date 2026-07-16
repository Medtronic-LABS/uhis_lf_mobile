import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/mission/programme_reason.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/programme.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/sync/offline_sync_service.dart';
import '../../core/widgets/header_icon_button.dart';
import '../../core/widgets/mockup_svg_icons.dart';
import '../../core/widgets/patient_filter_panel.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/mission_dashboard_repository.dart';
import '../search/member_search_repository.dart';
import '../visit/widgets/mission_queue_card.dart';
import 'household_detail_screen.dart';

/// The Patients tab — a single household-card list matching the v13
/// mockup's `#householdsScreen` exactly (navy header, village tabs, search,
/// one unified list — no Households/Members tab split), alongside the
/// location/SS filter sheet (which stays removed; not in the mockup and not
/// reintroduced here).
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

  // Member search results — replaces household-card filtering when query >= 2 chars.
  List<MemberHit> _memberSearchHits = const [];
  bool _memberSearchBusy = false;
  Timer? _memberSearchDebounce;

  // patientId -> queue item, so a household's flagged member (if any) can be
  // rendered with its real urgency badge/status via MissionQueueCard.
  Map<String, MissionQueueItem> _queueItems = {};

  // Inline village-tab row (populated from local DB after data loads).
  List<({String id, String name})> _inlineVillages = const [];
  String? _selectedInlineVillageId;

  // Household IDs whose "other members" panel is expanded.
  final Set<String> _expandedHouseholdIds = {};

  bool _refreshing = false;

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
      // Upcoming-tier members (due >7 days out, or no due date) get no
      // status badge — they still appear in the roster via the plain
      // PatientBadgeRow fallback below, just untagged.
      final queueMap = <String, MissionQueueItem>{};
      for (final item in queue) {
        if (item.patientId != null && item.tier != DashboardTier.upcoming) {
          queueMap[item.patientId!] = item;
        }
      }
      setState(() => _queueItems = queueMap);
    } catch (_) {}
  }

  @override
  void dispose() {
    _memberSearchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _runMemberSearch(String q) {
    _memberSearchDebounce?.cancel();
    if (q.length < 2) {
      setState(() {
        _memberSearchHits = const [];
        _memberSearchBusy = false;
      });
      debugPrint('[HouseholdList] search cleared');
      return;
    }
    setState(() => _memberSearchBusy = true);
    _memberSearchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      try {
        final repo = context.read<MemberSearchRepository>();
        final result = await repo.search(query: q);
        debugPrint('[HouseholdList] member search "$q" → ${result.matches.length} hits');
        if (!mounted) return;
        setState(() {
          _memberSearchHits = result.matches;
          _memberSearchBusy = false;
        });
      } catch (e) {
        debugPrint('[HouseholdList] member search error: $e');
        if (mounted) setState(() => _memberSearchBusy = false);
      }
    });
  }

  void _loadData() {
    final householdDao = context.read<HouseholdDao>();
    final memberDao = context.read<MemberDao>();
    final repo = context.read<DashboardRepository>();

    // Load distinct sub-villages for the village-tab row — matches the Home
    // dashboard's own village-chip granularity (the worklist's
    // Patient.villageName/villageId are actually sub-village data under a
    // misleading name, so "village" means sub-village on both screens now,
    // by product decision). Shown whenever there's at least one — the
    // mockup's row always shows "All villages" plus whatever exists, even
    // just one.
    memberDao.getDistinctSubVillages().then((villages) {
      if (mounted && villages.isNotEmpty) {
        setState(() => _inlineVillages = villages);
      }
    });

    setState(() {
      _future = _fetchHouseholds(householdDao, memberDao, repo);
    });
  }

  Future<void> _refreshFromServer() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final syncSvc = context.read<OfflineSyncService>();
      final report = await syncSvc.warmSync();
      if (!mounted) return;
      final msg = report.errors.isNotEmpty
          ? HouseholdListStrings.refreshFailed(report.errors.first)
          : HouseholdListStrings.refreshSummary(
              report.patients, report.assessments, report.followUps);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
      _loadData();
      _loadQueueItems();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Fetches households from LOCAL SQLite first (instant), falls back to API.
  Future<List<_HouseholdItem>> _fetchHouseholds(
    HouseholdDao householdDao,
    MemberDao memberDao,
    DashboardRepository repo,
  ) async {
    try {
      final localHouseholds = await householdDao.getAll(limit: 1000);

      // Get members grouped by household — search + village tabs are the
      // only filtering on this screen (the location/sub-village/SS-worker
      // sheet was removed; it's not in the mockup).
      final membersByHousehold = await memberDao.getAllGroupedByHousehold();

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
        final appDb = context.read<AppDatabase>();
        final programmesDao = PatientProgrammesDao(appDb);
        final programmesByPatient = await programmesDao.programmesForMany(
          allPatientIds,
        );
        // Visit counts so a non-queue member's badge is visit-count-aware
        // ("ANC Visit 3 due"), identical to the dashboard's real badge —
        // same DAO/kind-lists WorklistRepository uses (programme_reason.dart).
        final assessmentDao = AssessmentDao(appDb);
        final ancCounts = await assessmentDao.visitCountsByPatients(
          allPatientIds,
          ancVisitKinds,
        );
        final pncCounts = await assessmentDao.visitCountsByPatients(
          allPatientIds,
          pncVisitKinds,
        );

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
            return _HouseholdMember.fromEntity(
              e,
              programmes: progs,
              ancVisitCount: e.patientId != null
                  ? (ancCounts[e.patientId!] ?? 0)
                  : 0,
              pncVisitCount: e.patientId != null
                  ? (pncCounts[e.patientId!] ?? 0)
                  : 0,
            );
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

          items.add(
            _HouseholdItem(
              id: hhId,
              householdNo: hhId,
              name: householdName,
              village: firstMember.subVillageId,
              memberCount: members.length,
              members: memberList,
            ),
          );
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              FutureBuilder<List<_HouseholdItem>>(
                future: _future,
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <_HouseholdItem>[];
                  final filtered = _filterByVillage(items);
                  final totalMembers = filtered.fold<int>(
                    0,
                    (sum, h) => sum + (h.memberCount ?? 0),
                  );
                  return _buildHeader(context, filtered.length, totalMembers);
                },
              ),
              // 12px gap — matches the Home dashboard's own spacing between
              // its header and PatientFilterPanel/village-tab row.
              const SizedBox(height: AppSpacing.xl),
              _buildVillageTabRow(),
              Expanded(
                child: _future == null
                    ? const SizedBox.shrink()
                    : FutureBuilder<List<_HouseholdItem>>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                    ),
                                    child: Text(
                                      '${snapshot.error}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
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
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    HouseholdListStrings.noMembers,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            );
                          }
                          if (_searchQuery.length >= 2) {
                            return _buildMemberSearchResults(context);
                          }
                          return _buildHouseholdsList(context, items);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberSearchResults(BuildContext context) {
    if (_memberSearchBusy) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_memberSearchHits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(HouseholdListStrings.noMembers, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }
    debugPrint('[HouseholdList] rendering ${_memberSearchHits.length} member search results');
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
      itemCount: _memberSearchHits.length,
      separatorBuilder: (context, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final hit = _memberSearchHits[index];
        return _MemberSearchResultTile(
          hit: hit,
          onTap: () {
            final id = hit.id;
            if (id == null || id.isEmpty) return;
            debugPrint('[HouseholdList] search result tap: id=$id name=${hit.name}');
            context.push('/patients/$id?origin=household', extra: {
              'id': hit.id,
              'name': hit.name,
              'gender': hit.gender,
              'phoneNumber': hit.phone,
              'idCode': hit.nid,
              'householdId': hit.householdId,
            });
          },
        );
      },
    );
  }

  /// Households matching the selected village tab (search is applied
  /// per-item in [_buildHouseholdsList] since it also needs the member list).
  List<_HouseholdItem> _filterByVillage(List<_HouseholdItem> items) {
    if (_selectedInlineVillageId == null) return items;
    return items
        .where(
          (h) => h.members.any(
            (m) => m.subVillageId == _selectedInlineVillageId,
          ),
        )
        .toList();
  }

  /// Navy header: back button, 🏠-prefixed title, combined live "N
  /// households · M patients" count, a manual refresh button, and the search
  /// bar — matching the v13 mockup's `#householdsScreen` header (background,
  /// back button, type).
  Widget _buildHeader(
    BuildContext context,
    int householdCount,
    int patientCount,
  ) {
    return Container(
      color: AppColors.navy,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 10,
        20,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Bottom-nav tab root, so "back" means Home — mirrors the
              // mockup's own back button (`onclick="go('s2')"` → Home).
              HeaderIconButton(
                icon: Icons.arrow_back,
                tooltip: BottomNavStrings.home,
                onTap: () => context.go('/home'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      HouseholdListStrings.headerTitle,
                      style: AppTextStyles.householdHeaderTitle,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      HouseholdListStrings.headerSummary(
                        householdCount,
                        patientCount,
                      ),
                      style: AppTextStyles.householdHeaderSub,
                    ),
                  ],
                ),
              ),
              HeaderIconButton(
                icon: Icons.cloud_download_outlined,
                tooltip: PatientContextStrings.refresh,
                onTap: _refreshing ? null : _refreshFromServer,
                child: _refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : null,
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
                    onChanged: (v) {
                      final q = v.trim();
                      setState(() => _searchQuery = q.toLowerCase());
                      _runMemberSearch(q);
                    },
                    style: const TextStyle(
                      fontFamily: 'NunitoSans',
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      hintText: HouseholdListStrings.searchHint,
                      // fontSize matches the Home dashboard's own search bar
                      // hint (DashboardSearchField, fontSize: 14).
                      hintStyle: TextStyle(
                        fontFamily: 'NunitoSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                      // The global inputDecorationTheme sets explicit
                      // enabledBorder/focusedBorder (app_theme.dart:2014-2021)
                      // which win over a bare `border:` override — every
                      // state must be suppressed individually to get the
                      // mockup's flat, borderless white pill.
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _memberSearchHits = const [];
                      });
                    },
                    child: const Icon(
                      Icons.clear,
                      size: 18,
                      color: Color(0xFF9CA3AF),
                    ),
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
  /// Uses `VillageFilterTab`'s default styling (no `fontWeight` override) so
  /// this screen's village tabs render identically to the Home dashboard's.
  Widget _buildVillageTabRow() {
    if (_inlineVillages.isEmpty) return const SizedBox.shrink();
    return Container(
      // Explicit width — as a plain (non-Expanded) child of the outer
      // Column, this Container otherwise shrink-wraps to the tab row's
      // own short content width, and the Column's default center
      // cross-axis-alignment then centers that narrow box instead of
      // stretching it, unlike the header/list which force full width via
      // Expanded/Row-with-Expanded.
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      // 16px matches the Home dashboard's own body-content inset
      // (mission_dashboard_screen.dart's PatientFilterPanel/list padding)
      // — and matches the household list's padding below, so the tabs and
      // the cards line up with each other, not just with the header.
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
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
                  label: titleCaseWords(v.name),
                  isActive: _selectedInlineVillageId == v.id,
                  onTap: () => setState(() => _selectedInlineVillageId = v.id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHouseholdsList(
    BuildContext context,
    List<_HouseholdItem> items,
  ) {
    final villageFiltered = _filterByVillage(items);
    final filteredItems = _searchQuery.isEmpty
        ? villageFiltered
        : villageFiltered
              .where((h) => _matchesSearch(h, _searchQuery))
              .toList();

    if (filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
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

    return ListView.separated(
      controller: _scrollController,
      // 16px matches the village-tab row above it and the Home dashboard's
      // own body-content inset.
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
          primaryMemberRow: _buildMemberRow(
            context,
            _MemberInfo.fromMember(primary, item),
          ),
          primaryRelation: _displayRelation(primary.relation),
          otherMembers: others,
          isExpanded: _expandedHouseholdIds.contains(id),
          onToggleExpanded: id.isEmpty
              ? null
              : () => setState(() {
                  if (!_expandedHouseholdIds.remove(id)) {
                    _expandedHouseholdIds.add(id);
                  }
                }),
          onMemberTap: (other) => _navigateToMemberDetail(
            context,
            _MemberInfo.fromMember(other, item),
          ),
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
      debugPrint(
        '[HouseholdList] Skipping nav — member has no usable ID: ${member.name}',
      );
      return;
    }
    // Push directly to /patients/:id — the /patient/:id redirect drops extra.
    context.push(
      '/patients/$id?origin=household',
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
  /// plain `PatientBadgeRow`.
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
          if (navId != null &&
              navId.isNotEmpty &&
              navId != 'household' &&
              navId != 'households') {
            context.go(
              '/patients/$navId',
              extra: {'name': queueItem.patientName},
            );
          }
        },
      );
    }
    return PatientBadgeRow(
      name: member.name,
      age: member.age,
      gender: member.gender,
      phoneNumber: member.phoneNumber,
      programmes: member.programmes,
      ancVisitCount: member.ancVisitCount,
      pncVisitCount: member.pncVisitCount,
      householdNo: member.householdNo,
      householdName: member.householdName,
      onTap: () => _navigateToMemberDetail(context, member),
    );
  }

  /// Resolves a household's stored village value (which may be a raw village
  /// id from the members-grouping path, or already a name from the entity/
  /// JSON fallback paths) to a display name via the same village list the
  /// filter tabs use. Falls back to the stored value when no match is found.
  static final _bareIdPattern = RegExp(r'^\d+$');

  String? _villageDisplayName(String? villageIdOrName) {
    if (villageIdOrName == null || villageIdOrName.isEmpty) return null;
    for (final v in _inlineVillages) {
      if (v.id == villageIdOrName) return titleCaseWords(v.name);
    }
    // No match in the resolved village-tab list — if this is a raw database
    // id rather than an actual place name, don't surface it at all (a bare
    // "26" reads as broken, not helpful); a real name we just couldn't
    // cross-reference is still shown as-is.
    if (_bareIdPattern.hasMatch(villageIdOrName)) return null;
    return titleCaseWords(villageIdOrName);
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

/// The relation worth showing next to a primary member row — null for a
/// blank relation or for the household head/self (redundant: they're already
/// the household's own name at the top of the card).
String? _displayRelation(String? relation) {
  if (relation == null || relation.isEmpty) return null;
  final lower = relation.toLowerCase();
  if (lower == 'head' || lower == 'self') return null;
  return relation;
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
    this.primaryRelation,
    required this.otherMembers,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onMemberTap,
    this.onTap,
  });

  final _HouseholdItem item;
  final String? villageDisplayName;
  final Widget primaryMemberRow;

  /// The primary member's relation to the household head (e.g. "Husband"),
  /// or null when not shown (blank, or the member IS the head/self).
  final String? primaryRelation;
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
        ? (item.members
              .firstWhere(
                (m) => m.isHouseholdHead == true,
                orElse: () => item.members.first,
              )
              .name)
        : null;
    final title =
        headName ??
        item.name ??
        (item.householdNo != null
            ? 'Household #${item.householdNo}'
            : HouseholdListStrings.unnamedHousehold);

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
                decoration: const BoxDecoration(
                  color: AppColors.cardSurfaceMuted,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.progressTrack,
                      width: 1,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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
                          if (villageDisplayName != null &&
                              villageDisplayName!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              villageDisplayName!,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: AppColors.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
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
          if (primaryRelation != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(
                primaryRelation!,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
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
                      HouseholdListStrings.otherMembersToggle(
                        otherMembers.length,
                      ),
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
                      _OtherMemberRow(
                        member: other,
                        onTap: () => onMemberTap(other),
                      ),
                  ],
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
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
      if (member.relation != null && member.relation!.isNotEmpty)
        member.relation,
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
              decoration: const BoxDecoration(
                color: AppColors.progressTrack,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                memberInitials(member.name),
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
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                      ),
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
              child: Text(
                HouseholdListStrings.enrolledTag,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.statusSuccessAction,
                ),
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
      if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
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
          if (now.month < dob.month ||
              (now.month == dob.month && now.day < dob.day)) {
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
      memberCount: memberDataList.isNotEmpty
          ? memberDataList.length
          : memberCount,
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
    if (latVal is double) {
      lat = latVal;
    } else if (latVal is num) {
      lat = latVal.toDouble();
    }
    if (lngVal is double) {
      lng = lngVal;
    } else if (lngVal is num) {
      lng = lngVal.toDouble();
    }

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
      rawJson: json is Map<String, dynamic>
          ? json
          : Map<String, dynamic>.from(json),
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
        'noOfPeople': memberList.isNotEmpty
            ? memberList.length
            : hh.memberCount,
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
    this.subVillageId,
    this.subVillageName,
    this.programmes = const {},
    this.ancVisitCount = 0,
    this.pncVisitCount = 0,
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
  /// Parent village id — real village level, but shown nowhere on this
  /// screen: the Patients screen's village-tab filter now matches the
  /// Home dashboard's granularity (sub-village), per product decision, since
  /// `Patient.villageName`/`villageId` (dashboard's worklist) are already
  /// sub-village data under a misleading name.
  final String? villageId;
  final String? subVillageId;
  final String? subVillageName;
  final Set<Programme> programmes;

  /// Completed ANC/PNC visit counts — drives the visit-count-aware badge
  /// label ("ANC Visit 3 due"), identical to the dashboard's real badge.
  final int ancVisitCount;
  final int pncVisitCount;

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
    final isHead =
        relationLower == 'head' ||
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
      subVillageId: str('subVillageId'),
      subVillageName: str('subVillage') ?? str('subVillageName'),
    );
  }

  /// Creates from local SQLite HouseholdMemberEntity.
  static _HouseholdMember fromEntity(
    HouseholdMemberEntity e, {
    Set<Programme> programmes = const {},
    int ancVisitCount = 0,
    int pncVisitCount = 0,
  }) {
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
      subVillageId: e.subVillageId,
      subVillageName: e.subVillageName,
      programmes: programmes,
      ancVisitCount: ancVisitCount,
      pncVisitCount: pncVisitCount,
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
    this.subVillageId,
    this.householdMemberCount,
    this.programmes = const {},
    this.ancVisitCount = 0,
    this.pncVisitCount = 0,
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

  /// Sub-village id — matches [_HouseholdListScreenState._selectedInlineVillageId],
  /// which is populated from sub-village data (see [_HouseholdMember.villageId]'s
  /// doc comment for why "village" means sub-village on this screen).
  final String? subVillageId;
  final int? householdMemberCount;
  final Set<Programme> programmes;
  final int ancVisitCount;
  final int pncVisitCount;

  /// Calculate age from date of birth if not directly provided.
  static int? _calculateAge(String? dateOfBirth) {
    if (dateOfBirth == null) return null;
    try {
      final dob = DateTime.parse(dateOfBirth);
      final now = DateTime.now();
      var age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  /// Create from _HouseholdMember and household context.
  factory _MemberInfo.fromMember(
    _HouseholdMember member,
    _HouseholdItem household,
  ) {
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
      subVillageId: member.subVillageId,
      householdMemberCount: household.memberCount,
      programmes: member.programmes,
      ancVisitCount: member.ancVisitCount,
      pncVisitCount: member.pncVisitCount,
    );
  }
}

class _MemberSearchResultTile extends StatelessWidget {
  const _MemberSearchResultTile({required this.hit, required this.onTap});

  final MemberHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFEFF6FF),
              child: Text(
                hit.name?.isNotEmpty == true
                    ? hit.name![0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.name ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    [
                      if (hit.gender != null) hit.gender!,
                      if (hit.phone != null) hit.phone!,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 20),
          ],
        ),
      ),
    );
  }
}
