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
    final s = await context.read<AuthState>().userProfileSummary();
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
      if (mounted) context.go('/login?from=lock');
      return;
    }
    setState(() => _failed = true);
  }

  Future<void> _usePassword() async {
    final auth = context.read<AuthState>();
    await auth.requestPasswordFallback();
    if (!mounted) return;
    context.go('/login?from=lock');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
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
                  busy: auth.busy,
                  failed: _failed,
                  biometricEnabled: auth.biometricEnabled,
                  pinEnabled: auth.pinEnabled,
                  isOnline: _isOnline,
                  onUnlock: _trigger,
                  onPinUnlock: () => context.go('/pin-unlock'),
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
