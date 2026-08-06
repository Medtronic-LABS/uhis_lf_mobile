import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_repository.dart';
import '../core/config/app_config.dart';
import '../core/constants/app_strings.dart';
import '../core/i18n/app_locale.dart';
import '../core/services/micro_coaching_service.dart';
import '../core/widgets/mockup_svg_icons.dart';
import 'theme.dart';

/// Shell widget for the persistent 3-tab bottom navigation.
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
        SnackBar(
          content: Text(BottomNavStrings.pressBackAgainToExit),
          duration: const Duration(seconds: 2),
        ),
      );
    return true;
  }

  // Assistant tab visible index — tap launches SDK instead of navigating.
  static const int _assistantVisibleIndex = 2;

  Future<void> _launchMicroCoaching(BuildContext context) async {
    try {
      final repo = context.read<AuthRepository>();
      final userId = await repo.userId();
      final chwId = userId?.toString() ?? 'chw_unknown';
      if (!await MicroCoachingService.isInitialized()) {
        final token = await repo.getToken();
        if (token == null || token.isEmpty) throw Exception('No auth token');
        await MicroCoachingService.initialize(
          authToken: token,
          backendUrl: AppConfig.coachingServiceUrl,
          language: AppLocale.isBangla ? 'bn' : 'en',
          hfToken: AppConfig.hfToken,
        );
      }
      await MicroCoachingService.launch(chwId);
    } catch (e) {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AssistantStrings.errorMessage),
          duration: const Duration(seconds: 3),
        ));
    }
  }

  Future<void> _onTap(BuildContext context, int visibleIndex) async {
    if (visibleIndex == _assistantVisibleIndex) {
      await _launchMicroCoaching(context);
      return;
    }
    // Visit flow now lives on the root navigator (see router.dart), so it's
    // never shown under this bar — no need to guard tab switches against an
    // in-progress visit here; VisitFlowScreen's own PopScope already confirms
    // before leaving via the back button.
    final branchIndex = _visibleBranchIndices[visibleIndex];
    widget.navigationShell.goBranch(branchIndex, initialLocation: true);
  }

  // Maps visible nav-bar position -> real StatefulShellRoute branch index.
  static const List<int> _visibleBranchIndices = [0, 1, 2];

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
