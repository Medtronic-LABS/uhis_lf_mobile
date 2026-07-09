import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/programme.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/db/encounter_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/db/patient_programmes_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../../core/api/scribe_api_service.dart' show ScribeMode;
import '../../../core/api/realtime_asr_service.dart';
import '../../patient/followup_repository.dart';
import '../../patient/vitals_repository.dart';
import '../../realtime_asr/chief_complaint_matcher.dart';
import '../../realtime_asr/models/realtime_clinical_fields.dart';
import '../../realtime_asr/realtime_asr_controller.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/scribe_controller.dart';
import '../../scribe/scribe_mic_waveform.dart';
import '../../scribe/scribe_permission_service.dart';
import '../../scribe/scribe_session.dart';
import '../briefing/briefing_models.dart';
import '../briefing/visit_briefing_repository.dart';
import '../pathway/pathway_engine.dart';
import 'patient_context_builder.dart';
import 'visit_step_header.dart';
import 'triage_view_model.dart';
import 'ai_scribe_triage_vocab.dart';

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
  final void Function(
    Set<String> symptoms,
    String? sicknessDuration,
    String? otherSymptoms,
  )?
  onSymptomsConfirmed;

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
  int? _ancVisitCount;

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
      final builder = PatientContextBuilder(
        patientDao: patientDao,
        programmesDao: programmesDao,
        pregnancyDao: pregnancyDao,
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
      setState(() {
        _patientContext = ctx;
        _viewModel = TriageViewModel(patientContext: ctx);
        _isLoading = false;
      });
      debugPrint('[SymptomPicker] Load complete');
      _startBriefingFetch(ctx);
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
          _ancVisitCount = visitsByVisit.length;
        });
      }
    } on Object {
      if (mounted) setState(() => _briefingLoading = false);
    }
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  void _onContinue() {
    final vm = _viewModel;
    if (vm == null || _patientContext == null) return;

    debugPrint(
      '[SymptomPicker] Continue tapped — ${vm.activatedPathways.length} pathways: ${vm.activatedPathways.map((p) => p.programme.name).join(', ')}',
    );

    // In-flow host (VisitFlowScreen) intercepts via callback. The host also
    // needs the SK-confirmed symptom set to build the Step-2 AI programme
    // recommendation request payload — surface it via the optional
    // onSymptomsConfirmed callback before advancing.
    final onAdvance = widget.onAdvance;
    if (onAdvance != null) {
      widget.onSymptomsConfirmed?.call(
        vm.selectedSymptoms,
        vm.sicknessDuration,
        vm.customSymptomText,
      );
      onAdvance(vm.activatedPathways);
      return;
    }

    // Bypass the triage-result interstitial and go straight to the form.
    _navigateToForm(vm.activatedPathways);
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
                // 0) ANC visit summary chip — only for ANC patients.
                //    Spec §4.1 "AI Brief — Visit summary chip — Read-only".
                if (_patientContext!.isPregnant)
                  SliverToBoxAdapter(
                    child: _AncVisitSummaryChip(
                      patientName: widget.patientName,
                      patientContext: _patientContext!,
                      visitCount: _ancVisitCount,
                    ),
                  ),

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
                if (AppConfig.scribeEnabled)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _AiScribeTriageBanner(
                        encounterId: widget.encounterId,
                        patientId: widget.patientId,
                        viewModel: vm,
                      ),
                    ),
                  ),

                // Unified symptom section: AI chips + search/type-to-add
                // inline list + other symptoms free-text — all in one card.
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _UnifiedSymptomPicker(vm: vm),
                  ),
                ),

                // Status bar + Start Checkup CTA
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Status row ────────────────────────────────────
                        if (vm.selectedSymptoms.isNotEmpty ||
                            vm.activatedPathways.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                if (vm.selectedSymptoms.isNotEmpty)
                                  Text(
                                    SymptomPickerStrings.symptomsSelectedStatus(
                                      vm.selectedSymptoms.length,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                if (vm.selectedSymptoms.isNotEmpty &&
                                    vm.activatedPathways.isNotEmpty)
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 6),
                                    child: Text(
                                      '|',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                if (vm.activatedPathways.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      SymptomPickerStrings.servicesOpeningStatus(
                                        vm.activatedPathways.length,
                                        vm.activatedPathways
                                            .map((p) => p.programme.wireTag)
                                            .toList(),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),

                        // ── Routine visit fallback link ────────────────────
                        if (vm.isRoutineVisit && vm.activatedPathways.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextButton(
                              onPressed: () => _navigateToForm([]),
                              child: const Text(
                                  TriageStrings.noSymptomsRoutineVisit),
                            ),
                          ),

                        // ── Start Checkup button ───────────────────────────
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

// ── ANC Visit Summary Chip ────────────────────────────────────────────────────
//
// Spec §4.1: Read-only strip at the top of Step 1 for ANC patients.
// Shows: patient name · ANC visit number · gestational week · parity · key trend.
// Sits flush edge-to-edge so it reads as a contextual header, not a card.

class _AncVisitSummaryChip extends StatelessWidget {
  const _AncVisitSummaryChip({
    required this.patientContext,
    this.patientName,
    this.visitCount,
  });

  final PatientContext patientContext;
  final String? patientName;

  /// Total completed visits for this patient — loaded from vitals history.
  /// Null while the briefing fetch is in flight.
  final int? visitCount;

  String? get _keyTrend {
    final facts = patientContext.pregnancyFacts;
    if (patientContext.lastBpSystolic != null &&
        patientContext.lastBpSystolic! >= 140) {
      return ComposerStrings.ancSummaryBpElevated;
    }
    if (facts == null) return null;
    if (facts.isNearTermAnc) return ComposerStrings.ancSummaryNearTerm;
    if (facts.highRiskPregnantWoman) return ComposerStrings.ancSummaryHighRisk;
    if (facts.hasGapsInAnc) return ComposerStrings.ancSummaryAncGap;
    return null;
  }

  Color get _trendColor {
    final facts = patientContext.pregnancyFacts;
    if (patientContext.lastBpSystolic != null &&
        patientContext.lastBpSystolic! >= 140) {
      return AppColors.statusCritical;
    }
    if (facts?.isNearTermAnc == true) return AppColors.statusWarning;
    if (facts?.highRiskPregnantWoman == true) return AppColors.statusCritical;
    if (facts?.hasGapsInAnc == true) return AppColors.statusWarning;
    return AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final ga = patientContext.gestationalWeeks;
    final g = patientContext.gravida;
    final p = patientContext.para;
    final trend = _keyTrend;

    return Container(
      color: AppColors.ancSurface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          // ANC badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.ancText,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ComposerStrings.ancSummaryEyebrow,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Patient name
          Expanded(
            child: Text(
              patientName ?? '',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ancText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Pill chips — GA · parity · visit number
          Wrap(
            spacing: 5,
            children: [
              if (ga != null)
                _SummaryPill(
                  label: '$ga ${ComposerStrings.ancSummaryGaUnit}',
                  color: AppColors.ancText,
                  surface: AppColors.ancBorder,
                ),
              if (g != null && p != null)
                _SummaryPill(
                  label: ComposerStrings.ancSummaryParity(g, p),
                  color: AppColors.ancText,
                  surface: AppColors.ancBorder,
                ),
              if (visitCount != null)
                _SummaryPill(
                  label: '${ComposerStrings.ancSummaryVisitPrefix}$visitCount',
                  color: AppColors.ancText,
                  surface: AppColors.ancBorder,
                ),
              if (trend != null)
                _SummaryPill(
                  label: trend,
                  color: Colors.white,
                  surface: _trendColor,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.color,
    required this.surface,
  });

  final String label;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
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
            Row(
              children: [
                Flexible(
                  child: Text(
                    bangla,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textOnNavy,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textOnNavy.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    '"$english"',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textOnNavy.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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

// ── _AiScribeTriageBanner ────────────────────────────────────────────────────
//
// Prominent purple banner at the top of Step 1. Spec §4.1.2 (ANC) / §5.1.1
// (NCD): tap-to-record. Result symptoms render as pre-ticked chips in the
// list below; SK can untick AI picks or add missed ones manually.
//
// State machine driven by [ScribeController.session]:
//   idle       → mic icon, "tap to fill the form by voice"
//   recording  → red pulse, "Listening… tap to stop"
//   processing → spinner, "AI is reviewing the recording"
//   reviewReady (mode==triage) → silently transitions back to idle once the
//   [TriageViewModel] has consumed the result and the controller is reset.

class _AiScribeTriageBanner extends StatefulWidget {
  const _AiScribeTriageBanner({
    required this.encounterId,
    required this.patientId,
    required this.viewModel,
  });

  final String encounterId;
  final String patientId;
  final TriageViewModel viewModel;

  @override
  State<_AiScribeTriageBanner> createState() => _AiScribeTriageBannerState();
}

class _AiScribeTriageBannerState extends State<_AiScribeTriageBanner> {
  static const Color _gradStart = AppColors.aiPurpleDark;
  static const Color _gradEnd = AppColors.aiPurple;
  static const Color _iconBg = AppColors.aiPurple;
  static const Color _recordingIconBg = AppColors.aiPurpleLight;
  static const Color _errorGradStart = AppColors.statusCriticalText;
  static const Color _errorGradEnd = AppColors.rangeCritical;

  bool _showDone = false;
  bool _triageResultConsumed = false;
  ScribeController? _scribe;

  // Independent "Live ASR" mode — see ScribeBanner's docs for the same
  // pattern. Never runs at the same time as the batch triage recording
  // above; both would otherwise try to capture the mic at once.
  late final RealtimeAsrController _liveCtrl;
  RealtimeClinicalFields? _lastAppliedLiveFields;

  @override
  void initState() {
    super.initState();
    _liveCtrl = RealtimeAsrController(
      service: context.read<RealtimeAsrService>(),
      permissionService: ScribePermissionService(),
    );
    _liveCtrl.addListener(_onLiveChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<ScribeController>();
    if (!identical(_scribe, next)) {
      _scribe?.removeListener(_onScribeChanged);
      _scribe = next;
      _scribe!.addListener(_onScribeChanged);
      _onScribeChanged();
    }
    _liveCtrl.bindContext(context);
  }

  @override
  void dispose() {
    _scribe?.removeListener(_onScribeChanged);
    _liveCtrl.removeListener(_onLiveChanged);
    _liveCtrl.dispose();
    super.dispose();
  }

  void _onLiveChanged() {
    if (!mounted) return;
    final fields = _liveCtrl.fields;
    if (fields != null && !identical(fields, _lastAppliedLiveFields)) {
      _lastAppliedLiveFields = fields;
      debugPrint('[RealtimeASR/Triage] chiefComplaints: ${fields.chiefComplaints}');
      if (fields.chiefComplaints.isNotEmpty) {
        final matchedCodes = ChiefComplaintMatcher.match(fields.chiefComplaints);
        debugPrint('[RealtimeASR/Triage] matched vocab codes: $matchedCodes');
        if (matchedCodes.isNotEmpty) {
          widget.viewModel.applyScribeTriageResult(
            TriageExtractionResult(
              symptomCodes: [
                for (final code in matchedCodes)
                  AIExtractedField(
                    fieldId: code,
                    value: true,
                    confidence: ChiefComplaintMatcher.matchConfidence,
                  ),
              ],
              transcriptText: _liveCtrl.fullTranscript,
            ),
          );
        }
      }
    }
    setState(() {});
  }

  void _startOther(ScribeController controller) {
    controller.bindContext(context);
    if (_showDone) {
      setState(() {
        _showDone = false;
        _triageResultConsumed = false;
      });
    }
    controller.startRecordingForTriage(
      patientId: widget.patientId,
      encounterId: widget.encounterId,
      symptomCatalog: AiScribeTriageVocab.codes,
    );
  }

  void _startAsr() {
    if (_showDone) {
      setState(() {
        _showDone = false;
        _triageResultConsumed = false;
      });
    }
    _liveCtrl.start();
  }

  void _onScribeChanged() {
    if (!mounted || _showDone) return;
    final session = _scribe!.session;
    if (session.state == ScribeState.reviewReady &&
        session.mode == ScribeMode.triage &&
        !_triageResultConsumed) {
      _consumeTriageResult(_scribe!);
    } else if (session.state == ScribeState.error) {
      setState(() {});
    }
  }

  void _consumeTriageResult(ScribeController controller) {
    _triageResultConsumed = true;
    final triageResult = controller.session.triageExtractionResult;
    if (triageResult != null) {
      widget.viewModel.applyScribeTriageResult(triageResult);
    }
    controller.resetSession();
    setState(() => _showDone = true);
  }

  @override
  Widget build(BuildContext context) {
    ScribeController controller;
    try {
      controller = context.watch<ScribeController>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    final session = controller.session;
    final liveActive = _liveCtrl.isActive;
    final isRecording = !liveActive && session.state == ScribeState.recording;
    final isError =
        !liveActive && !_showDone && session.state == ScribeState.error;
    final isProcessing =
        !liveActive &&
        !_showDone &&
        !isError &&
        (session.state == ScribeState.uploading ||
            session.state == ScribeState.processing);
    // True idle OR the terminal "done" state — both offer the ASR/Other
    // chooser instead of an implicit whole-card tap-to-start.
    final idleChoice = !liveActive && !isRecording && !isError && !isProcessing;

    final title = liveActive
        ? RealtimeAsrStrings.title
        : _showDone
        ? SymptomPickerStrings.scribeBannerDone
        : isError
        ? SymptomPickerStrings.scribeBannerError
        : isRecording
        ? SymptomPickerStrings.scribeBannerRecording
        : isProcessing
        ? SymptomPickerStrings.scribeBannerProcessing
        : SymptomPickerStrings.scribeBannerTitle;

    final subtitle = liveActive
        ? (switch (_liveCtrl.state) {
            RealtimeAsrState.connecting => RealtimeAsrStrings.connecting,
            RealtimeAsrState.stopping => RealtimeAsrStrings.stopping,
            _ => RealtimeAsrStrings.listening,
          })
        : _showDone
        ? SymptomPickerStrings.scribeBannerDoneSubtitle
        : isError
        ? SymptomPickerStrings.scribeBannerErrorSubtitle
        : isRecording
        ? SymptomPickerStrings.scribeBannerRecordingSubtitle
        : idleChoice
        ? ScribeBannerStrings.idleSub
        : SymptomPickerStrings.scribeBannerSubtitle;

    void onTap() {
      controller.bindContext(context);
      if (liveActive) {
        _liveCtrl.stop();
      } else if (isRecording) {
        controller.stopRecording(
          patientId: widget.patientId,
          encounterId: widget.encounterId,
        );
      } else if (isError) {
        setState(() {
          _showDone = false;
          _triageResultConsumed = false;
        });
        controller.resetSession();
      }
      // idleChoice (true idle or done) is handled by the explicit ASR/Other
      // buttons below, not by tapping the card.
    }

    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: !idleChoice,
        label: liveActive
            ? 'Stop live ASR'
            : isRecording
            ? SymptomPickerStrings.scribeStopRecordingLabel
            : isError
            ? SymptomPickerStrings.scribeBannerError
            : _showDone
            ? SymptomPickerStrings.scribeBannerDone
            : SymptomPickerStrings.scribeBannerTitle,
        child: InkWell(
          onTap: (isProcessing || idleChoice) ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: liveActive
                    ? const [_gradStart, _gradEnd]
                    : _showDone
                    ? const [
                        AppColors.statusSuccessAction,
                        AppColors.statusSuccess,
                      ]
                    : isError
                    ? const [_errorGradStart, _errorGradEnd]
                    : const [_gradStart, _gradEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: _showDone
                  ? Border.all(
                      color: AppColors.textOnNavy.withValues(alpha: 0.35),
                      width: 1,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: (_showDone ? AppColors.statusSuccess : _gradStart)
                      .withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // idle → mic · recording → waveform · processing → spinner
                    // · done → green check · live → podcast icon → idle.
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: _buildCircleContent(
                          controller: controller,
                          isRecording: isRecording,
                          isProcessing: isProcessing,
                          isError: isError,
                          showDone: _showDone,
                          liveActive: liveActive,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (isRecording) ...[
                                const ScribeRecordingLiveDot(),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textOnNavy,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textOnNavy.withValues(alpha: 0.78),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Idle/done: explicit mode chooser — no implicit whole-card
                    // tap-to-start, so it's always clear which engine runs.
                    if (idleChoice) ...[
                      const SizedBox(width: 8),
                      _TriageModeButton(
                        key: const Key('triage_banner_mode_asr'),
                        label: ScribeBannerStrings.modeAsr,
                        icon: Icons.podcasts,
                        onTap: _startAsr,
                      ),
                      const SizedBox(width: 6),
                      _TriageModeButton(
                        key: const Key('triage_banner_mode_other'),
                        label: ScribeBannerStrings.modeOther,
                        icon: Icons.mic,
                        onTap: () => _startOther(controller),
                      ),
                    ],
                    // Batch ("Other") mode active: badge makes the active
                    // engine explicit at a glance (live mode's title already
                    // says "Real-Time ASR").
                    if (!liveActive && !idleChoice) ...[
                      const SizedBox(width: 8),
                      const _TriageModeBadge(
                        label: ScribeBannerStrings.modeOtherBadge,
                      ),
                    ],
                  ],
                ),
                if (liveActive) ...[
                  const SizedBox(height: 10),
                  _TriageLiveAsrPanel(controller: _liveCtrl),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCircleContent({
    required ScribeController controller,
    required bool isRecording,
    required bool isProcessing,
    required bool isError,
    required bool showDone,
    required bool liveActive,
  }) {
    if (liveActive) {
      // Spinner while the socket is coming up or the session is winding down,
      // so tapping start/stop gives immediate feedback; podcast icon while the
      // session is actively listening.
      final busy = _liveCtrl.state == RealtimeAsrState.connecting ||
          _liveCtrl.state == RealtimeAsrState.stopping;
      return Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: _recordingIconBg,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textOnNavy,
                ),
              )
            : const Icon(Icons.podcasts, color: AppColors.textOnNavy, size: 22),
      );
    }
    if (showDone) {
      return const ScribeDoneMicOrb();
    }
    if (isRecording) {
      return ScribeRecordingMicOrb(
        recorderController: controller.waveformRecorder,
        backgroundColor: _recordingIconBg,
      );
    }
    if (isProcessing) {
      return const ScribeProcessingMicOrb(backgroundColor: _iconBg);
    }
    if (isError) {
      return Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: _iconBg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(Icons.refresh_rounded, color: AppColors.textOnNavy, size: 22),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(color: _iconBg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const Icon(Icons.mic_rounded, color: AppColors.textOnNavy, size: 22),
    );
  }
}

/// Explicit mode-chooser button on the triage banner, shown only at idle —
/// same purpose as ScribeBanner's `_ModeButton`, styled to match this
/// screen's rounded-chip aesthetic instead.
class _TriageModeButton extends StatelessWidget {
  const _TriageModeButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Start $label mode',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.textOnNavy.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.textOnNavy.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textOnNavy, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textOnNavy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Non-interactive tag making the active engine explicit once "Other"
/// (standard/batch triage) is running.
class _TriageModeBadge extends StatelessWidget {
  const _TriageModeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.textOnNavy.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textOnNavy.withValues(alpha: 0.85),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Live transcript + on-demand detected-symptoms preview for the triage
/// banner's "ASR" mode — content mirrors ScribeBanner's `_LiveAsrPanel`.
/// Independent of the batch triage flow: nothing here feeds
/// [TriageViewModel] or the pre-ticked symptom chips below.
class _TriageLiveAsrPanel extends StatelessWidget {
  const _TriageLiveAsrPanel({required this.controller});
  final RealtimeAsrController controller;

  @override
  Widget build(BuildContext context) {
    final fields = controller.fields;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // [MANUAL: no token — 20% black inset panel on the dark ASR surface]
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.rxIcon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.micWarning != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.statusWarningDark, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      controller.micWarning!,
                      style: const TextStyle(color: AppColors.statusWarningDark, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (controller.errorMessage != null)
            Text(
              controller.errorMessage!,
              style: const TextStyle(color: AppColors.textOnNavy, fontSize: 12),
            )
          else ...[
            Text(
              controller.segments.isEmpty
                  ? RealtimeAsrStrings.transcriptEmpty
                  : controller.fullTranscript,
              style: TextStyle(
                color: AppColors.textOnNavy.withValues(alpha: 0.9),
                fontSize: 12,
                fontStyle: controller.segments.isEmpty
                    ? FontStyle.italic
                    : null,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    fields == null || fields.isEmpty
                        ? RealtimeAsrStrings.symptomsEmpty
                        : _summarize(fields),
                    style: TextStyle(
                      color: AppColors.textOnNavy.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: controller.isExtracting ? null : controller.extractNow,
                  child: Text(
                    controller.isExtracting
                        ? RealtimeAsrStrings.extracting
                        : RealtimeAsrStrings.extractNow,
                    style: const TextStyle(
                      color: AppColors.textOnNavy,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _summarize(RealtimeClinicalFields f) {
    final parts = <String>[
      if (f.diagnosis != null) f.diagnosis!,
      if (f.bloodPressure != null) 'BP ${f.bloodPressure}',
      if (f.bloodGlucose != null) 'BG ${f.bloodGlucose}',
      ...f.chiefComplaints,
    ];
    return parts.isEmpty ? RealtimeAsrStrings.symptomsEmpty : parts.join(' · ');
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
      widget.vm.addSymptom(code);
      // After selecting a symptom while the user is mid-search, clear the
      // search so they can see the remaining unselected primary chips.
      if (_query.isNotEmpty) {
        _searchCtrl.clear();
        FocusScope.of(context).unfocus();
      }
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
        // Secondary (cross-programme) symptoms only surface once the user has
        // typed enough to be intentionally looking for them.
        final searchPool = _query.length >= _secondaryThreshold
            ? vm.applicableVocabCodes
            : vm.primaryVocabCodes;
        final primaryCodes = vm.primaryVocabCodes;

        // Determine which codes to show in the grid.
        final List<String> gridCodes;
        if (isSearching) {
          gridCodes = searchPool
              .where(
                (c) => TriageStrings.symptomLabel(c)
                    .toLowerCase()
                    .contains(_query),
              )
              .toList();
        } else {
          gridCodes = primaryCodes;
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.textOnNavy,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Search bar ────────────────────────────────────────────────
              TextField(
                key: const Key('triage_symptom_search'),
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: SymptomPickerStrings.searchSymptomsHint,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.navy),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: AppColors.canvas,
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

              const SizedBox(height: 14),

              // ── Chip grid ─────────────────────────────────────────────────
              if (gridCodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    SymptomPickerStrings.searchNoResults,
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
                  children: gridCodes
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

              // ── Footer: count + "type more" hint ──────────────────────────
              const SizedBox(height: 10),
              Row(
                children: [
                  if (selected.isNotEmpty)
                    Text(
                      SymptomPickerStrings.symptomsSelected(selected.length),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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

