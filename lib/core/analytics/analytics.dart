import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../errors/domain_exceptions.dart';
import 'analytics_events.dart';

/// Where analytics calls end up. Firebase in the app, a fake in tests.
abstract interface class AnalyticsSink {
  Future<void> logEvent(String name, Map<String, Object> params);
  Future<void> logScreen(String screenName, String? screenClass);
  Future<void> setUserId(String? id);
  Future<void> setUserProperty(String name, String? value);
}

class _FirebaseSink implements AnalyticsSink {
  _FirebaseSink(this._fa);
  final FirebaseAnalytics _fa;

  @override
  Future<void> logEvent(String name, Map<String, Object> params) =>
      _fa.logEvent(name: name, parameters: params.isEmpty ? null : params);

  @override
  Future<void> logScreen(String screenName, String? screenClass) =>
      _fa.logScreenView(screenName: screenName, screenClass: screenClass);

  @override
  Future<void> setUserId(String? id) => _fa.setUserId(id: id);

  @override
  Future<void> setUserProperty(String name, String? value) =>
      _fa.setUserProperty(name: name, value: value);
}

/// Google Analytics (Firebase GA4) usage events (LEAP-152).
///
/// Static so any layer (router observer, AuthState, sync, dialogs) can log
/// without plumbing. Every call is fire-and-forget and never throws: when
/// Firebase isn't initialised (iOS/web, missing config, init failure, or
/// [AppConfig.analyticsEnabled] off) calls are dropped.
///
/// This is separate from — and does not change — the in-house
/// `TelemetryService` pipeline.
///
/// PRIVACY: see `analytics_events.dart`. Only fixed choices, counts,
/// durations and booleans; never patient data or free text.
abstract final class Analytics {
  static AnalyticsSink? _sink;
  static String? _lastScreen;

  /// GA4 limit for string parameter / user property values.
  static const int maxValueLength = 100;

  /// Initialise Firebase. Call once in `main()` before `runApp`. Android only;
  /// failure is logged and leaves analytics disabled.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp();
      final fa = FirebaseAnalytics.instance;
      final enabled = AppConfig.analyticsEnabled;
      await fa.setAnalyticsCollectionEnabled(enabled);
      if (enabled) _sink = _FirebaseSink(fa);
      debugPrint('[Analytics] Firebase ready (collection=$enabled)');
    } catch (e) {
      debugPrint('[Analytics] Firebase init failed — analytics off: $e');
    }
  }

  @visibleForTesting
  static set sink(AnalyticsSink? s) {
    _sink = s;
    _lastScreen = null;
  }

  static bool get isEnabled => _sink != null;

  /// Log a custom event. `null` params are dropped, booleans are sent as
  /// `"true"`/`"false"` (GA has no bool type), strings are capped at 100.
  static void event(String name, [Map<String, Object?> params = const {}]) {
    final sink = _sink;
    if (sink == null) return;
    final clean = sanitize(params);
    if (kDebugMode) debugPrint('[Analytics] $name $clean');
    _guard(sink.logEvent(name, clean), name);
  }

  /// Log a `screen_view`. Repeats of the same screen back-to-back (e.g. a
  /// rebuild re-reporting the current step) are ignored.
  static void screen(String screenName, {String? screenClass}) {
    final sink = _sink;
    if (sink == null) return;
    if (screenName == _lastScreen) return;
    _lastScreen = screenName;
    if (kDebugMode) debugPrint('[Analytics] screen_view $screenName');
    _guard(sink.logScreen(screenName, screenClass ?? screenName),
        'screen_view');
  }

  /// GA `permission_result`. [permission] is one of `camera`, `microphone`,
  /// `location`, `notifications`; [source] is where it was asked
  /// (`onboarding`, `scribe`, `card_scan`, `nid_scan`, `teleconsult`, `enrollment`).
  static void permissionResult(String permission, bool granted,
          {required String source}) =>
      event(AnalyticsEvent.permissionResult, {
        AnalyticsParam.permission: permission,
        AnalyticsParam.granted: granted,
        AnalyticsParam.source: source,
      });

  /// Identify the signed-in SK. [userId] is the backend user id — never a
  /// name, phone, NID or username.
  static Future<void> setUser({
    required String? tenantId,
    required int? userId,
    String? upazila,
    String? unionArea,
    String? appLanguage,
  }) async {
    final sink = _sink;
    if (sink == null) return;
    final id = gaUserId(tenantId: tenantId, userId: userId);
    if (kDebugMode) debugPrint('[Analytics] user $id');
    try {
      await sink.setUserId(id);
      await sink.setUserProperty(AnalyticsUserProperty.tenantId, tenantId);
      await sink.setUserProperty(AnalyticsUserProperty.upazila, _cap(upazila));
      await sink.setUserProperty(
          AnalyticsUserProperty.unionArea, _cap(unionArea));
      await sink.setUserProperty(
          AnalyticsUserProperty.appLanguage, appLanguage);
      await sink.setUserProperty(AnalyticsUserProperty.appFlavor,
          AppConfig.isTrainingBuild ? 'training' : 'prod');
    } catch (e) {
      debugPrint('[Analytics] setUser failed: $e');
    }
  }

  /// Update the language user property after a switch.
  static void setLanguage(String language) {
    final sink = _sink;
    if (sink == null) return;
    _guard(sink.setUserProperty(AnalyticsUserProperty.appLanguage, language),
        'app_language');
  }

  /// Forget the SK on logout so a shared phone's next user starts clean.
  static Future<void> clearUser() async {
    final sink = _sink;
    if (sink == null) return;
    try {
      await sink.setUserId(null);
      await sink.setUserProperty(AnalyticsUserProperty.tenantId, null);
      await sink.setUserProperty(AnalyticsUserProperty.upazila, null);
      await sink.setUserProperty(AnalyticsUserProperty.unionArea, null);
    } catch (e) {
      debugPrint('[Analytics] clearUser failed: $e');
    }
  }

  /// GA user id: `<tenantId>-<userId>` (backend user ids are not guaranteed
  /// unique across tenants). `null` when the user id is unknown.
  @visibleForTesting
  static String? gaUserId({required String? tenantId, required int? userId}) {
    if (userId == null) return null;
    final t = tenantId?.trim();
    return (t == null || t.isEmpty) ? '$userId' : '$t-$userId';
  }

  /// Maps an error to a fixed `failure_reason` value — never the message.
  static String failureReason(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return AnalyticsValue.timeout;
        case DioExceptionType.connectionError:
          return AnalyticsValue.offline;
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode ?? 0;
          if (code == 401 || code == 403) return AnalyticsValue.wrongCredentials;
          if (code >= 500) return AnalyticsValue.serverError;
          return AnalyticsValue.other;
        default:
          return AnalyticsValue.other;
      }
    }
    if (error is TimeoutException) return AnalyticsValue.timeout;
    if (error is NetworkException) {
      final cause = error.cause;
      return cause != null ? failureReason(cause) : AnalyticsValue.offline;
    }
    if (error is UnauthorizedException) return AnalyticsValue.wrongCredentials;
    if (error is SessionExpiredException) return AnalyticsValue.sessionExpired;
    return AnalyticsValue.other;
  }

  @visibleForTesting
  static Map<String, Object> sanitize(Map<String, Object?> params) {
    final out = <String, Object>{};
    params.forEach((k, v) {
      if (v == null) return;
      if (v is bool) {
        out[k] = v ? 'true' : 'false';
      } else if (v is num) {
        out[k] = v;
      } else {
        out[k] = _cap(v.toString())!;
      }
    });
    return out;
  }

  static String? _cap(String? v) => (v == null || v.length <= maxValueLength)
      ? v
      : v.substring(0, maxValueLength);

  static void _guard(Future<void> f, String what) {
    unawaited(f.catchError((Object e) {
      debugPrint('[Analytics] $what failed: $e');
    }));
  }
}
