import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/locale_provider.dart';
import '../../app/theme.dart';
import '../../app/theme_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/constants/app_strings.dart';
import '../../core/i18n/app_locale.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/local_dashboard_repository.dart';
import '../../core/debug/console_log.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/models/risk.dart';
import '../../core/widgets/patient_filter_panel.dart';
import '../referral/referral_repository.dart';
import 'widgets/dashboard_search_field.dart';
import '../visit/visit_controller.dart';
import '../visit/visit_start_helper.dart';
import '../visit/widgets/widgets.dart';
import 'dashboard_repository.dart';
import 'mission_dashboard_repository.dart';
import '../household/enrollment/enrollment_entry_sheet.dart';
import '../cce/cce_alerts_drawer.dart';
import '../cce/cce_repository.dart';
import '../settings/ai_settings_screen.dart';
import 'sk_performance_screen.dart';

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


  // Cached reference to mission repository for change listening.
  MissionDashboardRepository? _missionRepo;
  bool _missionListenerAdded = false;
  bool _demoSeeded = false;
  
  // Flag to track if data needs refresh when widget becomes visible.
  bool _pendingRefresh = false;

  // Version counter for forcing FutureBuilder rebuilds.
  int _refreshVersion = 0;

  // Notification badge count — referral critical + active counts.
  int _notificationCount = 0;

  // Completed patient IDs for today — cards remain visible but non-navigable.
  Set<String> _completedIds = const {};

  // Inline village chip + need filter + inline search
  List<String> _inlineVillages = const [];
  String? _selectedVillageChipName;
  Set<NeedFilter> _selectedNeeds = const {};
  Set<NeedFilter> _availableNeeds = const {};
  String _searchQuery = '';

  // Full unfiltered queue — filter/search applied synchronously from this cache.
  List<MissionQueueItem> _baseQueue = const [];

  /// Today's actionable visit count for the ✦ AI sorted badge.
  /// Always derived from [_baseQueue] with upcoming dropped — never from the
  /// currently applied village/need/search filter (those only shrink the list).
  int _todayVisitCount = 0;
  bool _todayCountLoading = true;

  /// How many queue cards are currently painted. Grows on scroll (§ lazy load).
  /// Full clinical order stays in `_queueFuture` — we only window the widgets.
  static const int _kQueuePageSize = 15;
  int _queueRevealCount = _kQueuePageSize;

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
    // Debug builds only: seed the 3 wireframe CCE scenarios once so the
    // Care Coordination Alerts drawer has data to demo. Never runs in
    // release, so real users never see fabricated referrals.
    if (kDebugMode && !_demoSeeded) {
      _demoSeeded = true;
      context.read<ReferralRepository>().seedDemoDataIfEmpty().then((_) {
        if (mounted) _refreshNotificationCount();
      });
    }
    _refreshNotificationCount();
  }

  Future<void> _refreshNotificationCount() async {
    try {
      // The bell opens the CCE drawer, so its badge must match the drawer's
      // "N actions needed" (breached + warning), not raw active count.
      final cce = CceRepository(
        referrals: context.read<ReferralRepository>(),
        patients: context.read<PatientDao>(),
      );
      final alerts = await cce.loadAlerts();
      if (!mounted) return;
      setState(() => _notificationCount = cce.actionsNeededCount(alerts));
    } catch (_) {}
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
      _queueRevealCount = _kQueuePageSize;
      _todayCountLoading = true;
      debugPrint('[Dashboard] Loading mission data, version=$_refreshVersion');
      // Load completed patient IDs and filter queue to exclude them
      _queueFuture = _loadFilteredQueue(missionRepo, encounterDao);
    });
  }
  
  /// Load the mission queue, cache it, then apply active filters and return.
  Future<List<MissionQueueItem>> _loadFilteredQueue(
    MissionDashboardRepository missionRepo,
    EncounterDao encounterDao,
  ) async {
    final completedIds = await encounterDao.completedTodayPatientIds();

    // Persist completed IDs so filtering + card "done" state use the same set.
    // Assign before loadQueue so any concurrent filter apply sees them;
    // setState after so the first paint also marks DONE correctly.
    _completedIds = completedIds;

    final rawQueue = await missionRepo.loadQueue(limit: 500);

    // Keep completed-today patients in the cache so programme filters can still
    // show them (done state) in clinical priority order. Unfiltered dashboard
    // drops them inside filterMissionQueue().
    final queue = rawQueue;

    assert(() {
      final villages = <String, int>{};
      for (final i in rawQueue) {
        final v = i.village?.trim().isNotEmpty == true
            ? i.village!.trim()
            : '(null)';
        villages[v] = (villages[v] ?? 0) + 1;
      }
      debugPrint(
        '[Dashboard filter] baseLoad raw=${rawQueue.length} '
        'completedToday=${completedIds.length}',
      );
      debugPrint(
        '[Dashboard filter] baseLoad villages: '
        '${villages.entries.map((e) => "${e.key}=${e.value}").join(", ")}',
      );
      for (final probe in const [
        'Yasmeen',
        'Raaajasri',
        'Teena',
        'Nazmeen',
        'Jakir',
      ]) {
        MissionQueueItem? hit;
        for (final i in rawQueue) {
          if (i.patientName == probe) {
            hit = i;
            break;
          }
        }
        if (hit == null) {
          debugPrint(
            '[Dashboard filter] baseLoad probe $probe → ABSENT from loadQueue',
          );
          continue;
        }
        final done = hit.patientId != null &&
            completedIds.contains(hit.patientId);
        final sched = DashboardTier.fromDueAt(hit.dueAt);
        debugPrint(
          '[Dashboard filter] baseLoad probe $probe → '
          '[${hit.priorityCode}] v=${hit.village} '
          'prog=${hit.programmes.map((p) => p.name).join("+")} '
          'tier=${hit.tier.name} due=${hit.dueAt} sched=${sched.name} '
          '${done ? "COMPLETED-today(kept-in-base)" : "actionable"}',
        );
      }
      return true;
    }());

    // Cache full queue so filters can be re-applied synchronously
    // without a repository round-trip on every chip tap.
    final todayCount = _countTodaysActionable(queue, completedIds);
    _baseQueue = queue;

    // Extract distinct village labels for inline chips
    final allVillageLabels = queue
        .map((i) => i.village?.trim())
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final availableNeeds = computeAvailableNeeds(queue);
    if (mounted) {
      // ignore: use_build_context_synchronously
      setState(() {
        _inlineVillages = allVillageLabels;
        _availableNeeds = availableNeeds;
        _todayVisitCount = todayCount;
        _todayCountLoading = false;
      });
    }

    assert(() {
      debugPrint(
        '[Dashboard filter] todayBadge=$todayCount '
        '(base=${queue.length}, excl. upcoming; '
        'activeFilters '
        'village=${_selectedVillageChipName ?? "(all)"} '
        'needs=[${_selectedNeeds.map((n) => n.name).join(",")}] '
        '— badge ignores these)',
      );
      return true;
    }());

    return _buildFilteredList(queue);
  }

  /// Visits that belong on the unfiltered "today" dashboard — not upcoming
  /// and not already completed today.
  static int _countTodaysActionable(
    List<MissionQueueItem> queue,
    Set<String> completedIds,
  ) {
    return queue
        .where(
          (i) =>
              i.tier != DashboardTier.upcoming &&
              (i.patientId == null || !completedIds.contains(i.patientId)),
        )
        .length;
  }

  /// Apply all active filters (village, need category, search query) to [queue]
  /// and return the matching subset. Pure — reads current filter state fields.
  List<MissionQueueItem> _buildFilteredList(List<MissionQueueItem> queue) {
    return filterMissionQueue(
      queue: queue,
      village: _selectedVillageChipName,
      selectedNeeds: _selectedNeeds,
      searchQuery: _searchQuery,
      completedPatientIds: _completedIds,
    );
  }

  void _clearFilters() {
    _selectedNeeds = const {};
    _selectedVillageChipName = null;
    _searchQuery = '';
    _queueRevealCount = _kQueuePageSize;
  }

  /// Re-apply current filters to the cached base queue synchronously.
  /// Use for chip toggles and search — avoids a repository round-trip when
  /// only the filter state changed.
  void _applyFilters() {
    if (!mounted) return;
    if (_baseQueue.isEmpty) {
      // Base queue not yet loaded — reload from repo, which populates _baseQueue
      // and then applies active filters at the end of _loadFilteredQueue().
      _loadMissionData();
      return;
    }
    setState(() {
      _refreshVersion++;
      _queueRevealCount = _kQueuePageSize;
      _queueFuture = Future.value(_buildFilteredList(_baseQueue));
    });
  }

  /// Expand the painted window when the SK scrolls near the end of the list.
  void _maybeRevealMore(int total) {
    if (!mounted || total <= _queueRevealCount) return;
    setState(() {
      _queueRevealCount =
          (_queueRevealCount + _kQueuePageSize).clamp(0, total);
    });
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
        title: Text(DashboardStrings.useDeviceUnlockTitle),
        content: Text(
          supported
              ? DashboardStrings.biometricOfferSupported
              : DashboardStrings.biometricOfferUnsupported,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(DashboardStrings.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(DashboardStrings.enable),
          ),
        ],
      ),
    );
    if (ans != true || !mounted) return;
    if (!supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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
        SnackBar(content: Text(DashboardStrings.deviceUnlockEnabled)),
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
    assert(() {
      final code = '${item.band.wireTag.replaceFirst('band', '')}'
          '${item.modifier == Modifier.none ? '' : item.modifier.wireTag}';
      final progs = item.programmes.map((p) => p.name).join(',');
      final overdueTag = (item.daysOverdue != null && item.daysOverdue! > 0)
          ? ' | overdue: ${item.daysOverdue}d'
          : '';
      final driversTag =
          item.drivers.isNotEmpty ? ' | drivers: ${item.drivers.join(",")}' : '';
      ConsoleLog.banner(
        '[Patient selected] [$code] ${item.patientName}'
        ' | prog: $progs | tier: ${item.tier.name}'
        '${item.isPregnant ? " | pregnant" : ""}'
        '$overdueTag$driversTag'
        ' | sortRank: ${item.priorityScore}',
      );
      if (item.clinicalReasons.isNotEmpty) {
        ConsoleLog.banner('  Why $code:');
        for (final r in item.clinicalReasons) {
          ConsoleLog.banner('    • $r');
        }
      } else {
        ConsoleLog.banner('  Why $code: (no clinical reasons stored)');
      }
      return true;
    }());
    final patientId = item.patientId;
    if (patientId != null && _completedIds.contains(patientId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            MissionDashboardStrings.completedVisitToast(item.patientName),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (patientId == null || patientId.isEmpty) {
      if (item.referralId != null) {
        context.push('/referral/${item.referralId}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(MissionDashboardStrings.visitMissingPatient),
          ),
        );
      }
      return;
    }
    // Look up member to get referenceId (backend integer PK) and memberId.
    final memberDao = context.read<MemberDao>();
    final controller = context.read<VisitController>();
    final member = await memberDao.getByPatientId(patientId);
    // referenceId is the backend integer PK; fall back to id which may also
    // be numeric (e.g. "768293") for members synced before schema v17.
    final householdMemberLocalId =
        int.tryParse(member?.referenceId ?? '') ??
        int.tryParse(member?.id ?? '') ??
        0;
    final memberId = member?.id;
    // Mirror Android: use sub-village ID for assessment scope so that Android's
    // member-assessment-history pull (scoped to [203, 204, 206]) can find
    // Flutter-submitted assessments. Parent villageId (34) is invisible to it.
    final villageId = member?.subVillageId ?? member?.villageId;
    debugPrint('[Dashboard] member lookup: patientId=$patientId referenceId=${member?.referenceId} memberId=$memberId villageId=$villageId → householdMemberLocalId=$householdMemberLocalId');
    if (!mounted) return;
    final encounterId = await startOrResumeVisit(
      context,
      controller: controller,
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
          'patientGender': member?.gender,
          'householdId': item.householdId,
          'patientAge': item.age,
          'memberId': memberId,
          'householdMemberLocalId': householdMemberLocalId,
          'villageId': villageId,
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
              onPerformance: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SkPerformanceScreen(),
                ),
              ),
              settingsMenu: _SettingsMenu(onOfferBiometric: _offerBiometric),
              notificationCount: _notificationCount,
              onNotificationTap: () => CceAlertsDrawer.show(context),
              onSearchChanged: (q) {
                setState(() {
                  _searchQuery = q;
                  _queueRevealCount = _kQueuePageSize;
                });
                _applyFilters();
              },
            ),
            // Referral alert strip — sits between header/search and village tabs
            // so it reads as a system-level alert before the worklist.
            _ReferralAlertBanner(
              key: ValueKey('referral_banner_$_refreshVersion'),
              onTap: () => CceAlertsDrawer.show(context),
              count: _notificationCount,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<MissionQueueItem>>(
                  key: ValueKey('queue_$_refreshVersion'),
                  future: _queueFuture,
                  builder: (context, snap) {
                    final waiting =
                        snap.connectionState == ConnectionState.waiting &&
                            _baseQueue.isEmpty;
                    final queue = snap.data ?? const <MissionQueueItem>[];

                    assert(() {
                      if (waiting || queue.isEmpty) return true;
                      final codes = queue.map((q) => q.priorityCode);
                      ConsoleLog.banner(
                        '[Dashboard UI] ${queue.length} visits (spec §2.8 lazy):',
                      );
                      ConsoleLog.banner(
                        '  spec:     $kPrioritySortSpecLegend',
                      );
                      ConsoleLog.banner(
                        '  chain:    ${prioritySortChain(codes)}',
                      );
                      ConsoleLog.banner(
                        '  compact:  ${prioritySortChainCompact(codes)}',
                      );
                      final preview = queue.length > 12 ? 12 : queue.length;
                      for (var i = 0; i < preview; i++) {
                        final q = queue[i];
                        ConsoleLog.banner(
                          '  ${i + 1}. [${q.priorityCode}] ${q.patientName}'
                          ' | tier: ${q.tier.name}'
                          '${q.isPregnant ? " | pregnant" : ""}',
                        );
                      }
                      if (queue.length > preview) {
                        ConsoleLog.banner(
                          '  … +${queue.length - preview} more (scroll)',
                        );
                      }
                      return true;
                    }());

                    // Headers: filter panel, spacer, visits title, spacer.
                    // Then empty-state OR a reveal-window of queue cards.
                    const headerCount = 4;
                    final hasFilters = _selectedNeeds.isNotEmpty ||
                        _selectedVillageChipName != null ||
                        _searchQuery.isNotEmpty;
                    final revealed = queue.isEmpty
                        ? 0
                        : (_queueRevealCount < queue.length
                            ? _queueRevealCount
                            : queue.length);
                    final hasMore = revealed < queue.length;
                    final bodyCount =
                        waiting || queue.isEmpty ? 1 : revealed;
                    final itemCount =
                        headerCount + bodyCount + (hasMore ? 1 : 0);

                    return NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.pixels >=
                            n.metrics.maxScrollExtent - 240) {
                          _maybeRevealMore(queue.length);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return PatientFilterPanel(
                              villages: _inlineVillages
                                  .map((name) => (value: name, label: name))
                                  .toList(),
                              selectedVillageValue: _selectedVillageChipName,
                              onVillageSelected: (name) {
                                debugPrint(
                                  '[Dashboard filter] village tap → '
                                  '${name ?? "(all)"}',
                                );
                                setState(() {
                                  _selectedVillageChipName = name;
                                  _queueRevealCount = _kQueuePageSize;
                                });
                                _applyFilters();
                              },
                              availableNeeds: _availableNeeds,
                              selectedNeeds: _selectedNeeds,
                              onNeedToggled: (need) {
                                setState(() {
                                  final updated =
                                      Set<NeedFilter>.from(_selectedNeeds);
                                  if (updated.contains(need)) {
                                    updated.remove(need);
                                  } else {
                                    updated.add(need);
                                  }
                                  _selectedNeeds = updated;
                                  _queueRevealCount = _kQueuePageSize;
                                  debugPrint(
                                    '[Dashboard filter] need tap → '
                                    '${need.name} '
                                    'now=[${updated.map((n) => n.name).join(",")}]',
                                  );
                                });
                                _applyFilters();
                              },
                            );
                          }
                          if (index == 1) return const SizedBox(height: 6);
                          if (index == 2) {
                            return _TodaysVisitsHeader(
                              visitCount: _todayVisitCount,
                              loading: _todayCountLoading || waiting,
                              onTap: _navigateToFirstQueueItem,
                            );
                          }
                          if (index == 3) return const SizedBox(height: 10);

                          if (waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              ),
                            );
                          }

                          if (queue.isEmpty) {
                            if (hasFilters) {
                              return _FilterEmptyCard(
                                onClearFilters: () {
                                  setState(() {
                                    _clearFilters();
                                  });
                                  _applyFilters();
                                },
                              );
                            }
                            return _EmptyVisitsCard();
                          }

                          final queueIndex = index - headerCount;
                          if (queueIndex >= revealed) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }

                          final item = queue[queueIndex];
                          final done = item.patientId != null &&
                              _completedIds.contains(item.patientId);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MissionQueueCard(
                              item: item,
                              compact: true,
                              isCompleted: done,
                              onTap: () => _startVisitFromQueue(item),
                              onAction: () => _startVisitFromQueue(item),
                            ),
                          );
                        },
                      ),
                    );
                  },
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
        iconSize: 21,
        padding: EdgeInsets.zero,
        // padding/iconSize alone don't shrink Material 3's hidden 48x48
        // minimum tap-target — this style override is what actually does.
        style: IconButton.styleFrom(
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onSelected: (v) async {
          switch (v) {
            case 'enable_bio':
              onOfferBiometric();
              break;
            case 'disable_bio':
              final confirmBio = await showDialog<bool>(
                context: ctx,
                builder: (dlgCtx) => AlertDialog(
                  title: Text(DashboardStrings.confirmDisableDeviceUnlock),
                  content: Text(DashboardStrings.confirmDisableDeviceUnlockBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(false),
                      child: Text(DashboardStrings.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(true),
                      child: Text(DashboardStrings.disable),
                    ),
                  ],
                ),
              );
              if (confirmBio != true) break;
              await auth.disableBiometric();
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(DashboardStrings.deviceUnlockDisabled)),
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
                      child: Text(DashboardStrings.cancel),
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
            case 'appearance':
              final theme = ctx.read<ThemeProvider>();
              final chosen = await _showOptionPicker<ThemeMode>(
                context: ctx,
                title: SettingsStrings.appearance,
                current: theme.mode,
                options: [
                  (ThemeMode.light, SettingsStrings.lightMode),
                  (ThemeMode.dark, SettingsStrings.darkMode),
                  (ThemeMode.system, SettingsStrings.systemMode),
                ],
              );
              if (chosen != null) await theme.setMode(chosen);
              break;
            case 'language':
              final locale = ctx.read<LocaleProvider>();
              final chosen = await _showOptionPicker<AppLanguage>(
                context: ctx,
                title: SettingsStrings.language,
                current: locale.language,
                options: [
                  (AppLanguage.english, SettingsStrings.english),
                  (AppLanguage.bangla, SettingsStrings.bangla),
                ],
              );
              if (chosen != null) await locale.setLanguage(chosen);
              break;
            case 'ai_settings':
              Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AiSettingsScreen(),
                ),
              );
              break;
            case 'logout':
              final confirmLogout = await showDialog<bool>(
                context: ctx,
                builder: (dlgCtx) => AlertDialog(
                  title: Text(DashboardStrings.confirmSignOut),
                  content: Text(DashboardStrings.confirmSignOutBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(false),
                      child: Text(DashboardStrings.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dlgCtx).pop(true),
                      child: Text(DashboardStrings.signOut),
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
            PopupMenuItem(
              value: 'enable_bio',
              child: _SettingsRow(
                emoji: '🔓',
                chipColor: AppColors.aiSurfaceStart,
                title: DashboardStrings.enableDeviceUnlock,
              ),
            ),
          if (auth.biometricEnabled)
            PopupMenuItem(
              value: 'disable_bio',
              child: _SettingsRow(
                emoji: '🔒',
                chipColor: AppColors.aiSurfaceStart,
                title: DashboardStrings.disableDeviceUnlock,
              ),
            ),
          if (!auth.pinEnabled)
            PopupMenuItem(
              value: 'set_pin',
              child: _SettingsRow(
                emoji: '🔢',
                chipColor: AppColors.ancSurface,
                title: PinStrings.enablePin,
              ),
            ),
          if (auth.pinEnabled)
            PopupMenuItem(
              value: 'remove_pin',
              child: _SettingsRow(
                emoji: '🔢',
                chipColor: AppColors.ancSurface,
                title: PinStrings.disablePin,
              ),
            ),
          PopupMenuItem(
            value: 'appearance',
            child: Consumer<ThemeProvider>(
              builder: (_, theme, _) {
                final String subtitle;
                if (theme.isDark) {
                  subtitle = SettingsStrings.darkMode;
                } else if (theme.isSystem) {
                  subtitle = SettingsStrings.systemMode;
                } else {
                  subtitle = SettingsStrings.lightMode;
                }
                return _SettingsRow(
                  emoji: '🌓',
                  chipColor: AppColors.catChildSurface,
                  title: SettingsStrings.appearance,
                  subtitle: subtitle,
                );
              },
            ),
          ),
          PopupMenuItem(
            value: 'language',
            child: Consumer<LocaleProvider>(
              builder: (_, locale, _) => _SettingsRow(
                emoji: '🌐',
                chipColor: AppColors.catHomeSurface,
                title: SettingsStrings.language,
                subtitle: locale.isBangla
                    ? SettingsStrings.bangla
                    : SettingsStrings.english,
              ),
            ),
          ),
          PopupMenuItem(
            value: 'ai_settings',
            child: _SettingsRow(
              emoji: '🤖',
              chipColor: AppColors.aiSurfaceStart,
              title: SettingsStrings.aiSettings,
              subtitle: SettingsStrings.aiSettingsSubtitle,
            ),
          ),
          PopupMenuItem(
            value: 'logout',
            child: _SettingsRow(
              emoji: '🚪',
              chipColor: AppColors.catHighriskSurface,
              title: DashboardStrings.signOut,
              titleColor: AppColors.statusCritical,
              showChevron: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the Settings popup — colored icon chip + title + optional
/// subtitle + trailing chevron, matching the v13 mockup's `.settings-opt`
/// row exactly (28×28 rounded-8 chip, 12px/700 title, 9.5px muted subtitle).
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.emoji,
    required this.chipColor,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.showChevron = true,
  });

  final String emoji;
  final Color chipColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: titleColor ?? AppColors.textPrimary,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ),
        if (showChevron)
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
      ],
    );
  }
}

/// Small "pick one of N" dialog shared by the Appearance and Language rows —
/// a list of options with a check mark next to whichever is current.
Future<T?> _showOptionPicker<T>({
  required BuildContext context,
  required String title,
  required T current,
  required List<(T value, String label)> options,
}) {
  return showDialog<T>(
    context: context,
    builder: (dlgCtx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final (value, label) in options)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dlgCtx).pop(value),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                if (value == current)
                  const Icon(Icons.check, size: 18, color: AppColors.aiPurpleDark),
              ],
            ),
          ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// HTML-composition widgets
// Match `Leapfrog .html` dashboard: navy header, stat card, referral banner,
// village tabs, category bubbles, priority-ordered patient cards.
// ─────────────────────────────────────────────────────────────────────────────

/// Pink "Enroll new" compact pill FAB — Apon Sushashthya V1 §2.1.
class _EnrolNewFab extends StatelessWidget {
  const _EnrolNewFab();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<WorklistCategoryColors>()!;
    return Semantics(
      button: true,
      label: MissionDashboardStrings.enrolNewCta,
      child: Container(
        key: const Key('dashboard_enrol_new_fab'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.fabPill),
          boxShadow: [
            BoxShadow(
              color: tokens.fabShadow,
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: tokens.fabBackground,
          borderRadius: BorderRadius.circular(AppRadius.fabPill),
          child: InkWell(
            onTap: () => showEnrollmentEntrySheet(context),
            borderRadius: BorderRadius.circular(AppRadius.fabPill),
            splashColor: Colors.white.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    MissionDashboardStrings.enrolNewCta,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
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
    required this.onPerformance,
    required this.settingsMenu,
    required this.notificationCount,
    required this.onNotificationTap,
    required this.onSearchChanged,
  });

  final String greeting;
  final String? locationLine;
  final VoidCallback onPerformance;
  final Widget settingsMenu;
  final int notificationCount;
  final VoidCallback onNotificationTap;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      color: tokens.brandNavy,
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .header-row: flex, space-between, align-items:center, margin-bottom:14px
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting, style: AppTextStyles.headerTitle),
                    const SizedBox(height: 1), // .header-sub margin-top:1px
                    Text(
                      locationLine ?? DashboardStrings.communityAtAGlance,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headerSub,
                    ),
                  ],
                ),
              ),
              // Icon order fixed per spec: Performance → Settings → Notifications.
              // Not an IconButton — Material 3's hidden 48x48 minimum tap-target
              // would defeat the spec's tight 14px inter-icon gap even with
              // padding/iconSize zeroed out.
              Tooltip(
                message: PerformanceStrings.iconTooltip,
                child: GestureDetector(
                  onTap: onPerformance,
                  child: const Icon(
                    Icons.leaderboard_rounded,
                    size: 21,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxl), // 14px per spec
              settingsMenu,
              const SizedBox(width: AppSpacing.xxl),
              _NotificationBell(
                count: notificationCount,
                onTap: onNotificationTap,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl), // .header-row margin-bottom:14px
          DashboardSearchField(onChanged: onSearchChanged),
        ],
      ),
    );
  }
}

class _ReferralAlertBanner extends StatefulWidget {
  const _ReferralAlertBanner({
    super.key,
    required this.onTap,
    required this.count,
  });
  final VoidCallback onTap;

  /// Pre-computed CCE actions-needed count — keeps this banner in sync with
  /// the bell badge (both now use the same source: CceRepository).
  final int count;

  @override
  State<_ReferralAlertBanner> createState() => _ReferralAlertBannerState();
}

class _ReferralAlertBannerState extends State<_ReferralAlertBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.pulseSlow,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: AppAnimations.gentle),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.count;
    // Spec-exact #DC2626/#B91C1C — deliberately not tokens.statusCritical
    // (a different, more generic red), same rationale as the notification
    // badge's hardcoded pink below.
    final bannerColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.referralAlertBgDark
        : AppColors.referralAlertBg;
    return Semantics(
          button: true,
          label: 'Referral alerts: $total',
          child: Container(
            decoration: BoxDecoration(
              color: bannerColor,
              boxShadow: [
                BoxShadow(
                  color: bannerColor.withValues(alpha: 0.25),
                  offset: const Offset(0, 2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('dashboard_referral_banner_tap'),
                onTap: widget.onTap,
                splashColor: Colors.white.withValues(alpha: 0.15),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Circle badge with count + yellow pulse dot
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            child: Center(
                              child: Text(
                                total > 99 ? '99+' : '$total',
                                style: const TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: -2,
                            right: -2,
                            child: AnimatedBuilder(
                              animation: _pulseAnim,
                              builder: (_, _) => Opacity(
                                opacity: _pulseAnim.value,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.referralPulseDot,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          MissionDashboardStrings.referralAlertsLabel,
                          style: const TextStyle(
                            fontFamily: 'NunitoSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 13,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
  }
}

class _TodaysVisitsHeader extends StatelessWidget {
  const _TodaysVisitsHeader({
    required this.visitCount,
    required this.loading,
    this.onTap,
  });

  /// Unfiltered today's actionable visits (upcoming excluded). Independent of
  /// village / need / search chips so the badge stays honest while filtering.
  final int visitCount;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final aiTokens = Theme.of(context).extension<AiColors>()!;
    final dateLabel = DateFormat('EEE d MMM').format(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              MissionDashboardStrings.todaysVisits(dateLabel),
              style: AppTextStyles.worklistRowLabel,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: aiTokens.surface,
              borderRadius: BorderRadius.circular(AppRadius.rxIcon),
            ),
            child: Text(
              loading
                  ? MissionDashboardStrings.aiSortedBadge
                  : MissionDashboardStrings.aiSortedVisitsToday(visitCount),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: aiTokens.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty card shown when there are no visits for today.
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

/// Empty state shown when filters are active but no items match.
/// Apon Sushashthya V1 §2.7 — magnifying glass illustration + helpful text.
class _FilterEmptyCard extends StatelessWidget {
  const _FilterEmptyCard({required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final aiTokens = Theme.of(context).extension<AiColors>()!;
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
              color: aiTokens.primary.withValues(alpha: 0.10),
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
                foregroundColor: aiTokens.primary,
                side: BorderSide(color: aiTokens.primary.withValues(alpha: 0.4)),
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

// ─── Notification bell ────────────────────────────────────────────────────────

class _NotificationBell extends StatefulWidget {
  const _NotificationBell({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.badgePulse,
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: AppAnimations.gentle);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final count = widget.count;
    return Semantics(
      label: count > 0 ? '$count notifications' : 'Notifications',
      button: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_outlined,
                color: Colors.white,
                size: 22,
              ),
              if (count > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final t = _pulse.value;
                      return Transform.scale(
                        scale: 1 + 0.1 * t,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // Spec-exact #E8356D, not tokens.brandPink — that
                            // token resolves to a different, brighter pink in
                            // dark theme, but the badge must pixel-match the
                            // spec regardless of theme mode.
                            color: const Color(0xFFE8356D),
                            border: Border.all(color: tokens.brandNavy, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE8356D)
                                    .withValues(alpha: 0.5 * (1 - t)),
                                spreadRadius: 4 * t,
                              ),
                            ],
                          ),
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

