import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/naba/guideline_visual_selector.dart';

import 'naba_visuals_fixtures.dart';

void main() {
  group('GuidelineVisualSelector.citedIds', () {
    test('collects every source once, in first-seen order', () {
      final naba = nabaWith(
        citations: {
          'counselling': [
            ['A-1', 'A-2'],
            ['A-1'],
          ],
          'danger_signs': [
            ['A-3'],
          ],
        },
        findingIds: ['A-2', 'A-4', null],
        referralId: 'A-5',
        rationaleIds: ['A-6', 'A-1', ''],
      );

      expect(GuidelineVisualSelector.citedIds(naba), [
        'A-1',
        'A-2',
        'A-3',
        'A-4',
        'A-5',
        'A-6',
      ]);
    });
  });

  group('GuidelineVisualSelector.select', () {
    Map<String, dynamic> visualsFor(Iterable<String> ids) => {
      for (final id in ids) id: visualJson(en: 'EN $id', bn: 'BN $id'),
    };

    test('keeps only cited ids that have images and a caption', () {
      final naba = nabaWith(
        rationaleIds: ['A-1', 'A-2', 'A-3', 'A-4'],
        visuals: {
          'A-1': visualJson(en: 'Keep'),
          'A-2': visualJson(en: '   '), // no English caption
          'A-3': visualJson(images: []), // no images
          'Z-9': visualJson(), // not cited
        },
      );

      final picked = GuidelineVisualSelector.select(
        naba,
        bangla: false,
        seed: 'v1',
      );

      expect(picked.map((p) => p.pointerId), ['A-1']);
      expect(picked.single.caption, 'Keep');
    });

    test('caption follows the app language', () {
      final naba = nabaWith(
        rationaleIds: ['A-1'],
        visuals: {'A-1': visualJson(en: 'English', bn: '')},
      );

      expect(
        GuidelineVisualSelector.select(
          naba,
          bangla: false,
          seed: 'v',
        ).single.caption,
        'English',
      );
      // Bangla app with no Bangla caption → not shown.
      expect(
        GuidelineVisualSelector.select(naba, bangla: true, seed: 'v'),
        isEmpty,
      );
    });

    test('uses the lowest-order image of each guideline', () {
      final naba = nabaWith(
        rationaleIds: ['A-1'],
        visuals: {
          'A-1': visualJson(
            images: [imageJson('a-02', 2), imageJson('a-01', 1)],
          ),
        },
      );

      final picked = GuidelineVisualSelector.select(
        naba,
        bangla: false,
        seed: 'v',
      );
      expect(picked.single.image.visualKey, 'a-01');
    });

    test('caps at 3 and is stable for the same seed', () {
      final ids = [for (var i = 1; i <= 8; i++) 'A-$i'];
      final naba = nabaWith(rationaleIds: ids, visuals: visualsFor(ids));

      final first = GuidelineVisualSelector.select(
        naba,
        bangla: false,
        seed: 'visit-42',
      );
      final again = GuidelineVisualSelector.select(
        naba,
        bangla: false,
        seed: 'visit-42',
      );

      expect(first, hasLength(3));
      expect(first.map((p) => p.pointerId).toSet(), hasLength(3));
      expect(again.map((p) => p.pointerId), first.map((p) => p.pointerId));
    });

    test('different visits can get different pictures', () {
      final ids = [for (var i = 1; i <= 8; i++) 'A-$i'];
      final naba = nabaWith(rationaleIds: ids, visuals: visualsFor(ids));

      final picks = {
        for (var v = 0; v < 20; v++)
          GuidelineVisualSelector.select(
            naba,
            bangla: false,
            seed: 'visit-$v',
          ).map((p) => p.pointerId).join(','),
      };
      expect(picks.length, greaterThan(1));
    });

    test('empty when nothing is eligible', () {
      expect(
        GuidelineVisualSelector.select(nabaWith(), bangla: false, seed: 'v'),
        isEmpty,
      );
    });
  });

  test('stableHash is deterministic and spreads values', () {
    expect(
      GuidelineVisualSelector.stableHash('abc'),
      GuidelineVisualSelector.stableHash('abc'),
    );
    expect(
      GuidelineVisualSelector.stableHash('abc'),
      isNot(GuidelineVisualSelector.stableHash('abd')),
    );
  });
}
