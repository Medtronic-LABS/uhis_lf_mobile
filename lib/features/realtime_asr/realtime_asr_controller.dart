import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api/realtime_asr_service.dart';
import '../../core/constants/app_strings.dart';
import '../scribe/form_field_schema_builder.dart';
import '../scribe/models/ai_extracted_field.dart';
import '../scribe/scribe_permission_service.dart';
import 'models/realtime_clinical_fields.dart';
import 'realtime_asr_channel_io.dart'
    if (dart.library.html) 'realtime_asr_channel_web.dart';
import 'vad_gate.dart';

enum RealtimeAsrState { idle, connecting, listening, stopping, error }

/// Drives one live-listening session against `/scribe/realtime/transcribe`:
/// mic -> WAV chunks -> WebSocket -> live transcript, plus on-demand
/// clinical-field extraction against the transcript accumulated so far.
///
/// Mirrors the wire protocol implemented by the ai-scribe-service demo at
/// `/realtime/` (app/services/realtime_bridge.py): client sends
/// audio/flush/extract/stop; server sends transcript/symptoms/error.
class RealtimeAsrController extends ChangeNotifier {
  RealtimeAsrController({
    required RealtimeAsrService service,
    required ScribePermissionService permissionService,
  })  : _service = service,
        _perm = permissionService;

  final RealtimeAsrService _service;
  final ScribePermissionService _perm;
  final AudioRecorder _recorder = AudioRecorder();

  static const Duration _autoExtractInterval = Duration(seconds: 4);
  static const Duration _finalExtractionTimeout = Duration(seconds: 15);
  // Safety net so one dropped/slow "symptoms"/"error" reply can't
  // permanently block every future extractNow() call via the _extracting
  // guard (that guard has no other reset path outside of stop()'s own
  // bounded wait) — this was a real bug: a single lost reply made the
  // periodic auto-extract silently no-op for the rest of the session.
  static const Duration _extractionSafetyTimeout = Duration(seconds: 20);

  int _chunkCount = 0;
  int _chunkBytes = 0;
  // Rolling window used to detect a "stuck" mic signal — real audio (even
  // silence) always has some sample-to-sample variation from noise floor;
  // a value that's bit-for-bit identical across many consecutive chunks
  // means the app isn't receiving real signal at all (seen in practice as
  // a constant 32768 peak — the emulator's virtual audio session dropping
  // out), not the WS/Sarvam/extraction pipeline, which was independently
  // validated working.
  static const int _stuckWindowSize = 40;
  final List<int> _recentAmplitudes = [];

  // Gates silence/noise out of the audio sent to the server — saves mobile
  // bandwidth and server ASR/LLM cost on the low-connectivity, low-end
  // devices this app targets. See VadGate's own doc comment for the
  // algorithm and tuning rationale.
  VadGate _vadGate = VadGate();

  // Set whenever a chunk was gated out (VadGate returned nothing to send)
  // since the last auto-extract tick — tells that tick to also send a
  // {"type":"ping"} keepalive, since a long silence now means genuinely no
  // audio traffic flows, which previously never happened on this connection.
  bool _silentSinceLastTick = false;

  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _autoExtractTimer;
  Completer<void>? _extractionCompleter;

  BuildContext? _context;
  void bindContext(BuildContext ctx) => _context = ctx;

  RealtimeAsrState _state = RealtimeAsrState.idle;
  RealtimeAsrState get state => _state;

  final List<String> _segments = [];
  List<String> get segments => List.unmodifiable(_segments);
  String get fullTranscript => _segments.join(' ').trim();

  RealtimeClinicalFields? _fields;
  RealtimeClinicalFields? get fields => _fields;

  /// Result from `form_fill` extraction — populated when [setFormSchema] has
  /// been called before starting the session (Step 2 form mode).
  FormPrefillResult? _formFill;
  FormPrefillResult? get formFill => _formFill;

  /// Active form schema sent with every extract frame.
  ///
  /// Set by [setFormSchema] before [start]; cleared by [stop] / [_teardown].
  /// When non-null the extract frame includes `mode: "form_fill"` and the
  /// server replies with `{"type": "form_fill", ...}` instead of `"symptoms"`.
  List<FormFieldSchema>? _formSchema;

  bool _extracting = false;
  bool get isExtracting => _extracting;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Non-fatal — session stays connected/listening, this is purely informational
  // so the UI can tell the user "the mic isn't picking up real audio" instead
  // of silently showing "Listening…" forever with no transcript ever arriving.
  String? _micWarning;
  String? get micWarning => _micWarning;

  String? _lastExtractedTranscript;

  bool get isActive =>
      _state == RealtimeAsrState.connecting ||
      _state == RealtimeAsrState.listening ||
      _state == RealtimeAsrState.stopping;

  /// Attach a form field schema so that subsequent [extractNow] calls send
  /// `mode: "form_fill"` and populate [formFill] instead of [fields].
  ///
  /// Call before [start]. Pass `null` to revert to generic symptom extraction.
  void setFormSchema(List<FormFieldSchema>? schema) {
    _formSchema = schema;
  }

  /// [assessmentType] routes server-side extraction to the programme-specific
  /// prompt (ncd/anc/…) so replies arrive as `"form_fill"` — pass null for
  /// generic symptom extraction (Step 1 behaviour).
  Future<void> start({String language = 'bn-IN', String? assessmentType}) async {
    if (isActive) return;

    if (!realtimeAsrSupported) {
      _setError(RealtimeAsrStrings.notSupportedOnWeb);
      return;
    }

    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;

    // Flip to "connecting" and reset session state up-front so the banner
    // reacts the instant the button is tapped — the permission prompt and
    // network handshake below can otherwise take a noticeable moment with no
    // visible feedback.
    _segments.clear();
    _fields = null;
    _formFill = null;
    _errorMessage = null;
    _micWarning = null;
    _lastExtractedTranscript = null;
    _chunkCount = 0;
    _chunkBytes = 0;
    _recentAmplitudes.clear();
    _vadGate = VadGate();
    _silentSinceLastTick = false;
    _state = RealtimeAsrState.connecting;
    notifyListeners();

    final granted = await _perm.ensureMicPermission(ctx);
    if (!granted) {
      _setError(RealtimeAsrStrings.micPermissionDenied);
      return;
    }

    try {
      final info = await _service.connectionInfo(
        language: language,
        assessmentType: assessmentType,
      );
      debugPrint('[RealtimeASR] connecting to ${info.uri} headers=${info.headers.keys}');
      _channel = connectRealtimeChannel(info.uri, info.headers);
      _wsSub = _channel!.stream.listen(
        _onMessage,
        onDone: _onSocketDone,
        onError: (Object e) {
          debugPrint('[RealtimeASR] websocket error: $e');
          _setError('Connection error: $e');
          // A socket error leaves the mic stream and auto-extract timer
          // running against a dead channel unless torn down here too — same
          // leak as an unexpected close (see _onSocketDone).
          unawaited(_teardown());
        },
      );

      final hasPerm = await _recorder.hasPermission();
      debugPrint('[RealtimeASR] recorder.hasPermission()=$hasPerm');

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          // defaultSource routes through Android's AGC/NS/AEC processing
          // chain, which has been observed to return constantly-saturated
          // garbage (every sample pinned at the Int16 minimum) on some
          // emulator audio HALs. Raw mic source skips that chain.
          androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
        ),
      );
      _audioSub = stream.listen(_onAudioChunk);
      debugPrint('[RealtimeASR] mic stream started');

      _state = RealtimeAsrState.listening;
      notifyListeners();

      _autoExtractTimer = Timer.periodic(_autoExtractInterval, (_) {
        // A gap in "audio" frames is new behaviour now that VadGate withholds
        // silence — send a lightweight keepalive so a long quiet stretch in
        // the visit can't be mistaken by any idle-connection timeout
        // (server or proxy) for a dead client.
        if (_silentSinceLastTick) {
          _send({'type': 'ping'});
        }
        _silentSinceLastTick = true;
        extractNow();
      });
    } catch (e, st) {
      debugPrint('[RealtimeASR] start() failed: $e\n$st');
      _setError('Could not start real-time ASR: $e');
      await _teardown();
    }
  }

  /// Stops recording, runs one last extraction over the complete transcript,
  /// and waits for its reply (bounded by [_finalExtractionTimeout]) before
  /// closing — sending "stop" immediately after "extract" would let the
  /// server's receive loop hit "stop" first and cancel the in-flight
  /// extraction task before the LLM call finishes.
  Future<void> stop() async {
    if (_state == RealtimeAsrState.idle ||
        _state == RealtimeAsrState.stopping) {
      return;
    }
    // Surface "stopping" immediately — the flush + final-extraction wait below
    // can take several seconds, during which the banner would otherwise look
    // unchanged and the Stop tap would appear to do nothing.
    _state = RealtimeAsrState.stopping;
    notifyListeners();

    _autoExtractTimer?.cancel();
    _autoExtractTimer = null;

    _send({'type': 'flush'});
    await Future.delayed(const Duration(milliseconds: 500));

    extractNow();
    final completer = _extractionCompleter;
    if (completer != null) {
      await completer.future.timeout(
        _finalExtractionTimeout,
        onTimeout: () {},
      );
    }

    _send({'type': 'stop'});
    await _teardown();
    _state = RealtimeAsrState.idle;
    notifyListeners();
  }

  void extractNow() {
    final transcript = fullTranscript;
    if (transcript.isEmpty) {
      debugPrint('[RealtimeASR] extractNow(): skipped, transcript empty (no segments received yet)');
      return;
    }
    if (transcript == _lastExtractedTranscript) {
      debugPrint('[RealtimeASR] extractNow(): skipped, transcript unchanged since last extract');
      return;
    }
    if (_extracting) {
      debugPrint('[RealtimeASR] extractNow(): skipped, extraction already in flight');
      return;
    }

    _extracting = true;
    _lastExtractedTranscript = transcript;
    final completer = Completer<void>();
    _extractionCompleter = completer;
    notifyListeners();
    debugPrint('[RealtimeASR] extract requested (${transcript.length} chars): "$transcript"');

    final schema = _formSchema;
    if (schema != null && schema.isNotEmpty) {
      _send({
        'type': 'extract',
        'transcript': transcript,
        'mode': 'form_fill',
        'formSchema': {'fields': schema.map((f) => f.toJson()).toList()},
      });
    } else {
      _send({'type': 'extract', 'transcript': transcript});
    }

    Future.delayed(_extractionSafetyTimeout, () {
      if (identical(_extractionCompleter, completer) && _extracting) {
        debugPrint('[RealtimeASR] extractNow(): no reply within ${_extractionSafetyTimeout.inSeconds}s — resetting so future attempts are not blocked');
        _extracting = false;
        _extractionCompleter = null;
        notifyListeners();
      }
    });
  }

  void _onAudioChunk(Uint8List pcm) {
    _chunkCount++;
    _chunkBytes += pcm.length;

    final amp = _peakAmplitude(pcm);
    if (_chunkCount == 1 || _chunkCount % 20 == 0) {
      // Peak amplitude out of a possible 32767 (Int16 max). If this stays
      // near 0 while you're speaking, or is pinned at exactly the same
      // value chunk after chunk, the app isn't receiving real mic signal —
      // an emulator/host audio routing issue, not a code bug in the
      // WS/Sarvam pipeline (independently validated working this session).
      debugPrint(
        '[RealtimeASR] mic chunk #$_chunkCount (${pcm.length} bytes, '
        '${_chunkBytes ~/ 1024}KB total, peak amplitude=$amp/32767)',
      );
    }
    // Must run on every raw chunk, unconditionally, before VAD gating below —
    // this diagnostic exists to catch a mic stuck on a constant (including
    // constant-silent) value; gating first would let VadGate classify a
    // stuck-silent mic as ordinary silence, starving this detector of the
    // samples it needs to ever fire.
    _trackStuckAmplitude(amp);

    final toSend = _vadGate.process(pcm);
    if (toSend.isEmpty) return;
    _silentSinceLastTick = false;
    for (final chunk in toSend) {
      final wav = _wrapPcm16Wav(chunk, sampleRate: 16000);
      _send({
        'type': 'audio',
        'data': base64Encode(wav),
        'encoding': 'audio/wav',
        'sample_rate': 16000,
      });
    }
  }

  void _trackStuckAmplitude(int amp) {
    if (_micWarning != null) return; // already flagged this session
    _recentAmplitudes.add(amp);
    if (_recentAmplitudes.length > _stuckWindowSize) {
      _recentAmplitudes.removeAt(0);
    }
    if (_recentAmplitudes.length < _stuckWindowSize) return;
    if (_recentAmplitudes.toSet().length == 1) {
      final stuckValue = _recentAmplitudes.first;
      debugPrint(
        '[RealtimeASR] WARNING: peak amplitude has been exactly $stuckValue '
        'for $_stuckWindowSize consecutive chunks — this is not real mic '
        'signal (even silence has some sample-to-sample variation). The '
        'device/emulator mic is not delivering real audio to the app.',
      );
      _micWarning = stuckValue == 0
          ? 'No mic signal detected — check the device microphone.'
          : 'Mic signal looks stuck/invalid — check the device microphone '
              '(on an emulator, try a cold restart with host audio input enabled, '
              'or test on a physical device).';
      notifyListeners();
    }
  }

  /// Max absolute sample value in a raw PCM16LE buffer — a quick, cheap way
  /// to tell real mic signal apart from silence without needing the server.
  static int _peakAmplitude(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    var peak = 0;
    for (var i = 0; i + 1 < pcm.length; i += 2) {
      final sample = data.getInt16(i, Endian.little).abs();
      if (sample > peak) peak = sample;
    }
    return peak;
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[RealtimeASR] recv: unparseable message: $raw ($e)');
      return;
    }

    switch (msg['type']) {
      case 'symptoms':
        debugPrint('[RealtimeASR] recv symptoms: ${msg['data']}');
        _extracting = false;
        final symptomsData =
            (msg['data'] as Map<String, dynamic>?) ?? const {};
        _fields = RealtimeClinicalFields.fromJson(symptomsData);
        // Confirmed live: a deployed ai-service with an assessmentType set
        // returns "form_fill" (handled below), so this branch is a legacy
        // fallback for older-deployed backends that still only speak
        // "symptoms". When Step 2 form-fill mode is active (schema set),
        // convert the symptoms response into a FormPrefillResult so the
        // banner can still pre-fill the form fields.
        if (_formSchema != null && _formSchema!.isNotEmpty) {
          _formFill = _symptomsToFormFill(_fields!);
        }
        _extractionCompleter?.complete();
        _extractionCompleter = null;
        notifyListeners();
      case 'form_fill':
        debugPrint('[RealtimeASR] recv form_fill: ${msg['data']}');
        _extracting = false;
        final data = (msg['data'] as Map<String, dynamic>?) ?? const {};
        _formFill = FormPrefillResult.fromJson(data);
        _extractionCompleter?.complete();
        _extractionCompleter = null;
        notifyListeners();
      case 'error':
        debugPrint('[RealtimeASR] recv error: ${msg['message']}');
        _extracting = false;
        _errorMessage = msg['message'] as String?;
        _extractionCompleter?.complete();
        _extractionCompleter = null;
        notifyListeners();
      default:
        final data = msg['data'] as Map<String, dynamic>?;
        final transcript = data?['transcript'] as String?;
        if (transcript != null && transcript.trim().isNotEmpty) {
          debugPrint('[RealtimeASR] recv transcript segment: "${transcript.trim()}"');
          _segments.add(transcript.trim());
          notifyListeners();
        } else {
          debugPrint('[RealtimeASR] recv (type=${msg['type']}, no transcript): $msg');
        }
    }
  }

  /// Converts a [RealtimeClinicalFields] (returned by the server as
  /// `"type":"symptoms"`) into a [FormPrefillResult] that Step 2 can apply
  /// directly to form fields — legacy fallback for an older-deployed
  /// backend that hasn't rolled out `form_fill` mode yet and always
  /// returns the standard symptoms response instead.
  ///
  /// Structured fields (from the server's typed response):
  ///   - `bpLogDetails` → `[{systolic, diastolic}]` list
  ///   - `glucose`      → numeric value (mmol/L)
  ///   - `ncdSymptoms`  → List<String> from chiefComplaints
  ///
  /// Parsed from `clinicalNotes` (server English summary, generic prompt path):
  ///   ANC: `weight` · `hemoglobin` · `fundalHeight` · `fetalMovement` ·
  ///        `urinarySugar` · `urineProtein` · `urinaryAlbumin` ·
  ///        `urinaryBilirubin` · `folicAcidProvided` · `folicAcidTotalConsumed` ·
  ///        `ifaProvided` · `ifaTotalConsumed` · `calciumProvided` ·
  ///        `calciumTotalConsumed` · `ancDangerSigns` (none-only safe path)
  ///   NCD/shared: `weight` · `height` · `pulse` · `glucoseType` (qualifier-dependent)
  FormPrefillResult _symptomsToFormFill(RealtimeClinicalFields f) {
    final extracted = <AIExtractedField>[];
    final unmapped = <String>[];
    final now = DateTime.now();

    // Blood pressure: "170/80" → bpLogDetails list [{systolic, diastolic}]
    // The form's _BpReadingField reads data.getValue('bpLogDetails') as a
    // List<Map<String,dynamic>> — injecting a flat systolic key would be ignored.
    final bp = f.bloodPressure;
    if (bp != null && bp.isNotEmpty) {
      final parts = bp.split('/');
      if (parts.length == 2) {
        final sys = int.tryParse(parts[0].trim());
        final dia = int.tryParse(parts[1].trim());
        if (sys != null || dia != null) {
          extracted.add(AIExtractedField(
            fieldId: 'bpLogDetails',
            value: [
              <String, dynamic>{
                if (sys != null) 'systolic': sys,
                if (dia != null) 'diastolic': dia,
              }
            ],
            confidence: 0.9,
            source: FieldSource.aiPending,
            sourceSegment: bp,
            extractedAt: now,
          ));
        }
      } else {
        unmapped.add('BP: $bp');
      }
    }

    // Blood glucose: numeric string e.g. "7.3" → glucose (numeric field)
    final glucose = f.bloodGlucose;
    if (glucose != null && glucose.isNotEmpty) {
      final v = double.tryParse(
          glucose.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (v != null) {
        extracted.add(AIExtractedField(
          fieldId: 'glucose',
          value: v,
          confidence: 0.85,
          source: FieldSource.aiPending,
          sourceSegment: glucose,
          extractedAt: now,
        ));
      } else {
        unmapped.add('Glucose: $glucose');
      }
    }

    // Chief complaints → ncdSymptoms (dialogCheckbox — List<String>)
    if (f.chiefComplaints.isNotEmpty) {
      extracted.add(AIExtractedField(
        fieldId: 'ncdSymptoms',
        value: f.chiefComplaints,
        confidence: 0.75,
        source: FieldSource.aiPending,
        sourceSegment: f.chiefComplaints.join(', '),
        extractedAt: now,
      ));
    }

    // ANC/NCD vitals from the English `clinicalNotes` summary written by the
    // generic symptoms prompt. The server consistently formats these in English
    // regardless of transcript language; regex parsing here bridges the gap
    // until the server-side assessment-type extraction is deployed.
    //
    // `placed` tracks fieldIds already added above — prevents duplicates when
    // the server also populates bloodPressure/bloodGlucose structured fields.
    final notes = f.clinicalNotes;
    if (notes != null && notes.isNotEmpty) {
      final placed = {for (final e in extracted) e.fieldId};

      // Helper: extract a numeric vital via [re]; skip if already placed or out of range.
      void addNum(String id, RegExp re, double lo, double hi) {
        if (placed.contains(id)) return;
        final m = re.firstMatch(notes);
        if (m == null) return;
        final v = double.tryParse(m.group(1)!);
        if (v == null || v < lo || v > hi) return;
        extracted.add(AIExtractedField(
          fieldId: id,
          value: v,
          confidence: 0.8,
          source: FieldSource.aiPending,
          sourceSegment: m.group(0)!,
          extractedAt: now,
        ));
        placed.add(id);
      }

      // Weight (kg) — ANC + NCD
      addNum('weight', RegExp(r'weight\s+(\d+(?:\.\d+)?)\s*kg', caseSensitive: false), 20, 200);

      // Hemoglobin (g/dL; server writes "%" in summary but value is correct) — ANC
      addNum('hemoglobin', RegExp(r'hemoglobin\s+(\d+(?:\.\d+)?)(?:%|g/dl)?', caseSensitive: false), 1, 25);

      // Fundal height (cm) — must be extracted BEFORE generic height to claim priority
      addNum('fundalHeight', RegExp(r'fundal\s+height\s+(\d+(?:\.\d+)?)\s*cm', caseSensitive: false), 5, 45);

      // Pulse (/min) — NCD + ANC
      addNum('pulse', RegExp(r'pulse\s+(\d+)', caseSensitive: false), 20, 250);

      // Standalone height (cm) — NCD; skip if the matched "height" is preceded by "fundal"
      if (!placed.contains('height')) {
        final hm = RegExp(r'height\s+(\d+(?:\.\d+)?)\s*cm', caseSensitive: false).firstMatch(notes);
        if (hm != null) {
          final before = notes.substring(0, hm.start).trimRight().toLowerCase();
          if (!before.endsWith('fundal')) {
            final v = double.tryParse(hm.group(1)!);
            if (v != null && v >= 50 && v <= 250) {
              extracted.add(AIExtractedField(
                fieldId: 'height',
                value: v,
                confidence: 0.8,
                source: FieldSource.aiPending,
                sourceSegment: hm.group(0)!,
                extractedAt: now,
              ));
            }
          }
        }
      }

      // Fetal movement (ANC) — enum: normal / lessThanUsual / notFelt
      if (!placed.contains('fetalMovement')) {
        final fm = RegExp(
          r'fetal\s+movement\s+(normal|not\s+felt|less(?:\s+than\s+usual)?|reduced)',
          caseSensitive: false,
        ).firstMatch(notes);
        if (fm != null) {
          final raw = fm.group(1)!.trim().toLowerCase();
          final val = raw.startsWith('normal')
              ? 'normal'
              : (raw.contains('not') || raw.contains('felt'))
                  ? 'notFelt'
                  : 'lessThanUsual';
          extracted.add(AIExtractedField(
            fieldId: 'fetalMovement',
            value: val,
            confidence: 0.8,
            source: FieldSource.aiPending,
            sourceSegment: fm.group(0)!,
            extractedAt: now,
          ));
        }
      }

      // Urinary sugar (ANC) — enum: Absent / Present
      if (!placed.contains('urinarySugar')) {
        final us = RegExp(r'urinary\s+sugar\s+(absent|present)', caseSensitive: false).firstMatch(notes);
        if (us != null) {
          extracted.add(AIExtractedField(
            fieldId: 'urinarySugar',
            value: us.group(1)!.toLowerCase() == 'absent' ? 'Absent' : 'Present',
            confidence: 0.8,
            source: FieldSource.aiPending,
            sourceSegment: us.group(0)!,
            extractedAt: now,
          ));
        }
      }

      // Urine protein (ANC) — enum: Absent / Present
      if (!placed.contains('urineProtein')) {
        final up = RegExp(r'urine\s+protein\s+(absent|present)', caseSensitive: false).firstMatch(notes);
        if (up != null) {
          extracted.add(AIExtractedField(
            fieldId: 'urineProtein',
            value: up.group(1)!.toLowerCase() == 'absent' ? 'Absent' : 'Present',
            confidence: 0.8,
            source: FieldSource.aiPending,
            sourceSegment: up.group(0)!,
            extractedAt: now,
          ));
        }
      }

      // Glucose type (NCD) — only fires when server includes qualifier in notes
      // (current deployed server omits this; will auto-activate post-redeploy).
      if (!placed.contains('glucoseType')) {
        final lower = notes.toLowerCase();
        String? gType;
        if (lower.contains('fasting') &&
            (lower.contains('glucose') || lower.contains('blood sugar'))) {
          gType = 'fbs';
        } else if ((lower.contains('post') &&
                (lower.contains('prandial') || lower.contains('meal'))) ||
            lower.contains('ppbs')) {
          gType = 'ppbs';
        } else if ((lower.contains('random') &&
                (lower.contains('glucose') || lower.contains('blood sugar'))) ||
            RegExp(r'\brbs\b').hasMatch(lower)) {
          gType = 'rbs';
        }
        if (gType != null) {
          extracted.add(AIExtractedField(
            fieldId: 'glucoseType',
            value: gType,
            confidence: 0.75,
            source: FieldSource.aiPending,
            sourceSegment: gType == 'fbs'
                ? 'fasting glucose'
                : gType == 'ppbs'
                    ? 'post-prandial glucose'
                    : 'random glucose',
            extractedAt: now,
          ));
        }
      }

      // Supplement tablet counts (ANC):
      //   "received N X" → Provided (given this visit)
      //   "took N X"     → TotalConsumed (patient-reported cumulative)
      void addCount(String fieldId, RegExp re) {
        if (placed.contains(fieldId)) return;
        final m = re.firstMatch(notes);
        if (m == null) return;
        final v = int.tryParse(m.group(1)!);
        if (v == null || v < 0 || v > 200) return;
        extracted.add(AIExtractedField(
          fieldId: fieldId,
          value: v.toDouble(),
          confidence: 0.75,
          source: FieldSource.aiPending,
          sourceSegment: m.group(0)!,
          extractedAt: now,
        ));
        placed.add(fieldId);
      }

      addCount('folicAcidProvided',
          RegExp(r'(?:received|given)\s+(\d+)\s+folic', caseSensitive: false));
      addCount('folicAcidTotalConsumed',
          RegExp(r'took\s+(\d+)\s+folic', caseSensitive: false));
      addCount('ifaProvided',
          RegExp(r'(?:received|given)\s+(\d+)\s+(?:IFA|ifa)', caseSensitive: false));
      addCount('ifaTotalConsumed',
          RegExp(r'took\s+(\d+)\s+(?:IFA|ifa)', caseSensitive: false));
      addCount('calciumProvided',
          RegExp(r'(?:received|given)\s+(\d+)\s+calcium', caseSensitive: false));
      addCount('calciumTotalConsumed',
          RegExp(r'took\s+(\d+)\s+calcium', caseSensitive: false));

      // Urinary albumin (ANC) — enum: Absent / Present
      if (!placed.contains('urinaryAlbumin')) {
        final ua = RegExp(r'(?:urine\s+|urinary\s+)?albumin\s+(absent|present)',
                caseSensitive: false)
            .firstMatch(notes);
        if (ua != null) {
          extracted.add(AIExtractedField(
            fieldId: 'urinaryAlbumin',
            value: ua.group(1)!.toLowerCase() == 'absent' ? 'Absent' : 'Present',
            confidence: 0.8,
            source: FieldSource.aiPending,
            sourceSegment: ua.group(0)!,
            extractedAt: now,
          ));
        }
      }

      // Urinary bilirubin (ANC) — enum: Absent / Present
      if (!placed.contains('urinaryBilirubin')) {
        final ub =
            RegExp(r'bilirubin\s+(absent|present)', caseSensitive: false)
                .firstMatch(notes);
        if (ub != null) {
          extracted.add(AIExtractedField(
            fieldId: 'urinaryBilirubin',
            value: ub.group(1)!.toLowerCase() == 'absent' ? 'Absent' : 'Present',
            confidence: 0.8,
            source: FieldSource.aiPending,
            sourceSegment: ub.group(0)!,
            extractedAt: now,
          ));
        }
      }

      // ANC danger signs — only safe case: explicit "no danger signs" → None
      if (!placed.contains('ancDangerSigns')) {
        final nd = RegExp(r'no\s+(?:anc\s+)?danger\s+signs?', caseSensitive: false)
            .firstMatch(notes);
        if (nd != null) {
          extracted.add(AIExtractedField(
            fieldId: 'ancDangerSigns',
            value: ['None of these'],
            confidence: 0.75,
            source: FieldSource.aiPending,
            sourceSegment: nd.group(0)!,
            extractedAt: now,
          ));
        }
      }

      // Keep notes visible in the banner unmapped list.
      unmapped.add(notes);
    }

    // Surface remaining fields as unmapped so the banner shows them.
    if (f.diagnosis != null) unmapped.add('Diagnosis: ${f.diagnosis}');
    if (f.comorbidities.isNotEmpty) {
      unmapped.add('Comorbidities: ${f.comorbidities.join(', ')}');
    }

    debugPrint(
      '[RealtimeASR] _symptomsToFormFill: ${extracted.length} field(s) → '
      '${extracted.map((e) => '${e.fieldId}=${e.value}').join(', ')}',
    );

    return FormPrefillResult(
      fields: extracted,
      unmappedFindings: unmapped,
      transcriptText: fullTranscript,
    );
  }

  void _onSocketDone() {
    debugPrint('[RealtimeASR] websocket closed (state was $_state)');
    if (_state == RealtimeAsrState.listening || _state == RealtimeAsrState.connecting) {
      // An unexpected close (network blip, server restart) must stop the mic
      // and auto-extract timer here, not just flip the reported state —
      // otherwise both keep running against a dead channel while the banner
      // shows idle and looks tappable again.
      unawaited(_teardown());
      _state = RealtimeAsrState.idle;
      notifyListeners();
    }
  }

  void _send(Map<String, dynamic> msg) {
    if (_channel == null) {
      debugPrint('[RealtimeASR] _send(${msg['type']}): no channel — dropped');
      return;
    }
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('[RealtimeASR] _send(${msg['type']}) failed: $e');
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    _state = RealtimeAsrState.error;
    notifyListeners();
  }

  Future<void> _teardown() async {
    _autoExtractTimer?.cancel();
    _autoExtractTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  /// Wraps raw PCM16LE mono bytes (as emitted by `record`'s pcm16bits
  /// stream) in a minimal 44-byte WAV header — same shape the browser demo
  /// sends, which Sarvam's streaming API expects per chunk.
  static Uint8List _wrapPcm16Wav(Uint8List pcm, {required int sampleRate}) {
    const bitsPerSample = 16;
    const channels = 1;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    final header = ByteData(44)
      ..setUint8(0, 0x52) // 'R'
      ..setUint8(1, 0x49) // 'I'
      ..setUint8(2, 0x46) // 'F'
      ..setUint8(3, 0x46) // 'F'
      ..setUint32(4, 36 + pcm.length, Endian.little)
      ..setUint8(8, 0x57) // 'W'
      ..setUint8(9, 0x41) // 'A'
      ..setUint8(10, 0x56) // 'V'
      ..setUint8(11, 0x45) // 'E'
      ..setUint8(12, 0x66) // 'f'
      ..setUint8(13, 0x6d) // 'm'
      ..setUint8(14, 0x74) // 't'
      ..setUint8(15, 0x20) // ' '
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, channels, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, byteRate, Endian.little)
      ..setUint16(32, blockAlign, Endian.little)
      ..setUint16(34, bitsPerSample, Endian.little)
      ..setUint8(36, 0x64) // 'd'
      ..setUint8(37, 0x61) // 'a'
      ..setUint8(38, 0x74) // 't'
      ..setUint8(39, 0x61) // 'a'
      ..setUint32(40, pcm.length, Endian.little);

    final out = BytesBuilder();
    out.add(header.buffer.asUint8List());
    out.add(pcm);
    return out.toBytes();
  }

  @override
  void dispose() {
    _autoExtractTimer?.cancel();
    _audioSub?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _recorder.dispose();
    super.dispose();
  }
}
