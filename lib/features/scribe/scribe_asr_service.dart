import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/debug/console_log.dart';

/// ASR service backed by the sherpa-onnx Bengali Zipformer2 model.
///
/// Two modes:
///   - [transcribeFile]: batch — reads a PCM16 WAV file and returns the full transcript.
///   - [transcribeRealtime]: streaming — accepts a raw PCM16 byte stream and
///     yields partial transcripts in real-time as the recognizer reaches endpoints.
class ScribeAsrService {
  const ScribeAsrService(this.modelDir);
  final String modelDir;

  sherpa.OnlineRecognizerConfig _buildConfig() => sherpa.OnlineRecognizerConfig(
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
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
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
  Float32List _pcm16BytesToFloat(Uint8List bytes) {
    if (bytes.isEmpty) return Float32List(0);
    final pcm = bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
    final out = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = pcm[i] / 32768.0;
    }
    return out;
  }
}
