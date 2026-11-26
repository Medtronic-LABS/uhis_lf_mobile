import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/api/frappe_client.dart';
import 'package:uhis_next/core/api/scribe_api_service.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/user_hierarchy_service.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_log_interceptor.dart';
import 'package:uhis_next/core/net_log/network_request_recorder.dart';
import 'package:uhis_next/core/sync/call_log_sync_client.dart';
import 'package:uhis_next/core/sync/shukhee_encounter_link_client.dart';
import 'package:uhis_next/features/assistant/assistant_repository.dart';
import 'package:uhis_next/features/teleconsult/shukhee_consent_client.dart';

import '../api/scripted_adapter.dart';

class _FakeRecorder implements NetworkRequestRecorder {
  final List<NetworkLogEntry> entries = [];

  @override
  int get epoch => 1;

  @override
  void record(NetworkLogEntry e) => entries.add(e);
}

Dio _injectedDio(ScriptedAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;

/// The request outcome is irrelevant here; only the recorded row matters.
Future<void> _ignoreOutcome(Future<Object?> call) =>
    call.then<void>((_) {}, onError: (Object _) {});

void main() {
  late _FakeRecorder rec;
  late ScriptedAdapter adapter;

  setUp(() {
    rec = _FakeRecorder();
    adapter = ScriptedAdapter(const {});
  });

  void expectOneSanitisedRow({int status = 200}) {
    expect(rec.entries, hasLength(1));
    final e = rec.entries.single;
    expect(e.statusCode, status);
  }

  test('FrappeClient with an injected Dio records one row', () async {
    final client = FrappeClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'jwt',
      dio: _injectedDio(adapter),
      networkRecorder: rec,
    );

    await _ignoreOutcome(client.postJson('/api/method/x?token=abc', {}));

    expectOneSanitisedRow();
    expect(rec.entries.single.url, isNot(contains('token=abc')));
  });

  test('CallLogSyncClient with an injected Dio records one row', () async {
    final client = CallLogSyncClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'jwt',
      dio: _injectedDio(adapter),
      networkRecorder: rec,
    );

    await _ignoreOutcome(client.pull(cursor: 0));

    expectOneSanitisedRow();
    expect(rec.entries.single.url, contains(CallLogSyncClient.pullPath));
  });

  test(
    'ShukheeEncounterLinkClient with an injected Dio records one row',
    () async {
      final client = ShukheeEncounterLinkClient(
        baseUrl: 'https://example.test',
        authTokenProvider: () async => 'jwt',
        dio: _injectedDio(adapter),
        networkRecorder: rec,
      );

      await _ignoreOutcome(
        client.attachFhirEncounterId(callLog: 'CL-1', fhirEncounterId: 'E-1'),
      );

      expectOneSanitisedRow();
      expect(
        rec.entries.single.url,
        contains(ShukheeEncounterLinkClient.attachPath),
      );
    },
  );

  test('ShukheeConsentClient with an injected Dio records one row', () async {
    final client = ShukheeConsentClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'jwt',
      dio: _injectedDio(adapter),
      networkRecorder: rec,
    );

    await _ignoreOutcome(client.fetchConsent(lng: 'en'));

    expectOneSanitisedRow();
    expect(rec.entries.single.url, contains(ShukheeConsentClient.consentPath));
  });

  test(
    'ScribeApiService records its call through the ApiClient recorder',
    () async {
      final api = await ApiClient.create(networkRecorder: rec);
      final service = ScribeApiService(api, httpAdapter: adapter);

      await _ignoreOutcome(service.pollResult('job-1'));

      expectOneSanitisedRow();
    },
  );

  test('ScribeApiService attaches the log after its auth interceptor',
      () async {
    final api = await ApiClient.create(networkRecorder: rec);
    final service = ScribeApiService(api, httpAdapter: adapter);

    expect(service.dio.interceptors.last, isA<NetworkLogInterceptor>());
  });

  test('UserHierarchyService records the get_controls 404', () async {
    final api = await ApiClient.create(networkRecorder: rec);
    api.importAuthToken('Bearer jwt');
    adapter.successStatus = 404;
    final service = UserHierarchyService(
      api,
      AuthRepository(api),
      httpAdapter: adapter,
      shukheeBaseUrl: 'https://example.test/admin-api',
    );

    await service.refreshShukheeControls();

    expectOneSanitisedRow(status: 404);
    expect(rec.entries.single.method, 'POST');
  });

  test('UserHierarchyService records the feature-flag fetch', () async {
    final api = await ApiClient.create(networkRecorder: rec);
    final service = UserHierarchyService(
      api,
      AuthRepository(api),
      httpAdapter: adapter,
    );

    await service.refreshFeatureFlags();

    expectOneSanitisedRow();
    expect(rec.entries.single.method, 'GET');
  });

  test('AssistantRepository coaching RAG call records one row', () async {
    final api = await ApiClient.create(networkRecorder: rec);
    final repo = AssistantRepository(
      api,
      httpAdapter: adapter,
      coachingBaseUrl: 'https://example.test',
    );

    await _ignoreOutcome(repo.ask('what is hypertension'));

    expectOneSanitisedRow();
  });
}
