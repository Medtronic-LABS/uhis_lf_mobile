/// CDS-aware form controller for the 3-step visit flow.
///
/// Extends [DynamicFormController] with live clinical decision support:
/// evaluates [CdsRules] on every field change and manages alert state.
/// Supports dynamic section injection triggered by [CdsAction.addPathway].
library;

import 'package:flutter/foundation.dart';

import '../../../core/models/programme.dart';
import '../../../uhis_form/controller/dynamic_form_controller.dart';
import '../../../uhis_form/models/section_schema.dart';
import 'cds_rules.dart';

class VisitFormController extends DynamicFormController {
  VisitFormController({
    required super.formSchema,
    required super.encounterId,
    required super.patientId,
    required super.draftDao,
    super.memberId,
    super.formType,
    super.restoredDraft,
    required Set<Programme> activePathways,
    this.onReferNow,
  }) : _activePathways = Set.unmodifiable(activePathways);

  final Set<Programme> _activePathways;

  /// Called when any urgent [CdsAction.referNow] alert fires.
  final VoidCallback? onReferNow;

  List<CdsAlert> _alerts = const [];
  final Set<String> _dismissedAlertIds = {};
  final List<SectionSchema> _injectedSections = [];

  List<CdsAlert> get alerts => List.unmodifiable(_alerts);
  List<SectionSchema> get injectedSections =>
      List.unmodifiable(_injectedSections);

  @override
  void setValue(String fieldId, dynamic value) {
    super.setValue(fieldId, value);
    _evaluateCds();
  }

  void dismissAlert(String alertId) {
    _dismissedAlertIds.add(alertId);
    _alerts = _alerts.where((a) => a.alertId != alertId).toList();
    notifyListeners();
  }

  /// Adds a section to the live form (e.g. TB section when cough ≥14d fires).
  ///
  /// No-op if a section with the same [SectionSchema.sectionId] is already
  /// present in the base schema or injected list.
  void addInjectedSection(SectionSchema section) {
    final alreadyInBase =
        formSchema.sections.any((s) => s.sectionId == section.sectionId);
    final alreadyInjected =
        _injectedSections.any((s) => s.sectionId == section.sectionId);
    if (alreadyInBase || alreadyInjected) return;
    _injectedSections.add(section);
    notifyListeners();
  }

  void _evaluateCds() {
    // Pass flat values so composite BP fields (SDK: {systolic, diastolic})
    // are expanded to individual keys that CdsRules expects.
    final flat = flatFieldValues;
    final raw = CdsRules.evaluate(flat, _activePathways);
    final updated =
        raw.where((a) => !_dismissedAlertIds.contains(a.alertId)).toList();

    final changed = updated.length != _alerts.length ||
        updated.any((a) => !_alerts.contains(a));
    if (!changed) return;

    _alerts = updated;
    notifyListeners();

    if (_alerts.any((a) =>
        a.action == CdsAction.referNow &&
        a.severity == CdsSeverity.urgent)) {
      onReferNow?.call();
    }
  }
}

/// Extension so callers can read [VisitFormController] from context
/// without losing type information.
extension VisitFormControllerExt on DynamicFormController {
  bool get hasVisitExtensions => this is VisitFormController;
}
