import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
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
    final auth = context.read<AuthState>();
    final ok = await auth.biometricUnlock();
    if (!mounted) return;
    if (ok) {
      context.go('/dashboard');
    } else {
      if (!auth.biometricEnabled) {
        context.go('/login?from=lock');
      } else {
        setState(() => _failed = true);
      }
    }
  }

  void _retry() {
    setState(() {
      _tried = false;
      _failed = false;
    });
    _trigger();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.username;
    return Scaffold(
      body: SafeArea(
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
                        onPressed: () => context.go('/login?from=lock'),
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
    );
  }
}
