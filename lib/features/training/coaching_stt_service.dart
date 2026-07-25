import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/debug/console_log.dart';

class SttPartialResult {
  const SttPartialResult({required this.text, required this.isFinal});
  final String text;
  final bool isFinal;
}

class CoachingSttService {
  static const int _sampleRate = 16000;

  sherpa.OnlineRecognizer? _recognizer;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  StreamController<SttPartialResult>? _resultController;
  bool _isListening = false;

  bool get isAvailable => _recognizer != null;
  bool get isListening => _isListening;

  Future<void> initialize(String modelDir) async {
    if (_recognizer != null) return;
    final encoder = File('$modelDir/encoder.onnx');
    if (!encoder.existsSync()) {
      ConsoleLog.warn('[CoachingSttService] model files not found at $modelDir');
      return;
    }
    try {
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
        feat: sherpa.FeatureConfig(
          sampleRate: _sampleRate,
          featureDim: 80,
        ),
        decodingMethod: 'greedy_search',
        maxActivePaths: 4,
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.4,
        rule2MinTrailingSilence: 1.2,
        rule3MinUtteranceLength: 20.0,
      );
      _recognizer = sherpa.OnlineRecognizer(config);
      ConsoleLog.success('[CoachingSttService] recognizer initialized at $modelDir');
    } on Exception catch (e) {
      ConsoleLog.warn('[CoachingSttService] init failed: $e');
    }
  }

  Stream<SttPartialResult> startListening() {
    if (_recognizer == null || _isListening) {
      return const Stream.empty();
    }
    _resultController = StreamController<SttPartialResult>.broadcast();
    _isListening = true;
    _beginCapture();
    return _resultController!.stream;
  }

  void _beginCapture() async {
    final recognizer = _recognizer;
    if (recognizer == null) return;

    final recorder = AudioRecorder();
    _recorder = recorder;

    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      _resultController?.addError(Exception('microphone permission denied'));
      await stopListening();
      return;
    }

    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );

    final recStream = recognizer.createStream();
    String lastPartial = '';

    _audioSub = stream.listen(
      (Uint8List chunk) {
        if (!_isListening) return;
        final samples = _pcm16ToFloat32(chunk);
        recStream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
        while (recognizer.isReady(recStream)) {
          recognizer.decode(recStream);
        }
        final text = recognizer.getResult(recStream).text.trim();
        if (text.isNotEmpty && text != lastPartial) {
          lastPartial = text;
          _resultController?.add(SttPartialResult(text: text, isFinal: false));
        }
        if (recognizer.isEndpoint(recStream)) {
          final finalText = recognizer.getResult(recStream).text.trim();
          recognizer.reset(recStream);
          lastPartial = '';
          if (finalText.isNotEmpty) {
            _resultController?.add(SttPartialResult(text: finalText, isFinal: true));
          }
        }
      },
      onDone: () {
        // Drain any remaining partial on stream close.
        final text = recognizer.getResult(recStream).text.trim();
        if (text.isNotEmpty) {
          _resultController?.add(SttPartialResult(text: text, isFinal: true));
        }
        recStream.free();
        _resultController?.close();
        _isListening = false;
      },
      onError: (Object e) {
        ConsoleLog.warn('[CoachingSttService] audio stream error: $e');
        recStream.free();
        _resultController?.addError(e);
        _resultController?.close();
        _isListening = false;
      },
      cancelOnError: true,
    );
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _audioSub?.cancel();
    _audioSub = null;
    await _recorder?.stop();
    _recorder?.dispose();
    _recorder = null;
    // Stream close + controller close handled by onDone callback.
  }

  void dispose() {
    stopListening();
    _recognizer?.free();
    _recognizer = null;
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final int16 = bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
    final f32 = Float32List(int16.length);
    for (var i = 0; i < int16.length; i++) {
      f32[i] = int16[i] / 32768.0;
    }
    return f32;
  }
}
