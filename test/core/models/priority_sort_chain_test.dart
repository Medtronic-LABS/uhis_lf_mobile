import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/risk.dart';

void main() {
  group('prioritySortChain helpers', () {
    test('spec legend is the canonical §2.8 order', () {
      expect(
        kPrioritySortSpecLegend,
        '1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4',
      );
    });

    test('priorityCodeFor emits 1a / 2b / 3 / 4', () {
      expect(priorityCodeFor(Band.band1, Modifier.a), '1a');
      expect(priorityCodeFor(Band.band1, Modifier.b), '1b');
      expect(priorityCodeFor(Band.band1, Modifier.none), '1');
      expect(priorityCodeFor(Band.band2, Modifier.a), '2a');
      expect(priorityCodeFor(Band.band4, Modifier.none), '4');
    });

    test('chain joins codes with arrows', () {
      expect(
        prioritySortChain(const ['1a', '1', '2b', '4']),
        '1a → 1 → 2b → 4',
      );
    });

    test('compact collapses consecutive runs', () {
      expect(
        prioritySortChainCompact(
          const ['1a', '1a', '1a', '1', '2a', '2a', '2b', '4'],
        ),
        '1a×3 → 1 → 2a×2 → 2b → 4',
      );
    });
  });
}
