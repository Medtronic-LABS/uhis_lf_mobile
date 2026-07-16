import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/models/patient.dart';
import '../../core/models/referral.dart';
import '../../core/models/sla.dart';
import '../../core/sync/offline_sync_service.dart';
import '../dashboard/mission_dashboard_repository.dart';
import '../patient/followup_call_service.dart';
import '../visit/visit_controller.dart';
import '../visit/visit_start_helper.dart';
import '../visit/widgets/widgets.dart';
import 'referral_api_service.dart';
import '../../core/widgets/patient_filter_panel.dart' show VillageFilterTab;
import 'referral_repository.dart';
import 'widgets/bulk_actions.dart';
import 'widgets/critical_banner.dart';
import 'widgets/follow_up_scheduler.dart';
import 'widgets/loading_skeleton.dart';
import 'widgets/prescription_viewer.dart';
import 'widgets/priority_chip_row.dart';
import 'widgets/search_filter_bar.dart';
import 'widgets/sla_strip.dart';
import 'widgets/triage_referral_card.dart';

/// Standalone `/referrals` route. Built off the same composition primitives
/// the worklist uses: chip row + freshness strip + virtualised list +
/// optional banner.
class ReferralListScreen extends StatefulWidget {
  const ReferralListScreen({super.key});

  @override
  State<ReferralListScreen> createState() => _ReferralListScreenState();
}

class _ReferralListScreenState extends State<ReferralListScreen>
    with SingleTickerProviderStateMixin {
  SlaPriority? _filter;
  Future<_DashboardData>? _future;
  
  // Cached references to avoid context.read on deactivated widget
  ReferralRepository? _repo;
  PatientDao? _patientDao;
  OfflineSyncService? _sync;
  MissionDashboardRepository? _missionRepo;
  EncounterDao? _encounterDao;
  bool _listenerAdded = false;

  // Tab controller for Visits/Referrals tabs
  late TabController _tabController;

  // Mission queue state
  Future<List<MissionQueueItem>>? _missionQueueFuture;

  // Completed patient IDs (visited today)
  Set<String> _completedPatientIds = {};

  // Visit tier filter
  DashboardTier? _visitTierFilter;

  // Inline village chip filter for Visits tab
  String? _selectedVisitVillage;

  // Show only completed patients filter
  bool _showCompletedOnly = false;

  // Search and filter state
  String _searchQuery = '';
  Set<ReferralStatusFilter> _statusFilters = {};
  DateTimeRange? _dateRange;
  ReferralSortOption _sortOption = ReferralSortOption.priorityDesc;

  // Bulk selection state
  Set<String> _selectedIds = {};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  // Auto-refresh state
  Timer? _autoRefreshTimer;
  static const _autoRefreshInterval = Duration(minutes: 5);

  // Offline state
  bool _isOffline = false;
  final int _pendingActions = 0;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Loading state
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Defer to didChangeDependencies where context is valid
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache references - always refresh on didChangeDependencies
    _repo = context.read<ReferralRepository>();
    _patientDao = context.read<PatientDao>();
    _sync = context.read<OfflineSyncService>();
    _missionRepo = context.read<MissionDashboardRepository>();
    _encounterDao = context.read<EncounterDao>();
    // Initialize future and listener on first call
    if (!_listenerAdded) {
      _listenerAdded = true;
      _future = _loadAll(_filter);
      _missionQueueFuture = _loadMissionQueue();
      _repo!.changes.addListener(_onChanges);
      _missionRepo!.changes.addListener(_onMissionChanges);
      _startAutoRefresh();
      _setupConnectivityListener();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _repo?.changes.removeListener(_onChanges);
    _missionRepo?.changes.removeListener(_onMissionChanges);
    _autoRefreshTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (mounted && !_isOffline) {
        _syncNow();
      }
    });
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        if (!mounted) return;
        final wasOffline = _isOffline;
        _isOffline = results.contains(ConnectivityResult.none);
        if (wasOffline != _isOffline) {
          setState(() {});
          // Auto-sync when coming back online
          if (wasOffline && !_isOffline) {
            _syncNow();
          }
        }
      },
    );
  }

  void _onChanges() {
    if (!mounted) return;
    _reload();
  }

  /// Called when mission dashboard data changes (e.g., after assessment completion).
  void _onMissionChanges() {
    if (!mounted) return;
    debugPrint('[Tasks] Mission data changed, reloading queue...');
    _reloadMissionQueue();
  }

  void _reload() {
    if (!mounted || _repo == null) return;
    final future = _loadAll(_filter);
    final missionFuture = _loadMissionQueue();
    setState(() {
      _future = future;
      _missionQueueFuture = missionFuture;
    });
  }

  /// Reload just the mission queue (used when mission data changes).
  void _reloadMissionQueue() {
    if (!mounted) return;
    final missionFuture = _loadMissionQueue();
    setState(() {
      _missionQueueFuture = missionFuture;
    });
  }

  /// Load mission queue items sorted by tier priority.
  /// Completed patients (visited today) are sorted to the bottom.
  Future<List<MissionQueueItem>> _loadMissionQueue() async {
    final missionRepo = _missionRepo;
    final encounterDao = _encounterDao;
    if (missionRepo == null) return const [];
    try {
      // Load completed patient IDs first
      if (encounterDao != null) {
        final completedIds = await encounterDao.completedTodayPatientIds();
        if (mounted) {
          setState(() => _completedPatientIds = completedIds);
        }
      }
      
      final queue = await missionRepo.loadQueue(limit: 200);
      // Sort by: 1) completed status (not completed first), 2) tier priority
      final sorted = List<MissionQueueItem>.from(queue)
        ..sort((a, b) {
          final aCompleted = _completedPatientIds.contains(a.patientId);
          final bCompleted = _completedPatientIds.contains(b.patientId);
          // Completed items go to bottom
          if (aCompleted != bCompleted) {
            return aCompleted ? 1 : -1;
          }
          // Within same completion status, sort by tier
          return a.tier.rank.compareTo(b.tier.rank);
        });
      return sorted;
    } catch (e) {
      debugPrint('[Tasks] Failed to load mission queue: $e');
      return const [];
    }
  }

  Future<_DashboardData> _loadAll(SlaPriority? filter) async {
    final repo = _repo;
    final patientDao = _patientDao;
    final sync = _sync;
    // Return empty data if dependencies aren't ready (during hot reload edge cases)
    if (repo == null || patientDao == null || sync == null) {
      return _DashboardData(
        referrals: const [],
        patients: const {},
        counts: const {},
        events: const {},
        criticalCount: 0,
        activeCount: 0,
        lastSyncedAt: null,
      );
    }
    var list = await repo.load(levelFilter: filter);
    final counts = await repo.counts();
    final perLevel = <SlaPriority, int>{};
    for (final p in SlaPriority.values) {
      // Cheap recount via the indexed query; in practice this is a single
      // SELECT per band — accepting that for now over a more elaborate
      // SQL aggregate to keep the DAO surface small.
      perLevel[p] = (await repo.load(levelFilter: p)).length;
    }
    final patients = <String, Patient>{};
    final events = <String, List<ReferralStatusEventRow>>{};
    for (final r in list) {
      if (!patients.containsKey(r.patientId)) {
        final p = await patientDao.byId(r.patientId);
        if (p != null) patients[r.patientId] = p;
      }
      // Load timeline events for each referral
      events[r.id] = await repo.timeline(r.id);
    }

    // Apply search query filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((r) {
        final patient = patients[r.patientId];
        final patientName = patient?.name?.toLowerCase() ?? '';
        final diagnosis = r.diagnosisLabel?.toLowerCase() ?? '';
        final patientId = r.patientId.toLowerCase();
        return patientName.contains(query) ||
            diagnosis.contains(query) ||
            patientId.contains(query);
      }).toList();
    }

    // Apply status filters
    if (_statusFilters.isNotEmpty) {
      list = list.where((r) {
        return _statusFilters.any((f) => f.matches(r));
      }).toList();
    }

    // Apply date range filter
    if (_dateRange != null) {
      list = list.where((r) {
        final createdAt = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
        return createdAt.isAfter(_dateRange!.start.subtract(const Duration(days: 1))) &&
            createdAt.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }
    
    // Dynamic sorting based on selected option
    final sortedList = _sortReferrals(list, patients);

    // Mark initial load complete
    if (_isInitialLoad) {
      _isInitialLoad = false;
    }
    
    return _DashboardData(
      referrals: sortedList,
      patients: patients,
      counts: perLevel,
      events: events,
      criticalCount: counts.critical,
      activeCount: counts.active,
      lastSyncedAt: await sync.lastSyncedAt(),
    );
  }

  /// Dynamic sorting for triage board ordering.
  /// Priority: SLA severity > Clinical risk > Delay duration > Programme > AI score
  List<Referral> _sortReferrals(List<Referral> referrals, Map<String, Patient> patients) {
    final now = DateTime.now();
    return List.from(referrals)..sort((a, b) {
      switch (_sortOption) {
        case ReferralSortOption.priorityDesc:
          return _comparePriority(a, b, patients, now, ascending: false);
        case ReferralSortOption.priorityAsc:
          return _comparePriority(a, b, patients, now, ascending: true);
        case ReferralSortOption.dateDesc:
          return b.createdAt.compareTo(a.createdAt);
        case ReferralSortOption.dateAsc:
          return a.createdAt.compareTo(b.createdAt);
        case ReferralSortOption.patientName:
          final aName = patients[a.patientId]?.name ?? '';
          final bName = patients[b.patientId]?.name ?? '';
          return aName.compareTo(bName);
        case ReferralSortOption.urgency:
          return a.slaTier.index.compareTo(b.slaTier.index);
      }
    });
  }

  int _comparePriority(Referral a, Referral b, Map<String, Patient> patients, 
      DateTime now, {required bool ascending}) {
    // 1. SLA severity (breached first, then by priority level)
    final aBreached = a.breachedSince != null;
    final bBreached = b.breachedSince != null;
    if (aBreached != bBreached) {
      final result = aBreached ? -1 : 1;
      return ascending ? -result : result;
    }
    
    // 2. Priority level (critical > high > medium > low)
    final aPriority = SlaPriority.fromWireTag(a.priorityLevel);
    final bPriority = SlaPriority.fromWireTag(b.priorityLevel);
    var priorityCompare = aPriority.index.compareTo(bPriority.index);
    if (priorityCompare != 0) return ascending ? -priorityCompare : priorityCompare;
    
    // 3. Clinical risk (emergency tier > urgent > routine)
    final tierCompare = a.slaTier.index.compareTo(b.slaTier.index);
    if (tierCompare != 0) return ascending ? -tierCompare : tierCompare;
    
    // 4. Delay duration (longer delay first)
    final aDelay = _calculateDelay(a, now);
    final bDelay = _calculateDelay(b, now);
    var delayCompare = bDelay.compareTo(aDelay);
    if (delayCompare != 0) return ascending ? -delayCompare : delayCompare;
    
    // 5. AI risk score from patient (higher score first)
    final aRisk = patients[a.patientId]?.riskScore ?? 0;
    final bRisk = patients[b.patientId]?.riskScore ?? 0;
    var riskCompare = bRisk.compareTo(aRisk);
    if (riskCompare != 0) return ascending ? -riskCompare : riskCompare;
    
    // 6. Priority score as tiebreaker
    final aScore = a.priorityScore ?? 0;
    final bScore = b.priorityScore ?? 0;
    var scoreCompare = bScore.compareTo(aScore);
    return ascending ? -scoreCompare : scoreCompare;
  }

  int _calculateDelay(Referral r, DateTime now) {
    if (r.breachedSince != null) {
      return now.difference(
        DateTime.fromMillisecondsSinceEpoch(r.breachedSince!)
      ).inMinutes;
    }
    final dueAt = r.dueArrivalAt ?? r.dueTreatmentAt;
    if (dueAt != null) {
      final due = DateTime.fromMillisecondsSinceEpoch(dueAt);
      if (now.isAfter(due)) {
        return now.difference(due).inMinutes;
      }
    }
    return 0;
  }

  Future<void> _syncNow() async {
    final sync = _sync;
    final repo = _repo;
    if (sync == null || repo == null) return;
    if (_isOffline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You\'re offline. Actions will sync when connected.')),
        );
      }
      return;
    }
    final report = await sync.warmSync();
    if (!mounted) return;
    await repo.recomputeAllAfterSync();
    await repo.dispatchPendingNotifications();
    if (!mounted) return;
    final msg = report.errors.isNotEmpty
        ? ReferralStrings.loadFailed
        : 'Synced successfully';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Bulk Action Handlers ────────────────────────────────────────────────────

  void _toggleSelection(String referralId) {
    setState(() {
      if (_selectedIds.contains(referralId)) {
        _selectedIds.remove(referralId);
      } else {
        _selectedIds.add(referralId);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  void _selectAll(List<Referral> referrals) {
    setState(() {
      _selectedIds = referrals.map((r) => r.id).toSet();
    });
  }

  Future<void> _bulkEscalate() async {
    final confirmed = await BulkActionConfirmDialog.show(
      context,
      title: 'Escalate Referrals',
      message: 'This will escalate the selected referrals to the next supervisor level.',
      confirmLabel: 'Escalate',
      count: _selectedIds.length,
    );
    if (!confirmed || !mounted) return;

    final count = await _repo?.bulkEscalate(
      referralIds: _selectedIds.toList(),
      reason: 'Bulk escalation by SK',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count referrals escalated')),
      );
      _clearSelection();
      _reload();
    }
  }

  Future<void> _bulkClose() async {
    final confirmed = await BulkActionConfirmDialog.show(
      context,
      title: 'Close Cases',
      message: 'This will mark the selected referrals as completed.',
      confirmLabel: 'Close Cases',
      count: _selectedIds.length,
    );
    if (!confirmed || !mounted) return;

    final count = await _repo?.bulkClose(
      referralIds: _selectedIds.toList(),
      reason: 'Bulk closure by SK',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count cases closed')),
      );
      _clearSelection();
      _reload();
    }
  }

  Future<void> _bulkExport() async {
    // For now, show a message. In production, this would generate a report.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting ${_selectedIds.length} referrals...'),
      ),
    );
    // TODO: Implement CSV/PDF export
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export complete')),
      );
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<LeapfrogColors>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _clearSelection,
              tooltip: 'Cancel selection',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Visits'),
            Tab(text: 'Referrals'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Visits (Mission Queue Items)
          _buildVisitsTab(scheme, tokens),
          // Tab 2: Referrals (existing referral list)
          _buildReferralsTab(scheme),
        ],
      ),
    );
  }

  /// Build the Visits tab showing mission queue items sorted by tier priority.
  Widget _buildVisitsTab(ColorScheme scheme, LeapfrogColors? tokens) {
    return FutureBuilder<List<MissionQueueItem>>(
      future: _missionQueueFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorState(
            message: 'Failed to load visits: ${snap.error}',
            onRetry: _reload,
          );
        }
        final allQueue = snap.data ?? const <MissionQueueItem>[];

        // Extract distinct village names for the inline chip row
        final villageNames = allQueue
            .map((i) => i.village?.trim())
            .whereType<String>()
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

        // Apply inline village filter first
        final villageFiltered = _selectedVisitVillage != null
            ? allQueue
                .where((item) => item.village?.trim() == _selectedVisitVillage)
                .toList()
            : allQueue;

        // Apply tier / completed filters on top of village filter
        List<MissionQueueItem> queue;
        if (_showCompletedOnly) {
          queue = villageFiltered
              .where((item) => _completedPatientIds.contains(item.patientId))
              .toList();
        } else if (_visitTierFilter == null) {
          queue = villageFiltered;
        } else {
          final filter = _visitTierFilter!;
          final dateBased = filter == DashboardTier.dueToday ||
              filter == DashboardTier.thisWeek ||
              filter == DashboardTier.upcoming;
          queue = villageFiltered
              .where((item) {
                // Date chips keep completed-today patients whose next due
                // still falls in that window (Done cards). Critical/Overdue
                // chips stay actionable-only.
                if (!dateBased &&
                    _completedPatientIds.contains(item.patientId)) {
                  return false;
                }
                return DashboardTier.matchesVisitFilter(
                  filter: filter,
                  itemTier: item.tier,
                  dueAt: item.dueAt,
                );
              })
              .toList();
        }

        // Determine empty state message
        String emptyTitle;
        String emptySubtitle;
        VoidCallback? clearAction;
        if (_showCompletedOnly) {
          emptyTitle = 'No Completed Visits Today';
          emptySubtitle = 'Complete patient assessments to see them here.';
          clearAction = () => setState(() => _showCompletedOnly = false);
        } else if (_visitTierFilter != null) {
          emptyTitle = 'No ${MissionDashboardStrings.tierLabel(_visitTierFilter!)} Visits';
          emptySubtitle = 'No patients in this priority tier.';
          clearAction = () => setState(() => _visitTierFilter = null);
        } else {
          emptyTitle = 'No Visits Scheduled';
          emptySubtitle = 'All patients are up to date. Pull to refresh.';
          clearAction = null;
        }

        return Column(
          children: [
            // Village chip row (only shown when >1 village in the queue)
            if (villageNames.length > 1)
              _buildVisitVillageChipRow(villageNames),
            // Tier filter chip row
            _buildVisitTierChipRow(villageFiltered),
            // Main list
            Expanded(
              child: queue.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _syncNow,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          ReferralEmptyState(
                            title: emptyTitle,
                            subtitle: emptySubtitle,
                            icon: _showCompletedOnly 
                                ? Icons.check_circle_rounded 
                                : Icons.check_circle_outline_rounded,
                            actionLabel: clearAction != null ? 'Clear Filter' : null,
                            onAction: clearAction,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _syncNow,
                      child: _buildVisitList(queue),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Village chip row — "WHICH VILLAGE ARE YOU VISITING?" — Visits tab.
  Widget _buildVisitVillageChipRow(List<String> villageNames) {
    final scheme = Theme.of(context).colorScheme;
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                VillageFilterTab(
                  label: MissionDashboardStrings.allVillages,
                  isActive: _selectedVisitVillage == null,
                  onTap: () => setState(() => _selectedVisitVillage = null),
                ),
                ...villageNames.map((v) => VillageFilterTab(
                      label: v,
                      isActive: _selectedVisitVillage == v,
                      onTap: () => setState(() {
                        _selectedVisitVillage =
                            _selectedVisitVillage == v ? null : v;
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

  /// Build tier filter chip row for Visits tab.
  Widget _buildVisitTierChipRow(List<MissionQueueItem> allQueue) {
    final scheme = Theme.of(context).colorScheme;
    
    // Critical/Overdue counts = pending only (clinical).
    // Today / This week / Upcoming = date schedule (includes visited-today
    // with next due still in that window).
    final pendingQueue = allQueue
        .where((item) => !_completedPatientIds.contains(item.patientId))
        .toList();
    final counts = <DashboardTier?, int>{null: pendingQueue.length};
    for (final tier in DashboardTier.values) {
      final dateBased = tier == DashboardTier.dueToday ||
          tier == DashboardTier.thisWeek ||
          tier == DashboardTier.upcoming;
      final pool = dateBased ? allQueue : pendingQueue;
      counts[tier] = pool
          .where(
            (item) => DashboardTier.matchesVisitFilter(
              filter: tier,
              itemTier: item.tier,
              dueAt: item.dueAt,
            ),
          )
          .length;
    }
    final completedCount = _completedPatientIds.length;
    
    final tiers = [null, ...DashboardTier.values];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Tier chips
            ...tiers.map((tier) {
              final isSelected = !_showCompletedOnly && _visitTierFilter == tier;
              final label = tier == null
                  ? 'All'
                  : MissionDashboardStrings.tierLabel(tier);
              final count = counts[tier] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: VisitTierChip(
                  label: label,
                  count: count,
                  tier: tier,
                  isSelected: isSelected,
                  onTap: () => setState(() {
                    _showCompletedOnly = false;
                    _visitTierFilter = tier;
                  }),
                ),
              );
            }),
            // Completed Today chip
            _CompletedTodayChip(
              count: completedCount,
              isSelected: _showCompletedOnly,
              onTap: () => setState(() {
                _showCompletedOnly = !_showCompletedOnly;
                if (_showCompletedOnly) {
                  _visitTierFilter = null; // Clear tier filter when showing completed
                }
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the visit list with tier headers.
  Widget _buildVisitList(List<MissionQueueItem> queue) {
    // If showing completed only, display simple list without headers
    if (_showCompletedOnly) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: queue.length,
        itemBuilder: (context, index) {
          final item = queue[index];
          return MissionQueueCard(
            item: item,
            isCompleted: true,
            onTap: () => _handleVisitTap(item), // Allow tapping to view
            onAction: null, // No action for completed
          );
        },
      );
    }
    
    // If filtered to a single tier, don't show headers
    if (_visitTierFilter != null) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: queue.length,
        itemBuilder: (context, index) {
          final item = queue[index];
          final isCompleted = _completedPatientIds.contains(item.patientId);
          return MissionQueueCard(
            item: item,
            isCompleted: isCompleted,
            onTap: isCompleted ? null : () => _handleVisitTap(item),
            onAction: isCompleted ? null : () => _handleVisitAction(item),
          );
        },
      );
    }

    // Group by tier for display, but handle completed items separately
    // Completed items are already sorted to bottom by _loadMissionQueue
    final grouped = <DashboardTier, List<MissionQueueItem>>{};
    final completedItems = <MissionQueueItem>[];
    
    for (final item in queue) {
      if (_completedPatientIds.contains(item.patientId)) {
        completedItems.add(item);
      } else {
        grouped.putIfAbsent(item.tier, () => []).add(item);
      }
    }

    // Calculate total item count (tiers with items + their items + completed header + completed items)
    int totalCount = 0;
    for (final tier in DashboardTier.values) {
      if (grouped[tier]?.isNotEmpty == true) {
        totalCount += 1 + grouped[tier]!.length; // header + items
      }
    }
    if (completedItems.isNotEmpty) {
      totalCount += 1 + completedItems.length; // completed header + items
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // Build list with tier headers
        int itemIndex = 0;
        for (final tier in DashboardTier.values) {
          final items = grouped[tier];
          if (items == null || items.isEmpty) continue;
          
          // Header
          if (index == itemIndex) {
            return MissionTierHeader(tier: tier, count: items.length);
          }
          itemIndex++;
          
          // Items
          for (int i = 0; i < items.length; i++) {
            if (index == itemIndex) {
              return MissionQueueCard(
                item: items[i],
                isCompleted: false,
                onTap: () => _handleVisitTap(items[i]),
                onAction: () => _handleVisitAction(items[i]),
              );
            }
            itemIndex++;
          }
        }
        
        // Completed section
        if (completedItems.isNotEmpty) {
          // Completed header
          if (index == itemIndex) {
            return CompletedTierHeader(count: completedItems.length);
          }
          itemIndex++;
          
          // Completed items
          for (int i = 0; i < completedItems.length; i++) {
            if (index == itemIndex) {
              return MissionQueueCard(
                item: completedItems[i],
                isCompleted: true,
                onTap: null,
                onAction: null,
              );
            }
            itemIndex++;
          }
        }
        
        return const SizedBox.shrink();
      },
    );
  }

  /// Handle tap on a visit card - navigate to patient.
  void _handleVisitTap(MissionQueueItem item) {
    if (item.patientId != null) {
      context.push('/patient/${item.patientId}?origin=tasks');
    }
  }

  /// Handle action button on a visit card - start visit.
  Future<void> _handleVisitAction(MissionQueueItem item) async {
    if (item.patientId == null) return;
    try {
      final visitController = context.read<VisitController>();
      final encounterId = await startOrResumeVisit(
        context,
        controller: visitController,
        patientId: item.patientId!,
        programme: item.primaryProgramme,
        patientName: item.patientName,
        patientAge: item.age,
        householdId: item.householdId,
      );
      if (!mounted) return;
      if (encounterId != null) {
        context.push(
          '/patients/visit/$encounterId/flow?origin=tasks',
          extra: {
            'patientId': item.patientId,
            'patientName': item.patientName,
            'householdId': item.householdId,
            'patientAge': item.age,
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(visitController.error ?? 'Failed to start visit')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start visit: $e')),
      );
    }
  }

  /// Build the Referrals tab (existing referral list).
  Widget _buildReferralsTab(ColorScheme scheme) {
    return FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snap) {
          // Show loading skeleton on initial load
          if (_isInitialLoad && snap.connectionState == ConnectionState.waiting) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search bar placeholder
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const Expanded(child: ReferralLoadingSkeleton()),
              ],
            );
          }
          if (snap.hasError) {
            return _ErrorState(message: snap.error.toString(), onRetry: _reload);
          }
          final data = snap.data ?? _DashboardData(
            referrals: const [],
            patients: const {},
            counts: const {},
            events: const {},
            criticalCount: 0,
            activeCount: 0,
            lastSyncedAt: null,
          );
          final top = data.referrals.firstOrNull;
          final topIsCritical = top != null &&
              SlaPriority.fromWireTag(top.priorityLevel) ==
                  SlaPriority.critical;

          return Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Offline indicator
                  if (_isOffline)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: OfflineIndicator(
                        pendingActions: _pendingActions,
                        onRetry: _syncNow,
                      ),
                    ),

                  // Search and filter bar
                  ReferralSearchFilterBar(
                    searchText: _searchQuery,
                    selectedStatuses: _statusFilters,
                    selectedSort: _sortOption,
                    dateRange: _dateRange,
                    onSearchChanged: (query) {
                      setState(() => _searchQuery = query);
                      _reload();
                    },
                    onStatusFilterChanged: (filters) {
                      setState(() => _statusFilters = filters);
                      _reload();
                    },
                    onDateRangeChanged: (range) {
                      setState(() => _dateRange = range);
                      _reload();
                    },
                    onSortChanged: (sort) {
                      setState(() => _sortOption = sort);
                      _reload();
                    },
                  ),

                  // Priority chip row
                  PriorityChipRow(
                    selected: _filter,
                    onChanged: (v) {
                      setState(() => _filter = v);
                      _reload();
                    },
                    counts: data.counts,
                  ),

                  // SLA strip
                  SlaStrip(
                    lastSyncedAt: data.lastSyncedAt,
                    breachCount: data.referrals
                        .where((r) => r.breachedSince != null)
                        .length,
                    escalationsPending: data.referrals
                        .where((r) => r.escalationLevel > 0)
                        .length,
                    onSyncNow: _syncNow,
                  ),

                  // Critical banner
                  if (top != null && topIsCritical && !_isSelectionMode)
                    CriticalBanner(
                      patientName: data.patients[top.patientId]?.name ?? '—',
                      referral: top,
                    ),

                  // Main list
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _syncNow,
                      child: data.referrals.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                ReferralEmptyState(
                                  title: _searchQuery.isNotEmpty || 
                                         _statusFilters.isNotEmpty ||
                                         _dateRange != null
                                      ? 'No Matching Referrals'
                                      : ReferralStrings.emptyTitle,
                                  subtitle: _searchQuery.isNotEmpty || 
                                            _statusFilters.isNotEmpty ||
                                            _dateRange != null
                                      ? 'Try adjusting your filters or search terms.'
                                      : ReferralStrings.emptyBody,
                                  icon: _searchQuery.isNotEmpty
                                      ? Icons.search_off_rounded
                                      : Icons.folder_open_rounded,
                                  actionLabel: _searchQuery.isNotEmpty || 
                                               _statusFilters.isNotEmpty ||
                                               _dateRange != null
                                      ? 'Clear Filters'
                                      : null,
                                  onAction: _searchQuery.isNotEmpty || 
                                            _statusFilters.isNotEmpty ||
                                            _dateRange != null
                                      ? () {
                                          setState(() {
                                            _searchQuery = '';
                                            _statusFilters = {};
                                            _dateRange = null;
                                          });
                                          _reload();
                                        }
                                      : null,
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.only(
                                bottom: _isSelectionMode ? 120 : 16,
                              ),
                              itemCount: data.referrals.length,
                              itemBuilder: (context, i) {
                                final r = data.referrals[i];
                                final patient = data.patients[r.patientId];
                                final events = data.events[r.id] ?? const [];
                                final card = TriageReferralCard(
                                  referral: r,
                                  patient: patient,
                                  events: events,
                                  onTap: _isSelectionMode
                                      ? () => _toggleSelection(r.id)
                                      : () => _handleOpenReferral(r),
                                  onCallFamily: () => _handleCallFamily(r, patient),
                                  onUpdateStatus: () => _handleUpdateStatus(r),
                                  onLocate: () => _handleLocate(r, patient),
                                  onEscalate: () => _handleEscalate(r),
                                  onCallFacility: () => _handleCallFacility(r),
                                  onUpdateQueue: () => _handleUpdateQueue(r),
                                  onOpenReferral: () => _handleOpenReferral(r),
                                  onViewPrescription: () => _handleViewPrescription(r, patient),
                                  onScheduleFollowUp: () => _handleScheduleFollowUp(r, patient),
                                  onSendReminder: () => _handleSendReminder(r, patient),
                                  onCloseCase: () => _handleCloseCase(r),
                                );
                                return SelectableReferralCard(
                                  referralId: r.id,
                                  isSelected: _selectedIds.contains(r.id),
                                  isSelectionMode: _isSelectionMode,
                                  onToggleSelection: () => _toggleSelection(r.id),
                                  child: card,
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),

              // Bulk actions bar (positioned at bottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BulkActionsBar(
                  selectedIds: _selectedIds,
                  referrals: data.referrals,
                  onClearSelection: _clearSelection,
                  onSelectAll: () => _selectAll(data.referrals),
                  onBulkEscalate: _bulkEscalate,
                  onBulkClose: _bulkClose,
                  onBulkExport: _bulkExport,
                ),
              ),
            ],
          );
        },
      );
  }

  // ── Action Handlers ─────────────────────────────────────────────────────────

  void _handleCallFamily(Referral r, Patient? patient) {
    final phone = patient?.phone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ReferralStrings.errorNoPhone)),
      );
      return;
    }
    _showContactOptionsSheet(
      phone: phone,
      name: patient?.name ?? 'Patient',
      referral: r,
      patient: patient,
    );
  }

  void _showContactOptionsSheet({
    required String phone,
    required String name,
    Referral? referral,
    Patient? patient,
  }) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ReferralStrings.contactSheetTitle(name),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                phone,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.phone, color: scheme.primary),
                title: const Text(ReferralStrings.contactCall),
                subtitle: const Text(ReferralStrings.contactCallSubtitle),
                onTap: () {
                  Navigator.pop(ctx);
                  _launchPhoneDialer(phone);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.message,
                  color: Theme.of(context).extension<LeapfrogColors>()!.whatsapp,
                ),
                title: const Text(ReferralStrings.contactWhatsApp),
                subtitle: const Text(ReferralStrings.contactWhatsAppSubtitle),
                onTap: () {
                  Navigator.pop(ctx);
                  _launchWhatsApp(phone, _buildContactMessage(name, referral, patient));
                },
              ),
              ListTile(
                leading: Icon(Icons.sms, color: scheme.tertiary),
                title: const Text(ReferralStrings.contactSms),
                subtitle: const Text(ReferralStrings.contactSmsSubtitle),
                onTap: () {
                  Navigator.pop(ctx);
                  _launchSms(phone, _buildContactMessage(name, referral, patient));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildContactMessage(String name, Referral? referral, Patient? patient) {
    final buffer = StringBuffer();
    buffer.write(ReferralStrings.msgGreeting(name));
    buffer.write(ReferralStrings.msgIntro);
    
    if (referral != null) {
      if (referral.diagnosisLabel != null && referral.diagnosisLabel!.isNotEmpty) {
        buffer.write(ReferralStrings.msgReferralFor(referral.diagnosisLabel!));
      } else {
        buffer.write(ReferralStrings.msgReferralGeneric);
      }
      
      // Add status-specific message
      if (referral.breachedSince != null) {
        buffer.write(ReferralStrings.msgOverdue);
      } else if (referral.state == ReferralStatus.created || referral.state == ReferralStatus.acknowledged) {
        buffer.write(ReferralStrings.msgNewReferral);
      } else if (referral.state == ReferralStatus.arrived || referral.state == ReferralStatus.treatmentStarted) {
        buffer.write(ReferralStrings.msgInTreatment);
      } else if (referral.state.isClosed) {
        buffer.write(ReferralStrings.msgCompleted);
      }
    } else {
      buffer.write(ReferralStrings.msgGenericOutreach);
    }
    
    buffer.write(ReferralStrings.msgClosing);
    
    return buffer.toString();
  }

  Future<void> _launchPhoneDialer(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ReferralStrings.errorPhoneDialer)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ReferralStrings.errorOpening('phone', '$e'))),
        );
      }
    }
  }

  Future<void> _launchWhatsApp(String phone, String message) async {
    // Remove any non-digit characters and ensure country code
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final encodedMessage = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ReferralStrings.errorWhatsApp)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ReferralStrings.errorOpening('WhatsApp', '$e'))),
        );
      }
    }
  }

  Future<void> _launchSms(String phone, String message) async {
    // Use query parameters for SMS body - works on both Android and iOS
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ReferralStrings.errorSms)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ReferralStrings.errorOpening('SMS', '$e'))),
        );
      }
    }
  }

  void _handleUpdateStatus(Referral r) {
    _showStatusUpdateSheet(r);
  }

  void _handleLocate(Referral r, Patient? patient) {
    // Try to get location from patient's raw JSON or household
    final patientName = patient?.name ?? 'Patient';
    final villageId = patient?.villageId;
    
    // For demo, open Google Maps with a search for the patient's village or general area
    // In production, use actual lat/lng coordinates from patient data
    _showLocationSheet(patientName, villageId);
  }

  void _showLocationSheet(String patientName, String? villageId) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ReferralStrings.locateSheetTitle(patientName),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.map, color: scheme.primary),
                title: const Text(ReferralStrings.locateOpenMaps),
                subtitle: const Text(ReferralStrings.locateOpenMapsSubtitle),
                onTap: () {
                  Navigator.pop(ctx);
                  _launchGoogleMaps(patientName, villageId);
                },
              ),
              ListTile(
                leading: Icon(Icons.directions, color: scheme.tertiary),
                title: const Text(ReferralStrings.locateGetDirections),
                subtitle: const Text(ReferralStrings.locateGetDirectionsSubtitle),
                onTap: () {
                  Navigator.pop(ctx);
                  _launchGoogleMapsDirections(patientName, villageId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchGoogleMaps(String patientName, String? villageId) async {
    // In production, use actual coordinates. For now, search by name/village
    final query = villageId != null 
        ? 'Village $villageId, Bangladesh' 
        : patientName;
    
    // Try geo: scheme first (works with any maps app on Android)
    final geoUri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}');
    try {
      final geoLaunched = await launchUrl(geoUri);
      if (geoLaunched) return;
    } catch (_) {
      // geo: not supported, try web fallback
    }
    
    // Fallback to web URL (opens in browser)
    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    try {
      final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ReferralStrings.errorMaps)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ReferralStrings.errorOpening('maps', '$e'))),
        );
      }
    }
  }

  Future<void> _launchGoogleMapsDirections(String patientName, String? villageId) async {
    final destination = villageId != null 
        ? 'Village $villageId, Bangladesh' 
        : patientName;
    
    // Try geo: scheme for directions (limited support)
    final geoUri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(destination)}');
    try {
      final geoLaunched = await launchUrl(geoUri);
      if (geoLaunched) return;
    } catch (_) {
      // geo: not supported, try web fallback
    }
    
    // Fallback to web URL
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}',
    );
    try {
      final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ReferralStrings.errorMaps)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ReferralStrings.errorOpening('maps', '$e'))),
        );
      }
    }
  }

  void _handleEscalate(Referral r) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.trending_up_rounded,
                color: Theme.of(ctx).colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Escalate Referral'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will escalate to Level ${r.escalationLevel + 1} supervisor.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Enter escalation reason...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Escalate'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final success = await _repo?.escalate(
        referralId: r.id,
        reason: reasonController.text.isEmpty 
            ? null 
            : reasonController.text,
        actor: 'sk',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success == true 
                ? 'Referral escalated to Level ${r.escalationLevel + 1}'
                : 'Failed to escalate referral'),
          ),
        );
        _reload();
      }
    }
  }

  void _handleCallFacility(Referral r) {
    // Try to get facility phone from referral raw JSON
    // In production, fetch from facility metadata via ReferralApiService
    const facilityPhone = '+8801700000000';
    _showContactOptionsSheet(
      phone: facilityPhone,
      name: 'Health Facility',
      referral: r,
    );
  }

  void _handleUpdateQueue(Referral r) {
    _showQueueUpdateSheet(r);
  }

  void _handleOpenReferral(Referral r) {
    context.push('/patient/${r.patientId}/referrals');
  }

  Future<void> _handleViewPrescription(Referral r, Patient? patient) async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading prescriptions...'),
          ],
        ),
        duration: Duration(seconds: 1),
      ),
    );

    // For demo, create sample prescriptions
    // In production, fetch via ReferralApiService.fetchPrescriptions()
    final prescriptions = <Prescription>[
      Prescription(
        id: '1',
        medicationName: 'Amoxicillin',
        dosage: '500mg',
        frequency: '3 times daily',
        duration: '7',
        prescribedAt: DateTime.now().subtract(const Duration(days: 5)),
        prescribedBy: 'Dr. Rahman',
        instructions: 'Take with food. Complete full course.',
        isActive: true,
      ),
      Prescription(
        id: '2',
        medicationName: 'Paracetamol',
        dosage: '500mg',
        frequency: 'As needed',
        duration: '5',
        prescribedAt: DateTime.now().subtract(const Duration(days: 5)),
        prescribedBy: 'Dr. Rahman',
        instructions: 'For fever. Maximum 4 doses per day.',
        isActive: true,
      ),
      if (r.diagnosisCode?.startsWith('E11') ?? false)
        Prescription(
          id: '3',
          medicationName: 'Metformin',
          dosage: '500mg',
          frequency: 'Twice daily',
          duration: '30',
          prescribedAt: DateTime.now().subtract(const Duration(days: 30)),
          prescribedBy: 'Dr. Kamal',
          instructions: 'Take with meals.',
          isActive: true,
        ),
    ];

    if (!mounted) return;

    await PrescriptionViewer.show(
      context,
      prescriptions: prescriptions,
      patientName: patient?.name ?? 'Patient',
      onShare: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing prescription...')),
        );
      },
    );
  }

  Future<void> _handleScheduleFollowUp(Referral r, Patient? patient) async {
    final followUpCalls = context.read<FollowUpCallService>();
    final success = await FollowUpScheduler.show(
      context,
      referralId: r.id,
      patientName: patient?.name ?? 'Patient',
      existingFollowUpDate: r.dueTreatmentAt != null
          ? DateTime.fromMillisecondsSinceEpoch(r.dueTreatmentAt!)
          : null,
      onSchedule: (date, type, notes) async {
        // Persist a real local follow-up (backend accepts a null-id follow-up
        // as a create; it pushes on the next offline-sync cycle and shows in
        // the patient's Open Follow-ups). Replaces the former no-op stub.
        try {
          await followUpCalls.scheduleLocal(
            patientId: r.patientId,
            dueDate: date,
            type: type ?? 'MEDICAL_REVIEW',
            reason: notes,
            referredSiteId: r.diagnosisCode,
          );
        } catch (e) {
          debugPrint('[Referral] scheduleLocal failed: $e');
          return false;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Follow-up scheduled for ${date.day}/${date.month}/${date.year}',
              ),
            ),
          );
        }
        return true;
      },
    );

    if (success == true && mounted) {
      _reload();
    }
  }

  void _handleSendReminder(Referral r, Patient? patient) {
    final phone = patient?.phone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ReferralStrings.errorNoPhone)),
      );
      return;
    }
    _showContactOptionsSheet(
      phone: phone,
      name: patient?.name ?? 'Patient',
      referral: r,
      patient: patient,
    );
  }

  void _handleCloseCase(Referral r) async {
    final outcomeController = TextEditingController();
    ReferralStatus selectedOutcome = ReferralStatus.closedRecovered;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Close Case'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select outcome:'),
              const SizedBox(height: 12),
              SegmentedButton<ReferralStatus>(
                segments: const [
                  ButtonSegment(
                    value: ReferralStatus.closedRecovered,
                    label: Text('Recovered'),
                    icon: Icon(Icons.check_circle_outline),
                  ),
                  ButtonSegment(
                    value: ReferralStatus.closedDeceased,
                    label: Text('Deceased'),
                    icon: Icon(Icons.cancel_outlined),
                  ),
                ],
                selected: {selectedOutcome},
                onSelectionChanged: (selected) {
                  setDialogState(() {
                    selectedOutcome = selected.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: outcomeController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Enter closure notes...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.primary,
              ),
              child: const Text('Close Case'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await _repo?.transition(
        referralId: r.id,
        to: selectedOutcome,
        actor: 'sk',
        reason: outcomeController.text.isEmpty 
            ? 'Case closed by SK'
            : outcomeController.text,
      );
      _reload();
    }
  }

  void _showStatusUpdateSheet(Referral r) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final nextStates = _getValidNextStates(r.state);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update Status',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                for (final state in nextStates)
                  ListTile(
                    leading: Icon(_iconForState(state), color: scheme.primary),
                    title: Text(_labelForState(state)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _repo?.transition(
                        referralId: r.id,
                        to: state,
                        actor: 'sk',
                      );
                      if (mounted) _reload();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showQueueUpdateSheet(Referral r) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update Queue Status',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: const Text('Treatment Started'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _repo?.transition(
                      referralId: r.id,
                      to: ReferralStatus.treatmentStarted,
                      actor: 'sk',
                    );
                    if (mounted) _reload();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Discharged - Recovered'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _repo?.transition(
                      referralId: r.id,
                      to: ReferralStatus.closedRecovered,
                      actor: 'sk',
                    );
                    if (mounted) _reload();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<ReferralStatus> _getValidNextStates(ReferralStatus current) {
    switch (current) {
      case ReferralStatus.created:
        return [ReferralStatus.acknowledged, ReferralStatus.inTransit, ReferralStatus.refused];
      case ReferralStatus.acknowledged:
        return [ReferralStatus.inTransit, ReferralStatus.arrived];
      case ReferralStatus.inTransit:
        return [ReferralStatus.arrived, ReferralStatus.transportDeclined];
      case ReferralStatus.arrived:
        return [ReferralStatus.treatmentStarted];
      case ReferralStatus.treatmentStarted:
        return [ReferralStatus.closedRecovered, ReferralStatus.closedDeceased];
      default:
        return [];
    }
  }

  IconData _iconForState(ReferralStatus s) {
    switch (s) {
      case ReferralStatus.acknowledged:
        return Icons.check_outlined;
      case ReferralStatus.inTransit:
        return Icons.directions_car_outlined;
      case ReferralStatus.arrived:
        return Icons.location_on_outlined;
      case ReferralStatus.treatmentStarted:
        return Icons.medical_services_outlined;
      case ReferralStatus.closedRecovered:
        return Icons.check_circle_outlined;
      case ReferralStatus.closedDeceased:
        return Icons.cancel_outlined;
      case ReferralStatus.refused:
        return Icons.block_outlined;
      case ReferralStatus.transportDeclined:
        return Icons.no_transfer_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  String _labelForState(ReferralStatus s) {
    switch (s) {
      case ReferralStatus.acknowledged:
        return 'Acknowledged';
      case ReferralStatus.inTransit:
        return 'In Transit';
      case ReferralStatus.arrived:
        return 'Arrived at Facility';
      case ReferralStatus.treatmentStarted:
        return 'Treatment Started';
      case ReferralStatus.closedRecovered:
        return 'Discharged - Recovered';
      case ReferralStatus.closedDeceased:
        return 'Deceased';
      case ReferralStatus.refused:
        return 'Patient Refused';
      case ReferralStatus.transportDeclined:
        return 'Transport Declined';
      default:
        return s.wireTag;
    }
  }

}

class _DashboardData {
  const _DashboardData({
    required this.referrals,
    required this.patients,
    required this.counts,
    required this.events,
    required this.criticalCount,
    required this.activeCount,
    required this.lastSyncedAt,
  });

  final List<Referral> referrals;
  final Map<String, Patient> patients;
  final Map<SlaPriority, int> counts;
  final Map<String, List<ReferralStatusEventRow>> events;
  final int criticalCount;
  final int activeCount;
  final DateTime? lastSyncedAt;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 56),
            const SizedBox(height: 16),
            Text(ReferralStrings.loadFailed,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 22),
              label: Text(
                CommonStrings.retry,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip for filtering to completed visits today.
class _CompletedTodayChip extends StatelessWidget {
  const _CompletedTodayChip({
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<LeapfrogColors>()!;
    final color = tokens.statusSuccess;
    return Semantics(
      label: isSelected ? 'Show completed visits, selected' : 'Show completed visits',
      button: true,
      child: GestureDetector(
      key: const Key('referral_status_filter_tap'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Completed',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
                  ),
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

