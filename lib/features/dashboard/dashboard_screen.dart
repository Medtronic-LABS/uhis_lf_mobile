import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';
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

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferBiometric());
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
    _patientFuture = repo.patientCount();
    _householdFuture = repo.householdCount();
  }

  Future<void> _onRefresh() async {
    setState(_reload);
    await Future.wait([_patientFuture, _householdFuture]).catchError((_) => [0, 0]);
  }

  @override
  Widget build(BuildContext context) {
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
                        const SnackBar(content: Text('Device unlock disabled')),
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
          padding: const EdgeInsets.all(16),
          children: [
            _CountCard(
              title: 'Total Patients',
              icon: Icons.people,
              future: _patientFuture,
              onRetry: () => setState(_reload),
            ),
            const SizedBox(height: 12),
            _CountCard(
              title: 'Total Households',
              icon: Icons.home_work,
              future: _householdFuture,
              onRetry: () => setState(_reload),
            ),
            const SizedBox(height: 12),
            const _HighRiskPlaceholderCard(),
            const SizedBox(height: 24),
            _SearchTile(
              label: 'Search patients',
              hint: 'by name, phone, or NID',
              icon: Icons.person_search,
              onTap: () => context.push('/search/patient'),
            ),
            const SizedBox(height: 12),
            _SearchTile(
              label: 'Search households',
              hint: 'by household name or number',
              icon: Icons.home_outlined,
              onTap: () => context.push('/search/household'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.title,
    required this.icon,
    required this.future,
    required this.onRetry,
  });

  final String title;
  final IconData icon;
  final Future<int> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  FutureBuilder<int>(
                    future: future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      if (snap.hasError) {
                        return Row(
                          children: [
                            const Text('—',
                                style: TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: onRetry,
                              child: const Text('Retry'),
                            ),
                          ],
                        );
                      }
                      return Text(
                        '${snap.data ?? 0}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighRiskPlaceholderCard extends StatelessWidget {
  const _HighRiskPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(child: Icon(Icons.warning_amber)),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('High-Risk Patients',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Coming soon — AI triage'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({
    required this.label,
    required this.hint,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(hint),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
