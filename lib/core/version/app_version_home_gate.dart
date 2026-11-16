import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import 'app_update_flow.dart';
import 'app_version_enforcer.dart';
import 'app_version_service.dart';

/// Wraps the home screen and refreshes the version policy over it.
///
/// Runs a network check when home first paints and again when the app comes
/// back to the foreground (at most every [_recheckInterval]). A build below
/// the minimum gets the blocking update dialog; a build below the latest gets
/// the optional prompt once per session. Checks that can't reach the server
/// fall back to the cached policy and never block on their own.
class AppVersionHomeGate extends StatefulWidget {
  const AppVersionHomeGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppVersionHomeGate> createState() => _AppVersionHomeGateState();
}

class _AppVersionHomeGateState extends State<AppVersionHomeGate>
    with WidgetsBindingObserver {
  static const Duration _recheckInterval = Duration(minutes: 30);

  DateTime? _lastCheck;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) >= _recheckInterval) {
      _check();
    }
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final service = context.read<AppVersionEnforcer>().service;
      final result = await service.check();
      if (!mounted) return;
      switch (result) {
        case AppVersionUpdateRequired(:final minVersionLabel):
          await showAppUpdateRequiredDialog(
            context,
            message: AppUpdateStrings.forcedUpdateMessage(minVersionLabel),
          );
        case AppVersionUpdateAvailable():
          await promptOptionalUpdateIfNeeded(context);
        case AppVersionUpToDate():
        case AppVersionCheckFailed():
          break;
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
