import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/api/endpoints.dart';
import 'package:uhis_next/core/config/app_config.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_log_interceptor.dart';
import 'package:uhis_next/core/net_log/network_request_recorder.dart';

import '../api/scripted_adapter.dart';

class _FakeRecorder implements NetworkRequestRecorder {
  final List<NetworkLogEntry> entries = [];

  @override
  int get epoch => 7;

  @override
  void record(NetworkLogEntry e) => entries.add(e);
}

class _ThrowingRecorder implements NetworkRequestRecorder {
  @override
  int get epoch => 0;

  @override
  void record(NetworkLogEntry e) => throw const FormatException('boom');
}

Future<(ApiClient, ScriptedAdapter)> _client(
  NetworkRequestRecorder recorder, [
  Map<String, int> failures = const {},
]) async {
  final api = await ApiClient.create(networkRecorder: recorder);
  final adapter = ScriptedAdapter(failures);
  api.dio.httpClientAdapter = adapter;
  return (api, adapter);
}

void main() {
  test('200 records one row with sanitised url and status', () async {
    final rec = _FakeRecorder();
    final (api, _) = await _client(rec);

    await api.dio.get<dynamic>('/x/member?phone=0123456789&token=abc');

    expect(rec.entries, hasLength(1));
    final e = rec.entries.single;
    expect(e.source, 'dart');
    expect(e.method, 'GET');
    expect(e.statusCode, 200);
    expect(e.errorType, isNull);
    expect(e.timing, 'total');
    expect(e.attempt, 1);
    expect(e.epoch, 7);
    expect(e.finalUrl, isNull);
    expect(e.durationMs, isNotNull);
    expect(e.url, isNot(contains('0123456789')));
    expect(e.url, isNot(contains('token=abc')));
  });

  test('404 records one row with status and no errorType', () async {
    final rec = _FakeRecorder();
    final (api, adapter) = await _client(rec);
    adapter.successStatus = 404;

    await api.dio.get<dynamic>('/missing');

    expect(rec.entries.single.statusCode, 404);
    expect(rec.entries.single.errorType, isNull);
  });

  test('401 records one row and still fires onUnauthorized', () async {
    final rec = _FakeRecorder();
    final (api, adapter) = await _client(rec);
    adapter.successStatus = 401;
    var fired = 0;
    api.onUnauthorized = () => fired++;

    await api.dio.get<dynamic>('/secure');

    expect(rec.entries.single.statusCode, 401);
    expect(fired, 1);
  });

  test('a retried 500 logs one row per attempt, no duplicates', () async {
    final rec = _FakeRecorder();
    final (api, adapter) =
        await _client(rec, {Endpoints.offlineSyncHouseholds: 2});
    adapter.failureStatus = 500;

    await api.dio.post<dynamic>(Endpoints.offlineSyncHouseholds);

    expect(rec.entries.map((e) => e.attempt).toList(), [1, 2, 3]);
    expect(rec.entries.map((e) => e.statusCode).toList(), [500, 500, 200]);
    expect(rec.entries.first.errorType, isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a timeout records errorType connectionTimeout', () async {
    final rec = _FakeRecorder();
    final (api, adapter) = await _client(rec, {'/slow': 1});
    adapter.failureType = DioExceptionType.connectionTimeout;

    await expectLater(
      api.dio.post<dynamic>('/slow'),
      throwsA(isA<DioException>()),
    );

    expect(rec.entries.single.errorType, 'connectionTimeout');
    expect(rec.entries.single.statusCode, isNull);
  });

  test('attaching twice still records one row', () async {
    final rec = _FakeRecorder();
    final (api, _) = await _client(rec);
    api.attachNetworkLog(api.dio);
    NetworkLogInterceptor.attach(api.dio, rec);

    await api.dio.get<dynamic>('/x');

    expect(rec.entries, hasLength(1));
  });

  test('attachAiServiceAuth also attaches the log', () async {
    final rec = _FakeRecorder();
    final (api, _) = await _client(rec);
    final direct = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))
      ..httpClientAdapter = ScriptedAdapter({});

    api.attachAiServiceAuth(direct);
    await direct.get<dynamic>('/briefing');

    expect(rec.entries, hasLength(1));
  });

  test('never records headers, body or response data', () async {
    final rec = _FakeRecorder();
    final (api, _) = await _client(rec);

    await api.dio.post<dynamic>(
      '/x',
      data: {'marker': 'BODY-MARKER-123'},
      options: Options(headers: {'Authorization': 'Bearer SECRET-TOKEN-XYZ'}),
    );

    final all = rec.entries.map((e) => e.toDb().toString()).join();
    expect(all, isNot(contains('SECRET-TOKEN-XYZ')));
    expect(all, isNot(contains('BODY-MARKER-123')));
    expect(all, isNot(contains('"ok":true')));
  });

  test('a recorder that throws never fails the request', () async {
    final (api, _) = await _client(_ThrowingRecorder());

    final res = await api.dio.get<dynamic>('/x');

    expect(res.statusCode, 200);
  });

  test('an email in the path is recorded sanitised', () async {
    final rec = _FakeRecorder();
    final (api, _) = await _client(rec);

    await api.dio.get<dynamic>('/users/jane.doe@example.com/profile');

    expect(rec.entries.single.url, isNot(contains('jane.doe')));
    expect(rec.entries.single.url, isNot(contains('@example.com')));
  });
}
