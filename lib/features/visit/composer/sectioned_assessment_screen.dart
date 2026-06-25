/// Sectioned assessment screen + viewmodel.
///
/// Renders all activated sections in a single scrollable view, grouped by
/// programme ("NCD checks", "TB checks", etc.).  CDS and TB injection are
/// evaluated live on every field change.
///
/// Engineering Design Standards:
///   - Widgets carry no business logic or I/O — all logic is in
///     [SectionedAssessmentViewModel].
///   - All UI copy routes through [ComposerStrings].
///   - [FormCompositor.compose] is called once from the viewmodel constructor —
///     pure, no I/O.
///   - Error handling: narrow exceptions only, mapped to localized strings
///     at the widget boundary.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/db/local_assessment_dao.dart';
import '../../../core/models/programme.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/widgets/ai_field_indicator.dart';
import '../pathway/pathway_engine.dart';
import '../triage/patient_context_builder.dart';
import '../triage/visit_step_header.dart';
import 'cds_banner.dart';
import 'cds_rules.dart';
import 'form_compositor.dart';
import 'form_section.dart';
import 'section_registry.dart';

// ── Private helpers ───────────────────────────────────────────────────────────

/// Returns the single "primary" programme for grouping purposes.
///
/// Sections with multiple programmes (shared sections like vitals) map to
/// [Programme.unknown] → "General checks" group.
Programme _sectionPrimaryProgramme(FormSection section) {
  if (section.programmes.isEmpty || section.programmes.length > 1) {
    return Programme.unknown;
  }
  return section.programmes.first;
}

/// Returns the group header label for a programme.
String _programmeGroupLabel(Programme p) {
  switch (p) {
    case Programme.ncd:
      return ComposerStrings.groupNcd;
    case Programme.tb:
      return ComposerStrings.groupTb;
    case Programme.anc:
      return ComposerStrings.groupAnc;
    case Programme.pnc:
      return ComposerStrings.groupPnc;
    case Programme.imci:
      return ComposerStrings.groupImci;
    case Programme.epi:
      return ComposerStrings.groupEpi;
    case Programme.nutrition:
      return ComposerStrings.groupNutrition;
    case Programme.familyPlanning:
      return ComposerStrings.groupFamilyPlanning;
    case Programme.cataract:
      return ComposerStrings.groupCataract;
    case Programme.eyeCare:
      return ComposerStrings.groupEyeCare;
    default:
      return ComposerStrings.groupGeneral;
  }
}

// ── ViewModel ─────────────────────────────────────────────────────────────────

/// State for the sectioned assessment screen.
///
/// Matches the [ChangeNotifier] pattern used in [TriageViewModel].
class SectionedAssessmentViewModel extends ChangeNotifier {
  SectionedAssessmentViewModel({
    required List<ActivatedPathway> pathways,
    required this.encounterId,
    required this.patientId,
    required this.householdMemberLocalId,
    this.memberId,
    required AssessmentDraftDao draftDao,
  })  : _pathways = List.unmodifiable(pathways),
        _draftDao = draftDao {
    _form = FormCompositor.compose(pathways);
    debugPrint('[SectionedAssessment] Form composed — ${_form.sections.length} sections: ${_form.sections.map((s) => s.sectionId).join(' → ')}');
    _sectionStatus = {
      for (final s in _form.sections) s.sectionId: 'pending',
    };
  }

  final List<ActivatedPathway> _pathways;
  final AssessmentDraftDao _draftDao;

  final String encounterId;
  final String patientId;
  final int householdMemberLocalId;
  final String? memberId;

  late ComposedForm _form;
  ComposedForm get form => _form;

  /// Current field values, updated as the SK fills the form.
  final Map<String, dynamic> _fieldValues = {};
  Map<String, dynamic> get fieldValues => Map.unmodifiable(_fieldValues);

  // ── Scribe pre-fill state (S4.4) ────────────────────────────────────────────

  /// Fields whose current value was pre-filled by the AI scribe service and
  /// has not yet been verified by the SK.
  final Map<String, dynamic> _scribePreFilled = {};

  /// Fields the SK has manually interacted with.  Scribe results must never
  /// overwrite these — SK input wins unconditionally.
  final Set<String> _skEnteredFields = {};

  /// Whether [fieldId] is currently holding an unverified scribe pre-fill.
  bool isScribePreFilled(String fieldId) =>
      _scribePreFilled.containsKey(fieldId);

  /// Unmapped clinical findings from the last scribe result (if any).
  List<String> _unmappedFindings = const [];
  List<String> get unmappedFindings => List.unmodifiable(_unmappedFindings);

  /// Apply a form_prefill result from the AI scribe service.
  ///
  /// For each field in [result.fields] whose confidence meets
  /// [AppConfig.scribeFieldConfidenceFloor]:
  ///   - Skip the field if the SK has already touched it ([_skEnteredFields]).
  ///   - Otherwise write the value to [_fieldValues] and record it in
  ///     [_scribePreFilled].
  ///
  /// This is a no-op when [AppConfig.scribeEnabled] is false.
  void applyScribePrefill(FormPrefillResult result) {
    if (!AppConfig.scribeEnabled) return;

    final floor = AppConfig.scribeFieldConfidenceFloor;
    int applied = 0;
    for (final extracted in result.fields) {
      if (extracted.confidence < floor) continue;
      if (_skEnteredFields.contains(extracted.fieldId)) continue;

      _scribePreFilled[extracted.fieldId] = extracted.value;
      _fieldValues[extracted.fieldId] = extracted.value;
      applied++;
    }
    _unmappedFindings = List.unmodifiable(result.unmappedFindings);

    debugPrint(
      '[SectionedAssessment] Scribe pre-filled $applied fields; '
      '${result.unmappedFindings.length} unmapped findings',
    );
    notifyListeners();
  }

  /// Called whenever the SK interacts with [fieldId].
  ///
  /// Removes it from [_scribePreFilled] (SK wins) and adds to [_skEnteredFields]
  /// so future scribe results never overwrite this field for this session.
  void markFieldTouched(String fieldId) {
    _scribePreFilled.remove(fieldId);
    _skEnteredFields.add(fieldId);
    // Do NOT notify — the widget already re-renders from setFieldValue.
  }

  /// Section completion status.
  late Map<String, String> _sectionStatus;
  Map<String, String> get sectionStatus => Map.unmodifiable(_sectionStatus);

  /// Whether the TB-added banner should be visible.
  bool _tbBannerVisible = false;
  bool get tbBannerVisible => _tbBannerVisible;

  /// Current CDS alerts — updated live on every field change.
  List<CdsAlert> _currentAlerts = const [];
  List<CdsAlert> get currentAlerts => List.unmodifiable(_currentAlerts);

  /// Alert IDs the SK has explicitly dismissed.
  final Set<String> _dismissedAlertIds = {};

  /// Whether an async operation (save) is in progress.
  bool _isSaving = false;
  bool get isSaving => _isSaving;

  /// Error message to surface to the user (localized).
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Update a single field value, evaluating CDS and TB injection live.
  void setFieldValue(String fieldId, dynamic value) {
    _fieldValues[fieldId] = value;
    _checkTbInjection();
    _evaluateCds();
    notifyListeners();
  }

  /// Mark all sections done, persist the draft, and signal readiness for
  /// final submission.
  Future<void> submitAll() async {
    for (final section in _form.sections) {
      _sectionStatus[section.sectionId] = 'done';
    }
    _errorMessage = null;
    await _saveDraft();
    notifyListeners();
  }

  /// Inject TB section if cough ≥ 14 days is detected and not yet present.
  void _checkTbInjection() {
    final hasCough = _fieldValues['hasCough'];
    final coughDays = _fieldValues['coughDays'];
    final hasTbSection =
        _form.sections.any((s) => s.sectionId == 'tb-screen-detail');

    if (hasCough == true &&
        coughDays is int &&
        coughDays >= 14 &&
        !hasTbSection) {
      _injectTbSection();
      _tbBannerVisible = true;
    }
  }

  /// Evaluate CDS rules against current field values and active pathways.
  ///
  /// Any alert whose [CdsAlert.action] is [CdsAction.addPathway] and whose
  /// pathway is not yet in the form is inserted automatically.
  void _evaluateCds() {
    final activePathways =
        _pathways.map((p) => p.programme).toSet();
    final allAlerts = CdsRules.evaluate(_fieldValues, activePathways);

    // Filter out already-dismissed alerts.
    _currentAlerts = allAlerts
        .where((a) => !_dismissedAlertIds.contains(a.alertId))
        .toList();

    // Auto-insert sections for addPathway alerts.
    for (final alert in _currentAlerts) {
      if (alert.action == CdsAction.addPathway && alert.addPathway != null) {
        addPathwayFromCds(alert.addPathway!);
      }
    }
  }

  /// Dismiss the TB-added banner.
  void dismissTbBanner() {
    _tbBannerVisible = false;
    notifyListeners();
  }

  /// Dismiss a specific CDS alert by [alertId].
  void dismissAlert(String alertId) {
    _dismissedAlertIds.add(alertId);
    _currentAlerts =
        _currentAlerts.where((a) => a.alertId != alertId).toList();
    notifyListeners();
  }

  /// Insert a pathway section into the composed form (CDS-triggered addPathway).
  ///
  /// If [programme]'s sections are already present, this is a no-op.
  void addPathwayFromCds(Programme programme) {
    // Check if any section for this programme is already composed.
    final alreadyPresent =
        _form.sections.any((s) => s.programmes.contains(programme));
    if (alreadyPresent) return;

    final newPathways = [
      ..._pathways,
      ActivatedPathway(
        programme: programme,
        priority: 90,
        confidence: 1.0,
        trigger: PathwayTrigger.rule,
        rationaleKey: 'pathwayManualRationale',
        triggerFlags: const {'CDS_TRIGGERED'},
      ),
    ];
    _form = FormCompositor.compose(newPathways);
    _sectionStatus = {
      for (final s in _form.sections)
        s.sectionId: _sectionStatus[s.sectionId] ?? 'pending',
    };
    notifyListeners();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _injectTbSection() {
    final tbSection = SectionRegistry.byId('tb-screen-detail');
    if (tbSection == null) return;

    // Rebuild the composed form with the TB section appended.
    final newPathways = [
      ..._pathways,
      ActivatedPathway(
        programme: tbSection.programmes.first,
        priority: 90,
        confidence: 1.0,
        trigger: PathwayTrigger.rule,
        rationaleKey: 'pathwayTbScreenRationale',
        triggerSymptoms: const {'cough_over_2_weeks'},
      ),
    ];
    _form = FormCompositor.compose(newPathways);
    _sectionStatus = {
      for (final s in _form.sections)
        s.sectionId: _sectionStatus[s.sectionId] ?? 'pending',
    };
  }

  Future<void> _saveDraft() async {
    _isSaving = true;
    notifyListeners();
    try {
      final programmes = _pathways.map((p) => p.programme.wireTag).toList();
      final draft = AssessmentDraftRow(
        encounterId: encounterId,
        patientId: patientId,
        memberId: memberId,
        activatedProgrammes: jsonEncode(programmes),
        fieldValues: jsonEncode(_fieldValues),
        sectionStatus: jsonEncode(_sectionStatus),
      );
      await _draftDao.saveDraft(draft);
    } on DatabaseException catch (e) {
      debugPrint('[SectionedAssessmentViewModel] Draft save failed: $e');
      _errorMessage = 'Could not save draft — data is preserved in memory.';
    } finally {
      _isSaving = false;
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Renders all activated assessment sections in a single scrollable view.
///
/// Sections are grouped by programme ("NCD checks", "TB checks", etc.) with
/// visual group headers.  CDS and TB injection evaluate live on every field
/// change.  A single "Submit Assessment" button appears at the bottom.
class SectionedAssessmentScreen extends StatefulWidget {
  const SectionedAssessmentScreen({
    super.key,
    required this.pathways,
    required this.patientContext,
    required this.encounterId,
    required this.patientId,
    required this.householdMemberLocalId,
    this.memberId,
    required this.draftDao,
    this.onSubmit,
    this.onReferNow,
  });

  final List<ActivatedPathway> pathways;
  final PatientContext patientContext;
  final String encounterId;
  final String patientId;
  final int householdMemberLocalId;
  final String? memberId;
  final AssessmentDraftDao draftDao;

  /// Callback invoked when the SK taps Submit and the draft is persisted.
  final VoidCallback? onSubmit;

  /// Callback invoked when a CDS alert triggers an immediate referral.
  ///
  /// [alertId] is the stable alert identifier (e.g. `'bp_severe'`).
  /// The caller is responsible for opening the referral flow and pre-filling
  /// the reason from the alert.
  final void Function(String alertId)? onReferNow;

  @override
  State<SectionedAssessmentScreen> createState() =>
      _SectionedAssessmentScreenState();
}

class _SectionedAssessmentScreenState
    extends State<SectionedAssessmentScreen> {
  late SectionedAssessmentViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SectionedAssessmentViewModel(
      pathways: widget.pathways,
      encounterId: widget.encounterId,
      patientId: widget.patientId,
      householdMemberLocalId: widget.householdMemberLocalId,
      memberId: widget.memberId,
      draftDao: widget.draftDao,
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => _SectionedAssessmentView(
        viewModel: _viewModel,
        onSubmit: widget.onSubmit,
        onReferNow: widget.onReferNow,
      ),
    );
  }
}

/// Stateless inner view — all state lives in the viewmodel.
class _SectionedAssessmentView extends StatelessWidget {
  const _SectionedAssessmentView({
    required this.viewModel,
    this.onSubmit,
    this.onReferNow,
  });

  final SectionedAssessmentViewModel viewModel;
  final VoidCallback? onSubmit;
  final void Function(String alertId)? onReferNow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: VisitStepHeader(
        step: VisitStep.detailedForm,
        patientLabel: 'Assessment',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Column(
        children: [
          // ── TB added banner ────────────────────────────────────────────────
          if (viewModel.tbBannerVisible)
            _TbAddedBanner(onDismiss: viewModel.dismissTbBanner),

          // ── CDS alert banners ──────────────────────────────────────────────
          for (final alert in viewModel.currentAlerts)
            CdsBanner(
              alert: alert,
              onReferNow: alert.action == CdsAction.referNow
                  ? () => onReferNow?.call(alert.alertId)
                  : null,
              onAddPathway: alert.action == CdsAction.addPathway
                  ? () => viewModel.addPathwayFromCds(alert.addPathway!)
                  : null,
              onDismiss: () => viewModel.dismissAlert(alert.alertId),
            ),

          // ── Error message ──────────────────────────────────────────────────
          if (viewModel.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                viewModel.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          // ── All sections scrollable ────────────────────────────────────────
          Expanded(
            child: _AllSectionsBody(
              sections: viewModel.form.sections,
              fieldValues: viewModel.fieldValues,
              onFieldChanged: viewModel.setFieldValue,
              isScribePreFilled: viewModel.isScribePreFilled,
              onFieldTouched: viewModel.markFieldTouched,
              unmappedFindings: viewModel.unmappedFindings,
            ),
          ),

          // ── Submit button ──────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _SubmitButton(
                isSaving: viewModel.isSaving,
                onPressed: viewModel.isSaving
                    ? null
                    : () => viewModel.submitAll().then((_) => onSubmit?.call()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TbAddedBanner extends StatelessWidget {
  const _TbAddedBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(ComposerStrings.tbAddedBannerText),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text(ComposerStrings.dismissOkButton),
        ),
      ],
    );
  }
}

/// Renders all sections in a single scrollable list, grouped by programme.
///
/// Inserts a [_ProgrammeGroupHeader] whenever the primary programme changes.
/// Sections with no visible fields are omitted to keep the form clean.
class _AllSectionsBody extends StatelessWidget {
  const _AllSectionsBody({
    required this.sections,
    required this.fieldValues,
    required this.onFieldChanged,
    required this.isScribePreFilled,
    required this.onFieldTouched,
    this.unmappedFindings = const [],
  });

  final List<FormSection> sections;
  final Map<String, dynamic> fieldValues;
  final void Function(String fieldId, dynamic value) onFieldChanged;
  final bool Function(String fieldId) isScribePreFilled;
  final void Function(String fieldId) onFieldTouched;
  final List<String> unmappedFindings;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    String? lastGroupLabel;

    for (final section in sections) {
      final visibleFields = section.fields
          .where((f) =>
              f.visibleWhen == null || f.visibleWhen!.evaluate(fieldValues))
          .toList();

      if (visibleFields.isEmpty) continue;

      final groupLabel =
          _programmeGroupLabel(_sectionPrimaryProgramme(section));
      if (groupLabel != lastGroupLabel) {
        items.add(_ProgrammeGroupHeader(label: groupLabel));
        lastGroupLabel = groupLabel;
      }

      items.add(_SectionBlock(
        sectionId: section.sectionId,
        fields: visibleFields,
        fieldValues: fieldValues,
        onFieldChanged: onFieldChanged,
        isScribePreFilled: isScribePreFilled,
        onFieldTouched: onFieldTouched,
      ));
    }

    if (unmappedFindings.isNotEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _UnmappedFindingsCard(findings: unmappedFindings),
      ));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: items,
    );
  }
}

/// Coloured group header — rendered once per programme group.
class _ProgrammeGroupHeader extends StatelessWidget {
  const _ProgrammeGroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.tagBlueText.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.medical_services_outlined,
            size: 14,
            color: AppColors.tagBlueText,
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: AppColors.tagBlueText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the section subtitle and its visible fields.
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.sectionId,
    required this.fields,
    required this.fieldValues,
    required this.onFieldChanged,
    required this.isScribePreFilled,
    required this.onFieldTouched,
  });

  final String sectionId;
  final List<FieldDef> fields;
  final Map<String, dynamic> fieldValues;
  final void Function(String fieldId, dynamic value) onFieldChanged;
  final bool Function(String fieldId) isScribePreFilled;
  final void Function(String fieldId) onFieldTouched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = ComposerStrings.sectionTitle(sectionId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (int i = 0; i < fields.length; i++) ...[
                _FieldWidget(
                  field: fields[i],
                  currentValue: fieldValues[fields[i].fieldId],
                  isScribePreFilled: isScribePreFilled(fields[i].fieldId),
                  onChanged: (value) {
                    onFieldTouched(fields[i].fieldId);
                    onFieldChanged(fields[i].fieldId, value);
                  },
                ),
                if (i < fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// Info card shown at the bottom of the form when the scribe detected
/// clinical findings that didn't map to any registered field.
class _UnmappedFindingsCard extends StatelessWidget {
  const _UnmappedFindingsCard({required this.findings});

  final List<String> findings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  ComposerStrings.unmappedFindingsTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...findings.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $f',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal field widget — renders the correct input type per [FieldType].
///
/// When [isScribePreFilled] is true the field is wrapped with a light blue
/// background tint and an "AI" chip via [ConfidenceBadge], signalling that
/// the value came from the AI scribe and should be verified by the SK.
class _FieldWidget extends StatelessWidget {
  const _FieldWidget({
    required this.field,
    required this.currentValue,
    required this.onChanged,
    this.isScribePreFilled = false,
  });

  final FieldDef field;
  final dynamic currentValue;
  final ValueChanged<dynamic> onChanged;
  final bool isScribePreFilled;

  String get _label => ComposerStrings.fieldLabel(field.labelKey);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputWidget = _buildInput(context);

    if (!isScribePreFilled) return inputWidget;

    // Wrap with a scribe pre-fill visual indicator (light blue tint + AI chip).
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          inputWidget,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const ConfidenceBadge(confidence: 0.75, showLabel: true),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    ComposerStrings.scribeAiPreFilledHint,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    switch (field.type) {
      case FieldType.booleanField:
        return SwitchListTile(
          title: Text(_label),
          value: currentValue as bool? ?? false,
          onChanged: onChanged,
        );

      case FieldType.intField:
      case FieldType.doubleField:
        return TextFormField(
          decoration: InputDecoration(
            labelText: _label,
            suffixText: field.unit,
            border: const OutlineInputBorder(),
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          initialValue: currentValue?.toString(),
          onChanged: (text) {
            if (field.type == FieldType.intField) {
              final v = int.tryParse(text);
              if (v != null) onChanged(v);
            } else {
              final v = double.tryParse(text);
              if (v != null) onChanged(v);
            }
          },
        );

      case FieldType.selectField:
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: _label,
            border: const OutlineInputBorder(),
          ),
          initialValue: currentValue as String?,
          items: (field.options ?? [])
              .map((opt) =>
                  DropdownMenuItem(value: opt, child: Text(opt)))
              .toList(),
          onChanged: onChanged,
        );

      case FieldType.multiSelectField:
        // Multi-select: currentValue is List<String>.
        final selected =
            (currentValue as List<dynamic>?)?.cast<String>() ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            ...(field.options ?? []).map((opt) {
              final isSelected = selected.contains(opt);
              return CheckboxListTile(
                title: Text(opt),
                value: isSelected,
                onChanged: (checked) {
                  final newList = List<String>.from(selected);
                  if (checked == true) {
                    newList.add(opt);
                  } else {
                    newList.remove(opt);
                  }
                  onChanged(newList);
                },
              );
            }),
          ],
        );

      case FieldType.textField:
        return TextFormField(
          decoration: InputDecoration(
            labelText: _label,
            border: const OutlineInputBorder(),
          ),
          initialValue: currentValue as String?,
          onChanged: onChanged,
        );
    }
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.isSaving,
    required this.onPressed,
  });

  final bool isSaving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.pink,
        ),
        onPressed: onPressed,
        child: isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(ComposerStrings.submitButton),
      ),
    );
  }
}
