import '../../../core/models/programme.dart';

/// Pure helpers for the Step 1 eligible-services grid.
///
/// Keeps pathway ↔ SK selection merge rules testable without widget pumping.
abstract final class ProgrammeGridSync {
  ProgrammeGridSync._();

  /// Pathway activations that should be added to the SK's selection set.
  ///
  /// Never resurrects a programme the SK explicitly deselected in this visit
  /// ([dismissedBySk]) — even when the pathway engine still considers it active.
  static Set<Programme> additionsFromPathways({
    required Set<Programme> activated,
    required Set<Programme> selected,
    required Set<Programme> dismissedBySk,
  }) =>
      activated.difference(selected).difference(dismissedBySk);

  /// Enrolled programmes that may be auto-selected for *this* visit.
  ///
  /// Maternal programmes are gated by current state so a historical PNC
  /// enrollment does not force PNC forms onto a still-pregnant ANC visit
  /// (and vice versa). NCD / FP / other programmes stay eligible when enrolled.
  static Set<Programme> applicableEnrolledSeed({
    required Set<Programme> enrolled,
    required bool isPregnant,
    required bool isPostpartum,
  }) {
    return enrolled.where((p) {
      switch (p) {
        case Programme.anc:
        case Programme.pw:
          return isPregnant;
        case Programme.pnc:
          return isPostpartum;
        case Programme.unknown:
          return false;
        // FP: hidden during pregnancy; after delivery only once PNC is enrolled.
        case Programme.familyPlanning:
          if (isPregnant) return false;
          if (isPostpartum) return enrolled.contains(Programme.pnc);
          return true;
        // Other non-maternal programmes are always applicable when enrolled.
        case Programme.ncd:
        case Programme.cataract:
        case Programme.eyeCare:
        case Programme.epi:
        case Programme.imci:
          return true;
        // Excluded from selection regardless of enrolment — see
        // ServiceSelectionResolver.excludedFromSelection, the belt-and-
        // suspenders resolver-level filter this mirrors at the seed source.
        // tb: formType/manifest exists but form content isn't aligned yet.
        // nutrition: no formType exists yet (GAP 12).
        case Programme.tb:
        case Programme.nutrition:
          return false;
      }
    }).toSet();
  }

  /// Programmes a selected symptom's catalogue tag set should contribute to
  /// auto-selection. Excludes [Programme.imci]/[Programme.epi] unless
  /// [isChildVisitEligible] -- several everyday adult symptoms (fever,
  /// vomiting, edema, convulsions, unconscious, difficulty breathing) are
  /// cross-tagged with imci in `UnifiedSymptomCatalog` for clinical-rule
  /// relevance elsewhere, and folding that tag into an adult's selection
  /// would falsely mark the visit as a child visit (see
  /// `VisitFlowScreen._isChildVisit`), routing Step 2 to the immunisation
  /// timeline instead of the real programme form.
  static Set<Programme> catalogProgrammesFor(
    Set<Programme> symptomProgrammes, {
    required bool isChildVisitEligible,
  }) =>
      isChildVisitEligible
          ? symptomProgrammes
          : symptomProgrammes.difference({Programme.imci, Programme.epi});

  /// Apply Pregnancy Outcome (delivery) selection to the service grid.
  ///
  /// Clears **only** ANC and PW. Other selected programmes stay on; PNC is
  /// ensured so pregnancy-outcome / mother / child forms can open.
  static ({Set<Programme> selected, Set<Programme> dismissedBySk})
      applyDeliverySelected({
    required Set<Programme> selected,
    required Set<Programme> dismissedBySk,
  }) {
    final nextSelected = Set<Programme>.from(selected)
      ..remove(Programme.anc)
      ..remove(Programme.pw)
      ..add(Programme.pnc);
    final nextDismissed = Set<Programme>.from(dismissedBySk)
      ..add(Programme.anc)
      ..add(Programme.pw)
      ..remove(Programme.pnc);
    return (selected: nextSelected, dismissedBySk: nextDismissed);
  }

  /// Whether the Pregnancy Outcome (delivery) card should be locked
  /// (disabled) in the Step 1 service grid.
  ///
  /// When an open pregnancy episode exists, [isPregnant] alone isn't enough
  /// to unlock this — it's derived from three legacy signals (synced
  /// `pregnancyFacts`, `activeProgrammes.contains(Programme.pw)`, or a raw
  /// JSON flag on the patient record, see `PatientContextBuilder`) that can
  /// disagree with `PregnancyEpisodeDao`'s own open-episode row — e.g. a
  /// patient flagged pregnant by a stale/legacy signal but never actually
  /// registered (no open episode). This is the original bug this function
  /// was written to fix: *"Patient P1 is not registered for PW, still
  /// Pregnancy Outcome is showing."*
  ///
  /// When NO episode exists at all, though, Outcome is deliberately
  /// unlocked regardless of `isPregnant` — this supports an SK reaching a
  /// household *after* the child is already born, with no prior PW/ANC visit
  /// and therefore no local episode to check `isPregnant` against.
  /// Submitting in this state creates-and-closes a fresh episode in one
  /// shot (see `PregnancyEpisodeDao.closeEpisode` and
  /// `UnifiedFormNotifier._persistPregnancyEpisodeAfterSubmit`). Don't
  /// re-lock this branch — it's an intentional allowance, not a regression
  /// of the bug fix above.
  static bool isPregnancyOutcomeLocked({
    required bool isPregnant,
    required bool isPostpartum,
    required bool hasOpenPregnancyEpisode,
  }) {
    if (isPostpartum) return true;
    if (hasOpenPregnancyEpisode) return !isPregnant;
    return false;
  }
}
