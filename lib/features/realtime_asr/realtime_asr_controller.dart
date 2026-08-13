import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api/realtime_asr_service.dart';
import '../../core/audio/scribe_record_config.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/debug/asr_diagnostics.dart';
import '../../core/preferences/scribe_audio_settings_notifier.dart';
import '../../core/preferences/vad_tuning_notifier.dart';
import '../scribe/form_field_schema_builder.dart';
import '../scribe/models/ai_extracted_field.dart';
import '../scribe/scribe_permission_service.dart';
import 'models/realtime_clinical_fields.dart';
import 'models/realtime_symptom_codes.dart';
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
    VadTuningNotifier? vadTuning,
    ScribeAudioSettingsNotifier? audioSettings,
  })  : _service = service,
        _perm = permissionService,
        _vadTuning = vadTuning,
        _audioSettings = audioSettings;

  final RealtimeAsrService _service;

  // Nullable for the same reason as [_vadTuning] below — falls back to the
  // build-time default rather than requiring the preferences stack.
  final ScribeAudioSettingsNotifier? _audioSettings;

  /// Read at each session start, not cached, so flipping the setting
  /// applies to the next LIVE session without restarting the app.
  RecordConfig get _captureConfig => ScribeRecordConfig.realtimeStream(
        rawMicCapture: _audioSettings?.rawMicCaptureEnabled ??
            AppConfig.rawMicCaptureDefault,
      );
  // Nullable: callers that don't provide one (tests, a widget tree without
  // the provider registered) get VadGate's own built-in defaults instead of
  // a crash — same "degrade to defaults, never throw" stance as
  // VadTuningNotifier.load() itself.
  final VadTuningNotifier? _vadTuning;

  VadGate _buildVadGate() {
    final cfg = _vadTuning?.config;
    if (cfg == null) return VadGate();
    return VadGate(
      enterMarginDb: cfg.enterMarginDb,
      sustainMarginDb: cfg.sustainMarginDb,
      floorCeilingDbfs: cfg.floorCeilingDbfs,
      floorAlpha: cfg.floorAlpha,
      bootstrapDuration: Duration(milliseconds: cfg.bootstrapMs),
      debounceDuration: Duration(milliseconds: cfg.debounceMs),
      hangoverDuration: Duration(milliseconds: cfg.hangoverMs),
      preRollDuration: Duration(milliseconds: cfg.preRollMs),
    );
  }
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

  /// Set when [start] was given a `symptomVocab` — remembered for the
  /// session's lifetime so `_onMessage`'s `'symptoms'` case knows to parse
  /// the coded-symptom shape instead of the legacy free-text ClinicalFields
  /// shape (the server's response shape depends on whether this session sent
  /// a vocabulary, since the client itself decided that).
  List<String>? _symptomVocab;

  /// Result from a vocab-constrained `"symptoms"` reply — populated instead
  /// of [fields] when [start] was given a `symptomVocab`.
  RealtimeSymptomCodes? _symptomCodes;
  RealtimeSymptomCodes? get symptomCodes => _symptomCodes;

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

  // ── Diagnostics-only state ──────────────────────────────────────────────
  //
  // Everything below exists purely to answer "what happened in this session"
  // after the fact (production instrumentation for the intermittent
  // silent-failure investigation). None of it feeds back into control flow —
  // it is written but never read by any decision the controller makes.
  // Correlated by the visit's existing [encounterId], not a new session id.

  /// The visit's existing encounter id, passed in at [start] — the
  /// correlation key for every diagnostic event this controller emits.
  String? _encounterId;

  DateTime? _sessionStartedAt;

  /// True for the duration of a caller-initiated [stop] — lets
  /// [_onSocketDone] report whether a close was expected. `_teardown`'s own
  /// `_wsSub?.cancel()` normally prevents `_onSocketDone` from firing at all
  /// during a manual stop; this flag only matters for the rare race where a
  /// done event slips through anyway.
  bool _manualStopInProgress = false;

  /// Guards [_emitSessionSummaryOnce] so exactly one summary is emitted per
  /// session, however it ends.
  bool _summaryEmitted = false;

  /// Set exactly once, in [dispose]. Every method that can run after an
  /// async gap (an awaited call, a Future.delayed callback, a stream
  /// event) must check this before touching state or calling
  /// notifyListeners() — ChangeNotifier's own post-dispose guard is wrapped
  /// in `assert()`, which compiles out in release builds, so without this
  /// check a post-dispose call silently operates on a disposed instance in
  /// production and throws only in debug builds (this is exactly what
  /// crashed a live test session — see Task 1 of the remediation plan).
  bool _disposed = false;

  /// Reason passed to the most recent [_teardown] call — surfaced in the
  /// session summary as `wsCloseReason`.
  String _wsCloseReason = 'none';

  int _vadChunksReceived = 0;
  int _vadChunksPassedCount = 0;
  int _vadChunksDroppedCount = 0;
  DateTime? _lastVadPassAt;
  int _longestVadSilenceGapMs = 0;

  int _chunksSentWs = 0;
  int _audioBytesSentWs = 0;
  int _chunksDroppedNoChannel = 0;

  int _transcriptMessagesReceived = 0;
  int _transcriptSegmentsReceived = 0;
  int _transcriptCharacterCount = 0;
  DateTime? _firstTranscriptAt;
  DateTime? _lastTranscriptAt;

  /// Cumulative field count across every `form_fill` reply this session —
  /// the realtime controller's own view of §12's `fields_received_count`.
  /// Whether those fields were actually *applied* is decided several layers
  /// away in `UnifiedFormNotifier.applyAiPrefill`, which emits its own
  /// `ASR_FORM_APPLY` event correlated by the same encounter id — this
  /// controller has no visibility into that outcome and does not guess at it.
  int _formFillFieldsReceived = 0;

  int _extractRequestsSentCount = 0;
  int _extractResponsesReceivedCount = 0;
  int _extractTimeoutsCount = 0;
  bool _finalExtractRequested = false;
  bool _finalExtractResponseReceived = false;

  int _errorEventCount = 0;
  String? _lastErrorCategory;

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
  ///
  /// [symptomVocab], when [assessmentType] is null, constrains the generic
  /// "symptoms" extraction to exactly these client-supplied codes — pass the
  /// demographically-filtered vocabulary for this patient (e.g.
  /// `AiScribeTriageVocab.applicableCodes(ctx)`). The server then returns
  /// real per-code confidence instead of free-text complaints, so no
  /// client-side keyword matching is needed. Omit for the legacy free-text
  /// behaviour (only relevant while any consumer hasn't migrated yet).
  Future<void> start({
    String language = 'bn-IN',
    String? assessmentType,
    List<String>? symptomVocab,
    String? encounterId,
  }) async {
    if (isActive) return;

    // Set before any early return so even a same-session immediate failure
    // (unsupported platform, unmounted context) has a correlation id ready —
    // though those two guards intentionally emit no event at all, matching
    // their existing (silent) behavior; instrumentation starts at ASR_START.
    _encounterId = encounterId;

    if (!realtimeAsrSupported) {
      _setError(RealtimeAsrStrings.notSupportedOnWeb, category: 'unsupported_platform');
      _emitSessionSummaryOnce();
      return;
    }

    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;

    final stateBeforeReset = _state.name;

    // Flip to "connecting" and reset session state up-front so the banner
    // reacts the instant the button is tapped — the permission prompt and
    // network handshake below can otherwise take a noticeable moment with no
    // visible feedback.
    _segments.clear();
    _fields = null;
    _symptomCodes = null;
    _symptomVocab = (symptomVocab != null && symptomVocab.isNotEmpty) ? symptomVocab : null;
    _formFill = null;
    _errorMessage = null;
    _micWarning = null;
    _lastExtractedTranscript = null;
    _chunkCount = 0;
    _chunkBytes = 0;
    _recentAmplitudes.clear();
    _vadGate = _buildVadGate();
    _silentSinceLastTick = false;

    // Diagnostics-only resets — new session, fresh counters.
    _sessionStartedAt = DateTime.now();
    _manualStopInProgress = false;
    _summaryEmitted = false;
    _wsCloseReason = 'none';
    _vadChunksReceived = 0;
    _vadChunksPassedCount = 0;
    _vadChunksDroppedCount = 0;
    _lastVadPassAt = null;
    _longestVadSilenceGapMs = 0;
    _chunksSentWs = 0;
    _audioBytesSentWs = 0;
    _chunksDroppedNoChannel = 0;
    _transcriptMessagesReceived = 0;
    _transcriptSegmentsReceived = 0;
    _transcriptCharacterCount = 0;
    _firstTranscriptAt = null;
    _lastTranscriptAt = null;
    _formFillFieldsReceived = 0;
    _extractRequestsSentCount = 0;
    _extractResponsesReceivedCount = 0;
    _extractTimeoutsCount = 0;
    _finalExtractRequested = false;
    _finalExtractResponseReceived = false;
    _errorEventCount = 0;
    _lastErrorCategory = null;

    _state = RealtimeAsrState.connecting;
    _safeNotify();

    _logEvent('ASR_START', {
      'assessmentType': assessmentType,
      'currentState': stateBeforeReset,
    });

    final granted = await _perm.ensureMicPermission(ctx);
    _logEvent('ASR_MIC_PERMISSION', {'granted': granted});
    if (!granted) {
      _setError(RealtimeAsrStrings.micPermissionDenied, category: 'mic_permission_denied');
      _emitSessionSummaryOnce();
      return;
    }

    try {
      final info = await _service.connectionInfo(
        language: language,
        assessmentType: assessmentType,
        symptomVocab: _symptomVocab,
        encounterId: _encounterId,
      );
      debugPrint('[RealtimeASR] connecting to ${info.uri} headers=${info.headers.keys}');
      _logEvent('ASR_WS_CONNECT_START', const {});
      _channel = connectRealtimeChannel(info.uri, info.headers);
      // Diagnostic-only: `.ready` completes once the handshake actually
      // finishes (or errors) — logged purely for observability, never
      // awaited by the control flow below, so it cannot change timing or
      // behavior. Connection errors are still handled exclusively by the
      // existing `onError` callback; this just records that the handshake
      // *did* succeed, when it does.
      unawaited(_channel!.ready.then((_) {
        _logEvent('ASR_WS_CONNECTED', const {});
      }).catchError((Object _) {}));
      _wsSub = _channel!.stream.listen(
        _onMessage,
        onDone: _onSocketDone,
        onError: (Object e) {
          debugPrint('[RealtimeASR] websocket error: $e');
          _logEvent('ASR_WS_ERROR', {'errorType': e.runtimeType.toString()});
          // The raw exception ($e) is diagnostic-only (logged above, never
          // shown) — the SK sees a generic, localized connectivity message.
          _setError(RealtimeAsrStrings.connectionUnavailable, category: 'ws_connection_error');
          // A socket error leaves the mic stream and auto-extract timer
          // running against a dead channel unless torn down here too — same
          // leak as an unexpected close (see _onSocketDone).
          unawaited(_teardown(reason: 'ws_error'));
        },
      );

      // Register the schema once, right after connecting and before any
      // audio is captured — a backend with dynamic_form_schema_enabled on
      // can then extract using these exact fields from the very first
      // "extract" call. Sending it here is a pure optimization: extractNow()
      // below still sends the same schema inline on every extract call too
      // (unchanged), which is what makes this work against a backend that
      // doesn't understand "init_schema" yet, and what picks up a mid-visit
      // change in which fields are on screen.
      final schema = _formSchema;
      if (schema != null && schema.isNotEmpty) {
        _send({
          'type': 'init_schema',
          if (assessmentType != null) 'assessmentType': assessmentType,
          'fields': schema.map((f) => f.toJson()).toList(),
        });
      }

      final hasPerm = await _recorder.hasPermission();
      debugPrint('[RealtimeASR] recorder.hasPermission()=$hasPerm');

      final stream = await _recorder.startStream(_captureConfig);
      _audioSub = stream.listen(_onAudioChunk);
      debugPrint('[RealtimeASR] mic stream started');
      // Reference point for "how long has audio been captured with nothing
      // passing VAD" (see _onAudioChunk) — seeded here so a session where
      // VAD never once passes anything still measures a real gap, instead
      // of one that stays at zero because no prior pass ever happened.
      _lastVadPassAt = DateTime.now();
      _logEvent('ASR_RECORDER_START', {'hasPermission': hasPerm});

      // ── T6 guard: don't resurrect a dead WS channel into "listening" ──
      // Record channel availability and the current state immediately
      // before deciding whether to proceed to `listening` — captured here,
      // not after, because if the WS handshake already failed during the
      // awaits above, `_setError` (onError) or `_onSocketDone` may already
      // have moved `_state` to `error`/`idle`, and the unconditional write
      // that used to follow this check would silently overwrite that real
      // outcome. The `_state == idle` half of the check below also catches
      // the specific race where the WS close triggers `_onSocketDone`'s
      // `_teardown`, which is itself blocked on `_recorder.isRecording()`
      // behind the per-instance semaphore this in-flight `startStream()`
      // call is holding — so `_channel` hasn't been nulled yet, but `_state`
      // was already flipped to `idle`. In either case, tear down the mic
      // stream we just started and end this attempt as a failed start
      // instead of claiming `listening`.
      final channelAvailable = _channel != null;
      _logEvent('ASR_START_FINAL_STATE', {
        'channelAvailable': channelAvailable,
        'currentState': _state.name,
        'recorderStarted': true,
      });
      if (!channelAvailable ||
          _state == RealtimeAsrState.idle ||
          _state == RealtimeAsrState.error) {
        _logEvent('ASR_LISTENING_WITHOUT_WS', {'currentState': _state.name});
        await _teardown(reason: 'start_failed_no_channel');
        if (_state != RealtimeAsrState.error) {
          _setError(
            RealtimeAsrStrings.connectionUnavailable,
            category: 'ws_not_available_at_listening',
          );
        }
        _emitSessionSummaryOnce();
        return;
      }

      _state = RealtimeAsrState.listening;
      _safeNotify();
      _logEvent('ASR_LISTENING', const {});

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
      // The raw exception ($e) stays in the debug log above only — the SK
      // sees a generic, localized connectivity message, never Dart exception
      // text.
      _setError(RealtimeAsrStrings.connectionUnavailable, category: 'start_exception');
      await _teardown(reason: 'start_failed');
      _emitSessionSummaryOnce();
    }
  }

  /// Stops recording, runs one last extraction over the complete transcript,
  /// and waits for its reply (bounded by [_finalExtractionTimeout]) before
  /// closing — sending "stop" immediately after "extract" would let the
  /// server's receive loop hit "stop" first and cancel the in-flight
  /// extraction task before the LLM call finishes.
  Future<void> stop() async {
    if (_disposed) return;
    if (_state == RealtimeAsrState.idle ||
        _state == RealtimeAsrState.stopping) {
      return;
    }
    _manualStopInProgress = true;
    // Surface "stopping" immediately — the flush + final-extraction wait below
    // can take several seconds, during which the banner would otherwise look
    // unchanged and the Stop tap would appear to do nothing.
    _state = RealtimeAsrState.stopping;
    _safeNotify();

    _autoExtractTimer?.cancel();
    _autoExtractTimer = null;

    _send({'type': 'flush'});
    await Future.delayed(const Duration(milliseconds: 500));

    _finalExtractRequested = true;
    extractNow();
    final completer = _extractionCompleter;
    if (completer != null) {
      await completer.future.timeout(
        _finalExtractionTimeout,
        onTimeout: () {},
      );
    }

    _send({'type': 'stop'});
    await _teardown(reason: 'manual_stop');
    _state = RealtimeAsrState.idle;
    _safeNotify();
    _emitSessionSummaryOnce();
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
    _extractRequestsSentCount++;
    _safeNotify();
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
        _extractTimeoutsCount++;
        _extracting = false;
        _extractionCompleter = null;
        _safeNotify();
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
    _vadChunksReceived++;
    if (toSend.isEmpty) {
      _vadChunksDroppedCount++;
      if (_lastVadPassAt != null) {
        final gapMs = DateTime.now().difference(_lastVadPassAt!).inMilliseconds;
        if (gapMs > _longestVadSilenceGapMs) _longestVadSilenceGapMs = gapMs;
      }
      return;
    }
    _vadChunksPassedCount += toSend.length;
    _lastVadPassAt = DateTime.now();
    _silentSinceLastTick = false;
    for (final chunk in toSend) {
      final wav = _wrapPcm16Wav(
        chunk,
        sampleRate: ScribeRecordConfig.sampleRate,
      );
      // Recorded before _send() because a null channel means _send() drops
      // the frame silently (existing behavior, unchanged) — this is exactly
      // the condition the T6 hypothesis needs counted.
      final channelWasAvailable = _channel != null;
      _send({
        'type': 'audio',
        'data': base64Encode(wav),
        'encoding': 'audio/wav',
        'sample_rate': 16000,
      });
      if (channelWasAvailable) {
        _chunksSentWs++;
        _audioBytesSentWs += chunk.length;
      } else {
        _chunksDroppedNoChannel++;
      }
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
          ? RealtimeAsrStrings.noMicSignal
          : RealtimeAsrStrings.micSignalStuck;
      _safeNotify();
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
      // Raw message deliberately not logged here — it's server content and
      // may contain transcript/PHI even when malformed.
      _logEvent('ASR_WS_MESSAGE_PARSE_ERROR', {
        'errorType': e.runtimeType.toString(),
      });
      return;
    }

    switch (msg['type']) {
      case 'symptoms':
        debugPrint('[RealtimeASR] recv symptoms: ${msg['data']}');
        _extracting = false;
        _extractResponsesReceivedCount++;
        if (_finalExtractRequested && !_finalExtractResponseReceived) {
          _finalExtractResponseReceived = true;
        }
        final symptomsData =
            (msg['data'] as Map<String, dynamic>?) ?? const {};
        if (_symptomVocab != null) {
          // This session supplied its own vocabulary, so the server replied
          // with real codes + confidence (run_triage_inference's output
          // shape) instead of free-text chiefComplaints — see
          // ai-scribe-service's app/services/realtime_bridge.py.
          _symptomCodes = RealtimeSymptomCodes.fromJson(symptomsData);
        } else {
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
        }
        _extractionCompleter?.complete();
        _extractionCompleter = null;
        _safeNotify();
      case 'form_fill':
        debugPrint('[RealtimeASR] recv form_fill: ${msg['data']}');
        _extracting = false;
        _extractResponsesReceivedCount++;
        if (_finalExtractRequested && !_finalExtractResponseReceived) {
          _finalExtractResponseReceived = true;
        }
        final data = (msg['data'] as Map<String, dynamic>?) ?? const {};
        _formFill = FormPrefillResult.fromJson(data);
        _formFillFieldsReceived += _formFill!.fields.length;
        _extractionCompleter?.complete();
        _extractionCompleter = null;
        _safeNotify();
      case 'error':
        final rawServerErrorCode = msg['message'] as String?;
        debugPrint('[RealtimeASR] recv error: $rawServerErrorCode');
        _extracting = false;
        _extractResponsesReceivedCount++;
        if (_finalExtractRequested && !_finalExtractResponseReceived) {
          _finalExtractResponseReceived = true;
        }
        // Route through the same chokepoint every other error path uses —
        // this is what actually flips `_state` to `error` (previously it
        // never did, so the server closing the socket right after this frame
        // left `_onSocketDone` resetting to `idle` instead, and the banner's
        // error panel never rendered). The raw backend code is passed only as
        // `category` (diagnostic-only, never shown); the SK sees a localized
        // message via [_localizedServerErrorMessage].
        _setError(
          _localizedServerErrorMessage(rawServerErrorCode),
          category: rawServerErrorCode ?? 'server_error_unknown',
        );
        _extractionCompleter?.complete();
        _extractionCompleter = null;
      case 'schema_ack':
        // Reply to "init_schema" (or an inline "formSchema" on "extract") —
        // informational only, no state to update here. Logged so a schema
        // that's unexpectedly getting dropped in bulk is visible during
        // development without needing to inspect backend logs.
        debugPrint(
          '[RealtimeASR] recv schema_ack: accepted=${msg['acceptedCount']} '
          'dropped=${msg['droppedCount']} reasons=${msg['dropped']}',
        );
      default:
        // Every message that reaches here is one Sarvam forwarded through
        // the bridge, whether or not it happens to carry transcript text —
        // counted first, before inspecting content, so a session with zero
        // messages at all (never forwarded anything) is distinguishable
        // from one that received messages with no usable transcript field.
        _transcriptMessagesReceived++;
        final data = msg['data'] as Map<String, dynamic>?;
        final transcript = data?['transcript'] as String?;
        if (transcript != null && transcript.trim().isNotEmpty) {
          debugPrint('[RealtimeASR] recv transcript segment: "${transcript.trim()}"');
          _transcriptSegmentsReceived++;
          _transcriptCharacterCount += transcript.trim().length;
          _firstTranscriptAt ??= DateTime.now();
          _lastTranscriptAt = DateTime.now();
          _segments.add(transcript.trim());
          _safeNotify();
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
        unmapped.add(RealtimeAsrStrings.bloodPressurePrefix(bp));
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
        unmapped.add(RealtimeAsrStrings.glucosePrefix(glucose));
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
    if (f.diagnosis != null) unmapped.add(RealtimeAsrStrings.diagnosisPrefix(f.diagnosis!));
    if (f.comorbidities.isNotEmpty) {
      unmapped.add(RealtimeAsrStrings.comorbiditiesPrefix(f.comorbidities.join(', ')));
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
    if (_disposed) return;
    final previousState = _state;
    debugPrint('[RealtimeASR] websocket closed (state was $_state)');
    _logEvent('ASR_WS_DONE', {
      'previousState': previousState.name,
      'expected': _manualStopInProgress,
      'closeCode': _channel?.closeCode,
      'closeReason': _channel?.closeReason,
    });
    if (previousState == RealtimeAsrState.listening || previousState == RealtimeAsrState.connecting) {
      // An unexpected close (network blip, server restart) must stop the mic
      // and auto-extract timer here, not just flip the reported state —
      // otherwise both keep running against a dead channel while the banner
      // shows idle and looks tappable again.
      unawaited(_teardown(reason: 'ws_done'));
      _state = RealtimeAsrState.idle;
      _safeNotify();
      // Only safe to close out the summary here when the prior state was
      // `listening` — that state is set as the very last step of a
      // successful `start()`, so observing it guarantees `start()` has
      // already returned and cannot later overwrite this `idle` back to
      // `listening` (T6's race). If the prior state was `connecting`,
      // `start()` is still in flight and will go on to do exactly that —
      // emitting now would freeze the summary mid-race and (being
      // once-only) permanently suppress the real final summary for the
      // zombie session that follows. `stop` and `dispose` remain the
      // emission points for that case.
      if (previousState == RealtimeAsrState.listening) {
        _emitSessionSummaryOnce();
      }
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

  /// Maps a raw backend error code (the `message` field on a server
  /// `{"type":"error",...}` frame, e.g. `"audio_transcription_failed"`) to a
  /// localized, SK-facing message. The raw code itself must never reach the
  /// user — callers pass it separately as [_setError]'s diagnostic-only
  /// `category` instead.
  String _localizedServerErrorMessage(String? rawCode) {
    switch (rawCode) {
      case 'audio_transcription_failed':
        return RealtimeAsrStrings.audioTranscriptionFailed;
      default:
        return RealtimeAsrStrings.genericError;
    }
  }

  /// Single chokepoint for every client-side ASR error this controller can
  /// report. [category] is a fixed, coarse label supplied by the caller
  /// (never derived from the exception text) so error volume/type can be
  /// measured without logging the raw message.
  ///
  /// Diagnostic-only note: this does NOT emit the session summary — a
  /// session that reaches `error` here can still have that state
  /// overwritten moments later by the unconditional `_state = listening`
  /// write in [start] (the T6 race). Emitting a summary here would either
  /// fire prematurely for a session that isn't actually over, or (if guarded
  /// against re-firing) suppress the real final summary later. The summary
  /// is instead emitted only from genuinely terminal points: [stop],
  /// [_onSocketDone]'s teardown branch, [start]'s own catch block, and
  /// [dispose] as a last-resort catch-all for a session abandoned in this
  /// error state without ever being stopped.
  void _setError(String message, {String category = 'unknown'}) {
    final previousState = _state.name;
    _errorMessage = message;
    _state = RealtimeAsrState.error;
    _errorEventCount++;
    _lastErrorCategory = category;
    _logEvent('ASR_ERROR', {
      'previousState': previousState,
      'errorCategory': category,
    });
    _safeNotify();
  }

  Future<void> _teardown({String reason = 'unknown'}) async {
    _wsCloseReason = reason;
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
    if (_channel != null) {
      _logEvent('ASR_WS_CLOSED', {
        'reason': reason,
        'expected': reason == 'manual_stop',
        'closeCode': _channel?.closeCode,
        'closeReason': _channel?.closeReason,
      });
    }
    _channel = null;
  }

  /// Guarded notifyListeners() — every call site in this file goes through
  /// here instead of calling notifyListeners() directly, so a callback that
  /// resumes after [dispose] (an awaited call, a Timer, a Future.delayed)
  /// can never throw "used after being disposed".
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Convenience wrapper so every diagnostic call site doesn't repeat
  /// `encounterId: _encounterId`.
  void _logEvent(String name, Map<String, Object?> fields) {
    AsrDiagnostics.event(name, encounterId: _encounterId, fields: fields);
  }

  /// Emits exactly one `ASR_SESSION_SUMMARY` per session, however it ends.
  /// Guarded by [_summaryEmitted] — safe to call from multiple terminal
  /// paths (only the first call after [start] resets the guard does anything).
  void _emitSessionSummaryOnce() {
    if (_summaryEmitted) return;
    _summaryEmitted = true;
    final durationMs = _sessionStartedAt == null
        ? null
        : DateTime.now().difference(_sessionStartedAt!).inMilliseconds;
    final vadPassRatio = _vadChunksReceived == 0
        ? null
        : _vadChunksPassedCount / _vadChunksReceived;
    _logEvent('ASR_SESSION_SUMMARY', {
      'durationMs': durationMs,
      'rawChunksCaptured': _chunkCount,
      'audioBytesCaptured': _chunkBytes,
      'vadChunksReceived': _vadChunksReceived,
      'vadChunksPassed': _vadChunksPassedCount,
      'vadChunksDropped': _vadChunksDroppedCount,
      'vadPassRatio': vadPassRatio,
      'longestVadSilenceGapMs': _longestVadSilenceGapMs,
      'chunksSentWs': _chunksSentWs,
      'audioBytesSentWs': _audioBytesSentWs,
      'chunksDroppedNoChannel': _chunksDroppedNoChannel,
      'transcriptMessagesReceived': _transcriptMessagesReceived,
      'transcriptSegmentsReceived': _transcriptSegmentsReceived,
      'transcriptCharacterCount': _transcriptCharacterCount,
      'firstTranscriptAt': _firstTranscriptAt?.toIso8601String(),
      'lastTranscriptAt': _lastTranscriptAt?.toIso8601String(),
      'formFillFieldsReceived': _formFillFieldsReceived,
      'extractRequestsSent': _extractRequestsSentCount,
      'extractResponsesReceived': _extractResponsesReceivedCount,
      'extractTimeouts': _extractTimeoutsCount,
      'finalExtractRequested': _finalExtractRequested,
      'finalExtractResponseReceived': _finalExtractResponseReceived,
      'errorEventCount': _errorEventCount,
      'lastErrorCategory': _lastErrorCategory,
      'finalState': _state.name,
      'wsCloseReason': _wsCloseReason,
    });
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
    _disposed = true;
    _autoExtractTimer?.cancel();
    _audioSub?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _recorder.dispose();
    // Last-resort catch-all: a session abandoned in `error` state (T6's
    // race, or any `_setError` path) never reaches `stop()` or
    // `_onSocketDone`'s teardown branch — this guarantees its summary still
    // gets emitted once, whenever the controller itself is finally disposed.
    _emitSessionSummaryOnce();
    super.dispose();
  }
}
