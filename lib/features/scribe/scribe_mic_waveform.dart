import 'package:flutter/material.dart';

/// Recording-state mic icon — plain, non-animated: this app's Scribe feature
/// has no waveform/animation requirement, so recording is indicated only by
/// [backgroundColor] differing from the idle state (see AiScribeBanner).
class ScribeRecordingMicOrb extends StatelessWidget {
  const ScribeRecordingMicOrb({
    super.key,
    this.backgroundColor = const Color(0xFF7A63E8),
    this.diameter = 44,
  });

  final Color backgroundColor;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.mic_rounded,
        color: Colors.white,
        size: diameter * 0.5,
      ),
    );
  }
}

/// Spinner confined to the mic circle while upload / AI processing runs.
class ScribeProcessingMicOrb extends StatelessWidget {
  const ScribeProcessingMicOrb({
    super.key,
    this.backgroundColor = const Color(0xFF5E47C9),
    this.diameter = 44,
  });

  final Color backgroundColor;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: diameter * 0.4,
        height: diameter * 0.4,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Green check in the mic circle after a successful triage scribe run.
class ScribeDoneMicOrb extends StatelessWidget {
  const ScribeDoneMicOrb({
    super.key,
    this.diameter = 44,
  });

  final double diameter;

  static const Color _successBg = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: _successBg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _successBg.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.check_rounded,
        color: Colors.white,
        size: diameter * 0.52,
      ),
    );
  }
}

/// Tiny pulsing red dot beside the banner title while recording.
class ScribeRecordingLiveDot extends StatefulWidget {
  const ScribeRecordingLiveDot({super.key});

  @override
  State<ScribeRecordingLiveDot> createState() => _ScribeRecordingLiveDotState();
}

class _ScribeRecordingLiveDotState extends State<ScribeRecordingLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _blink, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFFFF6B6B),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
