import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';

/// Wraps runtime RECORD_AUDIO permission request with rationale dialog.
class ScribePermissionService {
  /// Returns true if mic permission is granted (or already was).
  /// Shows rationale sheet if needed; opens Settings if permanently denied.
  Future<bool> ensureMicPermission(BuildContext context) async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (context.mounted) await _showSettingsDialog(context);
      return false;
    }

    // Show rationale before the system dialog on first ask.
    if (context.mounted) {
      final proceed = await _showRationaleSheet(context);
      if (!proceed) return false;
    }

    final result = await Permission.microphone.request();
    if (result.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context);
    }
    return result.isGranted;
  }

  Future<bool> _showRationaleSheet(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _RationaleSheet(),
    );
    return result ?? false;
  }

  Future<void> _showSettingsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Microphone access needed'),
        content: const Text(
          'AI Scribe needs microphone access to record consultations. '
          'Enable it in Settings → App permissions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _RationaleSheet extends StatelessWidget {
  const _RationaleSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.aiSurfaceStart,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mic, color: AppColors.aiPurple, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Scribe',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Voice → clinical note',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _BulletItem(
            icon: Icons.mic_none,
            text: 'Records consultation audio',
          ),
          _BulletItem(
            icon: Icons.check_circle_outline,
            text: 'You review and accept before it saves',
          ),
          _BulletItem(
            icon: Icons.delete_outline,
            text: 'Audio deleted from server after processing',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Allow'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.aiPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
