import 'package:flutter/foundation.dart';

/// ANSI-coloured step tracing for local dev consoles (`flutter run` terminal,
/// `adb logcat`) — purely a debug aid, never user-facing copy. Terminals that
/// don't render ANSI just show the raw escape codes, which is harmless.
class ConsoleLog {
  const ConsoleLog._();

  static const _reset = '\x1B[0m';
  static const _cyan = '\x1B[36m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _magenta = '\x1B[35m';

  static void step(String message) => debugPrint('$_cyan$message$_reset');
  static void success(String message) => debugPrint('$_green$message$_reset');
  static void warn(String message) => debugPrint('$_yellow$message$_reset');
  static void banner(String message) => debugPrint('$_magenta$message$_reset');
}
