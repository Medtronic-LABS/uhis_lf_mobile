import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/net_log/url_sanitizer.dart';

void main() {
  final vectors =
      jsonDecode(
            File(
              'test/fixtures/net_log/url_sanitizer_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('vectors file is version 1', () {
    expect(vectors['vectors_version'], 1);
  });

  group('shared vectors', () {
    for (final raw in vectors['cases'] as List<dynamic>) {
      final c = raw as Map<String, dynamic>;
      test(c['name'] as String, () {
        expect(UrlSanitizer.sanitize(c['input'] as String), c['expected']);
      });
    }
  });

  test('random garbage never throws and never exceeds the cap', () {
    final rng = Random(778);
    const alphabet = 'abc/:?&=%#@+ .-_09০৯…\u{1F600}[]';
    final chars = alphabet.runes.toList();
    for (var n = 0; n < 500; n++) {
      final len = rng.nextInt(4000);
      final s = String.fromCharCodes(
        List.generate(len, (_) => chars[rng.nextInt(chars.length)]),
      );
      final prefixed = n.isEven ? 'https://h.example.test/$s?$s' : s;
      expect(UrlSanitizer.sanitize(prefixed).length, lessThanOrEqualTo(2048));
    }
  });
}
