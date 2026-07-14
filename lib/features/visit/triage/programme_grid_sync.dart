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
}
