import 'package:flutter_test/flutter_test.dart';
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

  test('longest base-URL prefix wins over the first path segment', () {
    expect(classifier.classify('$api/admin-api/api/method/x'), 'admin-api');
    expect(classifier.classify('$api/micro-coaching/medtronics-api/sync'),
        'micro-coaching');
  });

  test('a direct AI service host maps to ai-scribe', () {
    expect(classifier.classify('$ai/scribe/transcribe'), 'ai-scribe');
  });

  test('first path segment labels the API host', () {
    expect(classifier.classify('$api/auth-service/session'), 'auth-service');
    expect(classifier.classify('$api/user-service/x'), 'user-service');
    expect(classifier.classify('$api/spice-service/x'), 'spice-service');
    expect(classifier.classify('$api/offline-service/x'), 'offline-service');
    expect(classifier.classify('$api/fhir-server/fhir/Observation?e=1'),
        'fhir-server');
  });

  test('ai-scribe and ai-scribe-service both map to ai-scribe', () {
    expect(classifier.classify('$api/ai-scribe/mobile/app-version'),
        'ai-scribe');
    expect(classifier.classify('$api/ai-scribe-service/scribe/transcribe'),
        'ai-scribe');
  });

  test('another host is other-host', () {
    expect(classifier.classify('https://storage.example.test/bucket/a.wav'),
        'other-host');
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
    expect(const ServiceClassifier([]).classify('$api/auth-service/x'),
        'other');
  });
}
