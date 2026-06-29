/// Drop-in replacement for [SectionedAssessmentScreen].
///
/// Loads the appropriate [FormSchema] from [FormDataService], creates a
/// [DynamicFormController] via Provider, and renders [DynamicFormRenderer].
///
/// The Scribe AI banner and the submit button are wired to the same contracts
/// as [SectionedAssessmentScreen] — [onSubmit] is called after a successful
/// [DynamicFormController.saveDraft].
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_strings.dart';
import '../core/db/local_assessment_dao.dart';
import '../core/theme/app_theme.dart';
import 'controller/dynamic_form_controller.dart';
import 'form_data_service.dart';
import 'models/form_schema.dart';
import 'widgets/dynamic_form_renderer.dart';

class DynamicAssessmentScreen extends StatefulWidget {
  const DynamicAssessmentScreen({
    super.key,
    required this.formType,
    required this.encounterId,
    required this.patientId,
    required this.draftDao,
    required this.onSubmit,
    this.memberId,
    this.onReferNow,
    this.restoredDraft,
  });

  /// Programme name (e.g. 'anc', 'ncd') — used to select the form schema.
  final String formType;

  /// Encounter UUID — PK in [AssessmentDraftRow].
  final String encounterId;

  /// FHIR patient ID.
  final String patientId;

  final String? memberId;

  final AssessmentDraftDao draftDao;

  /// Called after a successful submit + draft save.
  final VoidCallback onSubmit;

  /// Optional: called when a CDS-driven referral is triggered.
  final VoidCallback? onReferNow;

  /// Restored draft from a previous session (pre-populates field values).
  final AssessmentDraftRow? restoredDraft;

  @override
  State<DynamicAssessmentScreen> createState() =>
      _DynamicAssessmentScreenState();
}

class _DynamicAssessmentScreenState extends State<DynamicAssessmentScreen> {
  FormSchema? _schema;
  bool _loading = true;
  String? _loadError;
  DynamicFormController? _controller;

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadSchema() async {
    try {
      final service = FormDataService();
      final schema = await service.schemaForType(widget.formType);
      if (schema == null) {
        setState(() {
          _loadError =
              'No form schema found for programme "${widget.formType}"';
          _loading = false;
        });
        return;
      }
      final ctrl = DynamicFormController(
        formSchema: schema,
        encounterId: widget.encounterId,
        patientId: widget.patientId,
        memberId: widget.memberId,
        draftDao: widget.draftDao,
        formType: widget.formType,
        restoredDraft: widget.restoredDraft,
      );
      setState(() {
        _schema = schema;
        _controller = ctrl;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Failed to load form: $e';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    await ctrl.submit(widget.onSubmit);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_programmeLabel)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null || _schema == null || _controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_programmeLabel)),
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
            appBar: AppBar(
              title: Text(_programmeLabel),
              actions: [
                IconButton(
                  icon: const Icon(Icons.save_outlined),
                  tooltip: 'Save draft',
                  onPressed: () => ctx.read<DynamicFormController>().saveDraft(),
                ),
              ],
            ),
            body: DynamicFormRenderer(
              schema: _schema!,
              controller: _controller!,
            ),
            bottomNavigationBar: _SubmitBar(onSubmit: _submit),
          );
        },
      ),
    );
  }

  String get _programmeLabel {
    final t = widget.formType;
    if (t.isEmpty) return 'Assessment';
    return t.substring(0, 1).toUpperCase() + t.substring(1);
  }
}

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
                      style: const TextStyle(color: Color(0xFFDC2626)),
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
