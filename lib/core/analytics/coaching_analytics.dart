import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

import 'analytics.dart';
import 'analytics_events.dart';

/// GA (LEAP-152): the Training tab's launch of the micro-coaching SDK.
///
/// Everything inside coaching (screens, modules, quizzes, chat, videos) is
/// sent by the SDK itself through this app's Firebase project; this is the one
/// thing only Flutter sees — whether coaching opened at all.

/// GA `failure_reason` for a coaching launch error.
String coachingLaunchFailureReason(Object error) {
  if (error is PlatformException) {
    switch (error.code) {
      case 'NOT_INITIALIZED':
        return AnalyticsValue.notInitialized;
      case 'NO_ACTIVITY':
        return AnalyticsValue.noActivity;
    }
  }
  return AnalyticsValue.error;
}

/// Sends `coaching_opened` {result, failure_reason, is_online}.
Future<void> trackCoachingOpened({Object? error}) async {
  bool? online;
  try {
    final results = await Connectivity().checkConnectivity();
    online = results.any((r) => r != ConnectivityResult.none);
  } on Object catch (_) {}
  Analytics.event(AnalyticsEvent.coachingOpened, {
    AnalyticsParam.result:
        error == null ? AnalyticsValue.success : AnalyticsValue.failed,
    AnalyticsParam.failureReason:
        error == null ? null : coachingLaunchFailureReason(error),
    AnalyticsParam.isOnline: online,
  });
}
