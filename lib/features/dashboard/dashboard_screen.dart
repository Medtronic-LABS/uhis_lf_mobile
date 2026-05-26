import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../search/global_search_bar.dart';
import 'dashboard_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<int> _patientFuture;
  late Future<int> _householdFuture;
  bool _bioPrompted = false;
  DateTime? _lastRefreshed;
  UserProfileSummary? _summary;

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSummary();
      await _maybeOfferBiometric();
    });
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    final s = await context.read<AuthState>().userProfileSummary();
    if (!mounted) return;
    setState(() => _summary = s);
  }

  Future<void> _maybeOfferBiometric({bool force = false}) async {
    if (_bioPrompted && !force) return;
    _bioPrompted = true;
    final auth = context.read<AuthState>();
    if (auth.biometricEnabled) return;
    if (!force && await auth.wasBiometricOffered()) return;
    if (!mounted) return;
    final supported = auth.biometricAvailable;
    final ans = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use device unlock?'),
        content: Text(
          supported
              ? 'Sign in next time with your fingerprint, face, or device PIN — no password needed.'
              : 'Sign in next time with your fingerprint, face, or device PIN. You may need to set up a screen lock in Android Settings first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    await auth.markBiometricOffered();
    if (ans != true || !mounted) return;
    if (!supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set up a screen lock (PIN, pattern, or fingerprint) in Android Settings, then try again.',
          ),
        ),
      );
      return;
    }
    try {
      await context.read<AuthState>().enrolBiometric();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device unlock enabled')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable: $e')),
      );
    }
  }

  void _reload() {
    final repo = context.read<DashboardRepository>();
    final authRepo = context.read<AuthRepository>();
    _patientFuture = repo.patientCount();
    _householdFuture = repo.householdCount().then((c) async {
      try {
        await authRepo.cacheHouseholdCount(c);
      } catch (_) {}
      return c;
    });
    _lastRefreshed = DateTime.now();
  }

  Future<void> _onRefresh() async {
    setState(_reload);
    await Future.wait([_patientFuture, _householdFuture])
        .catchError((_) => [0, 0]);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good Morning'
        : (hour < 17 ? 'Good Afternoon' : 'Good Evening');
    final first = _summary?.firstName?.trim();
    if (first != null && first.isNotEmpty) return '$part, $first';
    final fallback = context.read<AuthState>().username;
    if (fallback == null || fallback.isEmpty) return part;
    final stub = fallback.split('.').first.split('@').first;
    final cap = stub.isEmpty
        ? ''
        : '${stub[0].toUpperCase()}${stub.substring(1)}';
    return '$part, $cap';
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

  String _lastRefreshedLabel() {
    final t = _lastRefreshed;
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 30) return 'updated just now';
    if (diff.inMinutes < 1) return 'updated ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'updated ${diff.inMinutes}m ago';
    return 'updated ${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('UHIS Next'),
        actions: [
          Consumer<AuthState>(
            builder: (ctx, auth, _) => PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'enable_bio':
                    _bioPrompted = false;
                    await _maybeOfferBiometric(force: true);
                    break;
                  case 'disable_bio':
                    await auth.disableBiometric();
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Device unlock disabled')),
                      );
                    }
                    break;
                  case 'logout':
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
                      title: Text('Enable device unlock'),
                    ),
                  ),
                if (auth.biometricEnabled)
                  const PopupMenuItem(
                    value: 'disable_bio',
                    child: ListTile(
                      leading: Icon(Icons.fingerprint_outlined),
                      title: Text('Disable device unlock'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Sign out'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting(),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      if (_locationLine() != null)
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 16, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _locationLine()!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'Your community at a glance',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(_reload),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const GlobalSearchBar(),
            const SizedBox(height: 20),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Total\nPatients',
                      icon: Icons.people_alt_outlined,
                      accent: scheme.primary,
                      background:
                          scheme.primaryContainer.withValues(alpha: 0.55),
                      future: _patientFuture,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Use the search bar above to look up patients'),
                        ),
                      ),
                      onRetry: () => setState(_reload),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Total\nHouseholds',
                      icon: Icons.home_work_outlined,
                      accent: scheme.tertiary,
                      background:
                          scheme.tertiaryContainer.withValues(alpha: 0.55),
                      future: _householdFuture,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Use the search bar above to look up households'),
                        ),
                      ),
                      onRetry: () => setState(_reload),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard.placeholder(
                      label: 'High-Risk\nPatients',
                      icon: Icons.warning_amber_rounded,
                      accent: scheme.error,
                      background:
                          scheme.errorContainer.withValues(alpha: 0.45),
                      badge: 'SOON',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('AI triage coming soon — not wired yet'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _lastRefreshedLabel(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.icon,
    required this.accent,
    required this.background,
    required this.future,
    required this.onTap,
    required this.onRetry,
  })  : badge = null,
        isPlaceholder = false;

  const _StatCard.placeholder({
    required this.label,
    required this.icon,
    required this.accent,
    required this.background,
    required this.onTap,
    this.badge,
  })  : future = null,
        onRetry = null,
        isPlaceholder = true;

  final String label;
  final IconData icon;
  final Color accent;
  final Color background;
  final Future<int>? future;
  final VoidCallback onTap;
  final VoidCallback? onRetry;
  final String? badge;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(height: 12),
              _value(context),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
              ),
              if (badge != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style:
                        Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onError,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              fontSize: 10,
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

  Widget _value(BuildContext context) {
    if (isPlaceholder) {
      return Text(
        '—',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
      );
    }
    return FutureBuilder<int>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _SkeletonNumber();
        }
        if (snap.hasError) {
          return Row(
            children: [
              Text(
                '—',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(width: 6),
              if (onRetry != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: accent,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          );
        }
        return Text(
          _formatCount(snap.data ?? 0),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: accent,
              ),
        );
      },
    );
  }

  static String _formatCount(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final v = n / 1000;
      return v >= 10 ? '${v.toStringAsFixed(0)}k' : '${v.toStringAsFixed(1)}k';
    }
    final v = n / 1000000;
    return v >= 10 ? '${v.toStringAsFixed(0)}M' : '${v.toStringAsFixed(1)}M';
  }
}

class _SkeletonNumber extends StatefulWidget {
  const _SkeletonNumber();

  @override
  State<_SkeletonNumber> createState() => _SkeletonNumberState();
}

class _SkeletonNumberState extends State<_SkeletonNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    final hi = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.18);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: 36,
        width: 96,
        decoration: BoxDecoration(
          color: Color.lerp(base, hi, _c.value),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

