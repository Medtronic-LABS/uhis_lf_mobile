import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/analytics/analytics_events.dart';
import 'package:uhis_next/core/errors/domain_exceptions.dart';
import 'package:uhis_next/core/sync/offline_sync_service.dart';
import 'package:uhis_next/core/sync/sync_report.dart';

/// GA `sync_completed` params (LEAP-152): failure reasons come from the typed
/// error the sync stopped on, never from its message text.
void main() {
  final start = DateTime(2026, 11, 23, 10);
  SyncReport report({List<String> errors = const [], Object? failure}) =>
      SyncReport(
        startedAt: start,
        finishedAt: start.add(const Duration(seconds: 4)),
        households: 3,
        members: 12,
        errors: errors,
        failure: failure,
      );

  test('success: counts and duration, no failure reason', () {
    final p = OfflineSyncService.syncCompletedParams('manual', report());
    expect(p[AnalyticsParam.result], AnalyticsValue.success);
    expect(p[AnalyticsParam.failureReason], isNull);
    expect(p[AnalyticsParam.durationMs], 4000);
    expect(p[AnalyticsParam.households], 3);
    expect(p[AnalyticsParam.members], 12);
    expect(p[AnalyticsParam.trigger], 'manual');
  });

  test('no user id: session expired, from the typed error', () {
    final p = OfflineSyncService.syncCompletedParams(
      'auto',
      report(errors: const ['userId not available'],
          failure: const SessionExpiredException()),
    );
    expect(p[AnalyticsParam.result], AnalyticsValue.failed);
    expect(p[AnalyticsParam.failureReason], AnalyticsValue.sessionExpired);
  });

  test('network failure maps from the exception, not the text', () {
    final p = OfflineSyncService.syncCompletedParams(
      'auto',
      report(
        // Text that the old substring match would have read as a 5xx.
        errors: const ['Sync failed: page 5 of 50 records'],
        failure: DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      ),
    );
    expect(p[AnalyticsParam.failureReason], AnalyticsValue.offline);
  });

  test('failure without a typed error is other', () {
    final p = OfflineSyncService.syncCompletedParams(
        'auto', report(errors: const ['Entity sync download failed']));
    expect(p[AnalyticsParam.failureReason], AnalyticsValue.other);
  });

  test('a skipped sync is flagged so no sync_completed is sent', () {
    final r = SyncReport.empty()
        .copyWith(errors: const ['Sync already running'], skipped: true);
    expect(r.skipped, isTrue);
    expect(SyncReport.empty().skipped, isFalse);
  });
}
