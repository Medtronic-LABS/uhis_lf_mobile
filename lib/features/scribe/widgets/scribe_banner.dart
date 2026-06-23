import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../scribe_controller.dart';
import '../scribe_session.dart';

/// Inline AI Scribe banner — embedded in the visit form body.
///
/// Replaces the floating action button. Matches the prototype gradient card
/// from Leapfrog.html (scribeBanner): purple gradient idle, red recording
/// with wave bars, green when fields are populated.
///
/// In embedded mode, shows live transcript during recording and auto-fills
/// form fields without requiring a separate review screen.
class ScribeBanner extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Consumer<ScribeController>(
      builder: (context, ctrl, _) {
        final state = ctrl.session.state;
        final session = ctrl.session;
        final tappable = state == ScribeState.idle ||
            state == ScribeState.requestingPermission ||
            state == ScribeState.recording ||
            state == ScribeState.reviewReady ||
            state == ScribeState.fieldsPopulated ||
            state == ScribeState.error;

        return GestureDetector(
          key: const Key('scribe_banner_tap'),
          onTap: tappable ? () => _handleTap(state, ctrl) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: _gradient(state, session.fieldsJustPopulated),
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
                    _MicIconBox(state: state, fieldsJustPopulated: session.fieldsJustPopulated),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BannerText(state: state, session: session),
                    ),
                    if (state == ScribeState.recording) const _WaveBars(),
                    if (state == ScribeState.uploading || state == ScribeState.processing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    if (state == ScribeState.fieldsPopulated && session.pendingFieldCount > 0) ...[
                      _AcceptAllButton(onTap: onAcceptAll),
                    ],
                  ],
                ),
                // Show live transcript during recording
                if (state == ScribeState.recording && session.liveTranscript != null) ...[
                  const SizedBox(height: 10),
                  _LiveTranscriptBox(transcript: session.liveTranscript!),
                ],
                // Show transcript preview after processing
                if (state == ScribeState.fieldsPopulated && session.transcriptText != null) ...[
                  const SizedBox(height: 10),
                  _TranscriptPreview(
                    transcript: session.transcriptText!,
                    fieldCount: session.pendingFieldCount + session.acceptedFieldCount,
                  ),
                ],
              ],
            ),
          ),
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
        colors: [Color(0xFF059669), Color(0xFF34D399)],
      );
    }
    
    switch (state) {
      case ScribeState.fieldsPopulated:
      case ScribeState.reviewReady:
      case ScribeState.accepted:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF065F46), Color(0xFF10B981)],
        );
      case ScribeState.recording:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
        );
      case ScribeState.error:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF991B1B), Color(0xFFEF4444)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D3599), Color(0xFF6B63D4)],
        );
    }
  }

  static Color _shadowColor(ScribeState state) {
    switch (state) {
      case ScribeState.fieldsPopulated:
      case ScribeState.reviewReady:
      case ScribeState.accepted:
        return const Color(0xFF10B981).withValues(alpha: 0.3);
      case ScribeState.recording:
        return const Color(0xFFDC2626).withValues(alpha: 0.3);
      case ScribeState.error:
        return const Color(0xFFEF4444).withValues(alpha: 0.3);
      default:
        return const Color(0xFF6B63D4).withValues(alpha: 0.3);
    }
  }

  void _handleTap(ScribeState state, ScribeController ctrl) {
    switch (state) {
      case ScribeState.idle:
      case ScribeState.requestingPermission:
        onStartRecording();
        break;
      case ScribeState.recording:
        onStopRecording();
        break;
      case ScribeState.reviewReady:
        onOpenReview();
        break;
      case ScribeState.fieldsPopulated:
        // In embedded mode, tapping shows a mini-menu or accepts all
        onAcceptAll?.call();
        break;
      case ScribeState.error:
        onRetry();
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
    return GestureDetector(
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
          Positioned(
            top: -4,
            right: -4,
            child: _LiveDot(),
          ),
        if (state == ScribeState.fieldsPopulated && fieldsJustPopulated)
          Positioned(
            top: -4,
            right: -4,
            child: _SuccessCheckmark(),
          ),
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
        border: Border.all(color: const Color(0xFF10B981), width: 2),
      ),
      child: const Icon(Icons.check, color: Color(0xFF10B981), size: 12),
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
          color: const Color(0xFFEF4444),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF6B63D4), width: 2),
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
        Tween<double>(begin: 6, end: 18).animate(
          CurvedAnimation(parent: c, curve: Curves.easeInOut),
        ),
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
