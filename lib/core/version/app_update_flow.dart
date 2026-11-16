/// In-app update entry points (LEAP-144): the blocking force-update dialog,
/// the dismissible optional-update prompt, and the Play update itself.
///
/// The update uses Google Play's in-app update (immediate flow) when Play
/// reports one available; otherwise — sideloaded build, Play not yet serving
/// the new version, no Play Store — it falls back to opening the store page.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_strings.dart';

bool _forcedDialogShowing = false;

bool get _supportsPlayUpdate =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Resumes an immediate update Play left in progress when the app was last
/// backgrounded/killed. Play requires the app to re-show it on resume.
Future<void> resumeInProgressAppUpdateIfAny() async {
  if (!_supportsPlayUpdate) return;
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability ==
        UpdateAvailability.developerTriggeredUpdateInProgress) {
      await InAppUpdate.performImmediateUpdate();
    }
  } catch (e) {
    // Not installed from Play (debug/sideload) or Play unavailable.
    debugPrint('[AppUpdate] resume check skipped: $e');
  }
}

/// Blocking "update required" dialog. It cannot be dismissed (no barrier
/// tap, no back) and its only action starts the update, so the app stays
/// unusable until the user installs the minimum version. The returned future
/// completes only if the dialog is torn down with its route.
Future<void> showAppUpdateRequiredDialog(
  BuildContext context, {
  String? message,
}) async {
  if (!context.mounted || _forcedDialogShowing) return;
  _forcedDialogShowing = true;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(AppUpdateStrings.alertTitle),
          content: Text(message ?? AppUpdateStrings.pleaseUpdateTheApp),
          actions: [
            FilledButton(
              onPressed: () => startAppUpdate(dialogContext),
              child: Text(AppUpdateStrings.openPlayStore),
            ),
          ],
        ),
      ),
    );
  } finally {
    _forcedDialogShowing = false;
  }
}

/// Dismissible prompt for a newer-but-not-required version.
Future<void> showOptionalUpdateDialog(
  BuildContext context, {
  required String message,
}) async {
  if (!context.mounted || _forcedDialogShowing) return;
  final update = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppUpdateStrings.alertTitle),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(AppUpdateStrings.updateLater),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(AppUpdateStrings.openPlayStore),
        ),
      ],
    ),
  );
  if (update == true && context.mounted) await startAppUpdate(context);
}

/// Starts the Play immediate update when available, else opens the store.
Future<void> startAppUpdate(BuildContext context) async {
  if (_supportsPlayUpdate) {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed) {
        final result = await InAppUpdate.performImmediateUpdate();
        if (result == AppUpdateResult.success) return;
      }
    } catch (e) {
      debugPrint('[AppUpdate] Play in-app update unavailable: $e');
    }
  }
  if (!context.mounted) return;
  await _openStoreListing(context);
}

Future<void> _openStoreListing(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final packageName = (await PackageInfo.fromPlatform()).packageName;
    final market = Uri.parse('market://details?id=$packageName');
    if (await launchUrl(market, mode: LaunchMode.externalApplication)) return;
    final web =
        Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
    if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
  } catch (e) {
    debugPrint('[AppUpdate] could not open store listing: $e');
  }
  messenger?.showSnackBar(
    SnackBar(content: Text(AppUpdateStrings.pleaseCheckIfPlayStoreAvailable)),
  );
}
