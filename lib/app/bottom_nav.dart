import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_strings.dart';
import '../core/widgets/mockup_svg_icons.dart';
import '../features/visit/visit_flow_screen.dart';
import 'theme.dart';

/// Shell widget for the persistent 5-tab bottom navigation.
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
      final leave = await showLeaveVisitDialog(context);
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
            destinations: [
              NavigationDestination(
                icon: _NavIcon(builder: MockupIcons.navHome, isSelected: false),
                selectedIcon: _NavIcon(builder: MockupIcons.navHome, isSelected: true),
                label: BottomNavStrings.home,
              ),
              NavigationDestination(
                icon: _NavIcon(builder: MockupIcons.navPatients, isSelected: false),
                selectedIcon: _NavIcon(builder: MockupIcons.navPatients, isSelected: true),
                label: BottomNavStrings.patients,
              ),
              NavigationDestination(
                icon: _NavIcon(builder: MockupIcons.navTasks, isSelected: false),
                selectedIcon: _NavIcon(builder: MockupIcons.navTasks, isSelected: true),
                label: BottomNavStrings.tasks,
              ),
              NavigationDestination(
                icon: _NavIcon(builder: MockupIcons.navAssistant, isSelected: false),
                selectedIcon: _NavIcon(builder: MockupIcons.navAssistant, isSelected: true),
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

/// Bottom-nav icon matching the v13 mockup's exact dual selection mechanism:
/// fill-hex swap (`#9CA3AF` inactive → `#1B2B5E` active) *and* an opacity
/// transition (`0.35` inactive → `1`) layered on top of it — both are present
/// simultaneously in the mockup's CSS/markup, not just one or the other.
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.builder, required this.isSelected});

  final Widget Function({double size, required Color color}) builder;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isSelected ? 1 : 0.35,
      duration: const Duration(milliseconds: 150),
      child: builder(color: isSelected ? AppColors.navy : const Color(0xFF9CA3AF)),
    );
  }
}
