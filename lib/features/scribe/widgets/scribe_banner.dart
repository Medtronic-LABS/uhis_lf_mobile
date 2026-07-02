import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/realtime_asr_service.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/preferences/scribe_engine_notifier.dart';
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
                          if (!liveActive &&
                              !idleChoice &&
                              state == ScribeState.recording)
                            const _WaveBars(),
                          if (!liveActive &&
                              !idleChoice &&
                              (state == ScribeState.uploading ||
                                  state == ScribeState.processing))
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          if (!liveActive &&
                              !idleChoice &&
                              state == ScribeState.fieldsPopulated &&
                              session.pendingFieldCount > 0) ...[
                            _AcceptAllButton(onTap: widget.onAcceptAll),
                          ],
                          // Idle: single mode button driven by persisted engine
                          // preference + a settings icon to switch the preference.
                          if (idleChoice) ...[
                            const SizedBox(width: 8),
                            Consumer<ScribeEngineNotifier>(
                              builder: (ctx, enginePref, _) => _ModeButton(
                                key: const Key('scribe_banner_mode_start'),
                                label: enginePref.isLiveAsr
                                    ? ScribeBannerStrings.modeAsr
                                    : ScribeBannerStrings.modeGemini,
                                icon: enginePref.isLiveAsr
                                    ? Icons.podcasts
                                    : Icons.mic,
                                onTap: enginePref.isLiveAsr
                                    ? _liveCtrl.start
                                    : widget.onStartRecording,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _EngineSettingsButton(liveCtrl: _liveCtrl),
                          ],
                          // Live mode active: only its own stop control shows.
                          if (liveActive) ...[
                            const SizedBox(width: 8),
                            _LiveStopButton(controller: _liveCtrl),
                          ],
                          // Batch mode active: badge makes the active engine
                          // explicit at a glance.
                          if (!liveActive && !idleChoice) ...[
                            const SizedBox(width: 8),
                            Consumer<ScribeEngineNotifier>(
                              builder: (ctx, ep, _) => _ModeBadge(
                                label: ep.isLiveAsr
                                    ? ScribeBannerStrings.modeAsr
                                    : ScribeBannerStrings.modeGemini,
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Live mode: transcript + on-demand symptoms preview
                      if (liveActive) ...[
                        const SizedBox(height: 10),
                        _LiveAsrPanel(controller: _liveCtrl),
                      ],
                      // Batch mode: live transcript during recording
                      if (!liveActive &&
                          state == ScribeState.recording &&
                          session.liveTranscript != null) ...[
                        const SizedBox(height: 10),
                        _LiveTranscriptBox(transcript: session.liveTranscript!),
                      ],
                      // Batch mode: transcript preview after processing
                      if (!liveActive &&
                          state == ScribeState.fieldsPopulated &&
                          session.transcriptText != null) ...[
                        const SizedBox(height: 10),
                        _TranscriptPreview(
                          transcript: session.transcriptText!,
                          fieldCount:
                              session.pendingFieldCount +
                              session.acceptedFieldCount,
                        ),
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

/// Accept all button shown when fields are populated.
class _AcceptAllButton extends StatelessWidget {
  const _AcceptAllButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Accept AI note',
      button: true,
      child: GestureDetector(
        key: const Key('scribe_accept_all_tap'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              const Text(
                'Accept All',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live transcript display during recording.
class _LiveTranscriptBox extends StatelessWidget {
  const _LiveTranscriptBox({required this.transcript});

  final String transcript;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const _PulsingDot(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              transcript,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Transcript preview after processing.
class _TranscriptPreview extends StatelessWidget {
  const _TranscriptPreview({
    required this.transcript,
    required this.fieldCount,
  });

  final String transcript;
  final int fieldCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                '$fieldCount fields auto-filled',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '"${_truncate(transcript, 80)}"',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
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

/// Non-interactive tag making the active engine explicit at a glance —
/// shown once the "Other" (standard/batch) mode is running. The live-mode
/// equivalent is [_LiveBannerText]'s "Live ASR" title plus [_LiveStopButton].
class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Stop control shown only while the "ASR" (live streaming) mode is active.
class _LiveStopButton extends StatelessWidget {
  const _LiveStopButton({required this.controller});

  final RealtimeAsrController controller;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Stop live ASR',
      button: true,
      child: GestureDetector(
        key: const Key('scribe_banner_live_stop'),
        onTap: controller.stop,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop_circle_outlined, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text(
                ScribeBannerStrings.modeAsr,
                style: TextStyle(
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
                  onTap: controller.isExtracting ? null : controller.extractNow,
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

/// Small settings/tune icon on the banner (idle state only) — opens
/// [_ScribeModeSheet] to switch the persisted engine preference.
class _EngineSettingsButton extends StatelessWidget {
  const _EngineSettingsButton({required this.liveCtrl});
  final RealtimeAsrController liveCtrl;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Change AI Scribe mode',
      button: true,
      child: GestureDetector(
        key: const Key('scribe_banner_engine_settings'),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _ScribeModeSheet(liveCtrl: liveCtrl),
        ),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: const Icon(Icons.tune, color: Colors.white, size: 15),
        ),
      ),
    );
  }
}

/// Bottom sheet for switching the persisted AI Scribe engine preference.
class _ScribeModeSheet extends StatelessWidget {
  const _ScribeModeSheet({required this.liveCtrl});
  final RealtimeAsrController liveCtrl;

  @override
  Widget build(BuildContext context) {
    return Consumer<ScribeEngineNotifier>(
      builder: (ctx, enginePref, _) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                ScribeBannerStrings.modeSheetTitle,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _ModeOption(
                title: ScribeBannerStrings.modeGeminiTitle,
                description: ScribeBannerStrings.modeGeminiDesc,
                icon: Icons.mic,
                badge: ScribeBannerStrings.modeGeminiDefault,
                selected: !enginePref.isLiveAsr,
                onTap: () {
                  enginePref.set(ScribeEngine.gemini);
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 8),
              _ModeOption(
                title: ScribeBannerStrings.modeAsrTitle,
                description: ScribeBannerStrings.modeAsrDesc,
                icon: Icons.podcasts,
                badge: null,
                selected: enginePref.isLiveAsr,
                onTap: () {
                  enginePref.set(ScribeEngine.liveAsr);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String description;
  final IconData icon;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1B2B5E);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0F0FF) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? navy : Colors.grey[200]!,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? navy : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Color(0xFF1B2B5E), size: 20),
          ],
        ),
      ),
    );
  }
}
