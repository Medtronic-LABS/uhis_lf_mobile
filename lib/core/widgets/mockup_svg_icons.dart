import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Pixel-exact icon glyphs copied verbatim (path data) from the v13 HTML
/// design mockup's inline `<svg>` markup, so these render identically to the
/// design reference instead of approximating with the nearest Material icon.
/// Colored via [ColorFilter] so one path constant serves every state (active/
/// inactive) without needing per-color string variants.
abstract final class MockupIcons {
  MockupIcons._();

  static const String _search =
      'M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z';

  static const String _chevronDown =
      'M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6z';

  static const String _navHome =
      'M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z';

  static const String _navPatients =
      'M12 2a5 5 0 1 0 0 10A5 5 0 0 0 12 2zm0 12c-5.33 0-8 2.67-8 4v2h16v-2c0-1.33-2.67-4-8-4z';

  static const String _navTasks =
      'M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm-7 14l-5-5 1.41-1.41L12 14.17l7.59-7.59L21 8l-9 9z';

  static const String _navAssistant =
      'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-2 12H6v-2h12v2zm0-3H6V9h12v2zm0-3H6V6h12v2z';

  static Widget search({double size = 16, Color color = const Color(0xFF9CA3AF)}) =>
      _path(_search, size: size, color: color);

  static Widget chevronDown({double size = 10, Color color = const Color(0xFF6B63D4)}) =>
      _path(_chevronDown, size: size, color: color);

  static Widget navHome({double size = 20, required Color color}) =>
      _path(_navHome, size: size, color: color);

  static Widget navPatients({double size = 20, required Color color}) =>
      _path(_navPatients, size: size, color: color);

  static Widget navTasks({double size = 20, required Color color}) =>
      _path(_navTasks, size: size, color: color);

  static Widget navAssistant({double size = 20, required Color color}) =>
      _path(_navAssistant, size: size, color: color);

  static Widget _path(String d, {required double size, required Color color}) {
    return SvgPicture.string(
      '<svg viewBox="0 0 24 24"><path d="$d"/></svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
