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
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/db/roster_revision.dart';
import '../../core/mission/programme_reason.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/programme.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/sync/offline_sync_service.dart';
import '../../core/widgets/header_icon_button.dart';
import '../../core/widgets/mockup_svg_icons.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/patient_filter_panel.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/mission_dashboard_repository.dart';
import '../visit/widgets/mission_queue_card.dart' show PatientBadgeRow, programmeBadgeColors;
import 'member_assessment_lookup.dart';
import 'enrollment/enrollment_dob.dart';
import 'enrollment/enrollment_entry_sheet.dart';
import 'enrollment/nid_ocr_service.dart';
import '../../core/db/service_member_dao.dart';
import 'household_detail_screen.dart';
import 'members_service_type_dropdown.dart';
import 'service_member_list_tile.dart';
import 'service_static_filter.dart';

/// Watches the Patients branch navigator; registered in `router.dart`.
///
/// `/patients` and `/patients/households` both render this screen, so a
/// `go('/patients/households')` (used when the enrollment flow finishes)
/// stacks a second copy on top of the first. When that copy is later removed,
/// the original is revealed still holding the roster it queried on open. This
/// observer lets it notice and re-read.
final RouteObserver<ModalRoute<void>> patientsRouteObserver =
    RouteObserver<ModalRoute<void>>();

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

class _HouseholdListScreenState extends State<HouseholdListScreen>
    with RouteAware {
  List<_HouseholdItem>? _householdItems;
  bool _householdsLoading = false;
  Object? _householdLoadError;
  int _householdLoadGeneration = 0;
  final ScrollController _scrollController = ScrollController();

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Household IDs whose "other members" panel is expanded.
  final Set<String> _expandedHouseholdIds = {};

  // patientId -> queue item, so a household's flagged member (if any) can be
  // rendered with its real urgency badge/status via MissionQueueCard.
  Map<String, MissionQueueItem> _queueItems = {};

  // Inline village-tab row (populated from local DB after data loads).
  List<({String id, String name})> _inlineVillages = const [];
  String? _selectedInlineVillageId;

  bool _refreshing = false;

  /// UHIS service-recipient cohort (dropdown above village chips).
  ServiceStaticFilter _serviceFilter = ServiceStaticFilter.allMembers;
  final List<ServiceStaticFilter> _allowedServiceFilters =
      ServiceStaticFilter.allowedForSk();
  Map<ServiceStaticFilter, int> _serviceCounts = {};
  /// All-member count for navy header — always roster-wide (ignores village chip).
  int? _rosterAllMembersCount;
  Future<List<ServiceMemberListRow>>? _serviceMembersFuture;

  @override
  void initState() {
    debugPrint('[_HouseholdListScreenState] initState');
    super.initState();
    // Defer loading until after first frame when context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadData();
        _loadQueueItems();
      }
    });
    // This screen lives inside the nav shell's IndexedStack, so it stays
    // mounted while the user is on another tab and gets no callback when they
    // come back. Enrollment finishes with go('/home') — not a pop — so
    // didPopNext never fires for it either, and the new household would stay
    // invisible here until the app restarted.
    rosterRevision.addListener(_onRosterChanged);
  }

  void _onRosterChanged() {
    if (!mounted) return;
    debugPrint('[_HouseholdListScreenState] roster revision changed — reloading');
    _loadData();
    _loadQueueItems();
  }

  /// Loads the mission queue so a household's flagged member (if any) can
  /// render with its real urgency badge/status.
  Future<void> _loadQueueItems() async {
    debugPrint('[_HouseholdListScreenState] _loadQueueItems');
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      patientsRouteObserver.subscribe(this, route);
    }
  }

  /// A route above this one was popped — households or members may have been
  /// created while it was covered.
  @override
  void didPopNext() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    debugPrint('[_HouseholdListScreenState] dispose');
    rosterRevision.removeListener(_onRosterChanged);
    patientsRouteObserver.unsubscribe(this);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  void _loadData() {
    debugPrint('[_HouseholdListScreenState] _loadData');
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
      if (_householdItems == null) _householdsLoading = true;
      _householdLoadError = null;
    });
    unawaited(
      _reloadHouseholdList(householdDao, memberDao, repo),
    );
    _loadServiceFilterMeta();
  }

  Future<void> _loadServiceFilterMeta() async {
    if (!mounted) return;
    final dao = context.read<ServiceMemberDao>();
    try {
      final searchForDropdown = _serviceFilter == ServiceStaticFilter.allMembers
          ? ''
          : _searchController.text.trim();
      final villageId = _selectedInlineVillageId;
      if (villageId == null) {
        final counts = await dao.countForFilters(
          filters: _allowedServiceFilters,
          searchInput: searchForDropdown,
          subVillageId: null,
        );
        if (!mounted) return;
        setState(() {
          _serviceCounts = counts;
          _rosterAllMembersCount = counts[ServiceStaticFilter.allMembers];
        });
      } else {
        final results = await Future.wait<Map<ServiceStaticFilter, int>>([
          dao.countForFilters(
            filters: _allowedServiceFilters,
            searchInput: searchForDropdown,
            subVillageId: villageId,
          ),
          dao.countForFilters(
            filters: const [ServiceStaticFilter.allMembers],
            subVillageId: null,
          ),
        ]);
        if (!mounted) return;
        setState(() {
          _serviceCounts = results[0];
          _rosterAllMembersCount =
              results[1][ServiceStaticFilter.allMembers];
        });
      }
      if (_serviceFilter != ServiceStaticFilter.allMembers) {
        _reloadServiceMembers();
      }
    } catch (e, st) {
      debugPrint('[HouseholdList] service filter meta failed: $e\n$st');
    }
  }

  void _reloadServiceMembers() {
    final dao = context.read<ServiceMemberDao>();
    setState(() {
      _serviceMembersFuture = dao.getMembers(
        filter: _serviceFilter,
        searchInput: _searchController.text.trim(),
        subVillageId: _selectedInlineVillageId,
      );
    });
  }

  void _onServiceFilterSelected(ServiceStaticFilter filter) {
    setState(() {
      _serviceFilter = filter;
      if (filter == ServiceStaticFilter.allMembers) {
        _serviceMembersFuture = null;
      }
    });
    if (filter != ServiceStaticFilter.allMembers) {
      _reloadServiceMembers();
    }
  }

  /// Navy subtitle counts — same scope as dropdown **All member list**
  /// ([ServiceMemberDao] `household_id IS NOT NULL`), not the orphan bucket.
  (int households, int members) _headerRosterTotals(
    List<_HouseholdItem> items,
  ) {
    final linkedHouseholds =
        items.where((h) => (h.id ?? '').isNotEmpty).toList();
    final membersFromCards = linkedHouseholds.fold<int>(
      0,
      (sum, h) => sum + (h.memberCount ?? 0),
    );
    final members = _rosterAllMembersCount ?? membersFromCards;
    return (linkedHouseholds.length, members);
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

  /// Loads roster from SQLite: show household cards immediately, then badges.
  Future<void> _reloadHouseholdList(
    HouseholdDao householdDao,
    MemberDao memberDao,
    DashboardRepository repo,
  ) async {
    final generation = ++_householdLoadGeneration;
    debugPrint('[_HouseholdListScreenState] _reloadHouseholdList gen=$generation');
    try {
      final loaded = await Future.wait<Object?>([
        householdDao.getAll(limit: 1000),
        memberDao.getAllGroupedByHousehold(),
      ]);
      if (!mounted || generation != _householdLoadGeneration) return;
      final localHouseholds = loaded[0]! as List<HouseholdEntity>;
      final membersByHousehold =
          loaded[1]! as Map<String, List<HouseholdMemberEntity>>;

      List<_HouseholdItem> items;
      if (membersByHousehold.isNotEmpty) {
        items = _buildHouseholdItemsSkeleton(
          membersByHousehold,
          localHouseholds,
        );
      } else if (localHouseholds.isNotEmpty) {
        items = localHouseholds
            .map((hh) => _HouseholdItem.fromEntity(hh, []))
            .toList();
      } else {
        final rawList = await repo.getHouseholdsWithMembers();
        if (!mounted || generation != _householdLoadGeneration) return;
        items = rawList.map((raw) => _HouseholdItem.fromJson(raw)).toList();
        setState(() {
          _householdItems = items;
          _householdsLoading = false;
          _householdLoadError = null;
        });
        return;
      }

      setState(() {
        _householdItems = items;
        _householdsLoading = false;
        _householdLoadError = null;
      });

      if (membersByHousehold.isEmpty) return;

      final appDb = context.read<AppDatabase>();
      final enriched = await _enrichHouseholdItems(
        membersByHousehold,
        localHouseholds,
        appDb,
      );
      if (!mounted || generation != _householdLoadGeneration) return;
      setState(() => _householdItems = enriched);
    } catch (e, st) {
      debugPrint('[HouseholdList] load failed: $e\n$st');
      if (!mounted || generation != _householdLoadGeneration) return;
      setState(() {
        _householdLoadError = e;
        _householdsLoading = false;
      });
    }
  }

  List<_HouseholdItem> _buildHouseholdItemsSkeleton(
    Map<String, List<HouseholdMemberEntity>> membersByHousehold,
    List<HouseholdEntity> localHouseholds,
  ) {
    final items = <_HouseholdItem>[];
    for (final entry in membersByHousehold.entries) {
      final hhId = entry.key;
      final members = entry.value;
      final firstMember = members.first;
      final memberList =
          members.map((e) => _HouseholdMember.fromEntity(e)).toList();
      final head = memberList.firstWhere(
        (m) => m.isHouseholdHead == true,
        orElse: () => memberList.first,
      );
      final householdName = head.name != null
          ? HouseholdListStrings.namedHousehold(head.name!)
          : (hhId.isNotEmpty ? '#$hhId' : null);
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
    final coveredIds = membersByHousehold.keys.toSet();
    for (final hh in localHouseholds) {
      if (!coveredIds.contains(hh.id)) {
        items.add(_HouseholdItem.fromEntity(hh, []));
      }
    }
    return items;
  }

  Future<List<_HouseholdItem>> _enrichHouseholdItems(
    Map<String, List<HouseholdMemberEntity>> membersByHousehold,
    List<HouseholdEntity> localHouseholds,
    AppDatabase appDb,
  ) async {
    final allEntities =
        membersByHousehold.values.expand((e) => e).toList(growable: false);
    if (allEntities.isEmpty) {
      return _buildHouseholdItemsSkeleton(membersByHousehold, localHouseholds);
    }

    final tableKeys = <String>{
      for (final e in allEntities)
        if (memberSideTableKey(e) != null) memberSideTableKey(e)!,
    }.toList();
    final allLookupKeys = <String>{
      for (final e in allEntities) ...memberAssessmentLookupKeysFromEntity(e),
    }.toList();

    final programmesDao = PatientProgrammesDao(appDb);
    final assessmentDao = AssessmentDao(appDb);
    final localAssessmentDao = LocalAssessmentDao(appDb);

    final results = await Future.wait<Object?>([
      programmesDao.programmesForMany(tableKeys),
      assessmentDao.latestAssessmentForMany(allLookupKeys),
      assessmentDao.visitCountsByPatients(allLookupKeys, ancVisitKinds),
      assessmentDao.visitCountsByPatients(allLookupKeys, pncVisitKinds),
      localAssessmentDao.visitCountsByPatients(allLookupKeys, ancVisitKinds),
      localAssessmentDao.visitCountsByPatients(
        allLookupKeys,
        pncLocalVisitKinds,
      ),
      localAssessmentDao.latestLocalServiceForMany(allLookupKeys),
    ]);

    final programmesByPatient =
        results[0]! as Map<String, Set<Programme>>;
    final latestSynced = results[1]! as Map<String, AssessmentRow>;
    final assessmentsByPatient = {
      for (final e in latestSynced.entries) e.key: [e.value],
    };
    final ancSyncedCounts = results[2]! as Map<String, int>;
    final pncSyncedCounts = results[3]! as Map<String, int>;
    final ancLocalCounts = results[4]! as Map<String, int>;
    final pncLocalCounts = results[5]! as Map<String, int>;
    final localServices =
        results[6]! as Map<String, ({String type, int at})>;

    final items = <_HouseholdItem>[];
    for (final entry in membersByHousehold.entries) {
      final hhId = entry.key;
      final members = entry.value;
      final firstMember = members.first;
      final memberList = members.map((e) {
        final lookupKeys = memberAssessmentLookupKeysFromEntity(e);
        final tableKey = memberSideTableKey(e);
        final progs = tableKey != null
            ? (programmesByPatient[tableKey] ?? const <Programme>{})
            : const <Programme>{};
        final recentService = resolveRecentServiceKind(
          lookupKeys: lookupKeys,
          syncedByKey: assessmentsByPatient,
          localLatestByPatientId: localServices,
        );
        return _HouseholdMember.fromEntity(
          e,
          programmes: progs,
          ancVisitCount: combinedVisitCount(
            lookupKeys: lookupKeys,
            syncedCounts: ancSyncedCounts,
            localPendingCounts: ancLocalCounts,
          ),
          pncVisitCount: combinedVisitCount(
            lookupKeys: lookupKeys,
            syncedCounts: pncSyncedCounts,
            localPendingCounts: pncLocalCounts,
          ),
          recentService: recentService,
        );
      }).toList();
      final head = memberList.firstWhere(
        (m) => m.isHouseholdHead == true,
        orElse: () => memberList.first,
      );
      final householdName = head.name != null
          ? HouseholdListStrings.namedHousehold(head.name!)
          : (hhId.isNotEmpty ? '#$hhId' : null);
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
    final coveredIds = membersByHousehold.keys.toSet();
    for (final hh in localHouseholds) {
      if (!coveredIds.contains(hh.id)) {
        items.add(_HouseholdItem.fromEntity(hh, []));
      }
    }
    return items;
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
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              Builder(
                builder: (context) {
                  final items = _householdItems ?? const <_HouseholdItem>[];
                  final (householdCount, memberCount) =
                      _headerRosterTotals(items);
                  return _buildHeader(
                    context,
                    householdCount,
                    memberCount,
                  );
                },
              ),
              // 12px gap — matches the Home dashboard's own spacing between
              // its header and PatientFilterPanel/village-tab row.
              const SizedBox(height: AppSpacing.xl),
              MembersServiceTypeDropdown(
                filters: _allowedServiceFilters,
                selected: _serviceFilter,
                counts: _serviceCounts,
                onSelected: _onServiceFilterSelected,
              ),
              const SizedBox(height: AppSpacing.xl),
              _buildVillageTabRow(),
              Expanded(
                child: _serviceFilter == ServiceStaticFilter.allMembers
                    ? _buildAllMembersHouseholdBody(context)
                    : _buildServiceMembersBody(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Household cards with head + expand — default when dropdown is All member list.
  Widget _buildAllMembersHouseholdBody(BuildContext context) {
    if (_householdsLoading && _householdItems == null) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_householdLoadError != null && _householdItems == null) {
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
                '$_householdLoadError',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadData,
              child: Text(CommonStrings.retry),
            ),
          ],
        ),
      );
    }
    final items = _householdItems ?? const <_HouseholdItem>[];
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: EmptyStateCard(
            icon: Icons.people_outline,
            iconColor: AppColors.textMuted,
            iconBg: AppColors.border,
            title: HouseholdListStrings.noMembers,
          ),
        ),
      );
    }
    return _buildHouseholdsList(context, items);
  }

  /// UHIS-style flat list for a specific service cohort (not All member list).
  Widget _buildServiceMembersBody(BuildContext context) {
    final future = _serviceMembersFuture;
    if (future == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return FutureBuilder<List<ServiceMemberListRow>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('${snapshot.error}'),
            ),
          );
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: EmptyStateCard(
                icon: Icons.person_search_outlined,
                iconColor: AppColors.textMuted,
                iconBg: AppColors.border,
                title: HouseholdListStrings.noMembers,
              ),
            ),
          );
        }
        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final row = rows[index];
            final info = _MemberInfo.fromServiceRow(row);
            return ServiceMemberListTile(
              row: row,
              onTap: () => _navigateToMemberDetail(context, info),
            );
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
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
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
              color: lc.cardSurface,
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
                      setState(() => _searchQuery = v.trim().toLowerCase());
                      _loadServiceFilterMeta();
                    },
                    style: const TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      hintText:
                          _serviceFilter == ServiceStaticFilter.allMembers
                              ? HouseholdListStrings.searchHint
                              : ServiceMemberFilterStrings.memberSearchHint,
                      // fontSize matches the Home dashboard's own search bar
                      // hint (DashboardSearchField, fontSize: 14).
                      hintStyle: TextStyle(
                        fontFamily: AppFonts.body,
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
                      setState(() => _searchQuery = '');
                      _loadServiceFilterMeta();
                    },
                    child: Icon(
                      Icons.clear,
                      size: 18,
                      color: lc.textMuted,
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
                onTap: () {
                  setState(() => _selectedInlineVillageId = null);
                  _loadServiceFilterMeta();
                },
              ),
              for (final v in _inlineVillages)
                VillageFilterTab(
                  label: titleCaseWords(v.name),
                  isActive: _selectedInlineVillageId == v.id,
                  onTap: () {
                    setState(() => _selectedInlineVillageId = v.id);
                    _loadServiceFilterMeta();
                  },
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: EmptyStateCard(
            icon: Icons.search_off,
            iconColor: AppColors.textMuted,
            iconBg: AppColors.border,
            title: HouseholdListStrings.noMembers,
          ),
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
        final q = _searchQuery;
        final highlightPrimary = primary != null &&
            q.isNotEmpty &&
            (primary.name?.toLowerCase().contains(q) ?? false);
        return _HouseholdCard(
          item: item,
          villageDisplayName: _villageDisplayName(item.village),
          primaryMemberRow: primary != null
              ? _buildMemberRow(
                  context,
                  _MemberInfo.fromMember(primary, item),
                )
              : const SizedBox.shrink(),
          highlightPrimary: highlightPrimary,
          searchQuery: q,
          primaryRelation: primary != null
              ? _displayRelation(primary.relation)
              : null,
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
          onAddMember: () => _addMemberToHousehold(item),
        );
      },
    );
  }

  /// Search predicate: household/member name or village name.
  /// Household number is intentionally excluded (product decision).
  bool _matchesSearch(_HouseholdItem h, String query) {
    final villageName = _villageDisplayName(h.village) ?? '';
    final haystack = [
      h.name ?? '',
      villageName,
      ...h.members.map((m) => m.name ?? ''),
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  Future<void> _navigateToDetail(
      BuildContext context, _HouseholdItem item) async {
    debugPrint('[_HouseholdListScreenState] _navigateToDetail id=${item.id}');
    final id = item.id;
    if (id == null || id.isEmpty) {
      debugPrint('[HouseholdList] Skipping nav — household has empty ID');
      return;
    }
    await context.push('/patients/household/$id', extra: item.toDetailData());
    // A member may have been added from the detail screen. This list only
    // queries on init, so without this the card's member count (and the header
    // totals) would keep showing the roster as it was when the screen opened.
    if (mounted) _loadData();
  }

  /// Opens the NID scanner then the add-member form for [item]'s household.
  Future<void> _addMemberToHousehold(_HouseholdItem item) async {
    final localId = item.id ?? '';
    if (localId.isEmpty) return;

    // Use the screen State's context — not a ListView itemBuilder context,
    // which is deactivated after the async scanner closes.
    final result = await showNidScannerForMember(context);
    if (!mounted || result == null) return;

    final householdEntity =
        await context.read<HouseholdDao>().getById(localId);
    if (!mounted) return;

    final serverHouseholdId = householdEntity?.fhirId ?? localId;

    final villageId = householdEntity?.villageId ??
        item.members.firstOrNull?.villageId ??
        item.rawJson?['villageId'] as String? ??
        '';
    final subVillageId = householdEntity?.subVillageId ?? '';
    final subVillageName = householdEntity?.subVillageName ?? '';
    final memberNames = item.members
        .map((m) => m.name)
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    final head = _headMember(item.members);
    final extra = <String, dynamic>{
      'householdId': serverHouseholdId,
      'householdReferenceId': localId,
      'householdName': item.name ?? '',
      'householdNo': item.householdNo ?? '',
      'headName': head?.name ?? '',
      'headPhoneNumber': head?.phoneNumber?.trim().isNotEmpty == true
          ? head!.phoneNumber!.trim()
          : householdEntity?.headPhoneNumber?.trim(),
      'villageId': villageId,
      'villageName': item.village ?? '',
      'subVillageId': subVillageId,
      'subVillageName': subVillageName,
      'memberNames': memberNames,
    };
    if (result.status == NidScanStatus.success && result.data != null) {
      extra['fromNidScan'] = true;
      extra['nidNumber'] = result.data!.nidNumber;
      extra['name'] = result.data!.name;
      extra['dateOfBirth'] = result.data!.dateOfBirth;
    }
    if (!mounted) return;
    await context.push('/household/enrollment/link-member', extra: extra);
    if (mounted) _loadData();
  }

  void _navigateToMemberDetail(BuildContext context, _MemberInfo member) {
    debugPrint('[_HouseholdListScreenState] _navigateToMemberDetail patientId=${member.patientId} id=${member.id} name=${member.name}');
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
        'isActive': member.isActive,
      },
    );
  }

  /// Member row matching the v14 wireframe — uses [PatientBadgeRow] with the
  /// same latest-service badge as the household detail screen, plus a
  /// [_TierStatusPill] when the member has an active queue entry.
  Widget _buildMemberRow(BuildContext context, _MemberInfo member) {
    final pid = member.patientId ?? member.id;
    final queueItem = pid != null ? _queueItems[pid] : null;
    final tier = queueItem?.tier;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: PatientBadgeRow(
            name: member.name,
            ageLabel: member.ageLabel,
            gender: member.gender,
            phoneNumber: member.phoneNumber,
            programmes: member.programmes,
            ancVisitCount: member.ancVisitCount,
            pncVisitCount: member.pncVisitCount,
            householdNo: member.householdNo,
            householdName: member.householdName,
            useLatestServiceBadge: true,
            recentServiceKind: member.recentService,
            isDeceased: !member.isActive,
            onTap: () => _navigateToMemberDetail(context, member),
          ),
        ),
        if (tier != null && tier != DashboardTier.upcoming) ...[
          const SizedBox(width: 8),
          _TierStatusPill(tier: tier),
        ],
      ],
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
  _HouseholdMember? _primaryMember(_HouseholdItem item) {
    if (item.members.isEmpty) return null;
    for (final m in item.members) {
      final pid = m.patientId ?? m.id;
      if (pid != null && _queueItems.containsKey(pid)) return m;
    }
    return item.members.firstWhere(
      (m) => m.isHouseholdHead == true,
      orElse: () => item.members.first,
    );
  }

  _HouseholdMember? _headMember(List<_HouseholdMember> members) {
    if (members.isEmpty) return null;
    for (final m in members) {
      if (m.isHouseholdHead == true) return m;
    }
    return members.first;
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
/// Self-sufficient household card: the household header (🏠 emoji, head name,
/// village), the one flagged/actionable member inline ([primaryMemberRow]),
/// and — if there are more members — an expandable "+N other household
/// members" panel. No extra navigation is needed to see who's in the household.
class _HouseholdCard extends StatelessWidget {
  const _HouseholdCard({
    required this.item,
    required this.villageDisplayName,
    required this.primaryMemberRow,
    this.highlightPrimary = false,
    this.searchQuery = '',
    this.primaryRelation,
    required this.otherMembers,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onMemberTap,
    this.onTap,
    this.onAddMember,
  });

  final _HouseholdItem item;
  final String? villageDisplayName;
  final Widget primaryMemberRow;

  /// Whether the primary member row should be highlighted (name matches query).
  final bool highlightPrimary;

  /// Active search query — used to highlight matching other members and
  /// auto-expand the panel when a non-primary member matches.
  final String searchQuery;

  /// The primary member's relation to the household head (e.g. "Husband"),
  /// or null when not shown (blank, or the member IS the head/self).
  final String? primaryRelation;
  final List<_HouseholdMember> otherMembers;
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;
  final void Function(_HouseholdMember other) onMemberTap;
  final VoidCallback? onTap;
  final VoidCallback? onAddMember;

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
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
            ? '#${item.householdNo}'
            : HouseholdListStrings.unnamedHousehold);

    return Container(
      decoration: BoxDecoration(
        color: lc.cardSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.householdCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: lc.cardSurfaceMuted,
                border: Border(
                  bottom: BorderSide(
                    color: lc.surfaceTrack,
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
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: AppFonts.display,
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
                    ),
                    if (onAddMember != null) ...[
                      const SizedBox(width: 8),
                      _HouseholdAddMemberButton(onPressed: onAddMember!),
                    ],
                  ],
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
            child: highlightPrimary
                ? _SearchMatchHighlight(child: primaryMemberRow)
                : primaryMemberRow,
          ),
          if (otherMembers.isNotEmpty)
            Builder(builder: (context) {
              final anyOtherMatches = searchQuery.isNotEmpty &&
                  otherMembers.any(
                    (m) => m.name?.toLowerCase().contains(searchQuery) ?? false,
                  );
              final showExpanded = isExpanded || anyOtherMatches;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: lc.aiPurple,
                            ),
                          ),
                          const SizedBox(width: 5),
                          AnimatedRotation(
                            turns: showExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: MockupIcons.chevronDown(color: lc.aiPurple),
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
                          Divider(height: 1, color: lc.surfaceTrack),
                          for (final other in otherMembers)
                            _OtherMemberRow(
                              member: other,
                              isHighlighted: searchQuery.isNotEmpty &&
                                  (other.name
                                          ?.toLowerCase()
                                          .contains(searchQuery) ??
                                      false),
                              onTap: () => onMemberTap(other),
                            ),
                        ],
                      ),
                    ),
                    crossFadeState: showExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                    sizeCurve: Curves.easeOut,
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

/// Circular "+" on a household card header — opens add-member for that household.
class _HouseholdAddMemberButton extends StatelessWidget {
  const _HouseholdAddMemberButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: HouseholdDetailStrings.addMember,
      child: Material(
        color: AppColors.navy.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              Icons.add_rounded,
              size: 18,
              color: AppColors.navy,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in a household card's expanded "other members" panel — initials
/// avatar, name, relation + age/gender, phone, and the latest service tag
/// (or "Registered" when no visit history exists).
class _OtherMemberRow extends StatelessWidget {
  const _OtherMemberRow({
    required this.member,
    required this.onTap,
    this.isHighlighted = false,
  });

  final _HouseholdMember member;
  final VoidCallback onTap;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    final ageLabel = _MemberInfo.ageDisplayLabel(member.dateOfBirth);
    final genderInitial = (member.gender != null && member.gender!.isNotEmpty)
        ? member.gender![0].toUpperCase()
        : null;
    final ageGender = [
      if (ageLabel != null) ageLabel,
      if (genderInitial != null) genderInitial,
    ].join('/');
    final subtitle = [
      if (member.relation != null && member.relation!.isNotEmpty)
        member.relation,
      if (ageGender.isNotEmpty) ageGender,
    ].whereType<String>().join(' · ');
    final phone = member.phoneNumber?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;

    final deceased = !member.isActive;
    final serviceKind = member.recentService?.trim();
    final hasService = serviceKind != null && serviceKind.isNotEmpty;
    final tagLabel = deceased
        ? MemberDeceasedStrings.deceased
        : hasService
            ? ProgrammeLabels.forServiceKind(serviceKind)
            : HouseholdListStrings.enrolledTag;
    final serviceProgramme =
        hasService ? Programme.fromString(serviceKind) : null;
    final (badgeBg, badgeFg) = deceased
        ? (AppColors.progressTrack, AppColors.textMuted)
        : hasService &&
                serviceProgramme != null &&
                serviceProgramme != Programme.unknown
            ? programmeBadgeColors(serviceProgramme)
            : (lc.statusSuccessSurface, lc.statusSuccessAction);

    final row = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: lc.surfaceTrack,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                memberInitials(member.name),
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: lc.textMuted,
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
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isHighlighted ? FontWeight.w800 : FontWeight.w700,
                      color: deceased ? lc.textMuted : lc.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: lc.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (hasPhone)
                    Text(
                      phone,
                      style: AppTextStyles.worklistPhone.copyWith(
                        color: lc.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tagLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: badgeFg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return isHighlighted ? _SearchMatchHighlight(child: row) : row;
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
    this.recentService,
    this.isActive = true,
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
  final bool isActive;
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

  /// Most recent assessment `kind` / `serviceProvided` — shown on expanded
  /// "other member" rows when visit history exists.
  final String? recentService;

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
      isActive: json['isActive'] != false,
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
    String? recentService,
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
      isActive: e.isActive,
      householdId: e.householdId,
      villageId: e.villageId,
      subVillageId: e.subVillageId,
      subVillageName: e.subVillageName,
      programmes: programmes,
      ancVisitCount: ancVisitCount,
      pncVisitCount: pncVisitCount,
      recentService: recentService,
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
    this.ageLabel,
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
    this.recentService,
    this.isActive = true,
  });

  final String? id;
  final String? patientId;
  final String? name;
  final String? relation;
  final String? gender;
  final int? age;

  /// Compact UI label: `4m` under 24 months, otherwise whole years (`27`).
  final String? ageLabel;
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
  final String? recentService;
  final bool isActive;

  /// Whole years from DOB (0 for infants) — kept for navigation extras.
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
      return age < 0 ? 0 : age;
    } catch (_) {
      return null;
    }
  }

  /// Age for list chips. Infants show months (`4m`) / days (`12d`) so under-1
  /// members are not displayed as `0/F`.
  static String? ageDisplayLabel(String? dateOfBirth, {int? fallbackYears}) =>
      EnrollmentAge.compactChipLabel(
        dateOfBirth,
        fallbackYears: fallbackYears,
      );

  /// Create from _HouseholdMember and household context.
  factory _MemberInfo.fromServiceRow(ServiceMemberListRow row) {
    final m = row.member;
    return _MemberInfo(
      id: m.id,
      patientId: m.patientId,
      name: m.name,
      relation: m.relation,
      gender: m.gender,
      age: _calculateAge(m.dob),
      ageLabel: ageDisplayLabel(m.dob),
      dateOfBirth: m.dob,
      phoneNumber: m.phone,
      isPregnant: m.isPregnant,
      householdId: m.householdId,
      subVillageId: m.subVillageId,
      recentService: row.recentServiceKind,
      isActive: m.isActive,
    );
  }

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
      ageLabel: ageDisplayLabel(member.dateOfBirth),
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
      recentService: member.recentService,
      isActive: member.isActive,
    );
  }
}

/// Light blue tint wrapper for a member row that matches the current search query.
class _SearchMatchHighlight extends StatelessWidget {
  const _SearchMatchHighlight({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.statusWarning, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: child,
    );
  }
}

/// Dot + label status indicator matching the wireframe's `.v-status` element.
/// Palette is taken directly from the v14 prototype JS data object
/// (`statusColor` / `dotColor` per tier).
class _TierStatusPill extends StatelessWidget {
  const _TierStatusPill({required this.tier});
  final DashboardTier tier;

  static const _kTodayText    = Color(0xFF059669);
  static const _kTodayDot     = Color(0xFF10B981);
  static const _kOverdueText  = Color(0xFFDC2626);
  static const _kOverdueDot   = Color(0xFFEF4444);
  static const _kThisWeekText = Color(0xFFB45309);
  static const _kThisWeekDot  = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color textColor;
    final Color dotColor;
    if (tier == DashboardTier.critical || tier == DashboardTier.overdue) {
      label = MissionDashboardStrings.tierLabelOverdue;
      textColor = _kOverdueText;
      dotColor = _kOverdueDot;
    } else if (tier == DashboardTier.dueToday) {
      label = WorklistStrings.urgencyToday;
      textColor = _kTodayText;
      dotColor = _kTodayDot;
    } else if (tier == DashboardTier.thisWeek) {
      label = WorklistStrings.urgencyThisWeek;
      textColor = _kThisWeekText;
      dotColor = _kThisWeekDot;
    } else {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.worklistStatusPill.copyWith(color: textColor),
            ),
          ],
        ),
      ],
    );
  }
}
