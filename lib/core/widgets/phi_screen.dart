import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Base class for screens that display PHI (Protected Health Information).
///
/// On Android, sets FLAG_SECURE via a MethodChannel so the screen is excluded
/// from screenshots and the recent-apps thumbnail. On web, this is a no-op.
///
/// flutter_windowmanager 0.2.0 uses jcenter() (removed in AGP 8+) so we call
/// the platform directly. Wire the host side in MainActivity.kt:
///
/// ```kotlin
/// MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uhis/window")
///   .setMethodCallHandler { call, result ->
///     when (call.method) {
///       "addFlagSecure"   -> { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE);   result.success(null) }
///       "clearFlagSecure" -> { window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
///       else              -> result.notImplemented()
///     }
///   }
/// ```
///
/// Usage:
/// ```dart
/// class PatientContextScreen extends PhiScreen {
///   const PatientContextScreen({super.key, required this.patientId});
///   final String patientId;
///
///   @override
///   PhiScreenState<PatientContextScreen> createState() =>
///       _PatientContextScreenState();
/// }
///
/// class _PatientContextScreenState
///     extends PhiScreenState<PatientContextScreen> {
///   @override
///   Widget buildPhi(BuildContext context) { ... }
/// }
/// ```
abstract class PhiScreen extends StatefulWidget {
  const PhiScreen({super.key});
}

abstract class PhiScreenState<T extends PhiScreen> extends State<T> {
  static const _channel = MethodChannel('uhis/window');

  @override
  void initState() {
    super.initState();
    _setSecure(true);
  }

  @override
  void dispose() {
    _setSecure(false);
    super.dispose();
  }

  static Future<void> _setSecure(bool secure) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod(
          secure ? 'addFlagSecure' : 'clearFlagSecure');
    } on MissingPluginException {
      // Host-side MethodChannel not yet wired — safe to ignore in dev.
    }
  }

  @override
  Widget build(BuildContext context) => buildPhi(context);

  /// Override this instead of [build] to get PHI protection for free.
  Widget buildPhi(BuildContext context);
}
