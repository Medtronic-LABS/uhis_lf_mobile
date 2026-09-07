import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../scribe/form_field_schema_builder.dart';
import '../scribe/models/ai_extracted_field.dart';

enum LocalScribeState {
  idle,
  requestingPermission,
  recording,
  transcribing,
  inferring,
  done,
  error,
}

/// Timing + transcript + extracted fields from a local pipeline run.
class LocalScribeResult {
  const LocalScribeResult({
    required this.transcript,
    required this.fields,
    required this.asrDurationMs,
    required this.llmDurationMs,
  });

  final String transcript;
  final List<AIExtractedField> fields;
  final int asrDurationMs;
  final int llmDurationMs;

  int get totalDurationMs => asrDurationMs + llmDurationMs;
}

/// On-device scribe: sherpa-onnx streaming ASR + Qwen3 GBNF-constrained form fill.
///
/// Usage:
///   1. Call [startRecording] when mic button pressed.
///   2. Call [stopRecording] when mic released.
///   3. Listen for [state] == [LocalScribeState.done] then read [result].
///
/// Shows timing in [LocalModelBadge] via [result.asrDurationMs] and [result.llmDurationMs].
class LocalScribeController extends ChangeNotifier {
  LocalScribeController({
    required this.sherpaModelDir,
    required this.llmModelPath,
  });

  /// Directory containing sherpa-onnx transducer model files
  /// (encoder.onnx, decoder.onnx, joiner.onnx, tokens.txt).
  final String sherpaModelDir;

  /// Path to Qwen3 GGUF model file on device.
  final String llmModelPath;

  final AudioRecorder _recorder = AudioRecorder();

  LocalScribeState _state = LocalScribeState.idle;
  LocalScribeState get state => _state;

  String? _transcript;
  String? get transcript => _transcript;

  LocalScribeResult? _result;
  LocalScribeResult? get result => _result;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _elapsedSeconds = 0;
  int get elapsedSeconds => _elapsedSeconds;

  Timer? _elapsedTimer;
  String? _recordingPath;

  sherpa.OnlineRecognizer? _recognizer;

  bool get isActive =>
      _state == LocalScribeState.recording ||
      _state == LocalScribeState.transcribing ||
      _state == LocalScribeState.inferring;

  // GBNF grammar forces Qwen3 to emit valid JSON only (no prose).
  static const _jsonGrammar = r'''
root   ::= object
object ::= "{" ws (pair ("," ws pair)*)? ws "}"
pair   ::= string ws ":" ws value
string ::= "\"" char* "\""
char   ::= [^"\\\x7F\x00-\x1F] | "\\" ["\\/bfnrt]
value  ::= string | "null"
ws     ::= [ \t\n\r]*
''';

  Future<void> startRecording(List<FormFieldSchema> schema) async {
    if (isActive) return;
    _setState(LocalScribeState.requestingPermission);

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _setError('Microphone permission denied.');
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${dir.path}/local_scribe_$ts.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: _recordingPath!,
      );

      _elapsedSeconds = 0;
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _elapsedSeconds++;
        notifyListeners();
      });

      _setState(LocalScribeState.recording);
    } catch (e) {
      _setError('Recording failed: $e');
    }
  }

  Future<void> stopRecording(List<FormFieldSchema> schema) async {
    if (_state != LocalScribeState.recording) return;
    _elapsedTimer?.cancel();

    final path = await _recorder.stop();
    if (path == null) {
      _setError('No audio captured.');
      return;
    }

    await _runPipeline(path, schema);
  }

  Future<void> _runPipeline(String audioPath, List<FormFieldSchema> schema) async {
    _setState(LocalScribeState.transcribing);

    try {
      // ── ASR ──────────────────────────────────────────────────────────────
      final asrStart = DateTime.now();
      final transcript = await _transcribe(audioPath);
      final asrMs = DateTime.now().difference(asrStart).inMilliseconds;
      debugPrint('[LocalScribe] ASR done in ${asrMs}ms: "$transcript"');

      _transcript = transcript;
      notifyListeners();

      // ── LLM form fill ────────────────────────────────────────────────────
      _setState(LocalScribeState.inferring);
      final llmStart = DateTime.now();
      final fields = await _extractFields(transcript, schema);
      final llmMs = DateTime.now().difference(llmStart).inMilliseconds;
      debugPrint('[LocalScribe] LLM done in ${llmMs}ms, ${fields.length} fields');

      _result = LocalScribeResult(
        transcript: transcript,
        fields: fields,
        asrDurationMs: asrMs,
        llmDurationMs: llmMs,
      );
      _setState(LocalScribeState.done);
    } catch (e, st) {
      debugPrint('[LocalScribe] pipeline error: $e\n$st');
      _setError(e.toString());
    }
  }

  Future<String> _transcribe(String audioPath) async {
    _recognizer ??= _buildRecognizer();
    final rec = _recognizer!;

    final wave = sherpa.readWave(audioPath);
    if (wave.samples.isEmpty) throw Exception('Empty audio');

    final stream = rec.createStream();
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    rec.decode(stream);
    final result = rec.getResult(stream);
    stream.free();

    return result.text.trim();
  }

  sherpa.OnlineRecognizer _buildRecognizer() {
    final config = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$sherpaModelDir/encoder.onnx',
          decoder: '$sherpaModelDir/decoder.onnx',
          joiner: '$sherpaModelDir/joiner.onnx',
        ),
        tokens: '$sherpaModelDir/tokens.txt',
        modelType: 'transducer',
      ),
      decodingMethod: 'greedy_search',
    );
    return sherpa.OnlineRecognizer(config);
  }

  Future<List<AIExtractedField>> _extractFields(
    String transcript,
    List<FormFieldSchema> schema,
  ) async {
    if (transcript.isEmpty || schema.isEmpty) return [];
    if (!File(llmModelPath).existsSync()) {
      debugPrint('[LocalScribe] LLM model not found at $llmModelPath, skipping');
      return [];
    }

    final engine = await LlamaEngine.spawn(
      modelParams: ModelParams(path: llmModelPath, gpuLayers: 0),
      contextParams: const ContextParams(nCtx: 1024),
    );

    try {
      final fieldLines = schema
          .map((f) => '  "${f.fieldId}" (${f.label}): free text or null')
          .join('\n');

      final chat = await engine.createChat();
      chat.addSystem(
        'You extract clinical field values from a Bengali speech transcript. '
        'Output ONLY a JSON object. Set each key to the extracted value string '
        'or null if not mentioned in the transcript.',
      );
      chat.addUser(
        'Transcript: "$transcript"\n\nFields:\n$fieldLines',
      );

      final buffer = StringBuffer();
      await for (final event in chat.generate(
        sampler: SamplerParams(
          temperature: 0.1,
          topP: 0.9,
          grammar: const GrammarConfig(grammar: _jsonGrammar),
        ),
        maxTokens: 512,
      )) {
        if (event is TokenEvent) buffer.write(event.text);
        if (event is DoneEvent) break;
      }
      await chat.dispose();

      final raw = buffer.toString().trim();
      debugPrint('[LocalScribe] LLM raw: $raw');
      return _parseFields(raw);
    } finally {
      await engine.dispose();
    }
  }

  List<AIExtractedField> _parseFields(String json) {
    final result = <AIExtractedField>[];
    final now = DateTime.now();
    final pattern = RegExp(r'"([^"]+)"\s*:\s*(?:"([^"]*)"|(null))');
    for (final m in pattern.allMatches(json)) {
      final key = m.group(1)!;
      final val = m.group(2);
      if (val != null && val.isNotEmpty) {
        result.add(AIExtractedField(
          fieldId: key,
          value: val,
          confidence: 0.85,
          source: FieldSource.aiPending,
          extractedAt: now,
        ));
      }
    }
    return result;
  }

  void resetSession() {
    _state = LocalScribeState.idle;
    _transcript = null;
    _result = null;
    _errorMessage = null;
    _elapsedSeconds = 0;
    notifyListeners();
  }

  void _setState(LocalScribeState s) {
    _state = s;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _state = LocalScribeState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _recorder.dispose();
    _recognizer?.free();
    super.dispose();
  }
}
