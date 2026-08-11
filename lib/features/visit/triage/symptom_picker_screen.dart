import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/clinical/ai_context_fields.dart';
import '../../../core/clinical/briefing_rules/briefing_findings_aggregator.dart';
import '../../../core/clinical/service_eligibility.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/preferences/ai_feature_toggles_notifier.dart';
import '../../../core/db/assessment_dao.dart';
import '../../../core/db/encounter_dao.dart';
import '../../../core/db/immunisation_dao.dart';
import '../../../core/db/local_assessment_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/models/programme.dart';
import '../../../core/risk/pregnancy_cohort_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/db/patient_programmes_dao.dart';
import '../../../core/db/pregnancy_episode_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../../core/time/calendar_day.dart';
import '../../patient/followup_repository.dart';
import '../../patient/vitals_repository.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/widgets/ai_scribe_banner.dart';
import '../assessment_repository.dart';
import '../briefing/briefing_models.dart';
import '../briefing/visit_briefing_repository.dart';
import '../pathway/pathway_engine.dart';
import 'patient_context_builder.dart';
import 'programme_grid_sync.dart';
import 'service_selection_resolver.dart';
import 'symptom_catalog.dart';
import 'unified_symptom_catalog.dart';
import 'visit_step_header.dart';
import 'triage_view_model.dart';
import '../../../core/i18n/app_date_format.dart';

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
    this.onEnrolledProgrammesResolved,
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
  /// child visits (young child) skip the grid and use the vaccination path.
  final ValueChanged<Set<Programme>>? onProgrammesSelected;

  /// Fired alongside [onProgrammesSelected] with the patient's enrolled
  /// programmes (already loaded via [PatientContext] for this screen) so
  /// Step 2 can order sections enrolled-first without a second DB read.
  final ValueChanged<Set<Programme>>? onEnrolledProgrammesResolved;

  /// Fired on every service-card toggle so the host can update the visit
  /// header badge in real time without waiting for the SK to tap Continue.
  final ValueChanged<Set<Programme>>? onProgrammesLive;

  /// Fired just before [onAdvance] with whether the SK confirmed a delivery
  /// visit. When true, the host includes the pregnancyOutcome form sections.
  final ValueChanged<bool>? onDeliverySelected;

  @override
  State<SymptomPickerScreen> createState() => _SymptomPickerScreenState();
}

/// Result of checking whether a new ANC visit falls within the risk-based
/// revisit interval — see [_SymptomPickerScreenState._computeAncRevisitStatus].
class _AncRevisitStatus {
  const _AncRevisitStatus({
    required this.tooSoon,
    this.lastVisitMs,
    this.nextDueMs,
    this.highRisk = false,
    this.revisitDays,
  });

  static const unknown = _AncRevisitStatus(tooSoon: false);

  /// True when a new ANC visit is currently blocked by the revisit interval.
  final bool tooSoon;

  /// Epoch ms of the last ANC visit, when known.
  final int? lastVisitMs;

  /// Epoch ms of next ANC due — from latest assessment `nextVisitDate` when
  /// stamped, otherwise computed as last visit + [revisitDays].
  final int? nextDueMs;

  /// Whether that last visit was flagged high-risk.
  final bool highRisk;

  /// The interval applied — 1 day (high-risk) or 15 days (normal), null when
  /// [lastVisitMs] is unavailable and this fell back to [_ancVisitedToday].
  final int? revisitDays;
}

class _SymptomPickerScreenState extends State<SymptomPickerScreen> {
  TriageViewModel? _viewModel;
  PatientContext? _patientContext;
  bool _isLoading = true;
  String? _error;

  /// Canonical `patients.id` for this visit. The household screens route with
  /// the server-assigned `members.patient_id`, which [PatientContextBuilder]
  /// remaps onto the local key every other table is keyed by. Falls back to
  /// the routed id until the context has loaded.
  String get _patientId => _patientContext?.patientId ?? widget.patientId;

  VisitBriefingResponse? _briefingData;
  bool _briefingLoading = true;

  /// Programmes the SK has selected in the inline service grid.
  /// Initialized from the pathway engine on load; SK can toggle freely.
  final Set<Programme> _selectedProgrammes = {};

  /// Subset of [_selectedProgrammes] that were pre-activated by the pathway
  /// engine — rendered with the ✦ sparkle in the card.
  final Set<Programme> _pathwayActivatedProgrammes = {};

  /// Programmes the SK explicitly turned off this visit. Pathway-engine and
  /// background AI syncs must not resurrect these. However, an explicit
  /// symptom selection that directly maps to a dismissed programme lifts the
  /// dismissal (the SK is signalling clinical intent).
  final Set<Programme> _skDismissedProgrammes = {};

  /// Shadow of [TriageViewModel.selectedSymptoms] from the last sync cycle.
  /// Used to detect newly added symptoms so we can lift dismissals for their
  /// catalogue-mapped programmes before re-running the service grid sync.
  Set<String> _lastKnownSymptoms = {};

  /// PW meta-flag — gates ANC. Auto-true when patient already has PW/ANC registered.
  bool _isPW = false;

  /// Delivery meta-flag — gates PNC. Auto-true when patient is postpartum.
  bool _isDelivery = false;

  /// True when patient already has an ANC assessment recorded today — blocks
  /// a second ANC visit on the same calendar day.
  bool _ancVisitedToday = false;

  /// The patient's currently open pregnancy episode, if any — locks the PW
  /// card (already registered, re-registration would only be silently
  /// dropped by `ServiceSelectionResolver` at Continue-time) and shows its
  /// LMP/EDD on the card. Null for a patient with no open episode.
  PregnancyEpisodeRow? _openPregnancyEpisode;

  /// Whether ANC is currently within its risk-based revisit interval — locks
  /// the ANC card and shows the last-visit date (see
  /// [_computeAncRevisitStatus]) so the grid always matches what Continue
  /// would actually do.
  _AncRevisitStatus _ancRevisitStatus = _AncRevisitStatus.unknown;

  /// Young-child only: vaccination is always included for a child visit —
  /// Step 2 of the visit flow shows the vaccination timeline regardless, so
  /// this was never really a user choice. Forced true whenever the card
  /// would render (the card itself is only ever shown for young-child
  /// patients); the getter naturally evaluates false otherwise, for whom the
  /// card never renders and this value has no effect.
  bool get _vaccinationSelected => _patientContext?.isYoungChild ?? false;

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
    final episodeDao = context.read<PregnancyEpisodeDao>();

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
          .hasAncAssessmentTodayForPatient(ctx.patientId);
      // Whether this patient currently has an open pregnancy episode — locks
      // the PW card (see _InlineServiceSelector._isLocked) so the SK can't
      // select a re-registration that ServiceSelectionResolver would only
      // silently drop later. Deliberately NOT used to gate _isPW/ANC below —
      // ANC must stay selectable for an already-pregnant woman.
      final openEpisode = await episodeDao.openEpisodeFor(ctx.patientId);
      final mostRecentEpisode = await episodeDao.mostRecentFor(ctx.patientId);
      debugPrint(
        '[PwLockDebug] patientId=${ctx.patientId} isPw=$isPw '
        'activeProgrammes=${ctx.activeProgrammes} isPregnant=${ctx.isPregnant} '
        'openEpisode=${openEpisode?.id} '
        'mostRecentEpisode=${mostRecentEpisode?.id} '
        'mostRecentClosedAt=${mostRecentEpisode?.closedAt} '
        'mostRecentLmp=${mostRecentEpisode?.obstetric.lmpDate}',
      );
      // Risk-based ANC revisit interval (1 day high-risk / 15 days normal) —
      // locks the ANC card so the grid matches what Continue would actually
      // do, instead of just the same-day check above. fallbackTooSoon uses
      // the freshly computed ancToday, not the (still stale, pre-setState)
      // _ancVisitedToday field.
      final ancRevisitStatus = await _computeAncRevisitStatus(
        patientId: ctx.patientId,
        fallbackTooSoon: ancToday,
      );
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
        if (openEpisode != null) {
          // Already registered — PW is locked in the grid (see
          // _InlineServiceSelector._isLocked) so this should rarely matter,
          // but keeps _selectedProgrammes honest if enrolledSeed pre-ticked
          // it. Does NOT touch _isPW — ANC's own lock reads that flag
          // separately and must stay unlocked for an already-pregnant woman.
          _selectedProgrammes.remove(Programme.pw);
        }
        if (ancRevisitStatus.tooSoon) {
          // Within the revisit interval — ANC is locked in the grid (see
          // _InlineServiceSelector._isLocked), keeps _selectedProgrammes
          // honest if enrolledSeed pre-ticked it.
          _selectedProgrammes.remove(Programme.anc);
        }
        _pathwayActivatedProgrammes
          ..clear()
          ..addAll(pathwaySet);
        _isPW = isPw;
        _isDelivery = false;
        _ancVisitedToday = ancToday;
        _ancRevisitStatus = ancRevisitStatus;
        _openPregnancyEpisode = openEpisode;
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
        patientCtx.patientId,
        limit: 5,
      );
      final followUps = await followUpRepo.openForPatientLocal(
        patientCtx.patientId,
      );

      final vitalsMap = buildRecentVitalsSummary(visitsByVisit);
      final followUpSummaries = buildFollowUpSummaries(followUps);

      final clinicalFindings = await BriefingFindingsAggregator.build(
        patientId: patientCtx.patientId,
        patientCtx: patientCtx,
        selectedProgrammes: _selectedProgrammes,
        assessmentDao: context.read<LocalAssessmentDao>(),
        historyAssessmentDao: context.read<AssessmentDao>(),
        followUpRepo: followUpRepo,
        patientDao: context.read<PatientDao>(),
        immunisationDao: context.read<ImmunisationDao>(),
      );

      final lastVisit = visitsByVisit.isNotEmpty ? visitsByVisit.first : null;

      final request = <String, dynamic>{
        'patientId': patientCtx.patientId,
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
        'clinicalFindings': clinicalFindings.map((f) => f.toJson()).toList(),
        if (patientCtx.gestationalWeeks != null)
          'gestationalWeeks': patientCtx.gestationalWeeks,
      };

      debugPrint('[DebugTrace] briefing request patientId=${request['patientId']} '
          'body=${jsonEncode(request)}');
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
      if (e is DioException) {
        debugPrint('[DebugTrace] briefing error status=${e.response?.statusCode} '
            'data=${e.response?.data}');
      }
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
        // Don't resurrect ANC here if it's within its revisit interval —
        // otherwise toggling PW off/on would silently re-add an ANC
        // selection that Continue would only drop again.
        if ((_patientContext!.activeProgrammes.contains(Programme.anc) ||
                _pathwayActivatedProgrammes.contains(Programme.anc)) &&
            !_ancRevisitStatus.tooSoon) {
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
  /// whenever symptoms change (AI Scribe pre-tick or manual selection).
  ///
  /// Two complementary sources feed auto-selection:
  ///   1. PathwayEngine ([vm.allPathways]) — WHO-derived rule activations.
  ///   2. [UnifiedSymptomCatalog] direct mapping — each [UnifiedSymptomDef]
  ///      declares the programmes it belongs to; selecting a symptom
  ///      immediately surfaces all relevant services regardless of whether
  ///      a PathwayEngine rule fires for that exact symptom combination.
  ///
  /// Dismissal lift: when a symptom is *newly added* (not in [_lastKnownSymptoms]),
  /// its catalogue-mapped programmes are removed from [_skDismissedProgrammes]
  /// before the sync runs. Explicit symptom selection is a clinical signal that
  /// overrides a prior card dismissal; background pathway/AI refreshes do not.
  void _syncPathwaysToServiceGrid() {
    if (!mounted) return;
    final vm = _viewModel;
    if (vm == null) return;

    final currentSymptoms = vm.selectedSymptoms;

    // Lift dismissal for programmes mapped to newly added symptoms.
    // Only additions trigger this — removals leave dismissed state intact.
    final newlyAdded = currentSymptoms.difference(_lastKnownSymptoms);
    for (final code in newlyAdded) {
      final def = UnifiedSymptomCatalog.byCode(code);
      if (def != null) _skDismissedProgrammes.removeAll(def.programmes);
    }
    _lastKnownSymptoms = Set.from(currentSymptoms);

    // Source 1: rule-engine activations.
    final activated = vm.allPathways.map((p) => p.programme).toSet();

    // Source 2: catalogue direct symptom→programme mapping.
    // Each UnifiedSymptomDef.programmes names every service that symptom
    // belongs to, providing finer-grained auto-selection than the rule engine.
    // See ProgrammeGridSync.catalogProgrammesFor for why imci/epi are gated
    // on the patient actually being a young child.
    final isYoungChild = _patientContext?.isYoungChild == true;
    for (final code in currentSymptoms) {
      final def = UnifiedSymptomCatalog.byCode(code);
      if (def == null) continue;
      activated.addAll(ProgrammeGridSync.catalogProgrammesFor(
        def.programmes,
        isChildVisitEligible: isYoungChild,
      ));
    }

    // Exclude programmes currently locked in the grid — a newly-selected
    // symptom must not silently resurrect ANC (within its revisit interval)
    // or PW (already registered) after they were stripped/locked at load.
    final unseen = ProgrammeGridSync.additionsFromPathways(
      activated: activated,
      selected: _selectedProgrammes,
      dismissedBySk: _skDismissedProgrammes,
    ).where((p) {
      if (p == Programme.anc && _ancRevisitStatus.tooSoon) return false;
      if (p == Programme.pw && _openPregnancyEpisode != null) return false;
      return true;
    }).toSet();
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
    patientDao.byAnyId(_patientId).then((patient) {
      if (!mounted) return;
      context.push(
        '/patients/$_patientId/immunisation',
        extra: <String, dynamic>{
          'patientName': widget.patientName,
          if (patient?.dob != null) 'dob': patient!.dob,
          if (widget.memberId != null) 'memberId': widget.memberId,
          // householdMemberLocalId unavailable on this screen; defaults to 0
        },
      );
    });
  }

  /// Advances to the vaccination visit step.
  ///
  /// In embedded mode (inside VisitFlowScreen): fires [onAdvance] with
  /// vaccinationOnly so the IMCI form is skipped.
  /// In standalone mode: pushes the immunisation timeline route directly.
  void _onVaccination() {
    debugPrint('[_SymptomPickerScreenState] _onVaccination');
    final vm = _viewModel;
    if (vm == null) return;
    if (widget.onAdvance != null) {
      // vaccinationOnly: true so auto-activated IMCI pathway does not trigger
      // the child health form — the SK chose vaccination only.
      _doAdvance(vm, vaccinationOnly: true);
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

    _doAdvance(vm, vaccinationSelected: _vaccinationSelected);
  }

  /// [vaccinationOnly] suppresses IMCI — vaccination card tap = vaccination-only.
  /// [vaccinationSelected] adds Programme.epi so VisitFlowScreen can gate the
  /// vaccination step (skipped when only child health is selected).
  Future<void> _doAdvance(
    TriageViewModel vm, {
    bool vaccinationOnly = false,
    bool vaccinationSelected = false,
  }) async {
    // If the rule engine produced no pathways but the patient has enrolled
    // programmes, synthesize a pathway from enrolment so the form always
    // opens the correct section (guards against sex/data quality issues
    // that cause demographic gates to fail — see issue #127).
    var pathways = vm.activatedPathways;
    if (pathways.isEmpty && _patientContext != null) {
      pathways = _patientContext!.activeProgrammes
          .where(ServiceSelectionResolver.canonicalPriority.containsKey)
          .map(
            (p) => ActivatedPathway(
              programme: p,
              priority: ServiceSelectionResolver.canonicalPriority[p]!,
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
        final assessments = await dao.getByPatientId(_patientId);
        if (assessments.isNotEmpty) {
          final lastType = assessments.first.assessmentType;
          final programme = Programme.fromTag(lastType);
          if (programme != null) {
            pathways = [
              ActivatedPathway(
                programme: programme,
                priority:
                    ServiceSelectionResolver.canonicalPriority[programme] ??
                        50,
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
      // Always report the SK's confirmed programme set — including young-child
      // visits so VisitFlowScreen knows whether Child Health (IMCI) was
      // explicitly selected and can show the IMCI form after vaccination.
      // vaccinationOnly = true clears programmes so auto-activated pathways
      // (e.g. EPI_DUE) don't smuggle IMCI into a vaccination-only visit.
      final Set<Programme> programmes;
      if (vaccinationOnly) {
        programmes = const <Programme>{};
      } else {
        final base = Set<Programme>.from(_selectedProgrammes);
        // Include epi so VisitFlowScreen knows vaccination was selected;
        // without it the vaccination step is skipped for IMCI-only visits.
        if (vaccinationSelected) base.add(Programme.epi);
        programmes = base;
      }

      // Finalize the selection through the single service-selection choke
      // point — all business-rule gating (PW-once-only, ANC-blocked-
      // postpartum/revisit-too-soon, PW-auto-add) runs here, before the SK
      // ever leaves Step 1. Short-circuit the extra DAO reads unless the
      // selection actually touches PW/ANC.
      final needsPwCheck = programmes.contains(Programme.pw) ||
          programmes.contains(Programme.anc);
      final pwBlocked =
          needsPwCheck ? await _isPwRegistrationBlocked() : false;
      final ancRevisitBlocked = programmes.contains(Programme.anc)
          ? await _isAncRevisitTooSoon()
          : false;
      if (!mounted) return;

      final result = ServiceSelectionResolver.finalize(
        selected: programmes,
        pwRegistrationBlocked: pwBlocked,
        isPostpartum: _patientContext?.isPostpartum ?? false,
        ancRevisitBlocked: ancRevisitBlocked,
        isDeliveryVisit: _isDelivery,
        pncDismissedBySk: _skDismissedProgrammes.contains(Programme.pnc),
      );

      if (result.blockedReason != null) {
        await _showAncBlockedDialog(result.blockedReason!);
        if (!mounted) return;
        // Stay on Step 1 with the corrected selection applied — the SK's
        // symptom picks and other selected services survive; they can
        // review/adjust and tap Continue again.
        setState(() {
          _selectedProgrammes
            ..clear()
            ..addAll(result.programmes);
          _skDismissedProgrammes.add(Programme.anc);
        });
        _fireProgrammesLive();
        return;
      }

      if (result.silentlyEmptied) {
        // PW (or an excluded programme) was the only selection and got
        // dropped — hint instead of a dialog, stay on Step 1.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(AppStrings.pwAlreadyEnrolledMessage),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ));
        setState(() {
          _selectedProgrammes.clear();
          _skDismissedProgrammes.add(Programme.pw);
        });
        _fireProgrammesLive();
        return;
      }

      widget.onProgrammesSelected?.call(Set.unmodifiable(result.programmes));
      widget.onEnrolledProgrammesResolved?.call(
        Set.unmodifiable(_patientContext?.activeProgrammes ?? const {}),
      );
      widget.onDeliverySelected?.call(_isDelivery);
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

  /// Whether starting a new PW registration should be blocked because this
  /// pregnancy is already on file — now a direct query against real episode
  /// boundaries instead of guessing from a singleton's stale fields. Blocked
  /// if there's a currently open episode (already pregnant — one open
  /// episode at a time), or if the most recent episode closed within the
  /// 42-day postnatal window ([PregnancyCohortRules.isPostnatal]).
  ///
  /// This replaces the old check based on `PregnancySnapshotRow.lmpDate !=
  /// null` — a field that, once ever set, was never cleared, so it blocked
  /// re-registration forever after any historical pregnancy. That was the
  /// bug preventing a woman from ever registering a second pregnancy.
  Future<bool> _isPwRegistrationBlocked() async {
    final ctx = _patientContext;
    if (ctx == null) return false;
    try {
      final episodeDao = context.read<PregnancyEpisodeDao>();
      final open = await episodeDao.openEpisodeFor(_patientId);
      if (open != null) return true;
      final recent = await episodeDao.mostRecentFor(_patientId);
      return PregnancyCohortRules.isPostnatal(recent?.obstetric);
    } catch (e) {
      debugPrint('[SymptomPicker] pregnancy episode lookup failed: $e');
      return false;
    }
  }

  /// Whether a new ANC visit is too soon after the last one, and the
  /// context behind that decision (last visit date, risk level, the
  /// interval applied) — a risk-based revisit interval (1 day if the last
  /// visit was high-risk, else 15 days), ported from Android Spice's
  /// `isAncMenuDisabledByLastVisit` / `getAncMenuRevisitDays`. Falls back to
  /// [fallbackTooSoon] (the same-calendar-day check) when no dated snapshot
  /// is available yet (e.g. sync hasn't landed a `PregnancySnapshotDao` row).
  ///
  /// Shared by the Continue-time gate ([_isAncRevisitTooSoon]) and the
  /// Eligible Services grid (locks the ANC card, shows why) so the two can
  /// never drift from each other. [patientId] and [fallbackTooSoon] are
  /// explicit parameters rather than reading [_patientId]/[_ancVisitedToday]
  /// internally, since the grid calls this *during* `_loadPatientContext`,
  /// before those fields are updated for the current load.
  Future<_AncRevisitStatus> _computeAncRevisitStatus({
    required String patientId,
    required bool fallbackTooSoon,
  }) async {
    try {
      // Prefer latest ANC assessment (local + synced history) for last visit
      // and stamped nextVisitDate — same source as Care History / summary.
      final schedule = await context
          .read<AssessmentRepository>()
          .latestAncVisitSchedule(patientId, alsoId: widget.memberId);

      final snapshots = context.read<PregnancySnapshotDao>();
      final snapshot = await snapshots.byPatientOrMember(
        patientId,
        memberId: widget.memberId,
      );
      final lastVisitMs = schedule?.lastVisitAt.millisecondsSinceEpoch ??
          snapshot?.lastAncVisitDateMs;
      if (lastVisitMs == null) {
        debugPrint(
          '[AncRevisitDebug] READ patientId=$patientId memberId=${widget.memberId} '
          'scheduleFound=${schedule != null} snapshotFound=${snapshot != null} '
          'lastAncVisitDateMs=null → fallbackTooSoon=$fallbackTooSoon',
        );
        return _AncRevisitStatus(tooSoon: fallbackTooSoon);
      }
      final highRisk = snapshot?.facts.highRiskPregnantWoman ?? false;
      final revisitDays = highRisk ? 1 : 15;
      final stampedNext = schedule?.nextDueAt;
      final int nextDueMs;
      final bool tooSoon;
      if (stampedNext != null) {
        nextDueMs = CalendarDay.startOf(stampedNext).millisecondsSinceEpoch;
        // Locked until the calendar due day arrives (daysToDue > 0).
        tooSoon = CalendarDay.daysBetween(DateTime.now(), stampedNext) > 0;
      } else {
        nextDueMs =
            lastVisitMs + Duration(days: revisitDays).inMilliseconds;
        final daysSince = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(lastVisitMs))
            .inDays;
        tooSoon = daysSince < revisitDays;
      }
      debugPrint(
        '[AncRevisitDebug] READ patientId=$patientId memberId=${widget.memberId} '
        'lastVisitMs=$lastVisitMs nextDueMs=$nextDueMs '
        'stampedNext=${stampedNext != null} highRisk=$highRisk '
        'revisitDays=$revisitDays → tooSoon=$tooSoon',
      );
      return _AncRevisitStatus(
        tooSoon: tooSoon,
        lastVisitMs: lastVisitMs,
        nextDueMs: nextDueMs,
        highRisk: highRisk,
        revisitDays: revisitDays,
      );
    } catch (e) {
      debugPrint('[SymptomPicker] ANC revisit-interval lookup failed: $e');
      return _AncRevisitStatus(tooSoon: fallbackTooSoon);
    }
  }

  Future<bool> _isAncRevisitTooSoon() async => (await _computeAncRevisitStatus(
        patientId: _patientId,
        fallbackTooSoon: _ancVisitedToday,
      ))
          .tooSoon;

  /// Shows the ANC-blocked dialog, relocated here from
  /// `_Step2ProgrammesThenFormState._showAncBlockedDialog` — Step 2 no
  /// longer re-derives or re-gates the selection, so this only ever fires
  /// from Step 1 now.
  Future<void> _showAncBlockedDialog(ServiceSelectionBlockReason reason) {
    final String title;
    final String message;
    switch (reason) {
      case ServiceSelectionBlockReason.ancBlockedPostpartum:
        title = AppStrings.ancBlockedPostpartumTitle;
        message = AppStrings.ancBlockedPostpartumMessage;
      case ServiceSelectionBlockReason.ancBlockedRevisit:
        title = AppStrings.ancBlockedDuplicateTitle;
        message = AppStrings.ancBlockedDuplicateMessage;
    }
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(ComposerStrings.dismissOkButton),
          ),
        ],
      ),
    );
  }

  void _navigateToForm(List<ActivatedPathway> pathways) {
    debugPrint('[_SymptomPickerScreenState] _navigateToForm pathways=${pathways}');
    final origin = widget.origin;
    final originParam = origin != null ? '?origin=$origin' : '';

    context.go(
      '/patients/visit/${widget.encounterId}/form$originParam',
      extra: {
        'patientId': _patientId,
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
                      selectedProgrammes: _selectedProgrammes,
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
                        patientId: _patientId,
                        isFemale:
                            vm.patientContext.sex == Sex.female,
                        tapStartsLiveAsr: true,
                        symptomVocab: vm.applicableVocabCodes,
                        onReviewReady: (ctrl) {
                          final result = ctrl.session.triageExtractionResult;
                          if (result != null) {
                            vm.applyScribeTriageResult(result);
                          }
                          ctrl.resetSession();
                        },
                        onLiveSymptomCodes: (codes, transcript) {
                          if (codes.isEmpty) return;
                          vm.applyScribeTriageResult(
                            TriageExtractionResult(
                              symptomCodes: [
                                for (final entry in codes.hits.entries)
                                  AIExtractedField(
                                    fieldId: entry.key,
                                    value: true,
                                    confidence: entry.value.confidence,
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
                // Young child: Vaccination + Child Health cards only.
                // Everyone else: full programme card set.
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
                        ancRevisitStatus: _ancRevisitStatus,
                        openPregnancyEpisode: _openPregnancyEpisode,
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
                        vaccinationSelected: _vaccinationSelected,
                        vaccinationLocked: widget.onAdvance != null,
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
                        // ── Young-child CTA — driven by vaccination + child-health selection
                        if (_patientContext!.isYoungChild) ...[
                          const SizedBox(height: 4),
                          Builder(builder: (context) {
                            final imciSelected = _selectedProgrammes
                                .contains(Programme.imci);
                            final bothSelected =
                                _vaccinationSelected && imciSelected;
                            final neitherSelected =
                                !_vaccinationSelected && !imciSelected;
                            final label = bothSelected || imciSelected
                                ? SymptomPickerStrings.ctaStartCheckup
                                : ChildAssessmentStrings.vaccinationCta;
                            final VoidCallback? onPressed = neitherSelected
                                ? null
                                : (_vaccinationSelected && !imciSelected
                                    ? _onVaccination
                                    : _onContinue);
                            return SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: onPressed,
                                style: FilledButton.styleFrom(
                                  backgroundColor: neitherSelected
                                      ? AppColors.pink.withValues(alpha: 0.4)
                                      : AppColors.pink,
                                  foregroundColor: AppColors.textOnNavy,
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            );
                          }),
                        ],

                        // ── Start Checkup button (non-young-child only) ────
                        if (!(_patientContext!.isYoungChild)) ...[
                          const SizedBox(height: 4),
                          Builder(builder: (context) {
                            final eligible = hasAnyEligibleProgramme(
                                ageYears: _patientContext!.ageYears);
                            return SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () {
                                  if (!eligible) {
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(SnackBar(
                                        content:
                                            Text(EnrollStrings.noProgrammes),
                                        duration:
                                            const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                      ));
                                    return;
                                  }
                                  _onContinue();
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: eligible
                                      ? AppColors.pink
                                      : AppColors.pink.withValues(alpha: 0.4),
                                  foregroundColor: AppColors.textOnNavy,
                                ),
                                child: Text(
                                    SymptomPickerStrings.ctaStartCheckup),
                              ),
                            );
                          }),
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
    required this.selectedProgrammes,
  });

  final bool briefingLoading;
  final VisitBriefingResponse? briefingData;
  final PatientContext patientContext;

  /// The SK's currently-ticked service cards — lets the Greet Warmly
  /// fallback ask visit-relevant questions (e.g. only ask about fetal
  /// movement on an ANC visit, not for every adult woman).
  final Set<Programme> selectedProgrammes;

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
        // greeting in the SK's app language plus a helper hint that primes
        // the SK before they tap the AI Scribe below. Under-5 patients
        // can't answer for themselves, so the card addresses the guardian.
        GreetWarmlyCard(
          isFemale: isFemale,
          loading: briefingLoading,
          // Deliberately not isYoungChild (RMNCH childhoodVisit, <25mo) —
          // this card's "can't answer for themselves" rationale is a
          // communication-capability concern for the whole under-5 band,
          // not the narrower vaccination/IMCI service-eligibility gate.
          // (main's own build-fix commit took the naive isYoungChild
          // shortcut here — that's the wrong resolution, not a signal to
          // revert this back on a future merge.)
          isChild: patientContext.ageMonths < 60,
          selectedProgrammes: selectedProgrammes,
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
// strip used to live here but now stands on its own as [GreetWarmlyCard].

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
// static instruction ("👋 SIT WITH HER — GREET WARMLY"), body is a single
// greeting line in the SK's selected app language, footer is a small
// helper hint so the SK leads with empathy before tapping the AI Scribe
// below. Header/hint/greeting all follow [AppLocale] — no bilingual
// pairing: only the selected language renders, never both at once. The
// greeting prefers the AI-generated `greeting` block for the active
// language and falls back to the localized static copy when it's null,
// empty, or the SK has disabled the Step 1 AI briefing. When the briefing
// API returns a non-empty openingLine (legacy, pre-`greeting` field) we
// surface it as the English line before falling back to the static one —
// only relevant when the app language is English.
//
// Public so it can be pumped directly in a widget test — see
// GreetWarmlyCard's own test file for the header/hint/fallback coverage.
class GreetWarmlyCard extends StatelessWidget {
  const GreetWarmlyCard({
    super.key,
    required this.isFemale,
    required this.loading,
    this.isChild = false,
    this.selectedProgrammes = const {},
    this.greeting,
    this.fallbackOpeningLine,
  });

  final bool isFemale;
  final bool loading;

  /// True for an under-5 patient — they can't answer for themselves, so
  /// every line addresses the guardian about the child rather than the
  /// child directly (the AI-generated `greeting` block is instructed to do
  /// the same; this only governs the offline / AI-unavailable fallback).
  final bool isChild;

  /// The SK's currently-ticked service cards. Governs which static coaching
  /// hint is shown, so it names the actual checkup rather than always
  /// assuming a pregnancy one. Deliberately does NOT reach the greeting
  /// line — that stays generic (see
  /// [SymptomPickerStrings.sitWithGreetEnglishFor]).
  final Set<Programme> selectedProgrammes;

  /// AI-generated greeting block. When null or empty, the localized static
  /// fallback is shown so the SK still has a sensible opener offline.
  final GreetingContent? greeting;

  /// Legacy fallback — the SDP opening line was used before the dedicated
  /// greeting block existed. Surface it as the English line when the new
  /// `greeting.english` field is empty and the app language is English.
  /// Not used for a child patient — an adult-patient opener wouldn't fit a
  /// guardian-directed greeting.
  final String? fallbackOpeningLine;

  static const Color _navyBg = AppColors.navy;

  /// Single greeting line in the SK's selected app language — Bangla when
  /// [AppLocale.isBangla], English otherwise. Never returns both languages
  /// at once.
  String _resolveGreetingLine() {
    final g = greeting;
    if (AppLocale.isBangla) {
      if (g != null && g.bangla.trim().isNotEmpty) return g.bangla.trim();
      return SymptomPickerStrings.sitWithGreetBanglaFor(isChild: isChild);
    }
    if (g != null && g.english.trim().isNotEmpty) return g.english.trim();
    if (!isChild &&
        fallbackOpeningLine != null &&
        fallbackOpeningLine!.trim().isNotEmpty) {
      return fallbackOpeningLine!.trim();
    }
    return SymptomPickerStrings.sitWithGreetEnglishFor(isChild: isChild);
  }

  /// Coaching line shown under the greeting, in the SK's selected app
  /// language. When the app language is Bangla, prefers `greeting.hintBn`,
  /// then `greeting.hintBangla`, then falls through to the generic
  /// `greeting.hint`; English just uses `greeting.hint` directly. Falls
  /// back to the localized static coaching line when none of the AI
  /// fields are populated so the SK still gets the "ask about home first"
  /// nudge offline.
  String _resolveHint() {
    final g = greeting;
    if (g != null) {
      if (AppLocale.isBangla) {
        if (g.hintBn.trim().isNotEmpty) return g.hintBn.trim();
        if (g.hintBangla.trim().isNotEmpty) return g.hintBangla.trim();
      }
      if (g.hint.trim().isNotEmpty) return g.hint.trim();
    }
    return SymptomPickerStrings.sitWithGreetHintFor(
      isFemale: isFemale,
      selectedProgrammes: selectedProgrammes,
      isChild: isChild,
    );
  }

  @override
  Widget build(BuildContext context) {
    final greetingLine = _resolveGreetingLine();
    final hint = _resolveHint();
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
            SymptomPickerStrings.sitWithGreetHeaderFor(
              isFemale: isFemale,
              isChild: isChild,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                  greetingLine,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnNavy,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hint.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: AppColors.textOnNavy.withValues(alpha: 0.45),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// Skeleton shown inside [GreetWarmlyCard] while the briefing API is in
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
    if (ctx.isYoungChild) {
      chips.add((SymptomPickerStrings.chipUnder5, AppColors.statusInfo));
    }
    if (chips.isEmpty) {
      chips.add((SymptomPickerStrings.chipRoutine, AppColors.textMuted));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.wifi_off, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              SymptomPickerStrings.aiOfflineLocalContext,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
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

  /// Chips flow across the full width and re-wrap as the space allows; a label
  /// too long for a whole row is ellipsised instead of overflowing.
  Widget _chipWrap(List<String> codes) {
    final vm = widget.vm;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final code in codes)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _PickerChip(
                  key: ValueKey('triage_chip_$code'),
                  code: code,
                  isSelected: vm.isSelected(code),
                  isAi: vm.isScribePreTick(code),
                  onTap: () => _toggleSymptom(code),
                ),
              ),
          ],
        );
      },
    );
  }

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
              // Search results — one flat wrap of the matches.
              _chipWrap(gridSections.expand((s) => s.$2).toSet().toList())
            else if (gridSections.every((s) => s.$1 == null || s.$1!.isEmpty))
              // No section headers to draw — flow every service's symptoms as
              // a single block so chips keep filling each row.
              _chipWrap(gridSections.expand((s) => s.$2).toSet().toList())
            else
              // Per-service sections: each enrolled programme gets its own
              // labeled chip block; chips wrap within the block.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final section in gridSections)
                    if (section.$2.isNotEmpty) ...[
                      if (section.$1 != null && section.$1!.isNotEmpty) ...[
                        Text(
                          section.$1!.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMuted,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      _chipWrap(section.$2),
                      const SizedBox(height: 14),
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
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
// ANC and PNC respectively. Young-child patients skip this widget entirely.

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
// Row 3: Eye Care, Cataract
// Young-child row: Vaccination, Child Health
//
// TB has no card here by design — its form content isn't yet aligned, so it
// stays unreachable rather than exposed (see Programme.tb's doc comment and
// ServiceSelectionResolver.excludedFromSelection, which also blocks it from
// sneaking in via the rule engine, catalogue tags, or an enrolled record).
const _kAllServiceCards = [
  _ServiceCardDef(kind: _ServiceCardKind.pw,          emoji: '🤰', label: 'PW'),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '🏥', label: 'ANC',               programme: Programme.anc),
  _ServiceCardDef(kind: _ServiceCardKind.delivery,    emoji: '🚼', label: 'Pregnancy Outcome'),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '👶', label: 'PNC',               programme: Programme.pnc),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '🌸', label: 'FP',                programme: Programme.familyPlanning),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '💊', label: 'NCD',               programme: Programme.ncd),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '👁️', label: 'Eye Care',          programme: Programme.eyeCare),
  _ServiceCardDef(kind: _ServiceCardKind.programme,   emoji: '🔍', label: 'Cataract',           programme: Programme.cataract),
  // Young-child cards — shown only when ctx.isYoungChild
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
    this.ancRevisitStatus = _AncRevisitStatus.unknown,
    this.openPregnancyEpisode,
    required this.onProgrammeToggle,
    required this.onPWToggle,
    required this.onDeliveryToggle,
    required this.onVaccination,
    this.vaccinationSelected = false,
    this.vaccinationLocked = false,
  });

  final PatientContext patientContext;
  final Set<Programme> selectedProgrammes;
  final Set<Programme> pathwayProgrammes;

  /// Programmes the patient is already enrolled in from past visits.
  /// Cards show an "Enrolled" badge; they remain selectable for this visit.
  final Set<Programme> enrolledProgrammes;

  final bool isPW;
  final bool isDelivery;

  /// Whether ANC is currently within its risk-based revisit interval — locks
  /// the ANC card and shows the last-visit date/next-due date.
  final _AncRevisitStatus ancRevisitStatus;

  /// The patient's currently open pregnancy episode, if any — locks the PW
  /// card and shows its LMP/EDD. Deliberately independent of [isPW]: ANC's
  /// own lock reads [isPW], not this field, so ANC stays selectable for an
  /// already-pregnant woman regardless of this value.
  final PregnancyEpisodeRow? openPregnancyEpisode;

  final void Function(Programme programme, bool selected) onProgrammeToggle;
  final ValueChanged<bool> onPWToggle;
  final ValueChanged<bool> onDeliveryToggle;

  /// Whether the Vaccination card shows as selected (young-child only) — always
  /// true whenever the card renders, since vaccination is no longer a
  /// genuine choice; see [vaccinationLocked].
  final bool vaccinationSelected;

  /// True when embedded in the visit flow — the Vaccination card renders
  /// pre-selected and non-interactive (vaccination always happens for a
  /// child visit regardless of this card), so tapping it explains why
  /// instead of toggling anything. False for standalone (non-embedded) use,
  /// where the card tap still pushes the immunisation route directly via
  /// [onVaccination] — that legacy path is unaffected.
  final bool vaccinationLocked;

  /// Legacy — kept for standalone (non-embedded) use where the card tap
  /// still pushes the immunisation route directly.
  final VoidCallback onVaccination;

  List<_ServiceCardDef> _visibleCards() {
    final ctx = patientContext;
    return _kAllServiceCards.where((c) {
      switch (c.kind) {
        case _ServiceCardKind.vaccination:
          return ctx.isYoungChild;
        case _ServiceCardKind.pw:
        case _ServiceCardKind.delivery:
          // isReproductiveAge's 168-month floor is already stricter than
          // isYoungChild's 25-month ceiling, so no separate !isYoungChild
          // check needed.
          return ctx.isFemale && ctx.isReproductiveAge;
        case _ServiceCardKind.programme:
          final p = c.programme!;
          if (p == Programme.imci) return ctx.isYoungChild;
          if (ctx.isYoungChild) return false;
          if (p == Programme.anc ||
              p == Programme.pnc ||
              p == Programme.familyPlanning) {
            return ctx.isFemale && ctx.isReproductiveAge;
          }
          if (p == Programme.ncd) return ctx.isAdult;
          if (p == Programme.eyeCare || p == Programme.cataract) {
            return ctx.isEyeCareCataractEligible;
          }
          return ctx.ageYears >= 15;
        case _ServiceCardKind.rmnch:
        case _ServiceCardKind.general:
          return false;
      }
    }).toList();
  }

  String _cardLabel(_ServiceCardDef card) {
    if (card.isRMNCH) {
      final ctx = patientContext;
      return (ctx.isFemale && ctx.isPregnant && !ctx.isPostpartum)
          ? TriageStrings.pregnancyOutcomeChip
          : ProgrammeLabels.of(Programme.pnc);
    }
    if (card.isDelivery) return TriageStrings.pregnancyOutcomeChip;
    if (card.isPW) return ProgrammeLabels.of(Programme.pw);
    if (card.isVaccination) return ProgrammeLabels.of(Programme.epi);
    if (card.programme == Programme.imci) {
      return ProgrammeLabels.childHealthService;
    }
    if (card.programme != null) return ProgrammeLabels.of(card.programme!);
    return card.label;
  }

  bool _isLocked(_ServiceCardDef card) {
    if (card.isVaccination) return vaccinationLocked;
    if (card.programme == Programme.imci) return false;
    final ctx = patientContext;
    final pregnant = ctx.isPregnant && !ctx.isPostpartum;
    // PW: starts a new pregnancy registration — never requires prior pregnancy record.
    // Blocked during a delivery visit, when already postpartum, or when this
    // patient already has an open pregnancy episode (re-registration would
    // only be silently dropped later by ServiceSelectionResolver).
    if (card.isPW) {
      return isDelivery || ctx.isPostpartum || openPregnancyEpisode != null;
    }
    if (card.programme == Programme.anc) {
      // ANC requires PW selection first; also blocked within the risk-based
      // revisit interval (1 day if high-risk, 15 days otherwise).
      // !pregnant removed: SK may start ANC for a new pregnancy (no prior PW record).
      return !isPW || isDelivery || ancRevisitStatus.tooSoon;
    }
    if (card.isDelivery) {
      return ProgrammeGridSync.isPregnancyOutcomeLocked(
        isPregnant: ctx.isPregnant,
        isPostpartum: ctx.isPostpartum,
        hasOpenPregnancyEpisode: openPregnancyEpisode != null,
      );
    }
    // PNC's normal rule ("available once postpartum") can't fire during the
    // very visit that records the delivery — isPostpartum isn't true until
    // that submission lands. Carved out here so PNC is a genuinely optional,
    // freely-toggleable card specifically on a delivery visit (default
    // selected via ProgrammeGridSync.applyDeliverySelected, but the SK can
    // untick it — see ServiceSelectionResolver.finalize's pncDismissedBySk).
    if (card.programme == Programme.pnc) return !ctx.isPostpartum && !isDelivery;
    // FP is contraindicated during active pregnancy; available post-delivery.
    if (card.programme == Programme.familyPlanning) return pregnant;
    return false;
  }

  bool _isCardSelected(_ServiceCardDef card) {
    if (card.isVaccination) return vaccinationSelected;
    // Already-registered PW never shows as selected — it isn't part of this
    // visit's submission at all once an episode is open. Independent of
    // isPW, which ANC's own lock still reads unchanged. Also excludes a
    // postpartum patient: her prior pregnancy's episode is closed (so
    // openPregnancyEpisode is null, same as a brand-new patient actively
    // selecting PW this visit) but isPW stays true from that pregnancy's
    // history — without this check the card would misleadingly render as
    // checked while postpartum-locked, when nothing is actually selected.
    if (card.isPW) {
      return isPW &&
          !isDelivery &&
          openPregnancyEpisode == null &&
          !patientContext.isPostpartum;
    }
    // ANC never shows as selected once its revisit interval blocks a new
    // visit — mirrors the PW-episode treatment above.
    if (card.programme == Programme.anc) {
      return selectedProgrammes.contains(Programme.anc) &&
          !ancRevisitStatus.tooSoon;
    }
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

  /// Message shown when the SK taps a locked card — mirrors [_isLocked]'s
  /// per-card reasoning, branch for branch, so the two can't drift apart.
  /// That drift was the root cause of a locked FP card (patient pregnant)
  /// showing the ANC/PW-specific hint instead of an FP-specific one, and of
  /// two more mismatches found alongside it (PW-locked-by-postpartum and
  /// PW-locked-by-delivery both fell into the same generic fallback).
  String _lockMessageFor(_ServiceCardDef card) {
    final ctx = patientContext;
    if (card.isPW) {
      if (openPregnancyEpisode != null) return AppStrings.pwAlreadyEnrolledMessage;
      if (isDelivery) return TriageStrings.ancDeliveryConflictHint;
      if (ctx.isPostpartum) return TriageStrings.pwLockedPostpartumHint;
    }
    if (card.programme == Programme.anc) {
      if (isDelivery) return TriageStrings.ancDeliveryConflictHint;
      if (ancRevisitStatus.tooSoon) return _ancRevisitMessage(ancRevisitStatus);
      return TriageStrings.pwHint; // locked because PW isn't selected yet
    }
    if (card.isDelivery) return TriageStrings.pregnancyOutcomeLockedHint;
    if (card.programme == Programme.pnc) return TriageStrings.pncOnlyPostpartumHint;
    if (card.programme == Programme.familyPlanning) {
      return TriageStrings.fpLockedPregnantHint;
    }
    return TriageStrings.pwHint; // unreachable — every lockable card is covered above
  }

  void _handleTap(BuildContext context, _ServiceCardDef card) {
    if (card.isVaccination) {
      if (vaccinationLocked) {
        // Embedded in visit flow — vaccination always happens for a child
        // visit regardless of this card, so there's nothing to toggle;
        // explain why instead.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(TriageStrings.vaccinationDefaultHint),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ));
      } else {
        // Standalone (non-embedded) use — legacy direct navigation, unaffected.
        onVaccination();
      }
      return;
    }
    final alreadySelected = _isCardSelected(card);
    if (_isLocked(card) && !alreadySelected) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(_lockMessageFor(card)),
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
                    isPathwaySuggested: c.programme != null &&
                        pathwayProgrammes.contains(c.programme),
                    subtitle: (c.isPW && openPregnancyEpisode != null)
                        ? _pwEpisodeSubtitle(openPregnancyEpisode!)
                        : (c.programme == Programme.anc &&
                                ancRevisitStatus.tooSoon)
                            ? _ancRevisitMessage(ancRevisitStatus)
                            : null,
                    onTap: () => _handleTap(context, c),
                  ))
              .toList(),
        ),
      ],
    );
  }

  /// Compact "LMP … · EDD …" subtitle shown on the locked PW card.
  String _pwEpisodeSubtitle(PregnancyEpisodeRow episode) {
    final fmt = AppDateFormat.dayMonthYearFmt;
    final lmpMs = episode.obstetric.lmpDate;
    final eddMs = episode.obstetric.eddDate;
    return TriageStrings.pwEpisodeSubtitle(
      lmp: lmpMs != null
          ? fmt.format(DateTime.fromMillisecondsSinceEpoch(lmpMs))
          : '—',
      edd: eddMs != null
          ? fmt.format(DateTime.fromMillisecondsSinceEpoch(eddMs))
          : '—',
    );
  }

  /// Message shown both on the locked ANC card's subtitle and its tap toast
  /// — deliberately the same string in both places (unlike the PW fix).
  String _ancRevisitMessage(_AncRevisitStatus status) {
    final lastVisitMs = status.lastVisitMs;
    if (lastVisitMs == null) return TriageStrings.ancVisitedTodayMessage;
    final fmt = AppDateFormat.dayMonthYearFmt;
    final lastVisitStr =
        fmt.format(DateTime.fromMillisecondsSinceEpoch(lastVisitMs));
    if (status.highRisk) {
      return TriageStrings.ancRevisitMessageHighRisk(lastVisit: lastVisitStr);
    }
    final revisitDays = status.revisitDays ?? 15;
    final nextDueMs = status.nextDueMs ??
        lastVisitMs + Duration(days: revisitDays).inMilliseconds;
    return TriageStrings.ancRevisitMessageNormal(
      lastVisit: lastVisitStr,
      nextDue: fmt.format(DateTime.fromMillisecondsSinceEpoch(nextDueMs)),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.def,
    required this.label,
    required this.isSelected,
    required this.isLocked,
    required this.isPathwaySuggested,
    required this.onTap,
    this.subtitle,
  });

  final _ServiceCardDef def;
  final String label;
  final bool isSelected;

  /// Small persistent caption shown under the label — currently only used
  /// by the locked PW card to show its open episode's LMP/EDD.
  final String? subtitle;
  final bool isLocked;
  final bool isPathwaySuggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg = isSelected
        ? AppColors.navy.withValues(alpha: 0.04)
        : Colors.white;
    final Color borderColor =
        isSelected ? AppColors.navy : const Color(0xFFE5E7EB);
    final double borderWidth = isSelected ? 2.0 : 1.0;
    final Color labelColor = isLocked
        ? AppColors.navy.withValues(alpha: 0.45)
        : AppColors.navy;

    return Semantics(
            button: true,
            selected: isSelected,
            enabled: !isLocked,
            label: isSelected
                ? TriageStrings.deselectProgrammeA11y(label)
                : TriageStrings.selectProgrammeA11y(label),
            child: GestureDetector(
              onTap: onTap,
              child: Opacity(
                opacity: isLocked ? 0.40 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
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
                      // Selection circle — top-right
                      Positioned(
                        top: 7,
                        right: 7,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 22,
                          height: 22,
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
                                  size: 13,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                      // Emoji + label — Positioned.fill so Column
                      // gets tight constraints and mainAxisAlignment.center works.
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                def.emoji,
                                style: const TextStyle(fontSize: 28, height: 1.0),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.0,
                                  color: labelColor,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 1),
                                Text(
                                  subtitle!,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                    color: labelColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
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
