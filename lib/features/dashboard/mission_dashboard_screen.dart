import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/local_dashboard_repository.dart';
import '../../core/models/mission_brief.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/sync/offline_sync_service.dart';
import '../referral/referral_repository.dart';
import '../search/global_search_bar.dart';
import 'dashboard_repository.dart';
import 'mission_dashboard_repository.dart';
import 'widgets/ai_brief_card.dart';
import 'widgets/critical_alert_banner.dart';
import 'widgets/follow_ups_due_widget.dart';
import 'widgets/household_opportunities_widget.dart';
import 'widgets/mission_progress_card.dart';
import 'widgets/mission_queue_card.dart';
import 'widgets/referral_operations_widget.dart';

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
  
  // Community stats futures (from old dashboard)
  late Future<int> _memberFuture;
  late Future<int> _householdFuture;

  // Mission data futures
  Future<MissionBrief>? _briefFuture;
  Future<MissionProgress>? _progressFuture;
  Future<List<MissionQueueItem>>? _queueFuture;
  Future<List<MissionQueueItem>>? _alertsFuture;
  Future<ReferralSummary>? _referralSummaryFuture;
  Future<List<FollowUpDue>>? _followUpsFuture;
  Future<List<HouseholdOpportunity>>? _opportunitiesFuture;

  @override
  void initState() {
    super.initState();
    _reloadStats();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthState>();
      await _loadSummary(auth);
      // Trigger offline sync to populate local SQLite with referrals/worklist
      await _triggerSync();
      _loadMissionData();
    });
  }

  /// Trigger offline sync to populate local SQLite for mission data.
  Future<void> _triggerSync() async {
    if (!mounted) return;
    try {
      final sync = context.read<OfflineSyncService>();
      final report = await sync.coldSync();
      debugPrint('[Dashboard] Sync completed: patients=${report.patients}, referrals=${report.referrals}');
    } catch (e) {
      debugPrint('[Dashboard] Sync failed: $e');
    }
  }

  Future<void> _loadSummary(AuthState auth) async {
    if (!mounted) return;
    final s = await auth.userProfileSummary();
    if (!mounted) return;
    setState(() => _summary = s);
  }

  void _reloadStats() {
    // Try local-first for instant response (no network latency)
    final localRepo = context.read<LocalDashboardRepository>();
    final apiRepo = context.read<DashboardRepository>();
    final authRepo = context.read<AuthRepository>();
    
    final countsFuture = localRepo.householdAndMemberCount().then((local) async {
      // If local has data, use it (instant)
      if (local.households > 0) {
        debugPrint('[Dashboard] Using local counts: ${local.households} households, ${local.members} members');
        return local;
      }
      // Fall back to API if local cache is empty
      debugPrint('[Dashboard] Local empty, fetching from API...');
      return apiRepo.householdAndMemberCount();
    });
    
    _householdFuture = countsFuture.then((c) async {
      try {
        await authRepo.cacheHouseholdCount(c.households);
      } catch (_) {}
      return c.households;
    });
    _memberFuture = countsFuture.then((c) => c.members);
  }

  void _loadMissionData() {
    if (!mounted) return;
    
    // Check if MissionDashboardRepository is available
    final missionRepo = context.read<MissionDashboardRepository?>();
    if (missionRepo == null) {
      // No repository available - show empty state
      setState(() {
        _briefFuture = Future.value(MissionBrief.empty);
        _progressFuture = Future.value(const MissionProgress(
          completedVisits: 0,
          totalVisits: 0,
          estimatedRemainingMinutes: 0,
        ));
        _queueFuture = Future.value(const <MissionQueueItem>[]);
        _alertsFuture = Future.value(const <MissionQueueItem>[]);
        _referralSummaryFuture = Future.value(ReferralSummary.empty);
        _followUpsFuture = Future.value(const <FollowUpDue>[]);
        _opportunitiesFuture = Future.value(const <HouseholdOpportunity>[]);
      });
      return;
    }

    setState(() {
      _briefFuture = missionRepo.loadBrief();
      _progressFuture = missionRepo.loadProgress();
      _queueFuture = missionRepo.loadQueue(limit: 10);
      _alertsFuture = missionRepo.loadCriticalAlerts();
      _referralSummaryFuture = missionRepo.loadReferralSummary();
      _followUpsFuture = missionRepo.loadDueFollowUps();
      _opportunitiesFuture = missionRepo.loadHouseholdOpportunities();
    });
  }

  Future<void> _refresh() async {
    final missionRepo = context.read<MissionDashboardRepository?>();
    if (missionRepo != null) {
      await missionRepo.refresh();
    }
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
    if (s == null) return null;
    final ward = s.ward;
    final upazila = s.upazila ?? s.area;
    if (ward != null && upazila != null) return '$ward · $upazila';
    if (ward != null) return ward;
    if (upazila != null) return upazila;
    return null;
  }

  void _handleQueueAction(MissionQueueItem item, MissionAction action) {
    switch (action) {
      case MissionAction.openCase:
        if (item.patientId != null) {
          context.push('/patient/${item.patientId}');
        }
        break;
      case MissionAction.openReferral:
        if (item.referralId != null) {
          context.push('/referral/${item.referralId}');
        }
        break;
      case MissionAction.visitHousehold:
        if (item.householdId != null) {
          context.push('/household/${item.householdId}');
        }
        break;
      case MissionAction.callFamily:
      case MissionAction.callFacility:
        _handleCall(item.phoneNumber);
        break;
      case MissionAction.locate:
        _handleLocate(item);
        break;
      case MissionAction.scheduleVisit:
        // TODO: Implement visit scheduling
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visit scheduling coming soon')),
        );
        break;
      case MissionAction.updateStatus:
      case MissionAction.escalate:
        if (item.referralId != null) {
          context.push('/referral/${item.referralId}');
        }
        break;
    }
  }

  void _handleCall(String? phone) {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ReferralStrings.errorNoPhone)),
      );
      return;
    }
    launchUrl(Uri.parse('tel:$phone'));
  }

  void _handleLocate(MissionQueueItem item) {
    if (!item.hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }
    final url = 'https://www.google.com/maps/search/?api=1&query=${item.latitude},${item.longitude}';
    launchUrl(Uri.parse(url));
  }

  void _navigateToFirstQueueItem() async {
    final queue = await _queueFuture;
    if (queue != null && queue.isNotEmpty) {
      final first = queue.first;
      if (first.patientId != null) {
        if (mounted) context.push('/patient/${first.patientId}');
      } else if (first.referralId != null) {
        if (mounted) context.push('/referral/${first.referralId}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (_locationLine() != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      _locationLine()!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else
              Text(
                DashboardStrings.communityAtAGlance,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: [
          // Notifications button
          _ReferralNotificationButton(
            onTap: () => context.push('/referrals'),
          ),
          const SizedBox(width: 4),
          // AI Assistant button
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: MissionDashboardStrings.aiAssistant,
            onPressed: _showAiAssistant,
          ),
          const SizedBox(width: 4),
          // Settings menu
          _SettingsMenu(
            onOfferBiometric: _offerBiometric,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            // Search bar + Stats
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const GlobalSearchBar(),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatPill(
                            label: DashboardStrings.totalMembers,
                            icon: Icons.people_alt_outlined,
                            accent: Theme.of(context).colorScheme.primary,
                            future: _memberFuture,
                            onTap: () => context.push('/members'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _StatPill(
                            label: DashboardStrings.totalHouseholds,
                            icon: Icons.home_work_outlined,
                            accent: Theme.of(context).colorScheme.tertiary,
                            future: _householdFuture,
                            onTap: () => context.push('/households'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Critical alerts (sticky when present)
            SliverToBoxAdapter(
              child: FutureBuilder<List<MissionQueueItem>>(
                future: _alertsFuture,
                builder: (context, snap) {
                  if (!snap.hasData || snap.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return CriticalAlertBanner(
                    alerts: snap.data!,
                    onOpenCase: (item) {
                      if (item.patientId != null) {
                        context.push('/patient/${item.patientId}');
                      } else if (item.referralId != null) {
                        context.push('/referral/${item.referralId}');
                      }
                    },
                  );
                },
              ),
            ),

            // AI Daily Brief
            SliverToBoxAdapter(
              child: FutureBuilder<MissionBrief>(
                future: _briefFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final brief = snap.data ?? MissionBrief.empty;
                  return AIBriefCard(
                    brief: brief,
                    onContinueWork: _navigateToFirstQueueItem,
                  );
                },
              ),
            ),

            // Mission Progress
            SliverToBoxAdapter(
              child: FutureBuilder<MissionProgress>(
                future: _progressFuture,
                builder: (context, snap) {
                  final progress = snap.data ?? MissionProgress.empty;
                  return MissionProgressCard(
                    progress: progress,
                    onContinueWork: _navigateToFirstQueueItem,
                  );
                },
              ),
            ),

            // Section header: Mission Queue
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.assignment,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mission Queue',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            // Mission Queue Cards
            FutureBuilder<List<MissionQueueItem>>(
              future: _queueFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                final queue = snap.data ?? [];
                if (queue.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 48,
                              color: scheme.primary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              MissionDashboardStrings.noMissionsToday,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = queue[index];
                      return MissionQueueCard(
                        item: item,
                        rank: index + 1,
                        onAction: _handleQueueAction,
                        onTap: () {
                          if (item.patientId != null) {
                            context.push('/patient/${item.patientId}');
                          } else if (item.referralId != null) {
                            context.push('/referral/${item.referralId}');
                          }
                        },
                      );
                    },
                    childCount: queue.length,
                  ),
                );
              },
            ),

            // Referral Operations Widget
            SliverToBoxAdapter(
              child: FutureBuilder<ReferralSummary>(
                future: _referralSummaryFuture,
                builder: (context, snap) {
                  final summary = snap.data ?? ReferralSummary.empty;
                  return ReferralOperationsWidget(
                    summary: summary,
                    onOpenReferrals: () => context.push('/referrals'),
                    onOpenReferral: (item) {
                      if (item.referralId != null) {
                        context.push('/referral/${item.referralId}');
                      }
                    },
                    onCallPatient: (item) => _handleCall(item.phoneNumber),
                  );
                },
              ),
            ),

            // Follow-Ups Due Widget
            SliverToBoxAdapter(
              child: FutureBuilder<List<FollowUpDue>>(
                future: _followUpsFuture,
                builder: (context, snap) {
                  final followUps = snap.data ?? [];
                  if (followUps.isEmpty) return const SizedBox.shrink();
                  return FollowUpsDueWidget(
                    followUps: followUps,
                    onScheduleVisit: (followUp) {
                      context.push('/patient/${followUp.patientId}');
                    },
                  );
                },
              ),
            ),

            // Household Opportunities Widget
            SliverToBoxAdapter(
              child: FutureBuilder<List<HouseholdOpportunity>>(
                future: _opportunitiesFuture,
                builder: (context, snap) {
                  final opportunities = snap.data ?? [];
                  if (opportunities.isEmpty) return const SizedBox.shrink();
                  return HouseholdOpportunitiesWidget(
                    opportunities: opportunities,
                    onVisitHousehold: (opp) {
                      context.push('/household/${opp.householdId}');
                    },
                  );
                },
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
      // Floating AI Assistant button
      floatingActionButton: FloatingActionButton(
        onPressed: _showAiAssistant,
        tooltip: MissionDashboardStrings.askAiAssistant,
        child: const Icon(Icons.smart_toy),
      ),
    );
  }

  void _showAiAssistant() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => _AiAssistantSheet(
          scrollController: scrollController,
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
              ctx.read<DashboardRepository>().clearCache();
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

/// AI Assistant bottom sheet.
class _AiAssistantSheet extends StatelessWidget {
  const _AiAssistantSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.smart_toy,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        MissionDashboardStrings.aiAssistant,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Ask about patient care, guidelines, or procedures',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Quick questions
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Quick Questions',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                _QuickQuestion(
                  question: 'What should I do if a child refuses medication?',
                  onTap: () {},
                ),
                _QuickQuestion(
                  question: 'Can severe pneumonia be managed at home?',
                  onTap: () {},
                ),
                _QuickQuestion(
                  question: 'When should ANC patients be referred?',
                  onTap: () {},
                ),
                _QuickQuestion(
                  question: 'What are the danger signs in pregnancy?',
                  onTap: () {},
                ),
                _QuickQuestion(
                  question: 'How to measure blood pressure correctly?',
                  onTap: () {},
                ),
                const SizedBox(height: 24),
                // Input field placeholder
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          MissionDashboardStrings.aiAssistantHint,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Icon(
                        Icons.mic,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'AI Assistant coming soon — this is a preview',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickQuestion extends StatelessWidget {
  const _QuickQuestion({
    required this.question,
    required this.onTap,
  });

  final String question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact stat pill for member/household counts.
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.icon,
    required this.accent,
    required this.future,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final Future<int> future;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: FutureBuilder<int>(
                  future: future,
                  builder: (context, snap) {
                    final value = snap.hasError
                        ? '—'
                        : (snap.data == null ? '…' : '${snap.data}');
                    return Text(
                      '$value · ${label.replaceAll('\n', ' ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
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
