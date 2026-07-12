/// Global, context-free current-language flag — the localization seam
/// `app_strings.dart`'s own doc comment describes ("swap each `static const
/// String` for a locale lookup... without touching a single widget"). Set by
/// `LocaleProvider` on a language change; read directly by `*Strings` getters
/// with no `BuildContext` needed, so call sites never change.
library;

enum AppLanguage { english, bangla }

abstract final class AppLocale {
  AppLocale._();

  static AppLanguage current = AppLanguage.english;

  static bool get isBangla => current == AppLanguage.bangla;
}
