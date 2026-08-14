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
/// * `false` (default) — each path keeps the source it shipped with:
///   [AndroidAudioSource.defaultSource] for batch capture,
///   [AndroidAudioSource.mic] for the realtime stream. `defaultSource`
///   routes the signal through the handset's acoustic echo cancellation
///   (AEC), noise suppression and automatic gain control chain.
/// * `true` — both paths use [AndroidAudioSource.voiceRecognition], the
///   source Android documents as "tuned for voice recognition": supported
///   on every device since API 7, and not subject to the AEC that
///   `defaultSource` and `voiceCommunication` apply, while still keeping
///   the gain control that helps a distant or quiet speaker register.
///
/// Turn it on when the mic input is **audio being played back through a
/// loudspeaker** — a recorded test clip played at the handset, or a second
/// phone on speaker. AEC exists precisely to subtract speaker output from
/// mic input, so with the processed chain such a clip is cancelled down to
/// near-silence and the transcript comes back empty with no error. Some
/// emulator audio HALs also return constantly-saturated samples through
/// the processed chain.
///
/// Default is off: real field use is a person speaking directly at the
/// handset, where the processed chain is the better choice.
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
              ? AndroidAudioSource.voiceRecognition
              : AndroidAudioSource.defaultSource,
          manageBluetooth: _manageBluetooth,
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
          audioSource: rawMicCapture
              ? AndroidAudioSource.voiceRecognition
              // defaultSource routes through Android's AGC/NS/AEC processing
              // chain, which has been observed to return constantly-saturated
              // garbage (every sample pinned at the Int16 minimum) on some
              // emulator audio HALs. Raw mic source skips that chain.
              : AndroidAudioSource.mic,
          manageBluetooth: _manageBluetooth,
        ),
      );

  /// `record_android`'s Bluetooth SCO manager registers a receiver that
  /// replies to the native `start()` method-channel call from *either* a
  /// "SCO connected" or "SCO none" broadcast — whichever fires first. If a
  /// paired Bluetooth device's SCO connection state changes twice in quick
  /// succession right as recording starts (observed live: earbuds connected
  /// at app launch, still settling their connection when AI Scribe started),
  /// both broadcasts fire and the second reply throws
  /// `IllegalStateException: Reply already submitted`, crashing the app.
  ///
  /// Every capture path here wants the handset's own mic, never a Bluetooth
  /// headset's, so there is nothing this negotiation buys us — disabling it
  /// removes the crash instead of racing it.
  static const bool _manageBluetooth = false;
}
