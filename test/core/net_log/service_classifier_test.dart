import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/config/app_config.dart';
import 'package:uhis_next/core/net_log/service_classifier.dart';

void main() {
  const api = 'https://api.example.test';
  const ai = 'https://ai.example.test:8095';

  ConfiguredEndpoint ep(String service, String url) =>
      ConfiguredEndpoint(service: service, url: url, rule: 'RULE');

  final classifier = ServiceClassifier([
    ep(ServiceClassifier.gatewayService, api),
    ep('micro-coaching', '$api/micro-coaching'),
    ep('admin-api', '$api/admin-api'),
    ep('ai-scribe', ai),
    ep('ai-scribe', api),
  ]);

  test('a wss handshake on the https gateway is classified by its path', () {
    expect(
      classifier.classify(
        'wss://api.example.test/ai-scribe/scribe/realtime/transcribe',
      ),
      'ai-scribe',
    );
    expect(
      classifier.classify('wss://other.example.test/x'),
      ServiceClassifier.otherHost,
    );
  });

  test('longest base-URL prefix wins over the first path segment', () {
    expect(classifier.classify('$api/admin-api/api/method/x'), 'admin-api');
    expect(
      classifier.classify('$api/micro-coaching/medtronics-api/sync'),
      'micro-coaching',
    );
  });

  test('prefix beats first segment when they disagree', () {
    final c = ServiceClassifier([
      ep(ServiceClassifier.gatewayService, api),
      ep('admin-api', '$api/admin-api'),
      ep('ai-scribe', '$api/admin-api/x'),
      ep('micro-coaching', 'https://local.example.test:8000'),
    ]);
    expect(c.classify('$api/admin-api/x/y'), 'ai-scribe');
    expect(c.classify('$api/admin-api/other'), 'admin-api');
    expect(
      c.classify('https://local.example.test:8000/api/method/z'),
      'micro-coaching',
    );
  });

  test('the longest of nested prefixes wins', () {
    final c = ServiceClassifier([
      ep(ServiceClassifier.gatewayService, api),
      ep('micro-coaching', '$api/micro-coaching'),
      ep('ai-scribe', '$api/micro-coaching/medtronics-api/'),
    ]);
    expect(c.classify('$api/micro-coaching/medtronics-api/sync'), 'ai-scribe');
    expect(c.classify('$api/micro-coaching/other'), 'micro-coaching');
  });

  test('API-base fallback rows are skipped even for a non-normalised base', () {
    const raw = 'HTTPS://Api.Example.Test:443';
    final c = ServiceClassifier([
      ep(ServiceClassifier.gatewayService, raw),
      ep('ai-scribe', raw),
      ep('admin-api', '$raw/admin-api'),
    ]);
    expect(c.classify('$raw/auth-service/session'), 'auth-service');
    expect(c.classify('$raw/admin-api/x'), 'admin-api');
    expect(c.classify('$raw/unknown'), 'other');
  });

  test('a direct AI service host maps to ai-scribe', () {
    expect(classifier.classify('$ai/scribe/transcribe'), 'ai-scribe');
  });

  test('first path segment labels the API host', () {
    expect(classifier.classify('$api/auth-service/session'), 'auth-service');
    expect(classifier.classify('$api/user-service/x'), 'user-service');
    expect(classifier.classify('$api/spice-service/x'), 'spice-service');
    expect(classifier.classify('$api/offline-service/x'), 'offline-service');
    expect(
      classifier.classify('$api/fhir-server/fhir/Observation?e=1'),
      'fhir-server',
    );
  });

  test('ai-scribe and ai-scribe-service both map to ai-scribe', () {
    expect(
      classifier.classify('$api/ai-scribe/mobile/app-version'),
      'ai-scribe',
    );
    expect(
      classifier.classify('$api/ai-scribe-service/scribe/transcribe'),
      'ai-scribe',
    );
  });

  test('another host is other-host', () {
    expect(
      classifier.classify('https://storage.example.test/bucket/a.wav'),
      'other-host',
    );
  });

  test('an unknown path on the API host is other', () {
    expect(classifier.classify('$api/unknown/x'), 'other');
    expect(classifier.classify(api), 'other');
  });

  test('a prefix must end on a path boundary', () {
    expect(classifier.classify('$api/admin-apix/y'), 'other');
  });

  test('an unparsable or relative URL is other', () {
    expect(classifier.classify('/auth-service/session'), 'other');
    expect(classifier.classify(''), 'other');
  });

  test('with no gateway row every host falls to other', () {
    expect(
      const ServiceClassifier([]).classify('$api/auth-service/x'),
      'other',
    );
  });

  test('fromConfig classifies with the configured endpoints', () {
    final fromConfig = ServiceClassifier.fromConfig();

    expect(
      fromConfig.endpoints.map((e) => e.service),
      AppConfig.configuredEndpoints.map((e) => e.service),
    );
  });
}
