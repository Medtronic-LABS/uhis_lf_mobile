import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

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
/// Streams raw PCM from the mic into sherpa-onnx OnlineRecognizer chunk by
/// chunk — transcript updates live during recording, same as the remote
/// WebSocket ASR, but fully on-device with no network required.
///
/// Usage:
///   1. Call [startRecording] when mic button pressed.
///   2. Call [stopRecording] when mic released.
///   3. Listen for [state] == [LocalScribeState.done] then read [result].
class LocalScribeController extends ChangeNotifier {
  LocalScribeController({
    required this.sherpaModelDir,
    required this.llmModelPath,
    this.activeLlmId = '',
  });

  final String sherpaModelDir;
  final String llmModelPath;
  final String activeLlmId;

  final AudioRecorder _recorder = AudioRecorder();

  bool _isDisposed = false;

  LocalScribeState _state = LocalScribeState.idle;
  LocalScribeState get state => _state;

  String _transcript = '';
  String get transcript => _transcript;

  LocalScribeResult? _result;
  LocalScribeResult? get result => _result;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _elapsedSeconds = 0;
  int get elapsedSeconds => _elapsedSeconds;

  Timer? _elapsedTimer;
  StreamSubscription<Uint8List>? _audioSub;

  sherpa.OnlineRecognizer? _recognizer;
  DateTime? _asrStart;

  // PCM buffer — accumulate raw bytes during recording, process all at stop.
  final List<int> _pcmBuffer = [];

  // Live streaming state — single OnlineStream maintained for the full recording.
  // Audio chunks flow straight in; endpoint detection commits segments in real-time.
  sherpa.OnlineStream? _onlineStream;
  String _accumulatedSegments = '';

  // Fallback timer — fires every 500ms with inputFinished() to flush
  // any frames the model hasn't committed to an endpoint yet.
  Timer? _livePreviewTimer;

  // Live LLM extraction — debounce fires 1.5s after transcript stabilises
  // during recording; results broadcast immediately so banner can pre-fill.
  List<FormFieldSchema>? _schema;
  bool _llmRunning = false;
  Future<void>? _currentLlmFuture; // awaited by stopRecording to avoid "in flight" error
  List<AIExtractedField> _liveFields = [];
  List<AIExtractedField> get liveFields => _liveFields;
  Timer? _liveExtractDebounce;

  // Cached across sessions — loading 400MB GGUF takes 10-15s on CPU;
  // keeping it alive avoids that cost on every tap-stop cycle.
  LlamaEngine? _llmEngine;

  bool get isActive =>
      _state == LocalScribeState.recording ||
      _state == LocalScribeState.transcribing ||
      _state == LocalScribeState.inferring;

  // Bengali/Hindi keyword → symptom code. Covers garbled ASR variants.
  static const _symptomKeywords = <String, List<String>>{
    'fever':                      ['জ্বর', 'জর', 'তাপ', 'গরম শরীর'],
    'headache':                   ['মাথা ব্যথা', 'মাথাব্যথা', 'মাথায় ব্যথা', 'মাথা'],
    'chest_pain':                 ['ছাতি', 'চাতি', 'বুকে', 'বুক ব্যথা', 'বুকব্যথা', 'chest'],
    'abdominal_pain':             ['পেটে ব্যথা', 'পেট ব্যথা', 'পেটব্যথা', 'তলপেট', 'পেটে'],
    'vomiting':                   ['বমি', 'বমি হচ্ছে', 'বমি বমি', 'উলটি', 'বমন'],
    'breathlessness':             ['শ্বাস', 'শ্বাসকষ্ট', 'নিঃশ্বাস', 'শ্বাস নিতে'],
    'dizziness':                  ['মাথা ঘোরা', 'মাথাঘোরা', 'চক্কর', 'ঘোরা'],
    'weakness':                   ['দুর্বল', 'দুর্বলতা', 'শক্তিহীন', 'শক্তি নেই'],
    'fatigue':                    ['ক্লান্ত', 'ক্লান্তি', 'অবসাদ', 'ফ্যাটিক', 'ফ্যাটিগ', 'fatigue'],
    'edema':                      ['ফোলা', 'পা ফোলা', 'হাত ফোলা', 'শোথ'],
    'swelling_face_hands':        ['মুখ ফোলা', 'হাত ফোলা', 'মুখ ও হাত'],
    'blurred_vision':             ['চোখ ঝাপসা', 'ঝাপসা', 'দৃষ্টি'],
    'convulsions':                ['খিঁচুনি', 'খিচুনি', 'আক্ষেপ'],
    'reduced_fetal_movement':     ['বাচ্চা নড়ছে না', 'নড়াচড়া', 'নড়াচড়া কম'],
    'heavy_bleeding':             ['রক্ত', 'রক্তক্ষরণ', 'ব্লিডিং'],
    'vaginal_bleeding':           ['যোনি থেকে রক্ত', 'রক্তপাত'],
    'painful_urination':          ['প্রস্রাবে ব্যথা', 'পেশাবে ব্যথা', 'জ্বালা'],
    'leaking_fluid_vagina':       ['পানি ভেঙেছে', 'পানি পড়ছে', 'পানি ভেঙ'],
    'painful_uterine_contractions': ['পেটে টান', 'ব্যথা উঠছে', 'প্রসব ব্যথা'],
    'breast_pain':                ['বুকে ব্যথা', 'স্তনে ব্যথা', 'স্তন ব্যথা'],
    'breast_swelling':            ['স্তন ফোলা', 'বুক ফোলা'],
    'foul_smelling_vaginal_discharge': ['দুর্গন্ধ', 'স্রাব', 'দুর্গন্ধযুক্ত'],
    'perineal_wound_discharge':   ['ঘা থেকে পানি', 'ক্ষত', 'সেলাই'],
  };

  List<AIExtractedField> _keywordTriage(
    String transcript,
    List<FormFieldSchema> schema,
  ) {
    final validCodes = {for (final f in schema) f.fieldId};
    final now = DateTime.now();
    final matched = <String>{};
    for (final entry in _symptomKeywords.entries) {
      if (!validCodes.contains(entry.key)) continue;
      for (final kw in entry.value) {
        if (transcript.contains(kw)) {
          matched.add(entry.key);
          break;
        }
      }
    }
    debugPrint('[LocalScribe] keyword triage hits: $matched');
    return matched.map((code) => AIExtractedField(
      fieldId: code,
      value: 'yes',
      confidence: 0.7,
      source: FieldSource.aiPending,
      extractedAt: now,
    )).toList();
  }

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
    _schema = schema;
    _liveFields = [];
    _transcript = '';
    _result = null;
    _errorMessage = null;
    _setState(LocalScribeState.requestingPermission);

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _setError('Microphone permission denied.');
      return;
    }

    // Pre-warm LLM engine so first live extraction doesn't pay cold-start cost.
    unawaited(_ensureLlmEngine().catchError(
      (e) => debugPrint('[LocalScribe] LLM pre-warm error: $e'),
    ));

    try {
      debugPrint('[LocalScribe] building recognizer from $sherpaModelDir');
      sherpa.initBindings();
      _recognizer ??= _buildRecognizer();
      debugPrint('[LocalScribe] recognizer ready');
      _pcmBuffer.clear();
      _accumulatedSegments = '';
      _onlineStream?.free();
      _onlineStream = _recognizer!.createStream();
      // Fallback timer: every 500ms, flush remaining frames via inputFinished()
      // to produce partial transcripts when the model hasn't hit an endpoint yet.
      _livePreviewTimer?.cancel();
      _livePreviewTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _refreshLiveTranscript(),
      );
      _asrStart = DateTime.now();

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _audioSub = stream.listen(
        _onAudioChunk,
        onError: (Object e, StackTrace st) {
          debugPrint('[LocalScribe] audio stream error: $e\n$st');
          _setError('Audio error: $e');
        },
        onDone: () {
          debugPrint('[LocalScribe] audio stream closed (state=$_state)');
        },
        cancelOnError: false,
      );

      _elapsedSeconds = 0;
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _elapsedSeconds++;
        notifyListeners();
      });

      _setState(LocalScribeState.recording);
    } catch (e, st) {
      debugPrint('[LocalScribe] startRecording error: $e\n$st');
      _setError('Recording failed: $e');
    }
  }

  void _onAudioChunk(Uint8List pcm) {
    _pcmBuffer.addAll(pcm);
    if (_recognizer == null || _onlineStream == null) return;

    // Feed this chunk straight into the live stream — same pattern as the
    // server's Sarvam bridge: each audio frame → decode → emit segment.
    final samples = _int16ToFloat32(pcm);
    _onlineStream!.acceptWaveform(samples: samples, sampleRate: 16000);

    while (_recognizer!.isReady(_onlineStream!)) {
      _recognizer!.decode(_onlineStream!);
    }

    // Commit completed segment when endpoint detected, reset for next.
    if (_recognizer!.isEndpoint(_onlineStream!)) {
      final seg = _recognizer!.getResult(_onlineStream!).text.trim();
      debugPrint('[LocalScribe] endpoint segment: "$seg"');
      if (seg.isNotEmpty) {
        _accumulatedSegments = _accumulatedSegments.isEmpty ? seg : '$_accumulatedSegments $seg';
      }
      _recognizer!.reset(_onlineStream!);
    }

    final partial = _recognizer!.getResult(_onlineStream!).text.trim();
    final display = _accumulatedSegments.isEmpty
        ? partial
        : (partial.isEmpty ? _accumulatedSegments : '$_accumulatedSegments $partial');

    if (display.isNotEmpty && display != _transcript) {
      _transcript = display;
      notifyListeners();
      _scheduleLiveExtract();
    }
  }

  /// Debounce: 1.5s after transcript stops changing, fire live LLM extraction.
  void _scheduleLiveExtract() {
    if (_schema == null || _schema!.isEmpty) return;
    _liveExtractDebounce?.cancel();
    _liveExtractDebounce = Timer(
      const Duration(milliseconds: 1500),
      _runLiveExtract,
    );
  }

  Future<void> _runLiveExtract() async {
    if (_isDisposed) return;
    if (_llmRunning) { debugPrint('[LocalScribe] live extract skipped: llm busy'); return; }
    if (_transcript.isEmpty) { debugPrint('[LocalScribe] live extract skipped: empty transcript'); return; }
    if (_schema == null || _schema!.isEmpty) { debugPrint('[LocalScribe] live extract skipped: no schema (${_schema?.length} fields)'); return; }
    if (_state != LocalScribeState.recording) { debugPrint('[LocalScribe] live extract skipped: state=$_state'); return; }
    _llmRunning = true;
    final snapshot = _transcript;
    debugPrint('[LocalScribe] live extract start: "${snapshot.length}chars"');
    final future = _extractFields(snapshot, _schema!).then((fields) {
      // State may be transcribing by now (user stopped mid-extract) — still save.
      if (!_isDisposed && fields.isNotEmpty) {
        _liveFields = fields;
        debugPrint('[LocalScribe] live extract done: ${fields.length} fields');
        notifyListeners();
      }
    }).catchError((Object e) {
      debugPrint('[LocalScribe] live extract error: $e');
    }).whenComplete(() {
      _llmRunning = false;
      _currentLlmFuture = null;
    });
    _currentLlmFuture = future;
    await future;
  }

  /// Fallback: decode recent audio with inputFinished() to get partial
  /// transcript when isReady() hasn't fired (zipformer2 needs this).
  /// Capped to last 3 s to keep cost O(1) regardless of recording length.
  void _refreshLiveTranscript() {
    if (_recognizer == null || _pcmBuffer.isEmpty) return;
    final rec = _recognizer!;
    // 3 s × 16 kHz × 2 bytes/sample = 96 000 bytes
    const maxBytes = 96000;
    final tail = _pcmBuffer.length > maxBytes
        ? Uint8List.fromList(_pcmBuffer.sublist(_pcmBuffer.length - maxBytes))
        : Uint8List.fromList(_pcmBuffer);
    final tmpStream = rec.createStream();
    try {
      final samples = _int16ToFloat32(tail);
      const window = 1600;
      for (var i = 0; i < samples.length; i += window) {
        final end = (i + window).clamp(0, samples.length);
        tmpStream.acceptWaveform(
          samples: Float32List.sublistView(samples, i, end),
          sampleRate: 16000,
        );
      }
      tmpStream.inputFinished();
      while (rec.isReady(tmpStream)) {
        rec.decode(tmpStream);
      }
      final partial = rec.getResult(tmpStream).text.trim();
      final display = _accumulatedSegments.isEmpty
          ? partial
          : (partial.isEmpty ? _accumulatedSegments : '$_accumulatedSegments $partial');
      debugPrint('[LocalScribe] live flush: "$display"');
      if (display.isNotEmpty && display != _transcript) {
        _transcript = display;
        notifyListeners();
        _scheduleLiveExtract();
      }
    } catch (e) {
      debugPrint('[LocalScribe] live flush error: $e');
    } finally {
      tmpStream.free();
    }
  }

  Future<void> stopRecording(List<FormFieldSchema> schema) async {
    if (_state != LocalScribeState.recording) return;
    _elapsedTimer?.cancel();
    _liveExtractDebounce?.cancel();
    _liveExtractDebounce = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _recorder.stop();
    _livePreviewTimer?.cancel();
    _livePreviewTimer = null;
    _setState(LocalScribeState.transcribing);

    final asrMs = _asrStart != null
        ? DateTime.now().difference(_asrStart!).inMilliseconds
        : 0;

    // Finalize: flush the live stream with inputFinished() to get any
    // remaining frames, then batch-verify against the full PCM buffer.
    try {
      final rec = _recognizer ?? _buildRecognizer();
      _recognizer = rec;

      // First: flush the live stream's tail.
      String liveResult = _accumulatedSegments;
      if (_onlineStream != null) {
        _onlineStream!.inputFinished();
        while (rec.isReady(_onlineStream!)) {
          rec.decode(_onlineStream!);
        }
        final tail = rec.getResult(_onlineStream!).text.trim();
        if (tail.isNotEmpty) {
          liveResult = liveResult.isEmpty ? tail : '$liveResult $tail';
        }
        _onlineStream!.free();
        _onlineStream = null;
      }

      // Then: batch decode full buffer for accuracy (always more accurate).
      final asrStream = rec.createStream();
      try {
        final allSamples = _int16ToFloat32(Uint8List.fromList(_pcmBuffer));
        const windowSize = 1600;
        for (var offset = 0; offset < allSamples.length; offset += windowSize) {
          final end = (offset + windowSize).clamp(0, allSamples.length);
          asrStream.acceptWaveform(
            samples: Float32List.sublistView(allSamples, offset, end),
            sampleRate: 16000,
          );
        }
        asrStream.inputFinished();
        while (rec.isReady(asrStream)) {
          rec.decode(asrStream);
        }
        final batchText = rec.getResult(asrStream).text.trim();
        // Prefer batch result when non-empty (higher quality); fall back to live.
        _transcript = batchText.isNotEmpty ? batchText : liveResult;
      } finally {
        asrStream.free();
      }
    } catch (e, st) {
      debugPrint('[LocalScribe] ASR batch error: $e\n$st');
    }

    _pcmBuffer.clear();
    debugPrint('[LocalScribe] ASR done in ${asrMs}ms: "$_transcript"');
    notifyListeners();

    // Wait for any in-flight live extract to finish — avoids "generate in flight" error.
    if (_llmRunning && _currentLlmFuture != null) {
      debugPrint('[LocalScribe] awaiting in-flight live extract before stop…');
      await _currentLlmFuture;
    }

    // If live extract already ran on the same transcript, reuse results.
    if (_liveFields.isNotEmpty && !_llmRunning) {
      debugPrint('[LocalScribe] reusing live fields (${_liveFields.length} fields)');
      _result = LocalScribeResult(
        transcript: _transcript,
        fields: _liveFields,
        asrDurationMs: asrMs,
        llmDurationMs: 0,
      );
      _setState(LocalScribeState.done);
    } else {
      await _runLlm(schema, asrMs);
    }
  }

  Future<void> _runLlm(List<FormFieldSchema> schema, int asrMs) async {
    _setState(LocalScribeState.inferring);
    try {
      final llmStart = DateTime.now();
      final fields = await _extractFields(_transcript, schema);
      final llmMs = DateTime.now().difference(llmStart).inMilliseconds;
      debugPrint('[LocalScribe] LLM done in ${llmMs}ms, ${fields.length} fields');

      _result = LocalScribeResult(
        transcript: _transcript,
        fields: fields,
        asrDurationMs: asrMs,
        llmDurationMs: llmMs,
      );
      _setState(LocalScribeState.done);
    } catch (e, st) {
      debugPrint('[LocalScribe] LLM error: $e\n$st');
      // Still mark done with empty fields so banner shows result
      _result = LocalScribeResult(
        transcript: _transcript,
        fields: const [],
        asrDurationMs: asrMs,
        llmDurationMs: 0,
      );
      _setState(LocalScribeState.done);
    }
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
    return sherpa.OnlineRecognizer(config);
  }

  static Float32List _int16ToFloat32(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final out = Float32List(pcm.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  Future<void> _ensureLlmEngine() async {
    if (_llmEngine != null) return;
    debugPrint('[LocalScribe] spawning LLM engine (first use)…');
    _llmEngine = await LlamaEngine.spawn(
      modelParams: ModelParams(path: llmModelPath, gpuLayers: 99),
      contextParams: const ContextParams(nCtx: 1024),
    );
    debugPrint('[LocalScribe] LLM engine ready');
  }

  // Qwen2.5 and Qwen3 are multilingual — they understand Bengali natively.
  // Only translate to English for SmolLM2 which is English-only.
  Future<String> _translateIfNeeded(String text) async {
    final needsTranslation = activeLlmId == 'smollm2-135m';
    if (!needsTranslation) return text;
    debugPrint('[LocalScribe] translating Bengali→English for SmolLM2...');
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.bengali,
        targetLanguage: TranslateLanguage.english,
      );
      final translated = await translator.translateText(text);
      await translator.close();
      debugPrint('[LocalScribe] translated: $translated');
      return translated;
    } catch (e) {
      debugPrint('[LocalScribe] translation error: $e — using original');
      return text;
    }
  }

  Future<List<AIExtractedField>> _extractFields(
    String transcript,
    List<FormFieldSchema> schema,
  ) async {
    debugPrint('[LocalScribe] _extractFields: transcript=${transcript.length}chars schema=${schema.length}fields activeLlm=$activeLlmId');
    if (transcript.isEmpty || schema.isEmpty) return [];

    await _ensureLlmEngine();
    final engine = _llmEngine!;

    final processedTranscript = await _translateIfNeeded(transcript);


    final isTriage = schema.every((f) => f.type == FieldType.boolean);
    final chat = await engine.createChat();

    final buffer = StringBuffer();

    if (isTriage) {
      // Triage: list only the symptom codes that are EXPLICITLY mentioned.
      // Sparse output (~10 tokens) vs full JSON (~460 tokens) — 20-40x faster.
      final codeList = schema.map((f) => f.fieldId).join(', ');
      chat.addSystem(
        'You are a clinical symptom detector. '
        'The transcript may be in Bengali (বাংলা), Hindi, English, or a mix. '
        'Understand it semantically regardless of language or spelling errors from speech recognition. '
        'Output ONLY a JSON array of matching symptom codes from the valid list. '
        'Output [] if nothing relevant is mentioned. Be CONSERVATIVE — only include clear symptom mentions.',
      );
      chat.addUser(
        'Transcript: "$processedTranscript"\n\n'
        'Valid codes: $codeList\n\n'
        'Examples: "জ্বর"→fever, "মাথা ব্যথা"→headache, "ছাতি/বুকে ব্যথা"→chest_pain, '
        '"পেটে ব্যথা"→abdominal_pain, "বমি"→vomiting, "শ্বাসকষ্ট"→breathlessness',
      );
      await for (final event in chat.generate(
        sampler: SamplerParams(temperature: 0.1, topP: 0.9),
        maxTokens: 512,
      )) {
        if (event is TokenEvent) buffer.write(event.text);
        if (event is DoneEvent) break;
      }
      await chat.dispose();
      final raw = _stripThinking(buffer.toString().trim());
      debugPrint('[LocalScribe] LLM triage raw: $raw');
      final llmFields = _parseTriageList(raw, schema);
      final kwFields = _keywordTriage(transcript, schema);
      // Merge: union of LLM + keyword hits. Keywords compensate for LLM misses on garbled ASR.
      final seen = <String>{};
      final merged = <AIExtractedField>[];
      for (final f in [...llmFields, ...kwFields]) {
        if (seen.add(f.fieldId)) merged.add(f);
      }
      debugPrint('[LocalScribe] triage merged: ${merged.length} fields (llm=${llmFields.length} kw=${kwFields.length})');
      return merged;
    } else {
      final fieldLines = schema.map((f) =>
        '  "${f.fieldId}" (${f.label}): free text or null',
      ).join('\n');
      chat.addSystem(
        'You extract clinical field values from a speech transcript. '
        'Be CONSERVATIVE — only extract values EXPLICITLY mentioned. '
        'Output ONLY a JSON object. Set each key to the extracted value string '
        'or null if not mentioned.',
      );
      chat.addUser('Transcript: "$processedTranscript"\n\nFields:\n$fieldLines');
      if (activeLlmId.startsWith('qwen3')) {
        chat.addAssistant('<think>\n\n</think>\n');
      }
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
      final raw = _stripThinking(buffer.toString().trim());
      debugPrint('[LocalScribe] LLM raw: $raw');
      return _parseFields(raw);
    }
  }

  String _stripThinking(String raw) =>
      raw.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();

  List<AIExtractedField> _parseTriageList(
    String raw,
    List<FormFieldSchema> schema,
  ) {
    final now = DateTime.now();
    final validCodes = {for (final f in schema) f.fieldId};
    // Handle both ["fever","headache"] and [fever, headache] output formats.
    final stripped = raw.replaceAll(RegExp(r'[\[\]"]'), '');
    final codes = stripped
        .split(',')
        .map((s) => s.trim())
        .where(validCodes.contains)
        .toSet();
    debugPrint('[LocalScribe] triage parsed codes: $codes');
    return codes.map((code) => AIExtractedField(
      fieldId: code,
      value: 'yes',
      confidence: 0.85,
      source: FieldSource.aiPending,
      extractedAt: now,
    )).toList();
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
    _liveExtractDebounce?.cancel();
    _liveExtractDebounce = null;
    _liveFields = [];
    _state = LocalScribeState.idle;
    _transcript = '';
    _accumulatedSegments = '';
    _result = null;
    _errorMessage = null;
    _elapsedSeconds = 0;
    _pcmBuffer.clear();
    _onlineStream?.free();
    _onlineStream = null;
    notifyListeners();
  }

  void _setState(LocalScribeState s) {
    if (_isDisposed) return;
    _state = s;
    notifyListeners();
  }

  void _setError(String msg) {
    if (_isDisposed) return;
    _errorMessage = msg;
    _state = LocalScribeState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _elapsedTimer?.cancel();
    _livePreviewTimer?.cancel();
    _liveExtractDebounce?.cancel();
    _audioSub?.cancel();
    _recorder.dispose();
    _onlineStream?.free();
    _recognizer?.free();
    _llmEngine?.dispose();
    super.dispose();
  }
}
