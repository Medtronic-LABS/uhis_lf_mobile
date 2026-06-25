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
import '../../scribe/scribe_controller.dart';
import '../../scribe/scribe_session.dart';
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
    this.origin,
  });

  final String encounterId;
  final String patientId;
  final String? memberId;
  final String? householdId;
  final int? patientAge;
  final String? origin;

  @override
  State<SymptomPickerScreen> createState() => _SymptomPickerScreenState();
}

class _SymptomPickerScreenState extends State<SymptomPickerScreen> {
  TriageViewModel? _viewModel;
  PatientContext? _patientContext;
  bool _isLoading = true;
  String? _error;

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

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  void _onContinue() {
    final vm = _viewModel;
    if (vm == null || _patientContext == null) return;

    debugPrint('[SymptomPicker] Continue tapped — ${vm.activatedPathways.length} pathways: ${vm.activatedPathways.map((p) => p.programme.name).join(', ')}');

    if (vm.activatedPathways.isEmpty) {
      // No pathways — go straight to form (routine visit).
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
        body: const Center(child: CircularProgressIndicator()),
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

    return ChangeNotifierProvider<TriageViewModel>.value(
      value: _viewModel!,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: VisitStepHeader(
          step: VisitStep.symptomPicker,
          patientLabel: TriageStrings.pickerTitle,
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

                // Gap 1 — Before you knock · AI brief (collapsible)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _BeforeYouKnockCard(
                      patientContext: _patientContext!,
                    ),
                  ),
                ),

                // Gap 2 — SK asks the family opener card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: const _SkAsksCard(),
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

// ── Gap 1: Before you knock · AI brief card ───────────────────────────────────

/// Collapsible card showing contextual patient brief derived from
/// [PatientContext]. Starts collapsed; tapping the header toggles expansion.
class _BeforeYouKnockCard extends StatefulWidget {
  const _BeforeYouKnockCard({required this.patientContext});

  final PatientContext patientContext;

  @override
  State<_BeforeYouKnockCard> createState() => _BeforeYouKnockCardState();
}

class _BeforeYouKnockCardState extends State<_BeforeYouKnockCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.patientContext;

    // Build chips from patient context flags
    final chips = <_ContextChip>[];
    if (ctx.isPregnant) {
      chips.add(_ContextChip(
        label: SymptomPickerStrings.chipPregnant,
        color: AppColors.statusWarning,
        textColor: Colors.white,
      ));
    }
    if (ctx.hasKnownHypertension) {
      chips.add(_ContextChip(
        label: SymptomPickerStrings.chipHtn,
        color: AppColors.statusCritical,
        textColor: Colors.white,
      ));
    }
    if (ctx.hasKnownDiabetes) {
      chips.add(_ContextChip(
        label: SymptomPickerStrings.chipDm,
        color: AppColors.statusInfo,
        textColor: Colors.white,
      ));
    }
    if (ctx.isTbScreenDue) {
      chips.add(_ContextChip(
        label: SymptomPickerStrings.chipTbDue,
        color: AppColors.statusSuccess,
        textColor: Colors.white,
      ));
    }
    if (ctx.isUnder5) {
      chips.add(_ContextChip(
        label: SymptomPickerStrings.chipUnder5,
        color: AppColors.statusInfo,
        textColor: Colors.white,
      ));
    }
    if (chips.isEmpty) {
      chips.add(_ContextChip(
        label: SymptomPickerStrings.chipRoutine,
        color: AppColors.textMuted,
        textColor: Colors.white,
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — always visible
          Semantics(
            label: _expanded ? 'Collapse patient brief' : 'Expand patient brief',
            button: true,
            child: InkWell(
            key: const Key('triage_body_system_expand_tap'),
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  // Navy rounded icon box
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      SymptomPickerStrings.briefCardTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          ),

          // Expanded content — chips
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: chips
                    .map((c) => _ContextChipWidget(chip: c))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Data holder for a patient-context chip.
class _ContextChip {
  const _ContextChip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;
}

/// Renders a single patient-context chip.
class _ContextChipWidget extends StatelessWidget {
  const _ContextChipWidget({required this.chip});

  final _ContextChip chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chip.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        chip.label,
        style: TextStyle(
          color: chip.textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Gap 2: SK asks the family opener card ─────────────────────────────────────

/// Always-visible gradient card with the SK opener phrase.
class _SkAsksCard extends StatelessWidget {
  const _SkAsksCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.tagBlueSurface, AppColors.tagBlueSurface],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.tagBlueSurface),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SymptomPickerStrings.skAsksLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.tagBlueText,
              letterSpacing: 0.06,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            SymptomPickerStrings.skOpenerPhrase,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.tagBlueText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            SymptomPickerStrings.skOpenerPhraseBn,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
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
