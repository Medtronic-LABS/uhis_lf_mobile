import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/theme_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/local_dashboard_repository.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/models/programme.dart';
import '../referral/referral_repository.dart';
import '../search/global_search_bar.dart';
import '../visit/visit_controller.dart';
import '../visit/widgets/widgets.dart';
import 'dashboard_repository.dart';
import 'sk_performance_screen.dart';
import 'mission_dashboard_repository.dart';
import '../household/enrollment/enrollment_entry_sheet.dart';

enum _NeedFilter {
  highRisk,
  ancMnch,
  childImmunisation,
  ncd,
  eyeCare,
  missedFollowUp,
  pendingReferral,
  homeVisit,
  facilityReferral,
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
  

  // Cached reference to mission repository for change listening.
  MissionDashboardRepository? _missionRepo;
  bool _missionListenerAdded = false;
  
  // Flag to track if data needs refresh when widget becomes visible.
  bool _pendingRefresh = false;

  // Version counter for forcing FutureBuilder rebuilds.
  int _refreshVersion = 0;

  // Inline village chip + need filter
  List<String> _inlineVillages = const [];
  String? _selectedVillageChipName;
  Set<_NeedFilter> _selectedNeeds = const {};
  Set<_NeedFilter> _availableNeeds = const {};
  Set<Programme> _selectedProgrammes = const {};
  List<Programme> _availableProgrammes = const [];

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

    // Load full queue
    final queue = await missionRepo.loadQueue(limit: 500);

    // Filter out completed patients
    final withoutCompleted = queue.where((item) =>
      item.patientId == null || !completedIds.contains(item.patientId)
    ).toList();

    // Extract distinct village labels for inline chips (from un-completed queue)
    final allVillageLabels = withoutCompleted
        .map((i) => i.village?.trim())
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Derive available programmes from the queue (for dynamic programme chips).
    // PILOT-SCOPE v1: only pilot programmes shown as filter chips.
    // To restore all programmes: remove the `.where((p) => p.isPilot)` filter.
    final allProgrammes = withoutCompleted
        .expand((i) => i.programmes)
        .where((p) => p != Programme.unknown && p.isPilot)
        .toSet()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final availableNeeds = _computeAvailableNeeds(withoutCompleted);
    if (mounted) {
      // ignore: use_build_context_synchronously
      setState(() {
        _inlineVillages = allVillageLabels;
        _availableProgrammes = allProgrammes;
        _availableNeeds = availableNeeds;
      });
    }

    // Apply inline village chip filter
    var result = withoutCompleted;
    final chipVillage = _selectedVillageChipName;
    if (chipVillage != null) {
      result = result.where((i) => i.village?.trim() == chipVillage).toList();
    }

    // Apply programme filter (OR logic — item shown if it has any selected programme)
    if (_selectedProgrammes.isNotEmpty) {
      result = result
          .where((i) => i.programmes.any(_selectedProgrammes.contains))
          .toList();
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
    // refresh() fires _changes once → _onMissionChanges() → _loadMissionData().
    // No explicit call here; that would double-load.
    _reloadStats();
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
        '/patients/visit/$encounterId/flow?origin=dashboard',
        extra: {
          'patientId': patientId,
          'patientName': item.patientName,
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

  Set<_NeedFilter> _computeAvailableNeeds(List<MissionQueueItem> items) {
    final available = <_NeedFilter>{};
    for (final item in items) {
      if (item.priority == MissionPriority.critical ||
          item.priority == MissionPriority.high) {
        available.add(_NeedFilter.highRisk);
      }
      if (item.programmes.any((p) => p == Programme.anc || p == Programme.pnc)) {
        available.add(_NeedFilter.ancMnch);
      }
      // PILOT-SCOPE v1: child chip matches imci only (epi not in pilot).
      // To restore epi: change to `p == Programme.imci || p == Programme.epi`.
      if (item.programmes.contains(Programme.imci)) {
        available.add(_NeedFilter.childImmunisation);
      }
      if (item.programmes.contains(Programme.ncd)) {
        available.add(_NeedFilter.ncd);
      }
      // PILOT-SCOPE v1: eyeCare/cataract chip disabled (not in pilot).
      // To restore: un-comment the block below.
      // if (item.programmes.any((p) => p == Programme.eyeCare || p == Programme.cataract)) {
      //   available.add(_NeedFilter.eyeCare);
      // }
      if (item.daysOverdue != null && item.daysOverdue! > 0) {
        available.add(_NeedFilter.missedFollowUp);
      }
      if (item.referralId != null) {
        available.add(_NeedFilter.pendingReferral);
      }
      if (item.type == MissionItemType.patientVisit ||
          item.type == MissionItemType.householdOpportunity) {
        available.add(_NeedFilter.homeVisit);
      }
      if (item.type == MissionItemType.referral || item.referralId != null) {
        available.add(_NeedFilter.facilityReferral);
      }
    }
    return available;
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
          if (item.programmes.any((p) => p == Programme.anc || p == Programme.pnc)) { return true; }
        case _NeedFilter.childImmunisation:
          // PILOT-SCOPE v1: imci only (epi not in pilot).
          if (item.programmes.contains(Programme.imci)) { return true; }
        case _NeedFilter.ncd:
          if (item.programmes.contains(Programme.ncd)) { return true; }
        case _NeedFilter.eyeCare:
          // PILOT-SCOPE v1: eyeCare/cataract not in pilot — chip never added to availableNeeds.
          if (item.programmes.any((p) => p == Programme.eyeCare || p == Programme.cataract)) { return true; }
        case _NeedFilter.missedFollowUp:
          if (item.daysOverdue != null && item.daysOverdue! > 0) { return true; }
        case _NeedFilter.pendingReferral:
          if (item.referralId != null) { return true; }
        case _NeedFilter.homeVisit:
          if (item.type == MissionItemType.patientVisit ||
              item.type == MissionItemType.householdOpportunity) { return true; }
        case _NeedFilter.facilityReferral:
          if (item.type == MissionItemType.referral ||
              item.referralId != null) { return true; }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Check if a refresh is pending (e.g., assessment completed while on another tab)
    _checkPendingRefresh();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      // Pink "+ Enrol new" FAB — fixed bottom-right per spec §2.1. Opens
      // QR enrolment flow when the route lands; for now surfaces a snackbar
      // so the SK gets clear feedback rather than silent taps.
      floatingActionButton: _EnrolNewFab(),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _DashboardHeader(
              greeting: _greeting(),
              locationLine: _locationLine(),
              onNotifications: () => context.push('/referrals'),
              onPerformance: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SkPerformanceScreen(),
                ),
              ),
              settingsMenu: _SettingsMenu(onOfferBiometric: _offerBiometric),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                  children: [
                    _AiSortedInfoCard(
                      key: ValueKey('ai_sorted_$_refreshVersion'),
                      queueFuture: _queueFuture,
                    ),
                    const SizedBox(height: 10),
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
                      availableNeeds: _availableNeeds,
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
                        setState(() {
                          _selectedNeeds = const {};
                          _selectedProgrammes = const {};
                        });
                        _loadMissionData();
                      },
                      availableProgrammes: _availableProgrammes,
                      selectedProgrammes: _selectedProgrammes,
                      onProgrammeToggled: (prog) {
                        setState(() {
                          final updated = Set<Programme>.from(_selectedProgrammes);
                          if (updated.contains(prog)) {
                            updated.remove(prog);
                          } else {
                            updated.add(prog);
                          }
                          _selectedProgrammes = updated;
                        });
                        _loadMissionData();
                      },
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<List<MissionQueueItem>>(
                      key: ValueKey('queue_$_refreshVersion'),
                      future: _queueFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        final queue = snap.data ?? const [];
                        if (queue.isEmpty) {
                          final hasFilters = _selectedNeeds.isNotEmpty ||
                              _selectedProgrammes.isNotEmpty ||
                              _selectedVillageChipName != null;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _TodaysVisitsHeader(),
                              const SizedBox(height: 8),
                              if (hasFilters)
                                _FilterEmptyCard(
                                  onClearFilters: () {
                                    setState(() {
                                      _selectedNeeds = const {};
                                      _selectedProgrammes = const {};
                                      _selectedVillageChipName = null;
                                    });
                                    _loadMissionData();
                                  },
                                )
                              else
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

                        final widgets = <Widget>[];
                        for (final item in visible) {
                          widgets.add(Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MissionQueueCard(
                              item: item,
                              compact: true,
                              onTap: () => _startVisitFromQueue(item),
                              onAction: () => _startVisitFromQueue(item),
                            ),
                          ));
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _TodaysVisitsHeader(),
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
                            const SizedBox(height: 8),
                            const _HouseholdEnrollmentCard(),
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
        icon: const Icon(Icons.settings, color: Colors.white),
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
            case 'form_gallery':
              ctx.push('/dev/form-gallery');
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
              builder: (_, theme, _) {
                final IconData icon;
                final String label;
                if (theme.isSystem) {
                  icon = Icons.dark_mode;
                  label = SettingsStrings.darkMode;
                } else if (theme.isLight) {
                  icon = Icons.settings_brightness;
                  label = SettingsStrings.systemMode;
                } else {
                  icon = Icons.light_mode;
                  label = SettingsStrings.lightMode;
                }
                return ListTile(leading: Icon(icon), title: Text(label));
              },
            ),
          ),
          if (kDebugMode)
            const PopupMenuItem(
              value: 'form_gallery',
              child: ListTile(
                leading: Icon(Icons.view_list_outlined),
                title: Text('Form Gallery'),
                subtitle: Text('Dev: render all programme forms'),
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
              color: Colors.white,
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

/// Pink "Enroll new" compact pill FAB — Apon Sushashthya V1 §2.1.
class _EnrolNewFab extends StatelessWidget {
  const _EnrolNewFab();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Semantics(
      button: true,
      label: MissionDashboardStrings.enrolNewCta,
      child: Material(
        key: const Key('dashboard_enrol_new_fab'),
        color: tokens.brandPink,
        borderRadius: BorderRadius.circular(24),
        elevation: 2,
        shadowColor: tokens.brandPink.withValues(alpha: 0.4),
        child: InkWell(
          onTap: () => showEnrollmentEntrySheet(context),
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.white.withValues(alpha: 0.15),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_alt_1_rounded, size: 15, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  MissionDashboardStrings.enrolNewCta,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.greeting,
    required this.locationLine,
    required this.onNotifications,
    required this.onPerformance,
    required this.settingsMenu,
  });

  final String greeting;
  final String? locationLine;
  final VoidCallback onNotifications;
  final VoidCallback onPerformance;
  final Widget settingsMenu;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      color: tokens.brandNavy,
      padding: EdgeInsets.fromLTRB(16, topPadding + 10, 8, 10),
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
              IconButton(
                icon: const Icon(
                  Icons.leaderboard_rounded,
                  color: Colors.white,
                ),
                iconSize: 22,
                tooltip: PerformanceStrings.iconTooltip,
                onPressed: onPerformance,
              ),
              settingsMenu,
            ],
          ),
          const SizedBox(height: 8),
          const GlobalSearchBar(),
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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
    ),
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
    return Semantics(
      label: '$label: $value',
      button: true,
      child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      child: InkWell(
        key: const Key('dashboard_stat_card_tap'),
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLoading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: accent,
                              height: 1,
                            ),
                          ),
                          if (showPulse) ...[
                            const SizedBox(width: 5),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.4),
                                    blurRadius: 5,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subline,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: accent,
                        height: 1.2,
                      ),
                    ),
                    if (footnote != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        footnote!,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 14, color: accent.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _TodaysVisitsHeader extends StatelessWidget {
  const _TodaysVisitsHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final dateLabel = DateFormat('EEE d MMM').format(DateTime.now());
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
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tokens.aiSurfaceStart,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              MissionDashboardStrings.aiSortedBadge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: tokens.aiPurple,
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        label: 'View $count more visits',
        button: true,
        child: InkWell(
        key: const Key('dashboard_more_visits_tap'),
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
              color: Theme.of(context).colorScheme.onSurface,
            ),
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
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: tokens.statusSuccess.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.check_circle_rounded,
              size: 36,
              color: tokens.statusSuccess,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            MissionDashboardStrings.noMissionsToday,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            MissionDashboardStrings.allCaughtUp,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// AI sorted info banner — sits above the stats strip.
/// Navy gradient matching the app header; shows overnight sort count + 3 tags.
class _AiSortedInfoCard extends StatelessWidget {
  const _AiSortedInfoCard({super.key, required this.queueFuture});

  final Future<List<MissionQueueItem>>? queueFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MissionQueueItem>>(
      future: queueFuture,
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        final isLoading = snap.connectionState == ConnectionState.waiting;
        const tags = <String>[
          MissionDashboardStrings.aiSortedTagRisk,
          MissionDashboardStrings.aiSortedTagOverdue,
          MissionDashboardStrings.aiSortedTagCce,
        ];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.navy, AppColors.navyMid],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLoading
                          ? 'AI sorted your visits overnight'
                          : MissionDashboardStrings.aiSortedVisits(count),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: tags
                    .map(
                      (t) => Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: Text(
                          t,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Empty state shown when filters are active but no items match.
/// Apon Sushashthya V1 §2.7 — magnifying glass illustration + helpful text.
class _FilterEmptyCard extends StatelessWidget {
  const _FilterEmptyCard({required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: tokens.aiPurple.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('🔍', style: TextStyle(fontSize: 30)),
          ),
          const SizedBox(height: 12),
          Text(
            MissionDashboardStrings.noVisitsMatchFilters,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            MissionDashboardStrings.noVisitsMatchFiltersHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.cleaning_services_outlined, size: 16),
              label: Text(MissionDashboardStrings.clearNeedFilters),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.aiPurple,
                side: BorderSide(color: tokens.aiPurple.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
    required this.availableNeeds,
    required this.selectedNeeds,
    required this.onNeedToggled,
    required this.onClearNeeds,
    required this.availableProgrammes,
    required this.selectedProgrammes,
    required this.onProgrammeToggled,
  });

  final List<String> villages;
  final String? selectedVillage;
  final void Function(String? name) onVillageSelected;
  final Set<_NeedFilter> availableNeeds;
  final Set<_NeedFilter> selectedNeeds;
  final void Function(_NeedFilter need) onNeedToggled;
  final VoidCallback onClearNeeds;
  final List<Programme> availableProgrammes;
  final Set<Programme> selectedProgrammes;
  final void Function(Programme prog) onProgrammeToggled;


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
      case _NeedFilter.homeVisit:
        return MissionDashboardStrings.needHomeVisit;
      case _NeedFilter.facilityReferral:
        return MissionDashboardStrings.needFacilityReferral;
    }
  }

  String _programmeLabel(Programme programme) {
    switch (programme) {
      case Programme.imci:
        return PathwayStrings.programmeImci;
      case Programme.anc:
        return PathwayStrings.programmeAnc;
      case Programme.pnc:
        return PathwayStrings.programmePnc;
      case Programme.ncd:
        return PathwayStrings.programmeNcd;
      case Programme.tb:
        return PathwayStrings.programmeTb;
      case Programme.epi:
        return PathwayStrings.programmeEpi;
      case Programme.nutrition:
        return PathwayStrings.programmeNutrition;
      case Programme.familyPlanning:
        return PathwayStrings.programmeFamilyPlanning;
      case Programme.cataract:
        return PathwayStrings.programmeCataract;
      case Programme.eyeCare:
        return PathwayStrings.programmeEyeCare;
      case Programme.unknown:
        return PathwayStrings.programmeUnknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: village chips ──────────────────────────────────────────
        if (villages.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              MissionDashboardStrings.whichVillageVisiting,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
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
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 8),
        ],

        // ── Row 2: filter label + clear ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(
                MissionDashboardStrings.filterByNeed,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${MissionDashboardStrings.filterByNeedOptional})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (selectedNeeds.isNotEmpty || selectedProgrammes.isNotEmpty)
                Semantics(
                  label: 'Clear all filters',
                  button: true,
                  child: GestureDetector(
                    key: const Key('dashboard_filter_clear_needs_tap'),
                    onTap: onClearNeeds,
                    child: Text(
                      MissionDashboardStrings.clearNeedFilters,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ── Row 3: single scrollable row — need chips then programme chips ──
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: [
              ..._NeedFilter.values
                  .where((n) => availableNeeds.contains(n))
                  .map((need) {
                final active = selectedNeeds.contains(need);
                final cs = Theme.of(context).colorScheme;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                    label: active
                        ? 'Filter by need: ${_needLabel(need)}, selected'
                        : 'Filter by need: ${_needLabel(need)}',
                    button: true,
                    child: GestureDetector(
                      key: ValueKey('dashboard_need_filter_${need.name}'),
                      onTap: () => onNeedToggled(need),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: active ? AppColors.aiPurple : cs.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active
                                ? AppColors.aiPurple
                                : cs.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _needLabel(need),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                active ? FontWeight.w800 : FontWeight.w500,
                            color:
                                active ? Colors.white : cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              ...availableProgrammes.map((prog) {
                final active = selectedProgrammes.contains(prog);
                final cs = Theme.of(context).colorScheme;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                    label: active
                        ? 'Filter by programme: ${_programmeLabel(prog)}, selected'
                        : 'Filter by programme: ${_programmeLabel(prog)}',
                    button: true,
                    child: GestureDetector(
                      key: ValueKey('dashboard_prog_filter_${prog.name}'),
                      onTap: () => onProgrammeToggled(prog),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: active ? AppColors.aiPurple : cs.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active
                                ? AppColors.aiPurple
                                : cs.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _programmeLabel(prog),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                active ? FontWeight.w800 : FontWeight.w500,
                            color:
                                active ? Colors.white : cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        label: isActive ? 'Village filter: $label, selected' : 'Filter by village: $label',
        button: true,
        child: GestureDetector(
          key: const Key('dashboard_filter_chip_tap'),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? AppColors.navy : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isActive ? AppColors.navy : Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Household enrollment CTA card ────────────────────────────────────────────

class _HouseholdEnrollmentCard extends StatelessWidget {
  const _HouseholdEnrollmentCard();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.ancHeader.withValues(alpha: 0.35),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/patients/households'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.ancHeader.withValues(alpha: 0.12),
                  child: const Icon(Icons.home_rounded,
                      color: AppColors.ancHeader, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        MissionDashboardStrings.enrollHouseholdTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        MissionDashboardStrings.enrollHouseholdSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => context.push('/patients/households'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ancHeader,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  child: const Text(
                      MissionDashboardStrings.enrollHouseholdAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
