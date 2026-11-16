import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import 'app_update_flow.dart';
import 'app_version_service.dart';

/// Navigates to `/home` unless the cached version policy says this build is
/// below the minimum, in which case the blocking update dialog is shown
/// instead.
///
/// Used on PIN/biometric unlock and after sync — paths that never go through
/// login, so without this a returning user would bypass the force update.
/// Uses the cached policy only so unlock never waits on the network;
/// [AppVersionHomeGate] refreshes the policy once home is showing.
Future<void> goHomeIfUpToDate(BuildContext context) async {
  if (!context.mounted) return;
  final service = context.read<AppVersionEnforcer>().service;
  final result = await service.cachedResult();
  if (!context.mounted) return;
  if (result is AppVersionUpdateRequired) {
    await showAppUpdateRequiredDialog(
      context,
      message: AppUpdateStrings.forcedUpdateMessage(result.minVersionLabel),
    );
    return;
  }
  context.go('/home');
}

/// Shows the one-time optional-update prompt after login when the last
/// check reported a newer (but not required) version.
Future<void> promptOptionalUpdateIfNeeded(BuildContext context) async {
  if (!context.mounted || !AppVersionService.needsOptionalPrompt) return;
  AppVersionService.markOptionalPromptShown();
  await showOptionalUpdateDialog(
    context,
    message: AppUpdateStrings.optionalUpdateMessage(
      AppVersionService.optionalUpdateLabel,
    ),
  );
}

/// Holds the [AppVersionService] for the widget tree
/// (provided via `Provider<AppVersionEnforcer>`).
class AppVersionEnforcer {
  AppVersionEnforcer(this.service);

  final AppVersionService service;
}
