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
        default:
          return true;
      }
    }).toSet();
  }
}
