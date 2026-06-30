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
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/api/scribe_api_service.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/models/programme.dart';
import '../../core/theme/app_theme.dart';
import 'pathway/pathway_engine.dart';
import '../scribe/scribe_controller.dart';
import '../scribe/scribe_permission_service.dart';
import 'programme_selection/programme_selection_screen.dart';
import 'triage/symptom_picker_screen.dart';
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

  @override
  void initState() {
    super.initState();
    // Defer DB lookup to after first frame so context.read works safely.
    if (_patientName == null && widget.patientId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadPatientNameFromDb();
      });
    }
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
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_step > 0) {
          setState(() => _step -= 1);
        } else {
          await _exitFlow();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              _VisitFlowHeader(
                step: _step,
                patientName: _patientName,
                patientAge: _patientAge,
                householdId: widget.householdId,
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
            setState(() {
              _pathways = pathways;
              // Seed Step 2 selection with the rule-engine pathways so the SK
              // sees something even before the AI service responds.
              _confirmedProgrammes =
                  pathways.map((p) => p.programme).toSet();
              _step = 1;
            });
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
          patientLabel: widget.patientName ?? widget.patientId,
          primaryProgramme: _primaryProgramme,
          referralRecommended: _referralRecommended,
          memberId: widget.memberId,
          householdId: widget.householdId,
          origin: widget.origin ?? 'patients',
        );
    }
  }

  Future<bool?> _confirmExit() async {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
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
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
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
                      borderRadius: BorderRadius.circular(10),
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
                      borderRadius: BorderRadius.circular(10),
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
    this.primaryProgramme = Programme.unknown,
  });

  final int step; // 0..2
  final VoidCallback onBack;
  final String? patientName;
  final int? patientAge;
  final String? householdId;
  final Programme primaryProgramme;

  static const Color _headerColor = Color(0xFF1B2B5E); // Navy

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
    final stepLabels = <String>[
      '1. ${VisitFlowStrings.step1Title}',
      '2. ${VisitFlowStrings.step2Title}',
      '3. ${VisitFlowStrings.step3Title}',
    ];

    return Material(
      color: _headerColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: ← Back to visits
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
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
                          const SizedBox(height: 2),
                          Text(
                            _demographicsLine(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                              right: i == stepLabels.length - 1 ? 0 : 6,
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
                              right: i == stepLabels.length - 1 ? 0 : 6,
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

  String _demographicsLine() {
    final parts = <String>[];
    if (patientAge != null) parts.add('Age $patientAge');
    if (householdId != null && householdId!.isNotEmpty) {
      parts.add('House #$householdId');
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
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
      origin: widget.origin,
      onAdvance: widget.onAdvance,
    );
  }
}

/// Step 3 — AI recommendation screen. Fully folded here (no separate file):
///
/// - Programme-colored header.
/// - Success icon + "Assessment saved" headline.
/// - Optional referral warning card.
/// - Programme-aware action buttons (teleconsult / counselling / referral).
/// - "Back to home" button — returns to `/home` (or `/tasks` when origin
///   was the task list).
class _Step3AiReco extends StatelessWidget {
  const _Step3AiReco({
    super.key,
    required this.visitId,
    required this.primaryProgramme,
    required this.referralRecommended,
    required this.origin,
    this.patientLabel,
    this.memberId,
    this.householdId,
  });

  final String visitId;
  final String? patientLabel;
  final Programme primaryProgramme;
  final bool referralRecommended;
  final String? memberId;
  final String? householdId;
  final String origin;

  Color _headerColor(Programme p) => switch (p) {
        Programme.anc || Programme.pnc => AppColors.ancHeader,
        Programme.ncd => AppColors.ncdHeader,
        Programme.imci => AppColors.imciHeader,
        Programme.tb => AppColors.tbHeader,
        _ => AppColors.navy,
      };

  String get _returnPath => origin == 'dashboard' ? '/home' : '/tasks';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerColor = _headerColor(primaryProgramme);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.h6xl,
        vertical: AppSpacing.h6xl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.h8xl),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, value, child) =>
                Transform.scale(scale: value, child: child),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 80,
              color: AppColors.statusSuccess,
            ),
          ),
          const SizedBox(height: AppSpacing.h6xl),
          Text(
            VisitCompleteStrings.saved,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          if (primaryProgramme != Programme.unknown)
            Chip(
              label: Text(
                primaryProgramme.name.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              backgroundColor: headerColor,
              side: BorderSide.none,
            ),
          const SizedBox(height: AppSpacing.h6xl),
          if (referralRecommended) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              decoration: BoxDecoration(
                color: AppColors.statusCriticalSurface,
                borderRadius: BorderRadius.circular(AppRadius.patRow),
                border: Border.all(color: AppColors.statusCriticalBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.statusCritical,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      VisitCompleteStrings.referralWarning,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.statusCriticalText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.h8xl),
          ],
          const SizedBox(height: AppSpacing.h8xl),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (primaryProgramme == Programme.anc ||
                  primaryProgramme == Programme.pnc) ...[
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/teleconsult',
                    extra: {
                      'patientLabel': patientLabel ?? '',
                      'patientId': memberId ?? '',
                    },
                  ),
                  icon: const Icon(Icons.video_call_rounded),
                  label: const Text(VisitCompleteStrings.bookTeleconsult),
                  style: FilledButton.styleFrom(
                    backgroundColor: headerColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              if (primaryProgramme == Programme.epi ||
                  primaryProgramme == Programme.imci) ...[
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/counselling',
                    extra: {
                      'patientLabel': patientLabel ?? '',
                      'patientId': memberId ?? '',
                    },
                  ),
                  icon: const Icon(Icons.health_and_safety_rounded),
                  label: const Text(VisitCompleteStrings.sendCounsellingMessage),
                  style: FilledButton.styleFrom(
                    backgroundColor: headerColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              if (referralRecommended) ...[
                OutlinedButton(
                  onPressed: () => context.go('/tasks'),
                  child: const Text(VisitCompleteStrings.createReferral),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              TextButton(
                onPressed: () => context.go(_returnPath),
                child: const Text(VisitCompleteStrings.backToHome),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
