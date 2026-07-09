import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/realtime_asr_service.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../realtime_asr/models/realtime_clinical_fields.dart';
import '../../realtime_asr/realtime_asr_controller.dart';
import '../scribe_controller.dart';
import '../scribe_permission_service.dart';
import '../scribe_session.dart';

/// Inline AI Scribe banner — embedded in the visit form body.
///
/// Replaces the floating action button. Matches the prototype gradient card
/// from Leapfrog.html (scribeBanner): purple gradient idle, red recording
/// with wave bars, green when fields are populated.
///
/// In embedded mode, shows live transcript during recording and auto-fills
/// form fields without requiring a separate review screen.
///
/// Also hosts an independent "Live" mode (top-right icon) that streams to
/// `/scribe/realtime/transcribe` for a live transcript + live detected
/// symptoms preview — see [RealtimeAsrController]. It never runs at the same
/// time as the batch record-upload-poll flow above (both capture the mic
/// exclusively), and it does not feed into accept/reject or the note itself;
/// it's a live-listening aid.
class ScribeBanner extends StatefulWidget {
  const ScribeBanner({
    super.key,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onOpenReview,
    required this.onRetry,
    this.onAcceptAll,
    this.onClearAll,
  });

  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onOpenReview;
  final VoidCallback onRetry;
  final VoidCallback? onAcceptAll;
  final VoidCallback? onClearAll;

  @override
  State<ScribeBanner> createState() => _ScribeBannerState();
}

class _ScribeBannerState extends State<ScribeBanner> {
  late final RealtimeAsrController _liveCtrl;

  @override
  void initState() {
    super.initState();
    _liveCtrl = RealtimeAsrController(
      service: context.read<RealtimeAsrService>(),
      permissionService: ScribePermissionService(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _liveCtrl.bindContext(context);
  }

  @override
  void dispose() {
    _liveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _liveCtrl,
      builder: (context, _) {
        return Consumer<ScribeController>(
          builder: (context, ctrl, _) {
            final state = ctrl.session.state;
            final session = ctrl.session;
            final liveActive = _liveCtrl.isActive;
            // Only truly idle shows the ASR/Other chooser — once either mode
            // has started, its own controls take over (see below).
            final idleChoice = !liveActive && state == ScribeState.idle;
            final tappable =
                !liveActive &&
                !idleChoice &&
                (state == ScribeState.recording ||
                    state == ScribeState.reviewReady ||
                    state == ScribeState.fieldsPopulated ||
                    state == ScribeState.error);

            final bannerLabel = state == ScribeState.recording
                ? 'Stop recording'
                : state == ScribeState.reviewReady ||
                      state == ScribeState.fieldsPopulated
                ? 'Accept AI note'
                : state == ScribeState.error
                ? 'Retry AI Scribe'
                : 'AI Scribe';
            return Semantics(
              label: bannerLabel,
              button: tappable,
              child: GestureDetector(
                key: const Key('scribe_banner_tap'),
                onTap: tappable ? () => _handleTap(state, ctrl) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: liveActive
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.aiPurpleDark,
                              AppColors.aiPurple,
                            ],
                          )
                        : _gradient(state, session.fieldsJustPopulated),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _shadowColor(state),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _MicIconBox(
                            state: state,
                            fieldsJustPopulated: session.fieldsJustPopulated,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: liveActive
                                ? _LiveBannerText(state: _liveCtrl.state)
                                : _BannerText(state: state, session: session),
                          ),
                          // Idle: single ASR start button (ASR is the only mode).
                          if (idleChoice) ...[
                            const SizedBox(width: 8),
                            _ModeButton(
                              key: const Key('scribe_banner_mode_start'),
                              label: ScribeBannerStrings.modeAsr,
                              icon: Icons.podcasts,
                              onTap: _liveCtrl.start,
                            ),
                          ],
                          // Live mode active: stop control.
                          if (liveActive) ...[
                            const SizedBox(width: 8),
                            _LiveStopButton(
                              controller: _liveCtrl,
                              state: _liveCtrl.state,
                            ),
                          ],
                        ],
                      ),
                      // Live mode: transcript + on-demand symptoms preview
                      if (liveActive) ...[
                        const SizedBox(height: 10),
                        _LiveAsrPanel(controller: _liveCtrl),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static LinearGradient _gradient(ScribeState state, bool fieldsJustPopulated) {
    // Flash green when fields just populated
    if (state == ScribeState.fieldsPopulated && fieldsJustPopulated) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.statusSuccessAction, AppColors.statusSuccessDark],
      );
    }

    switch (state) {
      case ScribeState.fieldsPopulated:
      case ScribeState.reviewReady:
      case ScribeState.accepted:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.statusSuccessText, AppColors.statusSuccess],
        );
      case ScribeState.recording:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.statusCriticalText, AppColors.slaOverdueText],
        );
      case ScribeState.error:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.statusCriticalText, AppColors.statusCritical],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.aiPurpleDark, AppColors.aiPurple],
        );
    }
  }

  static Color _shadowColor(ScribeState state) {
    switch (state) {
      case ScribeState.fieldsPopulated:
      case ScribeState.reviewReady:
      case ScribeState.accepted:
        return AppColors.statusSuccess.withValues(alpha: 0.3);
      case ScribeState.recording:
        return AppColors.slaOverdueText.withValues(alpha: 0.3);
      case ScribeState.error:
        return AppColors.statusCritical.withValues(alpha: 0.3);
      default:
        return AppColors.aiPurple.withValues(alpha: 0.3);
    }
  }

  void _handleTap(ScribeState state, ScribeController ctrl) {
    switch (state) {
      case ScribeState.idle:
      case ScribeState.requestingPermission:
        widget.onStartRecording();
        break;
      case ScribeState.recording:
        widget.onStopRecording();
        break;
      case ScribeState.reviewReady:
        widget.onOpenReview();
        break;
      case ScribeState.fieldsPopulated:
        // In embedded mode, tapping shows a mini-menu or accepts all
        widget.onAcceptAll?.call();
        break;
      case ScribeState.error:
        widget.onRetry();
        break;
      default:
        break;
    }
  }
}


class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _MicIconBox extends StatelessWidget {
  const _MicIconBox({required this.state, this.fieldsJustPopulated = false});

  final ScribeState state;
  final bool fieldsJustPopulated;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: _iconWidget),
        ),
        if (state == ScribeState.recording)
          Positioned(top: -4, right: -4, child: _LiveDot()),
        if (state == ScribeState.fieldsPopulated && fieldsJustPopulated)
          Positioned(top: -4, right: -4, child: _SuccessCheckmark()),
      ],
    );
  }

  Widget get _iconWidget {
    switch (state) {
      case ScribeState.processing:
        return const _PulsingStarIcon();
      case ScribeState.fieldsPopulated:
        return const Icon(Icons.auto_awesome, color: Colors.white, size: 22);
      case ScribeState.reviewReady:
        return const Icon(Icons.auto_awesome, color: Colors.white, size: 22);
      case ScribeState.error:
        return const Icon(Icons.warning_amber, color: Colors.white, size: 22);
      case ScribeState.accepted:
        return const Icon(Icons.check, color: Colors.white, size: 22);
      case ScribeState.rejected:
        return const Icon(Icons.close, color: Colors.white, size: 22);
      default:
        return const Icon(Icons.mic, color: Colors.white, size: 22);
    }
  }
}

class _SuccessCheckmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.statusSuccess, width: 2),
      ),
      child: const Icon(Icons.check, color: AppColors.statusSuccess, size: 12),
    );
  }
}

class _BannerText extends StatelessWidget {
  const _BannerText({required this.state, required this.session});

  final ScribeState state;
  final ScribeSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _primaryText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (_subText.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            _subText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  String get _primaryText {
    switch (state) {
      case ScribeState.idle:
      case ScribeState.requestingPermission:
        return ScribeBannerStrings.idle;
      case ScribeState.recording:
        return ScribeBannerStrings.recording;
      case ScribeState.uploading:
        final pct = session.uploadProgressPercent;
        return pct != null
            ? 'Uploading… ${pct.toStringAsFixed(0)}%'
            : ScribeBannerStrings.uploading;
      case ScribeState.processing:
        return ScribeBannerStrings.processing;
      case ScribeState.fieldsPopulated:
        final count = session.pendingFieldCount + session.acceptedFieldCount;
        return 'AI filled $count fields';
      case ScribeState.reviewReady:
        return ScribeBannerStrings.ready;
      case ScribeState.error:
        return session.errorMessage ?? ScribeBannerStrings.error;
      case ScribeState.accepted:
        return ScribeStrings.acceptedSnackbar;
      case ScribeState.rejected:
        return ScribeStrings.rejectedSnackbar;
    }
  }

  String get _subText {
    switch (state) {
      case ScribeState.idle:
        return ScribeBannerStrings.idleSub;
      case ScribeState.recording:
        final secs = session.elapsedSeconds;
        final mm = (secs ~/ 60).toString().padLeft(2, '0');
        final ss = (secs % 60).toString().padLeft(2, '0');
        return '$mm:$ss • Listening...';
      case ScribeState.fieldsPopulated:
        return 'Tap fields to review • Accept all →';
      default:
        return '';
    }
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.2).animate(_ctrl),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.statusCritical,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.aiPurple, width: 2),
        ),
      ),
    );
  }
}

class _PulsingStarIcon extends StatefulWidget {
  const _PulsingStarIcon();

  @override
  State<_PulsingStarIcon> createState() => _PulsingStarIconState();
}

class _PulsingStarIconState extends State<_PulsingStarIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
    );
  }
}

/// 5 animated wave bars — visible while recording (prototype waveWrap).
class _WaveBars extends StatefulWidget {
  const _WaveBars();

  @override
  State<_WaveBars> createState() => _WaveBarsState();
}

class _WaveBarsState extends State<_WaveBars> with TickerProviderStateMixin {
  final List<AnimationController> _ctrls = [];
  final List<Animation<double>> _heights = [];

  static const List<int> _delayMs = [0, 150, 100, 250, 300];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 5; i++) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      );
      _ctrls.add(c);
      _heights.add(
        Tween<double>(
          begin: 6,
          end: 18,
        ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
      );
      Future.delayed(Duration(milliseconds: _delayMs[i]), () {
        if (mounted) c.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: AnimatedBuilder(
            animation: _heights[i],
            builder: (_, _) => Container(
              width: 3,
              height: _heights[i].value,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Explicit mode-chooser button, shown only at idle (see [ScribeBanner]) —
/// replaces the old implicit "tap the whole card to start batch recording"
/// behavior so it's always clear which engine a tap will start.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Start $label mode',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stop control shown only while the "ASR" (live streaming) mode is active.
///
/// While [state] is connecting or stopping it becomes a non-interactive
/// spinner+label so the tap that triggered it gives immediate feedback — the
/// underlying start/stop transitions can each take a few seconds.
class _LiveStopButton extends StatelessWidget {
  const _LiveStopButton({required this.controller, required this.state});

  final RealtimeAsrController controller;
  final RealtimeAsrState state;

  @override
  Widget build(BuildContext context) {
    final busy = state == RealtimeAsrState.connecting ||
        state == RealtimeAsrState.stopping;
    final label = state == RealtimeAsrState.stopping
        ? RealtimeAsrStrings.stopping
        : state == RealtimeAsrState.connecting
            ? RealtimeAsrStrings.connecting
            : ScribeBannerStrings.modeAsr;
    return Semantics(
      label: busy ? label : 'Stop live ASR',
      button: !busy,
      child: GestureDetector(
        key: const Key('scribe_banner_live_stop'),
        onTap: busy ? null : controller.stop,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: busy ? 0.18 : 0.28),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  Icons.stop_circle_outlined,
                  color: Colors.white,
                  size: 16,
                ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner headline text while a live session is connecting/listening.
class _LiveBannerText extends StatelessWidget {
  const _LiveBannerText({required this.state});
  final RealtimeAsrState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      RealtimeAsrState.connecting => RealtimeAsrStrings.connecting,
      RealtimeAsrState.listening => RealtimeAsrStrings.listening,
      RealtimeAsrState.stopping => RealtimeAsrStrings.stopping,
      RealtimeAsrState.error => 'Live ASR error',
      RealtimeAsrState.idle => RealtimeAsrStrings.idle,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Live ASR',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Live transcript + on-demand detected-symptoms preview, shown while a
/// [RealtimeAsrController] session is active. Independent of the batch
/// scribe flow — nothing here is saved to the note.
class _LiveAsrPanel extends StatelessWidget {
  const _LiveAsrPanel({required this.controller});
  final RealtimeAsrController controller;

  @override
  Widget build(BuildContext context) {
    final fields = controller.fields;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.errorMessage != null)
            Text(
              controller.errorMessage!,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            )
          else ...[
            Row(
              children: [
                const _PulsingDot(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.segments.isEmpty
                        ? RealtimeAsrStrings.transcriptEmpty
                        : controller.fullTranscript,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontStyle: controller.segments.isEmpty
                          ? FontStyle.italic
                          : null,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
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
                ),
                GestureDetector(
                  key: const Key('scribe_banner_live_extract_now'),
                  onTap: controller.isExtracting ||
                          controller.state == RealtimeAsrState.stopping
                      ? null
                      : controller.extractNow,
                  child: Text(
                    controller.isExtracting
                        ? RealtimeAsrStrings.extracting
                        : RealtimeAsrStrings.extractNow,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
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
