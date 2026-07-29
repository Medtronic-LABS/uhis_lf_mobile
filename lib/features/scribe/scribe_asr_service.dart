import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/debug/console_log.dart';

/// ASR service backed by either the Bengali Zipformer2 or Whisper Small model.
///
/// Modes:
///   - [transcribeFile]: batch WAV — Zipformer2 online recognizer.
///   - [transcribeRealtime]: streaming PCM — Zipformer2 online recognizer.
///   - [transcribeAccumulated]: batch PCM buffer — Whisper Small offline recognizer.
///     Runs after recording stops; outputs clean English from code-mixed speech,
///     matching the server's Sarvam ASR quality without the Bengali-phonetic-script
///     problem that makes downstream keyword matching fail.
class ScribeAsrService {
  const ScribeAsrService(this.modelDir);
  final String modelDir;

  // ── Whisper Small (OfflineRecognizer) ────────────────────────────────────

  sherpa.OfflineRecognizerConfig _buildWhisperConfig() {
    sherpa.initBindings();
    // int8-quantized encoder/decoder — ~100 MB total; good accuracy/speed
    // on mobile CPUs. `task = 'translate'` always outputs English, mirroring
    // the server's English-output Sarvam ASR path so keyword matching works.
    return sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: '$modelDir/encoder.int8.onnx',
          decoder: '$modelDir/decoder.int8.onnx',
          language: '',
          task: 'translate',
        ),
        tokens: '$modelDir/tokens.txt',
        numThreads: 2,
        debug: false,
        modelType: 'whisper',
      ),
    );
  }

  /// Transcribe raw PCM16 bytes (no WAV header) accumulated during recording.
  ///
  /// Sends the entire buffer to Whisper Small in one shot — better quality than
  /// short windowed segments. Call after [AudioRecorder.stop()] to transcribe
  /// the full recording. Returns an empty string on failure.
  Future<String> transcribeAccumulated(List<int> rawPcmBytes) async {
    if (rawPcmBytes.isEmpty) return '';
    final config = _buildWhisperConfig();
    final recognizer = sherpa.OfflineRecognizer(config);
    final stream = recognizer.createStream();
    try {
      final bytes = Uint8List.fromList(rawPcmBytes);
      final samples = _pcm16BytesToFloat(bytes);
      if (samples.isEmpty) return '';
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text.trim();
      ConsoleLog.success('[ScribeAsrService] Whisper transcript: ${text.length} chars');
      return text;
    } finally {
      stream.free();
      recognizer.free();
    }
  }

  sherpa.OnlineRecognizerConfig _buildConfig() {
    // Ensure the native sherpa-onnx FFI bindings are loaded before any API
    // call.  initBindings() is idempotent (uses ??= internally) and safe to
    // call multiple times.
    sherpa.initBindings();
    return sherpa.OnlineRecognizerConfig(
    model: sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: '$modelDir/encoder.onnx',
        decoder: '$modelDir/decoder.onnx',
        joiner: '$modelDir/joiner.onnx',
      ),
      tokens: '$modelDir/tokens.txt',
      numThreads: 2,
      provider: 'cpu',
      modelType: 'zipformer2',
      debug: false,
    ),
    feat: sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
    enableEndpoint: true,
    rule1MinTrailingSilence: 2.4,
    rule2MinTrailingSilence: 1.2,
    rule3MinUtteranceLength: 20.0,
    );
  }

  /// Streams raw PCM16 chunks from [pcmChunks] through the online recognizer
  /// and yields the accumulated transcript text after each detected endpoint.
  ///
  /// Input is raw PCM16 bytes with no WAV header (as produced by
  /// [AudioRecorder.startStream] with [AudioEncoder.pcm16bits]).
  Stream<String> transcribeRealtime(Stream<List<int>> pcmChunks) async* {
    final recognizer = sherpa.OnlineRecognizer(_buildConfig());
    final stream = recognizer.createStream();
    final buf = StringBuffer();
    try {
      await for (final chunk in pcmChunks) {
        if (chunk.isEmpty) continue;
        // Always copy — stream chunks may be sublist views with non-zero
        // offsetInBytes that would break asInt16List().
        final bytes = Uint8List.fromList(chunk);
        final samples = _pcm16BytesToFloat(bytes);
        stream.acceptWaveform(samples: samples, sampleRate: 16000);
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }
        if (recognizer.isEndpoint(stream)) {
          final seg = recognizer.getResult(stream).text.trim();
          if (seg.isNotEmpty) {
            if (buf.isNotEmpty) buf.write(' ');
            buf.write(seg);
            yield buf.toString();
          }
          recognizer.reset(stream);
        }
      }
      // Flush any remaining audio after the stream closes.
      stream.inputFinished();
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final last = recognizer.getResult(stream).text.trim();
      if (last.isNotEmpty) {
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(last);
        yield buf.toString();
      }
      ConsoleLog.success('[ScribeAsrService] realtime transcript: ${buf.length} chars');
    } finally {
      stream.free();
      recognizer.free();
    }
  }

  Future<String> transcribeFile(String wavPath) async {
    final recognizer = sherpa.OnlineRecognizer(_buildConfig());
    final stream = recognizer.createStream();
    try {
      final bytes = await File(wavPath).readAsBytes();
      final samples = _decodePcm16(bytes);
      ConsoleLog.step('[ScribeAsrService] transcribing ${samples.length} samples');
      const chunkSize = 3200; // 200ms @ 16 kHz
      for (var i = 0; i < samples.length; i += chunkSize) {
        final end = min(i + chunkSize, samples.length);
        stream.acceptWaveform(
          samples: Float32List.sublistView(samples, i, end),
          sampleRate: 16000,
        );
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }
      }
      stream.inputFinished();
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final text = recognizer.getResult(stream).text.trim();
      ConsoleLog.success('[ScribeAsrService] transcript ${text.length} chars');
      return text;
    } finally {
      stream.free();
      recognizer.free();
    }
  }

  /// Decode a PCM16 WAV file (skips 44-byte header).
  Float32List _decodePcm16(Uint8List bytes) {
    const headerSize = 44;
    if (bytes.length <= headerSize) return Float32List(0);
    final pcm = bytes.buffer.asInt16List(
      bytes.offsetInBytes + headerSize,
      (bytes.length - headerSize) ~/ 2,
    );
    final out = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = pcm[i] / 32768.0;
    }
    return out;
  }

  /// Decode raw PCM16 bytes with no WAV header (from [AudioRecorder.startStream]).
  ///
  /// [AudioRecorder.startStream] may deliver chunks as sublist views whose
  /// [ByteBuffer.offsetInBytes] is not a multiple of 2 — required by
  /// [ByteBuffer.asInt16List].  Copying into a fresh [Uint8List] aligns the
  /// offset to 0 before reinterpreting.
  Float32List _pcm16BytesToFloat(Uint8List bytes) {
    if (bytes.isEmpty) return Float32List(0);
    // Always copy to guarantee offsetInBytes == 0 for asInt16List().
    final aligned = Uint8List.fromList(bytes);
    final pcm = aligned.buffer.asInt16List();
    final out = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = pcm[i] / 32768.0;
    }
    return out;
  }
}
