import 'package:flutter/foundation.dart';

import '../../../core/models/programme.dart';
import '../pathway/pathway_engine.dart';
import 'patient_context_builder.dart';
import 'unified_symptom_catalog.dart';

/// ViewModel for the symptom picker screen.
///
/// Manages selected symptoms, patient context pre-ticks, and
/// pathway activation preview.
class TriageViewModel extends ChangeNotifier {
  TriageViewModel({
    required PatientContext patientContext,
  }) : _patientContext = patientContext {
    _initPreTicks();
  }

  final PatientContext _patientContext;

  /// Currently selected symptom codes.
  final Set<String> _selectedSymptoms = {};
  Set<String> get selectedSymptoms => Set.unmodifiable(_selectedSymptoms);

  /// Pre-ticked symptoms from patient context (removable hints).
  final Set<String> _preTicked = {};
  Set<String> get preTickedSymptoms => Set.unmodifiable(_preTicked);

  /// Activated pathways based on current selection.
  List<ActivatedPathway> _activatedPathways = [];
  List<ActivatedPathway> get activatedPathways =>
      List.unmodifiable(_activatedPathways);

  /// Whether any danger sign is selected.
  bool get hasDangerSign {
    final dangerCodes = UnifiedSymptomCatalog.dangerSigns.map((s) => s.code);
    return _selectedSymptoms.any((s) => dangerCodes.contains(s));
  }

  /// Whether no symptoms are selected (routine visit).
  bool get isRoutineVisit => _selectedSymptoms.isEmpty;

  /// Initialize pre-ticks based on patient context.
  void _initPreTicks() {
    // Pre-tick based on known conditions
    if (_patientContext.hasKnownHypertension) {
      _addPreTick('high_bp_known');
    }
    if (_patientContext.hasKnownDiabetes) {
      _addPreTick('polyuria');
      _addPreTick('polydipsia');
    }

    // Pre-tick pregnancy if enrolled
    if (_patientContext.isPregnant) {
      _addPreTick('pregnant');
    }

    // Pre-tick TB indicators if screen due
    if (_patientContext.isTbScreenDue) {
      // Pre-expand TB cluster but don't pre-tick symptoms
    }

    // Pre-tick based on active programmes
    for (final prog in _patientContext.activeProgrammes) {
      switch (prog) {
        case Programme.anc:
          _addPreTick('pregnant');
          break;
        case Programme.ncd:
          if (_patientContext.hasKnownHypertension) {
            _addPreTick('high_bp_known');
          }
          break;
        case Programme.tb:
          // Don't pre-tick TB symptoms, just highlight the cluster
          break;
        default:
          break;
      }
    }

    // Update pathways after pre-ticks
    _updateActivatedPathways();
  }

  void _addPreTick(String code) {
    _preTicked.add(code);
    _selectedSymptoms.add(code);
  }

  /// Toggle a symptom selection.
  void toggleSymptom(String code) {
    if (_selectedSymptoms.contains(code)) {
      _selectedSymptoms.remove(code);
    } else {
      _selectedSymptoms.add(code);
    }
    _updateActivatedPathways();
    notifyListeners();
  }

  /// Select multiple symptoms at once.
  void selectSymptoms(Set<String> codes) {
    _selectedSymptoms.addAll(codes);
    _updateActivatedPathways();
    notifyListeners();
  }

  /// Clear all selections.
  void clearAll() {
    _selectedSymptoms.clear();
    _activatedPathways = [];
    notifyListeners();
  }

  /// Clear all and mark as routine visit.
  void setRoutineVisit() {
    clearAll();
    // Pathways will be activated from history triggers only
    _updateActivatedPathways();
    notifyListeners();
  }

  void _updateActivatedPathways() {
    _activatedPathways = PathwayEngine.activate(
      _selectedSymptoms,
      _patientContext,
    );
  }

  /// Get symptoms grouped by cluster for display.
  Map<SymptomCluster, List<UnifiedSymptomDef>> get symptomsByCluster {
    final result = <SymptomCluster, List<UnifiedSymptomDef>>{};

    // Get all clusters in order
    for (final cluster in SymptomCluster.values) {
      final symptoms = UnifiedSymptomCatalog.byCluster(cluster);
      if (symptoms.isNotEmpty) {
        result[cluster] = symptoms;
      }
    }

    return result;
  }

  /// Get clusters that should be pre-expanded based on patient context.
  Set<SymptomCluster> get preExpandedClusters {
    final expanded = <SymptomCluster>{
      // Danger signs always expanded
      SymptomCluster.dangerSigns,
    };

    // Expand maternal if pregnant
    if (_patientContext.isPregnant || _patientContext.isPostpartum) {
      expanded.add(SymptomCluster.maternal);
    }

    // Expand NCD if known conditions
    if (_patientContext.hasKnownHypertension || _patientContext.hasKnownDiabetes) {
      expanded.add(SymptomCluster.ncdMetabolic);
    }

    // Expand TB if screen due or prior TB
    if (_patientContext.isTbScreenDue || _patientContext.hasPriorTb) {
      expanded.add(SymptomCluster.tbIndicators);
    }

    // Expand child health for children
    if (_patientContext.isUnder5) {
      expanded.add(SymptomCluster.childHealth);
      expanded.add(SymptomCluster.feverRespiratory);
      expanded.add(SymptomCluster.giNutrition);
    }

    return expanded;
  }

  /// Whether a symptom is selected.
  bool isSelected(String code) => _selectedSymptoms.contains(code);

  /// Whether a symptom was pre-ticked from patient context.
  bool isPreTicked(String code) => _preTicked.contains(code);

  /// Get the patient context.
  PatientContext get patientContext => _patientContext;
}
