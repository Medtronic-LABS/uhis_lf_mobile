/// In-app update (download + install) flow entry points.
///
/// > **Reconstructed file** — see the note in `app_version_info.dart`. These are
/// > minimal reimplementations from the call sites; restore PR #689's original
/// > flow to re-enable the real APK download/install + resume behaviour.
import 'package:flutter/material.dart';

import '../constants/app_strings.dart';

/// Resumes an APK update that was mid-download/install when the app was last
/// killed. No-op in this reconstruction.
Future<void> resumeInProgressAppUpdateIfAny() async {}

/// Shows the blocking "update required" dialog after a forced-update login
/// failure. Reconstruction: an acknowledge-only dialog carrying the server's
/// [message] (the real flow also offers a Play Store deep link).
Future<void> showAppUpdateRequiredDialog(
  BuildContext context, {
  String? message,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppUpdateStrings.alertTitle),
      content: Text(message ?? AppUpdateStrings.pleaseUpdateTheApp),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(CommonStrings.ok),
        ),
      ],
    ),
  );
}
