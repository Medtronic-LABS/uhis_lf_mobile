import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import 'lock_screen.dart' show LockContent;

/// Mid-session lock overlay. Sits on top of the live widget tree so the
/// underlying screen state (TextField text, scroll position, futures) is
/// preserved through a background → resume cycle.
class LockBarrier extends StatefulWidget {
  const LockBarrier({super.key});

  @override
  State<LockBarrier> createState() => _LockBarrierState();
}

class _LockBarrierState extends State<LockBarrier> {
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
    if (ok) return;
    if (!auth.biometricEnabled) {
      await auth.requestPasswordFallback();
      if (mounted) context.read<GoRouter>().go('/login?from=lock');
      return;
    }
    setState(() => _failed = true);
  }

  Future<void> _usePassword() async {
    final auth = context.read<AuthState>();
    await auth.requestPasswordFallback();
    if (!mounted) return;
    context.read<GoRouter>().go('/login?from=lock');
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild on specific field changes, not all auth changes
    final busy = context.select<AuthState, bool>((a) => a.busy);
    final biometricEnabled = context.select<AuthState, bool>((a) => a.biometricEnabled);
    final biometricAvailable = context.select<AuthState, bool>((a) => a.biometricAvailable);
    final pinEnabled = context.select<AuthState, bool>((a) => a.pinEnabled);
    
    return PopScope(
      canPop: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: LockContent(
                  summary: _summary,
                  busy: busy,
                  failed: _failed,
                  // Show biometric button only if user enabled it AND device has biometric enrolled
                  biometricEnabled: biometricEnabled && biometricAvailable,
                  pinEnabled: pinEnabled,
                  isOnline: _isOnline,
                  onUnlock: _trigger,
                  onPinUnlock: () => context.read<GoRouter>().go('/pin-unlock'),
                  onPassword: _usePassword,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
