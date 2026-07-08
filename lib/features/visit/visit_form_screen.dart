import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/scribe_api_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/db/encounter_dao.dart';
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
import 'pathway/pathway_engine.dart';
import 'assessment_repository.dart';
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

/// Prevents concurrent submit calls — set on first tap, cleared only if
  /// submit throws so the SK can retry; successful submit navigates away.
  bool _isSubmitting = false;

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

  /// Extract vital signs from raw field values so they can be persisted to
  /// the encounter row for offline display in VitalsRepository.
  static Map<String, dynamic> _extractVitals(Map<String, dynamic> fv) {
    final out = <String, dynamic>{};
    void pick(String outKey, List<String> aliases) {
      for (final k in aliases) {
        if (fv.containsKey(k) && fv[k] != null) {
          out[outKey] = fv[k];
          return;
        }
      }
    }

    pick('systolic', ['systolic', 'systolicBp', 'bloodPressureSystolic']);
    pick('diastolic', ['diastolic', 'diastolicBp', 'bloodPressureDiastolic']);
    pick('pulse', ['pulse', 'heartRate', 'pulseRate']);
    pick('glucose', ['glucose', 'bloodGlucose', 'glucoseValue', 'bg', 'fbs', 'rbs']);
    pick('weight', ['weight', 'weightInKg']);
    pick('height', ['height', 'heightInCm']);
    pick('bmi', ['bmi', 'bodyMassIndex']);
    pick('temperature', ['temperature', 'temp', 'bodyTemperature']);
    pick('spO2', ['spO2', 'spo2', 'oxygenSaturation', 'oxygenLevel']);
    pick('respiratoryRate', ['respiratoryRate', 'respiratoryRateValue', 'rr']);
    return out;
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
    // Form renderer removed — placeholder until new implementation lands.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.assignment_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Assessment form coming soon',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _onSectionedSubmit(ctx, visitCtrl, session),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _onSectionedSubmit(
    BuildContext ctx,
    VisitController visitCtrl,
    VisitSession session,
  ) async {
    if (_isSubmitting) {
      debugPrint('[VisitForm] _onSectionedSubmit — already submitting, ignoring duplicate tap');
      return;
    }
    _isSubmitting = true;
    debugPrint('[VisitForm] _onSectionedSubmit — visitId=${widget.visitId}');
    // Capture all services synchronously before any await — ctx is invalid after async gaps.
    final draftDao = ctx.read<AssessmentDraftDao>();
    final encounterDao = ctx.read<EncounterDao>();
    final assessmentRepo = ctx.read<AssessmentRepository>();
    final patientDao = ctx.read<PatientDao>();
    final worklistRepo = ctx.read<WorklistRepository>();
    try {
      final draft = await draftDao.getDraft(widget.visitId);
      debugPrint('[VisitForm] draft=${draft != null ? "found" : "null"}');
      if (draft != null) {
        await draftDao.deleteDraft(draft.encounterId);
        debugPrint('[VisitForm] draft deleted, sync will pick up pending assessments');

        final fieldValues = jsonDecode(draft.fieldValues) as Map<String, dynamic>;
        final vitalsMap = _extractVitals(fieldValues);
        final encounterId = draft.encounterId;
        final patientId = widget.patientId;
        final primaryProgramme = _getPrimaryProgramme();
        final now = DateTime.now();

        // Fire housekeeping in background — navigate immediately, these finish async.
        unawaited(Future(() async {
          try {
            if (vitalsMap.isNotEmpty) {
              await encounterDao.updateVitals(encounterId, vitalsMap);
              debugPrint('[VisitForm] encounter vitals written: $vitalsMap');
            }
            debugPrint('[VisitForm] triggering syncPendingAssessments');
            await assessmentRepo.syncPendingAssessments().then(
              (n) => debugPrint('[VisitForm] syncPendingAssessments → synced $n'),
              onError: (e) => debugPrint('[VisitForm] syncPendingAssessments ✗ $e'),
            );
            if (patientId != null) {
              await patientDao.updateVisitSchedule(
                patientId: patientId,
                lastVisitAt: now.millisecondsSinceEpoch,
                nextDueAt: _nextDueForProgramme(primaryProgramme, now),
                missedVisitCount: 0,
              );
              debugPrint('[VisitForm] schedule updated');
              await worklistRepo.recomputeAllAfterSync();
              debugPrint('[VisitForm] worklist recomputed');
            }
          } catch (e) {
            debugPrint('[VisitForm] background housekeeping error: $e');
          }
        }));
      }

      // Navigate immediately — background tasks continue independently.
      debugPrint('[VisitForm] mounted=$mounted ctx.mounted=${ctx.mounted}');
      if (mounted && ctx.mounted) {
        final onAdvance = widget.onAdvance;
        if (onAdvance != null) {
          debugPrint('[VisitForm] calling onAdvance');
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
    } catch (e, st) {
      _isSubmitting = false;
      debugPrint('[VisitForm] assessment save failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(VisitFormStrings.saveFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
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
