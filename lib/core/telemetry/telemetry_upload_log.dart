import 'package:flutter/foundation.dart';

/// Debug-only tracing for telemetry upload POSTs.
///
/// Wrapped in [kDebugMode] so release/production builds stay silent — unlike
/// bare [debugPrint], which still emits on device logcat in release.
void telemetryUploadLog(String message) {
  if (kDebugMode) debugPrint(message);
}
