import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/config/app_config.dart';
import 'package:uhis_next/core/net_log/service_classifier.dart';
import 'package:uhis_next/core/services/micro_coaching_service.dart';

void main() {
  const api = 'https://api.example.test';

  List<ConfiguredEndpoint> build({
    String apiBaseUrl = api,
    String coachingExplicit = '',
    String aiServiceBaseUrl = '',
    String scribeExplicit = '',
    String shukheeLocal = '',
    String spiceNextCoreLocal = '',
    String spiceNextAiLocal = '',
  }) => AppConfig.buildEndpoints(
    apiBaseUrl: apiBaseUrl,
    coachingExplicit: coachingExplicit,
    aiServiceBaseUrl: aiServiceBaseUrl,
    scribeExplicit: scribeExplicit,
    shukheeLocal: shukheeLocal,
    spiceNextCoreLocal: spiceNextCoreLocal,
    spiceNextAiLocal: spiceNextAiLocal,
  );

  ConfiguredEndpoint find(
    List<ConfiguredEndpoint> rows,
    String service,
    String rule,
  ) {
    final matches = rows
        .where((e) => e.service == service && e.rule == rule)
        .toList();
    expect(matches, isNotEmpty, reason: 'no row $service / $rule');
    return matches.first;
  }

  group('buildEndpoints defaults', () {
    test('derives from API_BASE_URL', () {
      final rows = build();
      expect(
        find(rows, ServiceClassifier.gatewayService, 'API_BASE_URL').url,
        api,
      );
      expect(
        find(rows, 'micro-coaching', 'API_BASE_URL + /micro-coaching').url,
        '$api/micro-coaching',
      );
      expect(
        find(rows, 'admin-api', 'API_BASE_URL + /admin-api').url,
        '$api/admin-api',
      );
      expect(
        find(rows, 'micro-coaching', 'coaching URL + /medtronics-api/').url,
        '$api/micro-coaching/medtronics-api/',
      );
    });

    test('every endpoint has a non-empty rule and service', () {
      for (final e in AppConfig.buildEndpoints(apiBaseUrl: api)) {
        expect(e.rule, isNotEmpty);
        expect(e.service, isNotEmpty);
      }
    });

    test('trailing slash on the base is normalised', () {
      final rows = build(apiBaseUrl: '$api/');
      expect(
        find(rows, 'admin-api', 'API_BASE_URL + /admin-api').url,
        '$api/admin-api',
      );
    });
  });

  group('buildEndpoints overrides', () {
    test('explicit coaching URL', () {
      final rows = build(coachingExplicit: 'https://coach.example.test');
      expect(
        find(rows, 'micro-coaching', 'COACHING_SERVICE_URL').url,
        'https://coach.example.test',
      );
      expect(
        find(rows, 'micro-coaching', 'coaching URL + /medtronics-api/').url,
        'https://coach.example.test/medtronics-api/',
      );
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
      final rows = build(scribeExplicit: 'https://legacy.example.test');
      final ai = rows.where((e) => e.service == 'ai-scribe').toList();
      expect(ai.map((e) => e.rule), ['SCRIBE_BASE_URL', 'API_BASE_URL']);
      expect(ai.first.url, 'https://legacy.example.test');
      expect(ai.last.url, api);
    });

    test('local Frappe overrides are used verbatim', () {
      final rows = build(
        shukheeLocal: 'http://127.0.0.1:8000',
        spiceNextCoreLocal: 'http://127.0.0.1:8001',
        spiceNextAiLocal: 'http://127.0.0.1:8081',
      );
      expect(
        find(rows, 'admin-api', 'SHUKHEE_API_BASE_URL').url,
        'http://127.0.0.1:8000',
      );
      expect(
        find(rows, 'admin-api', 'SPICE_NEXT_CORE_API_BASE_URL').url,
        'http://127.0.0.1:8001',
      );
      expect(
        find(rows, 'admin-api', 'SPICE_NEXT_AI_API_BASE_URL').url,
        'http://127.0.0.1:8081',
      );
    });
  });

  group('buildEndpoints with no overrides derives every row from the API base', () {
    test('coaching joins micro-coaching', () {
      expect(
        find(build(), 'micro-coaching', 'API_BASE_URL + /micro-coaching').url,
        AppConfig.joinUrlSegment(api, 'micro-coaching'),
      );
    });
    test('scribe and assistant rows fall back to the API base', () {
      final ai = build().where((e) => e.service == 'ai-scribe').toList();
      expect(ai, isNotEmpty);
      for (final e in ai) {
        expect(e.url, api);
      }
    });
    test('Frappe rows join admin-api', () {
      final frappe = build().where((e) => e.service == 'admin-api').toList();
      expect(frappe, hasLength(3));
      for (final e in frappe) {
        expect(e.url, AppConfig.joinUrlSegment(api, 'admin-api'));
      }
    });
    test('joinUrlSegment handles a trailing slash', () {
      expect(AppConfig.joinUrlSegment('$api/', 'x'), '$api/x');
      expect(AppConfig.joinUrlSegment(api, 'x'), '$api/x');
    });
  });

  test('configuredEndpoints carries the URL getters', () {
    final urls = AppConfig.configuredEndpoints.map((e) => e.url).toList();
    expect(urls, contains(AppConfig.coachingServiceUrl));
    expect(urls, contains(AppConfig.shukheeApiBaseUrl));
    expect(
      urls,
      contains(MicroCoachingService.sdkBaseUrl(AppConfig.coachingServiceUrl)),
    );
  });

  test('no endpoint url carries userinfo or a query', () {
    final rows = build(
      coachingExplicit: 'https://coach.example.test',
      aiServiceBaseUrl: 'https://ai.example.test',
      scribeExplicit: 'https://legacy.example.test',
      shukheeLocal: 'http://127.0.0.1:8000',
      spiceNextCoreLocal: 'http://127.0.0.1:8001',
      spiceNextAiLocal: 'http://127.0.0.1:8081',
    );
    expect(rows, isNotEmpty);
    for (final e in rows) {
      final uri = Uri.parse(e.url);
      expect(uri.userInfo, isEmpty, reason: e.rule);
      expect(uri.hasQuery, isFalse, reason: e.rule);
    }
  });

  test('sdkBaseUrl normalises the slash and appends medtronics-api', () {
    expect(
      MicroCoachingService.sdkBaseUrl('$api/micro-coaching'),
      '$api/micro-coaching/medtronics-api/',
    );
    expect(
      MicroCoachingService.sdkBaseUrl('$api/medtronics-api/'),
      '$api/medtronics-api/',
    );
  });
}
