import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import 'pin_pad.dart';

/// Dedicated PIN unlock screen. Navigated to from lock screen when user
/// chooses PIN unlock method. On successful unlock → dashboard.
class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({super.key});

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen> {
  final int _len = AppConfig.pinLength;
  String _value = '';
  String? _error;
  bool _busy = false;

  Future<void> _onChanged(String v) async {
    setState(() {
      _value = v;
      _error = null;
    });
    if (v.length < _len) return;

    setState(() => _busy = true);
    final auth = context.read<AuthState>();
    final ok = await auth.pinUnlock(v);
    if (!mounted) return;

    if (ok) {
      context.go('/dashboard');
    } else {
      setState(() {
        _busy = false;
        _error = auth.error ?? PinStrings.wrong;
        _value = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild on specific field changes
    final biometricEnabled = context.select<AuthState, bool>((a) => a.biometricEnabled);
    final biometricAvailable = context.select<AuthState, bool>((a) => a.biometricAvailable);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/lock'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final isCompact = availableHeight < 500;

            return Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: isCompact ? 8 : 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isCompact) ...[
                        Image.asset(
                          'assets/images/app-logo-name.png',
                          height: 48,
                          fit: BoxFit.contain,
                          semanticLabel: 'UHIS logo',
                        ),
                        const SizedBox(height: 24),
                      ],
                      Expanded(
                        child: PinEntryView(
                          length: _len,
                          value: _value,
                          onChanged: _onChanged,
                          busy: _busy,
                          errorText: _error,
                          title: PinStrings.enterTitle(_len),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Show biometric button only if user enabled it AND device has biometric enrolled
                      if (biometricEnabled && biometricAvailable)
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final router = GoRouter.of(context);
                                  final auth = context.read<AuthState>();
                                  final ok = await auth.biometricUnlock();
                                  if (!mounted) return;
                                  if (ok) router.go('/dashboard');
                                },
                          icon: const Icon(Icons.lock_open),
                          label: const Text(
                              LockStrings.unlockWithBiometrics),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => context.go('/login?from=lock'),
                        child: const Text(CommonStrings.usePassword),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
