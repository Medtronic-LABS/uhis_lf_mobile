/// Drop-in replacement for [SectionedAssessmentScreen].
///
/// Loads the appropriate [FormSchema] via [SdkFormCompositor] (multi-programme)
/// or [FormDataService] (single-programme fallback), creates a
/// [VisitFormController] via Provider, and renders [DynamicFormRenderer]
/// with live CDS banners above the form.
///
/// The Scribe AI banner and the submit button are wired to the same contracts
/// as [SectionedAssessmentScreen] — [onSubmit] is called after a successful
/// [VisitFormController.saveDraft].
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_strings.dart';
import '../core/db/assessment_dao.dart';
import '../core/db/local_assessment_dao.dart';
import '../core/models/programme.dart';
import '../core/theme/app_theme.dart';
import '../features/visit/composer/cds_banner.dart';
import '../features/visit/composer/cds_rules.dart';
import '../features/visit/composer/sdk_form_compositor.dart';
import '../features/visit/composer/visit_form_controller.dart';
import 'controller/dynamic_form_controller.dart';
import 'form_data_service.dart';
import 'models/field_schema.dart';
import 'models/form_schema.dart';
import 'models/section_schema.dart';
import 'widgets/dynamic_form_renderer.dart';

class DynamicAssessmentScreen extends StatefulWidget {
  const DynamicAssessmentScreen({
    super.key,
    this.formType = '',
    this.programmes,
    required this.encounterId,
    required this.patientId,
    required this.draftDao,
    required this.onSubmit,
    this.memberId,
    this.onReferNow,
    this.restoredDraft,
    this.embedded = false,
    this.onError,
  });

  /// Single programme identifier (e.g. 'anc', 'ncd').
  /// Used as fallback when [programmes] is null or empty.
  final String formType;

  /// Full list of activated programmes — enables multi-programme form
  /// composition via [SdkFormCompositor]. Preferred over [formType].
  final List<Programme>? programmes;

  /// Encounter UUID — PK in [AssessmentDraftRow].
  final String encounterId;

  /// FHIR patient ID.
  final String patientId;

  final String? memberId;

  final AssessmentDraftDao draftDao;

  /// Called after a successful submit + draft save.
  final VoidCallback onSubmit;

  /// Optional: called when a CDS-driven urgent referral alert fires.
  final VoidCallback? onReferNow;

  /// Restored draft from a previous session (pre-populates field values).
  final AssessmentDraftRow? restoredDraft;

  /// When true, suppresses the internal AppBar — caller owns the navigation
  /// chrome (e.g. [VisitFlowScreen] already shows patient header + step bar).
  final bool embedded;

  /// Called when the schema fails to load — lets the parent fall back to the
  /// legacy [SectionedAssessmentScreen] rather than showing an error wall.
  final VoidCallback? onError;

  @override
  State<DynamicAssessmentScreen> createState() =>
      _DynamicAssessmentScreenState();
}

class _DynamicAssessmentScreenState extends State<DynamicAssessmentScreen> {
  FormSchema? _schema;
  bool _loading = true;
  String? _loadError;
  VisitFormController? _controller;
  double? _previousAncWeight;

  @override
  void initState() {
    super.initState();
    _loadSchema();
    final isAnc = widget.programmes?.any((p) => p == Programme.anc) == true ||
        widget.formType.toLowerCase() == 'anc';
    if (isAnc) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrevAncWeight());
    }
  }

  Future<void> _loadPrevAncWeight() async {
    try {
      // Previous visits come from AssessmentDao (synced from server).
      // rawJson structure: {"observations": {"weight": 56, ...}, "serviceProvided": "ANC", ...}
      final dao = context.read<AssessmentDao>();
      final byPatient = await dao.forMany([widget.patientId]);
      final rows = byPatient[widget.patientId] ?? [];
      final ancRows = rows
          .where((r) => (r.kind ?? '').toUpperCase() == 'ANC')
          .toList();
      if (ancRows.isEmpty) return;
      final prev = ancRows.first; // sorted by occurred_at DESC
      final raw = jsonDecode(prev.rawJson) as Map<String, dynamic>?;
      final obs = raw?['observations'] as Map?;
      final w = obs?['weight'];
      if (w == null) return;
      final weight = (w is num) ? w.toDouble() : double.tryParse('$w');
      if (weight != null && mounted) setState(() => _previousAncWeight = weight);
    } catch (e, st) {
      debugPrint('[PrevWeight] error: $e\n$st');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadSchema() async {
    try {
      FormSchema? schema;
      final progs = widget.programmes;

      if (progs != null && progs.isNotEmpty) {
        schema = await SdkFormCompositor.compose(progs);
      }

      if (schema == null && widget.formType.isNotEmpty) {
        schema = await FormDataService().schemaForType(widget.formType);
      }

      if (schema == null) {
        debugPrint('[DynamicAssessment] no schema — triggering fallback');
        _triggerFallback(
          'No form schema for '
          '"${widget.programmes?.map((p) => p.name).join(', ') ?? widget.formType}"',
        );
        return;
      }

      final activePathways = (progs ?? const [])
          .where((p) => p.isPilot)
          .toSet();

      final ctrl = VisitFormController(
        formSchema: schema,
        encounterId: widget.encounterId,
        patientId: widget.patientId,
        memberId: widget.memberId,
        draftDao: widget.draftDao,
        formType: schema.formType,
        restoredDraft: widget.restoredDraft,
        activePathways: activePathways,
        onReferNow: widget.onReferNow,
      );

      setState(() {
        _schema = schema;
        _controller = ctrl;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[DynamicAssessment] _loadSchema error — triggering fallback: $e');
      _triggerFallback('Failed to load form: $e');
    }
  }

  void _triggerFallback(String reason) {
    if (widget.onError != null) {
      // Parent handles fallback — no need to render an error wall here.
      if (mounted) widget.onError!();
    } else {
      setState(() {
        _loadError = reason;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final errors = ctrl.validate();
    if (errors.isNotEmpty) {
      debugPrint('[DynamicAssessment] validate() blocked submit: $errors');
      if (!mounted) return;
      final names = errors.values.take(3).join('\n• ');
      final overflow =
          errors.length > 3 ? '\n(+${errors.length - 3} more)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Required fields missing:\n• $names$overflow'),
          duration: const Duration(seconds: 4),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    try {
      await ctrl.submit(widget.onSubmit);
    } catch (e, st) {
      debugPrint('[DynamicAssessment] submit error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submit failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final embedded = widget.embedded;

    if (_loading) {
      return Scaffold(
        appBar: embedded ? null : AppBar(title: Text(_programmeLabel)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null || _schema == null || _controller == null) {
      return Scaffold(
        appBar: embedded ? null : AppBar(title: Text(_programmeLabel)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _loadError ?? 'Unknown error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider<DynamicFormController>.value(
      value: _controller!,
      child: Builder(
        builder: (ctx) {
          return Scaffold(
            appBar: embedded
                ? null
                : AppBar(
                    title: Text(_programmeLabel),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.save_outlined),
                        tooltip: 'Save draft',
                        onPressed: () =>
                            ctx.read<DynamicFormController>().saveDraft(),
                      ),
                    ],
                  ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (embedded)
                  _EmbeddedFormHeader(
                    label: _programmeLabel,
                    onSave: () =>
                        ctx.read<DynamicFormController>().saveDraft(),
                  ),
                Expanded(
                  child: _FormBody(
                    schema: _schema!,
                    controller: _controller!,
                    onAddPathway: _handleAddPathway,
                    onReferNow: widget.onReferNow,
                    previousAncWeight: _previousAncWeight,
                  ),
                ),
              ],
            ),
            bottomNavigationBar: _SubmitBar(onSubmit: _submit),
          );
        },
      ),
    );
  }

  Future<void> _handleAddPathway(Programme programme) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    try {
      final schema = await FormDataService()
          .schemaForType(programme.name.toLowerCase());
      if (schema == null) return;
      for (final section in schema.sections) {
        ctrl.addInjectedSection(section);
      }
    } catch (_) {}
  }

  String get _programmeLabel {
    final progs = widget.programmes;
    if (progs != null && progs.isNotEmpty) {
      return progs
          .where((p) => p.isPilot)
          .map((p) {
            final n = p.name;
            return n.substring(0, 1).toUpperCase() + n.substring(1);
          })
          .join(' + ');
    }
    final t = widget.formType;
    if (t.isEmpty) return 'Assessment';
    return t.substring(0, 1).toUpperCase() + t.substring(1);
  }
}

// ── Form body with CDS banners + renderer ─────────────────────────────────────

class _FormBody extends StatelessWidget {
  const _FormBody({
    required this.schema,
    required this.controller,
    required this.onAddPathway,
    this.onReferNow,
    this.previousAncWeight,
  });

  final FormSchema schema;
  final VisitFormController controller;
  final Future<void> Function(Programme) onAddPathway;
  final VoidCallback? onReferNow;
  final double? previousAncWeight;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) {
        final alerts = controller.alerts;
        final injected = controller.injectedSections;

        // Build combined schema: base sections + CDS-injected sections
        final combinedSchema = injected.isEmpty
            ? schema
            : _merge(schema, injected);

        return Column(
          children: [
            // CDS alert banners
            if (alerts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: alerts.map((alert) {
                    return CdsBanner(
                      key: ValueKey(alert.alertId),
                      alert: alert,
                      onDismiss: () => controller.dismissAlert(alert.alertId),
                      onReferNow: alert.action == CdsAction.referNow
                          ? onReferNow
                          : null,
                      onAddPathway: alert.action == CdsAction.addPathway &&
                              alert.addPathway != null
                          ? () => onAddPathway(alert.addPathway!)
                          : null,
                    );
                  }).toList(),
                ),
              ),

            // Form renderer
            Expanded(
              child: DynamicFormRenderer(
                schema: combinedSchema,
                controller: controller,
                previousAncWeight: previousAncWeight,
              ),
            ),
          ],
        );
      },
    );
  }

  static FormSchema _merge(FormSchema base, List<SectionSchema> injected) {
    final sections = [...base.sections, ...injected];
    final allFields = <FieldSchema>[
      for (final s in sections) ...s.fields,
    ];
    return FormSchema(
      formType: base.formType,
      sections: sections,
      allFields: allFields,
    );
  }
}

// ── Submit bar ────────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Consumer<DynamicFormController>(
      builder: (ctx, ctrl, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ctrl.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    ctrl.errorMessage ?? '',
                    style: const TextStyle(color: AppColors.rangeCritical),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: ctrl.isSaving ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: ctrl.isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          ComposerStrings.submitButton,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Embedded form header ──────────────────────────────────────────────────────

/// Slim label + save-icon row shown when [DynamicAssessmentScreen.embedded]
/// is true and the outer AppBar is suppressed.
class _EmbeddedFormHeader extends StatelessWidget {
  const _EmbeddedFormHeader({
    required this.label,
    required this.onSave,
  });

  final String label;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        border: Border(
          bottom: BorderSide(color: tokens.divider),
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.brandNavy,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.save_outlined, color: tokens.brandNavy),
            tooltip: 'Save draft',
            onPressed: onSave,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
