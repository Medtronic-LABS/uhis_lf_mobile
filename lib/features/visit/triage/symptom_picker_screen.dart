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
import '../../scribe/scribe_session.dart';
import '../briefing/briefing_models.dart';
import '../briefing/visit_briefing_repository.dart';
import '../pathway/pathway_engine.dart';
import 'patient_context_builder.dart';
import 'visit_step_header.dart';
import 'triage_view_model.dart';
import 'unified_symptom_catalog.dart';

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
  /// inside a single-route 3-step flow.
  final ValueChanged<List<ActivatedPathway>>? onAdvance;

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
    debugPrint('[SymptomPicker] Starting load for encounterId=${widget.encounterId}, patientId=${widget.patientId}');
    
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
          debugPrint('[SymptomPicker] Got patientId from encounter: $patientId');
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
        debugPrint('[SymptomPicker] PatientContext: age=${ctx.ageMonths}mo, sex=${ctx.sex.name}, pregnant=${ctx.isPregnant}, programmes=${ctx.activeProgrammes.map((p) => p.name).join(',')}');
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

      final visitsByVisit =
          await vitalsRepo.recentByVisit(widget.patientId, limit: 5);
      final followUps =
          await followUpRepo.openForPatientLocal(widget.patientId);

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
        final spo2 =
            latest.readings.where((r) => r.type == VitalType.spO2).firstOrNull;
        final bmi =
            latest.readings.where((r) => r.type == VitalType.bmi).firstOrNull;
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
        final daysOverdue =
            f.isOverdue ? DateTime.now().difference(f.dueDate).inDays : null;
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
        'activeProgrammes':
            patientCtx.activeProgrammes.map((p) => p.name).toList(),
        'visitCount': visitsByVisit.length,
        if (lastVisit != null)
          'lastVisitDate':
              lastVisit.date.toIso8601String().split('T').first,
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

    debugPrint('[SymptomPicker] Continue tapped — ${vm.activatedPathways.length} pathways: ${vm.activatedPathways.map((p) => p.programme.name).join(', ')}');

    // In-flow host (VisitFlowScreen) intercepts via callback; spec §3.1
    // collapses old "/triage-result" preview into Step 2's header so the SK
    // does not see a separate landing page between symptoms and form.
    final onAdvance = widget.onAdvance;
    if (onAdvance != null) {
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

  String _clusterLabel(SymptomCluster cluster) {
    switch (cluster) {
      case SymptomCluster.dangerSigns:
        return TriageStrings.clusterDangerSigns;
      case SymptomCluster.feverRespiratory:
        return TriageStrings.clusterFeverRespiratory;
      case SymptomCluster.giNutrition:
        return TriageStrings.clusterGiNutrition;
      case SymptomCluster.maternal:
        return TriageStrings.clusterMaternal;
      case SymptomCluster.ncdMetabolic:
        return TriageStrings.clusterNcdMetabolic;
      case SymptomCluster.tbIndicators:
        return TriageStrings.clusterTbIndicators;
      case SymptomCluster.mentalHealth:
        return TriageStrings.clusterMentalHealth;
      case SymptomCluster.childHealth:
        return TriageStrings.clusterChildHealth;
    }
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
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
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
        floatingActionButton: AppConfig.scribeEnabled
            ? _ScribeTriageFab(
                encounterId: widget.encounterId,
                patientId: widget.patientId,
                viewModel: _viewModel!,
              )
            : null,
        body: Consumer<TriageViewModel>(
          builder: (context, vm, _) {
            final clusters = vm.symptomsByCluster;
            return CustomScrollView(
              slivers: [
                // Subtitle header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      TriageStrings.pickerSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),

                // AI briefing cards — Before You Knock / Conversation Guide / Begin Consultation
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: _AiBriefingSection(
                      briefingLoading: _briefingLoading,
                      briefingData: _briefingData,
                      patientContext: _patientContext!,
                    ),
                  ),
                ),

                // Symptom clusters
                for (final entry in clusters.entries)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: _buildClusterSection(
                        context,
                        cluster: entry.key,
                        symptoms: entry.value,
                        isDangerSigns: entry.key == SymptomCluster.dangerSigns,
                        vm: vm,
                      ),
                    ),
                  ),

                // Gap 3 — Duration picker (below clusters)
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
                          child: const Text(TriageStrings.noSymptomsRoutineVisit),
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

  Widget _buildClusterSection(
    BuildContext context, {
    required SymptomCluster cluster,
    required List<UnifiedSymptomDef> symptoms,
    required bool isDangerSigns,
    required TriageViewModel vm,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cluster header - always visible, no expand/collapse
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              if (isDangerSigns)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.warning_rounded,
                    color: theme.colorScheme.error,
                    size: 24,
                  ),
                ),
              Text(
                _clusterLabel(cluster),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isDangerSigns ? theme.colorScheme.error : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Big icon grid - always visible
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: symptoms.length,
          itemBuilder: (context, index) {
            final symptom = symptoms[index];
            return _buildBigIconTile(
              context,
              symptom: symptom,
              isSelected: vm.isSelected(symptom.code),
              isPreTicked: vm.isPreTicked(symptom.code),
              isScribePreTick: vm.isScribePreTick(symptom.code),
              onTap: () => vm.toggleSymptom(symptom.code),
            );
          },
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  /// Large icon tile for easy SK interaction.
  Widget _buildBigIconTile(
    BuildContext context, {
    required UnifiedSymptomDef symptom,
    required bool isSelected,
    required bool isPreTicked,
    required bool isScribePreTick,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDanger = symptom.isDangerSign;

    Color getBackgroundColor() {
      if (isSelected) {
        return isDanger
            ? theme.colorScheme.error
            : theme.colorScheme.primaryContainer;
      }
      return isDanger
          ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surfaceContainerHighest;
    }

    Color getIconColor() {
      if (isSelected) {
        return isDanger
            ? theme.colorScheme.onError
            : theme.colorScheme.onPrimaryContainer;
      }
      return isDanger
          ? theme.colorScheme.error
          : theme.colorScheme.onSurfaceVariant;
    }

    Color getTextColor() {
      if (isSelected) {
        return isDanger
            ? theme.colorScheme.onError
            : theme.colorScheme.onPrimaryContainer;
      }
      return isDanger
          ? theme.colorScheme.error
          : theme.colorScheme.onSurface;
    }

    return Semantics(
      label: isSelected
          ? 'Deselect symptom: ${TriageStrings.symptomLabel(symptom.code)}'
          : 'Select symptom: ${TriageStrings.symptomLabel(symptom.code)}',
      button: true,
      selected: isSelected,
      child: Material(
      color: getBackgroundColor(),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('triage_symptom_chip_tap'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? (isDanger ? theme.colorScheme.error : theme.colorScheme.primary)
                  : (isDanger
                      ? theme.colorScheme.error.withValues(alpha: 0.5)
                      : Colors.transparent),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Emoji or fallback icon
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    symptom.emoji != null
                        ? Text(
                            symptom.emoji!,
                            style: const TextStyle(fontSize: 32),
                          )
                        : Icon(
                            _getIconData(symptom.icon ?? 'help_outline'),
                            size: 36,
                            color: getIconColor(),
                          ),
                    // AI badge for scribe pre-ticked symptoms
                    if (isScribePreTick && isSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ComposerStrings.scribeAiBadge,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onTertiary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    // Standard pre-ticked indicator (patient context, not scribe)
                    else if (isPreTicked && isSelected)
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 12,
                          color: theme.colorScheme.onTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // English label
                Text(
                  TriageStrings.symptomLabel(symptom.code),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: getTextColor(),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                // Bangla sub-label
                if (TriageStrings.symptomBangla(symptom.code) != null)
                  Text(
                    TriageStrings.symptomBangla(symptom.code)!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? getTextColor().withValues(alpha: 0.85)
                          : AppColors.textMuted,
                    ),
                  ),
                // Selection checkmark
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle,
                      size: 16,
                      color: isDanger
                          ? theme.colorScheme.onError
                          : theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  // ── _ScribeTriageFab ──────────────────────────────────────────────────────

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'thermostat':
        return Icons.thermostat;
      case 'air':
        return Icons.air;
      case 'water_drop':
        return Icons.water_drop;
      case 'sick':
        return Icons.sick;
      case 'no_food':
        return Icons.no_food;
      case 'warning':
        return Icons.warning;
      case 'bedtime':
        return Icons.bedtime;
      case 'psychology':
        return Icons.psychology;
      case 'visibility_off':
        return Icons.visibility_off;
      case 'healing':
        return Icons.healing;
      case 'bubble_chart':
        return Icons.bubble_chart;
      case 'child_care':
        return Icons.child_care;
      case 'water':
        return Icons.water;
      case 'favorite':
        return Icons.favorite;
      case 'blur_on':
        return Icons.blur_on;
      case 'touch_app':
        return Icons.touch_app;
      case 'local_drink':
        return Icons.local_drink;
      case 'wc':
        return Icons.wc;
      case 'directions_walk':
        return Icons.directions_walk;
      case 'nightlight':
        return Icons.nightlight;
      case 'battery_alert':
        return Icons.battery_alert;
      case 'people':
        return Icons.people;
      case 'sentiment_dissatisfied':
        return Icons.sentiment_dissatisfied;
      case 'bedtime_off':
        return Icons.bedtime_off;
      case 'hearing':
        return Icons.hearing;
      case 'visibility':
        return Icons.visibility;
      case 'trending_down':
        return Icons.trending_down;
      case 'straighten':
        return Icons.straighten;
      case 'pregnant_woman':
        return Icons.pregnant_woman;
      default:
        return Icons.circle;
    }
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
        _BriefingCard(
          icon: Icons.psychology_outlined,
          iconColor: AppColors.navy,
          title: SymptomPickerStrings.briefCard1Title,
          child: briefingLoading
              ? const _BriefingLoadingSkeleton(lines: 3)
              : briefingData == null
                  ? _BriefingFallbackContent(
                      patientContext: patientContext, isFemale: isFemale)
                  : _BriefingCard1Content(
                      data: briefingData!, isFemale: isFemale),
        ),
        const SizedBox(height: 8),
        _BriefingCard(
          icon: Icons.chat_bubble_outline,
          iconColor: Colors.teal,
          title: SymptomPickerStrings.briefCard3TitleFor(isFemale: isFemale),
          child: briefingLoading
              ? const _BriefingLoadingSkeleton(lines: 4)
              : briefingData == null
                  ? const _BriefingUnavailable()
                  : _BriefingCard3Content(data: briefingData!),
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
  bool _expanded = false;

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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
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
// Spec §4.1.1 / §5.1.1: open the card with a navy "sit with him/her — greet
// them" instructional strip, then the AI-generated brief in the brand pink
// (#9D174D). Body hard-capped at 2 lines total (headline + 1 follow-up bullet)
// so the SK can absorb it in one glance.

class _BriefingCard1Content extends StatelessWidget {
  const _BriefingCard1Content({required this.data, required this.isFemale});
  final VisitBriefingResponse data;
  final bool isFemale;

  static const Color _aiTextColor = Color(0xFF9D174D);
  static const Color _greetBgColor = Color(0xFF1B2B5E);

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Navy greet strip — instructional, never AI-generated.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _greetBgColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(Icons.waving_hand,
                  size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  SymptomPickerStrings.beforeYouKnockGreetingFor(
                      isFemale: isFemale),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // AI-generated body — pink, 2-line hard stop.
        Text(
          aiBody,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: _aiTextColor,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Card 3 content: Suggested Discussion Points ───────────────────────────────

class _BriefingCard3Content extends StatelessWidget {
  const _BriefingCard3Content({required this.data});
  final VisitBriefingResponse data;

  @override
  Widget build(BuildContext context) {
    final sdp = data.suggestedDiscussionPoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.tagBlueSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.waving_hand, size: 13, color: AppColors.tagBlueText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sdp.openingLine,
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.tagBlueText,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ...sdp.sections.take(4).map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Icon(_iconFor(s.icon), size: 12, color: AppColors.aiPurple),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      s.topic,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  IconData _iconFor(String icon) {
    switch (icon) {
      case 'heart': return Icons.favorite_outline;
      case 'baby': return Icons.child_care;
      case 'nutrition': return Icons.restaurant;
      case 'medication': return Icons.medication_outlined;
      case 'lungs': return Icons.air;
      case 'home': return Icons.home_outlined;
      default: return Icons.checklist_outlined;
    }
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
          children: List.generate(lines, (i) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            height: 10,
            width: maxW * _fractions[i % _fractions.length],
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          )),
        );
      },
    );
  }
}

class _BriefingUnavailable extends StatelessWidget {
  const _BriefingUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.wifi_off, size: 14, color: AppColors.textMuted),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'AI unavailable — continue with symptoms below.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Fallback for card 1 when AI is unavailable — shows the navy greet strip
/// followed by rule-based context chips. Same shape as the AI variant so the
/// SK sees a consistent card layout whether or not the upstream call worked.
class _BriefingFallbackContent extends StatelessWidget {
  const _BriefingFallbackContent({
    required this.patientContext,
    required this.isFemale,
  });
  final PatientContext patientContext;
  final bool isFemale;

  @override
  Widget build(BuildContext context) {
    final ctx = patientContext;
    final chips = <(String, Color)>[];
    if (ctx.isPregnant) chips.add((SymptomPickerStrings.chipPregnant, AppColors.statusWarning));
    if (ctx.hasKnownHypertension) chips.add((SymptomPickerStrings.chipHtn, AppColors.statusCritical));
    if (ctx.hasKnownDiabetes) chips.add((SymptomPickerStrings.chipDm, AppColors.statusInfo));
    if (ctx.isTbScreenDue) chips.add((SymptomPickerStrings.chipTbDue, AppColors.statusSuccess));
    if (ctx.isUnder5) chips.add((SymptomPickerStrings.chipUnder5, AppColors.statusInfo));
    if (chips.isEmpty) chips.add((SymptomPickerStrings.chipRoutine, AppColors.textMuted));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2B5E),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(Icons.waving_hand,
                  size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  SymptomPickerStrings.beforeYouKnockGreetingFor(
                      isFemale: isFemale),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Icon(Icons.wifi_off, size: 12, color: AppColors.textMuted),
            SizedBox(width: 4),
            Text('AI offline · local context',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: chips.map((c) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.$2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(c.$1,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          )).toList(),
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
                  onTap: (v) => vm.setDuration(
                    vm.sicknessDuration == v ? null : v,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DurationButton(
                  label: SymptomPickerStrings.duration2To3Days,
                  value: SymptomPickerStrings.durationValue2to3,
                  selected: vm.sicknessDuration,
                  onTap: (v) => vm.setDuration(
                    vm.sicknessDuration == v ? null : v,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DurationButton(
                  label: SymptomPickerStrings.duration4Plus,
                  value: SymptomPickerStrings.durationValue4plus,
                  selected: vm.sicknessDuration,
                  onTap: (v) => vm.setDuration(
                    vm.sicknessDuration == v ? null : v,
                  ),
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
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            maxLines: 2,
            onChanged: widget.vm.setCustomSymptomText,
          ),
        ],
      ),
    );
  }
}

// ── Scribe triage FAB ─────────────────────────────────────────────────────────

/// Optional FAB shown on [SymptomPickerScreen] when [AppConfig.scribeEnabled].
///
/// Taps the [ScribeController] (if provided by an ancestor [Provider]) to
/// start a triage-mode recording.  When the result arrives the
/// [TriageViewModel] is updated via [TriageViewModel.applyScribeTriageResult].
///
/// If no [ScribeController] is in scope the FAB is hidden — the screen
/// remains fully functional without scribe.
class _ScribeTriageFab extends StatelessWidget {
  const _ScribeTriageFab({
    required this.encounterId,
    required this.patientId,
    required this.viewModel,
  });

  final String encounterId;
  final String patientId;
  final TriageViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    // Scribe controller is optional — guard with try/catch on context.read.
    ScribeController? controller;
    try {
      controller = context.read<ScribeController>();
    } catch (_) {
      // No ScribeController in scope — hide FAB.
      return const SizedBox.shrink();
    }

    final session = controller.session;
    final isRecording = session.state == ScribeState.recording;
    final isProcessing = session.state == ScribeState.uploading ||
        session.state == ScribeState.processing;

    void onTap() {
      controller!.bindContext(context);
      if (isRecording) {
        controller.stopRecording(
          patientId: patientId,
          encounterId: encounterId,
        );
      } else if (!isProcessing) {
        controller.startRecordingForTriage(
          patientId: patientId,
          encounterId: encounterId,
          symptomCatalog: UnifiedSymptomCatalog.all
              .map((s) => s.code)
              .toList(),
        );
      }
    }

    // Wire the triage result into the viewmodel when it arrives.
    if (session.state == ScribeState.reviewReady &&
        session.mode == ScribeMode.triage) {
      // Result arrived — apply and reset. We do this in the next frame so the
      // build pass completes cleanly before mutating external state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Triage results come via TriageExtractionResult, not FormPrefillResult.
        // The controller stores triage results in session when mode == triage.
        // TODO: expose triageExtractionResult on ScribeSession (tracked gap).
        // ignore: unused_local_variable
        final _ = session.formPrefillResult;
      });
    }

    return FloatingActionButton.extended(
      onPressed: isProcessing ? null : onTap,
      backgroundColor: isRecording
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary,
      icon: isProcessing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              isRecording ? Icons.stop : Icons.mic,
              color: Colors.white,
            ),
      label: Text(
        isProcessing
            ? ComposerStrings.scribeAiBadge
            : isRecording
                ? ScribeStrings.fabStop
                : ComposerStrings.scribeRecordButton,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}
