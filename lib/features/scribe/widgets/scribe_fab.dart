import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../realtime_asr/models/realtime_clinical_fields.dart';
import '../../realtime_asr/realtime_asr_controller.dart';
import '../scribe_controller.dart';
import '../scribe_session.dart';

/// Wraps [ScribeFab] with an explicit ASR/Other mode chooser at idle — see
/// [RealtimeAsrController]. Same design as ScribeBanner's mode chooser,
/// adapted to a floating-action-button context. The batch ("Other") flow
/// and live ASR never run at once; each is hidden while the other is active.
class ScribeModeFab extends StatelessWidget {
  const ScribeModeFab({
    super.key,
    required this.liveController,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onOpenReview,
    required this.onRetry,
  });

  final RealtimeAsrController liveController;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onOpenReview;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: liveController,
      builder: (context, _) {
        return Consumer<ScribeController>(
          builder: (context, ctrl, _) {
            final session = ctrl.session;

            if (liveController.isActive) {
              return FloatingActionButton.extended(
                heroTag: 'scribe_live_fab',
                onPressed: liveController.stop,
                backgroundColor: Colors.deepPurple,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
                label: const Text(
                  'Stop ASR',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }

            if (session.state == ScribeState.idle) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'scribe_asr_fab',
                    onPressed: liveController.start,
                    backgroundColor: Colors.deepPurple,
                    icon: const Icon(Icons.podcasts, color: Colors.white),
                    label: Text(
                      ScribeBannerStrings.modeAsr,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'scribe_other_fab',
                    onPressed: onStartRecording,
                    backgroundColor: Theme.of(context).primaryColor,
                    icon: const Icon(Icons.mic, color: Colors.white),
                    label: Text(
                      ScribeBannerStrings.modeOther,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            }

            // All other batch states (recording/uploading/error) keep the
            // existing single-FAB behavior.
            return ScribeFab(
              onStartRecording: onStartRecording,
              onStopRecording: onStopRecording,
              onOpenReview: onOpenReview,
              onRetry: onRetry,
            );
          },
        );
      },
    );
  }
}

/// Status pill shown above the form body — delegates to the existing
/// [ScribePill] for the batch flow, or shows a live transcript + on-demand
/// symptoms preview while [RealtimeAsrController] is active. Independent of
/// the batch flow: nothing here is saved to the note.
class ScribeStatusPill extends StatelessWidget {
  const ScribeStatusPill({
    super.key,
    required this.liveController,
    required this.onStop,
  });

  final RealtimeAsrController liveController;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: liveController,
      builder: (context, _) {
        if (!liveController.isActive) {
          return ScribePill(onStop: onStop);
        }
        return _LiveAsrStatusPanel(controller: liveController);
      },
    );
  }
}

class _LiveAsrStatusPanel extends StatelessWidget {
  const _LiveAsrStatusPanel({required this.controller});
  final RealtimeAsrController controller;

  @override
  Widget build(BuildContext context) {
    final fields = controller.fields;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.podcasts, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                controller.state == RealtimeAsrState.connecting
                    ? RealtimeAsrStrings.connecting
                    : RealtimeAsrStrings.listening,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: controller.isExtracting ? null : controller.extractNow,
                child: Text(
                  controller.isExtracting
                      ? RealtimeAsrStrings.extracting
                      : RealtimeAsrStrings.extractNow,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (controller.micWarning != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    controller.micWarning!,
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              controller.errorMessage!,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              controller.segments.isEmpty
                  ? RealtimeAsrStrings.transcriptEmpty
                  : controller.fullTranscript,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontStyle: controller.segments.isEmpty ? FontStyle.italic : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              fields == null || fields.isEmpty
                  ? RealtimeAsrStrings.symptomsEmpty
                  : _summarize(fields),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _summarize(RealtimeClinicalFields f) {
    final parts = <String>[
      if (f.diagnosis != null) f.diagnosis!,
      if (f.bloodPressure != null) 'BP ${f.bloodPressure}',
      if (f.bloodGlucose != null) 'BG ${f.bloodGlucose}',
      ...f.chiefComplaints,
    ];
    return parts.isEmpty ? RealtimeAsrStrings.symptomsEmpty : parts.join(' · ');
  }
}

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
