import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/sync/offline_sync_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.fromLock = false});

  final bool fromLock;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _obscurePassword = true;
  String? _bannerMessage;

  @override
  void initState() {
    debugPrint('[_LoginScreenState] initState');
    super.initState();
    final auth = context.read<AuthState>();
    final last = auth.username;
    if (last != null) {
      _userCtl.text = last;
    } else {
      _userCtl.text = 'hyper_sk';
    }
    if (_passCtl.text.isEmpty) _passCtl.text = 'Spice123';
    // Capture and clear any pending auth error (e.g. session expired) so it
    // shows as a persistent banner rather than a dismissible snackbar.
    final pending = auth.error;
    if (pending != null) {
      _bannerMessage = pending;
      auth.clearError();
    }
  }

  @override
  void dispose() {
    debugPrint('[_LoginScreenState] dispose');
    _userCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint('[_LoginScreenState] _submit username=${_userCtl.text.trim()}');
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthState>();
    final ok = await auth.login(_userCtl.text.trim(), _passCtl.text);
    if (!mounted) return;
    if (ok) {
      // Prefetch user hierarchy (saves upazila from chiefdoms[0].name) so the
      // lock screen profile card shows correct data on next background lock.
      context.read<UserHierarchyService>().prefetch().ignore();
      debugPrint('[_LoginScreenState] post-login: onboardingComplete=${auth.onboardingComplete} pinEnabled=${auth.pinEnabled} biometricEnabled=${auth.biometricEnabled}');
      if (!auth.onboardingComplete && !auth.pinEnabled) {
        // New user — kick off sync in background immediately so data arrives
        // while they complete PIN setup, then go to onboarding.
        debugPrint('[_LoginScreenState] new user → background sync + /onboarding');
        context.read<OfflineSyncService>().coldSync(wipeBeforeSync: true).ignore();
        context.go('/onboarding');
      } else if (!auth.pinEnabled && !auth.biometricEnabled) {
        // Returning user with no security enrolled (e.g. pre-PIN-mandate accounts).
        // Re-enter onboarding so user sees the "Set up security / Skip" choice.
        debugPrint('[_LoginScreenState] returning user, no security → /onboarding');
        context.go('/onboarding');
      } else {
        // Returning user with PIN or biometric — go to sync screen as normal.
        debugPrint('[_LoginScreenState] returning user → /sync');
        context.go('/sync');
      }
    } else {
      final msg = auth.error ?? LoginStrings.loginFailed;
      final isOffline = msg.contains('internet') || msg.contains('timed out');
      final hasPinOrBio = auth.pinEnabled ||
          (auth.biometricEnabled && auth.biometricAvailable);
      final isSessionExpired = _bannerMessage?.contains('expired') ?? false;
      if (isOffline && hasPinOrBio && !isSessionExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LoginStrings.offlineUsePinHint),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: auth.pinEnabled ? PinStrings.usePinShort : LoginStrings.useDeviceUnlock,
              onPressed: () {
                if (auth.pinEnabled) {
                  context.go('/pin-unlock');
                } else {
                  context.go('/lock');
                }
              },
            ),
          ),
        );
      } else if (isOffline && isSessionExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LoginStrings.sessionExpiredNeedOnline),
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild on specific field changes
    final showBio = context.select<AuthState, bool>(
      (a) => a.biometricEnabled && a.biometricAvailable,
    );
    final showPin = context.select<AuthState, bool>((a) => a.pinEnabled);
    final busy = context.select<AuthState, bool>((a) => a.busy);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Image.asset(
                      'assets/images/app-logo-name.png',
                      height: 56,
                      fit: BoxFit.contain,
                      semanticLabel: 'UHIS logo',
                    ),
                    const SizedBox(height: 32),
                    if (_bannerMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _bannerMessage!,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.fromLock && _bannerMessage == null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          LoginStrings.fromLockBanner,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (showBio || showPin) ...[
                      if (showBio)
                        OutlinedButton.icon(
                          onPressed: busy ? null : () => context.go('/lock'),
                          icon: const Icon(Icons.fingerprint),
                          label: Text(LoginStrings.useDeviceUnlock),
                        ),
                      if (showPin) ...[
                        if (showBio) const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => context.go('/pin-unlock'),
                          icon: const Icon(Icons.pin_outlined),
                          label: Text(PinStrings.usePin(AppConfig.pinLength)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(CommonStrings.or),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _userCtl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: LoginStrings.usernameLabel,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? CommonStrings.required
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: LoginStrings.passwordLabel,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? CommonStrings.required
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(LoginStrings.signIn),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => context.push('/forgot-password'),
                        child: Text(LoginStrings.forgotPassword),
                      ),
                    ),
                    // Medtronic Labs branding + logo temporarily hidden.
                    // const SizedBox(height: 48),
                    // Column(
                    //   children: [
                    //     Text(
                    //       AppStrings.poweredBy,
                    //       style: Theme.of(context).textTheme.bodySmall
                    //           ?.copyWith(
                    //             color: Theme.of(
                    //               context,
                    //             ).colorScheme.onSurfaceVariant,
                    //           ),
                    //       textAlign: TextAlign.center,
                    //     ),
                    //     const SizedBox(height: 8),
                    //     Image.asset(
                    //       'assets/images/medtronic-labs-logo.png',
                    //       height: 32,
                    //       fit: BoxFit.contain,
                    //       semanticLabel: 'Medtronic Labs logo',
                    //     ),
                    //   ],
                    // ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
