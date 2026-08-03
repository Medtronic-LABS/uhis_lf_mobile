// Flutter MethodChannel bridge to MicroCoachingSDK (micro-coaching-android-sdk).
// Channel: com.medtroniclabs.uhis_next/micro_coaching
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MicroCoachingService {
  static const _channel = MethodChannel('com.medtroniclabs.uhis_next/micro_coaching');

  /// Initialize SDK after login. Maps to MicroCoachingSDK.Builder(...).build().
  static Future<void> initialize({
    required String authToken,
    String backendUrl = 'https://agent-qa.beehyv.com/medtronics-api/',
    String language = 'bn',
    String hfToken = '',
  }) async {
    debugPrint('[MicroCoaching] initialize url=$backendUrl lang=$language');
    await _channel.invokeMethod('initialize', {
      'authToken': authToken,
      'backendUrl': backendUrl,
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
}
