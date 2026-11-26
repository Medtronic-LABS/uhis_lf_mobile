// Flutter MethodChannel bridge to MicroCoachingSDK (micro-coaching-android-sdk).
// Channel: com.medtroniclabs.uhis_next/micro_coaching
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../config/coaching_sdk_url.dart';
import '../debug/console_log.dart';
import '../net_log/native_network_event_source.dart';
import '../net_log/network_log_entry.dart';

class MicroCoachingService {
  static const _channel = MethodChannel('com.medtroniclabs.uhis_next/micro_coaching');

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
    debugPrint('[MicroCoaching] initialize url=$sdkUrl lang=$language analytics=$analytics');
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

  /// Pulls request events recorded by the native SDK (contract v1).
  ///
  /// Never throws: transport and payload problems map to a status. Logs
  /// exception types and counts only, never messages or row content.
  static Future<NativeNetworkEventsResult> getNetworkEvents({
    required int afterId,
    int limit = 200,
  }) async {
    const unavailable = NativeNetworkEventsResult(
      status: NativeNetworkStatus.unavailable,
    );
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return unavailable;
    }
    final Object? response;
    try {
      response = await _channel.invokeMethod<Object?>('getNetworkEvents', {
        'afterId': afterId < 0 ? 0 : afterId,
        'limit': limit.clamp(_minEventLimit, _maxEventLimit),
        'contract_version': _networkContractVersion,
      });
    } on MissingPluginException {
      ConsoleLog.warn('[MicroCoaching] getNetworkEvents MissingPluginException');
      return unavailable;
    } on PlatformException {
      ConsoleLog.warn('[MicroCoaching] getNetworkEvents PlatformException');
      return const NativeNetworkEventsResult(status: NativeNetworkStatus.failed);
    }
    return _parseNetworkEvents(response);
  }

  static NativeNetworkEventsResult _parseNetworkEvents(Object? response) {
    const failed = NativeNetworkEventsResult(status: NativeNetworkStatus.failed);
    if (response is! Map) return failed;
    final status = response['status'];
    final version = response['sdk_event_version'];
    final events = response['events'];
    final maxId = response['max_id'];
    if (status is! String || version is! int || events is! List || maxId is! int) {
      return failed;
    }
    if (version != _networkContractVersion) {
      return const NativeNetworkEventsResult(
        status: NativeNetworkStatus.unavailable,
      );
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
    for (final row in events) {
      final entry = _parseNetworkRow(row);
      if (entry == null) {
        skipped++;
      } else {
        parsed.add(entry);
      }
    }
    if (skipped > 0) {
      ConsoleLog.warn('[MicroCoaching] getNetworkEvents skipped $skipped malformed rows');
    }
    return NativeNetworkEventsResult(
      status: NativeNetworkStatus.ok,
      events: parsed,
      maxId: maxId,
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
        startedAt is! int ||
        method is! String ||
        url is! String ||
        duration is! int) {
      return null;
    }
    if ((statusCode != null && statusCode is! int) ||
        (errorType != null && errorType is! String)) {
      return null;
    }
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
