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

    test('never seeds tb or nutrition even when enrolled (paused pending form alignment)',
        () {
      final seeded = ProgrammeGridSync.applicableEnrolledSeed(
        enrolled: {Programme.ncd, Programme.tb, Programme.nutrition},
        isPregnant: false,
        isPostpartum: false,
      );
      expect(seeded, {Programme.ncd});
    });
  });

  group('ProgrammeGridSync.catalogProgrammesFor', () {
    test('drops imci/epi for a symptom cross-tagged with them when not under-5', () {
      final result = ProgrammeGridSync.catalogProgrammesFor(
        {Programme.imci, Programme.anc, Programme.tb},
        isChildVisitEligible: false,
      );
      expect(result, {Programme.anc, Programme.tb});
    });

    test('keeps imci/epi for the same tag set when the patient is under-5', () {
      final result = ProgrammeGridSync.catalogProgrammesFor(
        {Programme.imci, Programme.anc, Programme.tb},
        isChildVisitEligible: true,
      );
      expect(result, {Programme.imci, Programme.anc, Programme.tb});
    });

    test('unaffected when the symptom carries no imci/epi tag', () {
      final result = ProgrammeGridSync.catalogProgrammesFor(
        {Programme.ncd},
        isChildVisitEligible: false,
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

  // ===========================================================================
  // Regression: Pregnancy Outcome must not be selectable without an actual
  // open pregnancy episode. Previously the card's lock only checked the
  // legacy `isPregnant` flag (derived from synced pregnancyFacts / enrolled
  // programmes / a raw JSON flag — see PatientContextBuilder), independent of
  // PregnancyEpisodeDao's own open-episode row. A patient could be flagged
  // pregnant by a stale legacy signal with no actual PW registration, and
  // Pregnancy Outcome would still show as available — offering to record the
  // outcome of a pregnancy that was never formally registered. Found via
  // manual device testing: "Patient P1 is not registered for PW, still
  // Pregnancy Outcome is showing."
  // ===========================================================================
  group('ProgrammeGridSync.isPregnancyOutcomeLocked', () {
    test('locked when not pregnant at all', () {
      final locked = ProgrammeGridSync.isPregnancyOutcomeLocked(
        isPregnant: false,
        isPostpartum: false,
        hasOpenPregnancyEpisode: false,
      );
      expect(locked, isTrue);
    });

    test(
        'BUG SCENARIO: locked when isPregnant flag is true but there is no '
        'open pregnancy episode (never actually registered for PW)', () {
      final locked = ProgrammeGridSync.isPregnancyOutcomeLocked(
        isPregnant: true,
        isPostpartum: false,
        hasOpenPregnancyEpisode: false,
      );
      expect(locked, isTrue,
          reason: 'Nothing was ever registered via PW — there is no '
              'pregnancy episode to record an outcome for, regardless of '
              'what the legacy isPregnant flag says.');
    });

    test('unlocked when pregnant AND an open pregnancy episode exists', () {
      final locked = ProgrammeGridSync.isPregnancyOutcomeLocked(
        isPregnant: true,
        isPostpartum: false,
        hasOpenPregnancyEpisode: true,
      );
      expect(locked, isFalse,
          reason: 'A real, open PW registration exists — this is the '
              'normal case where recording the outcome makes sense.');
    });

    test('locked when already postpartum, even with a stale open episode flag', () {
      final locked = ProgrammeGridSync.isPregnancyOutcomeLocked(
        isPregnant: true,
        isPostpartum: true,
        hasOpenPregnancyEpisode: true,
      );
      expect(locked, isTrue,
          reason: 'Outcome already recorded once postpartum — should not '
              'be offered again.');
    });

    test('locked when an episode exists but the legacy isPregnant flag is false', () {
      final locked = ProgrammeGridSync.isPregnancyOutcomeLocked(
        isPregnant: false,
        isPostpartum: false,
        hasOpenPregnancyEpisode: true,
      );
      expect(locked, isTrue,
          reason: 'Both signals must agree there is an active, open '
              'pregnancy — a lagging/unsynced legacy flag should not by '
              'itself unlock the card either.');
    });
  });
}
