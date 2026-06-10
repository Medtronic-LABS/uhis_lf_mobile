/// Sectioned assessment screen + viewmodel.
///
/// Renders sections sequentially, saving drafts per section and revealing
/// `tb-screen-detail` dynamically when coughDays ≥ 14.
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/db/local_assessment_dao.dart';
import '../../../core/models/programme.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/widgets/ai_field_indicator.dart';
import '../pathway/pathway_engine.dart';
import '../triage/patient_context_builder.dart';
import 'cds_banner.dart';
import 'cds_rules.dart';
import 'form_compositor.dart';
import 'form_section.dart';
import 'section_registry.dart';

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

  /// Index of the section currently being rendered (0-based).
  int _currentSectionIndex = 0;
  int get currentSectionIndex => _currentSectionIndex;

  /// Whether the TB-added banner should be visible.
  bool _tbBannerVisible = false;
  bool get tbBannerVisible => _tbBannerVisible;

  /// Current CDS alerts — updated after each section completes.
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

  // ── Derived ───────────────────────────────────────────────────────────────

  FormSection get currentSection =>
      _form.sections[_currentSectionIndex];

  int get totalSections => _form.sections.length;

  bool get isLastSection => _currentSectionIndex >= totalSections - 1;

  bool get isAllDone =>
      _sectionStatus.values.every((s) => s == 'done');

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Update the value of a single field.
  void setFieldValue(String fieldId, dynamic value) {
    _fieldValues[fieldId] = value;
    notifyListeners();
  }

  /// Mark the current section done, persist a draft, and advance.
  ///
  /// Cross-section reveal: after `symptom-detail`, if coughDays ≥ 14 and
  /// `tb-screen-detail` is not already active, inject it into the composed
  /// form and show the banner.
  Future<void> completeCurrentSection() async {
    final sectionId = currentSection.sectionId;
    _sectionStatus[sectionId] = 'done';
    _errorMessage = null;

    // Cross-section reveal: TB screening for extended cough.
    if (sectionId == 'symptom-detail') {
      final coughDays = _fieldValues['coughDays'];
      final hasCough = _fieldValues['hasCough'];
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

    // CDS evaluation — pure, synchronous, no I/O.
    _evaluateCds();

    await _saveDraft();

    // Advance to next section if not at the end.
    if (!isLastSection) {
      _currentSectionIndex++;
    }
    notifyListeners();
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

/// Renders the sectioned assessment form.
///
/// Takes an already-activated list of [pathways] (from the triage step) and
/// renders them as sequentially completed form sections with per-section draft
/// saves.
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

  /// Callback invoked when all sections are marked done.
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

  /// Callback for referral flow entry — supplied by the parent screen.
  /// Receives the alertId so the caller can pre-fill the referral form.
  final void Function(String alertId)? onReferNow;

  @override
  Widget build(BuildContext context) {
    final current = viewModel.currentSection;
    final sectionTitle = ComposerStrings.sectionTitle(current.sectionId);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          ComposerStrings.sectionProgress(
            viewModel.currentSectionIndex + 1,
            viewModel.totalSections,
            sectionTitle,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Progress bar ───────────────────────────────────────────────────
          LinearProgressIndicator(
            value: (viewModel.currentSectionIndex + 1) /
                viewModel.totalSections,
          ),

          // ── TB added banner ────────────────────────────────────────────────
          if (viewModel.tbBannerVisible)
            _TbAddedBanner(
              onDismiss: viewModel.dismissTbBanner,
            ),

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
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          // ── Section fields ─────────────────────────────────────────────────
          Expanded(
            child: _SectionFieldList(
              section: current,
              fieldValues: viewModel.fieldValues,
              onFieldChanged: viewModel.setFieldValue,
              isScribePreFilled: viewModel.isScribePreFilled,
              onFieldTouched: viewModel.markFieldTouched,
              // Show unmapped findings card only in the last section.
              unmappedFindings: viewModel.isLastSection
                  ? viewModel.unmappedFindings
                  : const [],
            ),
          ),

          // ── Action row ─────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: viewModel.isLastSection && viewModel.isAllDone
                  ? _SubmitButton(
                      isSaving: viewModel.isSaving,
                      onPressed: onSubmit,
                    )
                  : _NextButton(
                      isSaving: viewModel.isSaving,
                      onPressed: viewModel.isSaving
                          ? null
                          : viewModel.completeCurrentSection,
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

class _SectionFieldList extends StatelessWidget {
  const _SectionFieldList({
    required this.section,
    required this.fieldValues,
    required this.onFieldChanged,
    required this.isScribePreFilled,
    required this.onFieldTouched,
    this.unmappedFindings = const [],
  });

  final FormSection section;
  final Map<String, dynamic> fieldValues;
  final void Function(String fieldId, dynamic value) onFieldChanged;

  /// Returns true if [fieldId] holds an unverified scribe pre-fill.
  final bool Function(String fieldId) isScribePreFilled;

  /// Called when the SK interacts with a field, removing any scribe pre-fill.
  final void Function(String fieldId) onFieldTouched;

  /// Unmapped clinical findings from the last scribe result. Rendered as an
  /// informational card at the bottom of the last section.
  final List<String> unmappedFindings;

  @override
  Widget build(BuildContext context) {
    final visibleFields = section.fields
        .where((f) =>
            f.visibleWhen == null || f.visibleWhen!.evaluate(fieldValues))
        .toList();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: visibleFields.length + (unmappedFindings.isNotEmpty ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        // Unmapped findings card at the end.
        if (index == visibleFields.length) {
          return _UnmappedFindingsCard(findings: unmappedFindings);
        }

        final field = visibleFields[index];
        final preFilledByScribe = isScribePreFilled(field.fieldId);

        return _FieldWidget(
          field: field,
          currentValue: fieldValues[field.fieldId],
          isScribePreFilled: preFilledByScribe,
          onChanged: (value) {
            onFieldTouched(field.fieldId);
            onFieldChanged(field.fieldId, value);
          },
        );
      },
    );
  }
}

/// Info card shown at the bottom of the last section when the scribe
/// detected clinical findings that didn't map to any registered field.
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
/// In production, each branch would expand to the full UHIS design-system
/// widget; here the structure is correct and test-stable.
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
        color: theme.colorScheme.primaryContainer.withOpacity(0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
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
          initialValue:
              currentValue != null ? currentValue.toString() : null,
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
          value: currentValue as String?,
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

class _NextButton extends StatelessWidget {
  const _NextButton({
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
        onPressed: onPressed != null
            ? () {
                // Wrap the async call — widgets don't own Future chains.
                if (onPressed is Future<void> Function()) {
                  (onPressed as Future<void> Function())();
                } else {
                  onPressed!();
                }
              }
            : null,
        child: isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(ComposerStrings.nextButton),
      ),
    );
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
        onPressed: onPressed,
        child: Text(ComposerStrings.submitButton),
      ),
    );
  }
}
