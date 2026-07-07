import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/api/realtime_asr_service.dart';
import '../../core/api/scribe_api_service.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../features/dashboard/mission_dashboard_repository.dart';
import '../../features/realtime_asr/realtime_asr_controller.dart';
import '../../features/scribe/scribe_controller.dart';
import '../../features/scribe/scribe_permission_service.dart';
import '../../features/scribe/scribe_session.dart';
import '../../features/scribe/widgets/scribe_fab.dart';
import '../../features/scribe/widgets/scribe_review_sheet.dart';
import '../../features/worklist/worklist_repository.dart';
import 'assessment_repository.dart';
import 'forms/anc_assessment_form.dart';
import 'forms/iccm_assessment_form.dart';
import 'forms/ncd_assessment_form.dart';
import 'forms/tb_assessment_form.dart';
import 'models/anc_assessment.dart';
import 'models/iccm_assessment.dart';
import 'models/ncd_assessment.dart';
import 'models/tb_assessment.dart';

/// Assessment step screen that displays the appropriate form based on programme.
class VisitAssessmentStep extends StatefulWidget {
  const VisitAssessmentStep({
    super.key,
    required this.visitId,
    required this.programme,
    this.patientId,
    this.memberId,
    this.householdId,
    this.villageId,
    this.householdMemberLocalId,
    this.patientAge,
    this.gestationalWeeks,
    this.origin,
  });

  final String visitId;
  final String programme;
  final String? patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;
  final int? gestationalWeeks;
  /// Origin screen for return navigation ('dashboard' or 'tasks')
  final String? origin;

  @override
  State<VisitAssessmentStep> createState() => _VisitAssessmentStepState();
}

class _VisitAssessmentStepState extends State<VisitAssessmentStep> {
  // Form data
  NcdAssessment? _ncdData;
  TbAssessment? _tbData;
  AncAssessment? _ancData;
  IccmAssessment? _iccmData;

  double? _previousAncWeight;
  double? _previousNcdWeight;
  bool _isSubmitting = false;

  late final ScribeController _scribeCtrl;
  // Independent "Live" ASR mode — see ScribeModeFab/ScribeStatusPill docs.
  // Never runs at the same time as the batch flow above.
  late final RealtimeAsrController _liveCtrl;

  @override
  void initState() {
    super.initState();
    _scribeCtrl = ScribeController(
      api: context.read<ScribeApiService>(),
      permissionService: ScribePermissionService(),
    );
    _liveCtrl = RealtimeAsrController(
      service: context.read<RealtimeAsrService>(),
      permissionService: ScribePermissionService(),
    );
    if (widget.patientId != null) {
      final prog = widget.programme.toUpperCase();
      if (prog == 'ANC') _loadPreviousAncWeight();
      if (prog == 'NCD') _loadPreviousNcdWeight();
    }
  }

  Future<void> _loadPreviousAncWeight() async {
    try {
      final dao = context.read<LocalAssessmentDao>();
      final records = await dao.getByPatientId(widget.patientId!);
      final ancRecords = records
          .where((r) => r.assessmentType.toUpperCase() == 'ANC')
          .toList();
      if (ancRecords.isEmpty) return;
      // records sorted DESC by created_at; skip index 0 (current in-progress visit)
      final prev = ancRecords.length > 1 ? ancRecords[1] : ancRecords[0];
      final json =
          jsonDecode(prev.assessmentDetails) as Map<String, dynamic>?;
      final anc = json?['anc'] as Map<String, dynamic>?;
      final phys =
          anc?['medicalHistoryPhysicalExamination'] as Map<String, dynamic>?;
      final w = phys?['weight'];
      if (w == null) return;
      final weight =
          (w is num) ? w.toDouble() : double.tryParse(w.toString());
      if (weight != null && mounted) {
        setState(() => _previousAncWeight = weight);
      }
    } catch (_) {}
  }

  Future<void> _loadPreviousNcdWeight() async {
    try {
      final dao = context.read<LocalAssessmentDao>();
      final records = await dao.getByPatientId(widget.patientId!);
      final ncdRecords = records
          .where((r) => r.assessmentType.toUpperCase() == 'NCD')
          .toList();
      if (ncdRecords.isEmpty) return;
      final prev = ncdRecords.length > 1 ? ncdRecords[1] : ncdRecords[0];
      final json =
          jsonDecode(prev.assessmentDetails) as Map<String, dynamic>?;
      // NCD stores weight at top-level or under bpLog
      final w = json?['weight'] ??
          (json?['bpLog'] as Map?)?['weight'];
      if (w == null) return;
      final weight =
          (w is num) ? w.toDouble() : double.tryParse(w.toString());
      if (weight != null && mounted) {
        setState(() => _previousNcdWeight = weight);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _scribeCtrl.dispose();
    _liveCtrl.dispose();
    super.dispose();
  }
  
  /// Return path based on origin
  String get _returnPath {
    debugPrint('[Assessment] origin=${widget.origin}');
    return widget.origin == 'dashboard' ? '/' : '/tasks';
  }

  String get _programmeTitle {
    switch (widget.programme.toUpperCase()) {
      case 'NCD':
        return 'NCD Assessment';
      case 'TB':
        return 'TB Screening';
      case 'ANC':
        return 'ANC Assessment';
      case 'ICCM':
      case 'IMCI':
        return 'ICCM Assessment';
      default:
        return 'Assessment';
    }
  }

  bool get _referralRecommended {
    switch (widget.programme.toUpperCase()) {
      case 'TB':
        return _tbData?.referralRecommended ?? false;
      case 'ANC':
        return _ancData?.referralRecommended ?? false;
      case 'ICCM':
      case 'IMCI':
        return _iccmData?.referralRecommended ?? false;
      default:
        return false;
    }
  }

  /// Calculate next due date based on programme type.
  /// Returns milliseconds since epoch.
  int _nextDueForProgramme(String programme, DateTime now) {
    final Duration interval;
    switch (programme.toUpperCase()) {
      case 'ANC':
        // ANC visits typically every 4 weeks
        interval = const Duration(days: 28);
        break;
      case 'NCD':
        // NCD follow-ups typically every 30 days
        interval = const Duration(days: 30);
        break;
      case 'TB':
        // TB follow-ups typically every 14 days during treatment
        interval = const Duration(days: 14);
        break;
      case 'ICCM':
      case 'IMCI':
        // Child health check-ups typically monthly
        interval = const Duration(days: 30);
        break;
      default:
        // Default to 30 days
        interval = const Duration(days: 30);
    }
    return now.add(interval).millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Bind context so ScribeController can show permission rationale sheet.
    _scribeCtrl.bindContext(context);
    _liveCtrl.bindContext(context);

    return ChangeNotifierProvider<ScribeController>.value(
      value: _scribeCtrl,
      child: Builder(
        builder: (ctx) {
          // Listen for reviewReady so we can show the review sheet automatically.
          ctx.select<ScribeController, ScribeState>(
            (c) => c.session.state,
          );
          final scribeState = _scribeCtrl.session.state;
          if (scribeState == ScribeState.reviewReady &&
              ModalRoute.of(ctx)?.isCurrent == true) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scribeCtrl.session.state == ScribeState.reviewReady) {
                showScribeReviewSheet(ctx);
              }
            });
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(_programmeTitle),
              actions: [
                if (_referralRecommended)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: const Text('Referral'),
                      avatar: const Icon(Icons.warning, size: 16),
                      backgroundColor: theme.colorScheme.errorContainer,
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            body: Column(
              children: [
                // Scribe pill — appears during recording / upload / processing / ready
                // (or the live ASR status panel, when that mode is active).
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: ScribeStatusPill(
                    liveController: _liveCtrl,
                    onStop: () => _scribeCtrl.stopRecording(
                      patientId: widget.patientId,
                      encounterId: widget.visitId,
                      programme: widget.programme,
                    ),
                  ),
                ),
                Expanded(child: _buildForm()),
              ],
            ),
            floatingActionButton: ScribeModeFab(
              liveController: _liveCtrl,
              onStartRecording: () => _scribeCtrl.startRecording(
                patientId: widget.patientId,
                encounterId: widget.visitId,
                programme: widget.programme,
              ),
              onStopRecording: () => _scribeCtrl.stopRecording(
                patientId: widget.patientId,
                encounterId: widget.visitId,
                programme: widget.programme,
              ),
              onOpenReview: () => showScribeReviewSheet(ctx),
              onRetry: () => _scribeCtrl.retryUpload(
                patientId: widget.patientId,
                encounterId: widget.visitId,
                programme: widget.programme,
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _onSubmit,
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

  Widget _buildForm() {
    switch (widget.programme.toUpperCase()) {
      case 'NCD':
        return NcdAssessmentForm(
          initialData: _ncdData,
          patientAge: widget.patientAge,
          previousWeight: _previousNcdWeight,
          onChanged: (data) => _ncdData = data,
        );
      case 'TB':
        return TbAssessmentForm(
          initialData: _tbData,
          onChanged: (data) {
            _tbData = data;
            setState(() {}); // Rebuild to update referral chip
          },
        );
      case 'ANC':
        return AncAssessmentForm(
          initialData: _ancData,
          gestationalWeeks: widget.gestationalWeeks,
          previousWeight: _previousAncWeight,
          onChanged: (data) {
            _ancData = data;
            setState(() {}); // Rebuild to update referral chip
          },
        );
      case 'ICCM':
      case 'IMCI':
        final ageInMonths = widget.patientAge != null
            ? widget.patientAge! * 12
            : null; // Convert years to months
        return IccmAssessmentForm(
          initialData: _iccmData,
          ageInMonths: ageInMonths,
          onChanged: (data) {
            _iccmData = data;
            setState(() {}); // Rebuild to update referral chip
          },
        );
      default:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.construction, size: 64),
              const SizedBox(height: 16),
              Text(
                'Unknown programme: ${widget.programme}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        );
    }
  }

  Future<void> _onSubmit() async {
    setState(() => _isSubmitting = true);

    try {
      // Get form data as JSON
      final Map<String, dynamic> assessmentData;
      final List<String>? referredReasons;
      
      switch (widget.programme.toUpperCase()) {
        case 'NCD':
          assessmentData = _ncdData?.toJson() ?? {};
          referredReasons = null;
          break;
        case 'TB':
          assessmentData = _tbData?.toJson() ?? {};
          referredReasons = _tbData?.isPositive == true 
              ? ['Positive TB Screen'] 
              : null;
          break;
        case 'ANC':
          assessmentData = _ancData?.toJson() ?? {};
          referredReasons = _ancData?.referralRecommended == true
              ? ['ANC Danger Signs']
              : null;
          break;
        case 'ICCM':
        case 'IMCI':
          assessmentData = _iccmData?.toJson() ?? {};
          referredReasons = _iccmData?.referralRecommended == true
              ? _iccmData!.conditionsSummary
              : null;
          break;
        default:
          assessmentData = {};
          referredReasons = null;
      }

      // Save to local DB via AssessmentRepository (offline-first)
      final repo = context.read<AssessmentRepository>();
      final localId = await repo.saveAssessment(
        assessmentType: widget.programme,
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

      debugPrint('Assessment saved locally with ID: $localId');
      debugPrint('Referral recommended: $_referralRecommended');

      // Fire-and-forget sync to backend — non-blocking so UI isn't delayed
      unawaited(repo.syncPendingAssessments().then(
        (n) => debugPrint('Synced $n assessment(s) to backend'),
        onError: (e) => debugPrint('Assessment sync failed (will retry): $e'),
      ));

      // Mark the encounter as completed so it shows in Tasks completed section
      if (!mounted) return;
      final encounterDao = context.read<EncounterDao>();
      await encounterDao.updateAssessment(widget.visitId, assessmentData);
      debugPrint('Encounter ${widget.visitId} marked as completed');

      // Update patient's scheduling fields:
      // - last_visit_at = now
      // - next_due_at = now + interval (based on programme)
      // - missed_visit_count = 0 (reset since visit completed)
      if (widget.patientId != null) {
        if (!mounted) return;
        final patientDao = context.read<PatientDao>();
        final now = DateTime.now();
        final nowMs = now.millisecondsSinceEpoch;
        // Schedule next visit based on programme type
        final nextDueMs = _nextDueForProgramme(widget.programme, now);
        await patientDao.updateVisitSchedule(
          patientId: widget.patientId!,
          lastVisitAt: nowMs,
          nextDueAt: nextDueMs,
          missedVisitCount: 0,
        );
        debugPrint('Updated patient ${widget.patientId} schedule: lastVisit=$nowMs, nextDue=$nextDueMs');

        // Recompute worklist priorities so patient moves out of Overdue
        if (!mounted) return;
        final worklistRepo = context.read<WorklistRepository>();
        await worklistRepo.recomputeAllAfterSync();
        debugPrint('Worklist recomputed after assessment');
      }

      // Navigate to completion screen
      if (mounted) {
        _showCompletionDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save assessment: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showCompletionDialog() {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
            Text('$_programmeTitle has been saved.'),
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
                        'Referral is recommended based on findings.',
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
                Navigator.pop(ctx);
                // Clear mission cache so dashboard/tasks reload with completed patient
                context.read<MissionDashboardRepository>().clearCache();
                // TODO: Navigate to create referral
                // Return to origin screen (dashboard or tasks)
                debugPrint('[Assessment] Create Referral: returnPath=$_returnPath');
                context.go(_returnPath);
              },
              child: const Text('Create Referral'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Clear mission cache so dashboard/tasks reload with completed patient
              context.read<MissionDashboardRepository>().clearCache();
              // Return to origin screen (dashboard or tasks)
              debugPrint('[Assessment] Done: returnPath=$_returnPath');
              context.go(_returnPath);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
