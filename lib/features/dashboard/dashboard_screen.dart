import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/constants/app_strings.dart';
import '../referral/referral_repository.dart';
import '../search/global_search_bar.dart';
import '../worklist/worklist_screen.dart';
import 'dashboard_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<int> _memberFuture;
  late Future<int> _householdFuture;
  UserProfileSummary? _summary;

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthState>();
      await _loadSummary(auth);
      // Seed demo referral data if empty (runs after login)
      await _seedReferralsIfNeeded();
    });
  }

  Future<void> _seedReferralsIfNeeded() async {
    if (!mounted) return;
    final referralRepo = context.read<ReferralRepository>();
    final seeded = await referralRepo.seedDemoDataIfEmpty();
    if (seeded > 0) {
      debugPrint('[dashboard] seeded $seeded demo referrals');
      // Trigger rebuild so the notification badge updates
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadSummary(AuthState auth) async {
    if (!mounted) return;
    final s = await auth.userProfileSummary();
    if (!mounted) return;
    setState(() => _summary = s);
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

  void _reload() {
    final repo = context.read<DashboardRepository>();
    final authRepo = context.read<AuthRepository>();
    final countsFuture = repo.householdAndMemberCount();
    _householdFuture = countsFuture.then((c) async {
      try {
        await authRepo.cacheHouseholdCount(c.households);
      } catch (_) {}
      return c.households;
    });
    _memberFuture = countsFuture.then((c) => c.members);
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
          _ReferralNotificationButton(
            onTap: () => context.push('/referrals'),
          ),
          Consumer<AuthState>(
            builder: (ctx, auth, _) => PopupMenuButton<String>(
              icon: const Icon(Icons.settings),
              onSelected: (v) async {
                switch (v) {
                  case 'enable_bio':
                    await _offerBiometric();
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
                        const SnackBar(
                            content: Text(PinStrings.disabledSnack)),
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
                    // Clear dashboard cache before logout to ensure fresh data on next login
                    context.read<DashboardRepository>().clearCache();
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
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const GlobalSearchBar(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatPill(
                        label: DashboardStrings.totalMembers,
                        icon: Icons.people_alt_outlined,
                        accent: scheme.primary,
                        future: _memberFuture,
                        onTap: () => context.push('/members'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPill(
                        label: DashboardStrings.totalHouseholds,
                        icon: Icons.home_work_outlined,
                        accent: scheme.tertiary,
                        future: _householdFuture,
                        onTap: () => context.push('/households'),
                      ),
                    ),
                  ],
                ),

              ],
            ),
          ),
          const Expanded(child: WorklistView()),
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
  
  // Cached reference to avoid context.read on deactivated widget
  ReferralRepository? _repo;
  bool _listenerAdded = false;

  @override
  void initState() {
    super.initState();
    // Defer to didChangeDependencies where context is valid
  }

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
    setState(() { _future = future; });
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
            label: Text(
              total > 99 ? '99+' : total.toString(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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


