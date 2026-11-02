/// Widget tests for [TeleconsultConsentScreen] -- scoped to verifying: on
/// Agree, the popped [TeleconsultConsentDecision] carries the right
/// version/lng/itemsChecked (no network call fires here at all -- the
/// decision is sent later, bundled into the booking call); on Decline, the
/// immediate [ShukheeConsentClient.recordDecline] POST fires with the right
/// body and the SK is popped back off this screen immediately, without ever
/// awaiting it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/theme/app_theme.dart';
import 'package:uhis_next/features/teleconsult/shukhee_consent_client.dart';
import 'package:uhis_next/features/teleconsult/teleconsult_consent_screen.dart';

/// Branches on request path -- the same [ShukheeConsentClient] instance is
/// used for both the consent-content fetch and (on Decline) the
/// `recordDecline` POST, exactly as production wiring does (see
/// `TeleconsultConsentScreen._decide`).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({required this.consentResponse});

  final Future<ResponseBody> Function(RequestOptions) consentResponse;

  /// Set to stall the decline POST's response until [declineGate] completes
  /// -- proves the screen pops without ever awaiting it.
  Completer<void>? declineGate;

  final List<RequestOptions> declineRequests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == ShukheeConsentClient.declinePath) {
      declineRequests.add(options);
      final gate = declineGate;
      if (gate != null) await gate.future;
      return _jsonResponse({
        'message': {'logged': true},
      });
    }
    return consentResponse(options);
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(bytes, 200, headers: {
    'content-type': ['application/json; charset=utf-8'],
  });
}

void main() {
  /// Builds a [ShukheeConsentClient] wired to [adapter] -- always returns the
  /// given consent copy for the content fetch, and (for Decline tests)
  /// branches to a `logged: true` response for `recordDecline` via the same
  /// adapter.
  ShukheeConsentClient fakeConsentClient(
    _ScriptedAdapter adapter, {
    String lng = 'en',
    String html = '<p>Test consent copy</p>',
    String? version = '2',
    String? versionId = 'VER-2',
    List<Map<String, Object?>> items = const [],
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    return ShukheeConsentClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'test-token',
      dio: dio,
    );
  }

  _ScriptedAdapter consentAdapter({
    String lng = 'en',
    String html = '<p>Test consent copy</p>',
    String? version = '2',
    String? versionId = 'VER-2',
    List<Map<String, Object?>> items = const [],
  }) =>
      _ScriptedAdapter(
        consentResponse: (_) async => _jsonResponse({
          'message': {
            'lng': lng,
            'consent': html,
            'version': version,
            'version_id': versionId,
            'items': items,
          },
        }),
      );

  /// Pumps [TeleconsultConsentScreen] pushed on top of a `/home` route (so
  /// `context.pop` has somewhere to land). Returns the router and the push's
  /// result future.
  Future<(GoRouter, Future<TeleconsultConsentDecision?>)> pumpConsentScreen(
    WidgetTester tester, {
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
      MaterialApp.router(routerConfig: router, theme: AppTheme.light),
    );
    await tester.pump();
    final resultFuture = router.push<TeleconsultConsentDecision>('/consent');
    return (router, resultFuture);
  }

  testWidgets(
      'tapping Agree with no consent items pops true with no network call for the decision',
      (tester) async {
    final adapter = consentAdapter(lng: 'en', version: '2', versionId: 'VER-2');
    final (_, resultFuture) = await pumpConsentScreen(
      tester,
      consentClientBuilder: (_) => fakeConsentClient(adapter),
      patientId: 'patient-42',
      visitId: 'visit-7',
      patientDob: '1990-01-01',
    );
    await tester.pumpAndSettle();

    // No items configured -- Agree is enabled immediately, nothing to tick.
    await tester.tap(find.text(TeleconsultConsentStrings.agreeButton));
    await tester.pumpAndSettle();

    final decision = await resultFuture;
    expect(decision?.agreed, isTrue);
    expect(decision?.version, '2');
    expect(decision?.versionId, 'VER-2');
    expect(decision?.lng, 'en');
    expect(decision?.itemsChecked, isNull);
    expect(find.text('home-route'), findsOneWidget);
    // Agree never posts to recordDecline -- there's no Call Logs row yet to
    // record anything against; the decision rides along in the booking call
    // instead (see TeleconsultScreen._submitBooking).
    expect(adapter.declineRequests, isEmpty);
  });

  testWidgets(
      'Agree stays disabled until the mandatory item is ticked; optional item never blocks it',
      (tester) async {
    final adapter = consentAdapter(items: [
      {'description': 'Mandatory item', 'mandatory': true},
      {'description': 'Optional item', 'mandatory': false},
    ]);
    final (_, resultFuture) = await pumpConsentScreen(
      tester,
      consentClientBuilder: (_) => fakeConsentClient(adapter),
      patientId: 'patient-1',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Mandatory item', findRichText: true), findsOneWidget);
    expect(find.textContaining('Optional item', findRichText: true), findsOneWidget);

    // Agree is disabled while the mandatory item is unticked -- tapping it
    // (via the FilledButton having a null onPressed) must be a no-op.
    await tester.tap(find.text(TeleconsultConsentStrings.agreeButton));
    await tester.pumpAndSettle();
    expect(find.text('home-route'), findsNothing);

    // Ticking only the optional item still doesn't unlock Agree.
    await tester.tap(find.textContaining('Optional item', findRichText: true));
    await tester.pump();
    await tester.tap(find.text(TeleconsultConsentStrings.agreeButton));
    await tester.pumpAndSettle();
    expect(find.text('home-route'), findsNothing);

    // Ticking the mandatory item too unlocks Agree.
    await tester.tap(find.textContaining('Mandatory item', findRichText: true));
    await tester.pump();
    await tester.tap(find.text(TeleconsultConsentStrings.agreeButton));
    await tester.pumpAndSettle();

    final decision = await resultFuture;
    expect(decision?.agreed, isTrue);
    expect(find.text('home-route'), findsOneWidget);
    expect(decision?.itemsChecked, [true, true]);
  });

  testWidgets('tapping Decline posts recordDecline and pops false', (tester) async {
    final adapter = consentAdapter(lng: 'bn', version: '3', versionId: 'VER-3');
    final (_, resultFuture) = await pumpConsentScreen(
      tester,
      consentClientBuilder: (_) => fakeConsentClient(adapter),
      patientId: 'patient-9',
      visitId: 'visit-9',
      patientDob: '1985-05-05',
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

    expect(adapter.declineRequests, hasLength(1));
    final sent = adapter.declineRequests.single.data as Map<String, dynamic>;
    expect(sent, {
      'patient_id': 'patient-9',
      'visit_id': 'visit-9',
      'lng': 'bn',
      'version_id': 'VER-3',
      'patient_dob': '1985-05-05',
    });
  });

  testWidgets(
      'navigation pops immediately even while the recordDecline call is still in flight',
      (tester) async {
    final adapter = consentAdapter()..declineGate = Completer<void>();
    final (_, resultFuture) = await pumpConsentScreen(
      tester,
      consentClientBuilder: (_) => fakeConsentClient(adapter),
      patientId: 'patient-1',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(TeleconsultConsentStrings.declineButton));
    await tester.pumpAndSettle();

    // The screen already popped -- proven by the route stack landing back on
    // /home -- even though the recordDecline POST is still pending.
    expect(find.text('home-route'), findsOneWidget);
    final decision = await resultFuture;
    expect(decision?.agreed, isFalse);
    expect(adapter.declineRequests, hasLength(1));

    // Let the pending request resolve so it doesn't leak into another test.
    adapter.declineGate!.complete();
    await tester.pumpAndSettle();
  });
}
