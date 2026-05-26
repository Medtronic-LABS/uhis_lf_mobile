import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';

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

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthState>();
    final last = auth.username;
    if (last != null) _userCtl.text = last;
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
      context.go('/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Login failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final showBio = auth.biometricEnabled;
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
                    Text(
                      'UHIS Next',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'MedtronicLabs · Frontline Health',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
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
                          'Biometric cancelled — sign in with password.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (showBio) ...[
                      OutlinedButton.icon(
                        onPressed: auth.busy
                            ? null
                            : () => context.go('/lock'),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Use device unlock'),
                      ),
                      const SizedBox(height: 16),
                      const Row(children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('or'),
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
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: auth.busy ? null : _submit,
                      child: auth.busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
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
