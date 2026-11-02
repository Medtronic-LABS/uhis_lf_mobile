import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_strings.dart';

/// Requests camera + microphone permission before a Shukhee video call is
/// ever started. `ShukheeCallView` (shukhee_sdk) auto-grants whatever the
/// WebView's own permission-request delegate is offered by the OS -- it must
/// never be the thing that first surfaces the OS prompt, since a mid-call
/// prompt (or a silent no-op if the OS never asked) is a confusing failure
/// mode. This mirrors `ScribePermissionService`'s status-check-first pattern,
/// batched here since a video call needs both permissions together (unlike
/// Scribe's audio-only need).
class TeleconsultPermissionService {
  /// Returns true only once both camera and microphone are granted. Shows a
  /// Settings-redirect dialog if either is permanently denied.
  Future<bool> ensureCameraAndMicPermission(BuildContext context) async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    final allGranted = statuses.values.every((s) => s.isGranted);
    if (allGranted) return true;

    if (statuses.values.any((s) => s.isPermanentlyDenied) && context.mounted) {
      await _showSettingsDialog(context);
    }
    return false;
  }

  Future<void> _showSettingsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TeleconsultStrings.cameraMicRequiredTitle),
        content: Text(TeleconsultStrings.cameraMicRequiredBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ScribeStrings.settingsCancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: Text(ScribeStrings.settingsOpen),
          ),
        ],
      ),
    );
  }
}
