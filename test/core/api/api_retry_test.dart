import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/api/endpoints.dart';
import 'package:uhis_next/core/config/app_config.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

/// Counts requests per path and replays a scripted outcome per attempt, so a
/// test can assert exactly how many times a request was issued. Replaces the
/// real adapter — no sockets, no mocking package needed.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.failuresBeforeSuccess);

  /// How many leading attempts fail with a receiveTimeout, per path.
  final Map<String, int> failuresBeforeSuccess;

  /// Total attempts observed, per path.
  final Map<String, int> calls = <String, int>{};

  /// Status returned once a path stops failing.
  int successStatus = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final seen = (calls[path] ?? 0) + 1;
    calls[path] = seen;

    if (seen <= (failuresBeforeSuccess[path] ?? 0)) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      successStatus,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiClient, _ScriptedAdapter)> _clientWith(
  Map<String, int> failures,
) async {
  final api = await ApiClient.create();
  final adapter = _ScriptedAdapter(failures);
  api.dio.httpClientAdapter = adapter;
  return (api, adapter);
}

void main() {
  // These assert English copy, so pin the language. AppLocale defaults to
  // Bangla (BD-first), and Bangla localizes digits — '12 days' becomes
  // '১২ days' — so an unpinned test is really asserting the default locale.
  setUp(() => AppLocale.current = AppLanguage.english);

  group('ApiClient timeouts', () {
    test('BaseOptions are driven by AppConfig, not hardcoded', () async {
      final api = await ApiClient.create();

      expect(
        api.dio.options.receiveTimeout,
        Duration(seconds: AppConfig.apiReceiveTimeoutSeconds),
      );
      expect(
        api.dio.options.connectTimeout,
        Duration(seconds: AppConfig.apiConnectTimeoutSeconds),
      );
    });

    test('connect timeout stays short so offline is still detected fast',
        () async {
      final api = await ApiClient.create();

      // A long connect timeout would make every offline action hang instead of
      // failing fast — only the wait-for-response budget was meant to grow.
      expect(api.dio.options.connectTimeout, const Duration(seconds: 30));
      expect(
        api.dio.options.connectTimeout!.inSeconds,
        lessThan(api.dio.options.receiveTimeout!.inSeconds),
      );
    });
  });

  group('ApiClient retry', () {
    test('replays a read that times out, then succeeds', () async {
      final (api, adapter) =
          await _clientWith({Endpoints.offlineSyncFetch: 2});

      final res = await api.dio.post<dynamic>(Endpoints.offlineSyncFetch);

      expect(res.statusCode, 200);
      expect(adapter.calls[Endpoints.offlineSyncFetch], 3);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('gives up after apiMaxAttempts and rethrows the timeout', () async {
      final (api, adapter) =
          await _clientWith({Endpoints.offlineSyncFetch: 99});

      await expectLater(
        api.dio.post<dynamic>(Endpoints.offlineSyncFetch),
        throwsA(isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        )),
      );
      expect(
        adapter.calls[Endpoints.offlineSyncFetch],
        AppConfig.apiMaxAttempts,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('never replays a write — a duplicate household is worse than a retry',
        () async {
      // offline-sync/create has no server-side requestId uniqueness, so a
      // replay can insert duplicate households/members/assessments.
      final (api, adapter) =
          await _clientWith({Endpoints.offlineSyncCreate: 99});

      await expectLater(
        api.dio.post<dynamic>(Endpoints.offlineSyncCreate),
        throwsA(isA<DioException>()),
      );
      expect(adapter.calls[Endpoints.offlineSyncCreate], 1);
    });

    test('does not replay a 4xx on a retryable read path', () async {
      final (api, adapter) = await _clientWith({});
      adapter.successStatus = 400;

      // validateStatus admits <500, so this resolves rather than throwing.
      final res = await api.dio.post<dynamic>(Endpoints.offlineSyncFetch);

      expect(res.statusCode, 400);
      expect(adapter.calls[Endpoints.offlineSyncFetch], 1);
    });

    test('reports each retry through onRetryAttempt', () async {
      final (api, _) = await _clientWith({Endpoints.offlineSyncFetch: 2});
      final seen = <(String, int, int)>[];
      api.onRetryAttempt = (path, attempt, max) => seen.add((path, attempt, max));

      await api.dio.post<dynamic>(Endpoints.offlineSyncFetch);

      // Attempt 1 is the original request; 2 and 3 are the replays.
      expect(seen.map((e) => e.$2).toList(), [2, 3]);
      expect(seen.every((e) => e.$1 == Endpoints.offlineSyncFetch), isTrue);
      expect(seen.every((e) => e.$3 == AppConfig.apiMaxAttempts), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
