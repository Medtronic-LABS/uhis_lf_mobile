import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';

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
      setState(() => _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isOnline = false);
    }
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LockContent(
                summary: _summary,
                busy: auth.busy,
                failed: _failed,
                biometricEnabled: auth.biometricEnabled,
                pinEnabled: auth.pinEnabled,
                isOnline: _isOnline,
                onUnlock: _trigger,
                onPinUnlock: () => context.go('/pin-unlock'),
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

  static const _btnSize = Size.fromHeight(48);

  String _displayName() {
    final s = summary;
    if (s == null) return '';
    final f = s.firstName?.trim() ?? '';
    final l = s.lastName?.trim() ?? '';
    return [f, l].where((e) => e.isNotEmpty).join(' ');
  }

  void _showOfflineMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(LockStrings.offlinePasswordDisabled),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = summary;
    final name = _displayName();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final isCompact = availableHeight < 550;
        final isTiny = availableHeight < 450;

        // Scale elements based on available height
        final logoHeight = isTiny ? 30.0 : (isCompact ? 40.0 : 56.0);
        final titleStyle = isTiny
            ? Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)
            : Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700);
        final subtitleStyle = isTiny
            ? Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)
            : Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant);
        final btnSize = isTiny ? const Size.fromHeight(40) : _btnSize;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            Image.asset(
              'assets/images/app-logo-name.png',
              height: logoHeight,
              fit: BoxFit.contain,
            ),
            const Spacer(),
            Text(
              name.isEmpty
                  ? LockStrings.welcomeBack
                  : LockStrings.welcomeBackNamed(name),
              style: titleStyle,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isTiny ? 2 : 4),
            Text(
              LockStrings.verifyToAccess,
              style: subtitleStyle,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            if (s != null && s.hasAnyDetail && !isCompact) ...[
              _UserDetailsCard(summary: s),
              const Spacer(),
            ],
            ..._methods(context, btnSize: btnSize, isCompact: isCompact),
            const Spacer(flex: 2),
          ],
        );
      },
    );
  }

  List<Widget> _methods(BuildContext context,
      {required Size btnSize, required bool isCompact}) {
    if (busy) return const [CircularProgressIndicator()];
    return [
      if (failed) ...[
        Text(
          LockStrings.biometricCancelled,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        SizedBox(height: isCompact ? 6 : 12),
      ],
      if (biometricEnabled) ...[
        FilledButton.icon(
          onPressed: onUnlock,
          icon: const Icon(Icons.fingerprint),
          label: const Text(LockStrings.unlockWithPhonePasswordOrBiometrics),
          style: FilledButton.styleFrom(minimumSize: btnSize),
        ),
        SizedBox(height: isCompact ? 4 : 8),
      ],
      if (pinEnabled) ...[
        OutlinedButton(
          onPressed: onPinUnlock,
          style: OutlinedButton.styleFrom(minimumSize: btnSize),
          child: Text(PinStrings.usePin(AppConfig.pinLength)),
        ),
        SizedBox(height: isCompact ? 4 : 8),
      ],
      OutlinedButton.icon(
        onPressed:
            isOnline ? onPassword : () => _showOfflineMessage(context),
        icon: Icon(
          Icons.password,
          color: isOnline ? null : Theme.of(context).disabledColor,
        ),
        label: Text(
          CommonStrings.usePassword,
          style: isOnline
              ? null
              : TextStyle(color: Theme.of(context).disabledColor),
        ),
        style: OutlinedButton.styleFrom(minimumSize: btnSize),
      ),
    ];
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
            _Row(label: LockStrings.skIdLabel, value: summary.skId!),
          if (summary.upazila != null)
            _Row(label: LockStrings.upazilaLabel, value: summary.upazila!),
          if (summary.nidOrPhone != null)
            _Row(label: LockStrings.nidLabel, value: summary.nidOrPhone!),
          if (wardLine != null) _Row(label: LockStrings.wardLabel, value: wardLine),
          if (summary.skId == null &&
              summary.upazila == null &&
              summary.nidOrPhone == null &&
              wardLine == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                summary.area ?? LockStrings.profileLoading,
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
    if (w != null && h != null) return '$w · $h ${LockStrings.households}';
    if (w != null) return w;
    if (h != null) return '$h ${LockStrings.households}';
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
