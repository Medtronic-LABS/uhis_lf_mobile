import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/db/encounter_dao.dart';
import '../../../core/db/immunisation_dao.dart';
import '../../../core/db/local_assessment_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/models/programme.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/db/patient_programmes_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../realtime_asr/chief_complaint_matcher.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/widgets/ai_scribe_banner.dart';
import '../pathway/pathway_engine.dart';
import 'patient_context_builder.dart';
import 'programme_grid_sync.dart';
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

  @override
  State<SymptomPickerScreen> createState() => _SymptomPickerScreenState();
}

class _SymptomPickerScreenState extends State<SymptomPickerScreen> {
  TriageViewModel? _viewModel;
  PatientContext? _patientContext;
  bool _isLoading = true;
  String? _error;

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

  /// PW meta-flag — gates ANC. Auto-true when patient is known pregnant.
  bool _isPW = false;

  /// Delivery meta-flag — gates PNC. Auto-true when patient is postpartum.
  bool _isDelivery = false;

  @override
  void initState() {
    super.initState();
    // Defer to after first frame to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPatientContext();
    });
  }

  Future<void> _loadPatientContext() async {
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
      final isPw =
          ctx.isPregnant || ctx.activeProgrammes.contains(Programme.anc);
      final isDelivery = ctx.isPostpartum;
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
        _isDelivery = isDelivery;
        _isLoading = false;
      });
      debugPrint(
          '[SymptomPicker] Load complete — pathway programmes: ${pathwaySet.map((p) => p.name).join(', ')} '
          'enrolledSeed: ${enrolledSeed.map((p) => p.name).join(', ')} '
          'selected: ${_selectedProgrammes.map((p) => p.name).join(', ')}');
      _fireProgrammesLive();
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

  void _fireProgrammesLive() {
    widget.onProgrammesLive?.call(Set.unmodifiable(_selectedProgrammes));
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
    super.dispose();
  }

  void _openVaccinationTimeline() {
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
            content: const Text(SymptomPickerStrings.noSymptomsGuard),
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
        widget.onProgrammesSelected?.call(Set.unmodifiable(_selectedProgrammes));
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
                  child: const Text(TriageStrings.retryButton),
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
            return CustomScrollView(
              slivers: [
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
                if (AppConfig.scribeEnabled)
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

                // Eligible services grid — adults only; under-5 uses vaccination CTA
                if (!(_patientContext!.isUnder5))
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
                        onPWToggle: (selected) {
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
                              // Turning PW on surfaces enrolled/pathway ANC.
                              if (_patientContext!.activeProgrammes
                                      .contains(Programme.anc) ||
                                  _pathwayActivatedProgrammes
                                      .contains(Programme.anc)) {
                                _selectedProgrammes.add(Programme.anc);
                              }
                            }
                          });
                          _fireProgrammesLive();
                        },
                        onDeliveryToggle: (selected) {
                          setState(() {
                            _isDelivery = selected;
                            if (!selected) {
                              _selectedProgrammes.remove(Programme.pnc);
                              _skDismissedProgrammes.add(Programme.pnc);
                            } else {
                              _skDismissedProgrammes.remove(Programme.pnc);
                              // Delivery unlocks PNC — include enrolled PNC.
                              if (_patientContext!.activeProgrammes
                                  .contains(Programme.pnc)) {
                                _selectedProgrammes.add(Programme.pnc);
                              }
                            }
                          });
                          _fireProgrammesLive();
                        },
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
                        // For children the vaccination button is the primary
                        // CTA; in embedded mode it also advances the visit flow
                        // to the vaccination step. The "Start Checkup" button
                        // is hidden for under-5 patients.
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
                              child: const Text(
                                ChildAssessmentStrings.vaccinationCta,
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
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
                              child: const Text(
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
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (context, _) {
        final vm = widget.vm;
        final selected = vm.selectedSymptoms;
        final isSearching = _query.isNotEmpty;

        // Default grid: enrolled-programme symptoms only (or all primary codes
        // when the patient has no enrolled programmes).
        final defaultCodes = vm.enrolledProgrammeVocabCodes;

        // Once the SK types 3+ chars, open up the full applicable vocab so
        // cross-programme symptoms become discoverable via search.
        final searchPool = _query.length >= _secondaryThreshold
            ? vm.applicableVocabCodes
            : defaultCodes;

        // Determine which sections to show in the grid.
        // Searching → one flat headerless section of matches. Otherwise →
        // per-programme sections plus any selected codes that fall outside
        // the default list (e.g. found via search from other programmes).
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
            for (final s in vm.groupedVocabSections)
              (null, s.codes.where((c) => !selected.contains(c)).toList()),
          ];
        }
        final gridIsEmpty =
            gridSections.every((s) => s.$2.isEmpty);

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

              const SizedBox(height: 14),

              // ── Chip grid (single flat Wrap — no per-section gaps) ───────
              if (gridIsEmpty)
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
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: gridSections
                      .expand((s) => s.$2)
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
                ),

              const SizedBox(height: 10),
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

enum _ServiceCardKind { programme, pw, delivery, general }

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
}

// Full card set — visibility filtered per patient demographics in the widget.
const _kAllServiceCards = [
  _ServiceCardDef(kind: _ServiceCardKind.pw,        emoji: '🤰', label: 'PW'),
  _ServiceCardDef(kind: _ServiceCardKind.programme, emoji: '🏥', label: 'ANC',      programme: Programme.anc),
  _ServiceCardDef(kind: _ServiceCardKind.programme, emoji: '🌸', label: 'FP',       programme: Programme.familyPlanning),
  _ServiceCardDef(kind: _ServiceCardKind.programme, emoji: '👶', label: 'PNC',      programme: Programme.pnc),
  _ServiceCardDef(kind: _ServiceCardKind.general,   emoji: '🩺', label: 'General'),
  _ServiceCardDef(kind: _ServiceCardKind.programme, emoji: '💊', label: 'NCD',      programme: Programme.ncd),
  _ServiceCardDef(kind: _ServiceCardKind.delivery,  emoji: '🚼', label: 'Delivery'),
];

class _InlineServiceSelector extends StatelessWidget {
  const _InlineServiceSelector({
    required this.patientContext,
    required this.selectedProgrammes,
    required this.pathwayProgrammes,
    required this.enrolledProgrammes,
    required this.isPW,
    required this.isDelivery,
    required this.onProgrammeToggle,
    required this.onPWToggle,
    required this.onDeliveryToggle,
  });

  final PatientContext patientContext;
  final Set<Programme> selectedProgrammes;
  final Set<Programme> pathwayProgrammes;

  /// Programmes the patient is already enrolled in from past visits.
  /// Cards show an "Enrolled" badge; they remain selectable for this visit.
  final Set<Programme> enrolledProgrammes;

  final bool isPW;
  final bool isDelivery;
  final void Function(Programme programme, bool selected) onProgrammeToggle;
  final ValueChanged<bool> onPWToggle;
  final ValueChanged<bool> onDeliveryToggle;

  List<_ServiceCardDef> _visibleCards() {
    final ctx = patientContext;
    return _kAllServiceCards.where((c) {
      switch (c.kind) {
        case _ServiceCardKind.pw:
        case _ServiceCardKind.delivery:
          return ctx.isFemale;
        case _ServiceCardKind.programme:
          final p = c.programme!;
          if (p == Programme.anc || p == Programme.familyPlanning) {
            return ctx.isFemale && ctx.ageYears >= 15;
          }
          if (p == Programme.pnc) return ctx.isFemale;
          return ctx.ageYears >= 15; // NCD, TB
        case _ServiceCardKind.general:
          return ctx.ageYears >= 15;
      }
    }).toList();
  }

  bool _isLocked(_ServiceCardDef card) {
    if (card.programme == Programme.anc) return !isPW;
    if (card.programme == Programme.pnc) return !isDelivery;
    return false;
  }

  bool _isCardSelected(_ServiceCardDef card) {
    if (card.isPW) return isPW;
    if (card.isDelivery) return isDelivery;
    if (card.programme != null) return selectedProgrammes.contains(card.programme);
    return false; // General — untacked
  }

  void _handleTap(BuildContext context, _ServiceCardDef card) {
    // Lock only blocks *adding* when the PW/Delivery gate is closed.
    // Already-selected cards can always be deselected (e.g. enrolled PNC that
    // was seeded incorrectly, or pathway ANC the SK does not want this visit).
    final alreadySelected = _isCardSelected(card);
    if (_isLocked(card) && !alreadySelected) {
      final hint = card.programme == Programme.anc
          ? TriageStrings.pwHint
          : TriageStrings.deliveryHint;
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
      onDeliveryToggle(!isDelivery);
    } else if (card.programme != null) {
      onProgrammeToggle(
          card.programme!, !selectedProgrammes.contains(card.programme));
    }
    // General card — no programme tracking
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
            const Text(
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
              child: const Text(
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
                    isSelected: _isCardSelected(c),
                    isLocked: _isLocked(c),
                    isEnrolled: (c.programme != null &&
                            enrolledProgrammes.contains(c.programme)) ||
                        (c.isPW &&
                            enrolledProgrammes.contains(Programme.anc)),
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
    required this.isSelected,
    required this.isLocked,
    required this.isEnrolled,
    required this.isPathwaySuggested,
    required this.onTap,
  });

  final _ServiceCardDef def;
  final bool isSelected;
  final bool isLocked;

  /// Patient is already enrolled in this programme from past visits.
  /// Shows an "Enrolled" badge; the card remains selectable for this visit.
  final bool isEnrolled;

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
          ? TriageStrings.enrolledProgrammeA11y(def.label)
          : (isSelected
              ? TriageStrings.deselectProgrammeA11y(def.label)
              : TriageStrings.selectProgrammeA11y(def.label)),
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
                        def.label,
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
                          child: const Text(
                            TriageStrings.enrolledBadge,
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
