import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/frappe_client.dart';

import '../../helpers/scripted_dio_adapter.dart';

void main() {
  (FrappeClient, ScriptedDioAdapter) build(
    List<Future<ResponseBody> Function(RequestOptions)> responses, {
    String? token = 'jwt-1',
    String? tenant = '7',
  }) {
    final adapter = ScriptedDioAdapter(responses);
    final dio = Dio(BaseOptions(baseUrl: 'https://frappe.test'))
      ..httpClientAdapter = adapter;
    return (
      FrappeClient(
        baseUrl: 'https://frappe.test',
        authTokenProvider: () async => token,
        tenantIdProvider: () async => tenant,
        dio: dio,
      ),
      adapter,
    );
  }

  group('postJson', () {
    test('sends X-Auth-Token + tenantId and unwraps message', () async {
      final (client, adapter) = build([
        (_) async => jsonResponseBody({
          'message': {'ok': true},
        }),
      ]);

      final result = await client.postJson('/api/method/x', {'a': 1});

      expect(result, {'ok': true});
      final headers = adapter.requests.single.headers;
      expect(headers['X-Auth-Token'], 'Bearer jwt-1');
      expect(headers['tenantId'], '7');
      expect(adapter.requests.single.data, {'a': 1});
    });

    test('no token → unauthorized without calling the server', () async {
      final (client, adapter) = build([
        (_) async => jsonResponseBody({'message': {}}),
      ], token: null);

      await expectLater(
        client.postJson('/x', {}),
        throwsA(
          isA<FrappeException>().having(
            (e) => e.kind,
            'kind',
            FrappeErrorKind.unauthorized,
          ),
        ),
      );
      expect(adapter.callCount, 0);
    });

    test('body without a message object → badResponse', () async {
      final (client, _) = build([
        (_) async => jsonResponseBody({'data': 1}),
      ]);

      await expectLater(
        client.postJson('/x', {}),
        throwsA(
          isA<FrappeException>().having(
            (e) => e.kind,
            'kind',
            FrappeErrorKind.badResponse,
          ),
        ),
      );
    });

    for (final (status, kind) in [
      (401, FrappeErrorKind.unauthorized),
      (404, FrappeErrorKind.notFound),
      (417, FrappeErrorKind.unavailable),
      (429, FrappeErrorKind.rateLimited),
      (503, FrappeErrorKind.unavailable),
      (400, FrappeErrorKind.badResponse),
    ]) {
      test('HTTP $status → ${kind.name}', () async {
        final (client, _) = build([
          (_) async => jsonResponseBody({'exc_type': 'X'}, statusCode: status),
        ]);

        await expectLater(
          client.postJson('/x', {}),
          throwsA(
            isA<FrappeException>()
                .having((e) => e.kind, 'kind', kind)
                .having((e) => e.statusCode, 'statusCode', status),
          ),
        );
      });
    }

    test('connection failure → network', () async {
      final (client, _) = build([
        (o) async => throw DioException.connectionError(
          requestOptions: o,
          reason: 'refused',
        ),
      ]);

      await expectLater(
        client.postJson('/x', {}),
        throwsA(
          isA<FrappeException>().having(
            (e) => e.kind,
            'kind',
            FrappeErrorKind.network,
          ),
        ),
      );
    });
  });

  group('getBytes', () {
    test('returns bytes and etag', () async {
      final (client, adapter) = build([
        (_) async => bytesResponseBody([1, 2, 3], etag: '"abc"'),
      ]);

      final r = await client.getBytes('/img');

      expect(r.status, 200);
      expect(r.bytes, [1, 2, 3]);
      expect(r.etag, '"abc"');
      expect(adapter.requests.single.headers['X-Auth-Token'], 'Bearer jwt-1');
    });

    test('304 with If-None-Match returns no bytes', () async {
      final (client, adapter) = build([
        (_) async => bytesResponseBody(const [], statusCode: 304),
      ]);

      final r = await client.getBytes('/img', ifNoneMatch: '"abc"');

      expect(r.status, 304);
      expect(r.bytes, isNull);
      expect(adapter.requests.single.headers['If-None-Match'], '"abc"');
    });

    test('404 → notFound', () async {
      final (client, _) = build([
        (_) async =>
            jsonResponseBody({'exc_type': 'DoesNotExist'}, statusCode: 404),
      ]);

      await expectLater(
        client.getBytes('/img'),
        throwsA(
          isA<FrappeException>().having(
            (e) => e.kind,
            'kind',
            FrappeErrorKind.notFound,
          ),
        ),
      );
    });
  });

  group('postMultipart', () {
    test('sends the form with auth headers and unwraps message', () async {
      final (client, adapter) = build([
        (_) async => jsonResponseBody({
          'message': {'ok': true},
        }),
      ]);
      final form = FormData.fromMap({'programme': 'epi'});

      final result = await client.postMultipart(
        '/api/method/x',
        form,
        receiveTimeout: const Duration(seconds: 180),
      );

      expect(result, {'ok': true});
      final request = adapter.requests.single;
      expect(request.data, same(form));
      expect(request.headers['X-Auth-Token'], 'Bearer jwt-1');
      expect(request.receiveTimeout, const Duration(seconds: 180));
    });
  });

  group('error cause', () {
    test('HTTP error keeps the DioException as cause', () async {
      final (client, _) = build([
        (_) async => jsonResponseBody({'exc_type': 'X'}, statusCode: 503),
      ]);

      await expectLater(
        client.postJson('/x', {}),
        throwsA(
          isA<FrappeException>().having(
            (e) => e.cause,
            'cause',
            isA<DioException>(),
          ),
        ),
      );
    });

    test('postJson applies a per-call receive timeout', () async {
      final (client, adapter) = build([
        (_) async => jsonResponseBody({
          'message': {'ok': true},
        }),
      ]);

      await client.postJson(
        '/x',
        {},
        receiveTimeout: const Duration(seconds: 30),
      );

      expect(
        adapter.requests.single.receiveTimeout,
        const Duration(seconds: 30),
      );
    });
  });
}
