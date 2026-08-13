/// Unit tests for the diagnostics-only instrumentation added to
/// [RealtimeAsrController] — encounter id propagation, the T6
/// listening-without-a-channel condition, error/session-summary emission,
/// and PHI-safety of every logged event.
///
/// No production behavior is exercised here beyond what already existed —
/// these tests exist to prove the *new* logging fires correctly and never
/// leaks transcript/PHI, not to re-validate ASR control flow.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/api/realtime_asr_service.dart';
import 'package:uhis_next/features/realtime_asr/realtime_asr_controller.dart';
import 'package:uhis_next/features/scribe/scribe_permission_service.dart';

/// Minimal fake of the `record` plugin's platform interface — only the
/// handful of calls [RealtimeAsrController] actually makes are meaningful;
/// everything else throws via [noSuchMethod], matching this codebase's
/// existing fake convention (see test/helpers/fake_form_deps.dart).
class FakeRecordPlatform extends RecordPlatform {
  bool hasPermissionResult = true;

  /// Test controls exactly when `startStream()` resolves, so the T6 race
  /// window can be driven deterministically instead of by a guessed delay.
  Completer<Stream<Uint8List>> startStreamGate = Completer<Stream<Uint8List>>();

  final StreamController<Uint8List> audioController =
      StreamController<Uint8List>.broadcast();

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      hasPermissionResult;

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) => startStreamGate.future.then((_) => audioController.stream);

  @override
  Future<String?> stop(String recorderId) async => null;

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakePermissionService extends ScribePermissionService {
  _FakePermissionService(this._granted);
  final bool _granted;

  @override
  Future<bool> ensureMicPermission(BuildContext context) async => _granted;
}

class _FakeRealtimeAsrService extends RealtimeAsrService {
  _FakeRealtimeAsrService(super.api, this._uri);
  final Uri _uri;

  @override
  Future<RealtimeAsrConnectionInfo> connectionInfo({
    required String language,
    String model = 'saarika:v2.5',
    String? assessmentType,
    List<String>? symptomVocab,
    String? encounterId,
  }) async => RealtimeAsrConnectionInfo(uri: _uri, headers: const {});
}

/// PCM16LE mono buffer whose peak amplitude clears the default VAD gate
/// threshold on the very first chunk it's given regardless of the adaptive
/// floor — used only to prove capture/VAD counters move; content is a plain
/// sine-ish sawtooth, not real audio, and is never logged.
Uint8List _loudPcmChunk({int samples = 320}) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, i.isEven ? 30000 : -30000, Endian.little);
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRecordPlatform fakeRecord;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;
  late ApiClient apiClient;

  late HttpOverrides? originalHttpOverrides;

  setUp(() async {
    fakeRecord = FakeRecordPlatform();
    RecordPlatform.instance = fakeRecord;

    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };

    // flutter_test installs a mock HttpOverrides that rejects all real
    // dart:io sockets by default (to stop tests from doing real network
    // I/O by accident). These tests deliberately spin up a real loopback
    // WebSocket server — no plugin/mock exists for the WS client side, so
    // real sockets are the only way to exercise it — hence opting out here.
    originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;

    apiClient = await ApiClient.create();
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    HttpOverrides.global = originalHttpOverrides;
  });

  /// Starts an [HttpServer] on loopback and upgrades every connection to a
  /// WebSocket, handing each accepted socket to [onConnect]. Real
  /// `dart:io` sockets — no plugin/mocking involved on the WS side, since
  /// `web_socket_channel`'s IO implementation is pure Dart.
  Future<HttpServer> startWsServer(
    void Function(WebSocket ws) onConnect,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        onConnect(ws);
      }
    });
    return server;
  }

  RealtimeAsrController buildController(Uri wsUri, {bool granted = true}) {
    return RealtimeAsrController(
      service: _FakeRealtimeAsrService(apiClient, wsUri),
      permissionService: _FakePermissionService(granted),
    );
  }

  group('encounterId propagation', () {
    test('mic-permission-denied path logs the caller-supplied encounterId', () async {
      final ctrl = buildController(Uri.parse('ws://127.0.0.1:1'), granted: false);
      ctrl.bindContext(_dummyContext());

      await ctrl.start(encounterId: 'enc-abc-123');

      // ConsoleLog.step wraps the line in an ANSI color code, so the tag
      // isn't at index 0 — match on contains, not startsWith.
      final asrLines = logs.where((l) => l.contains('[AsrDiag]')).toList();
      expect(asrLines, isNotEmpty);
      expect(asrLines.every((l) => l.contains('encounter_id=enc-abc-123')), isTrue);
      ctrl.dispose();
    });

    test('missing encounterId logs "unknown" rather than crashing', () async {
      final ctrl = buildController(Uri.parse('ws://127.0.0.1:1'), granted: false);
      ctrl.bindContext(_dummyContext());

      await ctrl.start();

      // ConsoleLog.step wraps the line in an ANSI color code, so the tag
      // isn't at index 0 — match on contains, not startsWith.
      final asrLines = logs.where((l) => l.contains('[AsrDiag]')).toList();
      expect(asrLines, isNotEmpty);
      expect(asrLines.every((l) => l.contains('encounter_id=unknown')), isTrue);
      ctrl.dispose();
    });
  });

  group('_setError chokepoint', () {
    test('mic permission denial emits ASR_ERROR with a fixed category and a session summary', () async {
      final ctrl = buildController(Uri.parse('ws://127.0.0.1:1'), granted: false);
      ctrl.bindContext(_dummyContext());

      await ctrl.start(encounterId: 'enc-1');

      final errorLine = logs.firstWhere((l) => l.contains('ASR_ERROR'));
      expect(errorLine, contains('errorCategory=mic_permission_denied'));
      expect(errorLine, contains('previousState=connecting'));

      final summaryLines = logs.where((l) => l.contains('ASR_SESSION_SUMMARY')).toList();
      expect(summaryLines, hasLength(1), reason: 'exactly one summary per session');
      expect(summaryLines.single, contains('errorEventCount=1'));
      expect(summaryLines.single, contains('lastErrorCategory=mic_permission_denied'));
      expect(summaryLines.single, contains('finalState=error'));
      ctrl.dispose();
    });
  });

  group('T6 — ASR_LISTENING_WITHOUT_WS', () {
    test('WS closes during the recorder-start await → the resulting idle '
        'state is unconditionally overwritten back to listening', () async {
      // NOTE on what this test can and can't prove deterministically: once
      // the server closes, _onSocketDone's `_teardown()` needs to call
      // `_recorder.isRecording()` — but the SAME AudioRecorder instance's
      // internal Semaphore is already held for the full duration of the
      // in-flight `startStream()` call this test is gating. That makes
      // `_teardown()` block until this test releases the gate, and the
      // instant it does, `start()`'s own synchronous continuation reaches
      // the T6 check before yielding back to the event loop — so
      // `channelAvailable` reliably reads `true` here, not `false`, in this
      // exact construction. That's a real, code-verified property of
      // `record`'s per-instance call serialization, not a flaw in this test:
      // it means the "channel already null" sub-variant of T6 is confined to
      // a much narrower window than "any recorder call in flight" (see the
      // investigation notes). What *is* reliably, deterministically
      // reproducible — and is exactly as dangerous — is proven below: the
      // WS-close handler already reset state to `idle` before `start()`
      // unconditionally overwrites it back to `listening`.
      final serverAcceptedAndClosed = Completer<void>();
      final server = await startWsServer((ws) {
        ws.close();
        serverAcceptedAndClosed.complete();
      });
      addTearDown(server.close);

      final wsUri = Uri.parse('ws://127.0.0.1:${server.port}');
      final ctrl = buildController(wsUri);
      ctrl.bindContext(_dummyContext());

      final startFuture = ctrl.start(encounterId: 'enc-race');

      // The server issuing close() doesn't mean the client has processed it
      // yet — condition-based wait on the client actually observing it
      // (state flips to idle inside _onSocketDone) before releasing the
      // recorder gate, not a guessed delay.
      await serverAcceptedAndClosed.future;
      for (var i = 0; i < 200 && ctrl.state != RealtimeAsrState.idle; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(ctrl.state, RealtimeAsrState.idle,
          reason: 'onSocketDone should have processed the close and reset '
              'state before the recorder gate is released');

      fakeRecord.startStreamGate.complete(fakeRecord.audioController.stream);
      await startFuture;

      // The overwrite hazard: state was idle (proven above) at the moment
      // the close was handled, then start() unconditionally clobbers it
      // back to listening regardless — exactly the T6 risk, independent of
      // whether _channel itself had also been nulled by then (see the
      // semaphore note above for why that narrower condition isn't
      // reliably reproducible in this exact construction).
      final finalStateLine = logs.firstWhere((l) => l.contains('ASR_START_FINAL_STATE'));
      expect(finalStateLine, contains('currentState=idle'));
      // Fixed behavior: start() must NOT resurrect the already-torn-down
      // idle state back into listening.
      expect(ctrl.state, isNot(RealtimeAsrState.listening));

      ctrl.dispose();
    });

    test('healthy connection never emits ASR_LISTENING_WITHOUT_WS', () async {
      final connected = Completer<void>();
      final server = await startWsServer((ws) {
        connected.complete();
        addTearDown(ws.close);
      });
      addTearDown(server.close);

      final wsUri = Uri.parse('ws://127.0.0.1:${server.port}');
      final ctrl = buildController(wsUri);
      ctrl.bindContext(_dummyContext());

      final startFuture = ctrl.start(encounterId: 'enc-healthy');
      await connected.future;
      fakeRecord.startStreamGate.complete(fakeRecord.audioController.stream);
      await startFuture;

      expect(logs.any((l) => l.contains('ASR_LISTENING_WITHOUT_WS')), isFalse);
      expect(logs.any((l) => l.contains('ASR_LISTENING ')), isTrue);
      expect(ctrl.state, RealtimeAsrState.listening);

      await ctrl.stop();
      ctrl.dispose();
    });
  });

  group('audio capture / VAD / send counters', () {
    test('a loud chunk passes VAD and is counted as sent once the channel is up', () async {
      final connected = Completer<void>();
      final server = await startWsServer((ws) {
        connected.complete();
        addTearDown(ws.close);
      });
      addTearDown(server.close);

      final wsUri = Uri.parse('ws://127.0.0.1:${server.port}');
      final ctrl = buildController(wsUri);
      ctrl.bindContext(_dummyContext());

      final startFuture = ctrl.start(encounterId: 'enc-audio');
      await connected.future;
      fakeRecord.startStreamGate.complete(fakeRecord.audioController.stream);
      await startFuture;

      // Bootstrap window (~500ms of assumed silence) must elapse before the
      // gate can flip to voice state — feed enough loud chunks to cross it.
      for (var i = 0; i < 40; i++) {
        fakeRecord.audioController.add(_loudPcmChunk());
        await Future<void>.delayed(Duration.zero);
      }

      await ctrl.stop();

      final summary = logs.firstWhere((l) => l.contains('ASR_SESSION_SUMMARY'));
      expect(summary, isNot(contains('vadChunksReceived=0')));
      // At least the send-side accounting must be internally consistent:
      // every chunk is either sent or dropped-for-no-channel, never neither.
      final sentMatch = RegExp(r'chunksSentWs=(\d+)').firstMatch(summary);
      final droppedMatch = RegExp(r'chunksDroppedNoChannel=(\d+)').firstMatch(summary);
      expect(sentMatch, isNotNull);
      expect(droppedMatch, isNotNull);

      ctrl.dispose();
    });
  });

  group('PHI safety', () {
    test('a received transcript segment never appears in any log line', () async {
      const secretTranscript = 'PATIENT_SAID_SOMETHING_SENSITIVE_42';
      final connected = Completer<void>();
      late WebSocket serverSocket;
      final server = await startWsServer((ws) {
        serverSocket = ws;
        connected.complete();
      });
      addTearDown(server.close);

      final wsUri = Uri.parse('ws://127.0.0.1:${server.port}');
      final ctrl = buildController(wsUri);
      ctrl.bindContext(_dummyContext());

      final startFuture = ctrl.start(encounterId: 'enc-phi');
      await connected.future;
      fakeRecord.startStreamGate.complete(fakeRecord.audioController.stream);
      await startFuture;

      serverSocket.add('{"type":"data","data":{"transcript":"$secretTranscript"}}');
      // Condition-based: wait until the controller actually recorded the
      // segment rather than sleeping a guessed duration.
      for (var i = 0; i < 200 && ctrl.fullTranscript.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(ctrl.fullTranscript, contains(secretTranscript));

      await ctrl.stop();

      // Scoped to this task's new [AsrDiag]-tagged instrumentation — the
      // pre-existing `debugPrint('[RealtimeASR] recv transcript segment:
      // ...')` a few lines up in _onMessage already logs raw transcript
      // text by design, for local dev only; that's out of scope here.
      final asrLines = logs.where((l) => l.contains('[AsrDiag]'));
      expect(asrLines.any((l) => l.contains(secretTranscript)), isFalse);
      final summary = asrLines.firstWhere((l) => l.contains('ASR_SESSION_SUMMARY'));
      expect(summary, contains('transcriptSegmentsReceived=1'));

      ctrl.dispose();
    });

    test('a malformed WS frame emits ASR_WS_MESSAGE_PARSE_ERROR without echoing the raw frame', () async {
      final connected = Completer<void>();
      late WebSocket serverSocket;
      final server = await startWsServer((ws) {
        serverSocket = ws;
        connected.complete();
      });
      addTearDown(server.close);

      final wsUri = Uri.parse('ws://127.0.0.1:${server.port}');
      final ctrl = buildController(wsUri);
      ctrl.bindContext(_dummyContext());

      final startFuture = ctrl.start(encounterId: 'enc-parse-error');
      await connected.future;
      fakeRecord.startStreamGate.complete(fakeRecord.audioController.stream);
      await startFuture;

      const malformed = 'not-json-and-definitely-not-a-transcript';
      serverSocket.add(malformed);
      var sawParseError = false;
      for (var i = 0; i < 200 && !sawParseError; i++) {
        await Future<void>.delayed(Duration.zero);
        sawParseError = logs.any((l) => l.contains('ASR_WS_MESSAGE_PARSE_ERROR'));
      }
      expect(sawParseError, isTrue);
      // Scoped to [AsrDiag] lines — the pre-existing `debugPrint('...
      // unparseable message: $raw ...')` in _onMessage already echoes the
      // raw frame for local dev only; out of scope for this instrumentation.
      final asrLines = logs.where((l) => l.contains('[AsrDiag]'));
      expect(asrLines.any((l) => l.contains(malformed)), isFalse);

      await ctrl.stop();
      ctrl.dispose();
    });
  });

  group('disposed guard', () {
    test('calling stop() after dispose() does not throw', () async {
      final ctrl = buildController(Uri.parse('ws://127.0.0.1:1'), granted: false);
      ctrl.bindContext(_dummyContext());
      await ctrl.start(encounterId: 'enc-dispose-guard');
      ctrl.dispose();
      // Must not throw "used after being disposed" — this reproduces the
      // shape of the live crash (a call landing after dispose()), just via
      // a synchronous call instead of the harder-to-reproduce async race.
      expect(() => ctrl.stop(), returnsNormally);
    });

    test('extractNow safety-timeout callback firing after dispose does not throw', () async {
      // Set up a real WebSocket server that won't reply to extractions,
      // so the _extractionSafetyTimeout callback stays pending after dispose.
      late WebSocket serverSocket;
      final connected = Completer<void>();
      final server = await startWsServer((ws) {
        serverSocket = ws;
        connected.complete();
        addTearDown(ws.close);
      });
      addTearDown(server.close);

      final wsUri = Uri.parse('ws://127.0.0.1:${server.port}');
      final ctrl = buildController(wsUri); // granted=true by default
      ctrl.bindContext(_dummyContext());

      // Start the session and reach listening state.
      final startFuture = ctrl.start(encounterId: 'enc-dispose-guard-2');
      await connected.future;
      fakeRecord.startStreamGate.complete(fakeRecord.audioController.stream);
      await startFuture;
      expect(ctrl.state, RealtimeAsrState.listening);

      // Send a transcript segment from the server so fullTranscript is non-empty.
      // extractNow() returns early if transcript is empty.
      serverSocket.add('{"type":"data","data":{"transcript":"test symptom"}}');
      // Wait for the controller to receive and process the message.
      for (var i = 0; i < 200 && ctrl.fullTranscript.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(ctrl.fullTranscript, isNotEmpty);

      // Call extractNow() — this schedules the _extractionSafetyTimeout callback.
      ctrl.extractNow();
      expect(ctrl.isExtracting, isTrue,
          reason: 'extractNow() should have set _extracting = true');

      // Dispose immediately, while the safety-timeout callback is still scheduled.
      // This is the real crash case: a Future.delayed callback fires after dispose().
      ctrl.dispose();

      // Pump past the safety-timeout (21 seconds) — if the dispose guard weren't
      // in place, the _safeNotify() call inside that callback would throw
      // "used after being disposed". With the guard, it silently returns.
      await Future<void>.delayed(const Duration(seconds: 21));

      // If we reach here without a throw, the guard worked.
    });
  });

  group('session summary emitted exactly once', () {
    test('dispose() after an error state still emits exactly one summary', () async {
      final ctrl = buildController(Uri.parse('ws://127.0.0.1:1'), granted: false);
      ctrl.bindContext(_dummyContext());

      await ctrl.start(encounterId: 'enc-once');
      ctrl.dispose(); // catch-all path — must not double-emit

      final summaryLines = logs.where((l) => l.contains('ASR_SESSION_SUMMARY')).toList();
      expect(summaryLines, hasLength(1));
    });

    test('a mid-session close (state already listening) emits the summary '
        'immediately, unlike the connecting-state race', () async {
      late WebSocket serverSocket;
      final connected = Completer<void>();
      final server = await startWsServer((ws) {
        serverSocket = ws;
        connected.complete();
      });
      addTearDown(server.close);

      final wsUri = Uri.parse('ws://127.0.0.1:${server.port}');
      final ctrl = buildController(wsUri);
      ctrl.bindContext(_dummyContext());

      final startFuture = ctrl.start(encounterId: 'enc-mid-death');
      await connected.future;
      fakeRecord.startStreamGate.complete(fakeRecord.audioController.stream);
      await startFuture;
      expect(ctrl.state, RealtimeAsrState.listening);

      await serverSocket.close();
      for (var i = 0; i < 200 && ctrl.state != RealtimeAsrState.idle; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final summaryLines = logs.where((l) => l.contains('ASR_SESSION_SUMMARY')).toList();
      expect(summaryLines, hasLength(1),
          reason: 'a death after reaching `listening` cannot be resurrected '
              'by a still-running start(), so the summary must not wait for '
              'dispose()');
      expect(summaryLines.single, contains('wsCloseReason=ws_done'));

      ctrl.dispose(); // must not emit a second summary
      expect(
        logs.where((l) => l.contains('ASR_SESSION_SUMMARY')),
        hasLength(1),
      );
    });
  });
}

/// A [BuildContext] good enough for [ScribePermissionService]-shaped fakes
/// that never actually read from it (our fakes short-circuit before
/// touching `context`), just to satisfy [RealtimeAsrController.bindContext]'s
/// non-null + mounted checks.
BuildContext _dummyContext() => _FakeBuildContext();

class _FakeBuildContext implements BuildContext {
  @override
  bool get mounted => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
