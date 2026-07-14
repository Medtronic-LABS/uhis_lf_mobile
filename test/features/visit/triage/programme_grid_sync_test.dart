import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/triage/programme_grid_sync.dart';

void main() {
  group('ProgrammeGridSync.additionsFromPathways', () {
    test('adds newly activated programmes not already selected', () {
      final adds = ProgrammeGridSync.additionsFromPathways(
        activated: {Programme.ncd, Programme.anc},
        selected: {Programme.anc},
        dismissedBySk: const {},
      );
      expect(adds, {Programme.ncd});
    });

    test('does not re-add a programme the SK deselected', () {
      final adds = ProgrammeGridSync.additionsFromPathways(
        activated: {Programme.ncd, Programme.anc},
        selected: {Programme.anc},
        dismissedBySk: {Programme.ncd},
      );
      expect(adds, isEmpty);
    });

    test('empty when selection already covers activations', () {
      final adds = ProgrammeGridSync.additionsFromPathways(
        activated: {Programme.ncd},
        selected: {Programme.ncd},
        dismissedBySk: const {},
      );
      expect(adds, isEmpty);
    });
  });
}
