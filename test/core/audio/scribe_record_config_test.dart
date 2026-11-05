import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:uhis_next/core/audio/scribe_record_config.dart';

void main() {
  group('ScribeRecordConfig.batch', () {
    test('defaults to the processed audio chain when raw capture is off', () {
      final cfg = ScribeRecordConfig.batch(rawMicCapture: false);

      expect(cfg.androidConfig.audioSource, AndroidAudioSource.defaultSource);
      expect(cfg.encoder, AudioEncoder.aacLc);
      expect(cfg.sampleRate, 16000);
      expect(cfg.numChannels, 1);
      expect(cfg.bitRate, 64000);
    });

    test('uses the truly raw mic source when raw capture is on', () {
      final cfg = ScribeRecordConfig.batch(rawMicCapture: true);

      // mic bypasses all on-device processing, including automatic gain
      // control — the emulator/diagnostic escape hatch when the processed
      // chain returns saturated garbage.
      expect(cfg.androidConfig.audioSource, AndroidAudioSource.mic);
    });

    test('keeps encoding identical across both capture modes', () {
      final off = ScribeRecordConfig.batch(rawMicCapture: false);
      final on = ScribeRecordConfig.batch(rawMicCapture: true);

      expect(on.encoder, off.encoder);
      expect(on.sampleRate, off.sampleRate);
      expect(on.numChannels, off.numChannels);
      expect(on.bitRate, off.bitRate);
    });
  });

  group('the disabled path is a no-op vs. the pre-setting behaviour', () {
    // Before this setting existed, the batch path passed NO androidConfig at
    // all, so it got the record package's implicit AndroidRecordConfig().
    // Now it always passes one. These pin that the off-path is still
    // field-for-field identical EXCEPT manageBluetooth (deliberately forced
    // off — see ScribeRecordConfig._manageBluetooth), so the rawMicCapture
    // setting itself genuinely changes nothing until an SK turns it on.
    test('batch off-path matches an implicit AndroidRecordConfig()', () {
      final a = ScribeRecordConfig.batch(rawMicCapture: false).androidConfig;
      const implicit = AndroidRecordConfig();

      expect(a.audioSource, implicit.audioSource);
      expect(a.useLegacy, implicit.useLegacy);
      expect(a.muteAudio, implicit.muteAudio);
      expect(a.manageBluetooth, isFalse);
      expect(a.speakerphone, implicit.speakerphone);
      expect(a.audioManagerMode, implicit.audioManagerMode);
    });

    test('realtime off-path changes only audioSource and manageBluetooth '
        'from the defaults', () {
      final a =
          ScribeRecordConfig.realtimeStream(rawMicCapture: false).androidConfig;
      const implicit = AndroidRecordConfig();

      // voiceRecognition normalises gain across OEM hardware (fixes
      // low-native-gain Motorola-class mics that never trigger server VAD
      // on the raw mic source); everything else stayed at the defaults
      // except manageBluetooth, forced off for every path (see
      // ScribeRecordConfig._manageBluetooth).
      expect(a.audioSource, AndroidAudioSource.voiceRecognition);
      expect(a.useLegacy, implicit.useLegacy);
      expect(a.muteAudio, implicit.muteAudio);
      expect(a.manageBluetooth, isFalse);
      expect(a.speakerphone, implicit.speakerphone);
      expect(a.audioManagerMode, implicit.audioManagerMode);
    });

    test('enabling changes the audio source and nothing else', () {
      for (final build in [
        ScribeRecordConfig.batch,
        ScribeRecordConfig.realtimeStream,
      ]) {
        final off = build(rawMicCapture: false).androidConfig;
        final on = build(rawMicCapture: true).androidConfig;

        expect(on.audioSource, isNot(off.audioSource));
        expect(on.useLegacy, off.useLegacy);
        expect(on.muteAudio, off.muteAudio);
        expect(on.manageBluetooth, off.manageBluetooth);
        expect(on.speakerphone, off.speakerphone);
        expect(on.audioManagerMode, off.audioManagerMode);
      }
    });
  });

  group('Bluetooth SCO management is disabled', () {
    // record_android's BluetoothManager registers a receiver that replies to
    // the start() method channel call from EITHER onBlScoConnected or
    // onBlScoNone — if a Bluetooth device's SCO connection state churns
    // right as recording starts, both fire and the second reply throws
    // "IllegalStateException: Reply already submitted", crashing the whole
    // app (live-caught with earbuds connected/disconnecting during AI
    // Scribe). This app has no use for SCO auto-negotiation — the phone's
    // own mic is what every capture path wants — so disabling it entirely
    // sidesteps the crash instead of racing it.
    test('batch config disables manageBluetooth', () {
      expect(
        ScribeRecordConfig.batch(rawMicCapture: false).androidConfig.manageBluetooth,
        isFalse,
      );
      expect(
        ScribeRecordConfig.batch(rawMicCapture: true).androidConfig.manageBluetooth,
        isFalse,
      );
    });

    test('realtime config disables manageBluetooth', () {
      expect(
        ScribeRecordConfig.realtimeStream(rawMicCapture: false)
            .androidConfig
            .manageBluetooth,
        isFalse,
      );
      expect(
        ScribeRecordConfig.realtimeStream(rawMicCapture: true)
            .androidConfig
            .manageBluetooth,
        isFalse,
      );
    });
  });

  group('ScribeRecordConfig.realtimeStream', () {
    test('uses the voiceRecognition source when raw capture is off', () {
      final cfg = ScribeRecordConfig.realtimeStream(rawMicCapture: false);

      // voiceRecognition (AGC on, AEC off) is the field-use default — it
      // normalises gain across OEM hardware differences instead of leaving
      // low-native-gain handsets too quiet for server-side VAD.
      expect(cfg.androidConfig.audioSource, AndroidAudioSource.voiceRecognition);
      expect(cfg.encoder, AudioEncoder.pcm16bits);
    });

    test('uses the defaultSource emulator escape hatch when raw capture is on', () {
      final cfg = ScribeRecordConfig.realtimeStream(rawMicCapture: true);

      expect(cfg.androidConfig.audioSource, AndroidAudioSource.defaultSource);
    });

    test('streams PCM16 mono at the rate the WAV header writer assumes', () {
      final cfg = ScribeRecordConfig.realtimeStream(rawMicCapture: false);

      expect(cfg.encoder, AudioEncoder.pcm16bits);
      expect(cfg.sampleRate, ScribeRecordConfig.sampleRate);
      expect(cfg.numChannels, 1);
    });
  });
}
