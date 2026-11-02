import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/sync/shukhee_encounter_link_client.dart';

/// Mirrors call_log_sync_service_test.dart's own `_ScriptedAdapter` convention
/// -- one scripted response (or thrown error) per call.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._responses);

  final List<Future<ResponseBody> Function(RequestOptions)> _responses;
  final List<RequestOptions> requests = [];
  int callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final index = callCount < _responses.length ? callCount : _responses.length - 1;
    callCount++;
    return _responses[index](options);
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  final bytes = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(bytes, statusCode, headers: {
    'content-type': ['application/json; charset=utf-8'],
  });
}

void main() {
  (ShukheeEncounterLinkClient, _ScriptedAdapter) buildClient(
    List<Future<ResponseBody> Function(RequestOptions)> responses,
  ) {
    final adapter = _ScriptedAdapter(responses);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
    final client = ShukheeEncounterLinkClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'test-token',
      tenantIdProvider: () async => 'tenant-1',
      dio: dio,
    );
    return (client, adapter);
  }

  group('ShukheeEncounterLinkClient.attachFhirEncounterId', () {
    test('returns true and posts the expected body on a confirmed attach', () async {
      final (client, adapter) = buildClient([
        (_) async => _jsonResponse({'message': {'attached': true}}),
      ]);

      final result = await client.attachFhirEncounterId(
        callLog: 'CL-1',
        fhirEncounterId: 'fhir-enc-1',
      );

      expect(result, isTrue);
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single.data as Map<String, dynamic>;
      expect(sent, {'call_log': 'CL-1', 'fhir_encounter_id': 'fhir-enc-1'});
      expect(adapter.requests.single.path, ShukheeEncounterLinkClient.attachPath);
      expect(adapter.requests.single.headers['X-Auth-Token'], 'Bearer test-token');
      expect(adapter.requests.single.headers['tenantId'], 'tenant-1');
    });

    test('returns false when the backend reports the call_log was unknown', () async {
      final (client, _) = buildClient([
        (_) async => _jsonResponse({'message': {'attached': false}}),
      ]);

      final result = await client.attachFhirEncounterId(
        callLog: 'CL-missing',
        fhirEncounterId: 'fhir-enc-1',
      );

      expect(result, isFalse);
    });

    test('returns false (never throws) on a network/HTTP error', () async {
      final (client, _) = buildClient([
        (_) async => _jsonResponse({'exc_type': 'ValidationError'}, statusCode: 417),
      ]);

      final result = await client.attachFhirEncounterId(
        callLog: 'CL-1',
        fhirEncounterId: 'fhir-enc-1',
      );

      expect(result, isFalse);
    });

    test('returns false without making a request when no auth token is available', () async {
      final adapter = _ScriptedAdapter([
        (_) async => _jsonResponse({'message': {'attached': true}}),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
      final client = ShukheeEncounterLinkClient(
        baseUrl: 'https://example.test',
        authTokenProvider: () async => null,
        dio: dio,
      );

      final result = await client.attachFhirEncounterId(
        callLog: 'CL-1',
        fhirEncounterId: 'fhir-enc-1',
      );

      expect(result, isFalse);
      expect(adapter.requests, isEmpty);
    });
  });
}
