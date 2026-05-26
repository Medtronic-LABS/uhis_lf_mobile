import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;
  UserProfileSummary? _summary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    final s = await context.read<AuthState>().userProfileSummary();
    if (!mounted) return;
    setState(() => _summary = s);
  }

  Future<void> _trigger() async {
    final auth = context.read<AuthState>();
    setState(() => _failed = false);
    final ok = await auth.biometricUnlock();
    if (!mounted) return;
    if (ok) {
      context.go('/dashboard');
    } else if (!auth.biometricEnabled) {
      context.go('/login?from=lock');
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (auth.status == AuthStatus.signedIn && !auth.locked) {
      return const Scaffold(
        body: Center(child: SizedBox.shrink()),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LockContent(
                summary: _summary,
                busy: auth.busy,
                failed: _failed,
                onUnlock: _trigger,
                onPassword: () => context.go('/login?from=lock'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LockContent extends StatelessWidget {
  const LockContent({
    super.key,
    required this.summary,
    required this.busy,
    required this.failed,
    required this.onUnlock,
    required this.onPassword,
  });

  final UserProfileSummary? summary;
  final bool busy;
  final bool failed;
  final VoidCallback onUnlock;
  final VoidCallback onPassword;

  String _displayName() {
    final s = summary;
    if (s == null) return '';
    final f = s.firstName?.trim() ?? '';
    final l = s.lastName?.trim() ?? '';
    return [f, l].where((e) => e.isNotEmpty).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = summary;
    final name = _displayName();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        CircleAvatar(
          radius: 36,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            (s?.firstName?.isNotEmpty == true ? s!.firstName![0] : 'U')
                .toUpperCase(),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name.isEmpty ? 'Welcome back' : 'Welcome back, $name',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Verify your identity to access your ward dashboard.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (s != null && s.hasAnyDetail) _UserDetailsCard(summary: s),
        const SizedBox(height: 24),
        if (busy)
          const CircularProgressIndicator()
        else if (failed) ...[
          Text(
            'Biometric cancelled',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onUnlock,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Unlock with fingerprint'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPassword,
            icon: const Icon(Icons.password),
            label: const Text('Use password'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: onUnlock,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Unlock with fingerprint'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPassword,
            icon: const Icon(Icons.password),
            label: const Text('Use password'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ],
    );
  }
}

class _UserDetailsCard extends StatelessWidget {
  const _UserDetailsCard({required this.summary});
  final UserProfileSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wardLine = _wardLine(summary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          if (summary.skId != null)
            _Row(label: 'SK ID', value: summary.skId!),
          if (summary.upazila != null)
            _Row(label: 'Upazila', value: summary.upazila!),
          if (summary.nidOrPhone != null)
            _Row(label: 'NID', value: summary.nidOrPhone!),
          if (wardLine != null) _Row(label: 'Ward', value: wardLine),
          if (summary.skId == null &&
              summary.upazila == null &&
              summary.nidOrPhone == null &&
              wardLine == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                summary.area ?? 'Profile loading…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }

  static String? _wardLine(UserProfileSummary s) {
    final w = s.ward;
    final h = s.householdCount;
    if (w != null && h != null) return '$w · $h households';
    if (w != null) return w;
    if (h != null) return '$h households';
    return null;
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
