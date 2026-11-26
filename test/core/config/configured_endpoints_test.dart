import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/config/app_config.dart';
import 'package:uhis_next/core/net_log/service_classifier.dart';
import 'package:uhis_next/core/services/micro_coaching_service.dart';

void main() {
  const api = 'https://api.example.test';

  Map<String, ConfiguredEndpoint> build({
    String apiBaseUrl = api,
    String coachingExplicit = '',
    String aiServiceBaseUrl = '',
    String scribeExplicit = '',
    String shukheeLocal = '',
    String spiceNextCoreLocal = '',
    String spiceNextAiLocal = '',
  }) {
    final list = AppConfig.buildEndpoints(
      apiBaseUrl: apiBaseUrl,
      coachingExplicit: coachingExplicit,
      aiServiceBaseUrl: aiServiceBaseUrl,
      scribeExplicit: scribeExplicit,
      shukheeLocal: shukheeLocal,
      spiceNextCoreLocal: spiceNextCoreLocal,
      spiceNextAiLocal: spiceNextAiLocal,
    );
    // First row per rule: rows that share a rule also share a URL.
    return {for (final e in list.reversed) e.rule: e};
  }

  group('buildEndpoints defaults', () {
    test('derives from API_BASE_URL', () {
      final byRule = build();
      expect(byRule['API_BASE_URL']!.url, api);
      expect(byRule['API_BASE_URL']!.service, ServiceClassifier.gatewayService);
      expect(byRule['API_BASE_URL + /micro-coaching']!.url,
          '$api/micro-coaching');
      expect(byRule['API_BASE_URL + /admin-api']!.url, '$api/admin-api');
      expect(byRule['API_BASE_URL + /admin-api']!.service, 'admin-api');
      expect(byRule['coaching URL + /medtronics-api/']!.url,
          '$api/micro-coaching/medtronics-api/');
      expect(byRule['coaching URL + /medtronics-api/']!.service,
          'micro-coaching');
    });

    test('every endpoint has a non-empty rule and service', () {
      for (final e in AppConfig.buildEndpoints(apiBaseUrl: api)) {
        expect(e.rule, isNotEmpty);
        expect(e.service, isNotEmpty);
      }
    });

    test('trailing slash on the base is normalised', () {
      final byRule = build(apiBaseUrl: '$api/');
      expect(byRule['API_BASE_URL + /admin-api']!.url, '$api/admin-api');
    });
  });

  group('buildEndpoints overrides', () {
    test('explicit coaching URL', () {
      final byRule = build(coachingExplicit: 'https://coach.example.test');
      expect(byRule['COACHING_SERVICE_URL']!.url, 'https://coach.example.test');
      expect(byRule['coaching URL + /medtronics-api/']!.url,
          'https://coach.example.test/medtronics-api/');
    });

    test('AI_SERVICE_URL drives every AI row', () {
      final list = AppConfig.buildEndpoints(
        apiBaseUrl: api,
        aiServiceBaseUrl: 'https://ai.example.test',
        scribeExplicit: 'https://legacy.example.test',
      );
      final ai = list.where((e) => e.service == 'ai-scribe').toList();
      expect(ai, isNotEmpty);
      for (final e in ai) {
        expect(e.url, 'https://ai.example.test');
        expect(e.rule, 'AI_SERVICE_URL');
      }
    });

    test('SCRIBE_BASE_URL applies only to the scribe row', () {
      final byRule = build(scribeExplicit: 'https://legacy.example.test');
      expect(byRule['SCRIBE_BASE_URL']!.url, 'https://legacy.example.test');
    });

    test('local Frappe overrides are used verbatim', () {
      final byRule = build(
        shukheeLocal: 'http://127.0.0.1:8000',
        spiceNextCoreLocal: 'http://127.0.0.1:8001',
        spiceNextAiLocal: 'http://127.0.0.1:8081',
      );
      expect(byRule['SHUKHEE_API_BASE_URL']!.url, 'http://127.0.0.1:8000');
      expect(byRule['SPICE_NEXT_CORE_API_BASE_URL']!.url,
          'http://127.0.0.1:8001');
      expect(byRule['SPICE_NEXT_AI_API_BASE_URL']!.url, 'http://127.0.0.1:8081');
    });
  });

  group('getters keep their values under the default empty defines', () {
    test('coachingServiceUrl', () {
      expect(AppConfig.coachingServiceUrl,
          AppConfig.joinUrlSegment(AppConfig.apiBaseUrl, 'micro-coaching'));
    });
    test('scribe, assistant and app-version fall back to the API base', () {
      expect(AppConfig.scribeBaseUrl, AppConfig.apiBaseUrl);
      expect(AppConfig.assistantBaseUrl, AppConfig.apiBaseUrl);
      expect(AppConfig.appVersionCheckBaseUrl, AppConfig.apiBaseUrl);
    });
    test('Frappe bases join admin-api', () {
      final expected = AppConfig.joinUrlSegment(AppConfig.apiBaseUrl, 'admin-api');
      expect(AppConfig.shukheeApiBaseUrl, expected);
      expect(AppConfig.spiceNextCoreApiBaseUrl, expected);
      expect(AppConfig.spiceNextAiApiBaseUrl, expected);
    });
    test('joinUrlSegment handles a trailing slash', () {
      expect(AppConfig.joinUrlSegment('$api/', 'x'), '$api/x');
      expect(AppConfig.joinUrlSegment(api, 'x'), '$api/x');
    });
  });

  test('configuredEndpoints matches the real getters and has no secret', () {
    final urls = AppConfig.configuredEndpoints.map((e) => e.url).toList();
    expect(urls, contains(AppConfig.coachingServiceUrl));
    expect(urls, contains(AppConfig.shukheeApiBaseUrl));
    expect(urls,
        contains(MicroCoachingService.sdkBaseUrl(AppConfig.coachingServiceUrl)));
    final secrets = [AppConfig.hfToken, AppConfig.passwordHashKey]
        .where((s) => s.isNotEmpty);
    for (final e in AppConfig.configuredEndpoints) {
      for (final s in secrets) {
        expect(e.url.contains(s) || e.rule.contains(s), isFalse);
      }
    }
  });

  test('sdkBaseUrl normalises the slash and appends medtronics-api', () {
    expect(MicroCoachingService.sdkBaseUrl('$api/micro-coaching'),
        '$api/micro-coaching/medtronics-api/');
    expect(MicroCoachingService.sdkBaseUrl('$api/medtronics-api/'),
        '$api/medtronics-api/');
  });
}
