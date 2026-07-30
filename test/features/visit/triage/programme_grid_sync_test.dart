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

  group('ProgrammeGridSync.applicableEnrolledSeed', () {
    test('pregnant visit keeps ANC/PW, drops historical PNC', () {
      final seeded = ProgrammeGridSync.applicableEnrolledSeed(
        enrolled: {Programme.anc, Programme.pnc, Programme.pw, Programme.ncd},
        isPregnant: true,
        isPostpartum: false,
      );
      expect(seeded, {Programme.anc, Programme.pw, Programme.ncd});
    });

    test('postpartum visit keeps PNC, drops ANC/PW', () {
      final seeded = ProgrammeGridSync.applicableEnrolledSeed(
        enrolled: {Programme.anc, Programme.pnc, Programme.pw},
        isPregnant: false,
        isPostpartum: true,
      );
      expect(seeded, {Programme.pnc});
    });
  });

  group('ProgrammeGridSync.catalogProgrammesFor', () {
    test('drops imci/epi for a symptom cross-tagged with them when not under-5', () {
      final result = ProgrammeGridSync.catalogProgrammesFor(
        {Programme.imci, Programme.anc, Programme.tb},
        isUnder5: false,
      );
      expect(result, {Programme.anc, Programme.tb});
    });

    test('keeps imci/epi for the same tag set when the patient is under-5', () {
      final result = ProgrammeGridSync.catalogProgrammesFor(
        {Programme.imci, Programme.anc, Programme.tb},
        isUnder5: true,
      );
      expect(result, {Programme.imci, Programme.anc, Programme.tb});
    });

    test('unaffected when the symptom carries no imci/epi tag', () {
      final result = ProgrammeGridSync.catalogProgrammesFor(
        {Programme.ncd},
        isUnder5: false,
      );
      expect(result, {Programme.ncd});
    });
  });

  group('ProgrammeGridSync.applyDeliverySelected', () {
    test('clears only ANC and PW; keeps NCD and ensures PNC', () {
      final next = ProgrammeGridSync.applyDeliverySelected(
        selected: {Programme.anc, Programme.pw, Programme.ncd},
        dismissedBySk: const {},
      );
      expect(next.selected, {Programme.ncd, Programme.pnc});
      expect(next.dismissedBySk, {Programme.anc, Programme.pw});
    });
  });
}
