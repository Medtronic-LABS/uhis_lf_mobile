import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';

/// Mid-session lock overlay. Sits on top of the live widget tree so the
/// underlying screen state (TextField text, scroll position, futures) is
/// preserved through a background → resume cycle.
class LockBarrier extends StatefulWidget {
  const LockBarrier({super.key});

  @override
  State<LockBarrier> createState() => _LockBarrierState();
}

class _LockBarrierState extends State<LockBarrier> {
  bool _tried = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _trigger());
  }

  Future<void> _trigger() async {
    if (_tried) return;
    _tried = true;
    if (!mounted) return;
    final auth = context.read<AuthState>();
    final ok = await auth.biometricUnlock();
    if (!mounted) return;
    if (ok) {
      // AuthState.biometricUnlock already calls unlock() on success — nothing
      // else to do; the parent rebuild will tear the barrier down.
      return;
    }
    if (!auth.biometricEnabled) {
      // Session expired during restore; full sign-in needed.
      await auth.requestPasswordFallback();
      if (mounted) context.go('/login?from=lock');
      return;
    }
    setState(() => _failed = true);
  }

  void _retry() {
    setState(() {
      _tried = false;
      _failed = false;
    });
    _trigger();
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
    final user = auth.username;
    return PopScope(
      canPop: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 16),
                  Text('UHIS Next',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    user == null ? 'Locked' : 'Locked — $user',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  if (auth.busy)
                    const CircularProgressIndicator()
                  else if (_failed)
                    Column(
                      children: [
                        const Text('Biometric cancelled'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Try again'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _usePassword,
                          child: const Text('Use password'),
                        ),
                      ],
                    )
                  else
                    const Icon(Icons.fingerprint, size: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
