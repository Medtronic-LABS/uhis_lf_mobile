import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';

/// Five-bar live equalizer driven by [RecorderController.waveData] — reacts to
/// current mic level instead of painting a scrolling history (which fills the
/// tiny circle and looks static).
class ScribeLiveMicBars extends StatefulWidget {
  const ScribeLiveMicBars({
    super.key,
    required this.recorderController,
    this.barCount = 5,
    this.size = 30,
  });

  final RecorderController recorderController;
  final int barCount;
  final double size;

  @override
  State<ScribeLiveMicBars> createState() => _ScribeLiveMicBarsState();
}

class _ScribeLiveMicBarsState extends State<ScribeLiveMicBars>
    with SingleTickerProviderStateMixin {
  late List<double> _bars;
  late AnimationController _idleBreath;

  @override
  void initState() {
    super.initState();
    _bars = List<double>.filled(widget.barCount, 0.16);
    widget.recorderController.addListener(_onRecorderUpdate);
    _idleBreath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _idleBreath.addListener(_onIdleBreath);
  }

  @override
  void dispose() {
    widget.recorderController.removeListener(_onRecorderUpdate);
    _idleBreath.dispose();
    super.dispose();
  }

  void _onIdleBreath() {
    if (!widget.recorderController.isRecording) return;
    final data = widget.recorderController.waveData;
    if (data.isNotEmpty && data.last > 0.06) return;
    final t = Curves.easeInOut.transform(_idleBreath.value);
    if (!mounted) return;
    setState(() {
      final center = (widget.barCount - 1) / 2;
      for (var i = 0; i < widget.barCount; i++) {
        final dist = center == 0 ? 0.0 : (i - center).abs() / center;
        _bars[i] = 0.12 + (0.14 * (1 - dist * 0.6)) * t;
      }
    });
  }

  void _onRecorderUpdate() {
    if (!widget.recorderController.isRecording) return;
    final data = widget.recorderController.waveData;
    if (data.isEmpty) return;
    final amp = data.last.clamp(0.0, 1.0);
    if (!mounted) return;
    setState(() => _bars = _barsFromAmplitude(amp));
  }

  List<double> _barsFromAmplitude(double amp) {
    final n = widget.barCount;
    final center = (n - 1) / 2.0;
    // Emulator / quiet mics: stretch low readings so motion is visible.
    final scaled = (amp < 0.05 ? amp * 2.5 : amp * 1.25).clamp(0.0, 1.0);
    final peak = 0.14 + scaled * 0.86;
    return List.generate(n, (i) {
      final dist = center == 0 ? 0.0 : (i - center).abs() / center;
      final falloff = 1.0 - dist * 0.5;
      return (peak * falloff).clamp(0.12, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.size / (widget.barCount * 2.4);
    final maxHeight = widget.size * 0.7;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final level in _bars)
            AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.symmetric(horizontal: barWidth * 0.12),
              width: barWidth,
              height: maxHeight * level,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(barWidth),
              ),
            ),
        ],
      ),
    );
  }
}

/// Recording-state mic orb: soft pulsing ring + live bars inside the circle.
class ScribeRecordingMicOrb extends StatefulWidget {
  const ScribeRecordingMicOrb({
    super.key,
    required this.recorderController,
    this.backgroundColor = const Color(0xFF7A63E8),
    this.diameter = 44,
  });

  final RecorderController recorderController;
  final Color backgroundColor;
  final double diameter;

  @override
  State<ScribeRecordingMicOrb> createState() => _ScribeRecordingMicOrbState();
}

class _ScribeRecordingMicOrbState extends State<ScribeRecordingMicOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inner = widget.diameter;
    final barsSize = inner - 12;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_pulse.value);
        final ringExpand = 3 * t;
        final ringAlpha = 0.18 + (0.22 * t);

        return SizedBox(
          width: inner + 8,
          height: inner + 8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: inner + ringExpand,
                height: inner + ringExpand,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: ringAlpha),
                    width: 1.5,
                  ),
                ),
              ),
              Container(
                width: inner,
                height: inner,
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: ScribeLiveMicBars(
                  recorderController: widget.recorderController,
                  size: barsSize,
                ),
              ),
            ],
          ),
        );
      },
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
