import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/programme.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../pathway/ai_pathway_client.dart';
import '../pathway/pathway_engine.dart';
import 'ai_scribe_triage_vocab.dart';
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
  }) : _patientContext = patientContext,
       _aiClient = aiPathwayClient,
       _memberId = memberId {
    // Step 1 is AI-driven: the symptom list starts empty and is populated by
    // the AI Scribe response. SK reviews / edits from there. Patient-context
    // pathway pre-activation still runs via [_updateActivatedPathways].
    _updateActivatedPathways();
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
  Set<String> get scribePreTickedSymptoms => Set.unmodifiable(_scribePreTicked);

  /// Free-text symptom description entered manually by the SK.
  String? _customSymptomText;
  String? get customSymptomText => _customSymptomText;

  void setCustomSymptomText(String? text) {
    _customSymptomText = text?.trim().isEmpty == true ? null : text?.trim();
    notifyListeners();
  }

  /// Chips added from the symptom-search "no match → add to other" flow.
  final List<String> _otherChips = [];
  List<String> get otherChips => List.unmodifiable(_otherChips);

  void addOtherChip(String text) {
    final t = text.trim();
    if (t.isEmpty || _otherChips.contains(t)) return;
    _otherChips.add(t);
    notifyListeners();
  }

  void removeOtherChip(String text) {
    if (_otherChips.remove(text)) notifyListeners();
  }

  /// Chips joined with typed free-text — sent as `otherSymptoms` downstream.
  String? get combinedCustomText {
    final chips = _otherChips.join(', ');
    final typed = _customSymptomText ?? '';
    if (chips.isEmpty && typed.isEmpty) return null;
    if (chips.isEmpty) return typed;
    if (typed.isEmpty) return chips;
    return '$chips, $typed';
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
  void _fetchAiSuggestionsForeground(AiPathwayClient client, String memberId) {
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

  /// Add a symptom by code (used by the "Add symptom" sheet).
  ///
  /// Idempotent: a code already in the set stays in the set.
  void addSymptom(String code) {
    if (_selectedSymptoms.add(code)) {
      _updateActivatedPathways();
      notifyListeners();
    }
  }

  /// Remove a symptom by code (used by the chip × affordance).
  void removeSymptom(String code) {
    if (_selectedSymptoms.remove(code)) {
      _preTicked.remove(code);
      _scribePreTicked.remove(code);
      _updateActivatedPathways();
      notifyListeners();
    }
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
    debugPrint(
      '[Triage] Pathways updated: ${_activatedPathways.map((p) => p.programme.name).toList()}',
    );
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
    if (_patientContext.hasKnownHypertension ||
        _patientContext.hasKnownDiabetes) {
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
  /// meets [AppConfig.scribeSymptomConfidenceFloor] AND whose code is part of
  /// the constrained [AiScribeTriageVocab.codes] list, the code is added to
  /// the selected set and marked as a scribe pre-tick. This is a no-op when
  /// [AppConfig.scribeEnabled] is false. The picker UI renders chips for every
  /// code that survives this filter, regardless of whether it has a
  /// [UnifiedSymptomCatalog] entry — the vocab is the source of truth for
  /// Step 1.
  void applyScribeTriageResult(TriageExtractionResult result) {
    if (!AppConfig.scribeEnabled) return;

    final floor = AppConfig.scribeSymptomConfidenceFloor;
    final validCodes = AiScribeTriageVocab
        .applicableCodes(_patientContext)
        .toSet();

    var appliedCount = 0;
    var demographicSkipped = 0;
    for (final extracted in result.symptomCodes) {
      if (extracted.confidence < floor) {
        debugPrint(
          '[AIScribe] pre-tick skip ${extracted.fieldId}: '
          'confidence=${extracted.confidence} < floor=$floor',
        );
        continue;
      }
      if (!AiScribeTriageVocab.codes.contains(extracted.fieldId)) {
        debugPrint(
          '[AIScribe] pre-tick skip ${extracted.fieldId}: not in vocab',
        );
        continue;
      }
      if (!validCodes.contains(extracted.fieldId)) {
        demographicSkipped++;
        debugPrint(
          '[AIScribe] pre-tick skip ${extracted.fieldId}: demographic filter',
        );
        continue;
      }
      _scribePreTicked.add(extracted.fieldId);
      _addPreTick(extracted.fieldId);
      appliedCount++;
      debugPrint(
        '[AIScribe] pre-tick applied ${extracted.fieldId} '
        '(confidence=${(extracted.confidence * 100).toStringAsFixed(0)}%)',
      );
    }
    debugPrint(
      '[Triage] Scribe applied $appliedCount pre-ticks; '
      'dropped $demographicSkipped demographic-ineligible codes',
    );
    _updateActivatedPathways();
    notifyListeners();
  }

  /// Vocab codes applicable to the current patient. The picker sheet uses
  /// this so the SK only sees demographic-relevant options.
  List<String> get applicableVocabCodes =>
      AiScribeTriageVocab.applicableCodes(_patientContext);

  /// Subset of vocab codes that are directly relevant to this patient's active
  /// clinical context (their "workflow" symptoms).
  ///
  /// Shown as the default chip grid on Step 1 without requiring a search.
  /// Symptoms outside this set are surfaced when the SK types 3+ characters.
  ///
  /// Unlike [applicableVocabCodes], this getter does NOT apply strict age-gates.
  /// This matters when a patient's DOB/age is absent from the local DB (ageMonths
  /// defaults to 0), which would otherwise hide NCD or maternal codes for enrolled
  /// patients.  The secondary search pool ([applicableVocabCodes]) still applies
  /// strict demographic gates so cross-programme "explore" symbols remain
  /// demographically scoped.
  List<String> get primaryVocabCodes {
    final ctx = _patientContext;

    // Maternal context: pregnant, postpartum, enrolled in ANC/PNC, OR a
    // female patient in the 14–44 reproductive age window (she may be
    // pregnant even if not yet confirmed or enrolled).
    // PNC patients (post-delivery) may have isPostpartum = false when the
    // delivery date is unknown, so fall back to programme membership.
    final isMaternalContext = ctx.isPregnant ||
        ctx.isPostpartum ||
        ctx.activeProgrammes.any(
          (p) => p == Programme.anc || p == Programme.pnc,
        ) ||
        (ctx.sex == Sex.female &&
            ctx.ageMonths >= AiScribeTriageVocab.maternalMinAgeMonths &&
            ctx.ageMonths <= AiScribeTriageVocab.maternalMaxAgeMonths);

    final isNcdContext = ctx.hasKnownHypertension ||
        ctx.hasKnownDiabetes ||
        ctx.activeProgrammes.any(
          (p) => p == Programme.ncd,
        );

    final isPediatricContext = ctx.isUnder5;

    // Sex gate: maternal symptoms are never appropriate for male patients
    // regardless of programme (data entry error guard).
    final isMale = ctx.sex == Sex.male;

    // Iterate ALL vocab codes, not just demographically-applicable ones,
    // so programme-enrolled patients always see their workflow symptoms even
    // when age data is missing from the local DB.
    return AiScribeTriageVocab.codes.where((code) {
      switch (AiScribeTriageVocab.categoryOf(code)) {
        case SymptomCategory.general:
          return true;
        case SymptomCategory.maternal:
          return !isMale && isMaternalContext;
        case SymptomCategory.ncd:
          return isNcdContext;
        case SymptomCategory.pediatric:
          return isPediatricContext;
      }
    }).toList();
  }

  /// Set of symptom codes that were pre-selected by the AI scribe.
  ///
  /// Exposed so Step 2 can colour AI-sourced chips differently from
  /// manually-selected ones.
  Set<String> get scribePreTickedCodes => Set.unmodifiable(_scribePreTicked);

  /// Get the patient context.
  PatientContext get patientContext => _patientContext;
}
