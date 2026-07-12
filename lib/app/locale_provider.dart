import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/i18n/app_locale.dart';

/// Manages the app's language with persistence — same shape as
/// [ThemeProvider]. Updates the context-free [AppLocale] flag so
/// `*Strings` getters pick up the change, and calls [notifyListeners]
/// so the `Builder` wrapping `MaterialApp.router` in `main.dart` (which
/// already watches [ThemeProvider] the same way) rebuilds the whole routed
/// tree, causing every widget to re-read its strings.
class LocaleProvider extends ChangeNotifier {
  LocaleProvider() {
    _loadFromStorage();
  }

  static const _key = 'app_language';
  static const _storage = FlutterSecureStorage();

  AppLanguage get language => AppLocale.current;

  bool get isBangla => AppLocale.isBangla;

  Future<void> _loadFromStorage() async {
    try {
      final stored = await _storage.read(key: _key);
      AppLocale.current =
          stored == 'bn' ? AppLanguage.bangla : AppLanguage.english;
      notifyListeners();
    } catch (_) {
      // Ignore storage errors on startup
    }
  }

  Future<void> setLanguage(AppLanguage lang) async {
    if (AppLocale.current == lang) return;
    AppLocale.current = lang;
    notifyListeners();
    try {
      await _storage.write(
        key: _key,
        value: lang == AppLanguage.bangla ? 'bn' : 'en',
      );
    } catch (_) {
      // Ignore storage errors
    }
  }
}
