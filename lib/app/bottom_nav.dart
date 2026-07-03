import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_strings.dart';
import 'theme.dart';

/// Shell widget for the persistent 4-tab bottom navigation.
/// Each tab maintains its own navigation stack.
class BottomNavShell extends StatefulWidget {
  const BottomNavShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell>
    with WidgetsBindingObserver {
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called by Android when back is pressed and no child navigator consumed it.
  /// Return true = we handled it (suppress exit), false = let system exit.
  @override
  Future<bool> didPopRoute() async {
    if (!mounted) return false;
    if (widget.navigationShell.currentIndex != 0) {
      widget.navigationShell.goBranch(0, initialLocation: true);
      return true;
    }
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return true;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(BottomNavStrings.pressBackAgainToExit),
          duration: Duration(seconds: 2),
        ),
      );
    return true;
  }

  Future<void> _onTap(BuildContext context, int index) async {
    // Same tab tapped — just reset to root of that branch.
    if (index == widget.navigationShell.currentIndex) {
      widget.navigationShell.goBranch(index, initialLocation: true);
      return;
    }
    // If an active visit flow is running, ask before leaving.
    final path =
        GoRouter.of(context).routeInformationProvider.value.uri.path;
    final inVisitFlow =
        path.contains('/patients/visit/') && path.endsWith('/flow');
    if (inVisitFlow) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(BottomNavStrings.leaveVisitTitle),
          content: const Text(BottomNavStrings.leaveVisitBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(BottomNavStrings.resumeVisitAction),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(BottomNavStrings.leaveVisitAction),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    widget.navigationShell.goBranch(index, initialLocation: true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;

    return Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.divider)),
          ),
          child: NavigationBar(
            selectedIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: (index) => _onTap(context, index),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: BottomNavStrings.home,
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: BottomNavStrings.patients,
              ),
              NavigationDestination(
                icon: Icon(Icons.task_alt_outlined),
                selectedIcon: Icon(Icons.task_alt),
                label: BottomNavStrings.tasks,
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: BottomNavStrings.assistant,
              ),
            ],
          ),
        ),
    );
  }
}

/// Placeholder widget for the Assistant tab (empty state).
class AssistantPlaceholderScreen extends StatelessWidget {
  const AssistantPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(BottomNavStrings.assistantTitle),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_outlined,
              size: 80,
              color: tokens.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              BottomNavStrings.assistantPlaceholderHeading,
              style: textTheme.headlineSmall?.copyWith(
                color: tokens.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              BottomNavStrings.assistantPlaceholderSubheading,
              style: textTheme.bodyLarge?.copyWith(
                color: tokens.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
