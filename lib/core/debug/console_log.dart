import 'dart:convert';

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

  /// Dumps [payload] under [label] as indented JSON that can be copied
  /// straight into a REST client.
  ///
  /// Emitted in chunks because logcat drops very long lines — a full sync
  /// request printed as one line arrives truncated on device.
  static void json(String label, Object? payload) {
    String text;
    try {
      text = const JsonEncoder.withIndent('  ').convert(payload);
    } catch (_) {
      // Non-encodable value somewhere in the tree — the raw dump still helps.
      text = payload.toString();
    }
    banner(label);
    const chunkSize = 800;
    for (var i = 0; i < text.length; i += chunkSize) {
      final end = i + chunkSize > text.length ? text.length : i + chunkSize;
      debugPrint(text.substring(i, end));
    }
  }
}
