import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import 'pin_pad.dart';

/// Mandatory first-run PIN setup: create, then confirm. Reached right after the
/// biometric offer on first dashboard load. No skip / no back — the user must
/// set a fallback PIN before continuing.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final int _len = AppConfig.pinLength;
  String _value = '';
  String? _firstEntry; // set once the create step is complete → confirm step
  String? _error;
  bool _busy = false;

  bool get _confirming => _firstEntry != null;

  Future<void> _onChanged(String v) async {
    debugPrint('[_PinSetupScreenState] _onChanged v.length=${v.length} confirming=$_confirming');
    setState(() {
      _value = v;
      _error = null;
    });
    if (v.length < _len) return;

    if (!_confirming) {
      setState(() {
        _firstEntry = v;
        _value = '';
      });
      return;
    }

    if (v == _firstEntry) {
      setState(() => _busy = true);
      final auth = context.read<AuthState>();
      await auth.enrolPin(v);
      if (!mounted) return;
      // PIN setup complete - go directly to home (sync already done before onboarding)
      context.go('/home');
    } else {
      setState(() {
        _error = PinStrings.mismatch;
        _firstEntry = null;
        _value = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: PinEntryView(
                  length: _len,
                  value: _value,
                  onChanged: _onChanged,
                  busy: _busy,
                  errorText: _error,
                  title: _confirming
                      ? PinStrings.confirmTitle
                      : PinStrings.createTitle(_len),
                  subtitle: _confirming ? null : PinStrings.createSubtitle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
