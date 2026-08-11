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

    test('uses the voiceRecognition source when raw capture is on', () {
      final cfg = ScribeRecordConfig.batch(rawMicCapture: true);

      // voiceRecognition is the source that skips acoustic echo cancellation,
      // which is what lets loudspeaker playback reach the recording instead
      // of being cancelled out as echo.
      expect(cfg.androidConfig.audioSource, AndroidAudioSource.voiceRecognition);
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

  group('ScribeRecordConfig.realtimeStream', () {
    test('keeps the raw mic source when raw capture is off', () {
      final cfg = ScribeRecordConfig.realtimeStream(rawMicCapture: false);

      expect(cfg.androidConfig.audioSource, AndroidAudioSource.mic);
      expect(cfg.encoder, AudioEncoder.pcm16bits);
    });

    test('uses the voiceRecognition source when raw capture is on', () {
      final cfg = ScribeRecordConfig.realtimeStream(rawMicCapture: true);

      expect(cfg.androidConfig.audioSource, AndroidAudioSource.voiceRecognition);
    });

    test('streams PCM16 mono at the rate the WAV header writer assumes', () {
      final cfg = ScribeRecordConfig.realtimeStream(rawMicCapture: false);

      expect(cfg.encoder, AudioEncoder.pcm16bits);
      expect(cfg.sampleRate, ScribeRecordConfig.sampleRate);
      expect(cfg.numChannels, 1);
    });
  });
}
