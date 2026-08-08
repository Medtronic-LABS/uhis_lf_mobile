import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards `assets/translations/strings.json` against the corruption class that
/// slipped through when codes were bulk-extracted from Dart source: a Dart
/// escape sequence (`\'`, `\"`, `\\`) copied verbatim into JSON, which then
/// renders as a literal backslash on screen.
///
/// This matters because `getTranslatedString` *prefers* the JSON entry over the
/// Dart fallback, so a corrupted `en` value silently shadows correct source.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> translations;

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/translations/strings.json');
    translations = jsonDecode(raw) as Map<String, dynamic>;
  });

  test('strings.json parses and is non-empty', () {
    expect(translations, isNotEmpty);
  });

  test('no entry contains a stray backslash escape artifact', () {
    final offenders = <String>[];
    translations.forEach((code, value) {
      for (final locale in const ['en', 'bn']) {
        final text = (value as Map)[locale] as String?;
        if (text != null && text.contains(r'\')) {
          offenders.add('$code.$locale = $text');
        }
      }
    });
    expect(offenders, isEmpty,
        reason: 'A Dart escape sequence was copied into JSON verbatim. Write the '
            'literal character instead — JSON needs no Dart-style escaping.');
  });

  test('every entry carries both en and bn text', () {
    final incomplete = <String>[];
    translations.forEach((code, value) {
      final map = value as Map;
      for (final locale in const ['en', 'bn']) {
        final text = map[locale];
        if (text is! String || text.isEmpty) incomplete.add('$code.$locale');
      }
    });
    expect(incomplete, isEmpty);
  });
}
