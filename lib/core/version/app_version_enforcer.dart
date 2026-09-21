import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_version_service.dart';

/// Navigates to `/home` once the version check clears. Permissive
/// reconstruction: the check never blocks, so this always routes home.
Future<void> goHomeIfUpToDate(BuildContext context) async {
  if (!context.mounted) return;
  context.go('/home');
}

/// Surfaces a one-time optional-update prompt after login when a newer version
/// exists. No-op in this reconstruction.
Future<void> promptOptionalUpdateIfNeeded(BuildContext context) async {}

/// Holds the [AppVersionService] and drives version enforcement for the widget
/// tree (provided via `Provider<AppVersionEnforcer>`).
///
/// > **Reconstructed file** — see the note in `app_version_info.dart`. Minimal
/// > reimplementation: it exposes the service but performs no blocking, so the
/// > app runs normally. Restore PR #689's original enforcer for real behaviour.
class AppVersionEnforcer {
  AppVersionEnforcer(this.service);

  final AppVersionService service;
}
