import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'enrollment_controller.dart';
import 'enrollment_nid_scan_screen.dart';
import 'create_household_screen.dart';
import 'household_head_info_screen.dart';
import 'household_created_screen.dart';
import 'add_household_member_screen.dart';

/// Full-screen overlay dialog that manages the entire household enrollment
/// flow through an internal [Navigator], keeping all 5 steps within a single
/// modal without any GoRouter route changes.
///
/// Usage:
/// ```dart
/// HouseholdEnrollmentSheet.show(context);
/// ```
///
/// The overlay slides up from the bottom with a 300 ms ease-out cubic curve,
/// presents a rounded-top-corners container over a 75 % black barrier, and
/// exposes a shared header pattern (back arrow / title / X close) that each
/// step screen implements via [EnrollmentOverlayShell].
class HouseholdEnrollmentSheet extends StatelessWidget {
  const HouseholdEnrollmentSheet({super.key});

  // ── Internal route names ──────────────────────────────────────────────────

  static const String _routeCreate = '/create';
  static const String _routeHeadInfo = '/head-info';
  static const String _routeCreated = '/created';
  static const String _routeAddMember = '/add-member';

  // ── Entry point ──────────────────────────────────────────────────────────

  /// Presents the enrollment overlay. Returns when the user completes or
  /// dismisses the flow.
  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss enrollment',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (ctx, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
      pageBuilder: (ctx, _, animation) => ChangeNotifierProvider(
        create: (_) => EnrollmentController(),
        child: const HouseholdEnrollmentSheet(),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFF5F6FB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Drag handle pill ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCDD0D8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // ── Inner navigator ───────────────────────────────────────────
            Expanded(
              child: Navigator(
                onGenerateRoute: (settings) {
                  final Widget page;
                  switch (settings.name) {
                    case _routeCreate:
                      page = const CreateHouseholdScreen();
                      break;
                    case _routeHeadInfo:
                      page = const HouseholdHeadInfoScreen();
                      break;
                    case _routeCreated:
                      page = const HouseholdCreatedScreen();
                      break;
                    case _routeAddMember:
                      page = const AddHouseholdMemberScreen();
                      break;
                    default: // _routeRoot
                      page = const EnrollmentNidScanScreen();
                  }
                  return MaterialPageRoute<void>(
                    builder: (_) => page,
                    settings: settings,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared header row used by every enrollment step screen.
///
/// Renders:
/// - A back arrow that pops the inner navigator (or is hidden on the first
///   step and success screens via [showBack]).
/// - A centered [title].
/// - An X button that calls `Navigator.of(context, rootNavigator: true).pop()`
///   to dismiss the entire overlay.
class EnrollmentOverlayHeader extends StatelessWidget {
  const EnrollmentOverlayHeader({
    super.key,
    required this.title,
    this.showBack = true,
  });

  final String title;

  /// Set to false on the NID scan (first) step and the success screen where
  /// there is no meaningful back destination.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          // Back arrow — inner navigator pop
          SizedBox(
            width: 48,
            child: showBack
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF1B2B5E)),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : const SizedBox.shrink(),
          ),
          // Title
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B2B5E),
              ),
            ),
          ),
          // Close X — dismisses the overlay
          SizedBox(
            width: 48,
            child: IconButton(
              icon: const Icon(Icons.close, color: Color(0xFF1B2B5E)),
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
