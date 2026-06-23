import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import 'lock_header.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;
  UserProfileSummary? _summary;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSummary();
      _checkConnectivity();
    });
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(
          () => _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isOnline = false);
    }
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    final auth = context.read<AuthState>();
    final s = await auth.userProfileSummary();
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
    final busy = context.select<AuthState, bool>((a) => a.busy);
    final biometricEnabled = context.select<AuthState, bool>((a) => a.biometricEnabled);
    final biometricAvailable = context.select<AuthState, bool>((a) => a.biometricAvailable);
    final pinEnabled = context.select<AuthState, bool>((a) => a.pinEnabled);

    final programTitle = _summary?.area ?? LockStrings.programName;

    return Scaffold(
      backgroundColor: AppColors.cardSurface,
      body: Column(
        children: [
          LockProgramHeader(title: programTitle),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: LockContent(
                    summary: _summary,
                    busy: busy,
                    failed: _failed,
                    biometricEnabled: biometricEnabled && biometricAvailable,
                    pinEnabled: pinEnabled,
                    isOnline: _isOnline,
                    onUnlock: _trigger,
                    onPinUnlock: () => context.go('/pin-unlock'),
                    onPassword: () => context.go('/login?from=lock'),
                  ),
                ),
              ),
            ),
          ),
        ],
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
    required this.biometricEnabled,
    required this.pinEnabled,
    required this.isOnline,
    required this.onUnlock,
    required this.onPinUnlock,
    required this.onPassword,
  });

  final UserProfileSummary? summary;
  final bool busy;
  final bool failed;
  final bool biometricEnabled;
  final bool pinEnabled;
  final bool isOnline;
  final VoidCallback onUnlock;
  final VoidCallback onPinUnlock;
  final VoidCallback onPassword;

  void _showOfflineMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(LockStrings.offlinePasswordDisabled),
        duration: Duration(seconds: 3),
      ),
    );
  }

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _UserAvatar(),
          const SizedBox(height: 20),
          Text(
            name.isEmpty ? LockStrings.welcomeBack : LockStrings.welcomeBackNamed(name),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            LockStrings.signInToStartYourDay,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (s != null && s.hasAnyDetail) ...[
            _UserProfileCard(summary: s),
            const SizedBox(height: 16),
          ],
          ..._actionWidgets(context),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<Widget> _actionWidgets(BuildContext context) {
    if (busy) return const [Center(child: CircularProgressIndicator())];
    return [
      if (failed) ...[
        Center(
          child: Text(
            LockStrings.biometricCancelled,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (biometricEnabled) _FingerprintCard(onTap: onUnlock),
      if (pinEnabled) ...[
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: onPinUnlock,
            child: Text(LockStrings.orUsePin(AppConfig.pinLength)),
          ),
        ),
      ],
      const SizedBox(height: 4),
      Center(
        child: TextButton.icon(
          onPressed: isOnline ? onPassword : () => _showOfflineMessage(context),
          icon: const Icon(Icons.lock_outline, size: 16),
          label: Text(CommonStrings.usePassword),
          style: TextButton.styleFrom(
            foregroundColor: isOnline
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).disabledColor,
          ),
        ),
      ),
    ];
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar();

  @override
  Widget build(BuildContext context) {
    return const CircleAvatar(
      radius: 36,
      backgroundColor: AppColors.pink,
      child: Icon(Icons.person_rounded, color: Colors.white, size: 36),
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  const _UserProfileCard({required this.summary});

  final UserProfileSummary summary;

  String _initials() {
    final f = summary.firstName?.trim() ?? '';
    final l = summary.lastName?.trim() ?? '';
    final fi = f.isNotEmpty ? f[0].toUpperCase() : '';
    final li = l.isNotEmpty ? l[0].toUpperCase() : '';
    final result = '$fi$li';
    return result.isNotEmpty ? result : '?';
  }

  String _fullName() {
    final f = summary.firstName?.trim() ?? '';
    final l = summary.lastName?.trim() ?? '';
    return [f, l].where((e) => e.isNotEmpty).join(' ');
  }

  String _idLine() {
    final parts = <String>[];
    if (summary.skId != null) parts.add(summary.skId!);
    if (summary.ward != null) parts.add(summary.ward!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LockStrings.shasthyaKormi,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.70),
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _InitialsAvatar(initials: _initials()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fullName().isNotEmpty ? _fullName() : LockStrings.profileLoading,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (_idLine().isNotEmpty)
                      Text(
                        _idLine(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.60),
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoCol(
                  label: LockStrings.nidLabel,
                  value: summary.nidOrPhone ?? '—',
                ),
              ),
              Expanded(
                child: _InfoCol(
                  label: LockStrings.upazilaLabel,
                  value: summary.upazila ?? '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.navyOnDark,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _InfoCol extends StatelessWidget {
  const _InfoCol({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.50),
                letterSpacing: 0.8,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _FingerprintCard extends StatelessWidget {
  const _FingerprintCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.navyDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.navyOnDark,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.fingerprint,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LockStrings.verifyFingerprint,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    LockStrings.tapToPlaceFinger,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.60),
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.60),
            ),
          ],
        ),
      ),
    );
  }
}
