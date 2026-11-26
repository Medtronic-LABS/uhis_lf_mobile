// Flutter MethodChannel bridge to MicroCoachingSDK (micro-coaching-android-sdk).
// Channel: com.medtroniclabs.uhis_next/micro_coaching
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../config/coaching_sdk_url.dart';
import '../debug/console_log.dart';
import '../net_log/native_network_events_result.dart';
import '../net_log/network_log_entry.dart';

class MicroCoachingService {
  static const _channel = MethodChannel(
    'com.medtroniclabs.uhis_next/micro_coaching',
  );

  /// The base URL the SDK uses for [url]; see [coachingSdkBaseUrl].
  static String sdkBaseUrl(String url) => coachingSdkBaseUrl(url);

  /// Initialize SDK after login. Maps to MicroCoachingSDK.Builder(...).build().
  static Future<void> initialize({
    required String authToken,
    String? backendUrl,
    String language = 'bn',
    String hfToken = '',
    bool? analyticsEnabled,
  }) async {
    final sdkUrl = sdkBaseUrl(backendUrl ?? AppConfig.coachingServiceUrl);
    // GA (LEAP-152): coaching screens follow the same switch as the Flutter
    // events, so debug runs without ANALYTICS_ENABLED never reach GA.
    final analytics = analyticsEnabled ?? AppConfig.analyticsEnabled;
    debugPrint(
      '[MicroCoaching] initialize url=$sdkUrl lang=$language analytics=$analytics',
    );
    await _channel.invokeMethod('initialize', {
      'authToken': authToken,
      'backendUrl': sdkUrl,
      'language': language,
      'hfToken': hfToken,
      'analyticsEnabled': analytics,
    });
    debugPrint('[MicroCoaching] initialize ✓');
  }

  /// Update Bearer token without full SDK re-init.
  static Future<void> updateToken(String authToken) async {
    debugPrint('[MicroCoaching] updateToken');
    await _channel.invokeMethod('updateToken', {'authToken': authToken});
  }

  /// Launch CoachingFlowActivity for the given CHW.
  static Future<void> launch(String chwId) async {
    debugPrint('[MicroCoaching] launch chwId=$chwId');
    await _channel.invokeMethod('launch', {'chwId': chwId});
    debugPrint('[MicroCoaching] launch ✓');
  }

  static Future<bool> isInitialized() async {
    final v = await _channel.invokeMethod<bool>('isInitialized') ?? false;
    debugPrint('[MicroCoaching] isInitialized=$v');
    return v;
  }

  static const _networkContractVersion = 1;
  static const _minEventLimit = 1;
  static const _maxEventLimit = 500;
  static const _networkTimeout = Duration(seconds: 8);

  /// Pulls request events recorded by the native SDK (contract v1).
  ///
  /// Maps MissingPluginException, PlatformException, a timeout and payload
  /// problems to a status instead of throwing. Logs exception types and
  /// counts only, never messages or row content. At most [limit] rows are
  /// read from the response.
  static Future<NativeNetworkEventsResult> getNetworkEvents({
    required int afterId,
    int limit = 200,
    Duration timeout = _networkTimeout,
  }) async {
    const unavailable = NativeNetworkEventsResult(
      status: NativeNetworkStatus.unavailable,
    );
    const failed = NativeNetworkEventsResult(
      status: NativeNetworkStatus.failed,
    );
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return unavailable;
    }
    final clamped = limit.clamp(_minEventLimit, _maxEventLimit);
    final Object? response;
    try {
      response = await _channel
          .invokeMethod<Object?>('getNetworkEvents', {
            'afterId': afterId < 0 ? 0 : afterId,
            'limit': clamped,
            'contract_version': _networkContractVersion,
          })
          .timeout(timeout);
    } on MissingPluginException {
      ConsoleLog.warn(
        '[MicroCoaching] getNetworkEvents MissingPluginException',
      );
      return unavailable;
    } on PlatformException {
      ConsoleLog.warn('[MicroCoaching] getNetworkEvents PlatformException');
      return failed;
    } on TimeoutException {
      ConsoleLog.warn('[MicroCoaching] getNetworkEvents TimeoutException');
      return failed;
    }
    return _parseNetworkEvents(response, clamped);
  }

  /// Asks the native SDK to delete its stored request events (a user switch).
  ///
  /// Never throws: an SDK that is absent, older than this contract or failing
  /// is not an error for the caller. Returns true only when the SDK confirmed
  /// the delete. Logs exception types only.
  static Future<bool> clearNetworkEvents({
    Duration timeout = _networkTimeout,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final reply = await _channel
          .invokeMethod<Object?>('clearNetworkEvents')
          .timeout(timeout);
      // Only an explicit `ok` counts: `notInitialized` means the SDK store was
      // not reachable, so its rows were not deleted.
      return reply is Map && reply['status'] == 'ok';
    } on MissingPluginException {
      ConsoleLog.warn(
        '[MicroCoaching] clearNetworkEvents MissingPluginException',
      );
    } on PlatformException {
      ConsoleLog.warn('[MicroCoaching] clearNetworkEvents PlatformException');
    } on TimeoutException {
      ConsoleLog.warn('[MicroCoaching] clearNetworkEvents TimeoutException');
    } on Object catch (e) {
      // Contract: never throws (the wipe calls this unawaited). Type only.
      ConsoleLog.warn('[MicroCoaching] clearNetworkEvents ${e.runtimeType}');
    }
    return false;
  }

  static NativeNetworkEventsResult _parseNetworkEvents(
    Object? response,
    int limit,
  ) {
    const failed = NativeNetworkEventsResult(
      status: NativeNetworkStatus.failed,
    );
    if (response is! Map) return failed;
    // Checked first: another contract version may reshape the rest. Any value
    // other than the int we speak (any type) means the SDK is not usable.
    final rawVersion = response['sdk_event_version'];
    if (response.containsKey('sdk_event_version') &&
        !(rawVersion is int && rawVersion == _networkContractVersion)) {
      return const NativeNetworkEventsResult(
        status: NativeNetworkStatus.unavailable,
      );
    }
    final status = response['status'];
    final events = response['events'];
    final maxId = response['max_id'];
    if (rawVersion is! int ||
        status is! String ||
        events is! List ||
        maxId is! int) {
      return failed;
    }
    if (status == 'notInitialized') {
      return NativeNetworkEventsResult(
        status: NativeNetworkStatus.notInitialized,
        maxId: maxId,
      );
    }
    if (status != 'ok') return failed;
    final parsed = <NetworkLogEntry>[];
    var skipped = 0;
    var lastRawId = -1;
    final rows = events.take(limit).toList();
    for (final row in rows) {
      final rawId = row is Map ? row['id'] : null;
      if (rawId is int && rawId > lastRawId) lastRawId = rawId;
      final entry = _parseNetworkRow(row);
      if (entry == null) {
        skipped++;
      } else {
        parsed.add(entry);
      }
    }
    if (skipped > 0) {
      ConsoleLog.warn(
        '[MicroCoaching] getNetworkEvents skipped $skipped malformed rows',
      );
    }
    return NativeNetworkEventsResult(
      status: NativeNetworkStatus.ok,
      events: parsed,
      maxId: maxId,
      lastRawId: lastRawId >= 0 ? lastRawId : null,
      rawCount: rows.length,
    );
  }

  static NetworkLogEntry? _parseNetworkRow(Object? row) {
    if (row is! Map) return null;
    final id = row['id'];
    final startedAt = row['started_at_ms'];
    final method = row['method'];
    final url = row['url'];
    final duration = row['duration_ms'];
    final statusCode = row['status_code'];
    final errorType = row['error_type'];
    if (id is! int ||
        id < 0 ||
        startedAt is! int ||
        method is! String ||
        url is! String ||
        duration is! int ||
        duration < 0) {
      return null;
    }
    // A wrongly typed or out-of-range optional field skips the whole row.
    if (statusCode != null &&
        (statusCode is! int || statusCode < 100 || statusCode > 599)) {
      return null;
    }
    if (errorType != null && errorType is! String) return null;
    return NetworkLogEntry(
      source: 'native',
      nativeId: id,
      startedAtMs: startedAt,
      service: '',
      method: method,
      url: url,
      statusCode: statusCode is int ? statusCode : null,
      durationMs: duration,
      timing: 'headers',
      attempt: 1,
      errorType: errorType is String ? errorType : null,
    );
  }

  /// Update SDK language without full re-init. No-op if SDK not initialized.
  static Future<void> setLanguage(String language) async {
    debugPrint('[MicroCoaching] setLanguage=$language');
    await _channel.invokeMethod('setLanguage', {'language': language});
  }
}
