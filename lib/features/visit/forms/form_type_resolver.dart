/// Expands Programme enum names (from triage) to the formType keys used by
/// `layout_manifests.json` and `UnifiedPayloadMapper`.
abstract final class FormTypeResolver {
  FormTypeResolver._();

  /// Rules:
  /// - Delivery visit → `pregnancyOutcome` first, then `pncMother`/`pncChild`,
  ///   then any other selected programmes (ANC/PW excluded — cleared at triage).
  /// - `pnc`  → `pncMother` + `pncChild`
  /// - `pw`   → `pwProfile`
  /// - `imci` → `iccm`
  /// - others → passed through (with eyeCare / familyPlanning wire aliases)
  static List<String> resolve(
    List<String> programmeNames, {
    bool isDelivery = false,
  }) {
    final out = <String>[];
    if (isDelivery) {
      // Birth documentation before mother/child PNC (Android parity).
      out.addAll(['pregnancyOutcome', 'pncMother', 'pncChild']);
    }

    for (final p in programmeNames) {
      // Delivery visit already seeds pregnancy-outcome + PNC; ANC/PW must not
      // reopen after the triage gate cleared them.
      if (isDelivery &&
          (p == 'pnc' || p == 'anc' || p == 'pw' || p == 'pregnancyOutcome')) {
        continue;
      }
      switch (p) {
        case 'pnc':
          out.addAll(['pncMother', 'pncChild']);
        case 'imci':
          out.add('iccm');
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
