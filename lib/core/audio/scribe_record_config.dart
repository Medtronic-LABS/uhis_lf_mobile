import 'package:record/record.dart';

/// Single home for the microphone capture settings used by every scribe
/// path — batch AI Scribe ([ScribeController]) and Real-Time ASR
/// ([RealtimeAsrController]).
///
/// Both paths previously declared their own inline [RecordConfig] (three
/// copies of the same literal in total), which is how they drifted: the
/// realtime path was fixed to use a raw mic source when the device
/// processing chain was found to return unusable audio, and the batch path
/// never got the same fix. One factory here means a capture change is made
/// once and cannot silently apply to only half the feature.
///
/// ## The [rawMicCapture] switch
///
/// * `false` (default, field use) — each path uses the best source for a
///   person speaking directly at the handset:
///   [AndroidAudioSource.defaultSource] (AEC + NS + AGC) for batch capture,
///   [AndroidAudioSource.voiceRecognition] (AGC, no AEC) for the realtime
///   stream. `voiceRecognition` is Android's documented speech-recognition
///   source (API 7+) and normalises gain across OEM hardware differences
///   without imposing AEC — important because AEC is tuned for phone-call
///   echo, not voice-form-fill.
/// * `true` (emulator / diagnostic mode) — both paths use the truly raw
///   [AndroidAudioSource.mic] source, bypassing all on-device processing
///   including automatic gain control. Use this when the emulator's audio
///   HAL returns constantly-saturated samples through the processed chain
///   (all samples pinned at Int16 min), or when you need unprocessed PCM
///   for diagnostic purposes. On most real devices, leaving this off gives
///   better recognition across all OEM hardware variants.
///
/// The [RealtimeAsrController] stuck-amplitude detector fires a UI warning
/// if samples are pinned at a constant value for 40 consecutive chunks —
/// that is the signal to toggle this on when testing on an emulator.
abstract final class ScribeRecordConfig {
  ScribeRecordConfig._();

  /// Capture sample rate (Hz) — matches what the ASR backend expects, and
  /// what [RealtimeAsrController]'s WAV header writer assumes.
  static const int sampleRate = 16000;

  /// Mono. Speech ASR gains nothing from a second channel and it doubles
  /// the bytes an SK pays to upload.
  static const int numChannels = 1;

  /// AAC-LC bitrate for the batch path.
  static const int batchBitRate = 64000;

  /// Config for the batch AI Scribe path — a whole utterance recorded to a
  /// file, then uploaded.
  static RecordConfig batch({required bool rawMicCapture}) => RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: sampleRate,
        numChannels: numChannels,
        bitRate: batchBitRate,
        androidConfig: AndroidRecordConfig(
          audioSource: rawMicCapture
              ? AndroidAudioSource.mic
              : AndroidAudioSource.defaultSource,
        ),
      );

  /// Config for the Real-Time ASR path — raw PCM16 chunks streamed over a
  /// WebSocket as they are captured.
  static RecordConfig realtimeStream({required bool rawMicCapture}) =>
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        androidConfig: AndroidRecordConfig(
          // voiceRecognition: Android's speech-recognition source (API 7+).
          // AGC enabled, AEC disabled — normalises gain across OEM hardware
          // without the phone-call echo cancellation that would suppress a
          // distant speaker.
          // rawMicCapture=true uses defaultSource (inputSource 0) as the
          // emulator escape hatch — emulator audio HALs that saturate with
          // voiceRecognition/mic (inputSource 6/1) typically work fine with
          // DEFAULT, which is what other Android apps use and what the
          // platform's hasPermission() probe also uses.
          audioSource: rawMicCapture
              ? AndroidAudioSource.defaultSource
              : AndroidAudioSource.voiceRecognition,
        ),
      );
}
