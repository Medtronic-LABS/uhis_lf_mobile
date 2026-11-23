import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/naba/naba_models.dart';

import 'naba_visuals_fixtures.dart';

void main() {
  group('NabaResponse visuals / citations parsing', () {
    test('missing blocks default to empty', () {
      final naba = nabaWith();

      expect(naba.visuals, isEmpty);
      expect(naba.citations, isEmpty);
    });

    test(
      'null, wrong-typed and malformed entries are dropped, never thrown',
      () {
        final naba = nabaWith(
          citations: {
            'counselling': [
              ['ANC-1.1', 7, null],
              'not-a-list',
            ],
            'bad': 'x',
          },
          visuals: {
            'ANC-1.1': visualJson(),
            'ANC-2.2': 'not-a-map',
            'ANC-3.3': visualJson(
              images: [
                {'visualKey': '', 'sha256': 'x', 'imagePath': '/p'},
                {'visualKey': 'k', 'order': 1},
              ],
            ),
          },
        );

        expect(naba.citations.keys, ['counselling']);
        expect(naba.citations['counselling'], [
          ['ANC-1.1'],
          <String>[],
        ]);
        expect(naba.visuals.keys, ['ANC-1.1', 'ANC-3.3']);
        expect(naba.visuals['ANC-3.3']!.images, isEmpty);
      },
    );

    test('images are sorted by order and fields map through', () {
      final naba = nabaWith(
        visuals: {
          'NCD-1.1': visualJson(
            en: 'Walk daily',
            bn: 'প্রতিদিন হাঁটুন',
            machine: true,
            images: [
              imageJson('n-03', 3),
              imageJson('n-01', 1),
              imageJson('n-02', 2),
            ],
          ),
        },
      );

      final v = naba.visuals['NCD-1.1']!;
      expect(v.images.map((i) => i.visualKey), ['n-01', 'n-02', 'n-03']);
      expect(v.captionBnMachine, isTrue);
      expect(v.captionFor(bangla: false), 'Walk daily');
      expect(v.captionFor(bangla: true), 'প্রতিদিন হাঁটুন');
      expect(v.images.first.imagePath, '${visualImagePath}n-01');
    });

    test('NabaVisualImage.tryParse requires key, sha256 and imagePath', () {
      expect(NabaVisualImage.tryParse(imageJson('a', 1)), isNotNull);
      expect(
        NabaVisualImage.tryParse({'visualKey': 'a', 'sha256': 's'}),
        isNull,
      );
      expect(NabaVisualImage.tryParse('x'), isNull);
    });
  });
}
