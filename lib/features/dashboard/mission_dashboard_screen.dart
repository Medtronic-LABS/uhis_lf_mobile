import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/theme_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/local_dashboard_repository.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/sync/offline_sync_service.dart';
import '../referral/referral_repository.dart';
import '../search/global_search_bar.dart';
import '../visit/visit_controller.dart';
import 'dashboard_repository.dart';
import 'mission_dashboard_repository.dart';
import 'widgets/critical_alert_banner.dart';

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
  
  // Mission data futures consumed by the HTML dashboard composition.
  Future<List<MissionQueueItem>>? _queueFuture;
  Future<List<MissionQueueItem>>? _alertsFuture;
  Future<ReferralSummary>? _referralSummaryFuture;

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
    setState(() {
      _queueFuture = missionRepo.loadQueue(limit: 10);
      _alertsFuture = missionRepo.loadCriticalAlerts();
      _referralSummaryFuture = missionRepo.loadReferralSummary();
    });
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
    if (s == null) return null;
    final ward = s.ward;
    final upazila = s.upazila ?? s.area;
    if (ward != null && upazila != null) return '$ward · $upazila';
    if (ward != null) return ward;
    if (upazila != null) return upazila;
    return null;
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
      context.go('/patients/visit/$encounterId/triage');
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
              onAiAssistant: _showAiAssistant,
              settingsMenu: _SettingsMenu(onOfferBiometric: _offerBiometric),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                  children: [
                    FutureBuilder<List<MissionQueueItem>>(
                      future: _queueFuture,
                      builder: (context, snap) {
                        final visitCount = (snap.data ?? const []).length;
                        return _AiRibbon(visitCount: visitCount);
                      },
                    ),
                    const SizedBox(height: 10),
                    _DashboardStatsRow(
                      queueFuture: _queueFuture,
                      referralFuture: _referralSummaryFuture,
                      onTapVisits: _navigateToFirstQueueItem,
                      onTapReferrals: () => context.push('/referrals'),
                    ),
                    const SizedBox(height: 14),
                    FutureBuilder<List<MissionQueueItem>>(
                      future: _alertsFuture,
                      builder: (context, snap) {
                        if (!snap.hasData || snap.data!.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CriticalAlertBanner(
                            alerts: snap.data!,
                            onOpenCase: (item) {
                              if (item.patientId != null) {
                                context.push('/patient/${item.patientId}');
                              } else if (item.referralId != null) {
                                context.push('/referral/${item.referralId}');
                              }
                            },
                          ),
                        );
                      },
                    ),
                    _TodaysVisitsHeader(),
                    const SizedBox(height: 8),
                    FutureBuilder<List<MissionQueueItem>>(
                      future: _queueFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final queue = snap.data ?? const [];
                        if (queue.isEmpty) {
                          return _EmptyVisitsCard();
                        }
                        const visibleLimit = 6;
                        final visible = queue.length > visibleLimit
                            ? queue.sublist(0, visibleLimit)
                            : queue;
                        final overflow = queue.length - visible.length;
                        return Column(
                          children: [
                            for (final item in visible)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _PriorityPatientCard(
                                  item: item,
                                  onTap: () {
                                    if (item.patientId != null) {
                                      context.push('/patient/${item.patientId}');
                                    } else if (item.referralId != null) {
                                      context.push('/referral/${item.referralId}');
                                    }
                                  },
                                  onAction: () => _startVisitFromQueue(item),
                                ),
                              ),
                            if (overflow > 0)
                              _MoreVisitsLink(
                                count: overflow,
                                onTap: () => context.go('/patients'),
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
    required this.onAiAssistant,
    required this.settingsMenu,
  });

  final String greeting;
  final String? locationLine;
  final VoidCallback onNotifications;
  final VoidCallback onAiAssistant;
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
              IconButton(
                icon: const Icon(Icons.smart_toy_outlined, color: Colors.white),
                tooltip: MissionDashboardStrings.aiAssistant,
                onPressed: onAiAssistant,
              ),
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

class _AiRibbon extends StatelessWidget {
  const _AiRibbon({required this.visitCount});

  final int visitCount;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.brandNavy,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MissionDashboardStrings.aiSortedVisits(visitCount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: const [
                    _AiRibbonChip(label: 'Risk scoring'),
                    _AiRibbonChip(label: 'Overdue flags'),
                    _AiRibbonChip(label: 'CCE alerts'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiRibbonChip extends StatelessWidget {
  const _AiRibbonChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '✦ $label',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DashboardStatsRow extends StatelessWidget {
  const _DashboardStatsRow({
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
              final count = (snap.data ?? const []).length;
              return _DashboardStatCard(
                value: '$count',
                label: MissionDashboardStrings.visitsToday,
                accentVariant: _DashboardStatVariant.navy,
                subline: MissionDashboardStrings.visitsTodaySubline,
                onTap: onTapVisits,
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FutureBuilder<ReferralSummary>(
            future: referralFuture,
            builder: (context, snap) {
              final s = snap.data ?? ReferralSummary.empty;
              final alerts = s.breached + s.awaitingReview;
              return _DashboardStatCard(
                value: '$alerts',
                label: MissionDashboardStrings.referralAlertsLabel,
                accentVariant: _DashboardStatVariant.pink,
                subline: MissionDashboardStrings.tapToFollowUp,
                footnote: MissionDashboardStrings.referralCceComingSoon,
                showPulse: s.hasBreaches,
                onTap: onTapReferrals,
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
  });

  final String value;
  final String label;
  final _DashboardStatVariant accentVariant;
  final String subline;
  final String? footnote;
  final bool showPulse;
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: accent,
                      height: 1,
                    ),
                  ),
                  if (showPulse) ...[
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
                color: tokens.brandNavy,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tokens.aiPurple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 12, color: tokens.aiPurple),
                const SizedBox(width: 4),
                Text(
                  MissionDashboardStrings.aiSortedBadge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: tokens.aiPurple,
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

class _PriorityPatientCard extends StatelessWidget {
  const _PriorityPatientCard({
    required this.item,
    required this.onTap,
    required this.onAction,
  });

  final MissionQueueItem item;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final urgency = Theme.of(context).extension<UrgencyTheme>()!;
    final borderColor = _borderColor(item.priority, urgency, tokens);
    final (actionLabel, actionBg, actionFg) =
        _actionStyle(item.priority, tokens);

    return Material(
      color: tokens.cardSurface,
      borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
            border: Border(
              left: BorderSide(color: borderColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: borderColor.withValues(alpha: 0.18),
                child: Text(
                  _initials(item.patientName),
                  style: TextStyle(
                    color: borderColor,
                    fontWeight: FontWeight.w800,
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
                      item.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _PriorityPatientReasonBadge(item: item),
                    const SizedBox(height: 6),
                    Text(
                      _subtitle(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: actionBg,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: actionFg,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _subtitle(MissionQueueItem item) {
    final parts = <String>[];
    if (item.age != null) parts.add(WorklistStrings.ageFmt(item.age!));
    final house = item.householdDisplay;
    if (house.isNotEmpty) parts.add(house);
    if (house.isEmpty &&
        item.village != null &&
        item.village!.isNotEmpty) {
      parts.add(item.village!);
    }
    if (parts.isEmpty) return item.reason;
    return parts.join(' · ');
  }

  Color _borderColor(
    MissionPriority p,
    UrgencyTheme urgency,
    LeapfrogColors tokens,
  ) {
    switch (p) {
      case MissionPriority.critical:
        return urgency.visitNow;
      case MissionPriority.high:
        return urgency.today;
      case MissionPriority.medium:
        return urgency.thisWeek;
      case MissionPriority.low:
        return tokens.textMuted;
    }
  }

  (String, Color, Color) _actionStyle(
    MissionPriority p,
    LeapfrogColors tokens,
  ) {
    switch (p) {
      case MissionPriority.critical:
        return (
          MissionDashboardStrings.actionVisitNow,
          tokens.statusCritical,
          Colors.white,
        );
      case MissionPriority.high:
        return (
          MissionDashboardStrings.actionVisitToday,
          tokens.brandNavy,
          Colors.white,
        );
      case MissionPriority.medium:
        return (
          MissionDashboardStrings.actionThisWeek,
          tokens.cardSurfaceMuted,
          tokens.brandNavy,
        );
      case MissionPriority.low:
        return (
          MissionDashboardStrings.actionRoutine,
          tokens.cardSurfaceMuted,
          tokens.textMuted,
        );
    }
  }
}

class _PriorityPatientReasonBadge extends StatelessWidget {
  const _PriorityPatientReasonBadge({required this.item});

  final MissionQueueItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final urgency = Theme.of(context).extension<UrgencyTheme>()!;
    final (bg, fg) = _badgeColors(item.priority, urgency, tokens);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        item.reason,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  (Color, Color) _badgeColors(
    MissionPriority p,
    UrgencyTheme urgency,
    LeapfrogColors tokens,
  ) {
    switch (p) {
      case MissionPriority.critical:
        return (urgency.visitNowContainer, urgency.visitNow);
      case MissionPriority.high:
        return (urgency.todayContainer, urgency.today);
      case MissionPriority.medium:
        return (urgency.thisWeekContainer, urgency.thisWeek);
      case MissionPriority.low:
        return (tokens.cardSurfaceMuted, tokens.textMuted);
    }
  }
}

/// Tail link beneath the priority visit list — matches the prototype's
/// "+ N more visits today" affordance and deep-links into the full worklist.
class _MoreVisitsLink extends StatelessWidget {
  const _MoreVisitsLink({required this.count, required this.onTap});

  final int count;
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
