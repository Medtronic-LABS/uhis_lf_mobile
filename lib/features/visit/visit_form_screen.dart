import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/scribe_api_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/models/programme.dart';
import '../dashboard/mission_dashboard_repository.dart';
import '../scribe/scribe_controller.dart';
import '../scribe/scribe_permission_service.dart';
import '../scribe/scribe_session.dart';
import '../scribe/widgets/scribe_review_sheet.dart';
import '../worklist/worklist_repository.dart';
import '../../core/config/app_config.dart';
import 'composer/sectioned_assessment_screen.dart';
import '../../uhis_form/dynamic_assessment_screen.dart';
import 'pathway/pathway_engine.dart';
import 'submission/unified_submission_orchestrator.dart';
import 'triage/patient_context_builder.dart';
import 'visit_controller.dart';
import 'visit_session.dart';

/// Step 3 of the 3-step visit flow: sectioned assessment driven by activated
/// pathways from triage.
///
/// Receives [activatedPathways] (programme name strings) from
/// [TriageResultScreen], rebuilds them into [ActivatedPathway] objects, and
/// delegates to [SectionedAssessmentScreen] for field rendering and CDS.
/// Submission fans out one [LocalAssessmentEntity] per programme via
/// [UnifiedSubmissionOrchestrator].
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
    this.triageNotes,
    this.origin,
    this.onAdvance,
  });

  final String visitId;
  final String? patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;
  final int? gestationalWeeks;

  /// Programme name strings from triage. Non-empty ⇒ sectioned assessment.
  final List<String>? activatedPathways;

  /// Free-text extra symptoms the SK entered in Step 1 not in the symptom list.
  final String? triageNotes;

  final String? origin;

  /// When non-null the screen calls this with the primary programme +
  /// referral flag instead of pushing the `/complete` route. Used by
  /// [VisitFlowScreen] to keep the SK on the same route for all 3 steps.
  final void Function(Programme primaryProgramme, bool referralRecommended)?
      onAdvance;

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  bool _scribeInitialized = false;
  late ScribeController _scribeCtrl;

  /// Set by [_buildSectionedScreen]'s onReferNow callback when a CDS alert
  /// fires a referral recommendation.
  bool _sectionedReferralTriggered = false;

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

  bool get _referralRecommended => _sectionedReferralTriggered;

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
      default:
        interval = const Duration(days: 30);
    }
    return now.add(interval).millisecondsSinceEpoch;
  }

  Programme _getPrimaryProgramme() {
    if (widget.activatedPathways != null) {
      for (final name in widget.activatedPathways!) {
        final p = Programme.fromString(name);
        if (p != Programme.unknown) return p;
      }
    }
    return Programme.unknown;
  }

  // ── Pathway reconstruction ─────────────────────────────────────────────────

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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_scribeInitialized) return const SizedBox.shrink();

    _scribeCtrl.bindContext(context);

    // In-flow hosting (VisitFlowScreen wraps us) suppresses our own AppBars
    // — the wrapper owns the navy patient + step header.
    final bool embedded = widget.onAdvance != null;

    return ChangeNotifierProvider<ScribeController>.value(
      value: _scribeCtrl,
      child: Consumer<VisitController>(
        builder: (ctx, visitCtrl, _) {
          final session = visitCtrl.session;

          if (session == null || session.id != widget.visitId) {
            return Scaffold(
              appBar: embedded ? null : AppBar(title: const Text('Visit')),
              body: const Center(child: Text('Visit session not found.')),
            );
          }

          // Auto-show SOAP review sheet when AI Scribe finishes transcription.
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

          if (_hasActivatedPathways) {
            return _buildSectionedScreen(ctx, visitCtrl, session, embedded);
          }

          return Scaffold(
            appBar:
                embedded ? null : AppBar(title: const Text('Routine Visit')),
            body: const Center(
              child: Text('No assessment pathways activated.'),
            ),
          );
        },
      ),
    );
  }

  // ── Sectioned assessment ───────────────────────────────────────────────────

  Widget _buildSectionedScreen(
    BuildContext ctx,
    VisitController visitCtrl,
    VisitSession session,
    bool embedded,
  ) {
    debugPrint(
        '[VisitForm] Sectioned mode — programmes: ${widget.activatedPathways?.join(', ')}');

    if (AppConfig.useDynamicForms) {
      final allProgrammes = (widget.activatedPathways ?? const [])
          .map(Programme.fromString)
          .where((p) => p != Programme.unknown)
          .toList();
      return DynamicAssessmentScreen(
        programmes: allProgrammes,
        formType: _getPrimaryProgramme().name.toLowerCase(),
        encounterId: widget.visitId,
        patientId: widget.patientId ?? '',
        memberId: widget.memberId,
        draftDao: ctx.read<AssessmentDraftDao>(),
        onSubmit: () => _onSectionedSubmit(ctx, visitCtrl, session),
        onReferNow: () => setState(() => _sectionedReferralTriggered = true),
        embedded: embedded,
      );
    }

    return SectionedAssessmentScreen(
      pathways: _buildPathways(),
      patientContext: _buildPatientContext(),
      encounterId: widget.visitId,
      patientId: widget.patientId ?? '',
      householdMemberLocalId: widget.householdMemberLocalId ?? 0,
      memberId: widget.memberId,
      triageNotes: widget.triageNotes,
      draftDao: ctx.read<AssessmentDraftDao>(),
      embedded: embedded,
      onSubmit: () => _onSectionedSubmit(ctx, visitCtrl, session),
      onReferNow: (_) {
        setState(() => _sectionedReferralTriggered = true);
      },
    );
  }

  Future<void> _onSectionedSubmit(
    BuildContext ctx,
    VisitController visitCtrl,
    VisitSession session,
  ) async {
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

      if (mounted && ctx.mounted) {
        final onAdvance = widget.onAdvance;
        if (onAdvance != null) {
          onAdvance(_getPrimaryProgramme(), _referralRecommended);
        } else {
          ctx.go(
            '/patients/visit/${widget.visitId}/complete',
            extra: {
              'patientLabel': widget.patientId ?? 'Patient',
              'primaryProgramme': _getPrimaryProgramme().name,
              'referralRecommended': _referralRecommended,
              'memberId': widget.memberId,
              'householdId': widget.householdId,
              'origin': widget.origin ?? 'patients',
            },
          );
        }
      }
    } catch (e) {
      debugPrint('VisitFormScreen: assessment save failed: $e');
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: const Text(VisitFormStrings.saveFailed),
        backgroundColor: Theme.of(ctx).colorScheme.error,
      ));
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────
  // Kept for non-sectioned fallback mode; sectioned visits navigate to
  // VisitCompleteScreen instead.

  // ignore: unused_element
  void _showCompletionDialog(BuildContext ctx) {
    final theme = Theme.of(ctx);
    final programmes = widget.activatedPathways ?? [];
    final label = programmes.isEmpty
        ? 'Assessment'
        : programmes
            .map((p) => Programme.fromString(p))
            .where((p) => p != Programme.unknown)
            .map((p) => p.wireTag.toUpperCase())
            .toSet()
            .join(' + ');

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _referralRecommended ? Icons.warning : Icons.check_circle,
              color: _referralRecommended
                  ? theme.colorScheme.error
                  : AppColors.statusSuccess,
            ),
            const SizedBox(width: 12),
            const Text('Assessment Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label assessment saved.'),
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

}
