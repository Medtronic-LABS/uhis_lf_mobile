import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/theme_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/local_dashboard_repository.dart';
import '../../core/db/member_dao.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/models/programme.dart';
import '../../core/widgets/location_filter_sheet.dart';
import '../referral/referral_repository.dart';
import '../search/global_search_bar.dart';
import '../visit/visit_controller.dart';
import '../visit/widgets/widgets.dart';
import 'dashboard_repository.dart';
import 'mission_dashboard_repository.dart';

enum _NeedFilter {
  highRisk,
  ancMnch,
  childImmunisation,
  ncd,
  eyeCare,
  missedFollowUp,
  pendingReferral,
}

/// AI Mission Dashboard — the operational command center for the SK.
///
/// Answers four questions within 5 seconds:
/// 1. Who needs attention today?
/// 2. Who is at highest risk?
/// 3. What work is pending?
/// 4. What should I do next?
///
/// Spec: AI Mission Dashboard (Screen 2).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  UserProfileSummary? _summary;
  String? _villagesLine;

  // Mission data futures consumed by the HTML dashboard composition.
  Future<List<MissionQueueItem>>? _queueFuture;
  Future<ReferralSummary>? _referralSummaryFuture;
  
  // Completed patient IDs (visited today) - these are excluded from the queue
  Set<String> _completedPatientIds = {};

  // Cached reference to mission repository for change listening.
  MissionDashboardRepository? _missionRepo;
  bool _missionListenerAdded = false;
  
  // Flag to track if data needs refresh when widget becomes visible.
  bool _pendingRefresh = false;

  // Version counter for forcing FutureBuilder rebuilds.
  int _refreshVersion = 0;

  // Location / SS filter state
  String? _selectedVillageId;
  String? _selectedSubVillageId;
  String? _selectedShebikaId;

  // Inline village chip + need filter
  List<String> _inlineVillages = const [];
  String? _selectedVillageChipName;
  Set<_NeedFilter> _selectedNeeds = const {};

  @override
  void initState() {
    super.initState();
    _reloadStats();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthState>();
      await _loadSummary(auth);
      await _loadVillagesLine();
      // Load mission data (may already be cached from sync screen)
      _loadMissionData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set up listener for mission data changes (e.g., after assessment completion).
    _missionRepo = context.read<MissionDashboardRepository>();
    if (!_missionListenerAdded) {
      _missionListenerAdded = true;
      _missionRepo!.changes.addListener(_onMissionChanges);
    }
  }

  @override
  void dispose() {
    _missionRepo?.changes.removeListener(_onMissionChanges);
    super.dispose();
  }

  /// Called when mission dashboard data changes (e.g., after assessment).
  void _onMissionChanges() {
    if (!mounted) return;
    debugPrint('[Dashboard] Mission data changed, reloading...');
    // Load new data immediately
    _loadMissionData();
    // If widget is not visible (e.g., user on Tasks tab), the setState might
    // not trigger an immediate rebuild. Set flag so build() can retry.
    _pendingRefresh = true;
  }
  
  /// Check if refresh is pending and trigger reload.
  /// Called from build() to ensure data is fresh when tab becomes visible.
  void _checkPendingRefresh() {
    if (_pendingRefresh && mounted) {
      debugPrint('[Dashboard] Tab became visible with pending refresh');
      _pendingRefresh = false;
      // The FutureBuilder key (using _refreshVersion) will force it to
      // re-subscribe to the current _queueFuture. No need to reload again
      // since _loadMissionData was already called in _onMissionChanges.
    }
  }

  /// Build the header sub-text from the SK's own cached households so the
  /// dashboard never falls back to the generic "Serving your community"
  /// string once data has landed. Empty-result paths leave [_villagesLine]
  /// null so the existing fallback continues to show.
  Future<void> _loadVillagesLine() async {
    if (!mounted) return;
    try {
      final hhDao = context.read<HouseholdDao>();
      final rows = await hhDao.getAll(limit: 50);
      final names = <String>{};
      for (final h in rows) {
        final v = h.village?.trim();
        if (v != null && v.isNotEmpty) names.add(v);
        if (names.length >= 3) break;
      }
      if (!mounted) return;
      if (names.isEmpty) return;
      final ordered = names.toList(growable: false);
      final shown = ordered.take(2).join(' · ');
      final remaining = ordered.length > 2 ? ordered.length - 2 : 0;
      setState(() {
        _villagesLine = remaining > 0 ? '$shown · +$remaining more' : shown;
      });
    } on Object catch (e) {
      debugPrint('[Dashboard] villages line failed: $e');
    }
  }

  Future<void> _loadSummary(AuthState auth) async {
    if (!mounted) return;
    final s = await auth.userProfileSummary();
    if (!mounted) return;
    setState(() => _summary = s);
  }

  void _reloadStats() {
    // Local-first household count cache for the auth repo.
    final localRepo = context.read<LocalDashboardRepository>();
    final apiRepo = context.read<DashboardRepository>();
    final authRepo = context.read<AuthRepository>();

    localRepo.householdAndMemberCount().then((local) async {
      final counts = local.households > 0
          ? local
          : await apiRepo.householdAndMemberCount();
      try {
        await authRepo.cacheHouseholdCount(counts.households);
      } catch (_) {}
    });
  }

  void _loadMissionData() {
    if (!mounted) return;
    // Provider registers MissionDashboardRepository as non-nullable; reading
    // `T?` would silently return null on miss and strand the screen on its
    // empty state.
    final missionRepo = context.read<MissionDashboardRepository>();
    final encounterDao = context.read<EncounterDao>();
    
    setState(() {
      // Increment version to force FutureBuilder rebuild
      _refreshVersion++;
      debugPrint('[Dashboard] Loading mission data, version=$_refreshVersion');
      // Load completed patient IDs and filter queue to exclude them
      _queueFuture = _loadFilteredQueue(missionRepo, encounterDao);
      _referralSummaryFuture = missionRepo.loadReferralSummary();
    });
  }
  
  /// Load the mission queue excluding patients who have been visited today,
  /// then apply any active location filter.
  Future<List<MissionQueueItem>> _loadFilteredQueue(
    MissionDashboardRepository missionRepo,
    EncounterDao encounterDao,
  ) async {
    // Load completed patient IDs first
    final completedIds = await encounterDao.completedTodayPatientIds();
    if (mounted) {
      setState(() => _completedPatientIds = completedIds);
    }

    // Load full queue
    final queue = await missionRepo.loadQueue(limit: 500);

    // Filter out completed patients
    final withoutCompleted = queue.where((item) =>
      item.patientId == null || !completedIds.contains(item.patientId)
    ).toList();

    // Apply location filter
    // ignore: use_build_context_synchronously
    if (!mounted) return withoutCompleted;
    // ignore: use_build_context_synchronously
    final locationFiltered = await _applyLocationFilter(withoutCompleted, context);

    // Extract distinct village labels for inline chips (from un-completed queue)
    final allVillageLabels = withoutCompleted
        .map((i) => i.village?.trim())
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (mounted) {
      // ignore: use_build_context_synchronously
      setState(() => _inlineVillages = allVillageLabels);
    }

    // Apply inline village chip filter
    var result = locationFiltered;
    final chipVillage = _selectedVillageChipName;
    if (chipVillage != null) {
      result = result.where((i) => i.village?.trim() == chipVillage).toList();
    }

    // Apply need filter (OR logic — item matches if it satisfies any selected need)
    if (_selectedNeeds.isNotEmpty) {
      result = result.where(_needMatches).toList();
    }

    return result;
  }

  Future<void> _refresh() async {
    final missionRepo = context.read<MissionDashboardRepository>();
    await missionRepo.refresh();
    _reloadStats();
    _loadMissionData();
  }

  /// Called from menu when user wants to enable device unlock.
  Future<void> _offerBiometric() async {
    final auth = context.read<AuthState>();
    if (auth.biometricEnabled) return;
    if (!mounted) return;
    final supported = auth.biometricAvailable;
    final ans = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(DashboardStrings.useDeviceUnlockTitle),
        content: Text(
          supported
              ? DashboardStrings.biometricOfferSupported
              : DashboardStrings.biometricOfferUnsupported,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(DashboardStrings.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(DashboardStrings.enable),
          ),
        ],
      ),
    );
    if (ans != true || !mounted) return;
    if (!supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(DashboardStrings.setUpScreenLock),
        ),
      );
      return;
    }
    try {
      final auth = context.read<AuthState>();
      await auth.enrolBiometric();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(DashboardStrings.deviceUnlockEnabled)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DashboardStrings.couldNotEnable(e))),
      );
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? DashboardStrings.goodMorning
        : (hour < 17
            ? DashboardStrings.goodAfternoon
            : DashboardStrings.goodEvening);
    final first = _summary?.firstName?.trim();
    if (first != null && first.isNotEmpty) {
      return DashboardStrings.greetingNamed(part, first);
    }
    final fallback = context.read<AuthState>().username;
    if (fallback == null || fallback.isEmpty) return part;
    final stub = fallback.split('.').first.split('@').first;
    final cap = stub.isEmpty
        ? ''
        : '${stub[0].toUpperCase()}${stub.substring(1)}';
    return DashboardStrings.greetingNamed(part, cap);
  }

  String? _locationLine() {
    final s = _summary;
    if (s != null) {
      final ward = s.ward;
      final upazila = s.upazila ?? s.area;
      if (ward != null && upazila != null) return '$ward · $upazila';
      if (ward != null) return ward;
      if (upazila != null) return upazila;
    }
    // Profile carries no ward / upazila (uhis-dev SKs are assigned via
    // sub-villages only) — fall back to the village names we already
    // synced into HouseholdDao so the header isn't stuck on the generic
    // "Serving your community" placeholder.
    return _villagesLine;
  }

  /// Begin a visit directly from the dashboard card. Matches the HTML
  /// prototype's "Visit now" — single tap drops the SK into triage.
  /// Falls back to opening the patient detail when the visit can't start.
  Future<void> _startVisitFromQueue(MissionQueueItem item) async {
    final patientId = item.patientId;
    if (patientId == null || patientId.isEmpty) {
      if (item.referralId != null) {
        context.push('/referral/${item.referralId}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(MissionDashboardStrings.visitMissingPatient),
          ),
        );
      }
      return;
    }
    final controller = context.read<VisitController>();
    final encounterId = await controller.startVisit(
      patientId: patientId,
      programme: item.primaryProgramme,
      patientName: item.patientName,
      patientAge: item.age,
      householdId: item.householdId,
    );
    if (!mounted) return;
    if (encounterId != null) {
      debugPrint('[Dashboard] Starting visit, navigating with origin=dashboard');
      context.go(
        '/patients/visit/$encounterId/triage?origin=dashboard',
        extra: {
          'patientId': patientId,
          'householdId': item.householdId,
          'patientAge': item.age,
        },
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.error ?? MissionDashboardStrings.visitStartFailed,
        ),
      ),
    );
  }

  void _navigateToFirstQueueItem() async {
    // Navigate to Tasks screen (Visits tab)
    if (mounted) context.push('/tasks');
  }

  /// Resolved display label for the most-specific active filter, or null.
  /// Priority: sub-village > SS > village.
  String? _activeFilterLabel() {
    final hierarchy = context.read<UserHierarchyService>();
    if (_selectedSubVillageId != null) {
      return hierarchy.subVillages
              ?.where((sv) => sv.id == _selectedSubVillageId)
              .firstOrNull
              ?.name ??
          _selectedSubVillageId;
    }
    if (_selectedShebikaId != null) {
      return hierarchy.ssWorkers
              ?.where((ss) => ss.id == _selectedShebikaId)
              .firstOrNull
              ?.name ??
          _selectedShebikaId;
    }
    if (_selectedVillageId != null) {
      return hierarchy.villages
              ?.where((v) => v.id == _selectedVillageId)
              .firstOrNull
              ?.name ??
          _selectedVillageId;
    }
    return null;
  }

  bool _needMatches(MissionQueueItem item) {
    final needs = _selectedNeeds;
    if (needs.isEmpty) return true;
    for (final need in needs) {
      switch (need) {
        case _NeedFilter.highRisk:
          if (item.priority == MissionPriority.critical ||
              item.priority == MissionPriority.high) { return true; }
        case _NeedFilter.ancMnch:
          if (item.programmes.contains(Programme.anc) ||
              item.programmes.contains(Programme.pnc)) { return true; }
        case _NeedFilter.childImmunisation:
          if (item.programmes.contains(Programme.imci) ||
              item.programmes.contains(Programme.epi)) { return true; }
        case _NeedFilter.ncd:
          if (item.programmes.contains(Programme.ncd)) { return true; }
        case _NeedFilter.eyeCare:
          if (item.programmes.contains(Programme.cataract) ||
              item.programmes.contains(Programme.eyeCare)) { return true; }
        case _NeedFilter.missedFollowUp:
          if (item.daysOverdue != null && item.daysOverdue! > 0) { return true; }
        case _NeedFilter.pendingReferral:
          if (item.referralId != null) { return true; }
      }
    }
    return false;
  }

  void _clearAllFilters() {
    setState(() {
      _selectedVillageId = null;
      _selectedSubVillageId = null;
      _selectedShebikaId = null;
    });
    _loadMissionData();
  }

  /// Opens the location/SS filter bottom sheet backed by the API hierarchy.
  Future<void> _openFilterSheet() async {
    final hierarchySvc = context.read<UserHierarchyService>();
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
          _loadMissionData();
        },
      ),
    );
  }

  /// Applies the active location filter to a list of [MissionQueueItem].
  /// Returns the original list unchanged when no filter is active.
  Future<List<MissionQueueItem>> _applyLocationFilter(
    List<MissionQueueItem> items,
    BuildContext context,
  ) async {
    if (_selectedVillageId == null &&
        _selectedSubVillageId == null &&
        _selectedShebikaId == null) {
      return items;
    }

    // Resolve SS → sub-village IDs before any async gap.
    List<String>? ssSubVillageIds;
    if (_selectedShebikaId != null) {
      final hierarchySvc = context.read<UserHierarchyService>();
      final ss = (hierarchySvc.ssWorkers ?? const [])
          .where((s) => s.id == _selectedShebikaId)
          .firstOrNull;
      if (ss != null && ss.subVillages.isNotEmpty) {
        ssSubVillageIds = ss.subVillages.map((sv) => sv.id).toList();
      }
    }

    // Village filter on queue items directly (item.village = villageId after sync fix).
    var filtered = items;
    if (_selectedVillageId != null) {
      filtered = filtered
          .where((i) => i.village == _selectedVillageId)
          .toList();
    }

    // Sub-village / SS filter via members table.
    final subVillageIds = ssSubVillageIds ??
        (_selectedSubVillageId != null ? [_selectedSubVillageId!] : null);
    if (subVillageIds != null) {
      final memberDao = context.read<MemberDao>();
      final matchingIds =
          await memberDao.getPatientIdsBySubVillages(subVillageIds);
      filtered = filtered
          .where((i) =>
              i.patientId != null && matchingIds.contains(i.patientId))
          .toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    // Check if a refresh is pending (e.g., assessment completed while on another tab)
    _checkPendingRefresh();
    
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _DashboardHeader(
              greeting: _greeting(),
              locationLine: _locationLine(),
              onNotifications: () => context.push('/referrals'),
              settingsMenu: _SettingsMenu(onOfferBiometric: _offerBiometric),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                  children: [
                    _DashboardStatsRow(
                      key: ValueKey('stats_$_refreshVersion'),
                      queueFuture: _queueFuture,
                      referralFuture: _referralSummaryFuture,
                      onTapVisits: _navigateToFirstQueueItem,
                      onTapReferrals: () => context.push('/referrals'),
                    ),
                    const SizedBox(height: 14),
                    _VisitFilterPanel(
                      villages: _inlineVillages,
                      selectedVillage: _selectedVillageChipName,
                      onVillageSelected: (name) {
                        setState(() => _selectedVillageChipName = name);
                        _loadMissionData();
                      },
                      selectedNeeds: _selectedNeeds,
                      onNeedToggled: (need) {
                        setState(() {
                          final updated = Set<_NeedFilter>.from(_selectedNeeds);
                          if (updated.contains(need)) {
                            updated.remove(need);
                          } else {
                            updated.add(need);
                          }
                          _selectedNeeds = updated;
                        });
                        _loadMissionData();
                      },
                      onClearNeeds: () {
                        setState(() => _selectedNeeds = const {});
                        _loadMissionData();
                      },
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<List<MissionQueueItem>>(
                      key: ValueKey('queue_$_refreshVersion'),
                      future: _queueFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TodaysVisitsHeader(
                                onFilter: _openFilterSheet,
                                activeFilterLabel: _activeFilterLabel(),
                                onClearFilter: _clearAllFilters,
                              ),
                              const SizedBox(height: 8),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              ),
                            ],
                          );
                        }
                        final queue = snap.data ?? const [];
                        if (queue.isEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TodaysVisitsHeader(
                                onFilter: _openFilterSheet,
                                activeFilterLabel: _activeFilterLabel(),
                                onClearFilter: _clearAllFilters,
                              ),
                              const SizedBox(height: 8),
                              _EmptyVisitsCard(),
                            ],
                          );
                        }
                        // 5-tier model: top 8 cards genuinely *mixed* across
                        // tiers per spec
                        // (leapfrog-setup/designs/dashboard-prioritization.md).
                        // Pure rank-ASC sort lets the top tier hog all 8 slots
                        // when ≥8 patients exist there, so the SK never sees
                        // the per-tier CTA variety (Visit today / Plan visit /
                        // Schedule). Round-robin: guarantee 1 slot per
                        // non-empty tier in rank order, then top up the
                        // remainder rank-ASC while capping any single tier at
                        // [maxPerTier].
                        const visibleLimit = 8;
                        const minPerTier = 1;
                        const maxPerTier = 3;

                        final byTier =
                            <DashboardTier, List<MissionQueueItem>>{};
                        for (final item in queue) {
                          (byTier[item.tier] ??= <MissionQueueItem>[])
                              .add(item);
                        }

                        final visible = <MissionQueueItem>[];
                        final perTierUsed = <DashboardTier, int>{
                          for (final t in DashboardTier.values) t: 0,
                        };

                        // Pass 1 — guarantee [minPerTier] per non-empty tier,
                        // walking tiers in rank order.
                        for (final t in DashboardTier.values) {
                          final list = byTier[t] ?? const <MissionQueueItem>[];
                          for (var i = 0;
                              i < list.length && i < minPerTier;
                              i++) {
                            if (visible.length >= visibleLimit) break;
                            visible.add(list[i]);
                            perTierUsed[t] = (perTierUsed[t] ?? 0) + 1;
                          }
                          if (visible.length >= visibleLimit) break;
                        }

                        // Pass 2 — fill remaining slots rank-ASC, capped at
                        // [maxPerTier] per tier so urgency variety stays
                        // visible.
                        for (final t in DashboardTier.values) {
                          final list = byTier[t] ?? const <MissionQueueItem>[];
                          while (visible.length < visibleLimit &&
                              (perTierUsed[t] ?? 0) < maxPerTier &&
                              (perTierUsed[t] ?? 0) < list.length) {
                            visible.add(list[perTierUsed[t]!]);
                            perTierUsed[t] = (perTierUsed[t] ?? 0) + 1;
                          }
                          if (visible.length >= visibleLimit) break;
                        }

                        // Restore tier-rank ordering for inline tier-header
                        // rendering. Within-tier order stays composite-DESC.
                        visible.sort((a, b) {
                          final c = a.tier.rank.compareTo(b.tier.rank);
                          if (c != 0) return c;
                          return MissionQueueItem.compareInTier(a, b);
                        });

                        final overflow = queue.length - visible.length;
                        // Overflow's dominant tier = first remaining item
                        // (queue is rank-ASC sorted upstream).
                        DashboardTier? overflowTier;
                        if (overflow > 0) {
                          final visibleSet = visible.toSet();
                          for (final q in queue) {
                            if (!visibleSet.contains(q)) {
                              overflowTier = q.tier;
                              break;
                            }
                          }
                        }

                        // Build widgets with inline tier headers
                        final widgets = <Widget>[];
                        DashboardTier? currentTier;
                        final tierCounts = <DashboardTier, int>{};
                        for (final item in visible) {
                          tierCounts[item.tier] =
                              (tierCounts[item.tier] ?? 0) + 1;
                        }
                        for (final item in visible) {
                          if (item.tier != currentTier) {
                            currentTier = item.tier;
                            widgets.add(Padding(
                              padding: EdgeInsets.only(
                                top: widgets.isEmpty ? 0 : 10,
                                bottom: 6,
                              ),
                              child: MissionTierHeader(
                                tier: currentTier,
                                count: tierCounts[currentTier] ?? 0,
                                compact: true,
                              ),
                            ));
                          }
                          widgets.add(Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MissionQueueCard(
                              item: item,
                              compact: true,
                              onTap: () {
                                final pid = item.patientId;
                                if (pid != null && pid.isNotEmpty &&
                                    pid != 'household' && pid != 'households') {
                                  context.push('/patient/$pid?origin=dashboard');
                                } else if (item.referralId != null) {
                                  context.push('/referral/${item.referralId}');
                                }
                              },
                              onAction: () => _startVisitFromQueue(item),
                            ),
                          ));
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TodaysVisitsHeader(
                                onFilter: _openFilterSheet,
                                activeFilterLabel: _activeFilterLabel(),
                                onClearFilter: _clearAllFilters,
                              ),
                            const SizedBox(height: 8),
                            ...widgets,
                            if (overflow > 0)
                              _MoreVisitsLink(
                                count: overflow,
                                tier: overflowTier,
                                onTap: () {
                                  // Deep-link to /patients with the dominant
                                  // overflow tier preselected as the filter
                                  // chip. Router parses `?tier=` into
                                  // `HouseholdListScreen.initialTier`.
                                  final route = overflowTier == null
                                      ? '/patients'
                                      : '/patients?tier=${overflowTier.name}';
                                  context.go(route);
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


}

/// Settings popup menu in the app bar.
class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.onOfferBiometric});

  final VoidCallback onOfferBiometric;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthState>(
      builder: (ctx, auth, _) => PopupMenuButton<String>(
        icon: const Icon(Icons.settings),
        onSelected: (v) async {
          switch (v) {
            case 'enable_bio':
              onOfferBiometric();
              break;
            case 'disable_bio':
              final confirmBio = await showDialog<bool>(
                context: ctx,
                builder: (dlgCtx) => AlertDialog(
                  title: const Text(DashboardStrings.confirmDisableDeviceUnlock),
                  content: const Text(DashboardStrings.confirmDisableDeviceUnlockBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(false),
                      child: const Text(DashboardStrings.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(true),
                      child: const Text(DashboardStrings.disable),
                    ),
                  ],
                ),
              );
              if (confirmBio != true) break;
              await auth.disableBiometric();
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text(DashboardStrings.deviceUnlockDisabled)),
                );
              }
              break;
            case 'set_pin':
              ctx.go('/pin-setup');
              break;
            case 'remove_pin':
              final confirmPin = await showDialog<bool>(
                context: ctx,
                builder: (dlgCtx) => AlertDialog(
                  title: const Text(PinStrings.confirmRemovePin),
                  content: const Text(PinStrings.confirmRemovePinBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(false),
                      child: const Text(DashboardStrings.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(true),
                      child: const Text(CommonStrings.remove),
                    ),
                  ],
                ),
              );
              if (confirmPin != true) break;
              await auth.disablePin();
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text(PinStrings.disabledSnack)),
                );
              }
              break;
            case 'toggle_dark':
              final theme = ctx.read<ThemeProvider>();
              await theme.toggleDarkMode();
              break;
            case 'logout':
              final confirmLogout = await showDialog<bool>(
                context: ctx,
                builder: (dlgCtx) => AlertDialog(
                  title: const Text(DashboardStrings.confirmSignOut),
                  content: const Text(DashboardStrings.confirmSignOutBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(false),
                      child: const Text(DashboardStrings.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(true),
                      child: const Text(DashboardStrings.signOut),
                    ),
                  ],
                ),
              );
              if (confirmLogout != true) break;
              await auth.logout();
              if (ctx.mounted) ctx.go('/login');
              break;
          }
        },
        itemBuilder: (_) => [
          if (!auth.biometricEnabled)
            const PopupMenuItem(
              value: 'enable_bio',
              child: ListTile(
                leading: Icon(Icons.fingerprint),
                title: Text(DashboardStrings.enableDeviceUnlock),
              ),
            ),
          if (auth.biometricEnabled)
            const PopupMenuItem(
              value: 'disable_bio',
              child: ListTile(
                leading: Icon(Icons.fingerprint_outlined),
                title: Text(DashboardStrings.disableDeviceUnlock),
              ),
            ),
          if (!auth.pinEnabled)
            const PopupMenuItem(
              value: 'set_pin',
              child: ListTile(
                leading: Icon(Icons.pin_outlined),
                title: Text(PinStrings.enablePin),
              ),
            ),
          if (auth.pinEnabled)
            const PopupMenuItem(
              value: 'remove_pin',
              child: ListTile(
                leading: Icon(Icons.pin_outlined),
                title: Text(PinStrings.disablePin),
              ),
            ),
          PopupMenuItem(
            value: 'toggle_dark',
            child: Consumer<ThemeProvider>(
              builder: (_, theme, __) => ListTile(
                leading: Icon(
                  theme.isDark ? Icons.light_mode : Icons.dark_mode,
                ),
                title: Text(
                  theme.isDark
                      ? SettingsStrings.lightMode
                      : SettingsStrings.darkMode,
                ),
              ),
            ),
          ),
          const PopupMenuItem(
            value: 'logout',
            child: ListTile(
              leading: Icon(Icons.logout),
              title: Text(DashboardStrings.signOut),
            ),
          ),
        ],
      ),
    );
  }
}

/// Notification bell button for referrals in the AppBar.
class _ReferralNotificationButton extends StatefulWidget {
  const _ReferralNotificationButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ReferralNotificationButton> createState() =>
      _ReferralNotificationButtonState();
}

class _ReferralNotificationButtonState
    extends State<_ReferralNotificationButton> {
  Future<({int critical, int active})>? _future;
  ReferralRepository? _repo;
  bool _listenerAdded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = context.read<ReferralRepository>();
    if (!_listenerAdded) {
      _listenerAdded = true;
      _future = _repo!.counts();
      _repo!.changes.addListener(_onChanges);
    }
  }

  @override
  void dispose() {
    _repo?.changes.removeListener(_onChanges);
    super.dispose();
  }

  void _onChanges() {
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    final repo = _repo;
    if (repo == null) return;
    final future = repo.counts();
    setState(() {
      _future = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<({int critical, int active})>(
      future: _future,
      builder: (context, snap) {
        final critical = snap.data?.critical ?? 0;
        final active = snap.data?.active ?? 0;
        final total = critical + active;
        final hasUrgent = critical > 0;
        return IconButton(
          tooltip: ReferralStrings.dashboardTitle,
          onPressed: widget.onTap,
          icon: Badge(
            isLabelVisible: total > 0,
            offset: const Offset(2, -2),
            label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                total > 99 ? '99+' : total.toString(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            backgroundColor: hasUrgent ? scheme.error : scheme.primary,
            child: Icon(
              hasUrgent
                  ? Icons.notification_important
                  : Icons.notifications_outlined,
              color: hasUrgent ? scheme.error : null,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HTML-composition widgets
// Match `Leapfrog .html` dashboard: navy header, AI ribbon, two-stat row,
// "Today's visits" priority-ordered patient cards with colored left border.
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.greeting,
    required this.locationLine,
    required this.onNotifications,
    required this.settingsMenu,
  });

  final String greeting;
  final String? locationLine;
  final VoidCallback onNotifications;
  final Widget settingsMenu;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      color: tokens.brandNavy,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: Colors.white70),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            locationLine ??
                                DashboardStrings.communityAtAGlance,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _ReferralNotificationButton(onTap: onNotifications),
              settingsMenu,
            ],
          ),
          const SizedBox(height: 10),
          // Search bar with QR-scan affordance
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              borderRadius:
                  BorderRadius.circular(LeapfrogColors.radiusMd),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: GlobalSearchBar(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStatsRow extends StatelessWidget {
  const _DashboardStatsRow({
    super.key,
    required this.queueFuture,
    required this.referralFuture,
    required this.onTapVisits,
    required this.onTapReferrals,
  });

  final Future<List<MissionQueueItem>>? queueFuture;
  final Future<ReferralSummary>? referralFuture;
  final VoidCallback onTapVisits;
  final VoidCallback onTapReferrals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FutureBuilder<List<MissionQueueItem>>(
            future: queueFuture,
            builder: (context, snap) {
              final isLoading = snap.connectionState == ConnectionState.waiting;
              final queue = snap.data ?? const <MissionQueueItem>[];
              final count = queue.length;
              final villageCount = queue
                  .map((i) => i.village)
                  .whereType<String>()
                  .where((v) => v.trim().isNotEmpty)
                  .toSet()
                  .length;
              return _DashboardStatCard(
                value: '$count',
                label: MissionDashboardStrings.visitsToday,
                accentVariant: _DashboardStatVariant.navy,
                subline: isLoading
                    ? 'Loading...'
                    : MissionDashboardStrings.visitsTodaySubline(villageCount),
                onTap: onTapVisits,
                isLoading: isLoading,
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FutureBuilder<ReferralSummary>(
            future: referralFuture,
            builder: (context, snap) {
              final isLoading = snap.connectionState == ConnectionState.waiting;
              final s = snap.data ?? ReferralSummary.empty;
              final alerts = s.breached + s.awaitingReview;
              return _DashboardStatCard(
                value: '$alerts',
                label: MissionDashboardStrings.referralAlertsLabel,
                accentVariant: _DashboardStatVariant.pink,
                subline: isLoading
                    ? 'Loading...'
                    : MissionDashboardStrings.tapToFollowUp,
                footnote: MissionDashboardStrings.referralCceComingSoon,
                showPulse: s.hasBreaches,
                onTap: onTapReferrals,
                isLoading: isLoading,
              );
            },
          ),
        ),
      ],
    );
  }
}

enum _DashboardStatVariant { navy, pink }

class _DashboardStatCard extends StatelessWidget {
  const _DashboardStatCard({
    required this.value,
    required this.label,
    required this.accentVariant,
    required this.subline,
    required this.onTap,
    this.footnote,
    this.showPulse = false,
    this.isLoading = false,
  });

  final String value;
  final String label;
  final _DashboardStatVariant accentVariant;
  final String subline;
  final String? footnote;
  final bool showPulse;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final accent = accentVariant == _DashboardStatVariant.pink
        ? tokens.brandPink
        : tokens.brandNavy;
    return Material(
      color: tokens.cardSurface,
      borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: accent,
                      ),
                    )
                  else
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: accent,
                        height: 1,
                      ),
                    ),
                  if (showPulse && !isLoading) ...[
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subline,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              if (footnote != null) ...[
                const SizedBox(height: 3),
                Text(
                  footnote!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TodaysVisitsHeader extends StatelessWidget {
  const _TodaysVisitsHeader({
    required this.onFilter,
    this.activeFilterLabel,
    this.onClearFilter,
  });

  final VoidCallback onFilter;

  /// Resolved display label when a filter is active (e.g. "Dinajpur").
  /// Null when no filter is selected — shows the placeholder chip instead.
  final String? activeFilterLabel;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final scheme = Theme.of(context).colorScheme;
    final dateLabel = DateFormat('EEE d MMM').format(DateTime.now());
    final isFiltered = activeFilterLabel != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              MissionDashboardStrings.todaysVisits(dateLabel),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: tokens.brandNavy,
              ),
            ),
          ),
          if (isFiltered)
            InputChip(
              label: Text(activeFilterLabel!,
                  style: const TextStyle(fontSize: 11)),
              onDeleted: onClearFilter,
              onPressed: onFilter,
              deleteIconColor: scheme.onSecondaryContainer,
              backgroundColor: scheme.secondaryContainer,
              labelStyle: TextStyle(color: scheme.onSecondaryContainer),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )
          else
            ActionChip(
              avatar: Icon(Icons.filter_list_rounded,
                  size: 14, color: scheme.onSurfaceVariant),
              label: Text(MissionDashboardStrings.filterByLocation,
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant)),
              onPressed: onFilter,
              backgroundColor: scheme.surfaceContainerHighest,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// Tail link beneath the priority visit list — matches the prototype's
/// "+ N more visits today" affordance and deep-links into the full worklist
/// pre-filtered by the dominant overflow tier.
class _MoreVisitsLink extends StatelessWidget {
  const _MoreVisitsLink({
    required this.count,
    required this.onTap,
    this.tier,
  });

  final int count;
  final DashboardTier? tier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          alignment: Alignment.center,
          child: Text(
            MissionDashboardStrings.moreVisits(count),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tokens.brandNavy,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyVisitsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline,
              size: 40, color: tokens.statusSuccess),
          const SizedBox(height: 8),
          Text(
            MissionDashboardStrings.noMissionsToday,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            MissionDashboardStrings.allCaughtUp,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-row inline filter panel for the dashboard visit list.
///
/// Row 1 — village chips (single-select, from queue items)
/// Row 2 — need chips (multi-select, programme/priority-based)
class _VisitFilterPanel extends StatelessWidget {
  const _VisitFilterPanel({
    required this.villages,
    required this.selectedVillage,
    required this.onVillageSelected,
    required this.selectedNeeds,
    required this.onNeedToggled,
    required this.onClearNeeds,
  });

  final List<String> villages;
  final String? selectedVillage;
  final void Function(String? name) onVillageSelected;
  final Set<_NeedFilter> selectedNeeds;
  final void Function(_NeedFilter need) onNeedToggled;
  final VoidCallback onClearNeeds;

  static const _pinkColor = Color(0xFFE8356D);
  static const _pinkActiveBg = Color(0xFFFDF2F8);
  static const _pinkActiveText = Color(0xFF9D174D);

  String _needLabel(_NeedFilter need) {
    switch (need) {
      case _NeedFilter.highRisk:
        return MissionDashboardStrings.needHighRisk;
      case _NeedFilter.ancMnch:
        return MissionDashboardStrings.needAncMnch;
      case _NeedFilter.childImmunisation:
        return MissionDashboardStrings.needChildImmunisation;
      case _NeedFilter.ncd:
        return MissionDashboardStrings.needNcd;
      case _NeedFilter.eyeCare:
        return MissionDashboardStrings.needEyeCare;
      case _NeedFilter.missedFollowUp:
        return MissionDashboardStrings.needMissedFollowUp;
      case _NeedFilter.pendingReferral:
        return MissionDashboardStrings.needPendingReferral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: village chips ──────────────────────────────────────────
          if (villages.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                MissionDashboardStrings.whichVillageVisiting,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
            ),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _VillageChip(
                    label: MissionDashboardStrings.allVillages,
                    isActive: selectedVillage == null,
                    onTap: () => onVillageSelected(null),
                  ),
                  ...villages.map((v) => _VillageChip(
                    label: v,
                    isActive: selectedVillage == v,
                    onTap: () => onVillageSelected(selectedVillage == v ? null : v),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: const Color(0xFFE5E7EB)),
            const SizedBox(height: 8),
          ],

          // ── Row 2: need chips ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                const Text(
                  MissionDashboardStrings.filterByNeed,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${MissionDashboardStrings.filterByNeedOptional})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const Spacer(),
                if (selectedNeeds.isNotEmpty)
                  GestureDetector(
                    onTap: onClearNeeds,
                    child: const Text(
                      MissionDashboardStrings.clearNeedFilters,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _pinkColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _NeedFilter.values.map((need) {
                final active = selectedNeeds.contains(need);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => onNeedToggled(need),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? _pinkActiveBg : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? _pinkColor
                              : const Color(0xFFD1D5DB),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _needLabel(need),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w500,
                          color: active
                              ? _pinkActiveText
                              : const Color(0xFF374151),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _VillageChip extends StatelessWidget {
  const _VillageChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  static const _navyColor = Color(0xFF1B2B5E);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? _navyColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? _navyColor : const Color(0xFFD1D5DB),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}
