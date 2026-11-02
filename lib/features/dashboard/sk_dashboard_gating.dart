import '../visit/forms/form_config.dart';

/// Leapfrog app is SK-only: NCD / eye / cataract tiles follow activated workflows
/// (Spice `hasNcdWorkflow()` etc.), not FO/PO-only dashboard rules.
/// CD Services programme tab is omitted in [SkDashboardCardCatalog.programmeCategories].
class SkDashboardGating {
  const SkDashboardGating({
    required this.showNcd,
    required this.showEyeCare,
    required this.showCataract,
  });

  final bool showNcd;
  final bool showEyeCare;
  final bool showCataract;

  /// Spice `getClinicalWorkflowWorkflowNamesLower()` — here, synced form types
  /// that indicate an activated clinical workflow on this SK install.
  factory SkDashboardGating.fromFormConfig() {
    try {
      final slugs =
          FormConfig.instance.forms.keys.map((k) => k.toLowerCase()).toSet();
      return SkDashboardGating(
        showNcd: slugs.contains('ncd'),
        showEyeCare: slugs.contains('eye_care'),
        showCataract: slugs.contains('cataract'),
      );
    } catch (_) {
      return const SkDashboardGating(
        showNcd: false,
        showEyeCare: false,
        showCataract: false,
      );
    }
  }
}
