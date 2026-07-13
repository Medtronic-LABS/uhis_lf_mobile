import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_strings.dart';
import '../core/widgets/mockup_svg_icons.dart';
import '../features/visit/visit_flow_screen.dart';
import 'theme.dart';

/// Shell widget for the persistent 3-tab bottom navigation.
/// Each tab maintains its own navigation stack.
///
/// TASKS-STASHED: the Tasks tab (StatefulShellBranch index 2 in
/// `router.dart`, routing to ReferralListScreen/ReferralDetailScreen) was
/// intentionally hidden from this bar per GitHub issue #84 (2026-07-13).
/// The branch itself, its route, and the 6 existing `context.go('/tasks')`
/// call sites elsewhere in the app (visit_complete_screen.dart,
/// visit_form_screen.dart, visit_flow_screen.dart, mission_dashboard_screen.dart)
/// are untouched and still fully functional — only the visible nav entry was
/// removed. Do NOT restore or further modify this without direct user
/// instruction. Search `TASKS-STASHED` for every related marker.
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
        SnackBar(
          content: Text(BottomNavStrings.pressBackAgainToExit),
          duration: const Duration(seconds: 2),
        ),
      );
    return true;
  }

  Future<void> _onTap(BuildContext context, int visibleIndex) async {
    final branchIndex = _visibleBranchIndices[visibleIndex];
    // Same tab tapped — just reset to root of that branch.
    if (branchIndex == widget.navigationShell.currentIndex) {
      widget.navigationShell.goBranch(branchIndex, initialLocation: true);
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
    widget.navigationShell.goBranch(branchIndex, initialLocation: true);
  }

  // TASKS-STASHED: maps visible nav-bar position -> real StatefulShellRoute
  // branch index. Branch 2 (Tasks, see router.dart "Tab 2: Tasks") is
  // deliberately excluded from this bar per GitHub issue #84 (2026-07-13) but
  // remains a live branch for existing direct `context.go('/tasks')` callers.
  static const List<int> _visibleBranchIndices = [0, 1, 3];

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final visiblePosition =
        _visibleBranchIndices.indexOf(widget.navigationShell.currentIndex);

    return Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.divider)),
          ),
          child: NavigationBar(
            // Falls back to 0 when currentIndex is the hidden Tasks branch
            // (reached via a direct call site, not this bar) — nothing in
            // the visible bar corresponds to it.
            selectedIndex: visiblePosition == -1 ? 0 : visiblePosition,
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
        title: Text(BottomNavStrings.assistantTitle),
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
