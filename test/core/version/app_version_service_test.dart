import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/api/endpoints.dart';
import 'package:uhis_next/core/version/app_version_service.dart';

class _MemoryStore implements AppVersionPolicyStore {
  AppVersionPolicy? policy;

  @override
  Future<AppVersionPolicy?> read() async => policy;

  @override
  Future<void> write(AppVersionPolicy p) async => policy = p;
}

AppVersionPolicy _policy({
  int min = 7,
  int latest = 9,
  bool exempt = false,
}) =>
    AppVersionPolicy(
      minAppVersionCode: min,
      minAppVersionLabel: 'v1.0.$min',
      latestAppVersionCode: latest,
      latestAppVersionLabel: 'v1.0.$latest',
      versionCheckExempt: exempt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  setUpAll(() async => api = await ApiClient.create());
  setUp(AppVersionService.invalidateSessionCache);

  AppVersionService service({
    required int installed,
    required _MemoryStore store,
    AppVersionPolicy? Function()? server,
  }) =>
      AppVersionService(
        api,
        store: store,
        installedVersionCode: () => installed,
        fetchPolicy: () async {
          final p = server?.call();
          if (p == null) throw Exception('offline');
          return p;
        },
      );

  test('checkUrl uses gateway or direct mobile path', () {
    final url = AppVersionService.checkUrl();
    expect(
      url.endsWith(Endpoints.mobileAppVersionGateway) ||
          url.endsWith(Endpoints.mobileAppVersionDirect),
      isTrue,
    );
  });

  group('AppVersionPolicy.evaluate', () {
    test('below minimum → update required with the min label', () {
      final r = _policy().evaluate(6);
      expect(r, isA<AppVersionUpdateRequired>());
      expect((r as AppVersionUpdateRequired).minVersionLabel, 'v1.0.7');
    });

    test('between minimum and latest → optional update', () {
      final r = _policy().evaluate(8);
      expect(r, isA<AppVersionUpdateAvailable>());
      expect((r as AppVersionUpdateAvailable).latestVersionLabel, 'v1.0.9');
    });

    test('at or above latest → up to date', () {
      expect(_policy().evaluate(9), isA<AppVersionUpToDate>());
      expect(_policy().evaluate(10), isA<AppVersionUpToDate>());
    });

    test('exempt user is never blocked', () {
      expect(_policy(exempt: true).evaluate(1), isA<AppVersionUpToDate>());
    });

    test('unknown installed code never blocks', () {
      expect(_policy().evaluate(0), isA<AppVersionUpToDate>());
    });
  });

  group('AppVersionPolicy.fromJson', () {
    test('parses the leapfrog-ai-service body', () {
      final p = AppVersionPolicy.fromJson({
        'status': true,
        'minAppVersionCode': 14,
        'minAppVersionLabel': '1.1.0',
        'latestAppVersionCode': '15',
        'latestAppVersionLabel': '1.1.1',
        'versionCheckExempt': false,
      })!;
      expect(p.minAppVersionCode, 14);
      expect(p.latestAppVersionCode, 15);
      expect(p.latestAppVersionLabel, '1.1.1');
    });

    test('missing minimum → null (never blocks on an unreadable policy)', () {
      expect(AppVersionPolicy.fromJson({'message': 'x'}), isNull);
      expect(AppVersionPolicy.fromJson('nope'), isNull);
    });

    test('latest defaults to minimum when absent', () {
      final p = AppVersionPolicy.fromJson({'minAppVersionCode': 5})!;
      expect(p.latestAppVersionCode, 5);
    });
  });

  group('AppVersionService.check', () {
    test('fetches, caches and evaluates the server policy', () async {
      final store = _MemoryStore();
      final s = service(installed: 6, store: store, server: _policy);

      expect(await s.check(), isA<AppVersionUpdateRequired>());
      expect(store.policy?.minAppVersionCode, 7);
    });

    test('offline falls back to the cached policy', () async {
      final store = _MemoryStore()..policy = _policy();
      final s = service(installed: 6, store: store);

      expect(await s.check(), isA<AppVersionUpdateRequired>());
    });

    test('offline with nothing cached → check failed', () async {
      final s = service(installed: 6, store: _MemoryStore());
      expect(await s.check(), isA<AppVersionCheckFailed>());
    });

    test('optional update sets the one-time prompt flag', () async {
      final s = service(installed: 8, store: _MemoryStore(), server: _policy);

      await s.check();
      expect(AppVersionService.needsOptionalPrompt, isTrue);
      expect(AppVersionService.optionalUpdateLabel, 'v1.0.9');

      AppVersionService.markOptionalPromptShown();
      expect(AppVersionService.needsOptionalPrompt, isFalse);

      AppVersionService.invalidateSessionCache();
      expect(AppVersionService.needsOptionalPrompt, isFalse);
    });
  });

  group('AppVersionService.cachedResult', () {
    test('uses the cache only — no policy means up to date', () async {
      var fetched = false;
      final s = AppVersionService(
        api,
        store: _MemoryStore(),
        installedVersionCode: () => 1,
        fetchPolicy: () async {
          fetched = true;
          return _policy();
        },
      );
      expect(await s.cachedResult(), isA<AppVersionUpToDate>());
      expect(fetched, isFalse);
    });

    test('enforces a cached minimum without the network', () async {
      final store = _MemoryStore()..policy = _policy();
      final s = service(installed: 6, store: store);
      expect(await s.cachedResult(), isA<AppVersionUpdateRequired>());
    });
  });
}
