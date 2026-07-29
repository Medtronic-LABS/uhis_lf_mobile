import 'package:flutter_tts/flutter_tts.dart';

import '../../core/debug/console_log.dart';

class CoachingTtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _initialized = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('bn-BD');
      await _tts.setSpeechRate(0.9);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() => _isSpeaking = false);
      _tts.setErrorHandler((_) => _isSpeaking = false);
      _initialized = true;
      ConsoleLog.success('[CoachingTtsService] initialized');
    } on Exception catch (e) {
      ConsoleLog.warn('[CoachingTtsService] init failed: $e');
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (!_initialized) await initialize();
    try {
      _isSpeaking = true;
      await _tts.speak(text);
    } on Exception catch (e) {
      _isSpeaking = false;
      ConsoleLog.warn('[CoachingTtsService] speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Exception catch (e) {
      ConsoleLog.warn('[CoachingTtsService] stop failed: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  void dispose() {
    stop();
  }
}
