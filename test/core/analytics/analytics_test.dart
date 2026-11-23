import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/analytics/analytics.dart';
import 'package:uhis_next/core/analytics/analytics_events.dart';
import 'package:uhis_next/core/analytics/analytics_route_observer.dart';

class _FakeSink implements AnalyticsSink {
  final events = <(String, Map<String, Object>)>[];
  final screens = <String>[];
  final userIds = <String?>[];
  final props = <String, String?>{};

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async =>
      events.add((name, params));

  @override
  Future<void> logScreen(String screenName, String? screenClass) async =>
      screens.add(screenName);

  @override
  Future<void> setUserId(String? id) async => userIds.add(id);

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      props[name] = value;
}

class _ThrowingSink extends _FakeSink {
  @override
  Future<void> logEvent(String name, Map<String, Object> params) =>
      Future.error(StateError('boom'));
}

void main() {
  late _FakeSink sink;

  setUp(() {
    sink = _FakeSink();
    Analytics.sink = sink;
  });

  tearDown(() => Analytics.sink = null);

  group('Analytics', () {
    test('drops everything when no sink (Firebase off)', () {
      Analytics.sink = null;
      Analytics.event('login', {'result': 'success'});
      Analytics.screen('dashboard');
      expect(Analytics.isEnabled, isFalse);
      expect(sink.events, isEmpty);
      expect(sink.screens, isEmpty);
    });

    test('init without Firebase leaves analytics off and does not throw',
        () async {
      Analytics.sink = null;
      await Analytics.init();
      expect(Analytics.isEnabled, isFalse);
    });

    test('event params: nulls dropped, bools as strings, strings capped', () {
      Analytics.event('x', {
        'a': null,
        'b': true,
        'c': 42,
        'd': 'y' * 150,
      });
      final params = sink.events.single.$2;
      expect(params.containsKey('a'), isFalse);
      expect(params['b'], 'true');
      expect(params['c'], 42);
      expect((params['d']! as String).length, Analytics.maxValueLength);
    });

    test('a failing sink never throws into the caller', () async {
      Analytics.sink = _ThrowingSink();
      expect(() => Analytics.event('x'), returnsNormally);
      await pumpEventQueue();
    });

    test('screen ignores back-to-back repeats only', () {
      Analytics.screen('dashboard');
      Analytics.screen('dashboard');
      Analytics.screen('patient_profile');
      Analytics.screen('dashboard');
      expect(sink.screens, ['dashboard', 'patient_profile', 'dashboard']);
    });

    test('gaUserId is tenant-userId, never anything else', () {
      expect(Analytics.gaUserId(tenantId: '5', userId: 402), '5-402');
      expect(Analytics.gaUserId(tenantId: null, userId: 402), '402');
      expect(Analytics.gaUserId(tenantId: ' ', userId: 402), '402');
      expect(Analytics.gaUserId(tenantId: '5', userId: null), isNull);
    });

    test('setUser sets id + properties; clearUser removes them', () async {
      await Analytics.setUser(
        tenantId: '5',
        userId: 402,
        upazila: 'Kalihati',
        unionArea: 'Paikora',
        appLanguage: 'bn',
      );
      expect(sink.userIds.last, '5-402');
      expect(sink.props[AnalyticsUserProperty.upazila], 'Kalihati');
      expect(sink.props[AnalyticsUserProperty.unionArea], 'Paikora');
      expect(sink.props[AnalyticsUserProperty.appLanguage], 'bn');
      expect(sink.props[AnalyticsUserProperty.appFlavor], 'prod');

      await Analytics.clearUser();
      expect(sink.userIds.last, isNull);
      expect(sink.props[AnalyticsUserProperty.upazila], isNull);
    });

    test('failureReason maps errors to fixed labels', () {
      final req = RequestOptions(path: '/x');
      DioException dio(DioExceptionType t, [int? code]) => DioException(
            requestOptions: req,
            type: t,
            response: code == null
                ? null
                : Response(requestOptions: req, statusCode: code),
          );
      expect(Analytics.failureReason(dio(DioExceptionType.connectionTimeout)),
          AnalyticsValue.timeout);
      expect(Analytics.failureReason(dio(DioExceptionType.connectionError)),
          AnalyticsValue.offline);
      // 401/403 is only "wrong credentials" on login; elsewhere unauthorized.
      expect(Analytics.failureReason(dio(DioExceptionType.badResponse, 401)),
          AnalyticsValue.unauthorized);
      expect(
          Analytics.failureReason(dio(DioExceptionType.badResponse, 403),
              login: true),
          AnalyticsValue.wrongCredentials);
      expect(Analytics.failureReason(dio(DioExceptionType.badResponse, 503)),
          AnalyticsValue.serverError);
      expect(Analytics.failureReason(TimeoutException('t')),
          AnalyticsValue.timeout);
      expect(Analytics.failureReason(StateError('secret text')),
          AnalyticsValue.other);
    });

    test('user properties are capped at GA4\'s 36 characters', () async {
      final sink = _FakeSink();
      Analytics.sink = sink;
      final long = 'U' * 50;
      await Analytics.setUser(
          tenantId: '11', userId: 44, upazila: long, unionArea: long);
      expect(sink.props[AnalyticsUserProperty.upazila]!.length, 36);
      expect(sink.props[AnalyticsUserProperty.unionArea]!.length, 36);
      expect(Analytics.capUserProperty('short'), 'short');
      expect(Analytics.capUserProperty(null), isNull);
      Analytics.sink = null;
    });

    test('union_area label: one union, several, none', () {
      expect(Analytics.unionAreaLabel(['Kundapukur']), 'Kundapukur');
      expect(Analytics.unionAreaLabel(['Tupamari', 'Kundapukur', ' ', 'Tupamari']),
          'Kundapukur +1');
      expect(Analytics.unionAreaLabel(const []), isNull);
    });

    test('visit step 2 screen names are snake_case', () {
      expect(AnalyticsScreen.visitStep2Form('ncd'), 'visit_step2_ncd');
      expect(AnalyticsScreen.visitStep2Form('familyPlanning'),
          'visit_step2_family_planning');
    });
  });

  group('AnalyticsRouteObserver.screenNameFor', () {
    test('maps known routes', () {
      expect(AnalyticsRouteObserver.screenNameFor('/home'), 'dashboard');
      expect(AnalyticsRouteObserver.screenNameFor(':id'), 'patient_profile');
      expect(AnalyticsRouteObserver.screenNameFor('household/:id'),
          'household_detail');
      expect(AnalyticsRouteObserver.screenNameFor('household_create'),
          'household_create');
    });

    test('never leaks path parameters and normalises names', () {
      expect(AnalyticsRouteObserver.screenNameFor('/patients/visit/:visitId/flow'),
          'patients_visit_flow');
      expect(AnalyticsRouteObserver.screenNameFor('telemetry-report'),
          'telemetry_report');
    });

    test('skips unnamed routes', () {
      expect(AnalyticsRouteObserver.screenNameFor(null), isNull);
      expect(AnalyticsRouteObserver.screenNameFor(''), isNull);
    });
  });

  testWidgets('observer logs pushed and revealed named pages, not sheets',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      navigatorObservers: [AnalyticsRouteObserver()],
      onGenerateRoute: (s) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/home'),
        builder: (_) => const Text('home'),
      ),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'settings'),
      builder: (_) => const Text('settings'),
    ));
    await tester.pumpAndSettle();
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Text('unnamed'),
    ));
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
      context: navKey.currentContext!,
      builder: (_) => const Text('dialog'),
    ));
    await tester.pumpAndSettle();
    navKey.currentState!.pop(); // dialog
    await tester.pumpAndSettle();
    navKey.currentState!.pop(); // unnamed
    await tester.pumpAndSettle();
    navKey.currentState!.pop(); // settings → home revealed
    await tester.pumpAndSettle();

    expect(sink.screens, ['dashboard', 'settings', 'dashboard']);
  });
}
