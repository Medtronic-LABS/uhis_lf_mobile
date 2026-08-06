import '../../../core/models/programme.dart';

/// Why [ServiceSelectionResolver.finalize] blocked a programme and the SK
/// must be told before the visit can proceed. `null` on
/// [ServiceSelectionResult.blockedReason] means nothing needs a dialog —
/// see [ServiceSelectionResult.silentlyEmptied] for the no-dialog case.
enum ServiceSelectionBlockReason {
  /// ANC removed — patient is within the postpartum window (PNC/delivery
  /// already recorded).
  ancBlockedPostpartum,

  /// ANC removed — the risk-based revisit interval since the last ANC visit
  /// hasn't elapsed yet (1 day if that visit was high-risk, else 15 days).
  ancBlockedRevisit,
}

/// Result of finalizing a visit's service selection.
class ServiceSelectionResult {
  const ServiceSelectionResult({
    required this.programmes,
    this.blockedReason,
    this.silentlyEmptied = false,
  });

  /// The final, priority-ordered set of programmes for this visit.
  final Set<Programme> programmes;

  /// True when a silent drop (no dialog) left [programmes] empty — e.g. PW
  /// was the only selection and got dropped because it's already
  /// registered. The caller should show an inline hint, not a dialog, and
  /// let the SK pick a different service.
  final bool silentlyEmptied;

  /// Set when a rule removed a programme in a way the SK must be told about
  /// via a dialog (see [ServiceSelectionBlockReason]).
  final ServiceSelectionBlockReason? blockedReason;
}

/// Single authoritative choke point for finalizing a visit's service
/// selection — all business-rule gating that used to live in Step 2
/// (`_Step2ProgrammesThenFormState._hydrate()`) now runs here, in Step 1,
/// before the SK ever leaves the triage screen.
///
/// Pure, unit-testable class (no `BuildContext`, no I/O) — follows the same
/// convention as [ProgrammeGridSync] in this directory.
abstract final class ServiceSelectionResolver {
  ServiceSelectionResolver._();

  /// Canonical clinical-priority order (lower = higher priority), replacing
  /// the duplicate inline `priorityByProgramme` maps that used to live in
  /// `SymptomPickerScreen._doAdvance`'s two fallback branches.
  static const Map<Programme, int> canonicalPriority = {
    Programme.imci: 10,
    Programme.pw: 15,
    Programme.anc: 20,
    Programme.pnc: 25,
    Programme.tb: 30,
    Programme.nutrition: 35,
    Programme.ncd: 40,
    Programme.familyPlanning: 45,
    Programme.cataract: 46,
    Programme.eyeCare: 47,
    Programme.epi: 100,
    Programme.unknown: 999,
  };

  /// Programmes excluded from the selectable set regardless of how they
  /// entered it (rule engine, catalogue tags, enrolled-programme seed, or
  /// server wire-tag parsing) — deliberately stricter than
  /// [Programme.kPilotProgrammes]:
  /// - [Programme.nutrition] — no `nutrition` formType exists yet in
  ///   `layout_manifests.json` (tracked as GAP 12 in
  ///   `unified_payload_mapper.dart`); without this filter it silently
  ///   renders a blank form.
  /// - [Programme.tb] — has a `tb` formType/manifest on disk, but the form
  ///   content isn't yet aligned/ready; intentionally paused despite being
  ///   listed in [Programme.kPilotProgrammes].
  ///
  /// [Programme.epi] is deliberately NOT excluded here — its only real entry
  /// point is `VisitFlowScreen._isChildVisit` routing to the already-working
  /// `_Step2Vaccination` immunisation path, which never touches
  /// `FormTypeResolver`/`layout_manifests.json`; filtering it here would risk
  /// regressing that working feature for no actual bug fixed.
  static const Set<Programme> excludedFromSelection = {
    Programme.nutrition,
    Programme.tb,
  };

  /// Finalizes the SK's Step-1 selection into the set Step 2 will render.
  ///
  /// Ports, in order, the 4 rules that used to run in Step 2's
  /// `_hydrate()`:
  /// 1. Delivery visits always include PNC.
  /// 2. **PW-once-only** — dropped silently when [pwRegistrationBlocked].
  ///    If that empties the selection, returns immediately with
  ///    [ServiceSelectionResult.silentlyEmptied] (no further rules run —
  ///    matches the original code's immediate home-navigation branch).
  /// 3. **ANC blocked postpartum** — removed with
  ///    [ServiceSelectionBlockReason.ancBlockedPostpartum] when
  ///    [isPostpartum].
  /// 4. **ANC blocked by revisit interval** — removed with
  ///    [ServiceSelectionBlockReason.ancBlockedRevisit] when
  ///    [ancRevisitBlocked] (1 day since last ANC visit if it was
  ///    high-risk, else 15 days — computed by the caller).
  /// 5. **PW auto-add** — added alongside a first-time (not
  ///    [pwRegistrationBlocked]) ANC selection.
  ///
  /// Finally applies [excludedFromSelection] and returns the surviving set
  /// ordered by [canonicalPriority].
  static ServiceSelectionResult finalize({
    required Set<Programme> selected,
    required bool pwRegistrationBlocked,
    required bool isPostpartum,
    required bool ancRevisitBlocked,
    bool isDeliveryVisit = false,
  }) {
    var programmes = Set<Programme>.from(selected);

    if (isDeliveryVisit) {
      programmes.add(Programme.pnc);
    }

    // Pilot-scope exclusion — silent, applies regardless of how the
    // programme entered the set.
    programmes = programmes.difference(excludedFromSelection);

    // Task 3 — PW once-only: drop PW silently if already registered/blocked.
    if (programmes.contains(Programme.pw) && pwRegistrationBlocked) {
      programmes.remove(Programme.pw);
    }
    if (programmes.isEmpty && selected.isNotEmpty) {
      return const ServiceSelectionResult(
        programmes: {},
        silentlyEmptied: true,
      );
    }

    final hasAnc = programmes.contains(Programme.anc);

    // Task 2 — block ANC when postpartum (PNC/delivery already recorded).
    if (hasAnc && isPostpartum) {
      programmes.remove(Programme.anc);
      return ServiceSelectionResult(
        programmes: _ordered(programmes),
        blockedReason: ServiceSelectionBlockReason.ancBlockedPostpartum,
      );
    }

    // Task 1 — block ANC within the risk-based revisit interval.
    if (hasAnc && ancRevisitBlocked) {
      programmes.remove(Programme.anc);
      return ServiceSelectionResult(
        programmes: _ordered(programmes),
        blockedReason: ServiceSelectionBlockReason.ancBlockedRevisit,
      );
    }

    // Task 5 — auto-include PW alongside a first-time ANC selection so the
    // pregnancy profile is submitted alongside the ANC visit. Registered
    // women are skipped — adding PW here would submit a duplicate PWPROFILE.
    if (hasAnc &&
        !pwRegistrationBlocked &&
        !programmes.contains(Programme.pw)) {
      programmes.add(Programme.pw);
    }

    return ServiceSelectionResult(programmes: _ordered(programmes));
  }

  /// Resolves the "primary" programme from an ordered list of programme-name
  /// strings (e.g. `VisitFormScreen.activatedPathways`, built from
  /// [finalize]'s already priority-ordered output) — the first name that
  /// maps to a known [Programme], skipping [Programme.unknown].
  static Programme primaryFrom(List<String> orderedProgrammeNames) {
    for (final name in orderedProgrammeNames) {
      final p = Programme.fromString(name);
      if (p != Programme.unknown) return p;
    }
    return Programme.unknown;
  }

  /// Sorts [programmes] by [canonicalPriority], preserving that order in the
  /// returned `Set`'s iteration order (Dart's default `Set` is insertion
  /// ordered).
  static Set<Programme> _ordered(Set<Programme> programmes) {
    final sorted = programmes.toList()
      ..sort((a, b) =>
          (canonicalPriority[a] ?? 999).compareTo(canonicalPriority[b] ?? 999));
    return Set<Programme>.from(sorted);
  }
}
