import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';

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

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthState>();
    final last = auth.username;
    if (last != null) {
      _userCtl.text = last;
    } else {
      _userCtl.text = 'hyper_sk';
    }
    if (_passCtl.text.isEmpty) _passCtl.text = 'Spice123';
  }

  @override
  void dispose() {
    _userCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthState>();
    final ok = await auth.login(_userCtl.text.trim(), _passCtl.text);
    if (!mounted) return;
    if (ok) {
      // Prefetch user hierarchy (saves upazila from chiefdoms[0].name) so the
      // lock screen profile card shows correct data on next background lock.
      context.read<UserHierarchyService>().prefetch().ignore();
      // Go to sync screen to download data before showing dashboard
      context.go('/sync');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? LoginStrings.loginFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild on specific field changes
    final showBio = context.select<AuthState, bool>((a) => a.biometricEnabled);
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
                    ),
                    const SizedBox(height: 32),
                    if (widget.fromLock)
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
                        child: const Text(
                          LoginStrings.fromLockBanner,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (showBio || showPin) ...[
                      if (showBio)
                        OutlinedButton.icon(
                          onPressed:
                              busy ? null : () => context.go('/lock'),
                          icon: const Icon(Icons.fingerprint),
                          label: const Text(LoginStrings.useDeviceUnlock),
                        ),
                      if (showPin) ...[
                        if (showBio) const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed:
                              busy ? null : () => context.go('/pin-unlock'),
                          icon: const Icon(Icons.pin_outlined),
                          label: Text(PinStrings.usePin(AppConfig.pinLength)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Row(children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(CommonStrings.or),
                        ),
                        Expanded(child: Divider()),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _userCtl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: LoginStrings.usernameLabel,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? CommonStrings.required : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: LoginStrings.passwordLabel,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? CommonStrings.required : null,
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
                          : const Text(LoginStrings.signIn),
                    ),
                    const SizedBox(height: 48),
                    Column(
                      children: [
                        Text(
                          AppStrings.poweredBy,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Image.asset(
                          'assets/images/medtronic-labs-logo.png',
                          height: 32,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
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
