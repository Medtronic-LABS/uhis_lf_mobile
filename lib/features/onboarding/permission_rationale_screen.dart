import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/device/battery_optimization_gate.dart';
import '../../core/device/battery_optimization_prompt.dart';
import '../../core/device/battery_optimization_service.dart';
import '../../core/device/permission_gate.dart';

/// One card per permission, shown before Android asks anything.
///
/// Android offers no combined dialog — it shows one per permission group in
/// sequence — so this is what makes the sequence make sense. Without it an SK
/// sees four bare system prompts with no explanation of why any of them is
/// needed, which is how a non-technical user ends up denying all four.
///
/// Never blocks: both buttons continue onboarding. "Not now" simply skips the
/// request, leaving the existing point-of-use prompts to ask later if the SK
/// reaches a feature that needs one.
class PermissionRationaleSheet extends StatelessWidget {
  const PermissionRationaleSheet({super.key});

  /// Returns true when the SK chose to continue to the system prompts.
  static Future<bool> show(BuildContext context) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const PermissionRationaleSheet(),
    );
    return proceed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(PermissionStrings.title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(PermissionStrings.subtitle,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            const _PermissionRow(
              icon: Icons.photo_camera_outlined,
              titleKey: _Which.camera,
            ),
            const _PermissionRow(
              icon: Icons.mic_none_outlined,
              titleKey: _Which.microphone,
            ),
            const _PermissionRow(
              icon: Icons.location_on_outlined,
              titleKey: _Which.location,
            ),
            const _PermissionRow(
              icon: Icons.notifications_none_outlined,
              titleKey: _Which.notification,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(PermissionStrings.allow),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(PermissionStrings.skip),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kept private and enum-keyed rather than passing strings in, so the copy is
/// resolved at build time and follows a language switch.
enum _Which { camera, microphone, location, notification }

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.icon, required this.titleKey});

  final IconData icon;
  final _Which titleKey;

  (String, String) get _copy => switch (titleKey) {
        _Which.camera => (
            PermissionStrings.cameraTitle,
            PermissionStrings.cameraBody
          ),
        _Which.microphone => (
            PermissionStrings.microphoneTitle,
            PermissionStrings.microphoneBody
          ),
        _Which.location => (
            PermissionStrings.locationTitle,
            PermissionStrings.locationBody
          ),
        _Which.notification => (
            PermissionStrings.notificationTitle,
            PermissionStrings.notificationBody
          ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, body) = _copy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Runs the whole step: rationale, then the system prompts, then a nudge to
/// Settings if anything came back permanently denied.
///
/// Returns when the step is finished. Never throws and never blocks — an SK
/// who declines everything still reaches the dashboard with a working app.
Future<void> runPermissionStep(
  BuildContext context,
  PermissionGate gate,
) async {
  if (!await gate.shouldPrompt()) return;
  if (!context.mounted) return;

  final proceed = await PermissionRationaleSheet.show(context);
  if (!proceed) {
    // Declining still counts as asked — re-prompting next launch is exactly
    // the nagging this step removes. Records the flag WITHOUT firing the
    // system dialogs.
    await gate.declineWithoutAsking();
    return;
  }

  final statuses = await gate.requestAll();

  // Battery optimisation belongs to the same conversation: OEM power managers
  // kill the sync regardless of any runtime permission, and asking here means
  // one setup moment instead of this appearing separately on the dashboard.
  // Self-suppressing via its own flag, so the dashboard fallback becomes a
  // no-op once this has run.
  if (!context.mounted) return;
  await maybeShowBatteryOptimizationPrompt(
    context,
    BatteryOptimizationGate(
      service: kIsWeb
          ? const NoopBatteryOptimizationService()
          : const MethodChannelBatteryOptimizationService(),
    ),
  );

  // Last, so it is not buried under the dialog above.
  if (!PermissionGate.anyPermanentlyDenied(statuses)) return;
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(PermissionStrings.blockedMessage),
      action: SnackBarAction(
        label: PermissionStrings.openSettings,
        onPressed: () => gate.openSettings(),
      ),
      duration: const Duration(seconds: 8),
    ),
  );
}
