import 'dart:math' as math;
import 'dart:typed_data';

/// Client-side Voice Activity Detection gate for the Real-Time ASR audio
/// stream — decides which native PCM16LE mono 16kHz chunks are worth sending
/// to the server, so silence/background noise isn't transcribed, billed, and
/// fed into the LLM extraction prompt alongside real speech.
///
/// Governing principle for every threshold below: **bias toward false
/// accepts over false rejects**. Sending a bit of extra silence is cheap;
/// silently dropping a chunk of real speech is unrecoverable and invisible
/// to the SK — there is no retry path for gated-out audio. When tuning any
/// constant here, resolve the judgment call in that direction.
///
/// Chunk duration is derived from byte count, never assumed fixed — the
/// native `record` package buffer size is OEM/device-dependent (see
/// `RealtimeAsrController`'s doc comments), so `bytesPerMs` (32 at 16kHz
/// mono PCM16) is what converts a chunk's `pcm.length` into elapsed time.
class VadGate {
  VadGate({
    this.enterMarginDb = 12,
    this.sustainMarginDb = 7,
    this.floorCeilingDbfs = -25,
    this.floorAlpha = 0.08,
    Duration? bootstrapDuration,
    Duration? debounceDuration,
    Duration? hangoverDuration,
    Duration? preRollDuration,
  })  : bootstrapDuration = bootstrapDuration ?? const Duration(milliseconds: 400),
        debounceDuration = debounceDuration ?? const Duration(milliseconds: 180),
        hangoverDuration = hangoverDuration ?? const Duration(milliseconds: 550),
        preRollDuration = preRollDuration ?? const Duration(milliseconds: 350);

  static const int _bytesPerMs = 32; // 16000 Hz * 2 bytes * 1 channel / 1000
  static const double _silenceFloorDbfs = -160.0; // dBFS of an all-zero buffer
  static const double _minFloorDbfs = -90.0;

  /// Margin above the noise floor (dB) required to *enter* voice state.
  final double enterMarginDb;

  /// Margin above the noise floor (dB) required to *sustain* voice state
  /// once already active — lower than [enterMarginDb] so natural
  /// mid-utterance volume dips don't drop out of voice state (hysteresis).
  final double sustainMarginDb;

  /// Hard ceiling on the adaptive noise floor — without this, a loud,
  /// continuous background talker gets tracked as "the noise floor," which
  /// would then require the patient to out-shout them to register as
  /// speech. Never let the floor drift above this.
  final double floorCeilingDbfs;

  /// EMA smoothing factor for the noise floor, applied only on frames
  /// currently classified silent (so the speaker's own voice never pulls
  /// the floor up).
  final double floorAlpha;

  /// How much of the session start is assumed silent, to seed the floor
  /// before any adaptive history exists.
  final Duration bootstrapDuration;

  /// Cumulative above-entry-threshold duration required before flipping to
  /// voice state — rejects single clicks/transients.
  final Duration debounceDuration;

  /// How long to stay in voice state after energy drops below the sustain
  /// threshold — covers trailing consonants/soft clause-final sounds.
  final Duration hangoverDuration;

  /// How much recent silence-state audio to keep buffered so it can be
  /// flushed on a silence -> voice transition (covers the debounce window
  /// itself plus a plausible onset ramp).
  final Duration preRollDuration;

  bool _bootstrapped = false;
  int _bootstrapMs = 0;
  double _bootstrapSum = 0;
  int _bootstrapSamples = 0;

  double _floorDbfs = _minFloorDbfs;
  bool _voiceActive = false;
  int _candidateVoiceMs = 0;
  int _hangoverRemainingMs = 0;

  final List<Uint8List> _preRoll = [];
  int _preRollMs = 0;

  double? _lastFrameDbfs;

  /// Current adaptive noise floor, in dBFS. Exposed for tuning/diagnostics.
  double get floorDbfs => _floorDbfs;

  /// dBFS of the most recently processed chunk. Exposed for tuning/diagnostics.
  double? get lastFrameDbfs => _lastFrameDbfs;

  /// Whether the gate is currently in voice (or hangover) state. Exposed for
  /// tuning/diagnostics.
  bool get isVoiceActive => _voiceActive;

  /// Feeds one native PCM16LE mono 16kHz chunk through the gate. Returns the
  /// buffers (in original order) that should now be sent to the server:
  /// empty when this chunk is silence, [pcm] alone in the steady
  /// voice/hangover case, or [pcm] plus buffered pre-roll chunks on a
  /// silence -> voice transition.
  List<Uint8List> process(Uint8List pcm) {
    final durationMs = _durationMsOf(pcm);
    final dbfs = _dbfsOf(pcm);
    _lastFrameDbfs = dbfs;

    if (!_bootstrapped) {
      _bootstrapSum += dbfs;
      _bootstrapSamples++;
      _bootstrapMs += durationMs;
      if (_bootstrapMs >= bootstrapDuration.inMilliseconds) {
        _floorDbfs = (_bootstrapSum / _bootstrapSamples).clamp(_minFloorDbfs, floorCeilingDbfs);
        _bootstrapped = true;
      }
      // Treat the bootstrap window itself as silence — buffer it as pre-roll
      // in case speech starts immediately (CHW taps LIVE and speaks at once).
      return _bufferSilent(pcm, durationMs);
    }

    if (_voiceActive) {
      final aboveSustain = dbfs >= _floorDbfs + sustainMarginDb;
      if (aboveSustain) {
        _hangoverRemainingMs = hangoverDuration.inMilliseconds;
        return [pcm];
      }
      _hangoverRemainingMs -= durationMs;
      if (_hangoverRemainingMs > 0) {
        return [pcm];
      }
      // Hangover elapsed — drop back to silence state.
      _voiceActive = false;
      _candidateVoiceMs = 0;
      return _bufferSilent(pcm, durationMs);
    }

    // Silence state: update the adaptive floor (clamped), track the
    // candidate-voice debounce counter, and decide whether to flip.
    final aboveEnter = dbfs >= _floorDbfs + enterMarginDb;
    if (aboveEnter) {
      _candidateVoiceMs += durationMs;
    } else {
      _candidateVoiceMs = 0;
      _floorDbfs = ((1 - floorAlpha) * _floorDbfs + floorAlpha * dbfs).clamp(_minFloorDbfs, floorCeilingDbfs);
    }

    // Buffer this chunk as pre-roll regardless of aboveEnter — the debounce
    // window's own qualifying chunks must be part of the flush too.
    _bufferSilent(pcm, durationMs);

    if (_candidateVoiceMs >= debounceDuration.inMilliseconds) {
      _voiceActive = true;
      _hangoverRemainingMs = hangoverDuration.inMilliseconds;
      final flushed = List<Uint8List>.unmodifiable(_preRoll);
      _preRoll.clear();
      _preRollMs = 0;
      return flushed;
    }

    return const [];
  }

  List<Uint8List> _bufferSilent(Uint8List pcm, int durationMs) {
    _preRoll.add(pcm);
    _preRollMs += durationMs;
    while (_preRollMs > preRollDuration.inMilliseconds && _preRoll.length > 1) {
      final dropped = _preRoll.removeAt(0);
      _preRollMs -= _durationMsOf(dropped);
    }
    return const [];
  }

  static int _durationMsOf(Uint8List pcm) => pcm.length ~/ _bytesPerMs;

  /// Short-time RMS energy of a raw PCM16LE buffer, in dBFS (0 dBFS = full
  /// scale). RMS over peak — peak is dominated by single-sample transients
  /// and says nothing about sustained energy, which is what distinguishes
  /// speech from a fan/click.
  static double _dbfsOf(Uint8List pcm) {
    if (pcm.length < 2) return _silenceFloorDbfs;
    final data = ByteData.sublistView(pcm);
    final sampleCount = pcm.length ~/ 2;
    double sumSquares = 0;
    for (var i = 0; i + 1 < pcm.length; i += 2) {
      final sample = data.getInt16(i, Endian.little).toDouble();
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    if (rms <= 0) return _silenceFloorDbfs;
    const maxPcmValue = 32768.0;
    return 20 * math.log(rms / maxPcmValue) / math.ln10;
  }
}
