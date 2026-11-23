import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/analytics/analytics.dart';
import 'package:uhis_next/core/analytics/analytics_events.dart';
import 'package:uhis_next/core/analytics/enrollment_analytics.dart';

class _Sink implements AnalyticsSink {
  final events = <(String, Map<String, Object>)>[];

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async =>
      events.add((name, params));
  @override
  Future<void> logScreen(String screenName, String? screenClass) async {}
  @override
  Future<void> setUserId(String? id) async {}
  @override
  Future<void> setUserProperty(String name, String? value) async {}

  List<Map<String, Object>> named(String name) =>
      [for (final e in events) if (e.$1 == name) e.$2];
}

void main() {
  late _Sink sink;
  late int now;
  int clock() => now;

  setUp(() {
    sink = _Sink();
    Analytics.sink = sink;
    now = 1000;
  });
  tearDown(() => Analytics.sink = null);

  group('GaNidScan', () {
    test('success after a failed read: one event, success wins', () {
      final scan = GaNidScan(AnalyticsValue.fab, clock: clock)
        ..attempt(
            method: AnalyticsValue.camera,
            success: false,
            failureReason: AnalyticsValue.notFound)
        ..attempt(
            method: AnalyticsValue.gallery, success: true, fieldsFilled: 3)
        ..existingPatient(true);
      now = 9000;
      scan
        ..finish()
        ..finish(); // second call ignored

      final e = sink.named(AnalyticsEvent.nidScanResult).single;
      expect(e[AnalyticsParam.source], AnalyticsValue.fab);
      expect(e[AnalyticsParam.result], AnalyticsValue.success);
      expect(e.containsKey(AnalyticsParam.failureReason), isFalse);
      expect(e[AnalyticsParam.method], AnalyticsValue.gallery);
      expect(e[AnalyticsParam.attempts], 2);
      expect(e[AnalyticsParam.fieldsFilled], 3);
      expect(e[AnalyticsParam.existingPatient], 'true');
      expect(e[AnalyticsParam.scanMs], 8000);
    });

    test('only failed reads → failed with the last reason', () {
      GaNidScan(AnalyticsValue.addMember, clock: clock)
        ..attempt(
            method: AnalyticsValue.camera,
            success: false,
            failureReason: AnalyticsValue.notFound)
        ..attempt(
            method: AnalyticsValue.camera,
            success: false,
            failureReason: AnalyticsValue.error)
        ..finish();
      final e = sink.named(AnalyticsEvent.nidScanResult).single;
      expect(e[AnalyticsParam.result], AnalyticsValue.failed);
      expect(e[AnalyticsParam.failureReason], AnalyticsValue.error);
      expect(e.containsKey(AnalyticsParam.fieldsFilled), isFalse);
      expect(e.containsKey(AnalyticsParam.existingPatient), isFalse);
    });

    test('closed without reading → cancelled, zero attempts', () {
      GaNidScan(AnalyticsValue.householdDetail, clock: clock).finish();
      final e = sink.named(AnalyticsEvent.nidScanResult).single;
      expect(e[AnalyticsParam.result], AnalyticsValue.cancelled);
      expect(e[AnalyticsParam.attempts], 0);
      expect(e.containsKey(AnalyticsParam.method), isFalse);
    });

    test('lookup that could not run reports unknown', () {
      final scan = GaNidScan(AnalyticsValue.searchScan, clock: clock)
        ..attempt(method: AnalyticsValue.camera, success: true, fieldsFilled: 4)
        ..existingPatient(null);
      expect(scan.existing, AnalyticsValue.unknown);
    });
  });

  test('enrollment_path_chosen carries source, action, existing_patient', () {
    gaEnrollmentPathChosen(
      source: AnalyticsValue.searchScan,
      action: AnalyticsValue.scanCreate,
      existingPatient: existingPatientValue(false),
    );
    final e = sink.named(AnalyticsEvent.enrollmentPathChosen).single;
    expect(e, {
      AnalyticsParam.source: AnalyticsValue.searchScan,
      AnalyticsParam.action: AnalyticsValue.scanCreate,
      AnalyticsParam.existingPatient: 'false',
    });
  });
}
