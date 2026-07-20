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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/scribe_api_service.dart';
import '../../core/clinical/referral_evaluator.dart';
import '../../core/constants/app_strings.dart';
import 'models/anc_assessment.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/db/pregnancy_snapshot_dao.dart';
import '../../core/models/programme.dart';
import '../../core/theme/app_theme.dart';
import 'naba/naba_models.dart';
import 'naba/naba_repository.dart';
import 'pathway/pathway_engine.dart';
import '../patient/followup_call_service.dart';
import '../scribe/scribe_controller.dart';
import '../scribe/scribe_permission_service.dart';
import 'immunisation/immunisation_timeline_screen.dart';
import 'programme_selection/programme_selection_screen.dart';
import 'triage/symptom_picker_screen.dart';
import 'visit_flow_header.dart';
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
    this.initialStep = 0,
    this.seedProgrammes = const <Programme>{},
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

  /// Step to start the flow at. Use 1 when the caller already captured
  /// symptom selection (e.g. [NewPatientVisitScreen]) so the SK goes straight
  /// to programme recommendation + clinical form.
  final int initialStep;

  /// Programmes pre-confirmed by the caller — seeded into [_confirmedProgrammes]
  /// so [_Step2ProgrammesThenForm] can pre-select without step 0.
  final Set<Programme> seedProgrammes;

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

  /// Resolved householdMemberLocalId — caller-supplied wins; falls back to
  /// parsing memberId as int (works when server issues numeric member IDs
  /// like "823260"). Android uses this numeric ID as `referenceId` in the
  /// offline-sync payload.
  int get _householdMemberLocalId =>
      widget.householdMemberLocalId ??
      int.tryParse(widget.memberId ?? '') ??
      0;

  /// Current step index — 0..2.
  late int _step =
      widget.debugInitialStep?.clamp(0, _totalSteps - 1) ??
      widget.initialStep.clamp(0, _totalSteps - 1);

  /// Patient name resolved from constructor or, as a fallback, looked up
  /// from the local DB via [PatientDao]. The constructor value wins —
  /// the lookup only fires when the caller did not supply a name.
  late String? _patientName = widget.patientName;
  late int? _patientAge = widget.patientAge;
  String? _patientDob;

  /// Postpartum status — seeded from constructor; DB lookup fills in the
  /// weeks value from [PregnancySnapshotDao] when not supplied by caller.
  late bool _isPostpartum = widget.isPostpartum;
  late final int? _postpartumWeeks = widget.postpartumWeeks;

  /// Gestational weeks resolved from the pregnancy snapshot when the caller
  /// did not supply it via the constructor.  The snapshot lookup always runs
  /// in [initState] so that Step 3's gestational-age card always has data.
  int? _resolvedGestationalWeeks;

  /// Raw LMP epoch-ms from the snapshot — used by [_GestationalAgeCard] so it
  /// can display the actual recorded date rather than a back-calculated one.
  int? _resolvedLmpMs;

  /// Raw EDD epoch-ms from the snapshot.
  int? _resolvedEddMs;

  /// Returns the best available gestational week count: constructor value
  /// first, then snapshot-resolved value.
  int? get _effectiveGestationalWeeks =>
      widget.gestationalWeeks ?? _resolvedGestationalWeeks;

  @override
  void initState() {
    super.initState();
    debugPrint('[_VisitFlowState] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always load — even when patientName is supplied we still need DOB + age
      // for the smart age label (months for infants). ??-guards inside prevent
      // overwriting values already provided by the caller.
      if (widget.patientId.isNotEmpty) {
        _loadPatientNameFromDb();
      }
      if (!_isPostpartum && widget.patientId.isNotEmpty) {
        _loadPostpartumFromDb();
      }
      // Always load snapshot regardless of whether gestationalWeeks was
      // passed via navigation — ensures the card shows on all entry paths.
      if (widget.patientId.isNotEmpty) {
        _loadPregnancySnapshotFromDb();
      }
    });
  }

  @override
  void dispose() {
    _step1Scribe?.dispose();
    super.dispose();
  }

  Future<void> _loadPatientNameFromDb() async {
    debugPrint('[_VisitFlowState] _loadPatientNameFromDb');
    try {
      final dao = context.read<PatientDao>();
      final p = await dao.byId(widget.patientId);
      if (!mounted || p == null) return;
      setState(() {
        _patientName = _patientName ?? p.name;
        _patientAge = _patientAge ?? p.age;
        _patientDob = _patientDob ?? p.dob;
      });
    } catch (e) {
      debugPrint('[VisitFlow] patient lookup failed: $e');
    }
  }

  Future<void> _loadPostpartumFromDb() async {
    debugPrint('[_VisitFlowState] _loadPostpartumFromDb');
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

  Future<void> _loadPregnancySnapshotFromDb() async {
    debugPrint('[_VisitFlowState] _loadPregnancySnapshotFromDb');
    try {
      final dao = context.read<PregnancySnapshotDao>();
      var snap = await dao.byPatient(widget.patientId);
      // Sync sometimes keys the row by household-member id when the FHIR
      // patient map was incomplete — fall back to memberId.
      final memberId = widget.memberId;
      if ((snap?.lmpDate == null && snap?.eddDate == null) &&
          memberId != null &&
          memberId.isNotEmpty &&
          memberId != widget.patientId) {
        final byMember = await dao.byPatient(memberId);
        if (byMember?.lmpDate != null || byMember?.eddDate != null) {
          snap = byMember;
        }
      }
      if (!mounted || snap == null) return;

      DateTime? lmp;
      DateTime? edd;
      if (snap.lmpDate != null) {
        lmp = DateTime.fromMillisecondsSinceEpoch(snap.lmpDate!);
      }
      if (snap.eddDate != null) {
        edd = DateTime.fromMillisecondsSinceEpoch(snap.eddDate!);
        // Derive LMP from EDD if not directly stored.
        lmp ??= edd.subtract(const Duration(days: 280));
      } else if (lmp != null) {
        edd = lmp.add(const Duration(days: 280));
      }

      final weeks =
          lmp != null ? DateTime.now().difference(lmp).inDays ~/ 7 : null;

      setState(() {
        if (weeks != null && weeks > 0) {
          _resolvedGestationalWeeks = weeks;
        }
        _resolvedLmpMs = lmp?.millisecondsSinceEpoch;
        _resolvedEddMs = edd?.millisecondsSinceEpoch;
      });
    } catch (e) {
      debugPrint('[VisitFlow] pregnancy snapshot lookup failed: $e');
    }
  }

  /// Pathways activated in Step 1 (rule engine), passed through to Step 3 if
  /// the SK accepts the AI's programme set verbatim. Kept for back-compat
  /// with the existing form composer.
  List<ActivatedPathway> _pathways = const <ActivatedPathway>[];

  /// Symptoms the SK confirmed in Step 1. Used to build the Step 2
  /// programme-recommendation request payload.
  Set<String> _confirmedSymptoms = const <String>{};

  /// Subset of [_confirmedSymptoms] that were pre-selected by the AI Scribe.
  Set<String> _aiPickedSymptoms = const <String>{};

  /// Sickness duration the SK picked in Step 1 ('1', '2-3', '4+').
  String? _sicknessDuration;

  /// Free-text "other symptoms" the SK typed in Step 1.
  String? _otherSymptoms;

  /// Programmes the SK confirmed in Step 2 — drives Step 3 form composition.
  late Set<Programme> _confirmedProgrammes =
      widget.seedProgrammes.isNotEmpty ? {...widget.seedProgrammes} : const <Programme>{};

  /// True once Step 1's service grid reported an explicit selection (adult
  /// visits). Prevents the empty-set fallback from resurrecting pathway NCD
  /// after the SK deselected every programme.
  bool _programmesExplicitlyChosen = false;

  /// True when the SK confirmed a delivery visit in Step 1. Gates whether
  /// the pregnancyOutcome form sections are included in Step 2.
  bool _isDeliveryVisit = false;

  /// Live programmes from Step 1 service card selection — drives header badge
  /// before the SK advances. Updated on every card toggle via [onProgrammesLive].
  Set<Programme> _step1LiveProgrammes = {};

  /// Set when Step 3 completes — handed to Step 4 for the recommendation card.
  Programme _primaryProgramme = Programme.unknown;
  bool _referralRecommended = false;
  List<String> _referredReasons = const [];
  String? _referralFacility;

  /// True once triage (Step 1) has been submitted. Blocks back-navigation to
  /// Step 1 from Step 2+ — re-entering triage would create a duplicate assessment.
  ///
  /// Initialised to true when [widget.initialStep] > 0 (e.g. flows launched
  /// from NewPatientVisitScreen that already captured symptoms on a separate
  /// screen). This prevents back-navigation from landing on an empty step 0.
  late bool _triageSubmitted = widget.initialStep > 0;

  /// AI Scribe controller for step 0 (symptom picker). Owned here so the
  /// controller — and any in-progress or completed transcript — survives
  /// step transitions instead of being discarded when the step-0 widget is
  /// replaced in the widget tree.
  ScribeController? _step1Scribe;

  /// Smart age label: months for under-2, years otherwise.
  /// Falls back to DOB when age-in-years is null (common for infants).
  String? get _ageDisplay {
    final dob = _patientDob;
    if (dob != null && dob.isNotEmpty) {
      try {
        final birth = DateTime.parse(dob);
        final now = DateTime.now();
        final months = (now.year - birth.year) * 12 +
            (now.month - birth.month) -
            (now.day < birth.day ? 1 : 0);
        if (months < 24) {
          return '$months month${months == 1 ? '' : 's'}';
        }
        final years = months ~/ 12;
        return '$years yr${years == 1 ? '' : 's'}';
      } catch (_) {}
    }
    final age = _patientAge;
    if (age == null) return null;
    if (age < 2) return '< 2 yrs';
    return '$age yrs';
  }

  /// True when the patient is under-5 or confirmed programmes contain EPI/IMCI.
  /// Age-based detection handles the no-symptoms case (no pathways activated
  /// → _confirmedProgrammes empty) so the vaccination path still fires for
  /// children who have no complaints on this visit.
  bool get _isChildVisit =>
      _confirmedProgrammes.any(
        (p) => p == Programme.epi || p == Programme.imci,
      ) ||
      // patientAge is in years; under-5 always routes to vaccination step
      // even when no symptoms were selected (no pathways → empty _confirmedProgrammes).
      (_patientAge != null && _patientAge! < 5);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_step > 1 || (_step == 1 && !_triageSubmitted)) {
          setState(() => _step -= 1);
        } else {
          await _exitFlow();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: VisitFlowHeader.statusBarStyle,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                VisitFlowHeader(
                  step: _step,
                  patientId: widget.patientId,
                  patientName: _patientName,
                  ageDisplay: _ageDisplay,
                  householdId: widget.householdId,
                  patientGender: widget.patientGender,
                  primaryProgramme: _pathways.isNotEmpty
                      ? _pathways.first.programme
                      : _primaryProgramme,
                  activeFormTypes: _step == 0
                      ? _step1LiveProgrammes.map((p) => p.name).toList()
                      : _confirmedProgrammes.map((p) => p.name).toList(),
                  onBack: () {
                    if (_step > 1 || (_step == 1 && !_triageSubmitted)) {
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
        _step1Scribe ??= ScribeController(
          api: context.read<ScribeApiService>(),
          permissionService: ScribePermissionService(),
        );
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
          scribeController: _step1Scribe!,
          onSymptomsConfirmed: (symptoms, duration, other, aiPicked) {
            // Captured before onAdvance fires (see SymptomPickerScreen).
            _confirmedSymptoms = symptoms;
            _aiPickedSymptoms = aiPicked;
            _sicknessDuration = duration;
            _otherSymptoms = other;
          },
          // Inline service selector fires this before onAdvance — use it to
          // override the pathway-derived set with the SK's explicit selection.
          onProgrammesSelected: (programmes) {
            _confirmedProgrammes = programmes;
            _programmesExplicitlyChosen = true;
          },
          onDeliverySelected: (isDelivery) {
            debugPrint('[DeliveryGate] onDeliverySelected: $isDelivery → _isDeliveryVisit=$isDelivery');
            _isDeliveryVisit = isDelivery;
          },
          onProgrammesLive: (programmes) {
            setState(() => _step1LiveProgrammes = programmes);
          },
          onAdvance: (pathways) {
            _pathways = pathways;
            // Fall back to pathway-derived set only when the service selector
            // was not shown (child visits — under-5 skips the grid).
            if (!_programmesExplicitlyChosen &&
                _confirmedProgrammes.isEmpty) {
              _confirmedProgrammes =
                  pathways.map((p) => p.programme).toSet();
            }
            setState(() {
              _step = 1;
              _triageSubmitted = true;
            });
          },
        );
      case 1:
        // For child visits (EPI / IMCI) Step 2 is the immunisation timeline,
        // not the standard checkup form. The 3-step progress header is unchanged.
        if (_isChildVisit) {
          return _Step2Vaccination(
            key: ValueKey('flow-step2-vacc-${widget.visitId}'),
            patientId: widget.patientId,
            patientName: widget.patientName,
            encounterId: widget.visitId,
            memberId: widget.memberId,
            householdMemberLocalId: _householdMemberLocalId,
            onAdvance: () {
              setState(() {
                _primaryProgramme = Programme.imci;
                // Ensure NABA and WhatsApp message generators see the IMCI
                // programme — vaccination step doesn't come through the
                // programme-selection path so _confirmedProgrammes may be
                // empty for under-5 patients with no symptoms.
                if (!_confirmedProgrammes.contains(Programme.imci)) {
                  _confirmedProgrammes = {
                    ..._confirmedProgrammes,
                    Programme.imci,
                  };
                }
                _referralRecommended = false;
                _step = 2;
              });
            },
          );
        }
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
          householdMemberLocalId: _householdMemberLocalId,
          patientAge: widget.patientAge,
          patientName: widget.patientName,
          patientGender: widget.patientGender,
          gestationalWeeks: _effectiveGestationalWeeks,
          lmpMs: _resolvedLmpMs,
          eddMs: _resolvedEddMs,
          isPostpartum: _isPostpartum,
          postpartumWeeks: _postpartumWeeks,
          confirmedSymptoms: _confirmedSymptoms,
          aiPickedSymptoms: _aiPickedSymptoms,
          sicknessDuration: _sicknessDuration,
          otherSymptoms: _otherSymptoms,
          seedProgrammes: _confirmedProgrammes,
          isDeliveryVisit: _isDeliveryVisit,
          origin: widget.origin,
          onAdvance: (programme, referral, reasons, facility) {
            debugPrint('[ReferralFacility] flow captured — facility=$facility referral=$referral');
            setState(() {
              _primaryProgramme = programme;
              _referralRecommended = referral;
              _referredReasons = reasons;
              _referralFacility = facility;
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
          gestationalWeeks: _effectiveGestationalWeeks,
          lmpMs: _resolvedLmpMs,
          eddMs: _resolvedEddMs,
          confirmedSymptoms: _confirmedSymptoms,
          confirmedProgrammes: _confirmedProgrammes,
          primaryProgramme: _primaryProgramme,
          referralRecommended: _referralRecommended,
          referredReasons: _referredReasons,
          referralFacility: _referralFacility,
          memberId: widget.memberId,
          householdId: widget.householdId,
          origin: widget.origin ?? 'patients',
        );
    }
  }

  Future<bool?> _confirmExit() {
    debugPrint('[_VisitFlowState] _confirmExit');
    return showLeaveVisitDialog(context);
  }
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
                  child: Text(VisitFlowStrings.discardCancel),
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
                  child: Text(VisitFlowStrings.discardConfirmCta),
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
    required this.scribeController,
    this.memberId,
    this.householdId,
    this.patientAge,
    this.patientName,
    this.patientGender,
    this.origin,
    this.onProgrammesSelected,
    this.onProgrammesLive,
    this.onDeliverySelected,
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
    Set<String> aiPickedSymptoms,
  ) onSymptomsConfirmed;

  /// Controller owned by [_VisitFlowState] so the AI Scribe session and
  /// transcript survive step transitions (e.g. step 0 → 1 → back to 0).
  final ScribeController scribeController;

  /// Fired just before [onAdvance] with the SK-confirmed programme set from
  /// the inline eligible-services grid. Absent for child visits (under-5).
  final ValueChanged<Set<Programme>>? onProgrammesSelected;

  /// Fired on every service card toggle — drives the Step 1 header badge live.
  final ValueChanged<Set<Programme>>? onProgrammesLive;

  /// Fired just before [onAdvance] with whether the SK confirmed a delivery visit.
  final ValueChanged<bool>? onDeliverySelected;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScribeController>.value(
      value: scribeController,
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
        onProgrammesSelected: onProgrammesSelected,
        onProgrammesLive: onProgrammesLive,
        onDeliverySelected: onDeliverySelected,
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
    this.lmpMs,
    this.eddMs,
    this.pathwayNames,
    this.triageNotes,
    this.origin,
    this.enrolledProgrammes = const {},
    this.confirmedSymptoms = const [],
    this.aiPickedSymptoms = const {},
    this.isDeliveryVisit = false,
  });

  final String visitId;
  final String patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;
  final int? gestationalWeeks;
  final int? lmpMs;
  final int? eddMs;
  final List<String>? pathwayNames;
  final String? triageNotes;
  final String? origin;
  final bool isDeliveryVisit;
  /// Enrolled programmes from the patient record — used to order sections.
  final Set<Programme> enrolledProgrammes;
  /// Symptom codes selected in Step 1.
  final List<String> confirmedSymptoms;
  /// Subset of [confirmedSymptoms] pre-selected by AI Scribe.
  final Set<String> aiPickedSymptoms;
  final void Function(
    Programme primaryProgramme,
    bool referralRecommended,
    List<String> referredReasons,
    String? referralFacility,
  ) onAdvance;

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
      lmpMs: lmpMs,
      eddMs: eddMs,
      activatedPathways: pathwayNames,
      isDeliveryVisit: isDeliveryVisit,
      triageNotes: triageNotes,
      origin: origin,
      enrolledProgrammes: enrolledProgrammes,
      confirmedSymptoms: confirmedSymptoms,
      aiPickedSymptoms: aiPickedSymptoms,
      onAdvance: onAdvance,
    );
  }
}

/// Step 2 — vaccination step for child visits (EPI / IMCI).
///
/// Embeds [ImmunisationTimelineScreen] within the 3-step flow. When the SK
/// taps "Done → Continue Visit", [onAdvance] fires and the host advances to
/// Step 3 (AI recommendation + household followup). Standalone access to the
/// immunisation timeline (from the patient record) is unaffected.
class _Step2Vaccination extends StatefulWidget {
  const _Step2Vaccination({
    super.key,
    required this.patientId,
    required this.onAdvance,
    this.patientName,
    this.encounterId,
    this.memberId,
    this.householdMemberLocalId,
  });

  final String patientId;
  final String? patientName;
  final VoidCallback onAdvance;

  /// The visit encounter ID — forwarded to [ImmunisationTimelineScreen] so
  /// vaccine updates can be pushed to the backend via [ImmunisationRepository].
  final String? encounterId;
  final String? memberId;
  final int? householdMemberLocalId;

  @override
  State<_Step2Vaccination> createState() => _Step2VaccinationState();
}

class _Step2VaccinationState extends State<_Step2Vaccination> {
  String? _dob;
  bool _dobLoaded = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[_Step2VaccinationState] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDob());
  }

  Future<void> _loadDob() async {
    debugPrint('[_Step2VaccinationState] _loadDob');
    try {
      final dao = context.read<PatientDao>();
      final patient = await dao.byId(widget.patientId);
      if (!mounted) return;
      setState(() {
        _dob = patient?.dob;
        _dobLoaded = true;
      });
    } catch (e) {
      debugPrint('[Step2Vaccination] DOB lookup failed: $e');
      if (!mounted) return;
      setState(() => _dobLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_dobLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return ImmunisationTimelineScreen(
      patientId: widget.patientId,
      patientName: widget.patientName,
      dob: _dob,
      onVisitComplete: widget.onAdvance,
      encounterId: widget.encounterId,
      memberId: widget.memberId,
      householdMemberLocalId: widget.householdMemberLocalId,
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
    required this.aiPickedSymptoms,
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
    this.lmpMs,
    this.eddMs,
    this.isPostpartum = false,
    this.postpartumWeeks,
    this.isDeliveryVisit = false,
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
  final int? lmpMs;
  final int? eddMs;
  final bool isPostpartum;
  final int? postpartumWeeks;
  final bool isDeliveryVisit;
  final Set<String> confirmedSymptoms;
  /// Subset of [confirmedSymptoms] pre-selected by the AI Scribe.
  final Set<String> aiPickedSymptoms;
  final String? sicknessDuration;
  final String? otherSymptoms;
  final Set<Programme> seedProgrammes;
  final String? origin;
  final void Function(
    Programme primaryProgramme,
    bool referralRecommended,
    List<String> referredReasons,
    String? referralFacility,
  ) onAdvance;

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
    debugPrint('[_Step2ProgrammesThenFormState] initState');
    _selectedProgrammes = widget.seedProgrammes;
    // Delivery visit always needs PNC in the seed so the form opens
    // pregnancy-outcome even if Step 1 live-set was emptied by a rebuild.
    if (widget.isDeliveryVisit) {
      _selectedProgrammes = {..._selectedProgrammes, Programme.pnc};
    }
    debugPrint(
      '[DeliveryGate] Step2 seed programmes='
      '${_selectedProgrammes.map((p) => p.name).join(', ')} '
      'isDeliveryVisit=${widget.isDeliveryVisit}',
    );
    // AI programme recommendation disabled — use rule-based PathwayEngine result directly.
    _phase = _Step2Phase.form;
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    final dao = context.read<PatientProgrammesDao>();
    try {
      final progs = await dao.programmesFor(widget.patientId);
      if (!mounted) return;

      final hasAnc = _selectedProgrammes.contains(Programme.anc);

      // Task 3 — PW once-only: drop PW silently if already enrolled.
      // Do not show a dialog — ANC/other programmes in the same visit should
      // continue without interrupting the SK.
      if (_selectedProgrammes.contains(Programme.pw) &&
          progs.contains(Programme.pw)) {
        debugPrint(
          '[Step2][PayloadDebug] PW block: patient=${widget.patientId} '
          'already enrolled in PW — re-enrollment skipped (no dialog).',
        );
        _selectedProgrammes =
            _selectedProgrammes.difference({Programme.pw});
        if (_selectedProgrammes.isEmpty) {
          if (!mounted) return;
          Navigator.of(context).pop();
          return;
        }
      }

      // Task 2 — Block ANC when patient is postpartum (PNC/Delivery Outcome
      // completed). ANC must not be started after delivery.
      if (hasAnc && widget.isPostpartum) {
        await _showAncBlockedDialog(
          context,
          AppStrings.ancBlockedPostpartumTitle,
          AppStrings.ancBlockedPostpartumMessage,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      // Task 1 — Block duplicate ANC on same calendar day.
      if (hasAnc) {
        final assessmentDao = context.read<LocalAssessmentDao>();
        final hasTodayAnc = await assessmentDao
            .hasAncAssessmentTodayForPatient(widget.patientId);
        if (!mounted) return;
        if (hasTodayAnc) {
          await _showAncBlockedDialog(
            context,
            AppStrings.ancBlockedDuplicateTitle,
            AppStrings.ancBlockedDuplicateMessage,
          );
          if (!mounted) return;
          Navigator.of(context).pop();
          return;
        }
      }

      // Task 5 — When ANC is selected for a first-time pregnancy (no LMP
      // snapshot yet) and PW was not explicitly chosen, auto-include PW so the
      // pregnancy profile form is submitted alongside the ANC visit.
      if (hasAnc && !_selectedProgrammes.contains(Programme.pw)) {
        final snapshotDao = context.read<PregnancySnapshotDao>();
        final snapshot = await snapshotDao.byPatient(widget.patientId);
        if (!mounted) return;
        if (snapshot?.lmpDate == null) {
          _selectedProgrammes = {..._selectedProgrammes, Programme.pw};
        }
      }

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

  Future<void> _showAncBlockedDialog(
    BuildContext ctx,
    String title,
    String message,
  ) {
    return showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
      lmpMs: widget.lmpMs,
      eddMs: widget.eddMs,
      pathwayNames: _selectedProgrammes
          .where((p) => p != Programme.unknown)
          .map((p) => p.name)
          .toList(),
      isDeliveryVisit: widget.isDeliveryVisit,
      triageNotes: widget.otherSymptoms,
      origin: widget.origin,
      enrolledProgrammes: _currentProgrammes,
      confirmedSymptoms: widget.confirmedSymptoms.toList(),
      aiPickedSymptoms: widget.aiPickedSymptoms,
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
    required this.referredReasons,
    required this.origin,
    required this.confirmedSymptoms,
    required this.confirmedProgrammes,
    this.patientLabel,
    this.patientAge,
    this.patientGender,
    this.gestationalWeeks,
    this.lmpMs,
    this.eddMs,
    this.memberId,
    this.householdId,
    this.referralFacility,
  });

  final String visitId;
  final String patientId;
  final String? patientLabel;
  final int? patientAge;
  final String? patientGender;
  final int? gestationalWeeks;
  /// LMP epoch-ms from the snapshot — overrides back-calculation in the card.
  final int? lmpMs;
  /// EDD epoch-ms from the snapshot — overrides back-calculation in the card.
  final int? eddMs;
  final Set<String> confirmedSymptoms;
  final Set<Programme> confirmedProgrammes;
  final Programme primaryProgramme;
  final bool referralRecommended;
  final List<String> referredReasons;
  final String? memberId;
  final String? householdId;
  final String origin;
  final String? referralFacility;

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
  NabaVitalSnapshot? _loadedVitals;
  List<NabaLabResult> _loadedLabs = [];
  DateTime? _selectedFollowUpDate;

  Color _headerColor(Programme p) => switch (p) {
        Programme.anc || Programme.pnc => AppColors.ancHeader,
        Programme.ncd => AppColors.ncdHeader,
        Programme.imci => AppColors.imciHeader,
        Programme.tb => AppColors.tbHeader,
        _ => AppColors.navy,
      };

  // Maps the entry point the SK launched this visit from back to the
  // screen they should land on after accepting Step 3 — 'household' and
  // 'patient' return to the specific record instead of the generic Tasks
  // list, which previously swallowed every origin but 'dashboard'.
  String get _returnPath {
    switch (widget.origin) {
      case 'dashboard':
        return '/home';
      case 'household':
        final householdId = widget.householdId;
        return householdId != null && householdId.isNotEmpty
            ? '/patients/household/$householdId'
            : '/home';
      case 'patient':
        return '/patients/${widget.patientId}';
      case 'tasks':
      default:
        return '/tasks';
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[_Step3AiRecoState] initState');
    _future = _fetchNaba();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _loadPatientPhone();
    _loadHouseholdMembers();
  }

  Future<void> _loadPatientPhone() async {
    debugPrint('[_Step3AiRecoState] _loadPatientPhone');
    final member = await context
        .read<MemberDao>()
        .getByPatientId(widget.patientId);
    final phone = member?.phone;
    if (mounted && phone != null && phone.isNotEmpty) {
      setState(() => _patientPhone = phone);
    }
  }

  Future<void> _loadHouseholdMembers() async {
    debugPrint('[_Step3AiRecoState] _loadHouseholdMembers');
    String? hid = widget.householdId;

    // patients.household_id is sparsely populated; members.household_id is
    // always written by sync — try that first as fallback.
    if ((hid == null || hid.isEmpty) && mounted) {
      try {
        final patient = await context.read<PatientDao>().byId(widget.patientId);
        hid = patient?.householdId;
      } on Object catch (_) {}
    }
    if ((hid == null || hid.isEmpty) && mounted) {
      try {
        final member =
            await context.read<MemberDao>().getByPatientId(widget.patientId);
        hid = member?.householdId;
      } on Object catch (_) {}
    }
    if (hid == null || hid.isEmpty || !mounted) return;

    final memberDao = context.read<MemberDao>();
    final progDao = context.read<PatientProgrammesDao>();

    // members table is the authoritative household membership source; querying
    // patients table for household_id misses members whose patient row wasn't
    // synced with household_id set.
    final entities = await memberDao.getByHouseholdId(hid);
    final active = entities.where((m) => m.isActive).toList();
    final ids = active
        .map((m) => m.patientId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    final progMap = await progDao.programmesForMany(ids);

    if (!mounted) return;
    final members = active.map((m) {
      final pid = m.patientId ?? '';
      if (pid.isEmpty) return null;
      final progs = progMap[pid] ?? {};
      final primary = progs.isNotEmpty ? progs.first : Programme.unknown;
      return _HouseholdMember(
        patientId: pid,
        name: m.name ?? '—',
        primaryProgramme: primary,
        isCurrentPatient: pid == widget.patientId,
      );
    }).whereType<_HouseholdMember>().toList()
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
    debugPrint('[_Step3AiRecoState] dispose');
    super.dispose();
  }

  Future<NabaResponse> _fetchNaba() async {
    debugPrint('[_Step3AiRecoState] _fetchNaba');
    final apiClient = context.read<ApiClient>(); // read before any await
    await _loadVitalsAndLabs();
    try {
      final repo = NabaRepository(apiClient);
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
        isPregnant: (widget.gestationalWeeks != null || widget.lmpMs != null) &&
            (widget.confirmedProgrammes.contains(Programme.anc) ||
             widget.confirmedProgrammes.contains(Programme.pnc)),
        manuallySelectedSymptoms: widget.confirmedSymptoms.toList(),
        currentVitals: _loadedVitals,
        labResults: _loadedLabs,
      );
      final ai = await repo.generate(req);
      // Backfill empty fields from rule-based fallback so the UI always
      // has counselling and follow-up content even when AI data is sparse.
      if (ai.counselling.isEmpty || ai.followUp.isEmpty) {
        final fallback = _ruleBasedNaba();
        return NabaResponse(
          requestId: ai.requestId,
          modelVersion: ai.modelVersion,
          generatedAt: ai.generatedAt,
          rationale: ai.rationale,
          visitSummary: ai.visitSummary,
          clinicalFindings: ai.clinicalFindings,
          nextActions: ai.nextActions.isNotEmpty ? ai.nextActions : fallback.nextActions,
          dangerSigns: ai.dangerSigns.isNotEmpty ? ai.dangerSigns : fallback.dangerSigns,
          followUp: ai.followUp.isNotEmpty ? ai.followUp : fallback.followUp,
          counselling: ai.counselling.isNotEmpty ? ai.counselling : fallback.counselling,
          familyCounselling: ai.familyCounselling,
          medicationAdvice: ai.medicationAdvice,
          whatsappSummary: ai.whatsappSummary ?? fallback.whatsappSummary,
          doctorHandover: ai.doctorHandover,
          referralRecommendation: ai.referralRecommendation,
          contextTruncated: ai.contextTruncated,
        );
      }
      if (ai.whatsappSummary != null) return ai;
      return NabaResponse(
        requestId: ai.requestId,
        modelVersion: ai.modelVersion,
        generatedAt: ai.generatedAt,
        rationale: ai.rationale,
        visitSummary: ai.visitSummary,
        clinicalFindings: ai.clinicalFindings,
        nextActions: ai.nextActions,
        dangerSigns: ai.dangerSigns,
        followUp: ai.followUp,
        counselling: ai.counselling,
        familyCounselling: ai.familyCounselling,
        medicationAdvice: ai.medicationAdvice,
        whatsappSummary: _ruleBasedWhatsAppMessage(),
        doctorHandover: ai.doctorHandover,
        referralRecommendation: ai.referralRecommendation,
        contextTruncated: ai.contextTruncated,
      );
    } catch (e) {
      debugPrint('[NABA] AI failed — rule-based fallback: $e');
      return _ruleBasedNaba();
    }
  }

  Future<void> _loadVitalsAndLabs() async {
    debugPrint('[_Step3AiRecoState] _loadVitalsAndLabs');
    try {
      final dao = context.read<LocalAssessmentDao>(); // read before first await
      final assessments = await dao.getByPatientId(widget.patientId);
      if (assessments.isEmpty) return;

      final isPrimaryAnc = widget.primaryProgramme == Programme.anc ||
          widget.primaryProgramme == Programme.pnc;
      final targetType = isPrimaryAnc ? 'ANC' : 'NCD';

      LocalAssessmentEntity? target;
      for (final a in assessments.reversed) {
        if (a.assessmentType == targetType) {
          target = a;
          break;
        }
      }
      target ??= assessments.last;

      final data =
          jsonDecode(target.assessmentDetails) as Map<String, dynamic>;
      if (target.assessmentType == 'ANC') {
        _parseAncVitals(data);
      } else if (target.assessmentType == 'NCD') {
        _parseNcdVitals(data);
      }
    } catch (e) {
      debugPrint('[NABA] Assessment vitals load failed: $e');
    }
  }

  void _parseAncVitals(Map<String, dynamic> data) {
    final phys = data['medicalHistoryPhysicalExamination']
            as Map<String, dynamic>? ??
        {};
    final poc =
        data['pointOfCareInvestigations'] as Map<String, dynamic>? ?? {};

    _loadedVitals = NabaVitalSnapshot(
      bloodPressureSystolic: phys['bloodPressureSystolic'] as int?,
      bloodPressureDiastolic: phys['bloodPressureDiastolic'] as int?,
      weight: (phys['weight'] as num?)?.toDouble(),
      bmi: (phys['bmi'] as num?)?.toDouble(),
    );

    final labs = <NabaLabResult>[];
    final hb = poc['hemoglobin'];
    if (hb != null) {
      final v = (hb as num).toDouble();
      labs.add(NabaLabResult(
        name: 'Hemoglobin',
        value: v.toStringAsFixed(1),
        unit: 'g/dL',
        referenceRange: '≥11 g/dL',
        abnormal: v < 11,
      ));
    }
    final bsf = poc['bloodSugarFasting'];
    if (bsf != null) {
      final v = (bsf as num).toDouble();
      labs.add(NabaLabResult(
        name: 'Blood Glucose (Fasting)',
        value: v.toStringAsFixed(0),
        unit: 'mg/dL',
        referenceRange: '<100 mg/dL',
        abnormal: v >= 126,
      ));
    }
    final bsr = poc['bloodSugarRandom'];
    if (bsr != null) {
      final v = (bsr as num).toDouble();
      labs.add(NabaLabResult(
        name: 'Blood Glucose (Random)',
        value: v.toStringAsFixed(0),
        unit: 'mg/dL',
        referenceRange: '<140 mg/dL',
        abnormal: v >= 200,
      ));
    }
    _loadedLabs = labs;
  }

  void _parseNcdVitals(Map<String, dynamic> data) {
    final bp = data['bpLog'] as Map<String, dynamic>? ?? {};
    final glucose = data['glucoseLog'] as Map<String, dynamic>? ?? {};

    final avgSys = bp['avgSystolic'];
    final avgDia = bp['avgDiastolic'];

    _loadedVitals = NabaVitalSnapshot(
      bloodPressureSystolic:
          avgSys != null ? (avgSys as num).toInt() : null,
      bloodPressureDiastolic:
          avgDia != null ? (avgDia as num).toInt() : null,
      weight: (bp['weight'] as num?)?.toDouble(),
      temperature: (bp['temperature'] as num?)?.toDouble(),
      bmi: (bp['bmi'] as num?)?.toDouble(),
    );

    final labs = <NabaLabResult>[];
    final gv = glucose['glucoseValue'];
    if (gv != null) {
      final isFasting = glucose['glucoseType'] == 'fasting';
      final v = (gv as num).toDouble();
      labs.add(NabaLabResult(
        name: isFasting ? 'Blood Glucose (Fasting)' : 'Blood Glucose (Random)',
        value: v.toStringAsFixed(0),
        unit: glucose['glucoseUnit'] as String? ?? 'mg/dL',
        referenceRange: isFasting ? '<100 mg/dL' : '<140 mg/dL',
        abnormal: isFasting ? v >= 126 : v >= 200,
      ));
    }
    final hba1cRaw = glucose['hba1c'];
    if (hba1cRaw != null) {
      final v = (hba1cRaw as num).toDouble();
      labs.add(NabaLabResult(
        name: 'HbA1c',
        value: v.toStringAsFixed(1),
        unit: '%',
        referenceRange: '<6.5%',
        abnormal: v >= 6.5,
      ));
    }
    _loadedLabs = labs;
  }

  String _ancVitalsSummary() {
    final v = _loadedVitals;
    if (v == null) {
      return 'BP, weight, urine protein, and fetal movement assessed. Continuing routine ANC care per WHO guidelines.';
    }
    final bpPart = (v.bloodPressureSystolic != null && v.bloodPressureDiastolic != null)
        ? 'BP ${v.bloodPressureSystolic}/${v.bloodPressureDiastolic} mmHg'
        : 'BP assessed';
    final wtPart = v.weight != null ? ', weight ${v.weight!.toStringAsFixed(1)} kg' : '';
    final hb = _loadedLabs.firstWhere(
      (l) => l.name == 'Hemoglobin',
      orElse: () => const NabaLabResult(name: '', value: '', unit: ''),
    );
    final hbPart = hb.name.isNotEmpty
        ? ', Hb ${hb.value} g/dL${hb.abnormal ? " — low" : ""}'
        : '';
    final bpHigh = v.bloodPressureSystolic != null && v.bloodPressureSystolic! >= 140;
    final status = bpHigh ? 'BP elevated — monitor for pre-eclampsia.' : 'Vitals within expected range.';
    return '$bpPart$wtPart$hbPart. $status';
  }

  String _ncdVitalsSummary() {
    final v = _loadedVitals;
    if (v == null) {
      return 'Blood pressure and blood glucose reviewed. Continuing NCD management per Bangladesh guidelines.';
    }
    final bpPart = (v.bloodPressureSystolic != null && v.bloodPressureDiastolic != null)
        ? 'BP avg ${v.bloodPressureSystolic}/${v.bloodPressureDiastolic} mmHg'
        : 'BP assessed';
    final gl = _loadedLabs.isNotEmpty ? _loadedLabs.first : null;
    final glPart = gl != null ? ', glucose ${gl.value} ${gl.unit}${gl.abnormal ? " — elevated" : ""}' : '';
    final bpHigh = v.bloodPressureSystolic != null && v.bloodPressureSystolic! >= 140;
    final status = bpHigh ? 'BP above target — review medication and refer if persistent.' : 'BP within controlled range.';
    return '$bpPart$glPart. $status';
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
        timeline: 'In 2 weeks',
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
        summary: hasAnc
            ? _ancVitalsSummary()
            : hasNcd
                ? _ncdVitalsSummary()
                : hasPnc
                    ? 'Mother and neonate assessed — lochia, cord, and breastfeeding. Continuing post-natal care.'
                    : hasImci
                        ? 'Child assessed for fever, respiratory rate, and hydration. IMCI classification applied.'
                        : hasTb
                            ? 'TB treatment adherence reviewed. Continuing directly observed therapy (DOT).'
                            : 'Vital signs assessed. Routine care plan generated per clinical guidelines.',
      ),
      nextActions: actions,
      counselling: counselling,
      followUp: followUp,
      whatsappSummary: _ruleBasedWhatsAppMessage(),
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

  String _ruleBasedWhatsAppMessage() {
    final progs = widget.confirmedProgrammes;
    final hasAnc = progs.contains(Programme.anc);
    final hasNcd = progs.contains(Programme.ncd);
    final hasPnc = progs.contains(Programme.pnc);
    final hasImci = progs.contains(Programme.imci);
    final hasTb = progs.contains(Programme.tb);

    final buf = StringBuffer();
    buf.writeln('Hello! Your health worker visited you today.');

    if (hasAnc) {
      final gw = widget.gestationalWeeks;
      buf.writeln();
      buf.writeln('*Pregnancy (ANC) visit completed.*');
      if (gw != null) buf.writeln('Gestational age: $gw weeks.');
      buf.writeln();
      buf.writeln('Reminders:');
      buf.writeln('• Take iron-folic acid every day');
      buf.writeln('• Eat well: vegetables, fish, eggs, lentils');
      buf.writeln('• Sleep under a bednet every night');
      buf.writeln('• Plan delivery at a health facility');
      buf.writeln('• Go to facility immediately for: heavy bleeding, severe headache, blurred vision, no fetal movement, swollen hands/feet');
      buf.writeln();
      buf.writeln('*Next ANC visit: in 4 weeks.*');
    }

    if (hasNcd) {
      buf.writeln();
      buf.writeln('*BP/Diabetes (NCD) visit completed.*');
      buf.writeln();
      buf.writeln('Reminders:');
      buf.writeln('• Take all medicines every day — never skip');
      buf.writeln('• Reduce salt; avoid processed food');
      buf.writeln('• Walk 30 minutes daily');
      buf.writeln('• Avoid tobacco and alcohol');
      buf.writeln('• Go to facility immediately for: one-sided weakness, sudden severe headache, or chest pain');
      buf.writeln();
      buf.writeln('*Next visit: in 4 weeks.*');
    }

    if (hasPnc) {
      buf.writeln();
      buf.writeln('*Post-natal care (PNC) visit completed.*');
      buf.writeln();
      buf.writeln('Reminders:');
      buf.writeln('• Breastfeed exclusively for 6 months — no water or other food');
      buf.writeln('• Keep baby warm; keep cord stump clean and dry');
      buf.writeln('• Eat well to support breast milk');
      buf.writeln('• Seek care immediately for: heavy bleeding, fever, foul discharge, or baby not feeding');
      buf.writeln();
      buf.writeln('*Next PNC visit: in 7 days.*');
    }

    if (hasImci) {
      buf.writeln();
      buf.writeln('*Child health (IMCI) visit completed.*');
      buf.writeln();
      buf.writeln('Reminders:');
      buf.writeln('• Continue feeding normally during illness');
      buf.writeln('• Give ORS often if child has diarrhoea');
      buf.writeln('• Return immediately if child cannot drink, has convulsions, or is very sleepy');
      buf.writeln();
      buf.writeln('*Follow-up visit: in 2 days.*');
    }

    if (hasTb) {
      buf.writeln();
      buf.writeln('*TB treatment follow-up visit completed.*');
      buf.writeln();
      buf.writeln('Reminders:');
      buf.writeln('• Take TB medicines every day — stopping causes drug resistance');
      buf.writeln('• Cover mouth when coughing; keep rooms ventilated');
      buf.writeln('• All household members should be screened for TB');
      buf.writeln();
      buf.writeln('*Next TB check: in 2 weeks.*');
    }

    if (!hasAnc && !hasNcd && !hasPnc && !hasImci && !hasTb) {
      buf.writeln();
      buf.writeln('*Routine health visit completed.*');
      buf.writeln('Continue your medications and attend your next scheduled visit.');
      buf.writeln();
      buf.writeln('*Next visit: in 4 weeks.*');
    }

    if (widget.referralRecommended) {
      buf.writeln();
      buf.writeln('⚠️ *Please go to the Upazila Health Complex today for further care.*');
    }

    buf.writeln();
    buf.write('Contact your health worker if your condition worsens.');
    return buf.toString().trim();
  }

  static String _programmeSummaryTitle(Programme p) => switch (p) {
        Programme.anc => 'ANC Visit — Guideline Care Plan',
        Programme.pnc => 'PNC Visit — Guideline Care Plan',
        Programme.ncd => 'NCD Visit — Guideline Care Plan',
        Programme.imci => 'Child Health Visit — Guideline Care Plan',
        Programme.tb => 'TB Follow-up — Guideline Care Plan',
        _ => 'Visit — Guideline Care Plan',
      };

  /// Previously shown as a separate "HIGH RISK — Refer today" card.
  /// Removed: referral reasons are now surfaced in [_ReferralAlertCard] above.
  // ignore: unused_element
  Widget? _buildClinicalReferralCard() {
    final progs = widget.confirmedProgrammes;
    final v = _loadedVitals;

    if (progs.contains(Programme.ncd) && v != null) {
      final sys = v.bloodPressureSystolic?.toDouble();
      final dia = v.bloodPressureDiastolic?.toDouble();
      final gl = _loadedLabs.isNotEmpty ? _loadedLabs.first : null;
      final isFasting = gl?.name.contains('Fasting') ?? false;
      final glVal = double.tryParse(gl?.value ?? '');

      final hba1cLab = _loadedLabs.cast<NabaLabResult?>().firstWhere(
            (l) => l?.name == 'HbA1c',
            orElse: () => null,
          );
      final hba1cVal = hba1cLab != null ? double.tryParse(hba1cLab.value) : null;

      final result = NcdReferralEvaluator.evaluate(
        systolic: sys,
        diastolic: dia,
        fastingGlucoseMmol: isFasting ? glVal : null,
        randomGlucoseMmol: isFasting ? null : glVal,
        hba1cPercent: hba1cVal,
        symptoms: widget.confirmedSymptoms.toList(),
      );

      if (!result.isReferralRequired) return null;

      final color = Color(
        int.parse(result.hexColor.replaceFirst('#', '0xFF')),
      );
      final label = switch (result.band) {
        NcdRiskBand.red => 'HIGH RISK — Refer today',
        NcdRiskBand.orange => 'Elevated risk — Referral recommended',
        NcdRiskBand.yellowHigh => 'Moderate risk — Monitor closely',
        NcdRiskBand.yellowLow => 'Borderline — Review at next visit',
        NcdRiskBand.green => 'Controlled',
      };

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 14, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (progs.contains(Programme.anc)) {
      final sys = v?.bloodPressureSystolic;
      final dia = v?.bloodPressureDiastolic;
      final hb = _loadedLabs
          .where((l) => l.name == 'Hemoglobin')
          .map((l) => double.tryParse(l.value))
          .whereType<double>()
          .firstOrNull;

      final result = AncReferralEvaluator.evaluate(
        AncAssessment(
          gestationalWeeks: widget.gestationalWeeks,
          medicalHistoryPhysicalExamination: (sys != null || dia != null)
              ? MedicalHistoryPhysicalExamination(
                  bloodPressureSystolic: sys,
                  bloodPressureDiastolic: dia,
                )
              : null,
          pointOfCareInvestigations: hb != null
              ? PointOfCareInvestigations(hemoglobin: hb)
              : null,
        ),
      );
      if (!result.isReferralRequired) return null;

      final isEmergency = result.isEmergencyReferral;
      final conditions = isEmergency
          ? result.emergencyConditions
          : result.nonEmergencyConditions;
      final color = isEmergency ? const Color(0xFFDC2626) : const Color(0xFFF97316);

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEmergency ? 'Emergency conditions detected' : 'Referral conditions detected',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            ...conditions.map((c) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $c',
                style: TextStyle(fontSize: 13, color: color),
              ),
            )),
          ],
        ),
      );
    }

    if (progs.contains(Programme.pnc) && v != null) {
      final sys = v.bloodPressureSystolic?.toDouble();
      final dia = v.bloodPressureDiastolic?.toDouble();
      final result = PncReferralEvaluator.evaluate(
        systolic: sys,
        diastolic: dia,
      );
      if (!result.isReferralRequired) return null;

      final isUrgent = result.isUrgentReferral;
      final conditions = isUrgent ? result.urgentConditions : result.nonUrgentConditions;
      final color = isUrgent ? const Color(0xFFDC2626) : const Color(0xFFF97316);

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUrgent ? 'Urgent PNC conditions' : 'PNC conditions requiring review',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            ...conditions.map((c) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $c',
                style: TextStyle(fontSize: 13, color: color),
              ),
            )),
          ],
        ),
      );
    }

    return null;
  }

  void _retry() {
    final nextFuture = _fetchNaba();
    setState(() => _future = nextFuture);
  }

  Future<void> _onAccepted(NabaResponse naba) async {
    debugPrint('[_Step3AiRecoState] _onAccepted naba=${naba}');
    if (_accepted) return;
    setState(() => _accepted = true);
    if (!mounted) return;

    // Schedule follow-up locally using the date the SK selected (or the
    // auto-calculated date from the first follow-up item). Stored as
    // NotSynced and pushed on the next offline-sync cycle.
    final followUpDate = _selectedFollowUpDate ??
        (naba.followUp.isNotEmpty
            ? _FollowUpDateRowState.resolveDate(naba.followUp.first)
            : DateTime.now().add(const Duration(days: 14)));
    try {
      final followUpSvc = context.read<FollowUpCallService>();
      await followUpSvc.scheduleLocal(
        patientId: widget.patientId,
        dueDate: followUpDate,
        type: 'MEDICAL_REVIEW',
      );
      debugPrint('[Step3] follow-up scheduled: $followUpDate');
    } catch (e) {
      debugPrint('[Step3] follow-up schedule failed (non-blocking): $e');
    }

    if (!mounted) return;
    context.go(_returnPath);
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
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Household strip shown immediately — taps locked until AI loads.
          if (_householdMembers != null && _householdMembers!.length > 1) ...[
            _HouseholdMemberStrip(
              members: _householdMembers!,
              onTapMember: null,
            ),
            const SizedBox(height: 20),
          ],
          // AI loading indicator + skeleton cards.
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.h8xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  Text(
                    NabaStrings.loadingSubtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
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
          ),
        ],
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
            Text(
              NabaStrings.errorTitle,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
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
                label: Text(NabaStrings.retryButton),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.go(_returnPath),
              child: Text(NabaStrings.skipButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(NabaResponse naba) {
    final referral =
        naba.referralRecommendation?.required_ ?? widget.referralRecommended;
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Referral banner — edge-to-edge, flush top ────────────
          // Reason prefers the clinically-detected conditions threaded
          // from _computeReferral(); falls back to NABA text only when
          // no evaluator conditions are available (e.g. NABA-only referral).
          if (referral || naba.dangerSigns.isNotEmpty) ...[
            _ReferralAlertCard(
              // Prefer NABA reason — it carries the 'context — finding' format
              // the two-line banner needs. Fall back to referredReasons bullets
              // only when no NABA reason is available.
              reason: naba.referralRecommendation?.reason ??
                  (widget.referredReasons.isNotEmpty
                      ? widget.referredReasons.join('\n')
                      : (naba.dangerSigns.isNotEmpty
                          ? naba.dangerSigns.take(2).join(', ')
                          : 'Referral recommended')),
              urgency: naba.referralRecommendation?.urgency ?? 'Today',
              facilityName: widget.referralFacility,
            ),
            Container(height: 1.5, color: const Color(0xFFFECACA)),
          ],

          // Inner content has horizontal padding
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          // ── Offline fallback notice — naba.modelVersion tags whether this
          // ── is a real AI response or the local rule-based substitute used
          // ── when the AI call couldn't be reached (see _fetchNaba).
          if (naba.modelVersion == 'rule-based-fallback') ...[
            const _OfflineFallbackBanner(),
            const SizedBox(height: 12),
          ],
          // ── Household member strip ──────────────────────────────────
          if (_householdMembers != null && _householdMembers!.length > 1) ...[
            _HouseholdMemberStrip(
              members: _householdMembers!,
              onTapMember: (patientId) =>
                  context.push('/patients/$patientId'),
            ),
            const SizedBox(height: 12),
          ],

          // ── 3. AI Counselling Guide (WhatsApp preview) ──────────────
          if (naba.whatsappSummary != null) ...[
            _AiCounsellingCard(
              programme: widget.primaryProgramme,
              text: naba.whatsappSummary!,
              patientLabel: widget.patientLabel,
              patientPhone: _patientPhone,
            ),
            const SizedBox(height: 12),
          ],

          // ── 5. Follow-up timeline ──────────────────────────────────
          if (naba.followUp.isNotEmpty) ...[
            _FollowUpTimeline(
              items: naba.followUp,
              programme: widget.primaryProgramme,
              onDateChanged: (d) => setState(() => _selectedFollowUpDate = d),
            ),
            const SizedBox(height: 16),
          ],
              ], // end inner Column children
            ),   // end inner Column
          ),     // end Padding

          // ── 6. CTA: accept + call/refer ─────────────────────────────
          _BottomCtaBar(
            naba: naba,
            accepted: _accepted,
            headerColor: _headerColor(widget.primaryProgramme),
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

/// Shown atop Step 3 when `_fetchNaba()` couldn't reach the AI service and
/// silently substituted the local rule-based recommendation — makes that
/// substitution visible instead of letting it pass as a full AI response.
class _OfflineFallbackBanner extends StatelessWidget {
  const _OfflineFallbackBanner();

  static const _amberBg = Color(0xFFFFFBEB);
  static const _amberBorder = Color(0xFFFDE68A);
  static const _amberText = Color(0xFF92400E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _amberBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amberBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18, color: _amberText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ComposerStrings.offlineFallbackBannerText,
              style: const TextStyle(
                fontSize: 13,
                color: _amberText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralAlertCard extends StatelessWidget {
  const _ReferralAlertCard({
    required this.reason,
    required this.urgency,
    this.facilityName,
  });
  final String reason;
  final String urgency;
  final String? facilityName;

  // Maps raw API camelCase referral keys → human-readable labels (fallback path).
  static const _reasonLabels = <String, String>{
    'bloodPressure':  'High blood pressure',
    'bloodGlucose':   'High blood glucose',
    'symptoms':       'Reported symptoms',
    'hbLevel':        'Low haemoglobin',
    'weight':         'Abnormal weight',
    'urineProtein':   'Urine protein detected',
    'dangerSigns':    'Danger signs present',
    'bmi':            'Abnormal BMI',
    'gestationalAge': 'Gestational age concern',
  };

  @override
  Widget build(BuildContext context) {
    const bg     = Color(0xFFFEE2E2);
    const accent = Color(0xFFDC2626);

    // Two-line format: NABA reason uses 'context — finding' separator.
    // Single-line / bullet fallback: raw API keys mapped to labels.
    final hasSplit = reason.contains(' — ');
    final parts    = hasSplit ? reason.split(' — ') : <String>[];
    final title    = hasSplit ? 'Referred — ${parts.first.trim()}' : 'Referred';
    final subtitle = hasSplit ? parts.skip(1).join(' — ').trim() : null;
    final bullets  = hasSplit
        ? const <String>[]
        : reason
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => _reasonLabels[s] ?? s)
            .toList();

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon with yellow badge dot
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.trending_up_rounded,
                    size: 18, color: Colors.white),
              ),
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24),
                    shape: BoxShape.circle,
                    border: Border.all(color: bg, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: accent.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ],
                ...bullets.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      '• $c',
                      style: TextStyle(
                        fontSize: 12,
                        color: accent.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                if (facilityName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: accent.withValues(alpha: 0.75)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          facilityName!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accent.withValues(alpha: 0.85),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Referred',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCounsellingCard extends StatelessWidget {
  const _AiCounsellingCard({
    required this.programme,
    required this.text,
    this.patientLabel,
    this.patientPhone,
  });
  final Programme programme;
  final String text;
  final String? patientLabel;
  final String? patientPhone;

  Color _outerBg() => programme == Programme.ncd
      ? const Color(0xFFFFFBEB)
      : const Color(0xFFF0FDF4);

  Future<void> _sendWhatsApp(BuildContext context) async {
    final encoded = Uri.encodeComponent(text);
    final rawPhone =
        patientPhone?.replaceAll(RegExp(r'[^\d]'), '') ?? '';
    final phoneParam = rawPhone.isNotEmpty ? 'phone=$rawPhone&' : '';
    final nativeUri =
        Uri.parse('whatsapp://send?${phoneParam}text=$encoded');
    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri);
      return;
    }
    final webUri = Uri.parse(
        'https://wa.me/${rawPhone.isNotEmpty ? rawPhone : ''}?text=$encoded');
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(NabaStrings.whatsAppNotInstalled)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipientLine = patientLabel != null
        ? 'To: $patientLabel${patientPhone != null ? ' · $patientPhone' : ''}'
        : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _outerBg(),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── WhatsApp-green header ──────────────────────────
            Container(
              color: const Color(0xFF008069),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 11, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          NabaStrings.aiCounsellingGuide,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (recipientLine != null)
                          Text(
                            recipientLine,
                            style: const TextStyle(
                              fontSize: 7.5,
                              color: Color(0xBFFFFFFF),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── WhatsApp chat area ─────────────────────────────
            Container(
              width: double.infinity,
              color: const Color(0xFFECE5DD),
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  // Message bubble
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF111111),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: const [
                            Text(
                              '10:52',
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFF8E9BA8),
                              ),
                            ),
                            SizedBox(width: 3),
                            Icon(Icons.done_all_rounded,
                                size: 13,
                                color: Color(0xFF53BDEB)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Send button
                  GestureDetector(
                    onTap: () => _sendWhatsApp(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.chat_rounded,
                              size: 12, color: Colors.white),
                          SizedBox(width: 7),
                          Text(
                            NabaStrings.sendThisMessage,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Shows all follow-up items: first item has a date picker; remaining items
// are compact left-border-coloured timeline rows.
class _FollowUpTimeline extends StatelessWidget {
  const _FollowUpTimeline({
    required this.items,
    this.programme = Programme.unknown,
    this.onDateChanged,
  });
  final List<NabaFollowUpItem> items;

  /// Primary programme, used to apply the routine follow-up cadence
  /// (ANC = 4 weeks, NCD = 2 weeks) to the editable date row.
  final Programme programme;
  final ValueChanged<DateTime>? onDateChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FollowUpDateRow(
          item: items.first,
          programme: programme,
          onDateChanged: onDateChanged,
        ),
        for (final item in items.skip(1)) ...[
          const SizedBox(height: 6),
          _FollowUpTimelineItem(item: item),
        ],
      ],
    );
  }
}

// Compact timeline row with a coloured left border — used for secondary
// follow-up items (after the primary date-picker row).
class _FollowUpTimelineItem extends StatelessWidget {
  const _FollowUpTimelineItem({required this.item});
  final NabaFollowUpItem item;

  static Color _borderColor(String timeline) {
    final t = timeline.toLowerCase();
    if (t.contains('today') || t.contains('now') ||
        t.contains('immediate') || t == 'in 1 day') {
      return const Color(0xFFDC2626);
    }
    if (t.contains('week') &&
        !t.contains('4 week') &&
        !t.contains('monthly')) {
      return const Color(0xFFB45309);
    }
    return const Color(0xFF0D9488);
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _borderColor(item.timeline);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  top: BorderSide(color: borderColor.withValues(alpha: 0.25)),
                  right: BorderSide(color: borderColor.withValues(alpha: 0.25)),
                  bottom: BorderSide(color: borderColor.withValues(alpha: 0.25)),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.activity,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: borderColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.timeline,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: borderColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowUpDateRow extends StatefulWidget {
  const _FollowUpDateRow({
    required this.item,
    this.programme = Programme.unknown,
    this.onDateChanged,
  });
  final NabaFollowUpItem item;
  final Programme programme;
  final ValueChanged<DateTime>? onDateChanged;

  @override
  State<_FollowUpDateRow> createState() => _FollowUpDateRowState();
}

class _FollowUpDateRowState extends State<_FollowUpDateRow> {
  late DateTime _date;

  static const _cardBg   = Color(0xFFF3F4F8);
  static const _cardText = Color(0xFF9D174D);
  static const _bellColor  = Color(0xFFB45309);

  /// Public static helper so _Step3AiRecoState can compute the default date
  /// for a follow-up item without needing to instantiate the widget.
  static DateTime resolveDate(NabaFollowUpItem item) {
    final t = item.timeline.toLowerCase();
    final isUrgentDays = RegExp(r'(\d+)\s*day').hasMatch(t);
    if (!isUrgentDays) {
      final days = _followUpDays(item.programme);
      if (days != null) return DateTime.now().add(Duration(days: days));
    }
    return _dateFromTimeline(item.timeline);
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[_FollowUpDateRowState] initState');
    _date = _initialDate();
  }

  /// Default follow-up date.
  ///
  /// Urgent, day-scoped timelines (danger signs / referrals, e.g. "In 2 days")
  /// always win.  Otherwise the routine programme cadence applies — ANC = 4
  /// weeks, NCD = 2 weeks — keyed off this item's own programme first, then the
  /// screen's primary programme, and finally the item's own timeline for other
  /// programmes.  The SK can still override via the date picker.
  DateTime _initialDate() {
    final t = widget.item.timeline.toLowerCase();
    final isUrgentDays = RegExp(r'(\d+)\s*day').hasMatch(t);
    if (!isUrgentDays) {
      final days = _followUpDays(widget.item.programme) ??
          _programmeFollowUpDays(widget.programme);
      if (days != null) return DateTime.now().add(Duration(days: days));
    }
    return _dateFromTimeline(widget.item.timeline);
  }

  /// Routine follow-up interval (in days) for a programme name string.
  static int? _followUpDays(String? programme) {
    switch (programme?.toUpperCase()) {
      case 'ANC':
        return 28; // 4 weeks
      case 'NCD':
        return 14; // 2 weeks
      default:
        return null;
    }
  }

  /// Routine follow-up interval (in days) for a [Programme] enum value.
  static int? _programmeFollowUpDays(Programme programme) {
    switch (programme) {
      case Programme.anc:
        return 28; // 4 weeks
      case Programme.ncd:
        return 14; // 2 weeks
      default:
        return null;
    }
  }

  static DateTime _dateFromTimeline(String timeline) {
    final t = timeline.toLowerCase();
    final now = DateTime.now();
    // parse "in X week(s)"
    final weekMatch = RegExp(r'(\d+)\s*week').firstMatch(t);
    if (weekMatch != null) {
      return now.add(Duration(days: int.parse(weekMatch.group(1)!) * 7));
    }
    // parse "in X day(s)"
    final dayMatch = RegExp(r'(\d+)\s*day').firstMatch(t);
    if (dayMatch != null) {
      return now.add(Duration(days: int.parse(dayMatch.group(1)!)));
    }
    // parse "in X month(s)"
    final monthMatch = RegExp(r'(\d+)\s*month').firstMatch(t);
    if (monthMatch != null) {
      return DateTime(now.year, now.month + int.parse(monthMatch.group(1)!), now.day);
    }
    return now.add(const Duration(days: 28));
  }

  String get _formatted =>
      '${_date.day.toString().padLeft(2, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.year}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
      widget.onDateChanged?.call(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Bell icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_rounded,
                    size: 18,
                    color: _bellColor,
                  ),
                ),
                const SizedBox(width: 10),
                // Label
                const Text(
                  'Follow-up',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _cardText,
                  ),
                ),
                const SizedBox(width: 10),
                // Date field
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _formatted,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const Icon(Icons.calendar_today_rounded,
                            size: 14, color: _cardText),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Auto-scheduled · already saved',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
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
                  label: Text(NabaStrings.acceptProposal),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEC4899),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFEC4899).withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    textStyle: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
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
                    label: Text(VisitCompleteStrings.sendCounsellingMessage),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: headerColor,
                      side: BorderSide(
                          color: headerColor.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
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
  // Null while the AI recommendation is still loading — members are shown
  // as a preview but taps are disabled until the care plan is ready.
  final void Function(String patientId)? onTapMember;

  static (Color ring, Color labelColor, String visitLabel) _style(Programme p) {
    switch (p) {
      case Programme.anc:
        return (const Color(0xFFFBCFE8), const Color(0xFFEC4899), 'ANC visit');
      case Programme.pnc:
        return (const Color(0xFFA7F3D0), const Color(0xFF10B981), 'PNC due');
      case Programme.imci:
        return (const Color(0xFFFDE68A), const Color(0xFFF59E0B), 'Child visit');
      case Programme.ncd:
        return (const Color(0xFFFDE68A), const Color(0xFF92400E), 'BP check');
      case Programme.tb:
        return (const Color(0xFFA5B4FC), const Color(0xFF4F46E5), 'TB check');
      case Programme.epi:
        return (const Color(0xFF93C5FD), const Color(0xFF1D4ED8), 'Vaccines');
      case Programme.nutrition:
        return (const Color(0xFF6EE7B7), const Color(0xFF15803D), 'Nutrition');
      default:
        return (const Color(0xFFE5E7EB), AppColors.textMuted, 'Scheduled');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
              children: [
                for (int i = 0; i < members.length; i++) ...[
                  if (i == 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 14, top: 4),
                      child: SizedBox(
                        height: 72,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  if (members[i].isCurrentPatient)
                    _MemberAvatar(
                      member: members[i],
                      ringColor: AppColors.navy,
                      ringWidth: 3.0,
                      labelText: 'Viewing',
                      labelColor: AppColors.navy,
                      labelBold: true,
                      onTap: null,
                    )
                  else ...[
                    Builder(builder: (context) {
                      final (ring, labelColor, visitLabel) =
                          _style(members[i].primaryProgramme);
                      final pid = members[i].patientId;
                      return Opacity(
                        opacity: onTapMember != null ? 1.0 : 0.45,
                        child: _MemberAvatar(
                          member: members[i],
                          ringColor: ring,
                          ringWidth: 1.5,
                          labelText: visitLabel,
                          labelColor: labelColor,
                          labelBold: false,
                          onTap: onTapMember != null
                              ? () => onTapMember!(pid)
                              : null,
                        ),
                      );
                    }),
                  ],
                ],
              ],
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
        return '🤰';
      case Programme.pnc:
        return '👩';
      case Programme.imci:
      case Programme.epi:
        return '👶';
      case Programme.ncd:
        return '👨';
      case Programme.tb:
        return '😷';
      case Programme.nutrition:
        return '🥦';
      case Programme.familyPlanning:
        return '👪';
      default:
        return '👤';
    }
  }

  static Color _bgColor(Programme p) {
    switch (p) {
      case Programme.anc:
      case Programme.pnc:
        return const Color(0xFFFDF2F8);
      case Programme.imci:
      case Programme.epi:
        return const Color(0xFFFEF3C7);
      case Programme.ncd:
        return const Color(0xFFFEF9EC);
      case Programme.tb:
        return const Color(0xFFEEF2FF);
      case Programme.nutrition:
      case Programme.familyPlanning:
        return const Color(0xFFF0FDF4);
      default:
        return const Color(0xFFF8FAFC);
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
          width: 56,
          child: Column(
            children: [
              Container(
                width: member.isCurrentPatient ? 46.0 : 42.0,
                height: member.isCurrentPatient ? 46.0 : 42.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _bgColor(member.primaryProgramme),
                  border: Border.all(color: ringColor, width: ringWidth),
                ),
                child: Center(
                  child: Text(
                    _emoji(member.primaryProgramme),
                    style: TextStyle(
                      fontSize: member.isCurrentPatient ? 20.0 : 18.0,
                    ),
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

