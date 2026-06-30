import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/db/encounter_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/db/patient_programmes_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../../core/api/scribe_api_service.dart' show ScribeMode;
import '../../patient/followup_repository.dart';
import '../../patient/vitals_repository.dart';
import '../../scribe/scribe_controller.dart';
import '../../scribe/scribe_mic_waveform.dart';
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
  )? onSymptomsConfirmed;

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

    if (vm.activatedPathways.isEmpty) {
      // Legacy direct-route entry: no pathways → go straight to form.
      _navigateToForm([]);
      return;
    }

    context.go(
      '/patients/visit/${widget.encounterId}/triage-result',
      extra: {
        'patientId': widget.patientId,
        'memberId': widget.memberId,
        'householdId': widget.householdId,
        'patientAge': widget.patientAge,
        'patientLabel': 'Visit',
        'pathwayObjects': vm.activatedPathways,
      },
    );
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

                // AI-detected symptom list — populated by the scribe response.
                // Replaces the previous hardcoded cluster grid; SK reviews,
                // removes incorrect picks, or adds missed ones via the sheet.
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: _DetectedSymptomList(
                      vm: vm,
                      onAddTap: () => _openAddSymptomSheet(context, vm),
                    ),
                  ),
                ),

                // Gap 3 — Duration picker (below symptoms list)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: _DurationPicker(vm: vm),
                  ),
                ),

                // Gap 4 — Other symptoms free-text input
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: _OtherSymptomsField(vm: vm),
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: Consumer<TriageViewModel>(
          builder: (context, vm, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Routine visit button
                    if (vm.isRoutineVisit && vm.activatedPathways.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextButton(
                          onPressed: () => _navigateToForm([]),
                          child: const Text(
                            TriageStrings.noSymptomsRoutineVisit,
                          ),
                        ),
                      ),

                    // Continue button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _onContinue,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.pink,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          vm.activatedPathways.isNotEmpty
                              ? SymptomPickerStrings.ctaWithPathways
                              : SymptomPickerStrings.ctaRoutine,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openAddSymptomSheet(
    BuildContext context,
    TriageViewModel vm,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AddSymptomSheet(vm: vm),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.aiBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tappable header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: widget.iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(widget.icon, size: 15, color: widget.iconColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.aiSurfaceStart,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.aiBorder),
                    ),
                    child: const Text(
                      '✦ AI',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.aiPurple,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          if (_expanded) ...[
            const Divider(height: 1, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: widget.child,
            ),
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

  static const Color _aiTextColor = Color(0xFF9D174D);

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

    return Text(
      aiBody,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: _aiTextColor,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
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

  static const Color _navyBg = Color(0xFF1B2B5E);
  static const Color _navyHint = Color(0xFF243C7A);

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

  String _resolveHint() {
    final g = greeting;
    if (g != null && g.hint.trim().isNotEmpty) return g.hint.trim();
    return SymptomPickerStrings.sitWithGreetHintFor(isFemale: isFemale);
  }

  @override
  Widget build(BuildContext context) {
    final bangla = _resolveBangla();
    final english = _resolveEnglish();
    final hint = _resolveHint();

    final hasAi = greeting != null && !greeting!.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: _navyBg,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('👋', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  SymptomPickerStrings.sitWithGreetHeaderFor(
                      isFemale: isFemale),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (hasAi)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '✦ AI',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (loading && !hasAi)
            const _GreetLoadingSkeleton()
          else ...[
            Text(
              bangla,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '"$english"',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
                fontStyle: FontStyle.italic,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _navyHint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                color: Colors.white.withValues(alpha: 0.14),
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
                      color: Colors.white,
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

// ── Gap 3: Duration picker ────────────────────────────────────────────────────

/// Three-option duration selector rendered below the symptom clusters.
///
/// Stores selection via [TriageViewModel.setDuration].
class _DurationPicker extends StatelessWidget {
  const _DurationPicker({required this.vm});

  final TriageViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000), // TODO: add AppColors token
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            SymptomPickerStrings.durationTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DurationButton(
                  label: SymptomPickerStrings.duration1Day,
                  value: SymptomPickerStrings.durationValue1,
                  selected: vm.sicknessDuration,
                  onTap: (v) =>
                      vm.setDuration(vm.sicknessDuration == v ? null : v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DurationButton(
                  label: SymptomPickerStrings.duration2To3Days,
                  value: SymptomPickerStrings.durationValue2to3,
                  selected: vm.sicknessDuration,
                  onTap: (v) =>
                      vm.setDuration(vm.sicknessDuration == v ? null : v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DurationButton(
                  label: SymptomPickerStrings.duration4Plus,
                  value: SymptomPickerStrings.durationValue4plus,
                  selected: vm.sicknessDuration,
                  onTap: (v) =>
                      vm.setDuration(vm.sicknessDuration == v ? null : v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Single duration option button.
class _DurationButton extends StatelessWidget {
  const _DurationButton({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    final isHighRisk = value == SymptomPickerStrings.durationValue4plus;

    final bgColor = isSelected
        ? (isHighRisk ? AppColors.statusCriticalSurface : AppColors.navy)
        : Colors.white;
    final borderColor = isSelected
        ? (isHighRisk ? AppColors.statusCritical : AppColors.navy)
        : AppColors.border;
    final textColor = isSelected
        ? (isHighRisk ? AppColors.statusCriticalText : Colors.white)
        : AppColors.navy;

    return Semantics(
      label: 'Select duration: $label',
      button: true,
      selected: isSelected,
      child: GestureDetector(
        key: const Key('triage_answer_option_tap'),
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Gap 4: Other symptoms free-text field ────────────────────────────────────

/// Free-text field for symptoms not covered by the tile grid.
class _OtherSymptomsField extends StatefulWidget {
  const _OtherSymptomsField({required this.vm});
  final TriageViewModel vm;

  @override
  State<_OtherSymptomsField> createState() => _OtherSymptomsFieldState();
}

class _OtherSymptomsFieldState extends State<_OtherSymptomsField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.vm.customSymptomText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            SymptomPickerStrings.otherSymptomsLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              hintText: SymptomPickerStrings.otherSymptomsHint,
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            maxLines: 2,
            onChanged: widget.vm.setCustomSymptomText,
          ),
        ],
      ),
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
  static const Color _gradStart = Color(0xFF4F3FBA);
  static const Color _gradEnd = Color(0xFF6E54E0);
  static const Color _iconBg = Color(0xFF5E47C9);
  static const Color _recordingIconBg = Color(0xFF7A63E8);
  static const Color _errorGradStart = Color(0xFF8B3A3A);
  static const Color _errorGradEnd = Color(0xFFB84A4A);

  bool _showDone = false;
  bool _triageResultConsumed = false;
  ScribeController? _scribe;

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
  }

  @override
  void dispose() {
    _scribe?.removeListener(_onScribeChanged);
    super.dispose();
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
    if (triageResult != null && triageResult.symptomCodes.isNotEmpty) {
      widget.viewModel.applyScribeTriageResult(triageResult);
      controller.resetSession();
      setState(() => _showDone = true);
    }
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
    final isRecording = session.state == ScribeState.recording;
    final isError = !_showDone && session.state == ScribeState.error;
    final isProcessing =
        !_showDone &&
        !isError &&
        (session.state == ScribeState.uploading ||
            session.state == ScribeState.processing);

    final title = _showDone
        ? SymptomPickerStrings.scribeBannerDone
        : isError
        ? (session.errorMessage ==
                SymptomPickerStrings.scribeBannerNoSymptomsSubtitle
            ? SymptomPickerStrings.scribeBannerNoSymptoms
            : SymptomPickerStrings.scribeBannerError)
        : isRecording
        ? SymptomPickerStrings.scribeBannerRecording
        : isProcessing
        ? SymptomPickerStrings.scribeBannerProcessing
        : SymptomPickerStrings.scribeBannerTitle;

    // Show partial transcript while processing so the SK sees what was heard.
    final liveText = session.liveTranscript;
    final subtitle = _showDone
        ? SymptomPickerStrings.scribeBannerDoneSubtitle
        : isError
        ? (session.errorMessage ??
              SymptomPickerStrings.scribeBannerErrorSubtitle)
        : isRecording
        ? SymptomPickerStrings.scribeBannerRecordingSubtitle
        : isProcessing && liveText != null && liveText.isNotEmpty
        ? '"$liveText"'
        : SymptomPickerStrings.scribeBannerSubtitle;

    void onTap() {
      controller.bindContext(context);
      if (isRecording) {
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
      } else if (_showDone) {
        setState(() {
          _showDone = false;
          _triageResultConsumed = false;
        });
        controller.startRecordingForTriage(
          patientId: widget.patientId,
          encounterId: widget.encounterId,
          symptomCatalog: AiScribeTriageVocab.codes,
        );
      } else if (!isProcessing) {
        controller.startRecordingForTriage(
          patientId: widget.patientId,
          encounterId: widget.encounterId,
          symptomCatalog: AiScribeTriageVocab.codes,
        );
      }
    }

    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        label: isRecording
            ? SymptomPickerStrings.scribeStopRecordingLabel
            : isError
            ? SymptomPickerStrings.scribeBannerError
            : _showDone
            ? SymptomPickerStrings.scribeBannerDone
            : SymptomPickerStrings.scribeBannerTitle,
        child: InkWell(
          onTap: isProcessing ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _showDone
                    ? const [Color(0xFF3D7A52), Color(0xFF2F9E62)]
                    : isError
                    ? const [_errorGradStart, _errorGradEnd]
                    : const [_gradStart, _gradEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: _showDone
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: (_showDone ? const Color(0xFF2F9E62) : _gradStart)
                      .withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // idle → mic · recording → waveform · processing → spinner
                // · done → green check → idle.
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
                                color: Colors.white,
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
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12,
                        ),
                      ),
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

  Widget _buildCircleContent({
    required ScribeController controller,
    required bool isRecording,
    required bool isProcessing,
    required bool isError,
    required bool showDone,
  }) {
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
        decoration: const BoxDecoration(
          color: _iconBg,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.refresh_rounded,
          color: Colors.white,
          size: 22,
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: _iconBg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.mic_rounded,
        color: Colors.white,
        size: 22,
      ),
    );
  }
}

// ── AI-detected symptom list ─────────────────────────────────────────────────
//
// Replaces the legacy hardcoded cluster grid. The list is initially empty;
// the AI Scribe response populates it via [TriageViewModel.applyScribeTriageResult].
// The SK can:
//   - tap × on any chip → [TriageViewModel.removeSymptom]
//   - tap "+ Add symptom" → opens [_AddSymptomSheet] with the full vocab.
// Source-of-truth for the available codes: [AiScribeTriageVocab.codes].

class _DetectedSymptomList extends StatelessWidget {
  const _DetectedSymptomList({required this.vm, required this.onAddTap});

  final TriageViewModel vm;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    final selected = vm.selectedSymptoms.toList();
    final isEmpty = selected.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppColors.aiPurple,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  SymptomPickerStrings.detectedSymptomsTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isEmpty
                ? SymptomPickerStrings.detectedSymptomsSubtitleEmpty
                : SymptomPickerStrings.detectedSymptomsSubtitleFilled,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          if (!isEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selected
                  .map(
                    (code) => _SymptomChip(
                      code: code,
                      isAi: vm.isScribePreTick(code),
                      onRemove: () => vm.removeSymptom(code),
                    ),
                  )
                  .toList(),
            ),
          if (!isEmpty) const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('triage_add_symptom_tap'),
              onPressed: onAddTap,
              icon: const Icon(Icons.add, size: 18),
              label: const Text(SymptomPickerStrings.addSymptomCta),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SymptomChip extends StatelessWidget {
  const _SymptomChip({
    required this.code,
    required this.isAi,
    required this.onRemove,
  });

  final String code;
  final bool isAi;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final label = TriageStrings.symptomLabel(code);
    final theme = Theme.of(context);
    return Semantics(
      label: '${SymptomPickerStrings.removeSymptomSemanticPrefix}: $label',
      button: true,
      child: Container(
        decoration: BoxDecoration(
          color: isAi
              ? AppColors.aiSurfaceStart
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isAi ? AppColors.aiBorder : AppColors.border,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAi) ...[
              const Icon(
                Icons.auto_awesome,
                size: 12,
                color: AppColors.aiPurple,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              key: const Key('triage_symptom_chip_remove'),
              borderRadius: BorderRadius.circular(20),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet picker for symptoms the AI Scribe did not detect.
///
/// Multi-select: tapping a tile adds it to the visit immediately, the tile is
/// removed from the sheet (since selected codes are filtered out), and the
/// sheet stays open until the SK taps Done. Rebuild is driven by listening to
/// the [TriageViewModel] so the available list updates as taps land.
class _AddSymptomSheet extends StatelessWidget {
  const _AddSymptomSheet({required this.vm});

  final TriageViewModel vm;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        final selected = vm.selectedSymptoms;
        final applicableCodes = vm.applicableVocabCodes;
        final applicableCodesSet = applicableCodes.toSet();
        final addedCount = selected
            .where(applicableCodesSet.contains)
            .length;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  SymptomPickerStrings.addSymptomSheetTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  SymptomPickerStrings.addSymptomSheetSubtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: applicableCodes.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              SymptomPickerStrings.addSymptomSheetEmpty,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: applicableCodes
                                .map(
                                  (code) => _AddSymptomTile(
                                    code: code,
                                    isSelected: selected.contains(code),
                                    isAi: vm.isScribePreTick(code),
                                    onTap: () {
                                      if (selected.contains(code)) {
                                        vm.removeSymptom(code);
                                      } else {
                                        vm.addSymptom(code);
                                      }
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        SymptomPickerStrings.addSymptomSheetCounter(addedCount),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FilledButton(
                      key: const Key('triage_add_symptom_done'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        SymptomPickerStrings.addSymptomSheetDone,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddSymptomTile extends StatelessWidget {
  const _AddSymptomTile({
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
    final Color bg;
    final Color border;
    final Color fg;
    if (isSelected) {
      bg = isAi ? AppColors.aiSurfaceStart : AppColors.navy;
      border = isAi ? AppColors.aiBorder : AppColors.navy;
      fg = isAi ? AppColors.aiPurple : Colors.white;
    } else {
      bg = Colors.white;
      border = AppColors.border;
      fg = AppColors.navy;
    }

    final IconData leadingIcon = isSelected
        ? Icons.check_circle_rounded
        : Icons.add_rounded;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const Key('triage_add_symptom_option'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(leadingIcon, size: 14, color: fg),
              const SizedBox(width: 4),
              Text(
                TriageStrings.symptomLabel(code),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (isAi && isSelected) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.aiPurple,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '✦ AI',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
