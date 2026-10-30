import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/teleconsult/shukhee_consent_client.dart';

/// Mirrors `shukhee_encounter_link_client_test.dart`'s own `_ScriptedAdapter`
/// convention -- one scripted response (or thrown error) per call.
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
  (ShukheeConsentClient, _ScriptedAdapter) buildClient(
    List<Future<ResponseBody> Function(RequestOptions)> responses,
  ) {
    final adapter = _ScriptedAdapter(responses);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
    final client = ShukheeConsentClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'test-token',
      tenantIdProvider: () async => 'tenant-1',
      dio: dio,
    );
    return (client, adapter);
  }

  group('ShukheeConsentClient.fetchConsent', () {
    test('returns the lng/html/versionId and posts the expected body on success', () async {
      final (client, adapter) = buildClient([
        (_) async => _jsonResponse({
              'message': {
                'lng': 'bn',
                'consent': '<p>বাংলা সম্মতি</p>',
                'version': '2',
                'version_id': '7',
              },
            }),
      ]);

      final result = await client.fetchConsent(lng: 'bn');

      expect(result.lng, 'bn');
      expect(result.html, '<p>বাংলা সম্মতি</p>');
      expect(result.version, '2');
      expect(result.versionId, '7');
      expect(result.items, isEmpty);
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single.data as Map<String, dynamic>;
      expect(sent, {'lng': 'bn'});
      expect(adapter.requests.single.path, ShukheeConsentClient.consentPath);
      expect(adapter.requests.single.headers['X-Auth-Token'], 'Bearer test-token');
      expect(adapter.requests.single.headers['tenantId'], 'tenant-1');
    });

    test('accepts a bare numeric version_id, not just a string', () async {
      final (client, _) = buildClient([
        (_) async => _jsonResponse({
              'message': {'lng': 'en', 'consent': '<p>English</p>', 'version_id': 7},
            }),
      ]);

      final result = await client.fetchConsent(lng: 'en');

      expect(result.versionId, '7');
    });

    test('parses items into ConsentItem, coercing mandatory to a bool', () async {
      final (client, _) = buildClient([
        (_) async => _jsonResponse({
              'message': {
                'lng': 'en',
                'consent': '<p>English</p>',
                'items': [
                  {'description': 'Mandatory item', 'mandatory': true},
                  {'description': 'Optional item', 'mandatory': false},
                ],
              },
            }),
      ]);

      final result = await client.fetchConsent(lng: 'en');

      expect(result.items, hasLength(2));
      expect(result.items[0].description, 'Mandatory item');
      expect(result.items[0].mandatory, isTrue);
      expect(result.items[1].description, 'Optional item');
      expect(result.items[1].mandatory, isFalse);
    });

    test('surfaces the server-side language fallback when it differs from the request', () async {
      final (client, _) = buildClient([
        (_) async => _jsonResponse({
              'message': {'lng': 'en', 'consent': '<p>English fallback</p>'},
            }),
      ]);

      final result = await client.fetchConsent(lng: 'bn');

      expect(result.lng, 'en');
      expect(result.html, '<p>English fallback</p>');
    });

    test('throws (never returns a fallback) on a network/HTTP error', () async {
      final (client, _) = buildClient([
        (_) async => _jsonResponse({'exc_type': 'ValidationError'}, statusCode: 500),
      ]);

      await expectLater(
        client.fetchConsent(lng: 'en'),
        throwsA(isA<ShukheeConsentException>()),
      );
    });

    test('throws without making a request when no auth token is available', () async {
      final adapter = _ScriptedAdapter([
        (_) async => _jsonResponse({
              'message': {'lng': 'en', 'consent': '<p>should not be reached</p>'},
            }),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
      final client = ShukheeConsentClient(
        baseUrl: 'https://example.test',
        authTokenProvider: () async => null,
        dio: dio,
      );

      await expectLater(
        client.fetchConsent(lng: 'en'),
        throwsA(isA<ShukheeConsentException>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('ShukheeConsentClient.recordDecline', () {
    test('returns true and posts the expected body on a confirmed log', () async {
      final (client, adapter) = buildClient([
        (_) async => _jsonResponse({'message': {'logged': true}}),
      ]);

      final result = await client.recordDecline(
        patientId: 'PAT-1',
        visitId: 'VISIT-1',
        lng: 'en',
        versionId: '7',
        patientDob: '1990-01-01',
      );

      expect(result, isTrue);
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single.data as Map<String, dynamic>;
      expect(sent, {
        'patient_id': 'PAT-1',
        'visit_id': 'VISIT-1',
        'lng': 'en',
        'version_id': '7',
        'patient_dob': '1990-01-01',
      });
      expect(adapter.requests.single.path, ShukheeConsentClient.declinePath);
      expect(adapter.requests.single.headers['X-Auth-Token'], 'Bearer test-token');
      expect(adapter.requests.single.headers['tenantId'], 'tenant-1');
    });

    test('returns false (never throws) on a network/HTTP error', () async {
      final (client, _) = buildClient([
        (_) async => _jsonResponse({'exc_type': 'ValidationError'}, statusCode: 417),
      ]);

      final result = await client.recordDecline(patientId: 'PAT-1', lng: 'en');

      expect(result, isFalse);
    });

    test('returns false without making a request when no auth token is available', () async {
      final adapter = _ScriptedAdapter([
        (_) async => _jsonResponse({'message': {'logged': true}}),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
      final client = ShukheeConsentClient(
        baseUrl: 'https://example.test',
        authTokenProvider: () async => null,
        dio: dio,
      );

      final result = await client.recordDecline(patientId: 'PAT-1', lng: 'en');

      expect(result, isFalse);
      expect(adapter.requests, isEmpty);
    });
  });
}
