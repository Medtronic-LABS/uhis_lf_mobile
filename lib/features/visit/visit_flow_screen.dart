/// Unified 4-step visit flow — spec §3.1 (`Apon Sushashthya V1`).
///
/// One [VisitFlowScreen] owns step state; the SK never leaves this route
/// while the visit is in progress. Hosted via the route
/// `/patients/visit/:visitId/flow`.
///
/// Steps (driven by [_VisitFlowState._step]):
///   0 → Step 1: symptom check (AI Scribe) — wraps [SymptomPickerScreen]
///   1 → Step 2: AI programme recommendation — wraps [ProgrammeSelectionScreen]
///   2 → Step 3: vitals + full form — wraps [VisitFormScreen]
///   3 → Step 4: AI recommendation — folded into [_Step3AiReco] here
///
/// Engineering Design Standards:
///   - Single-responsibility step widgets, composed by the wrapper.
///   - No business logic inside the wrapper widget — it owns nav state only.
///   - All copy from [VisitFlowStrings] / [VisitCompleteStrings].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/scribe_api_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/models/patient.dart';
import '../../core/db/pregnancy_snapshot_dao.dart';
import '../../core/models/programme.dart';
import '../../core/theme/app_theme.dart';
import 'naba/naba_models.dart';
import 'naba/naba_repository.dart';
import 'pathway/pathway_engine.dart';
import '../scribe/scribe_controller.dart';
import '../scribe/scribe_permission_service.dart';
import 'programme_selection/programme_selection_screen.dart';
import 'triage/symptom_picker_screen.dart';
import 'household_followup_screen.dart';
import 'visit_form_screen.dart';

/// Single-route 3-step visit flow wrapper.
class VisitFlowScreen extends StatefulWidget {
  const VisitFlowScreen({
    super.key,
    required this.visitId,
    required this.patientId,
    this.memberId,
    this.householdId,
    this.villageId,
    this.householdMemberLocalId,
    this.patientAge,
    this.patientName,
    this.patientGender,
    this.gestationalWeeks,
    this.isPostpartum = false,
    this.postpartumWeeks,
    this.origin,
    this.debugInitialStep,
  });

  final String visitId;
  final String patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;
  final String? patientName;
  final String? patientGender;
  final int? gestationalWeeks;
  final bool isPostpartum;
  final int? postpartumWeeks;
  final String? origin;

  /// Test-only hook: starts the wrapper at the given step so widget tests
  /// can exercise the progress header / Step 3 body without building Steps
  /// 1 and 2 (which require the full Provider chain of DAOs).
  @visibleForTesting
  final int? debugInitialStep;

  @override
  State<VisitFlowScreen> createState() => _VisitFlowState();
}

class _VisitFlowState extends State<VisitFlowScreen> {
  /// Total number of steps in the flow. Single source of truth for the
  /// progress header + clamps + bounds checks. Step 2 is a composite host
  /// — it renders the AI programme recommendation first, then the screening
  /// form — so the SK still sees three top-level progress dots.
  static const int _totalSteps = 3;

  /// Current step index — 0..2.
  late int _step =
      widget.debugInitialStep?.clamp(0, _totalSteps - 1) ?? 0;

  /// Patient name resolved from constructor or, as a fallback, looked up
  /// from the local DB via [PatientDao]. The constructor value wins —
  /// the lookup only fires when the caller did not supply a name.
  late String? _patientName = widget.patientName;
  late int? _patientAge = widget.patientAge;

  /// Postpartum status — seeded from constructor; DB lookup fills in the
  /// weeks value from [PregnancySnapshotDao] when not supplied by caller.
  late bool _isPostpartum = widget.isPostpartum;
  late final int? _postpartumWeeks = widget.postpartumWeeks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_patientName == null && widget.patientId.isNotEmpty) {
        _loadPatientNameFromDb();
      }
      if (!_isPostpartum && widget.patientId.isNotEmpty) {
        _loadPostpartumFromDb();
      }
    });
  }

  Future<void> _loadPatientNameFromDb() async {
    try {
      final dao = context.read<PatientDao>();
      final p = await dao.byId(widget.patientId);
      if (!mounted || p == null) return;
      setState(() {
        _patientName = _patientName ?? p.name;
        _patientAge = _patientAge ?? p.age;
      });
    } catch (e) {
      debugPrint('[VisitFlow] patient lookup failed: $e');
    }
  }

  Future<void> _loadPostpartumFromDb() async {
    try {
      final dao = context.read<PregnancySnapshotDao>();
      final all = await dao.getAll();
      final facts = all[widget.patientId];
      if (!mounted || facts == null) return;
      if (facts.isPostpartumWindow) {
        setState(() {
          _isPostpartum = true;
        });
      }
    } catch (e) {
      debugPrint('[VisitFlow] postpartum lookup failed: $e');
    }
  }

  /// Pathways activated in Step 1 (rule engine), passed through to Step 3 if
  /// the SK accepts the AI's programme set verbatim. Kept for back-compat
  /// with the existing form composer.
  List<ActivatedPathway> _pathways = const <ActivatedPathway>[];

  /// Symptoms the SK confirmed in Step 1. Used to build the Step 2
  /// programme-recommendation request payload.
  Set<String> _confirmedSymptoms = const <String>{};

  /// Sickness duration the SK picked in Step 1 ('1', '2-3', '4+').
  String? _sicknessDuration;

  /// Free-text "other symptoms" the SK typed in Step 1.
  String? _otherSymptoms;

  /// Programmes the SK confirmed in Step 2 — drives Step 3 form composition.
  Set<Programme> _confirmedProgrammes = const <Programme>{};

  /// Set when Step 3 completes — handed to Step 4 for the recommendation card.
  Programme _primaryProgramme = Programme.unknown;
  bool _referralRecommended = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_step > 0) {
          setState(() => _step -= 1);
        } else {
          await _exitFlow();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: SafeArea(
          child: Column(
            children: [
              _VisitFlowHeader(
                step: _step,
                patientName: _patientName,
                patientAge: _patientAge,
                householdId: widget.householdId,
                patientGender: widget.patientGender,
                primaryProgramme: _pathways.isNotEmpty
                    ? _pathways.first.programme
                    : _primaryProgramme,
                onBack: () {
                  if (_step > 0) {
                    setState(() => _step -= 1);
                  } else {
                    _exitFlow();
                  }
                },
              ),
              Expanded(child: _buildStepBody()),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the discard-confirmation dialog and, on confirm, navigates back
  /// to the home tab. Single home for context-after-await guards so the
  /// lint rule for `use_build_context_synchronously` lives in one place.
  Future<void> _exitFlow() async {
    final ok = await _confirmExit();
    if (!mounted) return;
    if (ok == true) context.go('/home');
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return _Step1Symptoms(
          key: ValueKey('flow-step1-${widget.visitId}'),
          encounterId: widget.visitId,
          patientId: widget.patientId,
          memberId: widget.memberId,
          householdId: widget.householdId,
          patientAge: widget.patientAge,
          patientName: widget.patientName,
          patientGender: widget.patientGender,
          origin: widget.origin,
          onSymptomsConfirmed: (symptoms, duration, other) {
            // Captured before onAdvance fires (see SymptomPickerScreen).
            _confirmedSymptoms = symptoms;
            _sicknessDuration = duration;
            _otherSymptoms = other;
          },
          onAdvance: (pathways) {
            _pathways = pathways;
            _showProgrammeConfirmSheet(pathways);
          },
        );
      case 1:
        // Step 2 is composite: AI programme recommendation → form. The
        // internal phase switch lives inside the host so the SK still sees a
        // 3-step progress header.
        return _Step2ProgrammesThenForm(
          key: ValueKey('flow-step2-${widget.visitId}'),
          visitId: widget.visitId,
          patientId: widget.patientId,
          memberId: widget.memberId,
          householdId: widget.householdId,
          villageId: widget.villageId,
          householdMemberLocalId: widget.householdMemberLocalId,
          patientAge: widget.patientAge,
          patientName: widget.patientName,
          patientGender: widget.patientGender,
          gestationalWeeks: widget.gestationalWeeks,
          isPostpartum: _isPostpartum,
          postpartumWeeks: _postpartumWeeks,
          confirmedSymptoms: _confirmedSymptoms,
          sicknessDuration: _sicknessDuration,
          otherSymptoms: _otherSymptoms,
          seedProgrammes: _confirmedProgrammes,
          origin: widget.origin,
          onAdvance: (programme, referral) {
            setState(() {
              _primaryProgramme = programme;
              _referralRecommended = referral;
              _step = 2;
            });
          },
        );
      case 2:
      default:
        return _Step3AiReco(
          key: ValueKey('flow-step3-${widget.visitId}'),
          visitId: widget.visitId,
          patientId: widget.patientId,
          patientLabel: widget.patientName ?? widget.patientId,
          patientAge: widget.patientAge,
          patientGender: widget.patientGender,
          gestationalWeeks: widget.gestationalWeeks,
          confirmedSymptoms: _confirmedSymptoms,
          confirmedProgrammes: _confirmedProgrammes,
          primaryProgramme: _primaryProgramme,
          referralRecommended: _referralRecommended,
          memberId: widget.memberId,
          householdId: widget.householdId,
          origin: widget.origin ?? 'patients',
        );
    }
  }

  void _showProgrammeConfirmSheet(List<ActivatedPathway> pathways) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ProgrammeConfirmSheet(
        pathways: pathways,
        onConfirm: (selected) {
          if (!mounted) return;
          setState(() {
            _confirmedProgrammes = selected;
            _step = 1;
          });
        },
      ),
    );
  }

  Future<bool?> _confirmExit() => showLeaveVisitDialog(context);
}

/// Shared leave-visit confirmation dialog.
/// Returns true if the user chose to leave, false/null to stay.
Future<bool?> showLeaveVisitDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.h5xl, 22, AppSpacing.h5xl, AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Danger icon disc — softens the warning while making it clear
              // this is a destructive action.
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.statusCritical.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  size: 28,
                  color: AppColors.statusCritical,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                VisitFlowStrings.discardConfirmTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                VisitFlowStrings.discardConfirm,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              // Stack the CTAs vertically so the destructive action is
              // visually separated from the safer "Stay" path; Stay is
              // primary (filled navy) so a stray tap doesn't lose the visit.
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text(VisitFlowStrings.discardCancel),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.statusCritical,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text(VisitFlowStrings.discardConfirmCta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
}

/// Visit flow header — single navy header that replaces every per-screen
/// AppBar inside the flow.
///
/// Layout (spec mockup):
///
///   ┌─────────────────────────────────────────────────┐
///   │ ←  Back to visits                               │
///   │                                                 │
///   │ [NB]  Nasrin Begum                              │
///   │       Age 24 · House #07                        │
///   │                                                 │
///   │ ●1. How are you?   2. {programme} form   3. Summary │
///   └─────────────────────────────────────────────────┘
///
/// Step label 2 takes the activated programme name (or "Visit" fallback)
/// so the SK sees what they are about to enter.
class _VisitFlowHeader extends StatelessWidget {
  const _VisitFlowHeader({
    required this.step,
    required this.onBack,
    this.patientName,
    this.patientAge,
    this.householdId,
    this.patientGender,
    this.primaryProgramme = Programme.unknown,
  });

  final int step; // 0..2
  final VoidCallback onBack;
  final String? patientName;
  final int? patientAge;
  final String? householdId;
  final String? patientGender;
  final Programme primaryProgramme;

  static const Color _headerColor = Color(0xFF831843);

  String get _initials {
    final name = (patientName ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final step2Title = (primaryProgramme == Programme.anc ||
            primaryProgramme == Programme.pnc)
        ? 'Pregnancy checks'
        : VisitFlowStrings.step2Title;
    final stepLabels = <String>[
      '1. ${VisitFlowStrings.step1Title}',
      '2. $step2Title',
      '3. ${VisitFlowStrings.step3Title}',
    ];

    return Material(
      color: _headerColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: ← Back to visits
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(AppRadius.rxIcon),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        VisitFlowStrings.backToVisits,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Row 2 + 3: avatar + name / age · house
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            patientName ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (patientAge != null)
                                _DemoChip(
                                  icon: Icons.cake_outlined,
                                  label: 'Age $patientAge',
                                ),
                              if (patientGender != null && patientGender!.isNotEmpty)
                                _DemoChip(
                                  icon: patientGender!.toUpperCase().startsWith('F')
                                      ? Icons.female_rounded
                                      : Icons.male_rounded,
                                  label: patientGender!.toUpperCase().startsWith('F')
                                      ? 'Female'
                                      : 'Male',
                                ),
                              if (householdId != null && householdId!.isNotEmpty)
                                _DemoChip(
                                  icon: Icons.home_outlined,
                                  label: 'House #$householdId',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Row 4: 3-step line indicators with labels below.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(stepLabels.length, (i) {
                        final filled = i <= step;
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: EdgeInsets.only(
                              right: i == stepLabels.length - 1 ? 0 : AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: filled
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: List.generate(stepLabels.length, (i) {
                        final active = i == step;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: i == stepLabels.length - 1 ? 0 : AppSpacing.sm,
                            ),
                            child: Text(
                              stepLabels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight:
                                    active ? FontWeight.w800 : FontWeight.w500,
                                color: Colors.white.withValues(
                                  alpha: active ? 1.0 : 0.6,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _DemoChip extends StatelessWidget {
  const _DemoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.75)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}


/// Step 1 — symptom check.
///
/// Thin host for [SymptomPickerScreen] with a parent-supplied `onAdvance`
/// callback so the picker advances the wrapper's step counter instead of
/// pushing the `/triage-result` route. Behaviour identical to the legacy
/// standalone screen otherwise.
class _Step1Symptoms extends StatelessWidget {
  const _Step1Symptoms({
    super.key,
    required this.encounterId,
    required this.patientId,
    required this.onAdvance,
    required this.onSymptomsConfirmed,
    this.memberId,
    this.householdId,
    this.patientAge,
    this.patientName,
    this.patientGender,
    this.origin,
  });

  final String encounterId;
  final String patientId;
  final String? memberId;
  final String? householdId;
  final int? patientAge;
  final String? patientName;
  final String? patientGender;
  final String? origin;
  final ValueChanged<List<ActivatedPathway>> onAdvance;
  final void Function(
    Set<String> symptoms,
    String? sicknessDuration,
    String? otherSymptoms,
  ) onSymptomsConfirmed;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScribeController>(
      create: (ctx) => ScribeController(
        api: ctx.read<ScribeApiService>(),
        permissionService: ScribePermissionService(),
      ),
      child: SymptomPickerScreen(
        encounterId: encounterId,
        patientId: patientId,
        memberId: memberId,
        householdId: householdId,
        patientAge: patientAge,
        patientName: patientName,
        patientGender: patientGender,
        origin: origin,
        onAdvance: onAdvance,
        onSymptomsConfirmed: onSymptomsConfirmed,
      ),
    );
  }
}

/// Step 2 — vitals + full sectioned form (single AI Scribe).
///
/// Thin host for [VisitFormScreen] in the same pattern as Step 1.
class _Step2VitalsForm extends StatelessWidget {
  const _Step2VitalsForm({
    required this.visitId,
    required this.patientId,
    required this.onAdvance,
    this.memberId,
    this.householdId,
    this.villageId,
    this.householdMemberLocalId,
    this.patientAge,
    this.gestationalWeeks,
    this.pathwayNames,
    this.triageNotes,
    this.origin,
  });

  final String visitId;
  final String patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;
  final int? gestationalWeeks;
  final List<String>? pathwayNames;
  final String? triageNotes;
  final String? origin;
  final void Function(Programme primaryProgramme, bool referralRecommended)
      onAdvance;

  @override
  Widget build(BuildContext context) {
    return VisitFormScreen(
      visitId: visitId,
      patientId: patientId,
      memberId: memberId,
      householdId: householdId,
      villageId: villageId,
      householdMemberLocalId: householdMemberLocalId,
      patientAge: patientAge,
      gestationalWeeks: gestationalWeeks,
      activatedPathways: pathwayNames,
      triageNotes: triageNotes,
      origin: origin,
      onAdvance: onAdvance,
    );
  }
}

/// Step 2 — composite "AI programme recommendation → screening form".
///
/// Renders the [ProgrammeSelectionScreen] first; once the SK taps Continue,
/// swaps to [VisitFormScreen] using the confirmed programme set. The phase
/// switch is owned here so the top-level [VisitFlowScreen] keeps a 3-step
/// progress header.
///
/// Back button behaviour:
///   - From the form phase, hitting back returns to the programme phase
///     (programme selection is preserved).
///   - From the programme phase, back bubbles up to the host which drops to
///     Step 1.
class _Step2ProgrammesThenForm extends StatefulWidget {
  const _Step2ProgrammesThenForm({
    super.key,
    required this.visitId,
    required this.patientId,
    required this.confirmedSymptoms,
    required this.sicknessDuration,
    required this.otherSymptoms,
    required this.seedProgrammes,
    required this.onAdvance,
    this.memberId,
    this.householdId,
    this.villageId,
    this.householdMemberLocalId,
    this.patientAge,
    this.patientName,
    this.patientGender,
    this.gestationalWeeks,
    this.isPostpartum = false,
    this.postpartumWeeks,
    this.origin,
  });

  final String visitId;
  final String patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;
  final String? patientName;
  final String? patientGender;
  final int? gestationalWeeks;
  final bool isPostpartum;
  final int? postpartumWeeks;
  final Set<String> confirmedSymptoms;
  final String? sicknessDuration;
  final String? otherSymptoms;
  final Set<Programme> seedProgrammes;
  final String? origin;
  final void Function(Programme primaryProgramme, bool referralRecommended)
      onAdvance;

  @override
  State<_Step2ProgrammesThenForm> createState() =>
      _Step2ProgrammesThenFormState();
}

enum _Step2Phase { programmes, form }

class _Step2ProgrammesThenFormState extends State<_Step2ProgrammesThenForm> {
  _Step2Phase _phase = _Step2Phase.programmes;
  Set<Programme> _currentProgrammes = const <Programme>{};
  Set<Programme> _selectedProgrammes = const <Programme>{};
  Map<String, dynamic> _request = const <String, dynamic>{};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _selectedProgrammes = widget.seedProgrammes;
    // AI programme recommendation disabled — use rule-based PathwayEngine result directly.
    _phase = _Step2Phase.form;
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    final dao = context.read<PatientProgrammesDao>();
    try {
      final progs = await dao.programmesFor(widget.patientId);
      if (!mounted) return;
      setState(() {
        _currentProgrammes = progs;
        _request = _buildRequest(progs);
        _ready = true;
      });
    } catch (e) {
      debugPrint('[Step2] currentProgrammes lookup failed: $e');
      if (!mounted) return;
      setState(() {
        _currentProgrammes = const <Programme>{};
        _request = _buildRequest(const <Programme>{});
        _ready = true;
      });
    }
  }

  Map<String, dynamic> _buildRequest(Set<Programme> currentProgrammes) {
    return <String, dynamic>{
      'patientId': widget.patientId,
      if (widget.patientName != null) 'patientName': widget.patientName,
      if (widget.patientAge != null) 'ageYears': widget.patientAge,
      if (widget.patientAge != null)
        'ageMonths': (widget.patientAge ?? 0) * 12,
      if (widget.patientGender != null) 'gender': widget.patientGender,
      'isPregnant': widget.gestationalWeeks != null,
      if (widget.gestationalWeeks != null)
        'gestationalWeeks': widget.gestationalWeeks,
      'isPostpartum': widget.isPostpartum,
      if (widget.postpartumWeeks != null)
        'postpartumWeeks': widget.postpartumWeeks,
      'selectedSymptoms': widget.confirmedSymptoms.toList(),
      if (widget.sicknessDuration != null)
        'sicknessDuration': widget.sicknessDuration,
      if (widget.otherSymptoms != null && widget.otherSymptoms!.isNotEmpty)
        'otherSymptoms': widget.otherSymptoms,
      'currentProgrammes': currentProgrammes
          .where((p) => p != Programme.unknown)
          .map((p) => p.wireTag)
          .toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_phase == _Step2Phase.programmes) {
      return ProgrammeSelectionScreen(
        request: _request,
        currentProgrammes: _currentProgrammes,
        onContinue: (programmes) {
          setState(() {
            _selectedProgrammes = programmes;
            _phase = _Step2Phase.form;
          });
        },
      );
    }
    return _Step2VitalsForm(
      visitId: widget.visitId,
      patientId: widget.patientId,
      memberId: widget.memberId,
      householdId: widget.householdId,
      villageId: widget.villageId,
      householdMemberLocalId: widget.householdMemberLocalId,
      patientAge: widget.patientAge,
      gestationalWeeks: widget.gestationalWeeks,
      pathwayNames: _selectedProgrammes
          .where((p) => p != Programme.unknown)
          .map((p) => p.name)
          .toList(),
      triageNotes: widget.otherSymptoms,
      origin: widget.origin,
      onAdvance: widget.onAdvance,
    );
  }
}

/// Step 3 — AI Next Best Action care plan proposal.
///
/// Calls [NabaRepository.generate] with the visit context assembled from
/// prior steps, then renders the structured care plan (visit summary, danger
/// signs, clinical findings, next actions, counselling, referral, WhatsApp).
///
/// The response is a *proposal* — FHIR resources are written only after the
/// SK accepts (architecture.md §5.2). The Accept button triggers [_onAccepted],
/// which logs the rationale snapshot and navigates the SK home.
class _Step3AiReco extends StatefulWidget {
  const _Step3AiReco({
    super.key,
    required this.visitId,
    required this.patientId,
    required this.primaryProgramme,
    required this.referralRecommended,
    required this.origin,
    required this.confirmedSymptoms,
    required this.confirmedProgrammes,
    this.patientLabel,
    this.patientAge,
    this.patientGender,
    this.gestationalWeeks,
    this.memberId,
    this.householdId,
  });

  final String visitId;
  final String patientId;
  final String? patientLabel;
  final int? patientAge;
  final String? patientGender;
  final int? gestationalWeeks;
  final Set<String> confirmedSymptoms;
  final Set<Programme> confirmedProgrammes;
  final Programme primaryProgramme;
  final bool referralRecommended;
  final String? memberId;
  final String? householdId;
  final String origin;

  @override
  State<_Step3AiReco> createState() => _Step3AiRecoState();
}

class _Step3AiRecoState extends State<_Step3AiReco>
    with SingleTickerProviderStateMixin {
  late Future<NabaResponse> _future;
  late AnimationController _shimmer;
  bool _accepted = false;
  String? _patientPhone;
  List<_HouseholdMember>? _householdMembers;

  Color _headerColor(Programme p) => switch (p) {
        Programme.anc || Programme.pnc => AppColors.ancHeader,
        Programme.ncd => AppColors.ncdHeader,
        Programme.imci => AppColors.imciHeader,
        Programme.tb => AppColors.tbHeader,
        _ => AppColors.navy,
      };

  String get _returnPath => widget.origin == 'dashboard' ? '/home' : '/tasks';

  @override
  void initState() {
    super.initState();
    _future = _fetchNaba();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _loadPatientPhone();
    _loadHouseholdMembers();
  }

  Future<void> _loadPatientPhone() async {
    final member = await context
        .read<MemberDao>()
        .getByPatientId(widget.patientId);
    final phone = member?.phone;
    if (mounted && phone != null && phone.isNotEmpty) {
      setState(() => _patientPhone = phone);
    }
  }

  Future<void> _loadHouseholdMembers() async {
    String? hid = widget.householdId;
    if ((hid == null || hid.isEmpty) && mounted) {
      try {
        final patient = await context.read<PatientDao>().byId(widget.patientId);
        hid = patient?.householdId;
      } on Object catch (_) {}
    }
    if (hid == null || hid.isEmpty || !mounted) return;

    final patientDao = context.read<PatientDao>();
    final progDao = context.read<PatientProgrammesDao>();

    final rows = await patientDao.getByHouseholdId(hid);
    final patients = rows.map(Patient.fromDb).where((p) => p.isActive != false).toList();
    final ids = patients.map((p) => p.id).toList();
    final progMap = await progDao.programmesForMany(ids);

    if (!mounted) return;
    final members = patients.map((p) {
      final progs = progMap[p.id] ?? {};
      final primary = progs.isNotEmpty ? progs.first : Programme.unknown;
      return _HouseholdMember(
        patientId: p.id,
        name: p.name ?? '—',
        primaryProgramme: primary,
        isCurrentPatient: p.id == widget.patientId,
      );
    }).toList()
      ..sort((a, b) {
        if (a.isCurrentPatient) return -1;
        if (b.isCurrentPatient) return 1;
        return 0;
      });

    setState(() => _householdMembers = members);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  Future<NabaResponse> _fetchNaba() async {
    try {
      final repo = NabaRepository(context.read<ApiClient>());
      final programmes = widget.confirmedProgrammes
          .where((p) => p != Programme.unknown)
          .map((p) => p.wireTag)
          .toList();

      final req = NabaRequest(
        requestId: widget.visitId,
        patientId: widget.patientId,
        visitType: 'routine',
        ageYears: widget.patientAge,
        sex: widget.patientGender,
        activeProgrammes: programmes,
        gestationalWeeks: widget.gestationalWeeks,
        isPregnant: widget.gestationalWeeks != null,
        manuallySelectedSymptoms: widget.confirmedSymptoms.toList(),
      );
      return await repo.generate(req);
    } catch (e) {
      debugPrint('[NABA] AI failed — rule-based fallback: $e');
      return _ruleBasedNaba();
    }
  }

  NabaResponse _ruleBasedNaba() {
    final progs = widget.confirmedProgrammes;
    final hasAnc = progs.contains(Programme.anc);
    final hasNcd = progs.contains(Programme.ncd);
    final hasPnc = progs.contains(Programme.pnc);
    final hasImci = progs.contains(Programme.imci);
    final hasTb = progs.contains(Programme.tb);

    final actions = <NabaNextAction>[];
    final counselling = <String>[];
    final followUp = <NabaFollowUpItem>[];

    if (hasAnc) {
      final gw = widget.gestationalWeeks;
      if (gw != null && gw >= 36) {
        actions.add(const NabaNextAction(
          priority: 0,
          action: 'Patient is at or near term (≥36 weeks). Advise to go to facility immediately if labour starts.',
          urgency: 'Now',
          programme: 'ANC',
        ));
      }
      actions.addAll(const [
        NabaNextAction(priority: 1, action: 'Measure blood pressure, weight, and fundal height', urgency: 'Today', programme: 'ANC'),
        NabaNextAction(priority: 2, action: 'Check for danger signs: heavy bleeding, severe headache, blurred vision, convulsions, no fetal movement', urgency: 'Today', programme: 'ANC'),
        NabaNextAction(priority: 3, action: 'Confirm iron-folic acid supply for next 4 weeks', urgency: 'Today', programme: 'ANC'),
        NabaNextAction(priority: 4, action: 'Schedule next ANC visit in 4 weeks', urgency: 'This week', programme: 'ANC'),
      ]);
      counselling.addAll(const [
        'Take iron-folic acid tablet every day, even when feeling well',
        'Eat nutritious food: green vegetables, lentils, fish, eggs',
        'Sleep under a bednet every night',
        'Plan delivery with a skilled attendant at a health facility',
        'Go to facility immediately if any danger sign occurs',
      ]);
      followUp.add(const NabaFollowUpItem(
        activity: 'ANC visit — BP, weight, fundal height, fetal position',
        timeline: 'In 4 weeks',
        programme: 'ANC',
      ));
    }

    if (hasNcd) {
      actions.addAll(const [
        NabaNextAction(priority: 1, action: 'Measure blood pressure in both arms', urgency: 'Today', programme: 'NCD'),
        NabaNextAction(priority: 2, action: 'Check fasting blood glucose if patient has diabetes', urgency: 'Today', programme: 'NCD'),
        NabaNextAction(priority: 3, action: 'Verify medication supply — patient must not run out', urgency: 'Today', programme: 'NCD'),
        NabaNextAction(priority: 4, action: 'Counsel on lifestyle: salt reduction, daily walking, no tobacco', urgency: 'This week', programme: 'NCD'),
      ]);
      counselling.addAll(const [
        'Take all prescribed medications every day without skipping',
        'Reduce salt in cooking — avoid processed and salty foods',
        'Walk at least 30 minutes every day',
        'Avoid tobacco and alcohol',
        'Return immediately for one-sided weakness, sudden severe headache, or chest pain',
      ]);
      followUp.add(const NabaFollowUpItem(
        activity: 'BP and glucose re-check',
        timeline: 'In 4 weeks',
        programme: 'NCD',
      ));
    }

    if (hasPnc) {
      actions.addAll(const [
        NabaNextAction(priority: 1, action: "Check mother's BP and temperature; assess lochia and wound healing", urgency: 'Today', programme: 'PNC'),
        NabaNextAction(priority: 2, action: 'Weigh neonate; check cord stump; observe breastfeeding latch', urgency: 'Today', programme: 'PNC'),
        NabaNextAction(priority: 3, action: 'Confirm vitamin A given to mother within 8 weeks of delivery', urgency: 'Today', programme: 'PNC'),
        NabaNextAction(priority: 4, action: 'Counsel on family planning options', urgency: 'This week', programme: 'PNC'),
      ]);
      counselling.addAll(const [
        'Breastfeed exclusively for 6 months — no water, no other food',
        'Keep baby warm and cord stump clean and dry',
        'Eat nutritious food to support breast milk production',
        'Seek care immediately for heavy bleeding, fever, foul-smelling discharge, or baby not feeding',
      ]);
      followUp.add(const NabaFollowUpItem(
        activity: 'PNC follow-up — mother and neonate',
        timeline: 'In 7 days',
        programme: 'PNC',
      ));
    }

    if (hasImci) {
      actions.addAll(const [
        NabaNextAction(priority: 1, action: 'Measure temperature and respiratory rate; assess hydration status', urgency: 'Today', programme: 'IMCI'),
        NabaNextAction(priority: 2, action: 'Classify illness per IMCI chart; prescribe ORS and zinc if diarrhoea', urgency: 'Today', programme: 'IMCI'),
        NabaNextAction(priority: 3, action: 'Check for danger signs: not able to drink, persistent vomiting, convulsions, very sleepy', urgency: 'Today', programme: 'IMCI'),
      ]);
      counselling.addAll(const [
        'Continue breastfeeding or usual feeding during illness',
        'Give ORS frequently if child has diarrhoea',
        'Complete full zinc course (10 days) for diarrhoea',
        'Return immediately if child is not improving or has a danger sign',
      ]);
      followUp.add(const NabaFollowUpItem(
        activity: 'Follow-up sick child visit',
        timeline: 'In 2 days',
        programme: 'IMCI',
      ));
    }

    if (hasTb) {
      actions.addAll(const [
        NabaNextAction(priority: 1, action: 'Confirm TB treatment adherence — check pill count and any side effects', urgency: 'Today', programme: 'TB'),
        NabaNextAction(priority: 2, action: 'Counsel on infection control: cough hygiene, ventilation, mask use', urgency: 'Today', programme: 'TB'),
      ]);
      counselling.addAll(const [
        'Take TB medicines every day without stopping — stopping leads to drug resistance',
        'Cover mouth when coughing; keep rooms well-ventilated',
        'All household contacts should be screened for TB symptoms',
      ]);
      followUp.add(const NabaFollowUpItem(
        activity: 'TB treatment adherence check',
        timeline: 'In 2 weeks',
        programme: 'TB',
      ));
    }

    if (actions.isEmpty) {
      actions.add(const NabaNextAction(
        priority: 1,
        action: 'Record vital signs and complete routine clinical assessment',
        urgency: 'Today',
      ));
      counselling.add('Follow up as scheduled and contact the health worker if symptoms worsen');
      followUp.add(const NabaFollowUpItem(
        activity: 'Routine follow-up visit',
        timeline: 'In 4 weeks',
      ));
    }

    return NabaResponse(
      requestId: widget.visitId,
      modelVersion: 'rule-based-fallback',
      generatedAt: DateTime.now().toIso8601String(),
      rationale: const NabaRationale(
        guidelineIds: ['WHO-ANC-2016', 'IMCI-2014', 'BN-NCD-2023'],
        sourceObservations: ['Programme context', 'Gestational age', 'Confirmed symptoms'],
        modelVersion: 'rule-based-fallback',
        confidence: 0.7,
        humanReviewRequired: true,
      ),
      visitSummary: NabaVisitSummary(
        title: _programmeSummaryTitle(widget.primaryProgramme),
        summary: 'Care plan generated using clinical guidelines. AI service was unavailable — review and adjust based on your clinical judgement.',
      ),
      nextActions: actions,
      counselling: counselling,
      followUp: followUp,
      referralRecommendation: widget.referralRecommended
          ? const NabaReferralRecommendation(
              required_: true,
              destination: 'Upazila Health Complex',
              urgency: 'Today',
              reason: 'Referral recommended based on clinical assessment',
            )
          : null,
    );
  }

  static String _programmeSummaryTitle(Programme p) => switch (p) {
        Programme.anc => 'ANC Visit — Guideline Care Plan',
        Programme.pnc => 'PNC Visit — Guideline Care Plan',
        Programme.ncd => 'NCD Visit — Guideline Care Plan',
        Programme.imci => 'Child Health Visit — Guideline Care Plan',
        Programme.tb => 'TB Follow-up — Guideline Care Plan',
        _ => 'Visit — Guideline Care Plan',
      };

  void _retry() {
    final nextFuture = _fetchNaba();
    setState(() => _future = nextFuture);
  }

  Future<void> _onAccepted(NabaResponse naba) async {
    if (_accepted) return;
    setState(() => _accepted = true);
    if (!mounted) return;

    // Prefer householdId from widget (passed via navigation extra).
    // If null (e.g. visit started from a screen that didn't set it), fall back
    // to a DB lookup on the patient row — same data, different code path.
    String? hid = widget.householdId;
    if ((hid == null || hid.isEmpty) && mounted) {
      try {
        final patient =
            await context.read<PatientDao>().byId(widget.patientId);
        hid = patient?.householdId;
        debugPrint(
          '[Step3] householdId from widget=${widget.householdId} '
          'DB fallback=$hid patientId=${widget.patientId}',
        );
      } on Object catch (e) {
        debugPrint('[Step3] householdId DB lookup failed: $e');
      }
    }

    if (!mounted) return;
    if (hid != null && hid.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HouseholdFollowUpScreen(
            householdId: hid!,
            excludePatientId: widget.patientId,
            onDone: () => context.go(_returnPath),
            onViewPatient: (patientId) => context.push('/patients/$patientId'),
          ),
        ),
      );
    } else {
      debugPrint(
        '[Step3] No householdId for patient ${widget.patientId} — skipping follow-up screen',
      );
      context.go(_returnPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NabaResponse>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildLoading();
        }
        if (snap.hasError) {
          return _buildError(snap.error);
        }
        return _buildResult(snap.data!);
      },
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.h8xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing AI icon
            AnimatedBuilder(
              animation: _shimmer,
              builder: (context, unused) => Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    AppColors.aiSurfaceStart,
                    AppColors.aiSurfaceEnd,
                    _shimmer.value,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.aiPurple.withValues(
                          alpha: 0.15 + 0.1 * _shimmer.value),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 38,
                  color: AppColors.aiPurple,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              NabaStrings.loadingTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              NabaStrings.loadingSubtitle,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            // Skeleton preview cards
            AnimatedBuilder(
              animation: _shimmer,
              builder: (context, unused) {
                final shimmerColor = Color.lerp(
                  AppColors.border,
                  AppColors.progressTrack,
                  _shimmer.value,
                )!;
                return Column(
                  children: [
                    _SkeletonCard(color: shimmerColor, height: 72),
                    const SizedBox(height: 10),
                    _SkeletonCard(color: shimmerColor, height: 56),
                    const SizedBox(height: 10),
                    _SkeletonCard(color: shimmerColor, height: 64),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.h8xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.statusCriticalSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 36,
                color: AppColors.statusCritical,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              NabaStrings.errorTitle,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              NabaStrings.errorSubtitle,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(NabaStrings.retryButton),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.go(_returnPath),
              child: const Text(NabaStrings.skipButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(NabaResponse naba) {
    final headerColor = _headerColor(widget.primaryProgramme);
    final referral =
        naba.referralRecommendation?.required_ ?? widget.referralRecommended;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, AppSpacing.xxxl, AppSpacing.xxxl, AppSpacing.h8xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // ── Success header ────────────────────────────────────────
              _ResultHeader(
                programme: widget.primaryProgramme,
                headerColor: headerColor,
              ),
              const SizedBox(height: 16),

              // ── Household "also cover while you're here" strip ────────
              if (_householdMembers != null && _householdMembers!.length > 1) ...[
                _HouseholdMemberStrip(
                  members: _householdMembers!,
                  onTapMember: (patientId) =>
                      context.push('/patients/$patientId'),
                ),
                const SizedBox(height: 16),
              ],

              // ── AI fallback notice ────────────────────────────────────
              if (naba.modelVersion == 'rule-based-fallback') ...[
                const _FallbackNoticeBanner(),
                const SizedBox(height: 12),
              ],

              // ── Danger signs — elevated to top ────────────────────────
              if (naba.dangerSigns.isNotEmpty) ...[
                _DangerSignsAlert(signs: naba.dangerSigns),
                const SizedBox(height: 12),
              ],

              // ── Banners: review required + referral ───────────────────
              if (naba.rationale.humanReviewRequired) ...[
                _InfoBanner(
                  color: AppColors.ncdSurface,
                  borderColor: AppColors.warningBorderAlt,
                  icon: Icons.supervisor_account_rounded,
                  iconColor: AppColors.slaDueSoonText,
                  text: NabaStrings.humanReviewBadge,
                ),
                const SizedBox(height: 12),
              ],
              if (referral) ...[
                _InfoBanner(
                  color: AppColors.statusCriticalSurface,
                  borderColor: AppColors.statusCriticalBorder,
                  icon: Icons.local_hospital_rounded,
                  iconColor: AppColors.statusCritical,
                  text: naba.referralRecommendation?.reason ??
                      VisitCompleteStrings.referralWarning,
                  label: NabaStrings.referralRequired,
                ),
                const SizedBox(height: 12),
              ],

              // ── Visit summary ─────────────────────────────────────────
              _SummaryCard(
                title: naba.visitSummary.title,
                body: naba.visitSummary.summary,
                headerColor: headerColor,
                confidence: naba.rationale.confidence,
              ),
              const SizedBox(height: 12),

              // ── Next actions ──────────────────────────────────────────
              if (naba.nextActions.isNotEmpty) ...[
                _SectionCard(
                  title: NabaStrings.sectionNextActions,
                  icon: Icons.checklist_rounded,
                  iconBg: AppColors.navy.withValues(alpha: 0.1),
                  iconColor: AppColors.navy,
                  child: _NextActionsTimeline(actions: naba.nextActions),
                ),
                const SizedBox(height: 12),
              ],

              // ── Clinical findings ─────────────────────────────────────
              if (naba.clinicalFindings.isNotEmpty) ...[
                _SectionCard(
                  title: NabaStrings.sectionFindings,
                  icon: Icons.biotech_rounded,
                  iconBg: AppColors.aiSurfaceStart,
                  iconColor: AppColors.aiPurple,
                  child:
                      _ClinicalFindingsCards(findings: naba.clinicalFindings),
                ),
                const SizedBox(height: 12),
              ],

              // ── Counselling ───────────────────────────────────────────
              if (naba.counselling.isNotEmpty) ...[
                if (widget.primaryProgramme == Programme.ncd)
                  Card(
                    child: ExpansionTile(
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.tagTealSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.chat_bubble_outline_rounded,
                            color: AppColors.tagTealText, size: 18),
                      ),
                      title: Text(NabaStrings.sectionCounselling,
                          style: Theme.of(context).textTheme.titleSmall),
                      subtitle: const Text('Tap to expand'),
                      initiallyExpanded: false,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _DotList(
                            items: naba.counselling,
                            dotColor: AppColors.tagTealText,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _SectionCard(
                    title: NabaStrings.sectionCounselling,
                    icon: Icons.chat_bubble_outline_rounded,
                    iconBg: AppColors.tagTealSurface,
                    iconColor: AppColors.tagTealText,
                    child: _DotList(
                      items: naba.counselling,
                      dotColor: AppColors.tagTealText,
                    ),
                  ),
                const SizedBox(height: 12),
              ],

              // ── Medication advice ─────────────────────────────────────
              if (naba.medicationAdvice.isNotEmpty) ...[
                _SectionCard(
                  title: NabaStrings.sectionMedication,
                  icon: Icons.medication_liquid_rounded,
                  iconBg: AppColors.tagBlueSurface,
                  iconColor: AppColors.tagBlueText,
                  child: _DotList(
                    items: naba.medicationAdvice,
                    dotColor: AppColors.tagBlueText,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Follow-up ─────────────────────────────────────────────
              if (naba.followUp.isNotEmpty) ...[
                _SectionCard(
                  title: NabaStrings.sectionFollowUp,
                  icon: Icons.event_available_rounded,
                  iconBg: AppColors.followUpIconBg,
                  iconColor: AppColors.followUpIconFg,
                  child: _FollowUpRows(items: naba.followUp),
                ),
                const SizedBox(height: 12),
              ],

              // ── WhatsApp summary ──────────────────────────────────────
              if (naba.whatsappSummary != null) ...[
                _WhatsAppCard(
                  text: naba.whatsappSummary!,
                  patientPhone: _patientPhone,
                  onShared: () => _onAccepted(naba),
                ),
                const SizedBox(height: 12),
              ],

              // ── Proposal note ─────────────────────────────────────────
              const SizedBox(height: 4),
              Center(
                child: Text(
                  NabaStrings.proposalNote,
                  style: AppTextStyles.subText.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // ── CTA bar at scroll bottom ──────────────────────────
              const SizedBox(height: 12),
              _BottomCtaBar(
                naba: naba,
                accepted: _accepted,
                headerColor: headerColor,
                referral: referral,
                primaryProgramme: widget.primaryProgramme,
                patientLabel: widget.patientLabel,
                memberId: widget.memberId,
                patientPhone: _patientPhone,
                returnPath: _returnPath,
                onAccepted: () => _onAccepted(naba),
              ),
            ],
          ),
        );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _FallbackNoticeBanner extends StatelessWidget {
  const _FallbackNoticeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFF57F17)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              NabaStrings.fallbackNotice,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF4E342E),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.color, required this.height});
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    required this.programme,
    required this.headerColor,
  });
  final Programme programme;
  final Color headerColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 550),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.statusSuccessSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 28,
                color: AppColors.statusSuccess,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            VisitCompleteStrings.saved,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          if (programme != Programme.unknown) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: headerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                programme.name.toUpperCase(),
                style: AppTextStyles.scorePill.copyWith(
                  color: headerColor,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DangerSignsAlert extends StatelessWidget {
  const _DangerSignsAlert({required this.signs});
  final List<String> signs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.statusCriticalSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border:
            Border.all(color: AppColors.statusCriticalBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.statusCritical,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppRadius.card),
                topRight: Radius.circular(AppRadius.card),
              ),
            ),
            child: Row(
              children: const [
                Icon(Icons.warning_rounded, size: 17, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  NabaStrings.sectionDangerSigns,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: signs
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 5),
                            child: Icon(
                              Icons.circle,
                              size: 7,
                              color: AppColors.statusCritical,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.statusCriticalText,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.text,
    this.label,
  });
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String text;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(
                    label!,
                    style: AppTextStyles.scorePill.copyWith(
                      color: iconColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  text,
                  style: AppTextStyles.body.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.body,
    required this.headerColor,
    required this.confidence,
  });
  final String title;
  final String body;
  final Color headerColor;
  final double confidence;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Programme-coloured header strip
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl, vertical: AppSpacing.xl),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.card),
                topRight: Radius.circular(AppRadius.card),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          // Summary body
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, AppSpacing.xxl, AppSpacing.xxxl, AppSpacing.lg),
            child: Text(
              body,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.55,
              ),
            ),
          ),
          // Confidence footer
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, 0, AppSpacing.xxxl, AppSpacing.xl),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 12,
                  color: AppColors.aiPurple.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  'AI confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                  style: AppTextStyles.subText.copyWith(letterSpacing: 0.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.listItem,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadius.rxIcon),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _NextActionsTimeline extends StatelessWidget {
  const _NextActionsTimeline({required this.actions});
  final List<NabaNextAction> actions;

  static const _urgencyFg = {
    'Now': AppColors.statusCritical,
    'Today': AppColors.slaDueSoonText,
    'This week': AppColors.navy,
  };
  static const _urgencyBg = {
    'Now': AppColors.statusCriticalSurface,
    'Today': AppColors.statusWarningSurface,
    'This week': AppColors.childSurface,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(actions.length, (i) {
        final a = actions[i];
        final fgColor =
            _urgencyFg[a.urgency] ?? AppColors.textMuted;
        final bgColor =
            _urgencyBg[a.urgency] ?? AppColors.cardSurfaceMuted;
        final isLast = i == actions.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Spine: circle + line
            Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fgColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: fgColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '${a.priority}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: fgColor,
                    ),
                  ),
                ),
                if (!isLast)
                  Container(width: 1.5, height: 16, color: AppColors.border),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.action,
                      style: AppTextStyles.body.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        a.urgency.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: fgColor,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _ClinicalFindingsCards extends StatelessWidget {
  const _ClinicalFindingsCards({required this.findings});
  final List<NabaClinicalFinding> findings;

  Color _severityColor(String s) => switch (s) {
        'High' => AppColors.statusCritical,
        'Medium' => AppColors.slaDueSoonText,
        _ => AppColors.statusSuccess,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: findings
          .map((f) {
            final sc = _severityColor(f.severity);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardSurfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.rxIcon),
                  border: Border(
                    left: BorderSide(color: sc, width: 3.5),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            f.finding,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.flag),
                          ),
                          child: Text(
                            f.severity.toUpperCase(),
                            style: AppTextStyles.microTag.copyWith(
                              color: sc,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      f.reason,
                      style: AppTextStyles.vitalUnit.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          })
          .toList(),
    );
  }
}

class _DotList extends StatelessWidget {
  const _DotList({required this.items, required this.dotColor});
  final List<String> items;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyles.body.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FollowUpRows extends StatelessWidget {
  const _FollowUpRows({required this.items});
  final List<NabaFollowUpItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.followUpIconBg,
                      borderRadius:
                          BorderRadius.circular(AppRadius.rxIcon),
                    ),
                    child: const Icon(
                      Icons.event_rounded,
                      size: 16,
                      color: AppColors.followUpIconFg,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.activity,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.timeline,
                          style: AppTextStyles.vitalUnit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _WhatsAppCard extends StatefulWidget {
  const _WhatsAppCard({
    required this.text,
    this.patientPhone,
    this.onShared,
  });
  final String text;
  // Pre-loaded from MemberDao; pre-fills recipient in SMS and WhatsApp.
  final String? patientPhone;
  // Called when the user returns to the app after launching SMS or WhatsApp.
  final VoidCallback? onShared;

  @override
  State<_WhatsAppCard> createState() => _WhatsAppCardState();
}

class _WhatsAppCardState extends State<_WhatsAppCard>
    with WidgetsBindingObserver {
  bool _copied = false;
  // True after a launch so we fire onShared on the next app-resume event.
  bool _launchedExternal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _launchedExternal) {
      _launchedExternal = false;
      widget.onShared?.call();
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _sendSms(BuildContext context) async {
    final encoded = Uri.encodeComponent(widget.text);
    // sms:<phone>?body=<text> pre-fills both the recipient and message body.
    // When no phone is available, sms:?body=<text> still opens the composer.
    final phone = widget.patientPhone ?? '';
    final uri = Uri.parse('sms:$phone?body=$encoded');
    if (!await canLaunchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(NabaStrings.smsNotAvailable)),
        );
      }
      return;
    }
    await launchUrl(uri);
    _launchedExternal = true;
  }

  Future<void> _sendWhatsApp(BuildContext context) async {
    final encoded = Uri.encodeComponent(widget.text);
    // Normalise phone: WhatsApp expects E.164 without the leading +.
    // e.g. +8801700123456 → 8801700123456
    final rawPhone = widget.patientPhone?.replaceAll(RegExp(r'[^\d]'), '') ?? '';

    // whatsapp://send?phone=<e164>&text=<text> opens a chat to the number.
    // Omitting the phone param opens the share sheet to pick any contact.
    final phoneParam = rawPhone.isNotEmpty ? 'phone=$rawPhone&' : '';
    final nativeUri = Uri.parse('whatsapp://send?${phoneParam}text=$encoded');
    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri);
      _launchedExternal = true;
      return;
    }
    // Fallback: wa.me/<phone>?text=<text> (browser universal link).
    final waPath = rawPhone.isNotEmpty ? rawPhone : '';
    final webUri = Uri.parse('https://wa.me/$waPath?text=$encoded');
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      _launchedExternal = true;
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(NabaStrings.whatsAppNotInstalled)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.waBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.waBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xl, 8, 0),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.whatsapp,
                    borderRadius: BorderRadius.circular(AppRadius.waIcon),
                  ),
                  child: const Icon(
                    Icons.chat_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    NabaStrings.sectionWhatsApp,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.waHeader,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Copy button
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _copied
                      ? TextButton.icon(
                          key: const ValueKey('copied'),
                          onPressed: null,
                          icon: const Icon(Icons.check_rounded, size: 14),
                          label: const Text(
                            NabaStrings.whatsAppCopied,
                            style: TextStyle(fontSize: 11),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.statusSuccess,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : TextButton.icon(
                          key: const ValueKey('copy'),
                          onPressed: _copy,
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          label: const Text(
                            NabaStrings.copyWhatsApp,
                            style: TextStyle(fontSize: 11),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.waHeader,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.waBorder),
          // ── Message body ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl),
            child: Text(
              widget.text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.55,
                color: AppColors.textStrong,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.waBorder),
          // ── Share actions ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _sendSms(context),
                    icon: const Icon(Icons.sms_rounded, size: 16),
                    label: const Text(NabaStrings.sendViaSms),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      textStyle: AppTextStyles.chip,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _sendWhatsApp(context),
                    icon: const Icon(Icons.chat_rounded, size: 16),
                    label: const Text(NabaStrings.sendViaWhatsApp),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.whatsapp,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      textStyle: AppTextStyles.chip,
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

class _BottomCtaBar extends StatelessWidget {
  const _BottomCtaBar({
    required this.naba,
    required this.accepted,
    required this.headerColor,
    required this.referral,
    required this.primaryProgramme,
    required this.returnPath,
    required this.onAccepted,
    this.patientLabel,
    this.memberId,
    this.patientPhone,
  });
  final NabaResponse naba;
  final bool accepted;
  final Color headerColor;
  final bool referral;
  final Programme primaryProgramme;
  final String returnPath;
  final VoidCallback onAccepted;
  final String? patientLabel;
  final String? memberId;
  final String? patientPhone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 16),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: accepted ? null : onAccepted,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text(NabaStrings.acceptProposal),
                  style: FilledButton.styleFrom(
                    backgroundColor: headerColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        headerColor.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    textStyle: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              if (primaryProgramme == Programme.anc ||
                  primaryProgramme == Programme.pnc) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                      '/teleconsult',
                      extra: {
                        'patientLabel': patientLabel ?? '',
                        'patientId': memberId ?? '',
                      },
                    ),
                    icon: const Icon(Icons.video_call_rounded),
                    label:
                        const Text(VisitCompleteStrings.bookTeleconsult),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: headerColor,
                      side: BorderSide(
                          color: headerColor.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    ),
                  ),
                ),
              ],
              if (primaryProgramme == Programme.ncd) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('tel:');
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    icon: const Icon(Icons.phone_rounded),
                    label: const Text(VisitCompleteStrings.ncdCallDoctor),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.statusCritical,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/tasks'),
                    icon: const Icon(Icons.local_hospital_rounded),
                    label: const Text(VisitCompleteStrings.ncdBookHospital),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: headerColor,
                      side: BorderSide(
                          color: headerColor.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    ),
                  ),
                ),
              ],
              if ((primaryProgramme == Programme.imci ||
                      primaryProgramme == Programme.epi) &&
                  naba.whatsappSummary != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                      '/counselling',
                      extra: {
                        'patientLabel': patientLabel ?? '',
                        'patientId': memberId ?? '',
                        'whatsappMessage': naba.whatsappSummary,
                        'patientPhone': patientPhone,
                      },
                    ),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text(VisitCompleteStrings.sendCounsellingMessage),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: headerColor,
                      side: BorderSide(
                          color: headerColor.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    ),
                  ),
                ),
              ],
              if (referral) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/tasks'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.statusCritical,
                      side: const BorderSide(
                          color: AppColors.statusCriticalBorder),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    ),
                    child: const Text(VisitCompleteStrings.createReferral),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => context.go(returnPath),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted),
                child: const Text(VisitCompleteStrings.backToHome),
              ),
            ],
          ),
        ],
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Programme confirm bottom sheet — shown after Step 1 triage so the SK can
// see which pathways were matched by the rule engine and add / remove any
// before opening the assessment form.
// ─────────────────────────────────────────────────────────────────────────────

class _ProgrammeConfirmSheet extends StatefulWidget {
  const _ProgrammeConfirmSheet({
    required this.pathways,
    required this.onConfirm,
  });

  final List<ActivatedPathway> pathways;
  final void Function(Set<Programme>) onConfirm;

  @override
  State<_ProgrammeConfirmSheet> createState() =>
      _ProgrammeConfirmSheetState();
}

class _ProgrammeConfirmSheetState extends State<_ProgrammeConfirmSheet> {
  late Set<Programme> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.pathways.map((p) => p.programme).toSet();
  }

  String _readable(String s) {
    final lower = s.replaceAll('_', ' ').toLowerCase();
    if (lower.isEmpty) return lower;
    return lower[0].toUpperCase() + lower.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final matched = widget.pathways.map((p) => p.programme).toSet();
    final unmatched = Programme.kPilotProgrammes
        .where((p) => !matched.contains(p))
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Opening forms for',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Tap to add or remove care pathways',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          if (widget.pathways.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No pathways matched. Select one manually to continue.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ...widget.pathways.map((pathway) {
            final triggers = [
              ...pathway.triggerSymptoms,
              ...pathway.triggerConditions,
            ];
            return CheckboxListTile(
              value: _selected.contains(pathway.programme),
              onChanged: (val) => setState(() {
                if (val == true) {
                  _selected.add(pathway.programme);
                } else {
                  _selected.remove(pathway.programme);
                }
              }),
              title: Text(pathway.programme.displayName),
              subtitle: triggers.isNotEmpty
                  ? Text(
                      triggers.map(_readable).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textMuted),
                    )
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              contentPadding: EdgeInsets.zero,
            );
          }),
          if (unmatched.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'Add manually',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            ...unmatched.map((p) => CheckboxListTile(
                  value: _selected.contains(p),
                  onChanged: (val) => setState(() {
                    if (val == true) {
                      _selected.add(p);
                    } else {
                      _selected.remove(p);
                    }
                  }),
                  title: Text(
                    p.displayName,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                )),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      widget.onConfirm(_selected);
                    },
              child: const Text('Start visit'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Household member data holder (Step 3 strip) ───────────────────────────────

class _HouseholdMember {
  const _HouseholdMember({
    required this.patientId,
    required this.name,
    required this.primaryProgramme,
    required this.isCurrentPatient,
  });

  final String patientId;
  final String name;
  final Programme primaryProgramme;
  final bool isCurrentPatient;
}

// ── Household member strip ────────────────────────────────────────────────────

class _HouseholdMemberStrip extends StatelessWidget {
  const _HouseholdMemberStrip({
    required this.members,
    required this.onTapMember,
  });

  final List<_HouseholdMember> members;
  final void Function(String patientId) onTapMember;

  static (Color ring, Color labelColor, String visitLabel) _style(Programme p) {
    switch (p) {
      case Programme.anc:
        return (AppColors.ancText, AppColors.ancText, 'ANC visit');
      case Programme.pnc:
        return (AppColors.pncText, AppColors.pncText, 'PNC visit');
      case Programme.imci:
        return (AppColors.imciText, AppColors.imciText, 'Child visit');
      case Programme.ncd:
        return (AppColors.ncdText, AppColors.ncdText, 'BP check');
      case Programme.tb:
        return (AppColors.tbText, AppColors.tbText, 'TB check');
      case Programme.epi:
        return (const Color(0xFF1D4ED8), const Color(0xFF1D4ED8), 'Vaccines');
      case Programme.nutrition:
        return (const Color(0xFF15803D), const Color(0xFF15803D), 'Nutrition');
      default:
        return (AppColors.border, AppColors.textMuted, 'Scheduled');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_rounded, size: 16, color: AppColors.navy),
              const SizedBox(width: 6),
              Text(
                VisitFlowStrings.alsoCoverWhileHere,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: members.map((m) {
                if (m.isCurrentPatient) {
                  return _MemberAvatar(
                    member: m,
                    ringColor: AppColors.navy,
                    ringWidth: 3.0,
                    labelText: 'Viewing',
                    labelColor: AppColors.navy,
                    labelBold: true,
                    onTap: null,
                  );
                }
                final (ring, labelColor, visitLabel) = _style(m.primaryProgramme);
                return _MemberAvatar(
                  member: m,
                  ringColor: ring,
                  ringWidth: 1.5,
                  labelText: visitLabel,
                  labelColor: labelColor,
                  labelBold: false,
                  onTap: () => onTapMember(m.patientId),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.member,
    required this.ringColor,
    required this.ringWidth,
    required this.labelText,
    required this.labelColor,
    required this.labelBold,
    required this.onTap,
  });

  final _HouseholdMember member;
  final Color ringColor;
  final double ringWidth;
  final String labelText;
  final Color labelColor;
  final bool labelBold;
  final VoidCallback? onTap;

  static String _emoji(Programme p) {
    switch (p) {
      case Programme.anc:
      case Programme.pnc:
        return '🤰';
      case Programme.imci:
        return '👶';
      case Programme.ncd:
        return '🫀';
      case Programme.tb:
        return '🫁';
      case Programme.epi:
        return '💉';
      case Programme.nutrition:
        return '🥗';
      default:
        return '🏥';
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = member.name.split(' ').first;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: ringColor, width: ringWidth),
                ),
                child: Center(
                  child: Text(
                    _emoji(member.primaryProgramme),
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                firstName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: labelBold ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                labelText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: labelBold ? FontWeight.w600 : FontWeight.w400,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
