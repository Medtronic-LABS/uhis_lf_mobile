/// Widget tests for [TeleconsultConsentScreen] -- scoped to verifying the
/// consent-decision log fires on both Agree and Decline (via
/// [TeleconsultConsentLogService]), and that the fire-and-forget contract
/// holds: the SK is popped back off this screen immediately, without ever
/// awaiting the log call.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_dao.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_service.dart';
import 'package:uhis_next/core/theme/app_theme.dart';
import 'package:uhis_next/features/teleconsult/shukhee_consent_client.dart';
import 'package:uhis_next/features/teleconsult/teleconsult_consent_screen.dart';

/// One scripted response per call -- mirrors `shukhee_consent_client_test.dart`.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._response);

  final Future<ResponseBody> Function(RequestOptions) _response;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      _response(options);
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(bytes, 200, headers: {
    'content-type': ['application/json; charset=utf-8'],
  });
}

/// Builds a [ShukheeConsentClient] that always returns the given consent
/// copy without touching the network.
ShukheeConsentClient _fakeConsentClient({
  String lng = 'en',
  String html = '<p>Test consent copy</p>',
  String? version = '2',
  String? versionId = 'VER-2',
}) {
  final adapter = _ScriptedAdapter(
    (_) async => _jsonResponse({
      'message': {'lng': lng, 'consent': html, 'version': version, 'version_id': versionId},
    }),
  );
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter;
  return ShukheeConsentClient(
    baseUrl: 'https://example.test',
    authTokenProvider: () async => 'test-token',
    dio: dio,
  );
}

/// Records every [record] call. [blockOn], when set, makes the returned
/// future stay pending until the test completes it -- used to prove the
/// screen pops without ever awaiting this call (see
/// `TeleconsultConsentLogService.record`'s own "never throws, never blocks"
/// contract).
class _FakeConsentLogService extends TeleconsultConsentLogService {
  _FakeConsentLogService(TeleconsultConsentLogDao dao)
      : super(dao: dao, userIdResolver: () async => null);

  final List<Map<String, Object?>> calls = [];
  Completer<void>? blockOn;

  @override
  Future<void> record({
    required String patientId,
    String? visitId,
    required bool agreed,
    required String lng,
    String? consentVersion,
    String? versionId,
    String? patientDob,
    DateTime? occurredAt,
  }) async {
    calls.add({
      'patientId': patientId,
      'visitId': visitId,
      'agreed': agreed,
      'lng': lng,
      'consentVersion': consentVersion,
      'versionId': versionId,
      'patientDob': patientDob,
    });
    final gate = blockOn;
    if (gate != null) await gate.future;
  }
}

void main() {
  // Same "real but never-written-to" reasoning as teleconsult_screen_test.dart's
  // testDao -- the fake service overrides record() entirely, so this DAO is
  // never actually queried, only needed to satisfy the constructor's type.
  late final TeleconsultConsentLogDao testDao;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion, onCreate: AppDatabase.createSchema),
    );
    testDao = TeleconsultConsentLogDao(AppDatabase.forTesting(db));
  });

  /// Pumps [TeleconsultConsentScreen] pushed on top of a `/home` route (so
  /// `context.pop` has somewhere to land), wired to [logService] and
  /// [consentClientBuilder]. Returns the router and the push's result future.
  Future<(GoRouter, Future<TeleconsultConsentDecision?>)> pumpConsentScreen(
    WidgetTester tester, {
    required _FakeConsentLogService logService,
    required ShukheeConsentClient Function(BuildContext) consentClientBuilder,
    String patientId = 'patient-1',
    String? visitId,
    String? patientDob,
  }) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
        GoRoute(
          path: '/consent',
          builder: (context, _) => TeleconsultConsentScreen(
            patientId: patientId,
            visitId: visitId,
            patientDob: patientDob,
            consentClientBuilder: consentClientBuilder,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<TeleconsultConsentLogService>.value(value: logService),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light),
      ),
    );
    await tester.pump();
    final resultFuture = router.push<TeleconsultConsentDecision>('/consent');
    return (router, resultFuture);
  }

  testWidgets('tapping Agree logs an Agreed decision and pops true',
      (tester) async {
    final logService = _FakeConsentLogService(testDao);
    final (_, resultFuture) = await pumpConsentScreen(
      tester,
      logService: logService,
      consentClientBuilder: (_) =>
          _fakeConsentClient(lng: 'en', version: '2', versionId: 'VER-2'),
      patientId: 'patient-42',
      visitId: 'visit-7',
      patientDob: '1990-01-01',
    );
    await tester.pumpAndSettle();

    // Agree is disabled until the checkbox is ticked.
    await tester.tap(find.text(TeleconsultConsentStrings.checkboxLabel));
    await tester.pump();
    await tester.tap(find.text(TeleconsultConsentStrings.agreeButton));
    await tester.pumpAndSettle();

    final decision = await resultFuture;
    expect(decision?.agreed, isTrue);
    expect(decision?.version, '2');
    expect(decision?.versionId, 'VER-2');
    expect(decision?.lng, 'en');
    expect(find.text('home-route'), findsOneWidget);
    expect(logService.calls, hasLength(1));
    expect(logService.calls.single, {
      'patientId': 'patient-42',
      'visitId': 'visit-7',
      'agreed': true,
      'lng': 'en',
      'consentVersion': '2',
      'versionId': 'VER-2',
      'patientDob': '1990-01-01',
    });
  });

  testWidgets('tapping Decline logs a Declined decision and pops false',
      (tester) async {
    final logService = _FakeConsentLogService(testDao);
    final (_, resultFuture) = await pumpConsentScreen(
      tester,
      logService: logService,
      consentClientBuilder: (_) =>
          _fakeConsentClient(lng: 'bn', version: '3', versionId: 'VER-3'),
      patientId: 'patient-9',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(TeleconsultConsentStrings.declineButton));
    await tester.pumpAndSettle();

    final decision = await resultFuture;
    expect(decision?.agreed, isFalse);
    expect(decision?.version, '3');
    expect(decision?.versionId, 'VER-3');
    expect(decision?.lng, 'bn');
    expect(find.text('home-route'), findsOneWidget);
    expect(logService.calls, hasLength(1));
    expect(logService.calls.single['agreed'], isFalse);
    expect(logService.calls.single['lng'], 'bn');
    expect(logService.calls.single['consentVersion'], '3');
    expect(logService.calls.single['versionId'], 'VER-3');
  });

  testWidgets(
      'navigation pops immediately even while the log call is still in flight',
      (tester) async {
    final logService = _FakeConsentLogService(testDao)
      ..blockOn = Completer<void>();
    final (_, resultFuture) = await pumpConsentScreen(
      tester,
      logService: logService,
      consentClientBuilder: (_) => _fakeConsentClient(),
      patientId: 'patient-1',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(TeleconsultConsentStrings.declineButton));
    await tester.pumpAndSettle();

    // The screen already popped -- proven by the route stack landing back on
    // /home -- even though logService.record()'s future is still pending.
    expect(find.text('home-route'), findsOneWidget);
    final decision = await resultFuture;
    expect(decision?.agreed, isFalse);
    expect(logService.calls, hasLength(1));

    // Let the pending future resolve so it doesn't leak into another test.
    logService.blockOn!.complete();
    await tester.pumpAndSettle();
  });
}
