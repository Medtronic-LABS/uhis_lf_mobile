import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/api/scribe_api_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/models/programme.dart';
import '../dashboard/mission_dashboard_repository.dart';
import '../scribe/form_field_schema_builder.dart';
import '../scribe/scribe_controller.dart';
import '../scribe/scribe_permission_service.dart';
import '../scribe/scribe_session.dart';
import '../scribe/widgets/scribe_banner.dart';
import '../scribe/widgets/scribe_review_sheet.dart';
import '../worklist/worklist_repository.dart';
import '../../core/db/local_assessment_dao.dart';
import 'assessment_repository.dart';
import 'composer/sectioned_assessment_screen.dart';
import 'forms/anc_assessment_form.dart';
import 'pathway/pathway_engine.dart';
import 'submission/unified_submission_orchestrator.dart';
import 'triage/patient_context_builder.dart';
import 'forms/iccm_assessment_form.dart';
import 'forms/ncd_assessment_form.dart';
import 'forms/tb_assessment_form.dart';
import 'models/anc_assessment.dart';
import 'models/iccm_assessment.dart';
import 'models/ncd_assessment.dart';
import 'models/tb_assessment.dart';
import 'visit_controller.dart';
import 'visit_session.dart';
import 'vital_classifier.dart';

/// Single-screen visit form: symptom check → vitals → assessment + AI Scribe.
///
/// Replaces the three-route flow (triage → vitals → assessment/:programme)
/// with one scrollable Scaffold. The AI Scribe banner lives inline above the
/// assessment section — not as a FAB.
class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({
    super.key,
    required this.visitId,
    this.patientId,
    this.memberId,
    this.householdId,
    this.villageId,
    this.householdMemberLocalId,
    this.patientAge,
    this.gestationalWeeks,
    this.activatedPathways,
    this.origin,
  });

  final String visitId;
  final String? patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;
  final int? gestationalWeeks;
  
  /// Activated pathways from symptom-driven triage.
  /// When non-empty, determines which assessment forms to show.
  final List<String>? activatedPathways;
  
  final String? origin;

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  bool _scribeInitialized = false;
  late ScribeController _scribeCtrl;

  NcdAssessment? _ncdData;
  TbAssessment? _tbData;
  AncAssessment? _ancData;
  IccmAssessment? _iccmData;

  bool _isSubmitting = false;

  /// Set by [_buildSectionedScreen]'s onReferNow callback when a CDS alert
  /// fires a referral recommendation during sectioned assessment.
  bool _sectionedReferralTriggered = false;

  /// Whether we're using the new pathway-driven flow.
  bool get _hasActivatedPathways =>
      widget.activatedPathways != null && widget.activatedPathways!.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_scribeInitialized) {
      _scribeCtrl = ScribeController(
        api: context.read<ScribeApiService>(),
        permissionService: ScribePermissionService(),
      );
      _scribeInitialized = true;
    }
  }

  @override
  void dispose() {
    if (_scribeInitialized) _scribeCtrl.dispose();
    super.dispose();
  }

  String get _returnPath =>
      widget.origin == 'dashboard' ? '/' : '/tasks';

  /// Build the programme label for the header.
  /// Shows activated pathways if available, otherwise single programme.
  String _buildProgrammeLabel(VisitSession session) {
    final pathways = widget.activatedPathways;
    if (pathways != null && pathways.isNotEmpty) {
      final labels = pathways.map((p) {
        final programme = Programme.fromString(p);
        switch (programme) {
          case Programme.imci:
            return 'ICCM';
          case Programme.anc:
            return 'ANC';
          case Programme.pnc:
            return 'PNC';
          case Programme.ncd:
            return 'NCD';
          case Programme.tb:
            return 'TB';
          default:
            return p.toUpperCase();
        }
      }).toSet().toList(); // Dedupe
      return labels.join(' + ');
    }
    return session.programme.wireTag;
  }

  int _nextDueForProgramme(Programme programme, DateTime now) {
    final Duration interval;
    switch (programme) {
      case Programme.anc:
      case Programme.pnc:
        interval = const Duration(days: 28);
        break;
      case Programme.ncd:
        interval = const Duration(days: 30);
        break;
      case Programme.tb:
        interval = const Duration(days: 14);
        break;
      case Programme.imci:
        interval = const Duration(days: 30);
        break;
      default:
        interval = const Duration(days: 30);
    }
    return now.add(interval).millisecondsSinceEpoch;
  }

  bool get _referralRecommended {
    if (_sectionedReferralTriggered) return true;
    final session = context.read<VisitController>().session;
    if (session == null) return false;
    switch (session.programme) {
      case Programme.tb:
        return _tbData?.referralRecommended ?? false;
      case Programme.anc:
      case Programme.pnc:
        return _ancData?.referralRecommended ?? false;
      case Programme.imci:
        return _iccmData?.referralRecommended ?? false;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_scribeInitialized) return const SizedBox.shrink();

    _scribeCtrl.bindContext(context);

    return ChangeNotifierProvider<ScribeController>.value(
      value: _scribeCtrl,
      child: Consumer<VisitController>(
        builder: (ctx, visitCtrl, _) {
          final session = visitCtrl.session;

          if (session == null || session.id != widget.visitId) {
            return Scaffold(
              appBar: AppBar(title: const Text('Visit')),
              body: const Center(child: Text('Visit session not found.')),
            );
          }

          // Auto-show review sheet ONLY for SOAP mode (reviewReady state).
          // For form_prefill mode (fieldsPopulated state), fields are populated inline.
          final scribeState = _scribeCtrl.session.state;
          final scribeMode = _scribeCtrl.session.mode;
          if (scribeState == ScribeState.reviewReady &&
              scribeMode == ScribeMode.soap &&
              ModalRoute.of(ctx)?.isCurrent == true) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _scribeCtrl.session.state == ScribeState.reviewReady &&
                  _scribeCtrl.session.mode == ScribeMode.soap) {
                showScribeReviewSheet(ctx);
              }
            });
          }

          // ── Phase 2: Sectioned assessment for pathway-driven flow ──────────
          if (_hasActivatedPathways) {
            return _buildSectionedScreen(ctx, visitCtrl, session);
          }

          return Scaffold(
            backgroundColor: const Color(0xFFF3F4F6),
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _VisitHeader(
                    patientName:
                        session.patientName ?? VisitTriageStrings.patient,
                    patientAge: session.patientAge,
                    programme: _buildProgrammeLabel(session),
                    onBack: () => _confirmLeave(ctx, session.patientId),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
                      children: [
                        // For new pathway-driven flow, skip old symptom/vitals
                        // sections since those were handled in triage screen
                        if (!_hasActivatedPathways) ...[
                          // ── Section 1: Symptom check (Legacy flow) ─────
                          _SectionDivider(
                            label: 'Symptom Check',
                            icon: Icons.search,
                          ),
                          _AiBriefCard(
                            patientName: session.patientName ??
                                VisitTriageStrings.patient,
                          ),
                          const SizedBox(height: 12),
                          _SkAsksFamilyCard(),
                          const SizedBox(height: 14),
                          _SymptomTilesGrid(
                            symptoms: session.symptoms,
                            onToggle: visitCtrl.toggleSymptom,
                          ),
                          const SizedBox(height: 16),
                          _DurationSelector(
                            selected: session.duration,
                            onSelect: visitCtrl.setDuration,
                          ),

                          const SizedBox(height: 20),
                          // ── Section 2: Vitals (Legacy flow) ────────────
                          _SectionDivider(
                            label: 'Vital Signs',
                            icon: Icons.favorite_border,
                          ),
                          ...session.vitals.map(
                            (v) => _VitalCard(
                              vital: v,
                              patientAge: widget.patientAge,
                              onChanged: (value,
                                  {double? systolic,
                                  double? diastolic,
                                  bool? boolValue}) {
                                visitCtrl.updateVital(
                                  v.code,
                                  value: value,
                                  systolic: systolic,
                                  diastolic: diastolic,
                                  boolValue: boolValue,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        // ── Section 3: Assessment + AI Scribe ─────────────
                        _SectionDivider(
                          label: 'Assessment',
                          icon: Icons.medical_information_outlined,
                        ),
                        ScribeBanner(
                          onStartRecording: () {
                            // Use form_prefill mode for embedded AI co-pilot experience
                            final programmes = _hasActivatedPathways
                                ? widget.activatedPathways!
                                : [session.programme.wireTag];
                            final schemas = programmes
                                .map((p) => FormFieldSchemaBuilder.forProgramme(
                                    Programme.fromString(p)))
                                .expand((s) => s)
                                .toList();
                            
                            debugPrint('[VisitForm] Starting AI Scribe for programmes: $programmes');
                            _scribeCtrl.startRecordingForFormPrefill(
                              patientId: widget.patientId,
                              encounterId: widget.visitId,
                              formSchema: schemas,
                              programmes: programmes,
                            );
                          },
                          onStopRecording: () =>
                              _scribeCtrl.stopRecording(
                            patientId: widget.patientId,
                            encounterId: widget.visitId,
                            programme: session.programme.wireTag,
                          ),
                          onOpenReview: () => showScribeReviewSheet(ctx),
                          onRetry: () => _scribeCtrl.retryUpload(
                            patientId: widget.patientId,
                            encounterId: widget.visitId,
                            programme: session.programme.wireTag,
                          ),
                          onAcceptAll: () {
                            _scribeCtrl.acceptAllFields();
                            debugPrint('[VisitForm] User accepted all AI-filled fields');
                          },
                        ),
                        ..._buildAssessmentForms(session),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _onSubmit(ctx, visitCtrl, session),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Complete Assessment'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build assessment forms based on activated pathways.
  ///
  /// If activatedPathways is provided (new symptom-driven flow), shows
  /// forms for each activated pathway. Otherwise falls back to single
  /// programme-based form (legacy flow).
  List<Widget> _buildAssessmentForms(VisitSession session) {
    // Use activated pathways if available (new flow)
    final pathways = widget.activatedPathways;
    if (pathways != null && pathways.isNotEmpty) {
      debugPrint('[VisitForm] Building forms for activated pathways: $pathways');
      final programmes = pathways
          .map((p) => Programme.fromString(p))
          .where((p) => p != Programme.unknown)
          .toSet() // Dedupe
          .toList();

      debugPrint('[VisitForm] Resolved programmes: ${programmes.map((p) => p.name).toList()}');

      if (programmes.isEmpty) {
        debugPrint('[VisitForm] No valid programmes, falling back to: ${session.programme.name}');
        return [_buildAssessmentForm(session.programme)];
      }

      return programmes.map((programme) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (programmes.length > 1) ...[
              const SizedBox(height: 16),
              _PathwayHeader(programme: programme),
            ],
            _buildAssessmentForm(programme),
          ],
        );
      }).toList();
    }

    // Fallback: single programme (legacy flow)
    debugPrint('[VisitForm] Legacy flow, single programme: ${session.programme.name}');
    return [_buildAssessmentForm(session.programme)];
  }

  Widget _buildAssessmentForm(Programme programme) {
    switch (programme) {
      case Programme.ncd:
        return NcdAssessmentForm(
          initialData: _ncdData,
          patientAge: widget.patientAge,
          onChanged: (d) => _ncdData = d,
        );
      case Programme.tb:
        return TbAssessmentForm(
          initialData: _tbData,
          onChanged: (d) {
            _tbData = d;
            setState(() {});
          },
        );
      case Programme.anc:
      case Programme.pnc:
        return AncAssessmentForm(
          initialData: _ancData,
          gestationalWeeks: widget.gestationalWeeks,
          onChanged: (d) {
            _ancData = d;
            setState(() {});
          },
        );
      case Programme.imci:
        final ageInMonths =
            widget.patientAge != null ? widget.patientAge! * 12 : null;
        return IccmAssessmentForm(
          initialData: _iccmData,
          ageInMonths: ageInMonths,
          onChanged: (d) {
            _iccmData = d;
            setState(() {});
          },
        );
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Programme ${programme.wireTag} assessment coming soon.',
              textAlign: TextAlign.center,
            ),
          ),
        );
    }
  }

  Future<void> _onSubmit(
    BuildContext ctx,
    VisitController visitCtrl,
    VisitSession session,
  ) async {
    setState(() => _isSubmitting = true);
    try {
      // Skip triage/vitals persistence for new pathway-driven flow
      // since those were handled in the triage screen
      if (!_hasActivatedPathways) {
        await visitCtrl.persistTriage();
        await visitCtrl.persistVitals();
      }

      // For new pathway-driven flow, save each activated pathway's assessment
      if (_hasActivatedPathways) {
        await _saveMultiPathwayAssessments(ctx);
      } else {
        // Legacy flow: single programme assessment
        await _saveSingleProgrammeAssessment(ctx, session.programme);
      }

      if (widget.patientId != null) {
        final patientDao = ctx.read<PatientDao>();
        final now = DateTime.now();
        // For multi-pathway, use shortest interval
        final primaryProgramme = _hasActivatedPathways
            ? _getPrimaryProgramme()
            : session.programme;
        await patientDao.updateVisitSchedule(
          patientId: widget.patientId!,
          lastVisitAt: now.millisecondsSinceEpoch,
          nextDueAt: _nextDueForProgramme(primaryProgramme, now),
          missedVisitCount: 0,
        );
        final worklistRepo = ctx.read<WorklistRepository>();
        await worklistRepo.recomputeAllAfterSync();
      }

      if (mounted) _showCompletionDialog(ctx, session);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Failed to save assessment: $e'),
          backgroundColor: Theme.of(ctx).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Get primary programme for multi-pathway flow (first non-unknown).
  Programme _getPrimaryProgramme() {
    if (widget.activatedPathways != null) {
      for (final name in widget.activatedPathways!) {
        final p = Programme.fromString(name);
        if (p != Programme.unknown) return p;
      }
    }
    return Programme.unknown;
  }

  // ── Phase 2: Sectioned assessment helpers ───────────────────────────────

  /// Reconstruct [ActivatedPathway] list from string programme names.
  ///
  /// Priority mirrors [PathwayRulesV1] order so section rendering is correct.
  List<ActivatedPathway> _buildPathways() {
    return widget.activatedPathways!
        .map(Programme.fromString)
        .where((p) => p != Programme.unknown)
        .map((p) => ActivatedPathway(
              programme: p,
              priority: _programmePriority(p),
              confidence: 1.0,
              trigger: PathwayTrigger.manual,
              rationaleKey: 'pathwayManualRationale',
            ))
        .toList();
  }

  int _programmePriority(Programme p) {
    switch (p) {
      case Programme.imci:
        return 10;
      case Programme.anc:
        return 20;
      case Programme.pnc:
        return 25;
      case Programme.tb:
        return 30;
      case Programme.ncd:
        return 40;
      default:
        return 50;
    }
  }

  /// Build a minimal [PatientContext] from the params available at this level.
  ///
  /// Sex is inferred: ANC in pathways → female. Pregnancy: ANC present → true.
  PatientContext _buildPatientContext() {
    final pathwayNames = widget.activatedPathways ?? const [];
    final hasAnc = pathwayNames.contains(Programme.anc.name) ||
        pathwayNames.contains(Programme.pnc.name);
    return PatientContext(
      patientId: widget.patientId ?? '',
      ageMonths: (widget.patientAge ?? 0) * 12,
      sex: hasAnc ? Sex.female : Sex.unknown,
      isPregnant: pathwayNames.contains(Programme.anc.name),
      gestationalWeeks: widget.gestationalWeeks,
    );
  }

  /// Builds [SectionedAssessmentScreen] for the pathway-driven assessment flow.
  Widget _buildSectionedScreen(
    BuildContext ctx,
    VisitController visitCtrl,
    VisitSession session,
  ) {
    return SectionedAssessmentScreen(
      pathways: _buildPathways(),
      patientContext: _buildPatientContext(),
      encounterId: widget.visitId,
      patientId: widget.patientId ?? '',
      householdMemberLocalId: widget.householdMemberLocalId ?? 0,
      memberId: widget.memberId,
      draftDao: ctx.read<AssessmentDraftDao>(),
      onSubmit: () => _onSectionedSubmit(ctx, visitCtrl, session),
      onReferNow: (_) {
        setState(() => _sectionedReferralTriggered = true);
      },
    );
  }

  /// Fan-out submission handler for the sectioned assessment flow.
  Future<void> _onSectionedSubmit(
    BuildContext ctx,
    VisitController visitCtrl,
    VisitSession session,
  ) async {
    setState(() => _isSubmitting = true);
    try {
      final draftDao = ctx.read<AssessmentDraftDao>();
      final orchestrator = ctx.read<UnifiedSubmissionOrchestrator>();

      final draft = await draftDao.getDraft(widget.visitId);
      if (draft != null) {
        await orchestrator.submit(
          draft,
          householdMemberLocalId: widget.householdMemberLocalId ?? 0,
          memberId: widget.memberId,
          householdId: widget.householdId,
          villageId: widget.villageId,
        );
      }

      if (widget.patientId != null && ctx.mounted) {
        final now = DateTime.now();
        await ctx.read<PatientDao>().updateVisitSchedule(
          patientId: widget.patientId!,
          lastVisitAt: now.millisecondsSinceEpoch,
          nextDueAt: _nextDueForProgramme(_getPrimaryProgramme(), now),
          missedVisitCount: 0,
        );
        if (ctx.mounted) {
          await ctx.read<WorklistRepository>().recomputeAllAfterSync();
        }
      }

      if (mounted && ctx.mounted) _showCompletionDialog(ctx, session);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Failed to save assessment: $e'),
          backgroundColor: Theme.of(ctx).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Save assessments for each activated pathway.
  Future<void> _saveMultiPathwayAssessments(BuildContext ctx) async {
    final repo = ctx.read<AssessmentRepository>();
    final encounterDao = ctx.read<EncounterDao>();
    final combinedData = <String, dynamic>{};

    // Process each activated pathway
    for (final name in widget.activatedPathways!) {
      final programme = Programme.fromString(name);
      if (programme == Programme.unknown) continue;

      final data = _getAssessmentDataForProgramme(programme);
      if (data != null && data.isNotEmpty) {
        // Save each assessment
        await repo.saveAssessment(
          assessmentType: programme.wireTag,
          assessmentDetails: data,
          householdMemberLocalId: widget.householdMemberLocalId ?? 0,
          memberId: widget.memberId,
          householdId: widget.householdId,
          patientId: widget.patientId,
          villageId: widget.villageId,
          isReferred: _referralRecommendedForProgramme(programme),
          referralStatus: _referralRecommendedForProgramme(programme)
              ? 'Referred'
              : 'Recovered',
          referredReasons: _getReferralReasonsForProgramme(programme),
        );
        combinedData[programme.wireTag] = data;
      }
    }

    // Update encounter with combined assessment data
    await encounterDao.updateAssessment(widget.visitId, combinedData);
  }

  /// Save single programme assessment (legacy flow).
  Future<void> _saveSingleProgrammeAssessment(
    BuildContext ctx,
    Programme programme,
  ) async {
    final assessmentData = _getAssessmentDataForProgramme(programme) ?? {};
    final referredReasons = _getReferralReasonsForProgramme(programme);

    final repo = ctx.read<AssessmentRepository>();
    await repo.saveAssessment(
      assessmentType: programme.wireTag,
      assessmentDetails: assessmentData,
      householdMemberLocalId: widget.householdMemberLocalId ?? 0,
      memberId: widget.memberId,
      householdId: widget.householdId,
      patientId: widget.patientId,
      villageId: widget.villageId,
      isReferred: _referralRecommended,
      referralStatus: _referralRecommended ? 'Referred' : 'Recovered',
      referredReasons: referredReasons,
    );

    final encounterDao = ctx.read<EncounterDao>();
    await encounterDao.updateAssessment(widget.visitId, assessmentData);
  }

  /// Get assessment data for a specific programme.
  Map<String, dynamic>? _getAssessmentDataForProgramme(Programme programme) {
    switch (programme) {
      case Programme.ncd:
        return _ncdData?.toJson();
      case Programme.tb:
        return _tbData?.toJson();
      case Programme.anc:
      case Programme.pnc:
        return _ancData?.toJson();
      case Programme.imci:
        return _iccmData?.toJson();
      default:
        return null;
    }
  }

  /// Check if referral is recommended for a specific programme.
  bool _referralRecommendedForProgramme(Programme programme) {
    switch (programme) {
      case Programme.tb:
        return _tbData?.isPositive ?? false;
      case Programme.anc:
      case Programme.pnc:
        return _ancData?.referralRecommended ?? false;
      case Programme.imci:
        return _iccmData?.referralRecommended ?? false;
      default:
        return false;
    }
  }

  /// Get referral reasons for a specific programme.
  List<String>? _getReferralReasonsForProgramme(Programme programme) {
    switch (programme) {
      case Programme.tb:
        return _tbData?.isPositive == true ? ['Positive TB Screen'] : null;
      case Programme.anc:
      case Programme.pnc:
        return _ancData?.referralRecommended == true
            ? ['ANC Danger Signs']
            : null;
      case Programme.imci:
        return _iccmData?.referralRecommended == true
            ? _iccmData!.conditionsSummary
            : null;
      default:
        return null;
    }
  }

  void _showCompletionDialog(BuildContext ctx, VisitSession session) {
    final theme = Theme.of(ctx);
    
    // Build the appropriate completion message
    final String savedMessage;
    if (_hasActivatedPathways) {
      savedMessage = '${_buildProgrammeLabel(session)} assessments saved.';
    } else {
      savedMessage = '${session.programme.wireTag} assessment saved.';
    }
    
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _referralRecommended ? Icons.warning : Icons.check_circle,
              color: _referralRecommended ? theme.colorScheme.error : Colors.green,
            ),
            const SizedBox(width: 12),
            const Text('Assessment Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(savedMessage),
            if (_referralRecommended) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Referral recommended based on findings.',
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_referralRecommended)
            OutlinedButton(
              onPressed: () {
                Navigator.pop(dlgCtx);
                ctx.read<MissionDashboardRepository>().clearCache();
                ctx.go(_returnPath);
              },
              child: const Text('Create Referral'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              ctx.read<MissionDashboardRepository>().clearCache();
              ctx.go(_returnPath);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext ctx, String patientId) {
    showDialog<void>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        title: const Text(VisitTriageStrings.leaveVisitTitle),
        content: const Text(VisitTriageStrings.leaveVisitBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text(VisitTriageStrings.stay),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              ctx.go('/patients/$patientId');
            },
            child: const Text(VisitTriageStrings.leave),
          ),
        ],
      ),
    );
  }
}

// ── Section divider ──────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: tokens.brandNavy,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: tokens.brandNavy,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: tokens.divider),
          ),
        ],
      ),
    );
  }
}

// ── Pathway header for multi-pathway assessments ────────────────────────────

class _PathwayHeader extends StatelessWidget {
  const _PathwayHeader({required this.programme});

  final Programme programme;

  String get _label {
    switch (programme) {
      case Programme.imci:
        return 'Child Health (ICCM)';
      case Programme.anc:
        return 'Antenatal Care';
      case Programme.pnc:
        return 'Postnatal Care';
      case Programme.ncd:
        return 'NCD Screening';
      case Programme.tb:
        return 'TB Screening';
      default:
        return programme.wireTag.toUpperCase();
    }
  }

  IconData get _icon {
    switch (programme) {
      case Programme.imci:
        return Icons.child_care;
      case Programme.anc:
        return Icons.pregnant_woman;
      case Programme.pnc:
        return Icons.family_restroom;
      case Programme.ncd:
        return Icons.favorite;
      case Programme.tb:
        return Icons.coronavirus;
      default:
        return Icons.medical_services;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _icon,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            _label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Visit header with 3-step progress bar ────────────────────────────────────

class _VisitHeader extends StatelessWidget {
  const _VisitHeader({
    required this.patientName,
    required this.patientAge,
    required this.programme,
    required this.onBack,
  });

  final String patientName;
  final int? patientAge;
  final String programme;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        patientAge != null ? '$patientName, Age $patientAge' : patientName;
    return Container(
      color: const Color(0xFF1E40AF),
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visit — $subtitle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      programme,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: const Row(
              children: [
                _ProgressBar(active: true),
                SizedBox(width: 6),
                _ProgressBar(active: true),
                SizedBox(width: 6),
                _ProgressBar(active: true),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: const [
                Expanded(
                  child: Text(
                    VisitTriageStrings.stepLabel1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    VisitTriageStrings.stepLabel2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    VisitTriageStrings.stepLabel3,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
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
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── Triage widgets (moved from visit_triage_step.dart) ───────────────────────

class _AiBriefCard extends StatefulWidget {
  const _AiBriefCard({required this.patientName});

  final String patientName;

  @override
  State<_AiBriefCard> createState() => _AiBriefCardState();
}

class _AiBriefCardState extends State<_AiBriefCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.cardSurfaceMuted,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        border: Border.all(color: tokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tokens.brandNavy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    VisitTriageStrings.beforeYouKnock,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: tokens.brandNavy,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.statusCriticalSurface,
                borderRadius:
                    BorderRadius.circular(LeapfrogColors.radiusSm),
                border: Border(
                  left: BorderSide(color: tokens.statusCritical, width: 3),
                ),
              ),
              child: Text(
                VisitTriageStrings.briefBody(widget.patientName),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.statusCritical,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkAsksFamilyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tokens.statusInfoSurface,
            tokens.statusInfoSurface.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        border: Border.all(
            color: tokens.statusInfo.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            VisitTriageStrings.skAsksFamily,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: tokens.statusInfo,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            VisitTriageStrings.skAsksBangla,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tokens.brandNavy,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            VisitTriageStrings.skAsksEnglish,
            style: TextStyle(
              fontSize: 12,
              color: tokens.statusInfo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SymptomTilesGrid extends StatelessWidget {
  const _SymptomTilesGrid(
      {required this.symptoms, required this.onToggle});

  final List<SymptomSelection> symptoms;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.5,
      ),
      itemCount: symptoms.length,
      itemBuilder: (context, index) {
        final s = symptoms[index];
        return _SymptomTile(
          symptom: s,
          onTap: () => onToggle(s.code),
        );
      },
    );
  }
}

class _SymptomTile extends StatelessWidget {
  const _SymptomTile({required this.symptom, required this.onTap});

  final SymptomSelection symptom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final selected = symptom.selected;
    return Material(
      color: selected ? tokens.statusCriticalSurface : tokens.cardSurface,
      borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
            border: Border.all(
              color: selected ? tokens.statusCritical : tokens.divider,
              width: selected ? 2 : 1.5,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_emoji(symptom.code),
                  style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 6),
              Text(
                symptom.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.brandNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _emoji(String code) {
    switch (code.toLowerCase()) {
      case 'fever':
        return '🌡️';
      case 'breathing':
      case 'fast_breathing':
        return '😮‍💨';
      case 'cough':
        return '🫁';
      case 'noeat':
      case 'not_eating':
        return '🍼';
      case 'diarrhea':
      case 'loose_motion':
        return '💧';
      case 'rash':
        return '🌶️';
      case 'vomit':
      case 'vomiting':
        return '🤢';
      case 'drowsy':
      case 'sleepy':
        return '😴';
      default:
        return '🩺';
    }
  }
}

class _DurationSelector extends StatelessWidget {
  const _DurationSelector(
      {required this.selected, required this.onSelect});

  final SymptomDuration? selected;
  final ValueChanged<SymptomDuration> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            VisitTriageStrings.durationQuestion,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: tokens.brandNavy,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final d in SymptomDuration.values) ...[
                Expanded(
                  child: _DurationButton(
                    duration: d,
                    selected: selected == d,
                    onTap: () => onSelect(d),
                  ),
                ),
                if (d != SymptomDuration.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DurationButton extends StatelessWidget {
  const _DurationButton({
    required this.duration,
    required this.selected,
    required this.onTap,
  });

  final SymptomDuration duration;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final isLong = duration == SymptomDuration.fourPlusDays;
    final activeFg =
        isLong ? tokens.statusCritical : tokens.brandNavy;
    final activeBg =
        isLong ? tokens.statusCriticalSurface : tokens.aiSurfaceStart;
    final bgColor = selected ? activeBg : tokens.cardSurface;
    final fgColor = selected ? activeFg : tokens.textMuted;
    final borderColor = selected ? activeFg : tokens.divider;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(LeapfrogColors.radiusMd),
            border: Border.all(
              color: borderColor,
              width: selected ? 2 : 1.5,
            ),
          ),
          padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Center(
            child: Text(
              duration.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: fgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Vital card (moved from visit_vitals_step.dart) ───────────────────────────

class _VitalCard extends StatefulWidget {
  const _VitalCard({
    required this.vital,
    required this.onChanged,
    this.patientAge,
  });

  final VitalInput vital;
  final int? patientAge;
  final void Function(
    double? value, {
    double? systolic,
    double? diastolic,
    bool? boolValue,
  }) onChanged;

  @override
  State<_VitalCard> createState() => _VitalCardState();
}

class _VitalCardState extends State<_VitalCard> {
  late TextEditingController _ctrl;
  late TextEditingController _systolicCtrl;
  late TextEditingController _diastolicCtrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.vital.value?.toString() ?? '');
    _systolicCtrl = TextEditingController(
        text: widget.vital.systolic?.toString() ?? '');
    _diastolicCtrl = TextEditingController(
        text: widget.vital.diastolic?.toString() ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _systolicCtrl.dispose();
    _diastolicCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _VitalCard old) {
    super.didUpdateWidget(old);
    if (old.vital.value != widget.vital.value) {
      _ctrl.text = widget.vital.value?.toString() ?? '';
    }
    if (old.vital.systolic != widget.vital.systolic) {
      _systolicCtrl.text = widget.vital.systolic?.toString() ?? '';
    }
    if (old.vital.diastolic != widget.vital.diastolic) {
      _diastolicCtrl.text = widget.vital.diastolic?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vital = widget.vital;
    final isBp =
        vital.code.contains('bp_') || vital.code == 'bp';
    final isBool = vital.boolValue != null ||
        vital.code.contains('edema') ||
        vital.code.contains('indrawing');

    VitalClassification? cls;
    if (vital.hasValue && !isBool) {
      if (isBp &&
          vital.systolic != null &&
          vital.diastolic != null) {
        cls = VitalClassifier.classifyBp(
            vital.systolic!, vital.diastolic!);
      } else if (vital.value != null) {
        cls = VitalClassifier.classify(vital.code, vital.value!,
            patientAge: widget.patientAge);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    vital.label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (vital.unit != null && !isBool)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(vital.unit!,
                        style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (isBool)
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('No'),
                      selected: vital.boolValue == false,
                      onSelected: (_) =>
                          widget.onChanged(null, boolValue: false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Yes'),
                      selected: vital.boolValue == true,
                      selectedColor:
                          theme.colorScheme.errorContainer,
                      onSelected: (_) =>
                          widget.onChanged(null, boolValue: true),
                    ),
                  ),
                ],
              )
            else if (vital.code == 'bp_systolic')
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _systolicCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Systolic',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        widget.onChanged(null,
                            systolic: double.tryParse(v),
                            diastolic:
                                double.tryParse(_diastolicCtrl.text));
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('/'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _diastolicCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Diastolic',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        widget.onChanged(null,
                            systolic:
                                double.tryParse(_systolicCtrl.text),
                            diastolic: double.tryParse(v));
                      },
                    ),
                  ),
                ],
              )
            else if (!isBp)
              TextField(
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Enter value',
                  suffixText: vital.unit,
                ),
                onChanged: (v) => widget.onChanged(double.tryParse(v)),
              ),
            if (cls != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _clsColor(cls, theme),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_clsIcon(cls),
                        size: 16,
                        color: _clsTextColor(cls, theme)),
                    const SizedBox(width: 4),
                    Text(
                      cls.label,
                      style: TextStyle(
                        color: _clsTextColor(cls, theme),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _clsColor(VitalClassification c, ThemeData t) {
    switch (c) {
      case VitalClassification.normal:
        return Colors.green.shade100;
      case VitalClassification.low:
      case VitalClassification.high:
        return Colors.orange.shade100;
      case VitalClassification.critical:
        return t.colorScheme.errorContainer;
    }
  }

  Color _clsTextColor(VitalClassification c, ThemeData t) {
    switch (c) {
      case VitalClassification.normal:
        return Colors.green.shade800;
      case VitalClassification.low:
      case VitalClassification.high:
        return Colors.orange.shade800;
      case VitalClassification.critical:
        return t.colorScheme.error;
    }
  }

  IconData _clsIcon(VitalClassification c) {
    switch (c) {
      case VitalClassification.normal:
        return Icons.check_circle;
      case VitalClassification.low:
        return Icons.arrow_downward;
      case VitalClassification.high:
        return Icons.arrow_upward;
      case VitalClassification.critical:
        return Icons.warning;
    }
  }
}
