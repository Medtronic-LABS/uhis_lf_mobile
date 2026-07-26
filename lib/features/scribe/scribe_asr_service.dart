import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/debug/console_log.dart';

/// Batch ASR: pumps a PCM16 WAV file through the sherpa-onnx Bengali
/// Zipformer2 model and returns the transcript string.
class ScribeAsrService {
  const ScribeAsrService(this.modelDir);
  final String modelDir;

  Future<String> transcribeFile(String wavPath) async {
    final config = sherpa.OnlineRecognizerConfig(
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

    final recognizer = sherpa.OnlineRecognizer(config);
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
}
