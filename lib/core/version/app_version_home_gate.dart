import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import 'app_update_controller.dart';
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
  late final AppUpdateController _updates = context.read<AppUpdateController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates.addListener(_onUpdateState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _updates.removeListener(_onUpdateState);
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
      unawaited(context.read<AppUpdateController>().refresh());
      final result = await service.check();
      if (!mounted) return;
      switch (result) {
        case final AppVersionUpdateRequired required:
          await enforceRequiredUpdate(context, required);
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

  void _onUpdateState() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_updates.restartReady) return widget.child;
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: _UpdateReadyBanner(onRestart: _updates.completeRestartIfSafe),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// Persistent, non-modal prompt shown once a flexible update has downloaded.
/// Restarting is always the user's tap — never automatic.
class _UpdateReadyBanner extends StatelessWidget {
  const _UpdateReadyBanner({required this.onRestart});

  final Future<bool> Function() onRestart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                AppUpdateStrings.updateReadyToRestart,
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
            TextButton(
              onPressed: () => onRestart(),
              child: Text(AppUpdateStrings.updateRestartAction),
            ),
          ],
        ),
      ),
    );
  }
}
