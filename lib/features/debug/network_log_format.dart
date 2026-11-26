import 'package:flutter/material.dart';

import '../../core/net_log/network_log_entry.dart';
import '../../core/theme/app_theme.dart';

/// Text and colour rules for one network log row, shared by the list and Copy.
abstract final class NetworkLogFormat {
  /// Shown as the status when a row has neither a code nor an error type.
  static const String unknownStatus = '-';

  static String time(NetworkLogEntry e) {
    final t = DateTime.fromMillisecondsSinceEpoch(e.startedAtMs);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// The status code, or the error type when the request never got a status.
  static String status(NetworkLogEntry e) =>
      e.statusCode?.toString() ?? e.errorType ?? unknownStatus;

  static String duration(NetworkLogEntry e) => '${e.durationMs ?? 0}';

  /// `time method status duration url`, the plain-text Copy format.
  static String line(NetworkLogEntry e) =>
      '${time(e)} ${e.method} ${status(e)} ${duration(e)} ${e.url}';

  static Color statusColor(NetworkLogEntry e) {
    final code = e.statusCode;
    if (code == null) return AppColors.rangeCrisis;
    if (code < 300) return AppColors.rangeNormal;
    if (code < 400) return AppColors.infoAccentDark;
    if (code < 500) return AppColors.rangeElevated;
    return AppColors.rangeCritical;
  }
}
