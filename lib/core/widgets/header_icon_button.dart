import 'package:flutter/material.dart';

/// Small circular icon button on a navy header — the mockup's own
/// back-button treatment (28×28, white 15%-alpha circle). Shared by every
/// screen with a navy hero header (Patients list, Household detail).
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.child,
  });

  final IconData icon;
  final String tooltip;

  /// Null disables the button (e.g. while an action it triggers is already
  /// in flight) — matches `IconButton.onPressed`'s null-disables convention.
  final VoidCallback? onTap;

  /// Overrides the rendered icon with an arbitrary widget (e.g. a loading
  /// spinner while `onTap` is null during a refresh) — `icon` is still
  /// required for the button's default state.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: child ?? Icon(icon, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}

/// Initials for an avatar (e.g. "Rafiqul Islam" -> "RI"). Shared by every
/// screen that renders an initials-circle member avatar.
String memberInitials(String? name) {
  if (name == null || name.isEmpty) return '';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}
