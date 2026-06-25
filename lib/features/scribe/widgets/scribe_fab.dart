import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../scribe_controller.dart';
import '../scribe_session.dart';

/// Floating action button for AI Scribe recording.
///
/// Shows record/stop/retry states and handles recording lifecycle.
class ScribeFab extends StatelessWidget {
  const ScribeFab({
    super.key,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onOpenReview,
    required this.onRetry,
  });

  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onOpenReview;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Consumer<ScribeController>(
      builder: (context, ctrl, _) {
        final session = ctrl.session;

        // Hide FAB when processing, reviewing, or accepted/rejected
        if (session.state == ScribeState.processing ||
            session.state == ScribeState.reviewReady ||
            session.state == ScribeState.accepted ||
            session.state == ScribeState.rejected) {
          return const SizedBox.shrink();
        }

        // Show retry button on error
        if (session.state == ScribeState.error) {
          return FloatingActionButton.extended(
            onPressed: onRetry,
            tooltip: 'Retry AI Scribe',
            backgroundColor: Colors.orange,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Retry', style: TextStyle(color: Colors.white)),
          );
        }

        // Show stop button when recording
        if (session.state == ScribeState.recording) {
          return FloatingActionButton.extended(
            onPressed: onStopRecording,
            tooltip: 'Stop recording',
            backgroundColor: Colors.red,
            icon: const Icon(Icons.stop, color: Colors.white),
            label: Text(
              'Stop (${_formatDuration(session.elapsedSeconds)})',
              style: const TextStyle(color: Colors.white),
            ),
          );
        }

        // Show uploading state
        if (session.state == ScribeState.uploading) {
          return FloatingActionButton.extended(
            onPressed: null,
            tooltip: 'Uploading audio',
            backgroundColor: Colors.grey,
            icon: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            label: const Text('Uploading...', style: TextStyle(color: Colors.white)),
          );
        }

        // Default: show record button
        return FloatingActionButton.extended(
          onPressed: onStartRecording,
          tooltip: 'Start AI Scribe recording',
          backgroundColor: Theme.of(context).primaryColor,
          icon: const Icon(Icons.mic, color: Colors.white),
          label: const Text('AI Scribe', style: TextStyle(color: Colors.white)),
        );
      },
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// Pill-shaped status indicator shown during scribe workflow.
///
/// Appears during recording, uploading, processing, and when ready for review.
class ScribePill extends StatelessWidget {
  const ScribePill({
    super.key,
    required this.onStop,
  });

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Consumer<ScribeController>(
      builder: (context, ctrl, _) {
        final session = ctrl.session;

        // Only show pill during active states
        if (session.state == ScribeState.idle ||
            session.state == ScribeState.requestingPermission ||
            session.state == ScribeState.accepted ||
            session.state == ScribeState.rejected) {
          return const SizedBox.shrink();
        }

        Color bgColor;
        IconData icon;
        String label;
        Widget? trailing;

        switch (session.state) {
          case ScribeState.recording:
            bgColor = Colors.red;
            icon = Icons.mic;
            label = 'Recording ${_formatDuration(session.elapsedSeconds)}';
            trailing = IconButton(
              tooltip: 'Stop recording',
              icon: const Icon(Icons.stop, color: Colors.white, size: 20),
              onPressed: onStop,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            );
            break;

          case ScribeState.uploading:
            bgColor = Colors.orange;
            icon = Icons.cloud_upload;
            label = 'Uploading...';
            trailing = const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            );
            break;

          case ScribeState.processing:
            bgColor = Colors.blue;
            icon = Icons.auto_awesome;
            label = 'Processing...';
            trailing = const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            );
            break;

          case ScribeState.reviewReady:
            bgColor = Colors.green;
            icon = Icons.check_circle;
            label = 'Ready for review';
            trailing = const Icon(Icons.chevron_right, color: Colors.white, size: 20);
            break;

          case ScribeState.error:
            bgColor = Colors.red.shade800;
            icon = Icons.error_outline;
            label = session.errorMessage ?? 'Error occurred';
            trailing = null;
            break;

          default:
            return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
