import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/programme.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../pathway/ai_pathway_client.dart';
import '../pathway/pathway_engine.dart';
import 'patient_context_builder.dart';
import 'unified_symptom_catalog.dart';

/// ViewModel for the symptom picker screen.
///
/// Manages selected symptoms, patient context pre-ticks, and
/// pathway activation preview.
///
/// Phase 4.4: Also wires AI pathway suggestions (fire-and-forget). AI
/// suggestions are merged into [allPathways] but can never remove a
/// rule-activated pathway. The invariant is:
///   allPathways = rule pathways ∪ ai suggestions (deduped by programme,
///   with rule winning on dedup).
class TriageViewModel extends ChangeNotifier {
  TriageViewModel({
    required PatientContext patientContext,
    AiPathwayClient? aiPathwayClient,
    String? memberId,
  })  : _patientContext = patientContext,
        _aiClient = aiPathwayClient,
        _memberId = memberId {
    _initPreTicks();
    _initAiSuggestions();
  }

  final PatientContext _patientContext;
  final AiPathwayClient? _aiClient;
  final String? _memberId;

  /// Currently selected symptom codes.
  final Set<String> _selectedSymptoms = {};
  Set<String> get selectedSymptoms => Set.unmodifiable(_selectedSymptoms);

  /// Pre-ticked symptoms from patient context (removable hints).
  final Set<String> _preTicked = {};
  Set<String> get preTickedSymptoms => Set.unmodifiable(_preTicked);

  /// Codes that were pre-ticked specifically by a scribe triage result.
  ///
  /// Used by the UI to render an "AI" badge on the tile. This is a subset of
  /// [_preTicked] — all scribe pre-ticks are also added to [_preTicked].
  final Set<String> _scribePreTicked = {};
  Set<String> get scribePreTickedSymptoms =>
      Set.unmodifiable(_scribePreTicked);

  /// Free-text symptom description entered manually by the SK.
  String? _customSymptomText;
  String? get customSymptomText => _customSymptomText;

  void setCustomSymptomText(String? text) {
    _customSymptomText = text?.trim().isEmpty == true ? null : text?.trim();
    notifyListeners();
  }

  /// Rule-activated pathways based on current selection.
  List<ActivatedPathway> _activatedPathways = [];

  /// AI-suggested pathways (from fire-and-forget fetch or SQLite cache).
  List<PathwaySuggestion> _aiSuggestions = [];

  /// Whether the last-used AI cache entry is stale (> 24 h old).
  bool _aiCacheIsStale = false;
  bool get aiCacheIsStale => _aiCacheIsStale;

  /// Unified pathway list: rule pathways ∪ AI suggestions.
  ///
  /// Invariant: removing an AI suggestion never removes a rule-activated
  /// pathway. Deduplication: if both rule and AI suggest the same programme,
  /// the rule-activated entry wins (trigger = rule, confidence = 1.0).
  /// AI-only entries appear with trigger = PathwayTrigger.ai.
  List<ActivatedPathway> get allPathways {
    final result = List<ActivatedPathway>.from(_activatedPathways);
    final rulePrograms = _activatedPathways.map((p) => p.programme).toSet();
    for (final suggestion in _aiSuggestions) {
      if (suggestion.programme == Programme.unknown) continue;
      if (!rulePrograms.contains(suggestion.programme)) {
        result.add(suggestion.toActivatedPathway());
      }
    }
    result.sort((a, b) => a.priority.compareTo(b.priority));
    return List.unmodifiable(result);
  }

  /// Activated pathways (rule-only). Kept for backward compatibility.
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

  /// Load cached AI suggestions on init, then fire-and-forget the live fetch.
  ///
  /// Step 1: load stale-or-fresh cache so the UI has something immediately.
  /// Step 2: fire-and-forget a live fetch; when it returns, merge and notify.
  void _initAiSuggestions() {
    final client = _aiClient;
    final memberId = _memberId;
    if (client == null || memberId == null || memberId.isEmpty) return;

    // Load cache synchronously (async task; we don't await the whole method).
    client.getCached(memberId).then((cache) {
      if (cache == null) return;
      if (!disposed) {
        _aiSuggestions = cache.suggestions;
        _aiCacheIsStale = cache.isStale;
        notifyListeners();
        debugPrint(
          '[Triage] Loaded ${_aiSuggestions.length} AI suggestions from cache '
          '(stale=$_aiCacheIsStale)',
        );
      }
    });

    // Fire-and-forget live fetch — do NOT await on the UI thread.
    _fetchAiSuggestionsForeground(client, memberId);
  }

  /// Build a [PathwaySuggestionRequest] from current state and fire the fetch.
  /// When it resolves, merge the result into [_aiSuggestions] and notify.
  void _fetchAiSuggestionsForeground(
    AiPathwayClient client,
    String memberId,
  ) {
    final req = PathwaySuggestionRequest(
      memberId: memberId,
      symptoms: _selectedSymptoms.toList(),
      ageMonths: _patientContext.ageMonths,
      sex: _patientContext.sex.name.toUpperCase(),
      activeConditions: _patientContext.knownConditions.toList(),
      openFlags: _patientContext.openFlags.toList(),
    );

    // Intentionally not awaited — picker must never block on this.
    client.fetchSuggestions(req).then((cache) {
      if (cache == null) return;
      if (!disposed) {
        _aiSuggestions = cache.suggestions;
        _aiCacheIsStale = false;
        notifyListeners();
        debugPrint(
          '[Triage] Merged ${_aiSuggestions.length} live AI suggestions',
        );
      }
    });
  }

  /// Selected sickness duration. One of '1', '2-3', '4+', or null.
  String? _sicknessDuration;
  String? get sicknessDuration => _sicknessDuration;

  /// Set the sickness duration selection and notify listeners.
  void setDuration(String? d) {
    _sicknessDuration = d;
    notifyListeners();
  }

  /// Whether this [ChangeNotifier] has been disposed (guards async callbacks).
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  void _addPreTick(String code) {
    _preTicked.add(code);
    _selectedSymptoms.add(code);
  }

  /// Toggle a symptom selection.
  void toggleSymptom(String code) {
    if (_selectedSymptoms.contains(code)) {
      _selectedSymptoms.remove(code);
      debugPrint('[Triage] Symptom deselected: $code');
    } else {
      _selectedSymptoms.add(code);
      debugPrint('[Triage] Symptom selected: $code');
    }
    _updateActivatedPathways();
    debugPrint('[Triage] Current selection: $_selectedSymptoms');
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
    debugPrint('[Triage] Pathways updated: ${_activatedPathways.map((p) => p.programme.name).toList()}');
  }

  /// Get symptoms grouped by cluster for display.
  ///
  /// Applies demographic filters: female-only symptoms are hidden for male
  /// patients; age-gated symptoms are hidden when the patient exceeds the
  /// maximum age.  Entire clusters with no visible symptoms are omitted.
  Map<SymptomCluster, List<UnifiedSymptomDef>> get symptomsByCluster {
    final isMale = _patientContext.sex == Sex.male;
    final ageMonths = _patientContext.ageMonths;
    final result = <SymptomCluster, List<UnifiedSymptomDef>>{};

    for (final cluster in SymptomCluster.values) {
      final symptoms = UnifiedSymptomCatalog.byCluster(cluster).where((s) {
        if (s.requiresFemale && isMale) return false;
        if (s.maxAgeMonths != null && ageMonths > s.maxAgeMonths!) return false;
        return true;
      }).toList();
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

  /// Whether a symptom was pre-ticked specifically by a scribe result.
  ///
  /// Used by the tile to render an "AI" badge overlay.
  bool isScribePreTick(String code) => _scribePreTicked.contains(code);

  /// Apply a triage extraction result from the AI scribe service.
  ///
  /// For each [AIExtractedField] in [result.symptomCodes] whose confidence
  /// meets [AppConfig.scribeSymptomConfidenceFloor], the code is added to
  /// the selected set and marked as a scribe pre-tick. This is a no-op when
  /// [AppConfig.scribeEnabled] is false.
  void applyScribeTriageResult(TriageExtractionResult result) {
    if (!AppConfig.scribeEnabled) return;

    final floor = AppConfig.scribeSymptomConfidenceFloor;
    for (final extracted in result.symptomCodes) {
      if (extracted.confidence < floor) continue;
      _scribePreTicked.add(extracted.fieldId);
      _addPreTick(extracted.fieldId);
    }
    debugPrint(
      '[Triage] Scribe applied ${_scribePreTicked.length} pre-ticks from result',
    );
    _updateActivatedPathways();
    notifyListeners();
  }

  /// Get the patient context.
  PatientContext get patientContext => _patientContext;
}
