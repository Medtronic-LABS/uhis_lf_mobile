import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/db/encounter_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/db/patient_programmes_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../pathway/pathway_engine.dart';
import '../pathway/pathway_review_sheet.dart';
import 'patient_context_builder.dart';
import 'triage_view_model.dart';
import 'unified_symptom_catalog.dart';

/// Symptom picker screen for the triage step.
///
/// This is a routed screen that:
/// 1. Builds PatientContext from local DB
/// 2. Shows symptom picker
/// 3. Shows PathwayReviewSheet on continue
/// 4. Navigates to visit form with activated pathways
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

  /// Track expanded clusters.
  final Set<SymptomCluster> _expandedClusters = {};

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
        _expandedClusters.addAll(_viewModel!.preExpandedClusters);
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

    // Show pathway review sheet
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => PathwayReviewSheet(
        patientName: '', // We don't have the name here, but it's for display
        activatedPathways: vm.activatedPathways,
        selectedSymptoms: vm.selectedSymptoms,
        onConfirm: (pathways, skipped) {
          Navigator.of(sheetContext).pop();
          _navigateToForm(pathways);
        },
        onSkip: (pathway) {
          // Skip handling is done internally by the sheet
        },
      ),
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
                  child: const Text('Retry'),
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
        appBar: AppBar(
          title: Text(TriageStrings.pickerTitle),
        ),
        body: Consumer<TriageViewModel>(
          builder: (context, vm, _) {
            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        TriageStrings.pickerSubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // Symptom clusters
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: vm.symptomsByCluster.length,
                    itemBuilder: (context, index) {
                      final cluster = vm.symptomsByCluster.keys.elementAt(index);
                      final symptoms = vm.symptomsByCluster[cluster]!;
                      final isExpanded = _expandedClusters.contains(cluster);
                      final isDangerSigns = cluster == SymptomCluster.dangerSigns;

                      return _buildClusterSection(
                        context,
                        cluster: cluster,
                        symptoms: symptoms,
                        isExpanded: isExpanded,
                        isDangerSigns: isDangerSigns,
                        vm: vm,
                      );
                    },
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(TriageStrings.continueButton),
                            if (vm.activatedPathways.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.onPrimary
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${vm.activatedPathways.length}',
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimary,
                                  ),
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
    required bool isExpanded,
    required bool isDangerSigns,
    required TriageViewModel vm,
  }) {
    final theme = Theme.of(context);

    // Count selected symptoms in this cluster
    final selectedCount = symptoms.where((s) => vm.isSelected(s.code)).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDangerSigns
          ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
          : null,
      child: Column(
        children: [
          // Cluster header
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedClusters.remove(cluster);
                } else {
                  _expandedClusters.add(cluster);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (isDangerSigns)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.warning_rounded,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _clusterLabel(cluster),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isDangerSigns
                            ? theme.colorScheme.error
                            : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selectedCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Icon(
                    isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Symptom tiles
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: symptoms.map((symptom) {
                  return _buildSymptomTile(
                    context,
                    symptom: symptom,
                    isSelected: vm.isSelected(symptom.code),
                    isPreTicked: vm.isPreTicked(symptom.code),
                    onTap: () => vm.toggleSymptom(symptom.code),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSymptomTile(
    BuildContext context, {
    required UnifiedSymptomDef symptom,
    required bool isSelected,
    required bool isPreTicked,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDanger = symptom.isDangerSign;

    Color getBackgroundColor() {
      if (isSelected) {
        if (isDanger) {
          return theme.colorScheme.error;
        }
        return theme.colorScheme.primary;
      }
      return theme.colorScheme.surfaceContainerHighest;
    }

    Color getForegroundColor() {
      if (isSelected) {
        if (isDanger) {
          return theme.colorScheme.onError;
        }
        return theme.colorScheme.onPrimary;
      }
      if (isDanger) {
        return theme.colorScheme.error;
      }
      return theme.colorScheme.onSurface;
    }

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (symptom.icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                _getIconData(symptom.icon!),
                size: 16,
                color: getForegroundColor(),
              ),
            ),
          Flexible(
            child: Text(
              TriageStrings.symptomLabel(symptom.code),
              style: TextStyle(
                color: getForegroundColor(),
              ),
            ),
          ),
          if (isPreTicked && isSelected)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.auto_awesome,
                size: 14,
                color: getForegroundColor().withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      backgroundColor: getBackgroundColor(),
      selectedColor: getBackgroundColor(),
      showCheckmark: false,
      side: isDanger && !isSelected
          ? BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5))
          : BorderSide.none,
    );
  }

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
