import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the app's theme mode (light/dark) with persistence.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    _loadFromStorage();
  }

  static const _key = 'theme_mode';
  static const _storage = FlutterSecureStorage();

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;
  bool get isLight => _mode == ThemeMode.light;
  bool get isSystem => _mode == ThemeMode.system;

  Future<void> _loadFromStorage() async {
    try {
      final stored = await _storage.read(key: _key);
      if (stored == 'dark') {
        _mode = ThemeMode.dark;
      } else if (stored == 'light') {
        _mode = ThemeMode.light;
      } else {
        _mode = ThemeMode.light;
      }
      notifyListeners();
    } catch (_) {
      // Ignore storage errors on startup
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      switch (mode) {
        case ThemeMode.dark:
          await _storage.write(key: _key, value: 'dark');
          break;
        case ThemeMode.light:
          await _storage.write(key: _key, value: 'light');
          break;
        case ThemeMode.system:
          await _storage.delete(key: _key);
          break;
      }
    } catch (_) {
      // Ignore storage errors
    }
  }

  /// Cycles system → light → dark → system.
  Future<void> cycleThemeMode() async {
    switch (_mode) {
      case ThemeMode.system:
        await setMode(ThemeMode.light);
        break;
      case ThemeMode.light:
        await setMode(ThemeMode.dark);
        break;
      case ThemeMode.dark:
        await setMode(ThemeMode.system);
        break;
    }
  }

  /// Legacy toggle kept for call-sites not yet updated; cycles the same way.
  Future<void> toggleDarkMode() => cycleThemeMode();
}
