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
  // Regression: when an open pregnancy episode DOES exist, Pregnancy Outcome
  // must not be selectable based on the legacy `isPregnant` flag alone.
  // Previously the card's lock only checked that flag (derived from synced
  // pregnancyFacts / enrolled programmes / a raw JSON flag — see
  // PatientContextBuilder), independent of PregnancyEpisodeDao's own
  // open-episode row. A patient could be flagged pregnant by a stale legacy
  // signal with no actual PW registration, and Pregnancy Outcome would still
  // show as available — offering to record the outcome of a pregnancy that
  // was never formally registered. Found via manual device testing: "Patient
  // P1 is not registered for PW, still Pregnancy Outcome is showing."
  //
  // Deliberately narrower than the original fix: when NO episode exists at
  // all, Outcome is now allowed regardless of `isPregnant` — direct entry for
  // an SK reaching a household after the child is already born, with no
  // prior PW/ANC visit. See the two tests below with `hasOpenPregnancyEpisode:
  // false` — they now expect `isFalse`, not a regression of the bug above.
  // ===========================================================================
  group('ProgrammeGridSync.isPregnancyOutcomeLocked', () {
    test('unlocked for direct entry — not pregnant, no episode, not postpartum', () {
      final locked = ProgrammeGridSync.isPregnancyOutcomeLocked(
        isPregnant: false,
        isPostpartum: false,
        hasOpenPregnancyEpisode: false,
      );
      expect(locked, isFalse,
          reason: 'No episode exists — this is the direct-entry case (SK '
              'reached the household after delivery, no prior PW/ANC visit). '
              'The legacy isPregnant flag has nothing to say when there is no '
              'episode to check it against.');
    });

    test(
        'unlocked for direct entry even when the legacy isPregnant flag is '
        'true, as long as no episode exists', () {
      final locked = ProgrammeGridSync.isPregnancyOutcomeLocked(
        isPregnant: true,
        isPostpartum: false,
        hasOpenPregnancyEpisode: false,
      );
      expect(locked, isFalse,
          reason: 'Same direct-entry case — nothing was ever registered via '
              'PW, but that is exactly the scenario this unlocks for, not a '
              'reason to keep it locked.');
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
