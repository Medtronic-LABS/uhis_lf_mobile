import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_request_recorder.dart';
import 'package:uhis_next/features/realtime_asr/realtime_asr_channel_io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeChannel implements WebSocketChannel {
  final Completer<void> readyCompleter = Completer<void>();

  @override
  Future<void> get ready => readyCompleter.future;

  @override
  Stream<dynamic> get stream => const Stream<dynamic>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recorder implements NetworkRequestRecorder {
  final List<NetworkLogEntry> rows = [];

  @override
  int get epoch => 7;

  @override
  void record(NetworkLogEntry e) => rows.add(e);
}

class _ThrowingRecorder implements NetworkRequestRecorder {
  @override
  int get epoch => 0;

  @override
  void record(NetworkLogEntry e) => throw StateError('boom');
}

final Uri _uri = Uri.parse(
    'wss://example.test/ai-scribe/scribe/realtime/transcribe'
    '?encounterId=ENC-1&tenantId=42&language=en');
const Map<String, String> _headers = {
  'Authorization': 'Bearer SECRET-MARKER',
  'Cookie': 'sid=SECRET-MARKER',
  'tenantId': '42',
};

void main() {
  late _FakeChannel channel;
  late _Recorder recorder;

  WebSocketChannel connect({NetworkRequestRecorder? rec, Map<String, String>? h}) =>
      connectRealtimeChannel(
        _uri,
        h ?? _headers,
        recorder: rec ?? recorder,
        connect: (_, _) => channel,
      );

  setUp(() {
    channel = _FakeChannel();
    recorder = _Recorder();
  });

  test('ready completes -> one WS handshake row, sanitised url', () async {
    connect();
    channel.readyCompleter.complete();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.rows, hasLength(1));
    final row = recorder.rows.single;
    expect(row.method, 'WS');
    expect(row.statusCode, 101);
    expect(row.timing, 'handshake');
    expect(row.errorType, isNull);
    expect(row.source, 'dart');
    expect(row.attempt, 1);
    expect(row.epoch, 7);
    expect(row.durationMs, isNotNull);
    expect(row.url, isNot(contains('encounterId')));
    expect(row.url, isNot(contains('tenantId')));
    expect(row.url, isNot(contains('ENC-1')));
    expect(row.service, isNotEmpty);
  });

  final mapped = <String, Object>{
    'wsError': WebSocketChannelException('x'),
    'connectionError': const SocketException('x'),
    'badCertificate': const HandshakeException('x'),
    'connectionTimeout': TimeoutException('x'),
    'unknown': StateError('x'),
  };
  mapped.forEach((type, error) {
    test('ready fails with ${error.runtimeType} -> $type', () async {
      connect();
      channel.readyCompleter.future.ignore();
      channel.readyCompleter.completeError(error);
      await Future<void>.delayed(Duration.zero);

      expect(recorder.rows, hasLength(1));
      expect(recorder.rows.single.errorType, type);
      expect(recorder.rows.single.statusCode, isNull);
      expect(recorder.rows.single.method, 'WS');
    });
  });

  test('original error still reaches a second listener', () async {
    final ch = connect();
    final seen = Completer<Object>();
    unawaited(ch.ready.then((_) {}, onError: (Object e) => seen.complete(e)));
    channel.readyCompleter.completeError(const SocketException('x'));

    expect(await seen.future, isA<SocketException>());
    expect(recorder.rows, hasLength(1));
  });

  test('a throwing recorder does not affect the connection', () async {
    final ch = connect(rec: _ThrowingRecorder());
    channel.readyCompleter.complete();
    await ch.ready;
    await Future<void>.delayed(Duration.zero);
  });

  test('header values never reach a recorded field', () async {
    connect();
    channel.readyCompleter.complete();
    await Future<void>.delayed(Duration.zero);
    final r = recorder.rows.single;
    final all = [r.url, r.finalUrl, r.service, r.method, r.timing, r.errorType]
        .join('|');
    expect(all, isNot(contains('SECRET-MARKER')));
    expect(all, isNot(contains('Bearer')));
  });
}
