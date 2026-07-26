import 'package:flutter/services.dart';

import '../../core/debug/console_log.dart';

class OfflineLlmException implements Exception {
  const OfflineLlmException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => 'OfflineLlmException[$code]: $message';
}

class OfflineLlmService {
  static const _channel =
      MethodChannel('com.medtroniclabs.uhis_lf_mobile/coaching_llm');

  /// Load the model at [modelPath] into the Android MediaPipe runtime.
  /// Call once after confirming the file is present on disk.
  Future<void> initialize(String modelPath) async {
    ConsoleLog.step('[OfflineLlmService] initialize modelPath=$modelPath');
    try {
      await _channel.invokeMethod<void>(
        'initialize',
        {'modelPath': modelPath},
      );
      ConsoleLog.success('[OfflineLlmService] model ready');
    } on PlatformException catch (e) {
      ConsoleLog.warn('[OfflineLlmService] initialize failed: ${e.message}');
      throw OfflineLlmException(e.message ?? 'init failed', code: e.code);
    }
  }

  /// Returns true when [initialize] has completed successfully.
  Future<bool> isReady() async {
    try {
      final ready = await _channel.invokeMethod<bool>('isReady');
      return ready ?? false;
    } on PlatformException catch (e) {
      ConsoleLog.warn('[OfflineLlmService] isReady error: ${e.message}');
      return false;
    }
  }

  /// Release the model from MediaPipe memory. Safe to call if not initialized.
  Future<void> close() async {
    ConsoleLog.step('[OfflineLlmService] close');
    try {
      await _channel.invokeMethod<void>('close');
    } on PlatformException catch (e) {
      ConsoleLog.warn('[OfflineLlmService] close failed: ${e.message}');
    }
  }

  /// Send [prompt] to the on-device Gemma model and return its response.
  Future<String> ask(String prompt) async {
    ConsoleLog.step('[OfflineLlmService] ask prompt=${prompt.length}chars');
    try {
      final answer = await _channel.invokeMethod<String>(
        'ask',
        {'prompt': prompt},
      );
      ConsoleLog.success('[OfflineLlmService] answer=${answer?.length}chars');
      return answer ?? '';
    } on PlatformException catch (e) {
      ConsoleLog.warn('[OfflineLlmService] ask failed: ${e.message}');
      throw OfflineLlmException(e.message ?? 'inference failed', code: e.code);
    }
  }
}
