import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the localization seam.
///
/// `getTranslatedString(code, fallback)` returns [fallback] — English — whenever
/// `code` is absent from `assets/translations/strings.json`. Nothing warns: the
/// app compiles, renders English, and passes review. Thirteen `Sync.*` keys
/// accumulated that way, including every step label on the sync screen, which is
/// why an SK running the app in Bangla saw "Downloading patients".
///
/// This is a ratchet, not an absolute gate. 308 keys were already untranslated
/// when it was written; those are recorded in `i18n_untranslated_baseline.txt`.
/// A key missing from BOTH the bundle and the baseline fails the build, so new
/// untranslated strings cannot be introduced. Removing baseline lines as they
/// get translated is the goal.
void main() {
  test('no new untranslated keys are introduced', () {
    final bundle = json.decode(
      File('assets/translations/strings.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final source =
        File('lib/core/constants/app_strings.dart').readAsStringSync();
    final used = RegExp(r"getTranslatedString\(\s*'([^']+)'")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    final baseline = File('test/i18n_untranslated_baseline.txt')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .toSet();

    final missing = used.where((k) => !bundle.containsKey(k)).toSet();
    final unexpected = (missing.difference(baseline).toList()..sort());

    expect(
      unexpected,
      isEmpty,
      reason: 'These keys render English in every language because they have no '
          'entry in assets/translations/strings.json. Add them there (with a '
          '"bn" value), or — only with reason — add them to '
          'test/i18n_untranslated_baseline.txt.',
    );
  });

  test('the baseline contains no keys that are now translated', () {
    // Keeps the ratchet tightening: once a key is translated its baseline line
    // must go, otherwise the file rots into a permanent allowlist.
    final bundle = json.decode(
      File('assets/translations/strings.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final baseline = File('test/i18n_untranslated_baseline.txt')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .toList();

    final stale = (baseline.where(bundle.containsKey).toList()..sort());

    expect(
      stale,
      isEmpty,
      reason: 'These keys are translated now — delete them from '
          'test/i18n_untranslated_baseline.txt.',
    );
  });

  test('every bundle entry carries a non-empty bn value', () {
    // A key present but with an empty "bn" falls back to English just as
    // silently as a missing one.
    final bundle = json.decode(
      File('assets/translations/strings.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final blank = <String>[];
    bundle.forEach((key, value) {
      final bn = (value as Map<String, dynamic>)['bn'];
      if (bn == null || (bn as String).trim().isEmpty) blank.add(key);
    });

    expect(blank..sort(), isEmpty,
        reason: 'Entries exist but have no Bangla text, so they render English.');
  });
}
