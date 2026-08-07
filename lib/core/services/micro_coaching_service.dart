// Flutter MethodChannel bridge to MicroCoachingSDK (micro-coaching-android-sdk).
// Channel: com.medtroniclabs.uhis_next/micro_coaching
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MicroCoachingService {
  static const _channel = MethodChannel('com.medtroniclabs.uhis_next/micro_coaching');

  // Retrofit requires base URL to end with '/' and include the full path prefix.
  // AppConfig.coachingServiceUrl omits 'medtronics-api/' for Dio callers — normalize here.
  static String _sdkUrl(String url) {
    var u = url.endsWith('/') ? url : '$url/';
    if (!u.contains('medtronics-api')) u = '${u}medtronics-api/';
    return u;
  }

  /// Initialize SDK after login. Maps to MicroCoachingSDK.Builder(...).build().
  static Future<void> initialize({
    required String authToken,
    String backendUrl = 'https://spice-dev-backend.uhis.labsplatform.com/micro-coaching/medtronics-api/',
    String language = 'bn',
    String hfToken = '',
  }) async {
    final sdkUrl = _sdkUrl(backendUrl);
    debugPrint('[MicroCoaching] initialize url=$sdkUrl lang=$language');
    await _channel.invokeMethod('initialize', {
      'authToken': authToken,
      'backendUrl': sdkUrl,
      'language': language,
      'hfToken': hfToken,
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

  /// Update SDK language without full re-init. No-op if SDK not initialized.
  static Future<void> setLanguage(String language) async {
    debugPrint('[MicroCoaching] setLanguage=$language');
    await _channel.invokeMethod('setLanguage', {'language': language});
  }
}
