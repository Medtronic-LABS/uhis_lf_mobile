/// Expands Programme enum names (from triage) to the formType keys used by
/// `layout_manifests.json` and `UnifiedPayloadMapper`.
abstract final class FormTypeResolver {
  FormTypeResolver._();

  /// Rules:
  /// - Delivery visit → `pregnancyOutcome` first; `pncMother` only when
  ///   `pnc` is in the programme list (PO+PNC optional on same visit).
  /// - `pnc`  → `pncMother` (Spice mother PNC; childhood is a separate menu)
  /// - `pw`   → `pwProfile`
  /// - `imci` → `pncChild` (Spice Childhood Visit / Child Health card)
  /// - others → passed through (with eyeCare / familyPlanning wire aliases)
  static List<String> resolve(
    List<String> programmeNames, {
    bool isDelivery = false,
  }) {
    final out = <String>[];
    if (isDelivery) {
      out.add('pregnancyOutcome');
    }

    for (final p in programmeNames) {
      // Delivery visit already seeds pregnancy-outcome; ANC/PW must not
      // reopen after the triage gate cleared them.
      if (isDelivery &&
          (p == 'anc' || p == 'pw' || p == 'pregnancyOutcome')) {
        continue;
      }
      switch (p) {
        case 'pnc':
          out.add('pncMother');
        case 'imci':
          out.add('pncChild');
        case 'pw':
          // PW registration — show only the pwProfile layout.
          out.add('pwProfile');
        case 'eyeCare':
          out.add('eye_care');
        case 'familyPlanning':
          out.add('family_planning');
        default:
          out.add(p);
      }
    }
    return out;
  }
}
