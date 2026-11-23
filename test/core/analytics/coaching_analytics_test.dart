import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/analytics/analytics_events.dart';
import 'package:uhis_next/core/analytics/coaching_analytics.dart';

void main() {
  group('coachingLaunchFailureReason', () {
    test('maps the plugin error codes', () {
      expect(
        coachingLaunchFailureReason(
            PlatformException(code: 'NOT_INITIALIZED')),
        AnalyticsValue.notInitialized,
      );
      expect(
        coachingLaunchFailureReason(PlatformException(code: 'NO_ACTIVITY')),
        AnalyticsValue.noActivity,
      );
    });

    test('anything else is error', () {
      expect(
        coachingLaunchFailureReason(PlatformException(code: 'MISSING_ARG')),
        AnalyticsValue.error,
      );
      expect(coachingLaunchFailureReason(StateError('x')),
          AnalyticsValue.error);
    });
  });
}
