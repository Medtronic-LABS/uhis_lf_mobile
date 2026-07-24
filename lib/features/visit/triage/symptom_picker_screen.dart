import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/preferences/ai_feature_toggles_notifier.dart';
import '../../../core/db/encounter_dao.dart';
import '../../../core/db/immunisation_dao.dart';
import '../../../core/db/local_assessment_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/models/programme.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/db/patient_programmes_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../patient/followup_repository.dart';
import '../../patient/vitals_repository.dart';
import '../../realtime_asr/chief_complaint_matcher.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/widgets/ai_scribe_banner.dart';
import '../briefing/briefing_models.dart';
import '../briefing/visit_briefing_repository.dart';
import '../pathway/pathway_engine.dart';
import 'patient_context_builder.dart';
import 'programme_grid_sync.dart';
import 'symptom_catalog.dart';
import 'visit_step_header.dart';
import 'triage_view_model.dart';

/// Symptom picker screen for the triage step.
///
/// This is a routed screen that:
/// 1. Builds PatientContext from local DB
/// 2. Shows symptom picker
/// 3. Navigates to TriageResultScreen (Step 2) with activated pathways
/// 4. TriageResultScreen navigates to visit form (Step 3)
class SymptomPickerScreen extends StatefulWidget {
  const SymptomPickerScreen({
    super.key,
    required this.encounterId,
    required this.patientId,
    this.memberId,
    this.householdId,
    this.patientAge,
    this.patientName,
    this.patientGender,
    this.origin,
    this.onAdvance,
    this.onSymptomsConfirmed,
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

  /// When non-null, the screen calls this on the "Continue" CTA instead of
  /// pushing the next route. Used by [VisitFlowScreen] to host the picker
  /// inside a single-route multi-step flow.
  final ValueChanged<List<ActivatedPathway>>? onAdvance;

  /// Optional secondary callback fired alongside [onAdvance] carrying the
  /// finalised symptom selection + sickness duration. Used by the host to
  /// build the AI Programme Recommendation request — kept separate from
  /// [onAdvance] so existing pathway-only callers don't break.
  ///
  /// [aiPickedSymptoms] is the subset of [symptoms] that were pre-selected by
  /// the AI Scribe; callers can use it to colour those chips differently in
  /// subsequent steps.
  final void Function(
    Set<String> symptoms,
    String? sicknessDuration,
    String? otherSymptoms,
    Set<String> aiPickedSymptoms,
  )?
  onSymptomsConfirmed;

  /// Fired just before [onAdvance] with the SK's confirmed programme set from
  /// the inline eligible-services grid. Only called for adult patients —
  /// child visits (under-5) skip the grid and use the vaccination path.
  final ValueChanged<Set<Programme>>? onProgrammesSelected;

  /// Fired on every service-card toggle so the host can update the visit
  /// header badge in real time without waiting for the SK to tap Continue.
  final ValueChanged<Set<Programme>>? onProgrammesLive;

  /// Fired just before [onAdvance] with whether the SK confirmed a delivery
  /// visit. When true, the host includes the pregnancyOutcome form sections.
  final ValueChanged<bool>? onDeliverySelected;

  @override
  State<SymptomPickerScreen> createState() => _SymptomPickerScreenState();
}

class _SymptomPickerScreenState extends State<SymptomPickerScreen> {
  TriageViewModel? _viewModel;
  PatientContext? _patientContext;
  bool _isLoading = true;
  String? _error;

  VisitBriefingResponse? _briefingData;
  bool _briefingLoading = true;

  /// Programmes the SK has selected in the inline service grid.
  /// Initialized from the pathway engine on load; SK can toggle freely.
  final Set<Programme> _selectedProgrammes = {};

  /// Subset of [_selectedProgrammes] that were pre-activated by the pathway
  /// engine — rendered with the ✦ sparkle in the card.
  final Set<Programme> _pathwayActivatedProgrammes = {};

  /// Programmes the SK explicitly turned off this visit. Pathway sync must
  /// not resurrect these — otherwise deselecting NCD (etc.) is immediately
  /// undone when symptoms/AI refresh pathway activation.
  final Set<Programme> _skDismissedProgrammes = {};

  /// PW meta-flag — gates ANC. Auto-true when patient already has PW/ANC registered.
  bool _isPW = false;

  /// Delivery meta-flag — gates PNC. Auto-true when patient is postpartum.
  bool _isDelivery = false;

  /// True when patient already has an ANC assessment recorded today — blocks
  /// a second ANC visit on the same calendar day.
  bool _ancVisitedToday = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[_SymptomPickerScreenState] initState');
    // Defer to after first frame to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPatientContext();
    });
  }

  Future<void> _loadPatientContext() async {
    debugPrint('[_SymptomPickerScreenState] _loadPatientContext');
    debugPrint(
      '[SymptomPicker] Starting load for encounterId=${widget.encounterId}, patientId=${widget.patientId}',
    );

    // Read all DAOs before any async operations
    final encounterDao = context.read<EncounterDao>();
    final patientDao = context.read<PatientDao>();
    final programmesDao = context.read<PatientProgrammesDao>();
    final pregnancyDao = context.read<PregnancySnapshotDao>();

    try {
      // Get patientId - either from widget or look up from encounter
      var patientId = widget.patientId;
      debugPrint('[SymptomPicker] Initial patientId: $patientId');

      if (patientId.isEmpty) {
        // Look up patientId from encounter
        debugPrint('[SymptomPicker] Looking up patient from encounter...');
        final encounter = await encounterDao.byId(widget.encounterId);
        debugPrint('[SymptomPicker] Encounter found: ${encounter != null}');
        if (encounter != null) {
          patientId = encounter.patientId;
          debugPrint(
            '[SymptomPicker] Got patientId from encounter: $patientId',
          );
        }
      }

      if (patientId.isEmpty) {
        debugPrint('[SymptomPicker] ERROR: patientId still empty');
        if (!mounted) return;
        setState(() {
          _error = 'Unable to determine patient for this visit';
          _isLoading = false;
        });
        return;
      }

      debugPrint('[SymptomPicker] Building PatientContext for $patientId...');
      final immunisationDao =
          context.read<ImmunisationDao>();
      final builder = PatientContextBuilder(
        patientDao: patientDao,
        programmesDao: programmesDao,
        pregnancyDao: pregnancyDao,
        immunisationDao: immunisationDao,
      );

      final ctx = await builder.build(patientId);
      debugPrint('[SymptomPicker] PatientContext built: ${ctx != null}');
      if (ctx != null) {
        debugPrint(
          '[SymptomPicker] PatientContext: age=${ctx.ageMonths}mo, sex=${ctx.sex.name}, pregnant=${ctx.isPregnant}, programmes=${ctx.activeProgrammes.map((p) => p.name).join(',')}',
        );
      }

      if (!mounted) return;

      if (ctx == null) {
        debugPrint('[SymptomPicker] ERROR: Patient not found');
        setState(() {
          _error = 'Patient not found in local database. Please sync first.';
          _isLoading = false;
        });
        return;
      }

      debugPrint('[SymptomPicker] Success! Setting up view model...');
      final vm = TriageViewModel(patientContext: ctx);
      final pathwaySet = vm.activatedPathways.map((p) => p.programme).toSet();
      // ANC gates behind PW: only pre-select PW if patient already has a PW
      // or ANC registration. Brand-new pregnant women start with PW=false so
      // the SK must explicitly select PW first before ANC becomes available.
      final isPw = ctx.activeProgrammes.contains(Programme.pw) ||
          ctx.activeProgrammes.contains(Programme.anc);
      // Block a second ANC visit on the same calendar day.
      final ancToday = await context
          .read<LocalAssessmentDao>()
          .hasAncAssessmentTodayForPatient(patientId);
      // Pregnancy Outcome is an explicit SK choice — never auto-on.
      // Postpartum mothers get PNC via [enrolledSeed], not this flag.
      final enrolledSeed = ProgrammeGridSync.applicableEnrolledSeed(
        enrolled: ctx.activeProgrammes.toSet(),
        isPregnant: ctx.isPregnant,
        isPostpartum: ctx.isPostpartum,
      );
      vm.addListener(_syncPathwaysToServiceGrid);
      setState(() {
        _patientContext = ctx;
        _viewModel = vm;
        _selectedProgrammes
          ..clear()
          ..addAll(pathwaySet)
          // Only seed enrolled programmes that apply to *this* visit state
          // (e.g. skip enrolled PNC while still pregnant). SK can still add
          // or remove cards after load.
          ..addAll(enrolledSeed);
        _pathwayActivatedProgrammes
          ..clear()
          ..addAll(pathwaySet);
        _isPW = isPw;
        _isDelivery = false;
        _ancVisitedToday = ancToday;
        _isLoading = false;
      });
      debugPrint(
          '[SymptomPicker] Load complete — pathway programmes: ${pathwaySet.map((p) => p.name).join(', ')} '
          'enrolledSeed: ${enrolledSeed.map((p) => p.name).join(', ')} '
          'selected: ${_selectedProgrammes.map((p) => p.name).join(', ')}');
      _fireProgrammesLive();
      if (context.read<AiFeatureTogglesNotifier>().toggles.step1SummaryEnabled) {
        _startBriefingFetch(ctx);
      } else {
        // Toggle off — skip the AI-service call entirely (saves the SK's
        // data) and land in the same state the fallback-render path already
        // treats as "show local briefing content".
        setState(() => _briefingLoading = false);
      }
    } catch (e, stack) {
      debugPrint('[SymptomPicker] ERROR: $e');
      debugPrint('[SymptomPicker] Stack: $stack');
      if (!mounted) return;
      setState(() {
        _error = 'Error loading patient: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _startBriefingFetch(PatientContext patientCtx) async {
    if (!mounted) return;
    try {
      final vitalsRepo = context.read<VitalsRepository>();
      final followUpRepo = context.read<FollowUpRepository>();
      final briefingRepo = context.read<VisitBriefingRepository>();

      final visitsByVisit = await vitalsRepo.recentByVisit(
        widget.patientId,
        limit: 5,
      );
      final followUps = await followUpRepo.openForPatientLocal(
        widget.patientId,
      );

      Map<String, dynamic>? vitalsMap;
      if (visitsByVisit.isNotEmpty) {
        final latest = visitsByVisit.first;
        final bp = latest.readings
            .where((r) => r.type == VitalType.bloodPressure)
            .firstOrNull;
        final weight = latest.readings
            .where((r) => r.type == VitalType.weight)
            .firstOrNull;
        final glucose = latest.readings
            .where((r) => r.type == VitalType.glucose)
            .firstOrNull;
        final spo2 = latest.readings
            .where((r) => r.type == VitalType.spO2)
            .firstOrNull;
        final bmi = latest.readings
            .where((r) => r.type == VitalType.bmi)
            .firstOrNull;
        vitalsMap = {
          if (bp?.systolic != null)
            'bloodPressureSystolic': bp!.systolic!.toInt(),
          if (bp?.diastolic != null)
            'bloodPressureDiastolic': bp!.diastolic!.toInt(),
          if (weight?.value != null) 'weight': weight!.value,
          if (glucose?.value != null) 'glucose': glucose!.value,
          if (spo2?.value != null) 'spO2': spo2!.value!.toInt(),
          if (bmi?.value != null) 'bmi': bmi!.value,
        };
      }

      final followUpSummaries = followUps.map((f) {
        final daysOverdue = f.isOverdue
            ? DateTime.now().difference(f.dueDate).inDays
            : null;
        return {
          'type': f.type.name,
          'daysOverdue': daysOverdue,
          'reason': f.reason,
        };
      }).toList();

      final risks = <String>[];
      if (followUps.any((f) => f.isOverdue)) risks.add('missed_followup');
      final latestBp = visitsByVisit.isNotEmpty
          ? visitsByVisit.first.readings
                .where((r) => r.type == VitalType.bloodPressure)
                .firstOrNull
          : null;
      if (latestBp?.systolic != null && latestBp!.systolic! >= 140) {
        risks.add('elevated_bp');
      }
      if (visitsByVisit.length >= 3) risks.add('returning_patient');

      final lastVisit = visitsByVisit.isNotEmpty ? visitsByVisit.first : null;

      final request = <String, dynamic>{
        'patientId': widget.patientId,
        if (widget.patientName != null) 'patientName': widget.patientName,
        if (widget.patientAge != null) 'ageYears': widget.patientAge,
        if (widget.patientGender != null) 'gender': widget.patientGender,
        'activeProgrammes': patientCtx.activeProgrammes
            .map((p) => p.name)
            .toList(),
        'visitCount': visitsByVisit.length,
        if (lastVisit != null)
          'lastVisitDate': lastVisit.date.toIso8601String().split('T').first,
        if (lastVisit != null) 'lastVisitProgramme': lastVisit.programme,
        if (vitalsMap != null && vitalsMap.isNotEmpty)
          'recentVitals': vitalsMap,
        'openFollowUps': followUpSummaries,
        'riskIndicators': risks,
        if (patientCtx.gestationalWeeks != null)
          'gestationalWeeks': patientCtx.gestationalWeeks,
      };

      final data = await briefingRepo.generate(request);
      if (mounted) {
        setState(() {
          _briefingData = data;
          _briefingLoading = false;
        });
      }
    } on Object catch (e, st) {
      debugPrint('[Briefing] fetch failed: $e');
      debugPrint('[Briefing] $st');
      if (mounted) setState(() => _briefingLoading = false);
    }
  }

  void _fireProgrammesLive() {
    widget.onProgrammesLive?.call(Set.unmodifiable(_selectedProgrammes));
  }

  void _onPWToggle(bool selected) {
    setState(() {
      _isPW = selected;
      if (!selected) {
        _selectedProgrammes.remove(Programme.anc);
        _selectedProgrammes.remove(Programme.pw);
        _skDismissedProgrammes.add(Programme.anc);
        _skDismissedProgrammes.add(Programme.pw);
      } else {
        _skDismissedProgrammes.remove(Programme.anc);
        _skDismissedProgrammes.remove(Programme.pw);
        _selectedProgrammes.add(Programme.pw);
        if (_patientContext!.activeProgrammes.contains(Programme.anc) ||
            _pathwayActivatedProgrammes.contains(Programme.anc)) {
          _selectedProgrammes.add(Programme.anc);
        }
      }
    });
    _fireProgrammesLive();
  }

  void _onDeliveryToggle(bool selected) {
    setState(() {
      _isDelivery = selected;
      if (!selected) {
        _selectedProgrammes.remove(Programme.pnc);
        _skDismissedProgrammes.add(Programme.pnc);
        // Restore ANC/PW that the delivery gate dismissed (and any pathway
        // programmes that were previously dismissed for the same reason).
        _skDismissedProgrammes.remove(Programme.anc);
        _skDismissedProgrammes.remove(Programme.pw);
        for (final p in _pathwayActivatedProgrammes) {
          _skDismissedProgrammes.remove(p);
          _selectedProgrammes.add(p);
        }
        // Re-enable PW gate when patient is still pregnant / ANC-enrolled.
        final ctx = _patientContext;
        if (ctx != null &&
            (ctx.isPregnant || ctx.activeProgrammes.contains(Programme.anc))) {
          _isPW = true;
          _selectedProgrammes.add(Programme.pw);
          if (ctx.activeProgrammes.contains(Programme.anc) ||
              _pathwayActivatedProgrammes.contains(Programme.anc)) {
            _selectedProgrammes.add(Programme.anc);
          }
        }
      } else {
        // Delivery / pregnancy-outcome visit: clear only ANC + PW. Other
        // selected programmes (NCD, TB, etc.) stay open alongside PNC /
        // pregnancy-outcome forms.
        _isPW = false;
        final next = ProgrammeGridSync.applyDeliverySelected(
          selected: _selectedProgrammes,
          dismissedBySk: _skDismissedProgrammes,
        );
        _selectedProgrammes
          ..clear()
          ..addAll(next.selected);
        _skDismissedProgrammes
          ..clear()
          ..addAll(next.dismissedBySk);
      }
    });
    debugPrint('[DeliveryGate] chip toggled: selected=$selected '
        'programmes=${_selectedProgrammes.map((p) => p.name).join(", ")} '
        'isPW=$_isPW');
    _fireProgrammesLive();
  }

  /// Keeps [_selectedProgrammes] and [_pathwayActivatedProgrammes] in sync
  /// with the pathway engine whenever symptoms change (AI Scribe pre-tick or
  /// manual selection). Only adds newly activated programmes — never removes
  /// an SK selection, and never resurrects a programme in
  /// [_skDismissedProgrammes].
  void _syncPathwaysToServiceGrid() {
    if (!mounted) return;
    final vm = _viewModel;
    if (vm == null) return;
    final activated = vm.allPathways.map((p) => p.programme).toSet();
    final unseen = ProgrammeGridSync.additionsFromPathways(
      activated: activated,
      selected: _selectedProgrammes,
      dismissedBySk: _skDismissedProgrammes,
    );
    if (unseen.isNotEmpty) {
      setState(() {
        _selectedProgrammes.addAll(unseen);
        _pathwayActivatedProgrammes.addAll(unseen);
      });
      _fireProgrammesLive();
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_syncPathwaysToServiceGrid);
    _viewModel?.dispose();
    debugPrint('[_SymptomPickerScreenState] dispose');
    super.dispose();
  }

  void _openVaccinationTimeline() {
    debugPrint('[_SymptomPickerScreenState] _openVaccinationTimeline');
    final ctx = _patientContext;
    if (ctx == null) return;
    // Fetch DOB from patient DAO to pass to timeline screen
    final patientDao = context.read<PatientDao>();
    patientDao.byId(widget.patientId).then((patient) {
      if (!mounted) return;
      context.push(
        '/patients/${widget.patientId}/immunisation',
        extra: <String, dynamic>{
          'patientName': widget.patientName,
          if (patient?.dob != null) 'dob': patient!.dob,
          if (widget.memberId != null) 'memberId': widget.memberId,
          // householdMemberLocalId unavailable on this screen; defaults to 0
        },
      );
    });
  }

  /// Handles the Vaccination CTA tap for under-5 patients.
  ///
  /// In embedded mode (inside VisitFlowScreen): advances the visit flow to the
  /// vaccination step by calling [_onContinue], which fires [onAdvance].
  /// In standalone mode: pushes the immunisation timeline route directly.
  void _onVaccination() {
    debugPrint('[_SymptomPickerScreenState] _onVaccination');
    final vm = _viewModel;
    if (vm == null) return;
    if (widget.onAdvance != null) {
      // Children bypass the no-symptoms guard — vaccination is always valid.
      _doAdvance(vm);
    } else {
      _openVaccinationTimeline();
    }
  }

  void _onContinue() {
    debugPrint('[_SymptomPickerScreenState] _onContinue');
    final vm = _viewModel;
    if (vm == null || _patientContext == null) return;

    debugPrint(
      '[SymptomPicker] Continue tapped — ${vm.activatedPathways.length} pathways: '
      '${vm.activatedPathways.map((p) => p.programme.name).join(', ')} | '
      'selected programmes: ${_selectedProgrammes.map((p) => p.name).join(', ')}',
    );

    // Guard: only block when there is truly no programme context —
    // no enrolled programmes, no activated pathways, no symptoms.
    // Enrolled patients always proceed: enrolment alone determines the form.
    final hasEnrolledProgrammes =
        _patientContext!.activeProgrammes.isNotEmpty;
    if (vm.selectedSymptoms.isEmpty &&
        vm.activatedPathways.isEmpty &&
        !hasEnrolledProgrammes) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(SymptomPickerStrings.noSymptomsGuard),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: SymptomPickerStrings.noSymptomsGuardCta,
              onPressed: () => _doAdvance(vm),
            ),
          ),
        );
      return;
    }

    _doAdvance(vm);
  }

  Future<void> _doAdvance(TriageViewModel vm) async {
    // If the rule engine produced no pathways but the patient has enrolled
    // programmes, synthesize a pathway from enrolment so the form always
    // opens the correct section (guards against sex/data quality issues
    // that cause demographic gates to fail — see issue #127).
    var pathways = vm.activatedPathways;
    if (pathways.isEmpty && _patientContext != null) {
      const priorityByProgramme = {
        Programme.anc: 20,
        Programme.pnc: 25,
        Programme.imci: 10,
        Programme.ncd: 40,
        Programme.tb: 30,
        Programme.epi: 100,
      };
      pathways = _patientContext!.activeProgrammes
          .where(priorityByProgramme.containsKey)
          .map(
            (p) => ActivatedPathway(
              programme: p,
              priority: priorityByProgramme[p]!,
              confidence: 1.0,
              trigger: PathwayTrigger.rule,
              rationaleKey: 'pathwayEnrolmentFallback',
            ),
          )
          .toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
      if (pathways.isNotEmpty) {
        debugPrint(
          '[SymptomPicker] activatedPathways empty — using enrolment fallback: '
          '${pathways.map((p) => p.programme.name).join(', ')}',
        );
      }
    }

    // Last-assessment fallback: if enrolment data is also absent (e.g. a
    // patient whose enrollment sync hasn't landed yet), look at the most
    // recent assessment in the local DB and open the same programme form.
    if (pathways.isEmpty && mounted) {
      try {
        final dao = context.read<LocalAssessmentDao>();
        final assessments = await dao.getByPatientId(widget.patientId);
        if (assessments.isNotEmpty) {
          final lastType = assessments.first.assessmentType;
          final programme = Programme.fromTag(lastType);
          if (programme != null) {
            const priorityByProgramme = {
              Programme.anc: 20,
              Programme.pnc: 25,
              Programme.imci: 10,
              Programme.ncd: 40,
              Programme.tb: 30,
              Programme.epi: 100,
            };
            pathways = [
              ActivatedPathway(
                programme: programme,
                priority: priorityByProgramme[programme] ?? 50,
                confidence: 1.0,
                trigger: PathwayTrigger.rule,
                rationaleKey: 'pathwayLastAssessmentFallback',
              ),
            ];
            debugPrint(
              '[SymptomPicker] no enrolment — last-assessment fallback: '
              '${programme.name} (from assessmentType=$lastType)',
            );
          }
        }
      } catch (e) {
        debugPrint('[SymptomPicker] last-assessment lookup failed: $e');
      }
    }

    // In-flow host (VisitFlowScreen) intercepts via callback.
    final onAdvance = widget.onAdvance;
    if (onAdvance != null) {
      if (!(_patientContext?.isUnder5 ?? false)) {
        // Delivery visit must always carry PNC so Step 2 opens the pregnancy-
        // outcome / PNC form even if the live set was emptied by a rebuild.
        final programmes = _isDelivery
            ? (Set<Programme>.from(_selectedProgrammes)..add(Programme.pnc))
            : _selectedProgrammes;
        widget.onProgrammesSelected?.call(Set.unmodifiable(programmes));
        widget.onDeliverySelected?.call(_isDelivery);
      }
      widget.onSymptomsConfirmed?.call(
        vm.selectedSymptoms,
        vm.sicknessDuration,
        vm.customSymptomText,
        vm.scribePreTickedCodes,
      );
      onAdvance(pathways);
      return;
    }

    // Bypass the triage-result interstitial and go straight to the form.
    _navigateToForm(pathways);
  }

  void _navigateToForm(List<ActivatedPathway> pathways) {
    debugPrint('[_SymptomPickerScreenState] _navigateToForm pathways=${pathways}');
    final origin = widget.origin;
    final originParam = origin != null ? '?origin=$origin' : '';

    context.go(
      '/patients/visit/${widget.encounterId}/form$originParam',
      extra: {
        'patientId': widget.patientId,
        'memberId': widget.memberId,
        'householdId': widget.householdId,
        'patientAge': widget.patientAge,
        'activatedPathways': pathways.map((p) => p.programme.name).toList(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(TriageStrings.pickerTitle)),
        body: const SizedBox.shrink(),
      );
    }

    if (_error != null || _viewModel == null) {
      return Scaffold(
        appBar: AppBar(title: Text(TriageStrings.pickerTitle)),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Failed to load patient context',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
                    _loadPatientContext();
                  },
                  child: Text(TriageStrings.retryButton),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // When hosted by VisitFlowScreen (onAdvance set) the wrapper owns the
    // patient + step header, so we drop our own AppBar to avoid two stacked
    // headers. Standalone route entry keeps the navy 3-step header.
    final bool embedded = widget.onAdvance != null;

    return ChangeNotifierProvider<TriageViewModel>.value(
      value: _viewModel!,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: embedded
            ? null
            : VisitStepHeader(
                step: VisitStep.symptomPicker,
                patientLabel: widget.patientName ?? TriageStrings.pickerTitle,
                onBack: () => context.pop(),
              ),
        // Floating mic moved to a prominent purple banner at the top of the
        // sliver list (see _AiScribeTriageBanner below). The legacy FAB is
        // retired — banner makes the entry point unmissable per spec §4.1.2.
        floatingActionButton: null,
        body: Consumer<TriageViewModel>(
          builder: (context, vm, _) {
            final aiToggles = context.watch<AiFeatureTogglesNotifier>().toggles;
            return CustomScrollView(
              slivers: [
                // 1) Before You Knock (AI brief — collapsible card).
                // 2) Sit with her / him — greet warmly (navy filled card).
                // 3) "How is she feeling today?" heading.
                // 4) AI Scribe banner.
                //
                // The greet card was previously a navy strip mixed inside the
                // Before-You-Knock body. It now stands on its own per design
                // reference so the SK reads context first, greets the
                // patient, then taps the scribe.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: _AiBriefingSection(
                      briefingLoading: _briefingLoading,
                      briefingData: _briefingData,
                      patientContext: _patientContext!,
                    ),
                  ),
                ),

                // Section heading directly above the AI Scribe banner.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      SymptomPickerStrings.howFeelingTodayHeadingFor(
                        isFemale: _patientContext!.sex == Sex.female,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ),

                // Prominent AI Scribe mic banner — spec §4.1.2 / §5.1.1.
                if (AppConfig.scribeEnabled && aiToggles.step1AsrEnabled)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: AiScribeBanner(
                        encounterId: widget.encounterId,
                        patientId: widget.patientId,
                        isFemale:
                            vm.patientContext.sex == Sex.female,
                        tapStartsLiveAsr: true,
                        onReviewReady: (ctrl) {
                          final result = ctrl.session.triageExtractionResult;
                          if (result != null) {
                            vm.applyScribeTriageResult(result);
                          }
                          ctrl.resetSession();
                        },
                        onLiveFields: (fields, transcript) {
                          if (fields.chiefComplaints.isEmpty) return;
                          final codes = ChiefComplaintMatcher.match(
                            fields.chiefComplaints,
                          );
                          if (codes.isEmpty) return;
                          vm.applyScribeTriageResult(
                            TriageExtractionResult(
                              symptomCodes: [
                                for (final code in codes)
                                  AIExtractedField(
                                    fieldId: code,
                                    value: true,
                                    confidence:
                                        ChiefComplaintMatcher.matchConfidence,
                                  ),
                              ],
                              transcriptText: transcript,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // Chip grid + search bar — no white card bg; blends with canvas.
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _UnifiedSymptomPicker(vm: vm),
                  ),
                ),

                // Selected symptoms panel — one wide row per picked symptom,
                // shown below the chip grid.
                if (vm.selectedSymptoms.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _SelectedSymptomsPanel(vm: vm),
                    ),
                  ),

                // Eligible services grid — shown for all patients.
                // Under-5: Vaccination + Child Health cards only.
                // Adults: full programme card set.
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _InlineServiceSelector(
                        patientContext: _patientContext!,
                        selectedProgrammes: _selectedProgrammes,
                        pathwayProgrammes: _pathwayActivatedProgrammes,
                        enrolledProgrammes: _patientContext!.activeProgrammes.toSet(),
                        isPW: _isPW,
                        isDelivery: _isDelivery,
                        ancVisitedToday: _ancVisitedToday,
                        onProgrammeToggle: (programme, selected) {
                          setState(() {
                            if (selected) {
                              _selectedProgrammes.add(programme);
                              _skDismissedProgrammes.remove(programme);
                            } else {
                              _selectedProgrammes.remove(programme);
                              _skDismissedProgrammes.add(programme);
                            }
                          });
                          _fireProgrammesLive();
                        },
                        onPWToggle: _onPWToggle,
                        onDeliveryToggle: _onDeliveryToggle,
                        onVaccination: _onVaccination,
                      ),
                    ),
                  ),

                // Status bar + CTA row
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedProgrammes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  SymptomPickerStrings.servicesOpeningStatus(
                                    _selectedProgrammes.length,
                                    _selectedProgrammes
                                        .map((p) => p.wireTag)
                                        .toList(),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.navy,
                                  ),
                                ),
                                if (vm.activatedPathways.isNotEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.auto_awesome_rounded,
                                          size: 11,
                                          color: Color(0xFF7C3AED),
                                        ),
                                        SizedBox(width: 3),
                                        Text(
                                          'AI selected',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF7C3AED),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                        // ── Vaccination CTA (under-5 only) ─────────────────
                        if (_patientContext!.isUnder5) ...[
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _onVaccination,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.pink,
                                foregroundColor: AppColors.textOnNavy,
                              ),
                              child: Text(
                                ChildAssessmentStrings.vaccinationCta,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          // Child Health assessment CTA — only when SK selected it.
                          if (_selectedProgrammes.contains(Programme.imci)) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _onContinue,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.navy,
                                  foregroundColor: AppColors.textOnNavy,
                                ),
                                child: Text(SymptomPickerStrings.ctaStartCheckup),
                              ),
                            ),
                          ],
                        ],

                        // ── Start Checkup button (adults only) ────────────
                        if (!(_patientContext!.isUnder5)) ...[
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _onContinue,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.pink,
                                foregroundColor: AppColors.textOnNavy,
                              ),
                              child: Text(
                                  SymptomPickerStrings.ctaStartCheckup),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

}

// ── AI Briefing Section: 3 stacked cards ─────────────────────────────────────

class _AiBriefingSection extends StatelessWidget {
  const _AiBriefingSection({
    required this.briefingLoading,
    required this.briefingData,
    required this.patientContext,
  });

  final bool briefingLoading;
  final VisitBriefingResponse? briefingData;
  final PatientContext patientContext;

  @override
  Widget build(BuildContext context) {
    // Pronoun resolution — spec §4.1 ANC greeting "আপু" (her),
    // §5.1 NCD "কাকা" (him). Defaults to him when sex is unknown.
    final isFemale = patientContext.sex == Sex.female;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1) Before You Knock — collapsible AI brief card. No navy greet
        // strip embedded here; greet now stands on its own (see below).
        _BriefingCard(
          icon: Icons.psychology_outlined,
          iconColor: AppColors.navy,
          title: SymptomPickerStrings.briefCard1Title,
          child: briefingLoading
              ? const _BriefingLoadingSkeleton(lines: 3)
              : briefingData == null
              ? _BriefingFallbackContent(patientContext: patientContext)
              : _BriefingCard1Content(data: briefingData!),
        ),
        const SizedBox(height: 10),
        // 2) Sit With Her / Him — Greet Warmly. Navy-filled card carrying the
        // Bangla greeting prompt + English translation + a helper hint that
        // primes the SK before they tap the AI Scribe below.
        _GreetWarmlyCard(
          isFemale: isFemale,
          loading: briefingLoading,
          greeting: briefingData?.greeting,
          fallbackOpeningLine:
              briefingData?.suggestedDiscussionPoints.openingLine,
        ),
      ],
    );
  }
}

/// Collapsible outer shell shared by all 3 briefing cards.
class _BriefingCard extends StatefulWidget {
  const _BriefingCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  State<_BriefingCard> createState() => _BriefingCardState();
}

class _BriefingCardState extends State<_BriefingCard> {
  // Default to open so the SK reads the brief without an extra tap; tap-to-
  // collapse is preserved for SKs who prefer the compact header.
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tappable header row
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Solid navy square with star icon
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.star, size: 12, color: Colors.white),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          // Expandable content
          if (_expanded) ...[
            const SizedBox(height: 6),
            widget.child,
          ],
        ],
      ),
    );
  }
}

// ── Card 1 content: Before You Knock ─────────────────────────────────────────
//
// Spec §4.1.1 / §5.1.1: AI-generated brief in the brand pink (#9D174D). Body
// hard-capped at 2 lines total (headline + 1 follow-up bullet) so the SK can
// absorb it in one glance. The instructional "sit with her — greet warmly"
// strip used to live here but now stands on its own as [_GreetWarmlyCard].

class _BriefingCard1Content extends StatelessWidget {
  const _BriefingCard1Content({required this.data});
  final VisitBriefingResponse data;

  static const Color _aiTextColor = AppColors.ancText;

  @override
  Widget build(BuildContext context) {
    final headline = data.briefingCard.headline.trim();
    final firstPoint = data.briefingCard.points.isEmpty
        ? null
        : data.briefingCard.points.first.trim();
    // Spec mandates a 2-line hard stop: headline (line 1) + one point (line 2).
    final aiBody = firstPoint != null && firstPoint.isNotEmpty
        ? '$headline\n$firstPoint'
        : headline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF2F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        aiBody,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: _aiTextColor,
        ),
      ),
    );
  }
}

// ── Sit With Her / Him — Greet Warmly card ────────────────────────────────
//
// Navy-filled card the SK sees right after Before You Knock. Header is the
// instruction ("👋 SIT WITH HER — GREET WARMLY"), body is the prepared
// Bangla greeting + English translation, footer is a small helper hint so
// the SK leads with empathy before tapping the AI Scribe below. When the
// briefing API returns a non-empty openingLine we surface it as the
// English translation, otherwise the localized fallback is shown.

class _GreetWarmlyCard extends StatelessWidget {
  const _GreetWarmlyCard({
    required this.isFemale,
    required this.loading,
    this.greeting,
    this.fallbackOpeningLine,
  });

  final bool isFemale;
  final bool loading;

  /// AI-generated greeting block. When null or empty, the localized static
  /// fallback is shown so the SK still has a sensible opener offline.
  final GreetingContent? greeting;

  /// Legacy fallback — the SDP opening line was used before the dedicated
  /// greeting block existed. Surface it as the English row when the new
  /// `greeting.english` field is empty.
  final String? fallbackOpeningLine;

  static const Color _navyBg = AppColors.navy;

  String _resolveBangla() {
    final g = greeting;
    if (g != null && g.bangla.trim().isNotEmpty) return g.bangla.trim();
    return SymptomPickerStrings.sitWithGreetBanglaFor(isFemale: isFemale);
  }

  String _resolveEnglish() {
    final g = greeting;
    if (g != null && g.english.trim().isNotEmpty) return g.english.trim();
    if (fallbackOpeningLine != null && fallbackOpeningLine!.trim().isNotEmpty) {
      return fallbackOpeningLine!.trim();
    }
    return SymptomPickerStrings.sitWithGreetEnglishFor(isFemale: isFemale);
  }

  @override
  Widget build(BuildContext context) {
    final bangla = _resolveBangla();
    final english = _resolveEnglish();
    final hasAi = greeting != null && !greeting!.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: _navyBg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '👋 Greet warmly',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.textOnNavy.withValues(alpha: 0.6),
              letterSpacing: 0.08 * 9,
            ),
          ),
          const SizedBox(height: 5),
          if (loading && !hasAi)
            const _GreetLoadingSkeleton()
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bangla,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnNavy,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '"$english"',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textOnNavy.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Skeleton shown inside [_GreetWarmlyCard] while the briefing API is in
/// flight. Mirrors the navy palette so it doesn't flash white.
class _GreetLoadingSkeleton extends StatelessWidget {
  const _GreetLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        Widget bar(double fraction, double height) => Container(
          width: w * fraction,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.textOnNavy.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(0.85, 18),
            const SizedBox(height: 8),
            bar(0.65, 18),
            const SizedBox(height: 12),
            bar(0.55, 12),
            const SizedBox(height: 12),
            bar(0.95, 14),
          ],
        );
      },
    );
  }
}

// ── Shared skeleton + unavailable states ─────────────────────────────────────

class _BriefingLoadingSkeleton extends StatelessWidget {
  const _BriefingLoadingSkeleton({required this.lines});
  final int lines;

  static const _fractions = [0.9, 0.75, 0.85, 0.6];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(
            lines,
            (i) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              height: 10,
              width: maxW * _fractions[i % _fractions.length],
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fallback for card 1 when AI is unavailable — shows rule-based context
/// chips. The instructional greet strip has been moved to its own card.
class _BriefingFallbackContent extends StatelessWidget {
  const _BriefingFallbackContent({required this.patientContext});
  final PatientContext patientContext;

  @override
  Widget build(BuildContext context) {
    final ctx = patientContext;
    final chips = <(String, Color)>[];
    if (ctx.isPregnant) {
      chips.add((SymptomPickerStrings.chipPregnant, AppColors.statusWarning));
    }
    if (ctx.hasKnownHypertension) {
      chips.add((SymptomPickerStrings.chipHtn, AppColors.statusCritical));
    }
    if (ctx.hasKnownDiabetes) {
      chips.add((SymptomPickerStrings.chipDm, AppColors.statusInfo));
    }
    if (ctx.isTbScreenDue) {
      chips.add((SymptomPickerStrings.chipTbDue, AppColors.statusSuccess));
    }
    if (ctx.isUnder5) {
      chips.add((SymptomPickerStrings.chipUnder5, AppColors.statusInfo));
    }
    if (chips.isEmpty) {
      chips.add((SymptomPickerStrings.chipRoutine, AppColors.textMuted));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.wifi_off, size: 12, color: AppColors.textMuted),
            SizedBox(width: 4),
            Text(
              'AI offline · local context',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: chips
              .map(
                (c) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: c.$2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.$1,
                    style: const TextStyle(
                      color: AppColors.textOnNavy,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
// ── Unified symptom section ───────────────────────────────────────────────────
//
// Inline chip grid that replaces the old text-field + modal-sheet pattern.
//
// Layout:
//   • Search bar — always visible at the top.
//   • Chip grid — shows programme-relevant ("primary") symptoms by default.
//     Once the SK types 3+ characters, ALL applicable symptoms that match
//     the query are shown so cross-programme symptoms (e.g. NCD "one-sided
//     weakness" on an ANC visit) are discoverable without crowding the default
//     view.
//   • Tapping a chip toggles selection. Selected chips are filled navy (or
//     purple for AI pre-ticks) with a leading check/star icon; unselected
//     chips are outlined.
//   • A footer hint counts selected symptoms and prompts the SK to type for
//     more when secondary symptoms exist.
//
// AI functions (ScribeController, RealtimeAsrController) are untouched —
// pre-ticked codes still flow through TriageViewModel.applyScribeTriageResult
// and render as filled purple chips in the grid.

class _UnifiedSymptomPicker extends StatefulWidget {
  const _UnifiedSymptomPicker({required this.vm});
  final TriageViewModel vm;

  @override
  State<_UnifiedSymptomPicker> createState() => _UnifiedSymptomPickerState();
}

class _UnifiedSymptomPickerState extends State<_UnifiedSymptomPicker> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// Minimum query length before secondary (cross-programme) symptoms appear.
  static const int _secondaryThreshold = 3;

  @override
  void initState() {
    super.initState();
    debugPrint('[_UnifiedSymptomPickerState] initState');
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    debugPrint('[_UnifiedSymptomPickerState] dispose');
    super.dispose();
  }

  void _toggleSymptom(String code) {
    if (widget.vm.isSelected(code)) {
      widget.vm.removeSymptom(code);
    } else {
      _addSymptomAndClearSearch(code);
    }
  }

  /// Adds [code] to the selected set and clears the search field if active.
  void _addSymptomAndClearSearch(String code) {
    widget.vm.addSymptom(code);
    if (_query.isNotEmpty) {
      _searchCtrl.clear();
      FocusScope.of(context).unfocus();
    }
  }

  static String? _sectionLabel(Programme? p) => null;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (context, _) {
        final vm = widget.vm;
        final selected = vm.selectedSymptoms;
        final isSearching = _query.isNotEmpty;

        // Search pool: full applicable vocab for cross-programme discovery
        // once the SK types 3+ chars; otherwise restricted to catalog codes.
        final searchPool = _query.length >= _secondaryThreshold
            ? vm.applicableVocabCodes
            : SymptomCatalog.all.map((s) => s.code).toList();

        // Determine which sections to show in the grid.
        // Searching → flat headerless section of matches.
        // Default → per-programme sections with headers from simpleProgrammeSections.
        final List<(String?, List<String>)> gridSections;
        if (isSearching) {
          gridSections = [
            (
              null,
              searchPool
                  .where(
                    (c) =>
                        !selected.contains(c) &&
                        TriageStrings.symptomLabel(c)
                            .toLowerCase()
                            .contains(_query),
                  )
                  .toList(),
            ),
          ];
        } else {
          gridSections = [
            for (final s in vm.simpleProgrammeSections)
              (
                _sectionLabel(s.programme),
                s.codes.where((c) => !selected.contains(c)).toList(),
              ),
          ];
        }
        final gridIsEmpty = gridSections.every((s) => s.$2.isEmpty);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Search bar ────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                key: const Key('triage_symptom_search'),
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: SymptomPickerStrings.searchSymptomsHint,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  filled: false,
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            FocusScope.of(context).unfocus();
                          },
                        )
                      : null,
                ),
                maxLines: 1,
              ),
            ),

            const SizedBox(height: 8),

            // ── Chip grid ─────────────────────────────────────────────────
            if (gridIsEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  isSearching
                      ? SymptomPickerStrings.searchNoResults
                      : SymptomPickerStrings.searchOnlyEmptyHint,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              // When searching and no match — offer to add as free-text chip.
              if (isSearching && _query.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    vm.addOtherChip(_query);
                    _searchCtrl.clear();
                    FocusScope.of(context).unfocus();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFC4B5FD)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_rounded,
                          size: 14,
                          color: Color(0xFF6B63D4),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Add "$_query" as symptom',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B63D4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ] else if (isSearching)
              // Search results — flat wrap, no headers.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                children: gridSections
                    .expand((s) => s.$2)
                    .toSet()
                    .map(
                      (code) => _PickerChip(
                        key: ValueKey('triage_chip_$code'),
                        code: code,
                        isSelected: selected.contains(code),
                        isAi: vm.isScribePreTick(code),
                        onTap: () => _toggleSymptom(code),
                      ),
                    )
                    .toList(),
              )
            else
              // Default grid — one Wrap per programme section with a label.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final section in gridSections)
                    if (section.$2.isNotEmpty) ...[
                      if (section.$1 != null && section.$1!.isNotEmpty) ...[
                        Text(
                          section.$1!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        children: section.$2
                            .map(
                              (code) => _PickerChip(
                                key: ValueKey(
                                  'triage_chip_${section.$1}_$code',
                                ),
                                code: code,
                                isSelected: selected.contains(code),
                                isAi: vm.isScribePreTick(code),
                                onTap: () => _toggleSymptom(code),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 6),
                    ],
                ],
              ),

            const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}

/// Panel of selected symptom rows shown above the chip grid.
/// Rebuilds whenever [vm] notifies (it is a [ChangeNotifier]).
class _SelectedSymptomsPanel extends StatelessWidget {
  const _SelectedSymptomsPanel({required this.vm});
  final TriageViewModel vm;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        final codes = vm.selectedSymptoms.toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final code in codes)
              _SelectedSymptomRow(
                key: ValueKey('sel_$code'),
                code: code,
                isAi: vm.isScribePreTick(code),
                onRemove: () => vm.removeSymptom(code),
              ),
          ],
        );
      },
    );
  }
}

/// Wide card row for a single selected symptom.
class _SelectedSymptomRow extends StatelessWidget {
  const _SelectedSymptomRow({
    super.key,
    required this.code,
    required this.isAi,
    required this.onRemove,
  });

  final String code;
  final bool isAi;
  final VoidCallback onRemove;

  static const _rowBg     = Color(0xFFEEF0FF);
  static const _rowBorder = Color(0xFFC4B5FD);
  static const _rowText   = Color(0xFF3D3599);
  static const _xBg       = Color(0x1AEF4444); // rgba(239,68,68,0.1)
  static const _xColor    = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final label = TriageStrings.symptomLabel(code);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: _rowBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _rowBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _rowText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Color(0x99FFFFFF), // rgba(255,255,255,0.6)
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              isAi ? 'AI detected' : 'Standard',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _rowText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _xBg,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 9, color: _xColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// A selectable symptom chip used in the inline grid on Step 1.
///
/// Unselected: white background, navy outline, navy label.
/// Selected:   navy background, white check + label.
/// AI-ticked:  purple-tinted surface + star icon.
class _PickerChip extends StatelessWidget {
  const _PickerChip({
    super.key,
    required this.code,
    required this.isSelected,
    required this.isAi,
    required this.onTap,
  });

  final String code;
  final bool isSelected;
  final bool isAi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = TriageStrings.symptomLabel(code);

    final Color bg;
    final Color borderColor;
    final Color textColor;
    if (isSelected) {
      bg = isAi ? AppColors.aiSurfaceStart : AppColors.navy;
      borderColor = isAi ? AppColors.aiBorder : AppColors.navy;
      textColor = isAi ? AppColors.aiPurple : AppColors.textOnNavy;
    } else {
      bg = Colors.white;
      borderColor = const Color(0xFFD1D5DB);
      textColor = AppColors.navy;
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${isSelected ? 'Remove' : 'Add'} $label',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Icon(
                  isAi ? Icons.auto_awesome : Icons.check_rounded,
                  size: 13,
                  color: textColor,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Inline Eligible Services Grid ────────────────────────────────────────────
//
// 8-card grid matching the wireframe (apon_sushashthya_v14.html).
// Meta-cards PW and Delivery are UI gates (not Programme enums) that lock/unlock
// ANC and PNC respectively. Under-5 patients skip this widget entirely.

enum _ServiceCardKind { programme, pw, delivery, general, rmnch, vaccination }


class _ServiceCardDef {
  const _ServiceCardDef({
    required this.kind,
    required this.emoji,
    required this.label,
    this.programme,
  });

  final _ServiceCardKind kind;
  final Programme? programme;
  final String emoji;
  final String label;

  bool get isPW => kind == _ServiceCardKind.pw;
  bool get isDelivery => kind == _ServiceCardKind.delivery;
  bool get isRMNCH => kind == _ServiceCardKind.rmnch;
  bool get isVaccination => kind == _ServiceCardKind.vaccination;
}

// Card order matches the Eligible Services wireframe (apon_sushashthya_v14):
// Row 1: PW, ANC, Pregnancy Outcome
// Row 2: PNC, FP, NCD
// Row 3: TB, Eye care
// Under-5 row: Vaccination, Child Health
const _kAllServiceCards = [
  _ServiceCardDef(kind: _ServiceCardKind.pw,          emoji: '🤰', label: 'PW'),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '🏥', label: 'ANC',               programme: Programme.anc),
  _ServiceCardDef(kind: _ServiceCardKind.delivery,    emoji: '🚼', label: 'Pregnancy Outcome'),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '👶', label: 'PNC',               programme: Programme.pnc),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '🌸', label: 'FP',                programme: Programme.familyPlanning),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '💊', label: 'NCD',               programme: Programme.ncd),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '👁️', label: 'Eye Care',          programme: Programme.eyeCare),
  // Under-5 cards — shown only when ctx.isUnder5
  _ServiceCardDef(kind: _ServiceCardKind.vaccination, emoji: '💉', label: 'Vaccination'),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '🧒', label: 'Child Health',      programme: Programme.imci),
];

class _InlineServiceSelector extends StatelessWidget {
  const _InlineServiceSelector({
    required this.patientContext,
    required this.selectedProgrammes,
    required this.pathwayProgrammes,
    required this.enrolledProgrammes,
    required this.isPW,
    required this.isDelivery,
    required this.ancVisitedToday,
    required this.onProgrammeToggle,
    required this.onPWToggle,
    required this.onDeliveryToggle,
    required this.onVaccination,
  });

  final PatientContext patientContext;
  final Set<Programme> selectedProgrammes;
  final Set<Programme> pathwayProgrammes;

  /// Programmes the patient is already enrolled in from past visits.
  /// Cards show an "Enrolled" badge; they remain selectable for this visit.
  final Set<Programme> enrolledProgrammes;

  final bool isPW;
  final bool isDelivery;
  final bool ancVisitedToday;
  final void Function(Programme programme, bool selected) onProgrammeToggle;
  final ValueChanged<bool> onPWToggle;
  final ValueChanged<bool> onDeliveryToggle;

  /// Called when SK taps the Vaccination card (under-5 only).
  final VoidCallback onVaccination;

  List<_ServiceCardDef> _visibleCards() {
    final ctx = patientContext;
    return _kAllServiceCards.where((c) {
      switch (c.kind) {
        case _ServiceCardKind.vaccination:
          return ctx.isUnder5;
        case _ServiceCardKind.pw:
        case _ServiceCardKind.delivery:
          return ctx.isFemale && ctx.ageYears >= 15 && !ctx.isUnder5;
        case _ServiceCardKind.programme:
          final p = c.programme!;
          if (p == Programme.imci) return ctx.isUnder5;
          if (ctx.isUnder5) return false;
          if (p == Programme.anc || p == Programme.pnc) {
            return ctx.isFemale && ctx.ageYears >= 15;
          }
          if (p == Programme.familyPlanning) {
            return ctx.isFemale && ctx.ageYears >= 15;
          }
          return ctx.ageYears >= 15;
        case _ServiceCardKind.rmnch:
        case _ServiceCardKind.general:
          return false;
      }
    }).toList();
  }

  String _enrolledLabel(_ServiceCardDef card) {
    if (card.isPW) return 'Registered';
    switch (card.programme) {
      case Programme.anc:
      case Programme.pnc:
        return 'Completed visit';
      default:
        return TriageStrings.enrolledBadge;
    }
  }

  String _cardLabel(_ServiceCardDef card) {
    if (card.isRMNCH) {
      final ctx = patientContext;
      return (ctx.isFemale && ctx.isPregnant && !ctx.isPostpartum)
          ? TriageStrings.pregnancyOutcomeChip
          : 'PNC';
    }
    if (card.isDelivery) return TriageStrings.pregnancyOutcomeChip;
    return card.label;
  }

  bool _isLocked(_ServiceCardDef card) {
    if (card.isVaccination) return false;
    if (card.programme == Programme.imci) return false;
    final ctx = patientContext;
    final pregnant = ctx.isPregnant && !ctx.isPostpartum;
    if (card.isPW) return isDelivery || !pregnant;
    if (card.programme == Programme.anc) {
      // ANC requires PW registration first; also blocked if ANC already done today.
      return !isPW || isDelivery || !pregnant || ancVisitedToday;
    }
    if (card.isDelivery) return !pregnant;
    if (card.programme == Programme.pnc) return !ctx.isPostpartum;
    // FP is contraindicated during active pregnancy; available post-delivery.
    if (card.programme == Programme.familyPlanning) return pregnant;
    return false;
  }

  bool _isCardSelected(_ServiceCardDef card) {
    if (card.isVaccination) return true;
    if (card.isPW) return isPW && !isDelivery;
    if (card.isDelivery) return isDelivery;
    if (card.isRMNCH) {
      final ctx = patientContext;
      return (ctx.isFemale && ctx.isPregnant && !ctx.isPostpartum)
          ? isDelivery
          : selectedProgrammes.contains(Programme.pnc);
    }
    if (card.programme != null) return selectedProgrammes.contains(card.programme);
    return false;
  }

  void _handleTap(BuildContext context, _ServiceCardDef card) {
    if (card.isVaccination) {
      onVaccination();
      return;
    }
    final alreadySelected = _isCardSelected(card);
    if (_isLocked(card) && !alreadySelected) {
      final hint = isDelivery
          ? TriageStrings.ancDeliveryConflictHint
          : TriageStrings.pwHint;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(hint),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    if (card.isPW) {
      onPWToggle(!isPW);
    } else if (card.isDelivery) {
      // Pregnancy Outcome visit — clears ANC/PW; other services stay on.
      onDeliveryToggle(!alreadySelected);
    } else if (card.programme != null) {
      onProgrammeToggle(
        card.programme!,
        !selectedProgrammes.contains(card.programme),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = _visibleCards();
    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              TriageStrings.eligibleServicesHeader,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                TriageStrings.eligibleServicesTag,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B63D4),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 9,
          mainAxisSpacing: 9,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          childAspectRatio: 1.05,
          children: cards
              .map((c) => _ServiceTile(
                    def: c,
                    label: _cardLabel(c),
                    isSelected: _isCardSelected(c),
                    isLocked: _isLocked(c),
                    isEnrolled: (c.programme != null &&
                            enrolledProgrammes.contains(c.programme)) ||
                        (c.isPW && enrolledProgrammes.contains(Programme.anc)),
                    enrolledLabel: _enrolledLabel(c),
                    isPathwaySuggested: c.programme != null &&
                        pathwayProgrammes.contains(c.programme),
                    onTap: () => _handleTap(context, c),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.def,
    required this.label,
    required this.isSelected,
    required this.isLocked,
    required this.isEnrolled,
    required this.enrolledLabel,
    required this.isPathwaySuggested,
    required this.onTap,
  });

  final _ServiceCardDef def;
  final String label;
  final bool isSelected;
  final bool isLocked;

  /// Patient is already enrolled in this programme from past visits.
  /// Shows an programme-specific badge; the card remains selectable for this visit.
  final bool isEnrolled;

  /// Badge text when [isEnrolled] is true. Defaults to "Enrolled" for most
  /// programmes; ANC/PNC use "Completed ANC"/"Completed PNC" etc.
  final String enrolledLabel;

  final bool isPathwaySuggested;
  final VoidCallback onTap;

  static const _enrolledBadgeBg = Color(0xFFE5E7EB);
  static const _enrolledBadgeText = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final Color bg = Colors.white;
    final Color borderColor =
        isSelected ? AppColors.navy : const Color(0xFFE5E7EB);
    final double borderWidth = isSelected ? 1.5 : 1;
    final Color labelColor = isLocked
        ? AppColors.navy.withValues(alpha: 0.55)
        : AppColors.navy;

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: !isLocked,
      label: isEnrolled
          ? TriageStrings.enrolledProgrammeA11y(label)
          : (isSelected
              ? TriageStrings.deselectProgrammeA11y(label)
              : TriageStrings.selectProgrammeA11y(label)),
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: isLocked ? 0.45 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              children: [
                // ✦ sparkle — pathway-engine suggested
                if (isPathwaySuggested && isSelected)
                  Positioned(
                    top: 5,
                    left: 6,
                    child: Text(
                      '✦',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.navy.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                // Checkmark — follows visit selection, not enrolment alone
                Positioned(
                  top: 5,
                  right: 6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? AppColors.navy : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.navy
                            : const Color(0xFFD1D5DB),
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 10,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                // Emoji + label + enrolled badge
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(def.emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: labelColor,
                        ),
                      ),
                      if (isEnrolled) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _enrolledBadgeBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            enrolledLabel,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: _enrolledBadgeText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
