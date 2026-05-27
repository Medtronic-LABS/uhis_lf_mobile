import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../pin/pin_pad.dart';

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
                biometricEnabled: auth.biometricEnabled,
                pinEnabled: auth.pinEnabled,
                onUnlock: _trigger,
                onPin: (pin) async {
                  final ok = await auth.pinUnlock(pin);
                  if (!mounted) return null;
                  if (ok) {
                    context.go('/dashboard');
                    return null;
                  }
                  return auth.error;
                },
                onPassword: () => context.go('/login?from=lock'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LockContent extends StatefulWidget {
  const LockContent({
    super.key,
    required this.summary,
    required this.busy,
    required this.failed,
    required this.biometricEnabled,
    required this.pinEnabled,
    required this.onUnlock,
    required this.onPin,
    required this.onPassword,
  });

  final UserProfileSummary? summary;
  final bool busy;
  final bool failed;
  final bool biometricEnabled;
  final bool pinEnabled;
  final VoidCallback onUnlock;

  /// Verify [pin]; returns a localized error message, or null on success
  /// (the parent handles navigation / barrier dismissal on success).
  final Future<String?> Function(String pin) onPin;
  final VoidCallback onPassword;

  @override
  State<LockContent> createState() => _LockContentState();
}

class _LockContentState extends State<LockContent> {
  bool _pinMode = false;
  String _pinValue = '';
  String? _pinError;
  bool _pinBusy = false;

  static const _btnSize = Size.fromHeight(48);

  String _displayName() {
    final s = widget.summary;
    if (s == null) return '';
    final f = s.firstName?.trim() ?? '';
    final l = s.lastName?.trim() ?? '';
    return [f, l].where((e) => e.isNotEmpty).join(' ');
  }

  void _enterPinMode() => setState(() {
        _pinMode = true;
        _pinValue = '';
        _pinError = null;
      });

  void _exitPinMode() => setState(() {
        _pinMode = false;
        _pinValue = '';
        _pinError = null;
      });

  Future<void> _onPinChanged(String v) async {
    setState(() {
      _pinValue = v;
      _pinError = null;
    });
    if (v.length < AppConfig.pinLength) return;
    setState(() => _pinBusy = true);
    final err = await widget.onPin(v);
    if (!mounted) return;
    setState(() {
      _pinBusy = false;
      if (err != null) {
        _pinError = err;
        _pinValue = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.summary;
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
          name.isEmpty
              ? LockStrings.welcomeBack
              : LockStrings.welcomeBackNamed(name),
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          LockStrings.verifyToAccess,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (s != null && s.hasAnyDetail) _UserDetailsCard(summary: s),
        const SizedBox(height: 24),
        if (_pinMode) ..._pinEntry() else ..._methods(context),
      ],
    );
  }

  List<Widget> _pinEntry() {
    return [
      PinEntryView(
        length: AppConfig.pinLength,
        value: _pinValue,
        onChanged: _onPinChanged,
        busy: _pinBusy,
        errorText: _pinError,
        title: PinStrings.enterTitle(AppConfig.pinLength),
      ),
      const SizedBox(height: 8),
      if (widget.biometricEnabled)
        TextButton.icon(
          onPressed: _pinBusy ? null : _exitPinMode,
          icon: const Icon(Icons.fingerprint),
          label: const Text(LockStrings.unlockWithPhonePasswordOrBiometrics),
        ),
      TextButton(
        onPressed: _pinBusy ? null : widget.onPassword,
        child: const Text(CommonStrings.usePassword),
      ),
    ];
  }

  List<Widget> _methods(BuildContext context) {
    if (widget.busy) return const [CircularProgressIndicator()];
    return [
      if (widget.failed) ...[
        Text(
          LockStrings.biometricCancelled,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
      ],
      if (widget.biometricEnabled) ...[
        FilledButton.icon(
          onPressed: widget.onUnlock,
          icon: const Icon(Icons.fingerprint),
          label: const Text(LockStrings.unlockWithPhonePasswordOrBiometrics),
          style: FilledButton.styleFrom(minimumSize: _btnSize),
        ),
        const SizedBox(height: 8),
      ],
      if (widget.pinEnabled) ...[
        OutlinedButton(
          onPressed: _enterPinMode,
          style: OutlinedButton.styleFrom(minimumSize: _btnSize),
          child: Text(PinStrings.usePin(AppConfig.pinLength)),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: widget.onPassword,
        icon: const Icon(Icons.password),
        label: const Text(CommonStrings.usePassword),
        style: OutlinedButton.styleFrom(minimumSize: _btnSize),
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
