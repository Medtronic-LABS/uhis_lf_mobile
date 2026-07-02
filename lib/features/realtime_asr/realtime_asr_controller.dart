import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api/realtime_asr_service.dart';
import '../../core/constants/app_strings.dart';
import '../scribe/scribe_permission_service.dart';
import 'models/realtime_clinical_fields.dart';
import 'realtime_asr_channel_io.dart'
    if (dart.library.html) 'realtime_asr_channel_web.dart';

enum RealtimeAsrState { idle, connecting, listening, error }

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
      _state == RealtimeAsrState.connecting || _state == RealtimeAsrState.listening;

  Future<void> start({String language = 'bn-IN'}) async {
    if (isActive) return;

    if (!realtimeAsrSupported) {
      _setError(RealtimeAsrStrings.notSupportedOnWeb);
      return;
    }

    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;

    final granted = await _perm.ensureMicPermission(ctx);
    if (!granted) {
      _setError(RealtimeAsrStrings.micPermissionDenied);
      return;
    }

    _segments.clear();
    _fields = null;
    _errorMessage = null;
    _micWarning = null;
    _lastExtractedTranscript = null;
    _chunkCount = 0;
    _chunkBytes = 0;
    _recentAmplitudes.clear();
    _state = RealtimeAsrState.connecting;
    notifyListeners();

    try {
      final info = await _service.connectionInfo(language: language);
      debugPrint('[RealtimeASR] connecting to ${info.uri} headers=${info.headers.keys}');
      _channel = connectRealtimeChannel(info.uri, info.headers);
      _wsSub = _channel!.stream.listen(
        _onMessage,
        onDone: _onSocketDone,
        onError: (Object e) {
          debugPrint('[RealtimeASR] websocket error: $e');
          _setError('Connection error: $e');
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

      _autoExtractTimer = Timer.periodic(_autoExtractInterval, (_) => extractNow());
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
    if (_state == RealtimeAsrState.idle) return;
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
    _send({'type': 'extract', 'transcript': transcript});

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
    _trackStuckAmplitude(amp);

    final wav = _wrapPcm16Wav(pcm, sampleRate: 16000);
    _send({
      'type': 'audio',
      'data': base64Encode(wav),
      'encoding': 'audio/wav',
      'sample_rate': 16000,
    });
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
        _fields = RealtimeClinicalFields.fromJson(
          (msg['data'] as Map<String, dynamic>?) ?? const {},
        );
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

  void _onSocketDone() {
    debugPrint('[RealtimeASR] websocket closed (state was $_state)');
    if (_state == RealtimeAsrState.listening || _state == RealtimeAsrState.connecting) {
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
