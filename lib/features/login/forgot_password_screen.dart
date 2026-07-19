import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/constants/app_strings.dart';
import '../../core/debug/console_log.dart';
import '../../core/errors/domain_exceptions.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  bool _busy = false;
  String? _successMessage;
  String? _errorMessage;

  @override
  void dispose() {
    debugPrint('[_ForgotPasswordScreenState] dispose');
    _emailCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint('[_ForgotPasswordScreenState] _submit');
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _successMessage = null;
      _errorMessage = null;
    });
    final email = _emailCtl.text.trim();
    ConsoleLog.step('[ForgotPw] request sent for $email');
    try {
      final client = context.read<ApiClient>();
      await client.dio.post<void>(Endpoints.forgotPassword(email));
      if (!mounted) return;
      ConsoleLog.success('[ForgotPw] reset email dispatched');
      setState(() => _successMessage = LoginStrings.forgotPasswordSuccess);
    } catch (e) {
      if (!mounted) return;
      ConsoleLog.warn('[ForgotPw] error: ${NetworkErrorMapper.friendly(e)}');
      setState(() => _errorMessage = NetworkErrorMapper.friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LoginStrings.forgotPasswordTitle),
        leading: BackButton(onPressed: () => context.pop()),
      ),
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
                    if (_successMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 18, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _successMessage!,
                                style: TextStyle(color: Colors.green.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_errorMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextFormField(
                      controller: _emailCtl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enabled: !_busy && _successMessage == null,
                      decoration: InputDecoration(
                        labelText: LoginStrings.emailLabel,
                        hintText: LoginStrings.forgotPasswordHint,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return CommonStrings.required;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed:
                          _busy || _successMessage != null ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(LoginStrings.forgotPasswordSend),
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
