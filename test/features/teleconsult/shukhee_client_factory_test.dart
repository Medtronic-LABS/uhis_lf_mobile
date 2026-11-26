import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';
import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_log_interceptor.dart';
import 'package:uhis_next/core/net_log/network_request_recorder.dart';
import 'package:uhis_next/features/teleconsult/shukhee_client_factory.dart';

import '../../core/api/scripted_adapter.dart';

class _FakeRecorder implements NetworkRequestRecorder {
  final List<NetworkLogEntry> entries = [];

  @override
  int get epoch => 1;

  @override
  void record(NetworkLogEntry e) => entries.add(e);
}

const _bearerMarker = 'Bearer SECRET-MARKER-123';

ShukheeConfig _config({
  Duration connect = const Duration(seconds: 10),
  Duration receive = const Duration(seconds: 15),
}) => ShukheeConfig(
  baseUrl: 'https://shukhee.example.test',
  authTokenProvider: () async => _bearerMarker,
  connectTimeout: connect,
  receiveTimeout: receive,
);

bool _hasDebugInterceptor(Dio dio) =>
    dio.interceptors.any((i) => i is InterceptorsWrapper);

void main() {
  test(
    'getSpecialities through the built Dio records exactly one row',
    () async {
      final rec = _FakeRecorder();
      final config = _config();
      final dio = buildShukheeDio(config, rec);
      dio.httpClientAdapter = ScriptedAdapter(const {});

      await ShukheeClient(config, dio: dio).getSpecialities();

      expect(rec.entries, hasLength(1));
      final e = rec.entries.single;
      expect(e.statusCode, 200);
      expect(e.method, 'POST');
      expect(e.url, contains('get_specialities'));
    },
  );

  test('no recorded field contains the Bearer marker', () async {
    final rec = _FakeRecorder();
    final config = _config();
    final dio = buildShukheeDio(config, rec);
    dio.httpClientAdapter = ScriptedAdapter(const {});

    await ShukheeClient(config, dio: dio).getSpecialities();

    for (final e in rec.entries) {
      final all = [...e.toDb().values, e.url, e.finalUrl].join('|');
      expect(all, isNot(contains('SECRET-MARKER')));
    }
  });

  test('mirrors the SDK default BaseOptions', () {
    final config = _config(
      connect: const Duration(seconds: 7),
      receive: const Duration(seconds: 9),
    );
    final mine = buildShukheeDio(config, _FakeRecorder()).options;
    // What ShukheeClient builds itself when no Dio is injected.
    final sdk = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
      ),
    ).options;

    expect(mine.baseUrl, sdk.baseUrl);
    expect(mine.connectTimeout, sdk.connectTimeout);
    expect(mine.receiveTimeout, sdk.receiveTimeout);
    expect(mine.sendTimeout, sdk.sendTimeout);
    expect(mine.headers, sdk.headers);
    expect(mine.responseType, sdk.responseType);
    expect(mine.contentType, sdk.contentType);
    expect(mine.followRedirects, sdk.followRedirects);
    expect(mine.validateStatus(200), sdk.validateStatus(200));
    expect(mine.validateStatus(500), sdk.validateStatus(500));
    expect(mine.baseUrl, 'https://shukhee.example.test');
    expect(mine.connectTimeout, const Duration(seconds: 7));
    expect(mine.receiveTimeout, const Duration(seconds: 9));
  });

  test('adds only the net log interceptor when debug logging is off', () {
    final dio = buildShukheeDio(
      _config(),
      _FakeRecorder(),
      debugLogging: false,
    );

    expect(_hasDebugInterceptor(dio), isFalse);
    expect(dio.interceptors.whereType<NetworkLogInterceptor>(), hasLength(1));
  });

  test('adds the [ShukheeDebug] interceptor when debug logging is on', () {
    final dio = buildShukheeDio(_config(), _FakeRecorder(), debugLogging: true);

    expect(_hasDebugInterceptor(dio), isTrue);
    expect(dio.interceptors.whereType<NetworkLogInterceptor>(), hasLength(1));
  });

  Future<ShukheeClient> buildThroughFactory(
    WidgetTester tester,
    NetworkRequestRecorder sessionRecorder,
    ScriptedAdapter adapter, {
    NetworkRequestRecorder? override,
  }) async {
    late ShukheeClient client;
    final api = await ApiClient.create(networkRecorder: sessionRecorder)
      ..importAuthToken(_bearerMarker);
    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: api,
        child: Builder(
          builder: (context) {
            client = buildShukheeClient(
              context,
              recorder: override,
              baseUrl: 'https://shukhee.example.test',
              httpAdapter: adapter,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return client;
  }

  testWidgets('factory records through the ApiClient recorder by default', (
    tester,
  ) async {
    final session = _FakeRecorder();
    final adapter = ScriptedAdapter(const {})..successStatus = 200;
    final client = await buildThroughFactory(tester, session, adapter);

    await tester.runAsync(
      () => client.getSpecialities().then<void>((_) {}, onError: (Object _) {}),
    );

    expect(session.entries, hasLength(1));
    expect(session.entries.single.statusCode, 200);
    expect(session.entries.single.errorType, isNull);
    expect(session.entries.single.url, contains('get_specialities'));
  });

  testWidgets('an explicit recorder overrides the ApiClient one', (
    tester,
  ) async {
    final session = _FakeRecorder();
    final override = _FakeRecorder();
    final adapter = ScriptedAdapter(const {})..successStatus = 200;
    final client = await buildThroughFactory(
      tester,
      session,
      adapter,
      override: override,
    );

    await tester.runAsync(
      () => client.getSpecialities().then<void>((_) {}, onError: (Object _) {}),
    );

    expect(override.entries, hasLength(1));
    expect(override.entries.single.statusCode, 200);
    expect(override.entries.single.errorType, isNull);
    expect(session.entries, isEmpty);
  });
}
