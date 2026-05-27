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
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                    return ok ? null : auth.error;
                  },
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
