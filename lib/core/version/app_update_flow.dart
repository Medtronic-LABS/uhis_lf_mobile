/// In-app update entry points (LEAP-144): the blocking "update required"
/// dialog, its dismissible warning variants, the optional-update prompt, and
/// the store fallback.
///
/// Play interaction itself lives in [AppUpdateController]; this file is only
/// the UI that reacts to its decisions and outcomes.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../config/app_config.dart';
import '../constants/app_strings.dart';
import 'app_update_controller.dart';
import 'app_version_service.dart';
import 'required_update_guard.dart';

/// Installer package name Google Play stamps on apps it installs.
const String _playInstaller = 'com.android.vending';

bool _forcedDialogShowing = false;

/// Whether this platform/flavor can use Play updates at all.
bool get supportsPlayUpdate =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    !AppConfig.isTrainingBuild;

/// Applies the required-update policy for [result]. Returns true when the
/// caller may continue (nothing to enforce, or a dismissible warning was
/// shown); the blocking dialog never lets the future resolve normally, so a
/// caller that gets `false` must stay where it is.
Future<bool> enforceRequiredUpdate(
  BuildContext context,
  AppVersionUpdateRequired result,
) async {
  final controller = context.read<AppUpdateController>();
  final decision = await controller.resolve(result);
  if (!context.mounted) return true;
  switch (decision) {
    case RequiredUpdateDecision.blockWithUpdate:
      if (controller.deferRequiredOnce()) return true;
      await showAppUpdateRequiredDialog(
        context,
        message: AppUpdateStrings.forcedUpdateMessage(result.minVersionLabel),
      );
      return false;
    case RequiredUpdateDecision.warn:
    case RequiredUpdateDecision.warnStranded:
      if (controller.takeWarningSlot()) {
        await _showWarningDialog(
          context,
          message: _warningMessage(decision),
        );
      }
      return true;
  }
}

String _warningMessage(RequiredUpdateDecision decision) {
  if (AppConfig.isTrainingBuild) return AppUpdateStrings.updateAskAdminForNewBuild;
  return decision == RequiredUpdateDecision.warnStranded
      ? AppUpdateStrings.requiredUpdateContactSupport
      : AppUpdateStrings.requiredUpdateNotYetAvailable;
}

/// Blocking "update required" dialog. It cannot be dismissed (no barrier
/// tap, no back) and its only action starts the update, so the app stays
/// unusable until the user installs the minimum version. Only shown where
/// Play can deliver the build (see [decideRequiredUpdate]). The returned
/// future completes only if the dialog is torn down with its route.
Future<void> showAppUpdateRequiredDialog(
  BuildContext context, {
  String? message,
}) async {
  if (!context.mounted || _forcedDialogShowing) return;
  _forcedDialogShowing = true;
  _trackUpdate(AnalyticsEvent.appUpdatePrompt, AnalyticsValue.force);
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
              onPressed: () {
                _trackUpdate(AnalyticsEvent.appUpdateAction,
                    AnalyticsValue.force, AnalyticsValue.update);
                _startRequiredUpdate(dialogContext);
              },
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

Future<void> _showWarningDialog(
  BuildContext context, {
  required String message,
}) =>
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppUpdateStrings.alertTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppUpdateStrings.ok),
          ),
        ],
      ),
    );

/// Dismissible prompt for a newer-but-not-required version.
Future<void> showOptionalUpdateDialog(
  BuildContext context, {
  required String message,
}) async {
  if (!context.mounted || _forcedDialogShowing) return;
  _trackUpdate(AnalyticsEvent.appUpdatePrompt, AnalyticsValue.optional);
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
  _trackUpdate(AnalyticsEvent.appUpdateAction, AnalyticsValue.optional,
      update == true ? AnalyticsValue.update : AnalyticsValue.later);
  if (update == true && context.mounted) await _startOptionalUpdate(context);
}

/// GA `app_update_prompt` / `app_update_action` (LEAP-152).
void _trackUpdate(String event, String type, [String? action]) =>
    Analytics.event(event, {
      AnalyticsParam.type: type,
      AnalyticsParam.action: action,
    });

Future<void> _startRequiredUpdate(BuildContext context) async {
  final outcome =
      await context.read<AppUpdateController>().startRequiredUpdate();
  if (!context.mounted) return;
  await _handleOutcome(context, outcome);
}

Future<void> _startOptionalUpdate(BuildContext context) async {
  final outcome =
      await context.read<AppUpdateController>().startOptionalUpdate();
  if (!context.mounted) return;
  await _handleOutcome(context, outcome);
}

Future<void> _handleOutcome(
  BuildContext context,
  AppUpdateOutcome outcome,
) async {
  switch (outcome) {
    case AppUpdateInstalled():
    case AppUpdateDownloading():
    case AppUpdateCancelled():
      return;
    case AppUpdateUnavailable():
    case AppUpdateFailed():
      if (await _storeFallbackWorthTrying()) {
        if (!context.mounted) return;
        await _openStoreListing(context);
        return;
      }
      if (!context.mounted) return;
      _showSnack(context, AppUpdateStrings.updateCouldNotComplete);
  }
}

/// The installer source is a hint, not a gate: only when Play itself
/// installed this build is a store listing likely to exist and to be useful.
Future<bool> _storeFallbackWorthTrying() async {
  if (!supportsPlayUpdate) return false;
  final installer = (await PackageInfo.fromPlatform()).installerStore;
  return installer == _playInstaller;
}

Future<void> _openStoreListing(BuildContext context) async {
  final packageName = (await PackageInfo.fromPlatform()).packageName;
  final market = Uri.parse('market://details?id=$packageName');
  final web =
      Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
  try {
    if (await launchUrl(market, mode: LaunchMode.externalApplication)) return;
    if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
  } on PlatformException catch (e) {
    debugPrint('[AppUpdate] could not open store listing: ${e.code}');
  }
  if (!context.mounted) return;
  _showSnack(context, AppUpdateStrings.pleaseCheckIfPlayStoreAvailable);
}

void _showSnack(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
